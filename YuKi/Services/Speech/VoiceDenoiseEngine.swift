import AVFoundation
import DeepFilterNet
import Foundation

/// DeepFilterNet3 降噪引擎：对 48 kHz 单声道 Float32 PCM 做流式降噪。
///
/// 封装 libDF 的 C API（df_create / df_process_frame / df_free），
/// 内部完成算法延迟补偿，调用方拿到的是与输入时间对齐的输出。
final class VoiceDenoiseEngine {
    static let sampleRate = 48000

    /// DFN3 算法延迟 = (fft_size - hop_size) + lookahead * hop_size
    /// = (960 - 480) + 2 * 480 = 1440 samples（30ms @48k，见模型 config.ini）
    static let algorithmicDelaySamples = 1440

    private let state: OpaquePointer
    let frameLength: Int

    /// 模型文件在 App bundle 中的位置
    static var bundledModelURL: URL? {
        if let url = Bundle.appResources.url(forResource: "DeepFilterNet3_onnx", withExtension: "tar.gz") {
            return url
        }
        // 兜底：release .app 会把 SPM 资源包整体拷到 .app 根目录
        #if SWIFT_PACKAGE
        return Bundle.module.url(forResource: "DeepFilterNet3_onnx", withExtension: "tar.gz")
        #else
        return nil
        #endif
    }

    init?(modelURL: URL, attenuationLimitDb: Float, postFilterBeta: Float) {
        guard attenuationLimitDb > 0 else { return nil }
        guard let state = df_create(modelURL.path, attenuationLimitDb, "error") else {
            return nil
        }
        if postFilterBeta > 0 {
            df_set_post_filter_beta(state, postFilterBeta)
        }
        let frameLength = df_get_frame_length(state)
        guard frameLength > 0 else {
            df_free(state)
            return nil
        }
        self.state = state
        self.frameLength = frameLength
    }

    deinit {
        df_free(state)
    }

    /// 流式处理一段采样。跨 chunk 调用时状态连续，可分段喂入长音频。
    ///
    /// - Parameters:
    ///   - samples: 输入采样（任意长度，内部按 frame 切分，尾部不足一帧时补零）
    ///   - isFinal: 是否为最后一段。为 true 时额外喂入延迟量的零采样，
    ///     把滞留在算法流水线里的尾部音频冲刷出来
    ///   - discardDelay: 是否丢弃开头的算法延迟采样（整段音频的第一个 chunk 传 true）
    /// - Returns: 与输入时间对齐的输出采样；长度可能与输入不同（延迟补偿阶段）
    func process(samples: UnsafePointer<Float>, count: Int, isFinal: Bool = false, discardDelay: Bool = false) -> [Float] {
        guard count > 0 || isFinal else { return [] }
        var output: [Float] = []
        output.reserveCapacity(count + Self.algorithmicDelaySamples)

        let inFrame = UnsafeMutablePointer<Float>.allocate(capacity: frameLength)
        let outFrame = UnsafeMutablePointer<Float>.allocate(capacity: frameLength)
        defer {
            inFrame.deallocate()
            outFrame.deallocate()
        }

        var pos = 0
        while pos < count {
            let n = min(frameLength, count - pos)
            if n < frameLength {
                inFrame.initialize(repeating: 0, count: frameLength)
            }
            memcpy(inFrame, samples + pos, n * MemoryLayout<Float>.size)
            _ = df_process_frame(state, inFrame, outFrame)
            output.append(contentsOf: UnsafeBufferPointer(start: outFrame, count: n))
            pos += frameLength
        }

        if isFinal {
            // 冲刷算法延迟：补 delay 个零采样，取回滞留在内部的尾部音频
            var remaining = Self.algorithmicDelaySamples
            inFrame.initialize(repeating: 0, count: frameLength)
            while remaining > 0 {
                let n = min(frameLength, remaining)
                _ = df_process_frame(state, inFrame, outFrame)
                output.append(contentsOf: UnsafeBufferPointer(start: outFrame, count: n))
                remaining -= n
            }
        }

        if discardDelay {
            // 输出整体滞后 algorithmicDelaySamples，丢弃开头即时间对齐
            let drop = min(Self.algorithmicDelaySamples, output.count)
            output.removeFirst(drop)
        }
        return output
    }
}
