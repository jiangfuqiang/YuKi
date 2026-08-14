#ifndef YUKI_LLAMA_BRIDGE_H
#define YUKI_LLAMA_BRIDGE_H

#include <stdint.h>

#ifdef __cplusplus
extern "C" {
#endif

typedef struct yuki_llama_context yuki_llama_context;

yuki_llama_context * yuki_llama_create(const char * model_path, uint32_t context_size);
void yuki_llama_destroy(yuki_llama_context * context);
char * yuki_llama_generate(yuki_llama_context * context, const char * prompt, int32_t maximum_tokens);
void yuki_llama_string_free(char * string);

#ifdef __cplusplus
}
#endif

#endif
