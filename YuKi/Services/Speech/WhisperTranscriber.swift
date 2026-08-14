import AVFoundation
import Foundation

import WhisperCpp

enum WhisperCaptionError: LocalizedError {
    case modelNotFound
    case modelLoadFailed(String)
    case audioReadFailed(String)
    case transcriptionFailed(String)
    case cancelled

    var errorDescription: String? {
        switch self {
        case .modelNotFound:
            return "找不到语音识别模型文件。请重新安装应用。"
        case .modelLoadFailed:
            return "语音识别模型加载失败。"
        case .audioReadFailed(let message):
            return "读取音频失败：\(message)"
        case .transcriptionFailed(let message):
            return "语音识别失败：\(message)"
        case .cancelled:
            return "识别已取消。"
        }
    }
}

/// whisper.cpp 单个识别片段。t0/t1 原始单位是 10ms，这里已换算成毫秒。
struct WhisperCaptionSegment {
    let startMs: Double
    let endMs: Double
    let text: String
}

/// 转录引擎路由。
enum TranscriptionEngine {
    case whisper
    case appleSpeech
}

/// 识别语言选项，附带引擎路由、whisper 参数和 Apple Speech locale。
///
/// 双引擎路由（FocusCapture 实测验证的方案）：
/// - 本地 whisper.cpp：简体中文、显式选择的 English (US)/(UK)
/// - Apple Speech（SFSpeechRecognizer，requiresOnDeviceRecognition 保持离线）：
///   繁体中文、粤语、日语、韩语
/// - 跟随系统：系统首选语言为简体中文走 whisper，其余走 Apple Speech。
///
/// whisper 采样策略按语言区分（whisper-demo 多轮真实录音验证）:
/// - 中文:beam search(beam_size=5) + prompt。中文依赖 prompt 提供标点和产品名,
///   beam + prompt 在长录音上内容最完整(greedy + prompt 曾吞掉两句)。
/// - 英文:greedy、无 prompt。英文 Whisper 原生输出标点,prompt 收益小;
///   且 beam 会偶发把开头一句合并吞掉(0–17s 压成一段),greedy 分段细、
///   时间戳也更贴近真实语音边界。
enum WhisperCaptionLanguage {
    case system
    case simplifiedChinese
    case traditionalChinese
    case englishUS
    case englishUK
    case french
    case spanish
    case cantonese
    case japanese
    case korean

    /// 从设置存储值解析；未知值兜底为 .system（旧版本只存过 system/zh-Hans/yue/ja/ko）。
    init(storageValue: String?) {
        switch storageValue {
        case "zh-Hans": self = .simplifiedChinese
        case "zh-Hant": self = .traditionalChinese
        case "en-US": self = .englishUS
        case "en-GB": self = .englishUK
        case "fr": self = .french
        case "es": self = .spanish
        case "yue": self = .cantonese
        case "ja": self = .japanese
        case "ko": self = .korean
        default: self = .system
        }
    }

    /// All recording languages use the bundled Whisper model so preview and
    /// final recovery stay offline and available during recording.
    var engine: TranscriptionEngine { .whisper }

    /// whisper_full_params 的 language 参数；仅 whisper 路由有效，其余为 nil。
    /// English (US)/(UK) 都传 en（whisper 没有口音参数）。
    var whisperLanguageCode: String? {
        switch self {
        case .simplifiedChinese: return "zh"
        case .englishUS, .englishUK: return "en"
        case .french: return "fr"
        case .spanish: return "es"
        case .traditionalChinese: return "zh"
        case .cantonese: return "yue"
        case .japanese: return "ja"
        case .korean: return "ko"
        case .system:
            let code = Locale.current.language.languageCode?.identifier ?? "auto"
            return ["zh", "yue", "ja", "ko", "en"].contains(code) ? code : "auto"
        }
    }

    /// true 用 beam search(beam_size=5),false 用 greedy。仅走 whisper 的中文为 true。
    var useBeamSearch: Bool {
        ["zh", "yue", "ja", "ko"].contains(whisperLanguageCode ?? "")
    }

    /// 给解码器的场景提示;nil 表示不传 initial_prompt。仅中文；英文不传。
    var initialPrompt: String? {
        switch self {
        case .simplifiedChinese:
            return "以下是简体中文的语音记录，用户正在 VoiceThought 中记录一段想法。"
        case .traditionalChinese:
            return "以下是繁體中文的語音記錄，用戶正在 VoiceThought 中記錄一段想法。"
        case .cantonese:
            return "以下係用戶喺 VoiceThought 記錄嘅一段廣東話想法。"
        case .japanese:
            return "以下はVoiceThoughtで記録された日本語の音声メモです。"
        case .korean:
            return "다음은 VoiceThought에서 녹음한 한국어 음성 메모입니다."
        case .system:
            return Self.systemPrefersSimplifiedChinese
                ? "以下是简体中文的语音记录，用户正在 VoiceThought 中记录一段想法。"
                : nil
        case .englishUS, .englishUK, .french, .spanish:
            return nil
        }
    }

    /// SFSpeechRecognizer 的 locale identifier；仅 appleSpeech 路由有效。
    /// .system 返回 nil，由默认 SFSpeechRecognizer() 使用系统当前听写语言。
    var appleSpeechLocaleIdentifier: String? {
        switch self {
        case .traditionalChinese: return "zh-TW"
        case .cantonese: return "yue-CN"
        case .japanese: return "ja-JP"
        case .korean: return "ko-KR"
        case .french: return "fr-FR"
        case .spanish: return "es-ES"
        case .system, .simplifiedChinese, .englishUS, .englishUK: return nil
        }
    }

    /// 系统首选语言是否为简体中文（对齐 FocusCapture AutoCaptionTranscriber 的判定：
    /// 首选语言 zh-Hans*/zh-CN；bare "zh" 时按 script/地区判断，CN/SG/MY 默认简体）。
    private static var systemPrefersSimplifiedChinese: Bool {
        if let preferred = Locale.preferredLanguages.first {
            return preferred.hasPrefix("zh-Hans") || preferred == "zh-CN"
        }
        let language = Locale.current.language
        guard language.languageCode?.identifier == "zh" else { return false }
        if let script = language.script?.identifier {
            return script == "Hans"
        }
        let region = Locale.current.region?.identifier ?? ""
        return ["CN", "SG", "MY"].contains(region)
    }
}

/// 基于 whisper.cpp 静态库的语音识别引擎（简体中文、英文）。
///
/// 输入为 16kHz 单声道 Float32 WAV（与自动字幕管线 preprocessAudioForSpeechRecognition
/// 的输出一致），参数沿用 whisper-demo 验证过的配置：beam search(beam_size=5)、
/// initial_prompt 场景提示、no_speech_thold=0.4、logprob_thold=-1.0、
/// temperature=0.0、temperature_inc=0.2。
final class WhisperCaptionTranscriber: @unchecked Sendable {
    static let shared = WhisperCaptionTranscriber()

    /// 模型 252MB，全进程只加载一次；whisper context 不支持并发 whisper_full，
    /// 用同一把锁串行化所有识别调用。
    private let lock = NSLock()
    private var context: OpaquePointer?

    /// C 字符串常量指针，交给 whisper_full_params 后必须全程有效，这里随进程存活。
    private var languageCString: UnsafeMutablePointer<CChar>?
    private var promptCString: UnsafeMutablePointer<CChar>?

    private init() {
        // 屏蔽 whisper/ggml 打到 stderr 的大量日志。
        whisper_log_set({ _, _, _ in }, nil)
        // 该 ggml-metal 版本在进程退出时断言 residency set 已全部释放
        // （GGML_ASSERT([rsets->data count] == 0)，见 ggml-metal-device.m:622），
        // 即使 whisper_free 后仍可能残留导致退出时 crash；residency sets 只是性能优化，
        // 官方提供了 GGML_METAL_NO_RESIDENCY 开关，在初始化 context 前关掉。
        setenv("GGML_METAL_NO_RESIDENCY", "1", 0)
        // 退出时显式释放 context（atexit 先于 C++ 静态析构执行）。
        atexit {
            WhisperCaptionTranscriber.shared.freeContext()
        }
    }

    /// 释放 whisper context（进程退出时由 atexit 调用；加锁避免与进行中的识别竞争）。
    private func freeContext() {
        lock.lock()
        defer { lock.unlock() }
        if let context {
            whisper_free(context)
            self.context = nil
        }
    }

    deinit {
        if let context { whisper_free(context) }
        free(languageCString)
        free(promptCString)
    }

    /// App bundle / SPM 资源包中的模型路径。
    static var bundledModelURL: URL? {
        let bundles: [Bundle] = {
            var result: [Bundle] = [.appResources]
            #if SWIFT_PACKAGE
            result.append(.module)
            #endif
            return result
        }()
        for bundle in bundles {
            if let url = bundle.url(forResource: "ggml-small-q8_0", withExtension: "bin", subdirectory: "MLModels") {
                return url
            }
            // 兜底：资源可能被扁平化复制（Xcode Copy Bundle Resources）
            if let url = bundle.url(forResource: "ggml-small-q8_0", withExtension: "bin") {
                return url
            }
        }
        return nil
    }

    /// 识别一个 16kHz 单声道 Float32 WAV 文件。
    /// whisper_full 是阻塞调用，放到后台线程执行；支持 Task cancellation
    /// （通过 abort_callback 让 whisper 尽快退出）。
    func transcribe(
        wavURL: URL, language: WhisperCaptionLanguage,
        progress: (@Sendable (Double) -> Void)? = nil
    ) async throws -> [WhisperCaptionSegment] {
        try Task.checkCancellation()
        let samples = try decodeSamples(from: wavURL)
        return try await transcribe(
            samples16k: samples, language: language, preview: false, progress: progress
        )
    }

    /// Streaming preview entry point. Samples must be mono Float32 at 16 kHz.
    func transcribe(
        samples16k samples: [Float],
        language: WhisperCaptionLanguage,
        previousText: String = ""
    ) async throws -> [WhisperCaptionSegment] {
        try await transcribe(
            samples16k: samples, language: language,
            preview: true, previousText: previousText
        )
    }

    /// 完整文件识别入口。输入已经是 16kHz 单声道 Float32，不再解码 AAC。
    func transcribe(
        samples16k samples: [Float],
        language: WhisperCaptionLanguage,
        progress: @escaping @Sendable (Double) -> Void
    ) async throws -> [WhisperCaptionSegment] {
        try await transcribe(
            samples16k: samples,
            language: language,
            preview: false,
            progress: progress
        )
    }

    /// Loads the bundled model away from the main actor so the first preview
    /// does not spend its entire latency budget opening a 252 MB model.
    func prepare() async throws {
        try await withCheckedThrowingContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                do {
                    _ = try self.obtainContext()
                    continuation.resume()
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }
    }

    /// Releases the 252 MB Whisper context before the dialogue model loads.
    /// YuKi deliberately trades a later reload for predictable peak memory.
    func releaseModel() async {
        await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .utility).async {
                self.freeContext()
                continuation.resume()
            }
        }
    }

    private func transcribe(
        samples16k samples: [Float],
        language: WhisperCaptionLanguage,
        preview: Bool,
        previousText: String = "",
        progress: (@Sendable (Double) -> Void)? = nil
    ) async throws -> [WhisperCaptionSegment] {
        try Task.checkCancellation()
        guard !samples.isEmpty else { return [] }
        // DeepFilterNet removes stationary noise but is not a voice activity
        // detector. Do not ask Whisper to invent text for a silent rolling
        // window. The adaptive floor keeps quiet speech while requiring several
        // consecutive voiced frames, so isolated taps/clicks do not pass.
        guard !preview || Self.containsSpeech(samples16k: samples) else { return [] }
        let cancellationFlag = CancellationFlag(progress: progress)

        return try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                DispatchQueue.global(qos: .userInitiated).async {
                    do {
                        // Loading the 252 MB model is intentionally performed on
                        // this worker too. Doing it before dispatch freezes the
                        // recorder UI during the first live preview.
                        let loadedContext = try self.obtainContext()
                        let contextAddress = Int(bitPattern: loadedContext)
                        // 串行化：whisper context 不支持并发 whisper_full
                        self.lock.lock()
                        defer { self.lock.unlock() }
                        guard let context = OpaquePointer(bitPattern: contextAddress) else {
                            throw WhisperCaptionError.modelLoadFailed("无效的模型上下文")
                        }
                        let segments = try self.runWhisper(
                            context: context,
                            samples: samples,
                            language: language,
                            preview: preview,
                            previousText: previousText,
                            cancellationFlag: cancellationFlag
                        )
                        continuation.resume(returning: segments)
                    } catch {
                        continuation.resume(throwing: error)
                    }
                }
            }
        } onCancel: {
            cancellationFlag.cancel()
        }
    }

    // MARK: - 私有实现

    private final class CancellationFlag: @unchecked Sendable {
        private let lock = NSLock()
        private var value = false
        private let progress: (@Sendable (Double) -> Void)?
        init(progress: (@Sendable (Double) -> Void)? = nil) { self.progress = progress }

        var isCancelled: Bool {
            lock.lock()
            defer { lock.unlock() }
            return value
        }

        func cancel() {
            lock.lock()
            value = true
            lock.unlock()
        }
        func report(_ value: Int32) { progress?(min(1, max(0, Double(value) / 100))) }
    }

    private func obtainContext() throws -> OpaquePointer {
        lock.lock()
        defer { lock.unlock() }

        if let context { return context }

        // 环境变量优先，方便冒烟测试/调试指定模型
        let modelURL: URL?
        if let override = ProcessInfo.processInfo.environment["WHISPER_MODEL_PATH"], !override.isEmpty {
            modelURL = URL(fileURLWithPath: override)
        } else {
            modelURL = Self.bundledModelURL
        }

        guard let modelURL, FileManager.default.fileExists(atPath: modelURL.path) else {
            throw WhisperCaptionError.modelNotFound
        }

        var contextParams = whisper_context_default_params()
        contextParams.use_gpu = true
        // DTW 词级对齐：用解码器 cross-attention 做动态时间规整，输出每个 token 的
        // 真实发声时刻（whisper-demo 验证：与能量检测的语音起点误差 <100ms）
        contextParams.dtw_token_timestamps = true
        contextParams.dtw_aheads_preset = WHISPER_AHEADS_SMALL
        // DTW 需要 cross-attention 权重，与 flash attention 不兼容，必须关闭
        contextParams.flash_attn = false
        guard let context = whisper_init_from_file_with_params(modelURL.path, contextParams) else {
            throw WhisperCaptionError.modelLoadFailed(modelURL.path)
        }
        self.context = context
        return context
    }

    /// 调用方必须已持有 lock。
    private func runWhisper(
        context: OpaquePointer,
        samples: [Float],
        language: WhisperCaptionLanguage,
        preview: Bool,
        previousText: String,
        cancellationFlag: CancellationFlag
    ) throws -> [WhisperCaptionSegment] {
        var params = whisper_full_default_params(
            language.useBeamSearch ? WHISPER_SAMPLING_BEAM_SEARCH : WHISPER_SAMPLING_GREEDY
        )
        if language.useBeamSearch {
            params.beam_search.beam_size = 5
        }
        free(languageCString); free(promptCString)
        languageCString = strdup(language.whisperLanguageCode ?? "auto")
        let trimmedPrevious = previousText.trimmingCharacters(in: .whitespacesAndNewlines)
        let effectivePrompt = [language.initialPrompt, trimmedPrevious.isEmpty ? nil : trimmedPrevious]
            .compactMap { $0 }
            .joined(separator: "\n")
        if !effectivePrompt.isEmpty {
            let prompt = effectivePrompt
            promptCString = strdup(prompt)
        } else {
            promptCString = nil
        }
        params.language = UnsafePointer(languageCString)
        params.initial_prompt = promptCString.map { UnsafePointer($0) }
        params.n_threads = Int32(max(2, min(preview ? 6 : 8, ProcessInfo.processInfo.activeProcessorCount)))
        params.print_realtime = false
        params.print_progress = false
        params.print_timestamps = false
        params.print_special = false
        params.token_timestamps = true   // 开 token 级时间戳(DTW 对齐需要)
        // 抑制非语音 token(训练数据里的 [Music]/(Applause)/"AUDIO OUT" 等事件标注,
        // 在静音/噪声/片头音乐上容易被幻觉出来)
        params.suppress_nst = true
        // 防吞字：放宽静音/低置信判定，允许温度回退重试（whisper-demo 验证值）
        params.no_speech_thold = 0.4
        params.logprob_thold = -1.0
        params.temperature = 0.0
        params.temperature_inc = 0.2

        let flagPointer = Unmanaged.passUnretained(cancellationFlag).toOpaque()
        params.abort_callback = { userData in
            guard let userData else { return false }
            return Unmanaged<CancellationFlag>.fromOpaque(userData)
                .takeUnretainedValue()
                .isCancelled
        }
        params.abort_callback_user_data = flagPointer
        params.progress_callback = { _, _, progress, userData in
            guard let userData else { return }
            Unmanaged<CancellationFlag>.fromOpaque(userData)
                .takeUnretainedValue().report(progress)
        }
        params.progress_callback_user_data = flagPointer

        let result = samples.withUnsafeBufferPointer { buffer in
            whisper_full(context, params, buffer.baseAddress, Int32(buffer.count))
        }
        guard !cancellationFlag.isCancelled else { throw WhisperCaptionError.cancelled }
        guard result == 0 else {
            throw WhisperCaptionError.transcriptionFailed("whisper_full 返回错误码 \(result)")
        }

        let segmentCount = Int(whisper_full_n_segments(context))
        var segments: [WhisperCaptionSegment] = []
        for index in 0 ..< segmentCount {
            guard let textPointer = whisper_full_get_segment_text(context, Int32(index)) else { continue }
            let text = String(cString: textPointer)
                .trimmingCharacters(in: .whitespacesAndNewlines)
            guard !text.isEmpty else { continue }
            // 过滤幻觉出的非语音标注("AUDIO OUT"、"[Music]"、"(Applause)" 等):
            // suppress_nst 不能全挡住,这里用 no_speech 概率 + 文本特征兜底
            let noSpeechProb = whisper_full_get_segment_no_speech_prob(context, Int32(index))
            // no_speech_thold affects decoder fallback but does not guarantee
            // that whisper_full emits no segment. Reject its high-confidence
            // silence result before it reaches the live transcript.
            if preview, noSpeechProb >= 0.72 { continue }
            if Self.isHallucinatedNonSpeech(text: text, noSpeechProb: noSpeechProb) { continue }
            // 兜底:整段是 initial_prompt 的回显(prompt 幻觉,全角标点 prompt 曾触发)则丢弃
            if Self.isPromptEcho(text: text, prompt: effectivePrompt, noSpeechProb: noSpeechProb) { continue }
            // 句段文本是解码器给出的稳定结果。不要为了词级时间戳把中文再次拆成
            // UTF-8 token 后重组；异常 token 对齐会污染正文，但句段时间戳不受影响。
            segments.append(WhisperCaptionSegment(
                startMs: Double(whisper_full_get_segment_t0(context, Int32(index))) * 10,
                endMs: Double(whisper_full_get_segment_t1(context, Int32(index))) * 10,
                text: text
            ))
        }
        return segments
    }

    /// 与 FocusCaptureDaxia `speechActivityWindows` 相同的 20 ms 动态门限，
    /// 用在已经过 DeepFilterNet 的准实时音频块上。
    static func containsSpeech(samples16k samples: [Float]) -> Bool {
        let frameSize = 320
        guard samples.count >= frameSize else { return false }
        var frameRMS: [Float] = []
        frameRMS.reserveCapacity(samples.count / frameSize)
        for start in stride(from: 0, through: samples.count - frameSize, by: frameSize) {
            var sum: Float = 0
            for sample in samples[start ..< start + frameSize] {
                sum += sample * sample
            }
            frameRMS.append(sqrt(sum / Float(frameSize)))
        }
        let sorted = frameRMS.sorted()
        let noiseFloor = sorted[min(sorted.count - 1, sorted.count / 5)]
        let speechLevel = sorted[min(sorted.count - 1, sorted.count * 9 / 10)]
        guard speechLevel >= 0.0025 else { return false }
        let threshold = max(0.0025, noiseFloor * 2.6, speechLevel * 0.12)
        var consecutive = 0
        for rms in frameRMS {
            if rms >= threshold {
                consecutive += 1
                // FocusCapture 的 activity window 是 20 ms；实时场景要求至少
                // 连续 60 ms，避免单个碰撞声被当作一句话。
                if consecutive >= 3 { return true }
            } else {
                consecutive = 0
            }
        }
        return false
    }

    /// 把一个 whisper 段拆成 token 级条目,时间取 DTW 对齐的 t_dtw(10ms 单位)。
    ///
    /// 两个细节:
    /// - 中文存在字节级 token,一个字会被拆成多个 UTF-8 碎片(直接 String(cString:)
    ///   会变成乱码),必须按字节累积、拼成完整 UTF-8 序列再输出,时间取首个碎片的
    /// - t_dtw 失败时(-1 或倒退)回退到 whisper 原生 token t0,再退到段起点
    private func extractTokens(context: OpaquePointer, segment index: Int32) -> [WhisperCaptionSegment] {
        let segmentStartMs = Double(whisper_full_get_segment_t0(context, index)) * 10
        let segmentEndMs = Double(whisper_full_get_segment_t1(context, index)) * 10
        let eot = whisper_token_eot(context)
        let tokenCount = Int(whisper_full_n_tokens(context, index))

        // 先收集 (文本字节, 时间) 序列
        var rawTokens: [(bytes: [UInt8], startMs: Double)] = []
        rawTokens.reserveCapacity(tokenCount)
        var lastValidMs = segmentStartMs
        for tokenIndex in 0 ..< tokenCount {
            let data = whisper_full_get_token_data(context, index, Int32(tokenIndex))
            guard data.id < eot else { continue } // 跳过特殊 token
            guard let textPointer = whisper_full_get_token_text(context, index, Int32(tokenIndex)) else { continue }
            var bytes: [UInt8] = []
            var pointer = textPointer
            while pointer.pointee != 0 {
                bytes.append(UInt8(bitPattern: pointer.pointee))
                pointer += 1
            }
            guard !bytes.isEmpty else { continue }
            // t_dtw 单位 10ms;-1 表示该 token 未对齐
            var startMs = Double(data.t_dtw) * 10
            if data.t_dtw < 0 || startMs < lastValidMs - 500 {
                startMs = Double(whisper_full_get_token_t0(context, index, Int32(tokenIndex))) * 10
            }
            if startMs < 0 || startMs < lastValidMs - 500 {
                startMs = lastValidMs
            }
            lastValidMs = startMs
            rawTokens.append((bytes, startMs))
        }
        guard !rawTokens.isEmpty else { return [] }

        // 合并 UTF-8 碎片并生成 token 级条目;endMs 取下一个 token 的起点
        var result: [WhisperCaptionSegment] = []
        result.reserveCapacity(rawTokens.count)
        var pendingBytes: [UInt8] = []
        var pendingStartMs = rawTokens[0].startMs
        for (tokenIndex, raw) in rawTokens.enumerated() {
            if pendingBytes.isEmpty { pendingStartMs = raw.startMs }
            pendingBytes.append(contentsOf: raw.bytes)
            guard let text = String(bytes: pendingBytes, encoding: .utf8) else {
                continue // UTF-8 序列还不完整,等后续碎片
            }
            pendingBytes.removeAll()
            let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { continue }
            let nextStartMs = tokenIndex + 1 < rawTokens.count ? rawTokens[tokenIndex + 1].startMs : segmentEndMs
            result.append(WhisperCaptionSegment(
                startMs: pendingStartMs,
                endMs: max(pendingStartMs + 10, nextStartMs),
                text: trimmed
            ))
        }
        return result
    }

    /// 判断整段是否为 initial_prompt 的回显(prompt 幻觉)。
    /// 两个条件同时满足才过滤,避免误伤真实念出产品名的语音:
    /// - 段文本(去标点/空白)与 prompt 存在 ≥6 字连续重合(回显会复述 prompt 措辞,
    ///   甚至乱序拼接,如"字幕录制教程旁白")
    /// - 模型自评 no_speech_prob 高(回显段多出现在静音区,真实语音该值很低)
    static func isPromptEcho(text: String, prompt: String?, noSpeechProb: Float) -> Bool {
        guard let prompt, text.count <= 40, noSpeechProb > 0.4 else { return false }
        let strip: (String) -> String = { string in
            String(string.unicodeScalars.filter { scalar in
                CharacterSet.alphanumerics.contains(scalar)
                    || (0x3400 ... 0x9FFF).contains(scalar.value)
            })
        }
        let strippedText = Array(strip(text))
        guard strippedText.count >= 6 else { return false }
        let strippedPrompt = strip(prompt)
        // 滑动窗口:任意连续 6 字出现在 prompt 中即视为回显
        for start in 0 ... (strippedText.count - 6) {
            let window = String(strippedText[start ..< start + 6])
            if strippedPrompt.contains(window) { return true }
        }
        return false
    }

    /// 已知的非语音事件标注幻觉文本(去掉括号/标点、统一大写后比较)。
    private static let hallucinatedNonSpeechTexts: Set<String> = [
        "AUDIO OUT", "AUDIO IN", "AUDIO", "MUSIC", "NOISE", "SILENCE",
        "APPLAUSE", "LAUGHTER", "BLANK AUDIO", "BLANKAUDIO", "STATIC",
        "BACKGROUND MUSIC", "MUSIC PLAYING", "SOUND", "BEEP", "CLICK",
    ]

    /// 判断一段文本是否为幻觉出的非语音标注:
    /// - 已知事件标注词表命中,且模型认为该段大概率不是语音(no_speech_prob > 0.3)
    /// - 或整段是括号包裹的标注样式([Music]、(Applause)),直接过滤
    static func isHallucinatedNonSpeech(text: String, noSpeechProb: Float) -> Bool {
        let stripped = text
            .trimmingCharacters(in: CharacterSet(charactersIn: "[](){}<>【】().,!?、。,!? "))
            .uppercased()
        if hallucinatedNonSpeechTexts.contains(stripped) {
            return true
        }
        // 括号/方括号整段包裹的短标注,典型的事件标注样式
        let isBracketed = (text.hasPrefix("[") && text.hasSuffix("]"))
            || (text.hasPrefix("(") && text.hasSuffix(")"))
            || (text.hasPrefix("【") && text.hasSuffix("】"))
        if isBracketed, text.count <= 24 {
            return true
        }
        // 全大写拉丁短词 + 模型判定大概率非语音,如片头幻觉出的 "AUDIO OUT XXX"
        let latinLetters = text.unicodeScalars.filter { CharacterSet.letters.contains($0) }
        let isAllCapsLatin = !latinLetters.isEmpty
            && latinLetters.allSatisfy { !CharacterSet.lowercaseLetters.contains($0) }
            && !text.unicodeScalars.contains { (0x3400 ... 0x9FFF).contains($0.value) }
        if isAllCapsLatin, text.count <= 24, noSpeechProb > 0.5 {
            return true
        }
        return false
    }

    /// 读取 WAV 为 16kHz 单声道 Float32 采样；格式不符时用 AVAudioConverter 转换。
    func decodeSamples(from url: URL) throws -> [Float] {
        let file: AVAudioFile
        do {
            file = try AVAudioFile(forReading: url)
        } catch {
            throw WhisperCaptionError.audioReadFailed(error.localizedDescription)
        }
        guard file.length > 0 else {
            throw WhisperCaptionError.audioReadFailed("音频文件为空")
        }

        let inputFormat = file.processingFormat
        guard let outputFormat = AVAudioFormat(
            commonFormat: .pcmFormatFloat32,
            sampleRate: 16_000,
            channels: 1,
            interleaved: false
        ) else {
            throw WhisperCaptionError.audioReadFailed("无法创建 16kHz 单声道音频格式")
        }

        let needsConversion = inputFormat.commonFormat != .pcmFormatFloat32
            || inputFormat.sampleRate != 16_000
            || inputFormat.channelCount != 1
        let chunkCapacity: AVAudioFrameCount = 32_768
        if !needsConversion {
            var samples: [Float] = []
            samples.reserveCapacity(Int(file.length))
            while file.framePosition < file.length {
                guard let buffer = AVAudioPCMBuffer(pcmFormat: inputFormat, frameCapacity: chunkCapacity) else {
                    throw WhisperCaptionError.audioReadFailed("无法创建音频读取缓冲区")
                }
                try file.read(into: buffer)
                guard let channel = buffer.floatChannelData?[0], buffer.frameLength > 0 else { break }
                samples.append(contentsOf: UnsafeBufferPointer(start: channel, count: Int(buffer.frameLength)))
            }
            return samples
        }

        guard let converter = AVAudioConverter(from: inputFormat, to: outputFormat) else {
            throw WhisperCaptionError.audioReadFailed("无法创建音频格式转换器")
        }
        var samples: [Float] = []
        samples.reserveCapacity(Int(Double(file.length) * 16_000 / max(1, inputFormat.sampleRate)))
        var reachedEnd = false
        var conversionError: NSError?
        // Never capture or mutate conversionError inside the input block:
        // AVAudioConverter holds an exclusive inout access to it while invoking
        // the block, and doing so traps at runtime on physical devices.
        var inputReadError: Error?
        repeat {
            guard let outputBuffer = AVAudioPCMBuffer(pcmFormat: outputFormat, frameCapacity: chunkCapacity) else {
                throw WhisperCaptionError.audioReadFailed("无法创建音频输出缓冲区")
            }
            let status = converter.convert(to: outputBuffer, error: &conversionError) { requested, outStatus in
                guard !reachedEnd else {
                    outStatus.pointee = .endOfStream
                    return nil
                }
                guard let inputBuffer = AVAudioPCMBuffer(pcmFormat: inputFormat, frameCapacity: requested) else {
                    outStatus.pointee = .noDataNow
                    return nil
                }
                do {
                    // AVAudioFile may throw an unhelpful Cocoa error when an AAC
                    // read asks for more frames than remain at the end of a short
                    // recording. Clamp every converter request to the exact
                    // remaining frame count.
                    let remaining = file.length - file.framePosition
                    guard remaining > 0 else {
                        reachedEnd = true
                        outStatus.pointee = .endOfStream
                        return nil
                    }
                    try file.read(
                        into: inputBuffer,
                        frameCount: min(requested, AVAudioFrameCount(remaining))
                    )
                } catch {
                    inputReadError = WhisperCaptionError.audioReadFailed(
                        "读取尾段失败（位置 \(file.framePosition)/\(file.length)）：\(error.localizedDescription)"
                    )
                    reachedEnd = true
                    outStatus.pointee = .endOfStream
                    return nil
                }
                if inputBuffer.frameLength == 0 {
                    reachedEnd = true
                    outStatus.pointee = .endOfStream
                    return nil
                }
                outStatus.pointee = .haveData
                return inputBuffer
            }
            if let channel = outputBuffer.floatChannelData?[0], outputBuffer.frameLength > 0 {
                samples.append(contentsOf: UnsafeBufferPointer(start: channel, count: Int(outputBuffer.frameLength)))
            }
            if status == .endOfStream { reachedEnd = true }
        } while !reachedEnd
        if let inputReadError {
            if let captionError = inputReadError as? WhisperCaptionError {
                throw captionError
            }
            throw WhisperCaptionError.audioReadFailed(inputReadError.localizedDescription)
        }
        if let conversionError {
            throw WhisperCaptionError.audioReadFailed(conversionError.localizedDescription)
        }
        guard !samples.isEmpty else {
            throw WhisperCaptionError.audioReadFailed("音频格式转换结果为空")
        }
        return samples
    }
}
