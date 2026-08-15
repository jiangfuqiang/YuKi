#include "YuKiLlamaBridge.h"
#include <llama/llama.h>
#include <TargetConditionals.h>

#include <algorithm>
#include <chrono>
#include <cstdlib>
#include <cstring>
#include <mutex>
#include <string>
#include <thread>
#include <vector>

struct yuki_llama_context {
    llama_model * model = nullptr;
    llama_context * context = nullptr;
    const llama_vocab * vocabulary = nullptr;
    llama_sampler * sampler = nullptr;
    // Tokens guaranteed to occupy the KV cache (the latest prompt). Generated
    // tokens may still sit behind them and are trimmed before the next decode.
    std::vector<llama_token> kv_tokens;
};

static std::once_flag backend_once;

static std::vector<llama_token> tokenize(const llama_vocab * vocabulary, const char * text) {
    const int32_t byte_count = static_cast<int32_t>(std::strlen(text));
    std::vector<llama_token> tokens(static_cast<size_t>(byte_count) + 32);
    int32_t count = llama_tokenize(vocabulary, text, byte_count, tokens.data(), static_cast<int32_t>(tokens.size()), true, true);
    if (count < 0) {
        tokens.resize(static_cast<size_t>(-count));
        count = llama_tokenize(vocabulary, text, byte_count, tokens.data(), static_cast<int32_t>(tokens.size()), true, true);
    }
    if (count <= 0) { return {}; }
    tokens.resize(static_cast<size_t>(count));
    return tokens;
}

static std::string token_piece(const llama_vocab * vocabulary, llama_token token) {
    std::vector<char> bytes(32);
    int32_t count = llama_token_to_piece(vocabulary, token, bytes.data(), static_cast<int32_t>(bytes.size()), 0, false);
    if (count < 0) {
        bytes.resize(static_cast<size_t>(-count));
        count = llama_token_to_piece(vocabulary, token, bytes.data(), static_cast<int32_t>(bytes.size()), 0, false);
    }
    return count > 0 ? std::string(bytes.data(), static_cast<size_t>(count)) : std::string();
}

static char * copy_result(const std::string & value) {
    char * result = static_cast<char *>(std::malloc(value.size() + 1));
    if (!result) { return nullptr; }
    std::memcpy(result, value.data(), value.size());
    result[value.size()] = '\0';
    return result;
}

yuki_llama_context * yuki_llama_create(const char * model_path, uint32_t context_size) {
    if (!model_path) { return nullptr; }
    std::call_once(backend_once, [] { llama_backend_init(); });

    auto * state = new yuki_llama_context();
    llama_model_params model_parameters = llama_model_default_params();
#if TARGET_OS_SIMULATOR
    model_parameters.n_gpu_layers = 0;
#else
    model_parameters.n_gpu_layers = 99;
#endif
    state->model = llama_model_load_from_file(model_path, model_parameters);
    if (!state->model) {
        delete state;
        return nullptr;
    }

    llama_context_params context_parameters = llama_context_default_params();
    context_parameters.n_ctx = context_size;
    // n_batch must accept the largest prompt the guard below allows through
    // (n_ctx - max generation tokens). llama_decode aborts the process when a
    // batch exceeds n_batch, so a long conversation would otherwise crash.
    context_parameters.n_batch = context_size;
    context_parameters.n_ubatch = 256;
    const unsigned int processors = std::max(2u, std::thread::hardware_concurrency());
    const int32_t threads = static_cast<int32_t>(std::min(6u, processors > 2 ? processors - 2 : processors));
    context_parameters.n_threads = threads;
    context_parameters.n_threads_batch = threads;
    state->context = llama_init_from_model(state->model, context_parameters);
    if (!state->context) {
        llama_model_free(state->model);
        delete state;
        return nullptr;
    }

    state->vocabulary = llama_model_get_vocab(state->model);
    state->sampler = llama_sampler_chain_init(llama_sampler_chain_default_params());
    llama_sampler_chain_add(state->sampler, llama_sampler_init_top_k(40));
    // penalty_last_n must cover the whole prompt, not just freshly generated
    // tokens: the conversation history lives in the prompt.
    llama_sampler_chain_add(state->sampler, llama_sampler_init_penalties(1024, 1.1f, 0.0f, 0.0f));
    llama_sampler_chain_add(state->sampler, llama_sampler_init_top_p(0.9f, 1));
    llama_sampler_chain_add(state->sampler, llama_sampler_init_min_p(0.05f, 1));
    llama_sampler_chain_add(state->sampler, llama_sampler_init_temp(0.6f));
    llama_sampler_chain_add(state->sampler, llama_sampler_init_dist(LLAMA_DEFAULT_SEED));
    return state;
}

void yuki_llama_destroy(yuki_llama_context * state) {
    if (!state) { return; }
    if (state->sampler) { llama_sampler_free(state->sampler); }
    if (state->context) { llama_free(state->context); }
    if (state->model) { llama_model_free(state->model); }
    delete state;
}

char * yuki_llama_generate(yuki_llama_context * state, const char * prompt, int32_t maximum_tokens) {
    if (!state || !prompt || maximum_tokens <= 0) { return nullptr; }
    const auto deadline = std::chrono::steady_clock::now() + std::chrono::seconds(55);
    llama_sampler_reset(state->sampler);

    std::vector<llama_token> prompt_tokens = tokenize(state->vocabulary, prompt);
    if (prompt_tokens.empty() || prompt_tokens.size() + static_cast<size_t>(maximum_tokens) >= llama_n_ctx(state->context)) {
        return nullptr;
    }

    // Reuse the KV cache across turns. Within a session the prompt grows
    // append-only (system + history + new user turn), so only the suffix
    // beyond the shared prefix needs decoding instead of the whole prompt.
    size_t common = 0;
    while (common < state->kv_tokens.size() && common < prompt_tokens.size()
           && state->kv_tokens[common] == prompt_tokens[common]) { ++common; }
    // Drop everything past the shared prefix: stale generated tokens from the
    // previous turn and any history that no longer matches.
    if (!llama_memory_seq_rm(llama_get_memory(state->context), 0, static_cast<llama_pos>(common), -1)) {
        llama_memory_clear(llama_get_memory(state->context), true);
        common = 0;
    }
    state->kv_tokens.resize(common);
    const int32_t suffix_count = static_cast<int32_t>(prompt_tokens.size() - common);
    if (suffix_count > 0) {
        llama_batch batch = llama_batch_get_one(prompt_tokens.data() + common, suffix_count);
        if (llama_decode(state->context, batch) != 0) { return nullptr; }
    }
    state->kv_tokens = prompt_tokens;
    // The penalties sampler only sees tokens passed through accept(). Feed the
    // prompt in as well, otherwise the repetition penalty window is empty at
    // the start of every turn and the model freely re-asks questions it
    // already asked earlier in the conversation.
    for (const llama_token token : prompt_tokens) {
        llama_sampler_accept(state->sampler, token);
    }

    std::string output;
    output.reserve(static_cast<size_t>(maximum_tokens) * 4);
    for (int32_t index = 0; index < maximum_tokens; ++index) {
        if (std::chrono::steady_clock::now() >= deadline) { return copy_result("__YUKI_TIMEOUT__"); }
        const llama_token token = llama_sampler_sample(state->sampler, state->context, -1);
        if (llama_vocab_is_eog(state->vocabulary, token)) { break; }
        output += token_piece(state->vocabulary, token);
        llama_token next = token;
        llama_batch batch = llama_batch_get_one(&next, 1);
        if (llama_decode(state->context, batch) != 0) { return nullptr; }
    }
    if (output.empty()) { return nullptr; }
    return copy_result(output);
}

void yuki_llama_string_free(char * string) {
    std::free(string);
}
