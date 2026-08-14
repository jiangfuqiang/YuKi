import AVFoundation
import Foundation

enum VoiceDenoiseError: LocalizedError {
    case modelMissing
    case exportFailed
    case decodeFailed

    var errorDescription: String? {
        switch self {
        case .modelMissing: return "降噪模型文件缺失"
        case .exportFailed: return "降噪音频导出失败"
        case .decodeFailed: return "麦克风音轨解码失败"
        }
    }
}

/// 人声降噪处理器
///
/// 处理链路与产品定义一致：低频过滤 → DeepFilterNet 神经网络降噪 → 音量均衡 → 防爆音限制。
/// 优先处理第一条麦克风音轨；仅有系统音频时也允许将其下混为单声道处理。
/// 全程流式处理，内存占用与音频时长无关。
enum VoiceDenoiseProcessor {
    struct Output {
        /// 供详情页试听和长期保存的 AAC 文件。
        let playbackURL: URL
        /// 直接从 DFN 输出的 48kHz Float32 PCM 重采样而来，未经过 AAC。
        let transcriptionSamples16k: [Float]
    }

    // MARK: - 对外入口

    /// 处理 asset 的第一条音轨，同时返回试听文件与无 AAC 中转的识别 PCM。
    /// 无音轨或档位为关闭时返回 nil。
    static func processMicrophoneTrack(
        of asset: AVAsset,
        settings: VoiceDenoiseSettings,
        progress: ((Double) -> Void)? = nil
    ) async throws -> Output? {
        guard settings.isEnabled else { return nil }
        let audioTracks = try await asset.loadTracks(withMediaType: .audio)
        guard let micTrack = audioTracks.first else { return nil }
        // 麦克风轨身份是位置约定（Track 0）。录制时麦克风是单声道、
        // 系统声音通常是立体声。
        // 录制同时包含麦克风和系统声音时，Track 0 必须仍是单声道麦克风，
        // 避免误处理系统声；只有一条音轨时，它可能是立体声系统音频，此时
        // AVAudioConverter 会安全下混为 48 kHz 单声道后再执行人声降噪。
        if audioTracks.count > 1 {
            guard try await isMonoTrack(micTrack) else { return nil }
        }
        guard let modelURL = VoiceDenoiseEngine.bundledModelURL else {
            throw VoiceDenoiseError.modelMissing
        }
        guard let engine = VoiceDenoiseEngine(
            modelURL: modelURL,
            attenuationLimitDb: settings.effectiveAttenuationLimitDb,
            postFilterBeta: settings.effectivePostFilterBeta
        ) else {
            throw VoiceDenoiseError.modelMissing
        }

        // 1. VoiceThought 的普通录音本来就是单音轨文件，直接解码，避免为了
        // “统一入口”再次 AAC 编码。只有 composition / 多音轨输入才沿用
        // FocusCaptureDaxia 的单轨导出逻辑。
        let temporaryRawURL: URL?
        let rawURL: URL
        if audioTracks.count == 1, let urlAsset = asset as? AVURLAsset {
            rawURL = urlAsset.url
            temporaryRawURL = nil
        } else {
            let exported = temporaryURL(suffix: "raw", ext: "m4a")
            try await exportSingleTrack(micTrack, to: exported)
            rawURL = exported
            temporaryRawURL = exported
        }
        defer {
            if let temporaryRawURL {
                try? FileManager.default.removeItem(at: temporaryRawURL)
            }
        }
        progress?(0.15)

        // 2. 解码 → 高通 → DFN → 临时 WAV（流式，累积响度统计）
        let wavURL = temporaryURL(suffix: "denoised", ext: "wav")
        defer { try? FileManager.default.removeItem(at: wavURL) }
        let stats = try await denoiseToWAV(source: rawURL, destination: wavURL, engine: engine) { p in
            progress?(0.15 + p * 0.65)
        }
        // WAV 此时已经关闭并写回文件头。从 DFN 的 Float32 PCM 直接重采样，
        // 识别链路不经过后续 AAC 编码。
        let transcriptionSamples16k = try WhisperCaptionTranscriber.shared.decodeSamples(from: wavURL)

        // 3. 音量均衡 + 防爆音限制 → AAC m4a
        let outURL = temporaryURL(suffix: "denoised_final", ext: "m4a")
        try await normalizeAndEncodeAAC(source: wavURL, destination: outURL, stats: stats) { p in
            progress?(0.8 + p * 0.2)
        }
        progress?(1)
        return Output(
            playbackURL: outURL,
            transcriptionSamples16k: transcriptionSamples16k
        )
    }

    /// 把 asset 的第一条音轨替换为给定音频文件，其余轨道原样保留。
    /// 用于导出前把降噪后的麦克风音轨替换回去。
    static func assetReplacingFirstAudioTrack(of asset: AVAsset, with audioURL: URL) async throws -> AVMutableComposition? {
        let audioTracks = try await asset.loadTracks(withMediaType: .audio)
        guard let firstAudio = audioTracks.first else { return nil }
        let newAudioAsset = AVURLAsset(url: audioURL)
        guard let newAudioTrack = try await newAudioAsset.loadTracks(withMediaType: .audio).first else {
            return nil
        }
        let newAudioRange = try await newAudioTrack.load(.timeRange)
        let firstAudioRange = try await firstAudio.load(.timeRange)

        let composition = AVMutableComposition()
        for track in try await asset.load(.tracks) where track.mediaType != .audio {
            guard let compTrack = composition.addMutableTrack(
                withMediaType: track.mediaType,
                preferredTrackID: kCMPersistentTrackID_Invalid
            ) else { continue }
            let range = try await track.load(.timeRange)
            try compTrack.insertTimeRange(range, of: track, at: range.start)
            compTrack.preferredTransform = try await track.load(.preferredTransform)
        }

        // 降噪后的麦克风轨放回原麦克风轨的时间位置（长度取两者交集）
        if let compAudio = composition.addMutableTrack(
            withMediaType: .audio,
            preferredTrackID: kCMPersistentTrackID_Invalid
        ) {
            let duration = CMTimeMinimum(newAudioRange.duration, firstAudioRange.duration)
            if CMTimeCompare(duration, .zero) > 0 {
                try compAudio.insertTimeRange(
                    CMTimeRange(start: .zero, duration: duration),
                    of: newAudioTrack,
                    at: firstAudioRange.start
                )
            }
        }

        // 其余音轨（系统声音等）原样保留
        for track in audioTracks.dropFirst() {
            guard let compTrack = composition.addMutableTrack(
                withMediaType: .audio,
                preferredTrackID: kCMPersistentTrackID_Invalid
            ) else { continue }
            let range = try await track.load(.timeRange)
            try compTrack.insertTimeRange(range, of: track, at: range.start)
        }
        return composition
    }

    // MARK: - 内部步骤

    /// 音轨是否为单声道（麦克风轨特征；读不出声道数时按单声道处理，保持兼容）
    private static func isMonoTrack(_ track: AVAssetTrack) async throws -> Bool {
        let descriptions = try await track.load(.formatDescriptions)
        guard let desc = descriptions.first else { return true }
        let mediaType = CMFormatDescriptionGetMediaType(desc)
        guard mediaType == kCMMediaType_Audio,
              let asbd = CMAudioFormatDescriptionGetStreamBasicDescription(desc) else {
            return true
        }
        return asbd.pointee.mChannelsPerFrame == 1
    }

    private static func temporaryURL(suffix: String, ext: String) -> URL {
        URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("focuscapture_denoise_\(suffix)_\(UUID().uuidString)")
            .appendingPathExtension(ext)
    }

    /// 把单条音轨导出为 m4a（AAC），作为统一的解码入口
    private static func exportSingleTrack(_ track: AVAssetTrack, to url: URL) async throws {
        let composition = AVMutableComposition()
        guard let compTrack = composition.addMutableTrack(
            withMediaType: .audio,
            preferredTrackID: kCMPersistentTrackID_Invalid
        ) else { throw VoiceDenoiseError.exportFailed }
        let range = try await track.load(.timeRange)
        try compTrack.insertTimeRange(range, of: track, at: .zero)

        try? FileManager.default.removeItem(at: url)
        guard let session = AVAssetExportSession(
            asset: composition,
            presetName: AVAssetExportPresetAppleM4A
        ) else { throw VoiceDenoiseError.exportFailed }
        session.outputURL = url
        session.outputFileType = .m4a
        await session.export()
        guard session.status == .completed else {
            throw session.error ?? VoiceDenoiseError.exportFailed
        }
    }

    private struct LoudnessStats {
        var sumSquares: Double = 0
        var sampleCount: Int = 0
        var rms: Double { sampleCount > 0 ? (sumSquares / Double(sampleCount)).squareRoot() : 0 }
    }

    /// 解码源音频 → 80 Hz 高通 → DeepFilterNet → 写 48k 单声道 Float32 WAV
    private static func denoiseToWAV(
        source: URL,
        destination: URL,
        engine: VoiceDenoiseEngine,
        progress: (Double) -> Void
    ) async throws -> LoudnessStats {
        let srcFile: AVAudioFile
        do {
            srcFile = try AVAudioFile(forReading: source)
        } catch {
            throw VoiceDenoiseError.decodeFailed
        }
        guard let targetFormat = AVAudioFormat(
            commonFormat: .pcmFormatFloat32,
            sampleRate: Double(VoiceDenoiseEngine.sampleRate),
            channels: 1,
            interleaved: false
        ) else {
            throw VoiceDenoiseError.decodeFailed
        }
        try? FileManager.default.removeItem(at: destination)
        var wavFile: AVAudioFile? = try AVAudioFile(forWriting: destination, settings: [
            AVFormatIDKey: kAudioFormatLinearPCM,
            AVSampleRateKey: VoiceDenoiseEngine.sampleRate,
            AVNumberOfChannelsKey: 1,
            AVLinearPCMBitDepthKey: 32,
            AVLinearPCMIsFloatKey: true,
        ])
        defer { wavFile = nil } // deinit 时回写 WAV 头

        let totalFrames = srcFile.length
        var stats = LoudnessStats()
        var processedFrames: Int64 = 0
        var isFirstChunk = true
        var highPass = OnePoleHighPass(cutoffHz: 80, sampleRate: Double(VoiceDenoiseEngine.sampleRate))

        // 流式重采样到 48k 单声道（源通常已是 48k 单声道，converter 直通）
        let srcFormat = srcFile.processingFormat
        guard let converter = AVAudioConverter(from: srcFormat, to: targetFormat) else {
            throw VoiceDenoiseError.decodeFailed
        }
        let inChunkFrames: AVAudioFrameCount = 480_000 // 10s 输入块
        let inputState = AudioConversionInputState()

        while true {
            try Task.checkCancellation()
            let outCapacity = AVAudioFrameCount(Double(inChunkFrames) * targetFormat.sampleRate / srcFormat.sampleRate + 4096)
            guard let outBuf = AVAudioPCMBuffer(pcmFormat: targetFormat, frameCapacity: outCapacity) else {
                throw VoiceDenoiseError.decodeFailed
            }
            var convError: NSError?
            let status = converter.convert(to: outBuf, error: &convError) { _, status in
                if inputState.isDone {
                    status.pointee = .endOfStream
                    return nil
                }
                guard let inBuf = AVAudioPCMBuffer(pcmFormat: srcFormat, frameCapacity: inChunkFrames) else {
                    status.pointee = .endOfStream
                    inputState.markDone()
                    return nil
                }
                do {
                    // 钳制到剩余帧数：超出剩余的读取会失败且不填 NSError
                    let remaining = srcFile.length - srcFile.framePosition
                    if remaining <= 0 {
                        inputState.markDone()
                        status.pointee = .endOfStream
                        return nil
                    }
                    try srcFile.read(into: inBuf, frameCount: min(inChunkFrames, AVAudioFrameCount(remaining)))
                } catch {
                    status.pointee = .endOfStream
                    inputState.markDone()
                    return nil
                }
                if inBuf.frameLength == 0 {
                    inputState.markDone()
                    status.pointee = .endOfStream
                    return nil
                }
                status.pointee = .haveData
                return inBuf
            }
            if convError != nil { throw VoiceDenoiseError.decodeFailed }

            if outBuf.frameLength > 0, let data = outBuf.floatChannelData?[0] {
                let count = Int(outBuf.frameLength)
                highPass.apply(data, count: count)
                let denoised = engine.process(
                    samples: data,
                    count: count,
                    isFinal: false,
                    discardDelay: isFirstChunk
                )
                isFirstChunk = false
                if !denoised.isEmpty {
                    try writeSamples(denoised, to: wavFile, format: targetFormat, stats: &stats)
                }
                processedFrames += Int64(count)
                if totalFrames > 0 {
                    progress(min(1, Double(processedFrames) / Double(totalFrames) * 0.95))
                }
            }
            if status == .endOfStream || (inputState.isDone && outBuf.frameLength == 0) { break }
        }

        // 冲刷算法尾部延迟
        let flushSample: [Float] = [0]
        let tail = flushSample.withUnsafeBufferPointer { buffer -> [Float] in
            guard let baseAddress = buffer.baseAddress else { return [] }
            return engine.process(samples: baseAddress, count: 0, isFinal: true)
        }
        if !tail.isEmpty {
            try writeSamples(tail, to: wavFile, format: targetFormat, stats: &stats)
        }
        progress(1)
        return stats
    }

    private static func writeSamples(
        _ samples: [Float],
        to file: AVAudioFile?,
        format: AVAudioFormat,
        stats: inout LoudnessStats
    ) throws {
        guard let file, let buf = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(samples.count)) else {
            throw VoiceDenoiseError.exportFailed
        }
        buf.frameLength = AVAudioFrameCount(samples.count)
        let dst = buf.floatChannelData![0]
        var sumSq: Double = 0
        for i in 0..<samples.count {
            let v = samples[i]
            dst[i] = v
            sumSq += Double(v) * Double(v)
        }
        stats.sumSquares += sumSq
        stats.sampleCount += samples.count
        try file.write(from: buf)
    }

    /// 音量均衡（只衰减过响内容，不放大降噪残留）→ 防爆音（-1.5 dBFS 硬限幅）→ AAC m4a
    private static func normalizeAndEncodeAAC(
        source: URL,
        destination: URL,
        stats: LoudnessStats,
        progress: (Double) -> Void
    ) async throws {
        let targetRms = pow(10.0, -18.0 / 20.0)
        let rawGain = stats.rms > 1e-6 ? targetRms / stats.rms : 1
        // DeepFilterNet 已经改变了噪声/回声与人声的比例。按输出 RMS
        // 盲目补到 -18 dBFS 最多会施加 +12 dB，把 AEC 剩余的微弱回声
        // 重新放大成明显的“影子声”。降噪阶段只允许衰减过响信号；
        // 录制音量由实时采集链保持，不在离线降噪后做正增益补偿。
        let gain = Float(min(1.0, max(0.25, rawGain)))
        let ceiling = Float(pow(10.0, -1.5 / 20.0))

        let srcFile: AVAudioFile
        do {
            srcFile = try AVAudioFile(forReading: source)
        } catch {
            throw VoiceDenoiseError.decodeFailed
        }
        let format = srcFile.processingFormat
        try? FileManager.default.removeItem(at: destination)
        var outFile: AVAudioFile? = try AVAudioFile(forWriting: destination, settings: [
            AVFormatIDKey: kAudioFormatMPEG4AAC,
            AVSampleRateKey: VoiceDenoiseEngine.sampleRate,
            AVNumberOfChannelsKey: 1,
            AVEncoderBitRateKey: 96_000,
        ])
        defer { outFile = nil }

        let totalFrames = srcFile.length
        var done: Int64 = 0
        let chunk: AVAudioFrameCount = 480_000
        while true {
            try Task.checkCancellation()
            // 读取数必须钳制到剩余帧数：AVAudioFile 对超出剩余帧的读取会
            // 返回失败且不填 NSError（上层表现为 nilError）
            let remaining = totalFrames - done
            if remaining <= 0 { break }
            let toRead = min(chunk, AVAudioFrameCount(remaining))
            guard let buf = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: toRead) else {
                throw VoiceDenoiseError.decodeFailed
            }
            try srcFile.read(into: buf, frameCount: toRead)
            if buf.frameLength == 0 { break }
            if let data = buf.floatChannelData?[0] {
                for i in 0..<Int(buf.frameLength) {
                    var v = data[i] * gain
                    v = min(ceiling, max(-ceiling, v))
                    data[i] = v
                }
            }
            try outFile?.write(from: buf)
            done += Int64(buf.frameLength)
            if totalFrames > 0 {
                progress(min(1, Double(done) / Double(totalFrames)))
            }
        }
    }

    /// 一阶 RC 高通滤波器（80 Hz 去低频轰声），跨 chunk 保持状态
    private struct OnePoleHighPass {
        let alpha: Double
        var prevInput: Float = 0
        var prevOutput: Float = 0

        init(cutoffHz: Double, sampleRate: Double) {
            let rc = 1.0 / (2.0 * .pi * cutoffHz)
            alpha = rc / (rc + 1.0 / sampleRate)
        }

        mutating func apply(_ samples: UnsafeMutablePointer<Float>, count: Int) {
            let a = Float(alpha)
            for i in 0..<count {
                let x = samples[i]
                let y = a * (prevOutput + x - prevInput)
                prevInput = x
                prevOutput = y
                samples[i] = y
            }
        }
    }
}

private final class AudioConversionInputState: @unchecked Sendable {
    private let lock = NSLock()
    private var done = false

    var isDone: Bool {
        lock.lock()
        defer { lock.unlock() }
        return done
    }

    func markDone() {
        lock.lock()
        done = true
        lock.unlock()
    }
}
