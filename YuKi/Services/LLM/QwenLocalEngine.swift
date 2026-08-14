import Foundation
import LlamaBridge

enum QwenLocalEngineError: LocalizedError {
    case modelMissing
    case modelLoadFailed
    case inferenceFailed
    case emptyResponse
    case timedOut

    var errorDescription: String? {
        switch self {
        case .modelMissing: "未找到 Qwen3.5 本地模型。"
        case .modelLoadFailed: "Qwen3.5 模型加载失败。"
        case .inferenceFailed: "本地模型推理失败。"
        case .emptyResponse: "本地模型没有生成有效回复。"
        case .timedOut: "本地模型未在 60 秒内生成回复，请重试。"
        }
    }
}

/// llama.cpp access is serialized on a dedicated native queue. Keeping the
/// blocking model load and decode calls off Swift's cooperative executors is
/// essential: an actor job may otherwise monopolize the UI executor on device.
final class QwenLocalEngine: @unchecked Sendable {
    static let shared = QwenLocalEngine()

    private let queue = DispatchQueue(label: "com.localfirst.yuki.qwen", qos: .userInitiated)
    private var bridge: OpaquePointer?

    func prepare() async throws {
        try await withCheckedThrowingContinuation { continuation in
            queue.async { [self] in
                do {
                    try ensureLoaded()
                    continuation.resume()
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }
    }

    func generate(prompt: String, maximumTokens: Int32 = 192) async throws -> String {
        try await withCheckedThrowingContinuation { continuation in
            queue.async { [self] in
                do {
                    continuation.resume(returning: try generateSynchronously(prompt: prompt, maximumTokens: maximumTokens))
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }
    }

    private func generateSynchronously(prompt: String, maximumTokens: Int32) throws -> String {
        try ensureLoaded()
        guard let bridge else { throw QwenLocalEngineError.modelLoadFailed }
        guard let generated = yuki_llama_generate(bridge, prompt, maximumTokens) else {
            throw QwenLocalEngineError.inferenceFailed
        }
        defer { yuki_llama_string_free(generated) }
        guard let result = String(validatingCString: generated)?
            .trimmingCharacters(in: .whitespacesAndNewlines),
              !result.isEmpty else {
            throw QwenLocalEngineError.emptyResponse
        }
        if result == "__YUKI_TIMEOUT__" {
            throw QwenLocalEngineError.timedOut
        }
        return result
    }

    func releaseModel() async {
        await withCheckedContinuation { continuation in
            queue.async { [self] in
                if let bridge {
                    yuki_llama_destroy(bridge)
                    self.bridge = nil
                }
                continuation.resume()
            }
        }
    }

    private func ensureLoaded() throws {
        guard bridge == nil else { return }
        guard let modelURL = Self.bundledModelURL else { throw QwenLocalEngineError.modelMissing }
        guard let created = yuki_llama_create(modelURL.path, 2048) else {
            throw QwenLocalEngineError.modelLoadFailed
        }
        bridge = created
    }

    static var bundledModelURL: URL? {
        Bundle.main.url(
            forResource: "Qwen3.5-0.8B-Q4_K_M",
            withExtension: "gguf",
            subdirectory: "MLModels"
        ) ?? Bundle.main.url(forResource: "Qwen3.5-0.8B-Q4_K_M", withExtension: "gguf")
    }
}
