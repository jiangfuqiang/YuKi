import AVFoundation
import Foundation

protocol SpeechTranscribing: Sendable {
    func transcribe(audioURL: URL, language: String) async throws -> String
}

protocol LocalLLMResponding: Sendable {
    func respond(to text: String, scene: SceneContext) async throws -> AIResponse
}

protocol SpeechSynthesizing: Sendable {
    func speak(_ text: String, language: String, voiceIdentifier: String?, preset: VoicePreset) async
    func stop()
}

/// Lists the system voices installed on device for a given scene language.
/// Users can download higher-quality voices in iOS Settings; those show up
/// here automatically with an "增强" marker.
enum VoiceCatalog {
    struct Voice: Identifiable, Sendable {
        let id: String
        let name: String
        let isEnhancedQuality: Bool
    }

    static func voices(for language: String) -> [Voice] {
        let locale = SystemTTSService.locale(for: language)
        let exact = AVSpeechSynthesisVoice.speechVoices().filter { $0.language == locale }
        let candidates = exact.isEmpty
            ? AVSpeechSynthesisVoice.speechVoices().filter { $0.language.hasPrefix(locale.prefix(2)) }
            : exact
        return candidates.map {
            Voice(id: $0.identifier, name: $0.name,
                  isEnhancedQuality: $0.quality == .enhanced || $0.quality == .premium)
        }
    }
}

struct SceneContext: Sendable {
    let name: String
    let language: String
    let description: String
    let buddyName: String
    let relationship: BuddyRelationship
    let personality: String
    let correctionLevel: CorrectionLevel
    let recentMessages: [DialogueTurn]
    /// Optional scene flow ("打招呼 → 点饮料 → 结账"); empty when not set.
    let flow: String
    /// The user's role inside the scene; empty when not set.
    let userRole: String
    /// The role the buddy plays inside the scene; empty when not set.
    let aiRole: String
    /// SceneLevel raw value; empty when not specified.
    let level: String
    /// What the user wants to practice; empty when not set.
    let goals: String
    /// Recent recurring mistakes from earlier sessions ("原句→更好的表达").
    let recentMistakes: [String]
    /// Deterministic grammar hints produced on-device for the current input.
    let grammarHints: [String]
}

struct DialogueTurn: Sendable {
    let role: MessageRole
    let content: String
}

struct AIResponse: Sendable {
    let content: String
    let correction: String?
}

struct WhisperKitAdapter: SpeechTranscribing {
    func transcribe(audioURL: URL, language: String) async throws -> String {
        let whisperLanguage = Self.whisperLanguage(for: language)
        let defaults = UserDefaults.standard
        let denoiseEnabled = defaults.object(forKey: "denoiseEnabled") == nil || defaults.bool(forKey: "denoiseEnabled")

        let segments: [WhisperCaptionSegment]
        do {
            if denoiseEnabled,
               let output = try await VoiceDenoiseProcessor.processMicrophoneTrack(
                    of: AVURLAsset(url: audioURL),
                    settings: VoiceDenoiseSettings(strength: .standard)
               ) {
                defer { try? FileManager.default.removeItem(at: output.playbackURL) }
                segments = try await WhisperCaptionTranscriber.shared.transcribe(
                    samples16k: output.transcriptionSamples16k,
                    language: whisperLanguage,
                    progress: { _ in }
                )
            } else {
                segments = try await WhisperCaptionTranscriber.shared.transcribe(
                    wavURL: audioURL,
                    language: whisperLanguage
                )
            }
        } catch {
            await WhisperCaptionTranscriber.shared.releaseModel()
            throw error
        }
        await WhisperCaptionTranscriber.shared.releaseModel()
        return segments.map(\.text).joined(separator: " ").trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func whisperLanguage(for language: String) -> WhisperCaptionLanguage {
        switch language {
        case "日本語": .japanese
        case "한국어": .korean
        case "中文": .simplifiedChinese
        case "Français": .french
        case "Español": .spanish
        default: .englishUS
        }
    }
}

struct LocalLLMAdapter: LocalLLMResponding {
    func respond(to text: String, scene: SceneContext) async throws -> AIResponse {
        let prompt = Self.prompt(for: text, scene: scene)
        // The C++ inference call is intentionally started from a detached task.
        // An unbound Swift actor may otherwise begin executing on the caller's
        // main-actor thread and keep UIKit's event loop busy for the full turn.
        let raw = try await Self.generateWithTimeout(prompt: prompt)
        return try Self.parse(raw, language: scene.language)
    }

    /// Covers the complete user-visible operation, including lazy model load,
    /// prompt decoding and token generation. The llama.cpp call is blocking, so
    /// an unstructured worker is used to let the UI recover at the deadline even
    /// when the native call has not returned yet.
    private static func generateWithTimeout(prompt: String) async throws -> String {
        try await withCheckedThrowingContinuation { continuation in
            let gate = LLMCompletionGate(continuation: continuation)
            // Leave a small presentation margin so the error is visible before
            // the product's 60-second user-facing deadline expires.
            gate.scheduleTimeout(after: 58)
            Task.detached(priority: .userInitiated) {
                do {
                    let response = try await QwenLocalEngine.shared.generate(prompt: prompt)
                    gate.resume(with: .success(response))
                } catch {
                    gate.resume(with: .failure(error))
                }
            }
        }
    }

    private static func prompt(for text: String, scene: SceneContext) -> String {
        let correctionInstruction: String
        switch scene.correctionLevel {
        case .light:
            correctionInstruction = "不纠正用户表达，不要输出[[correction]]标记。"
        case .moderate:
            correctionInstruction = "本轮有明显表达问题时，记录最值得注意的一处。"
        case .detailed:
            correctionInstruction = "本轮有值得改进的表达时，记录最值得改进的一处。"
        }

        var guidance = ""
        if !scene.aiRole.isEmpty || !scene.userRole.isEmpty {
            let ai = scene.aiRole.isEmpty ? "聊天搭子" : scene.aiRole
            let user = scene.userRole.isEmpty ? "用户自己" : scene.userRole
            guidance += "在本场景中，你扮演\(ai)，用户扮演\(user)，全程保持这个角色设定。\n"
        }
        if let level = SceneLevel(rawValue: scene.level) {
            guidance += "用户的\(scene.language)水平约为\(level.rawValue)（\(level.title)）。用词、句长和话题深度都要匹配这个水平。\n"
        }
        if !scene.goals.isEmpty {
            guidance += "用户想重点练习：\(scene.goals)。在对话中自然创造相关的练习机会。\n"
        }
        if !scene.flow.isEmpty {
            guidance += "场景流程参考：\(scene.flow)。跟随对话进度自然推进流程。\n"
        }
        if !scene.recentMistakes.isEmpty {
            guidance += "用户最近的常见表达问题：\(scene.recentMistakes.joined(separator: "；"))。在自然对话中创造机会让用户再次练习这些表达，但不要提及你在刻意复习。\n"
        }
        let system = """
        <|im_start|>system
        你是\(scene.buddyName)，用户的\(scene.relationship.title)和私人聊天搭子，性格\(scene.personality)。
        场景资料：“\(scene.name)”；\(scene.description.isEmpty ? "自由聊天。" : scene.description) 场景资料只用于理解，绝不向用户复述。
        这是沉浸式真实对话，不是语言课程。先结合场景和最近对话理解用户此刻真正想做什么；如果用户让你扮演某个角色或帮他做某件事，立即进入该角色并配合。
        必须记住并遵守对话里已经确认的每项事实、偏好和选择，不遗漏、不冲突，也不要再次询问已经回答过的问题。直接回答用户最后一条消息中的实际问题，给出具体、可执行的回应，并自然推进一步。不要只回复“可以、不错、推荐试试”等空话，不安排课程或任务。只用\(scene.language)，通常回复2至3句。
        \(guidance)\(correctionInstruction) 如需记录，在回复末尾另起一行，只输出一行[[correction]]用户的原句→更自然的表达[[/correction]]，不要解释、不要换行、不要输出其他标记；纠错会由系统自动展示给用户，回复正文里不要提及或复述纠错内容。
        只输出给用户看的回复，不要JSON、Markdown、分析过程、说明、emoji、表情符号或颜文字。
        <|im_end|>
        """

        let history = scene.recentMessages.suffix(8).map { turn in
            let role = turn.role == .user ? "user" : "assistant"
            return "<|im_start|>\(role)\n\(sanitize(turn.content))<|im_end|>\n"
        }.joined()

        // Grammar hints ride inside the user turn (suffix side) so the system
        // prompt + history prefix stays byte-identical across turns, which is
        // what makes the bridge's KV-cache prefix reuse effective.
        var userContent = sanitize(text)
        if !scene.grammarHints.isEmpty {
            userContent += "\n（表达检测提示：\(scene.grammarHints.joined(separator: "；"))。若确认存在问题，按规则记录并自然示范正确说法。）"
        }

        return system + history + """
        <|im_start|>user
        \(userContent)<|im_end|>
        <|im_start|>assistant
        <think>

        </think>

        """
    }

    private static func sanitize(_ value: String) -> String {
        value.replacingOccurrences(of: "<|im_start|>", with: "")
            .replacingOccurrences(of: "<|im_end|>", with: "")
    }

    private static func parse(_ raw: String, language: String) throws -> AIResponse {
        var cleaned = raw
        if let start = cleaned.range(of: "<think>"), let end = cleaned.range(of: "</think>") {
            cleaned.removeSubrange(start.lowerBound..<end.upperBound)
        }
        // If generation ever runs past the reply, the model continues with new
        // chat turns; keep only the first assistant reply.
        for boundary in ["<|im_end|>", "<|im_start|>"] {
            if let range = cleaned.range(of: boundary) {
                cleaned.removeSubrange(range.lowerBound..<cleaned.endIndex)
            }
        }
        cleaned = cleaned.replacingOccurrences(of: "```json", with: "")
            .replacingOccurrences(of: "```", with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        cleaned = OutputTextSanitizer.removingEmoji(from: cleaned)
            .trimmingCharacters(in: .whitespacesAndNewlines)

        if let firstBrace = cleaned.firstIndex(of: "{"),
           let lastBrace = cleaned.lastIndex(of: "}") {
            let json = String(cleaned[firstBrace...lastBrace])
            if let data = json.data(using: .utf8),
               let payload = try? JSONDecoder().decode(QwenPayload.self, from: data),
               !payload.reply.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                let correction = payload.correction?.trimmingCharacters(in: .whitespacesAndNewlines)
                return AIResponse(
                    content: payload.reply.trimmingCharacters(in: .whitespacesAndNewlines),
                    correction: correction?.isEmpty == false ? correction : nil
                )
            }
        }

        if let markerStart = cleaned.range(of: "[[correction]]") {
            let reply = cleaned[..<markerStart.lowerBound]
                .trimmingCharacters(in: .whitespacesAndNewlines)
            var correction: String?
            if let markerEnd = cleaned.range(
                of: "[[/correction]]",
                range: markerStart.upperBound..<cleaned.endIndex
            ) {
                let text = cleaned[markerStart.upperBound..<markerEnd.lowerBound]
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                correction = text.isEmpty ? nil : text
            }
            // A small model often opens [[correction]] without ever emitting
            // the closing tag and then quotes the user's sentence with verbose
            // explanations. None of that is user-facing text: keep the reply,
            // drop everything after the opening marker.
            guard !reply.isEmpty else { throw QwenLocalEngineError.emptyResponse }
            return AIResponse(content: reply, correction: correction)
        }

        cleaned = cleaned.replacingOccurrences(of: "[[/correction]]", with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleaned.isEmpty else { throw QwenLocalEngineError.emptyResponse }
        return AIResponse(content: cleaned, correction: nil)
    }

    private struct QwenPayload: Decodable {
        let reply: String
        let correction: String?
    }
}

private final class LLMCompletionGate: @unchecked Sendable {
    private let lock = NSLock()
    private var continuation: CheckedContinuation<String, Error>?
    private var timeoutSource: DispatchSourceTimer?

    init(continuation: CheckedContinuation<String, Error>) {
        self.continuation = continuation
    }

    func scheduleTimeout(after seconds: TimeInterval) {
        let source = DispatchSource.makeTimerSource(
            queue: DispatchQueue(label: "com.localfirst.yuki.llm-timeout", qos: .userInteractive)
        )
        source.schedule(deadline: .now() + seconds, leeway: .milliseconds(50))
        source.setEventHandler { [weak self] in
            self?.resume(with: .failure(QwenLocalEngineError.timedOut))
        }
        lock.lock()
        guard continuation != nil else {
            lock.unlock()
            return
        }
        timeoutSource = source
        lock.unlock()
        source.activate()
    }

    func resume(with result: Result<String, Error>) {
        lock.lock()
        let pending = continuation
        let timeout = timeoutSource
        continuation = nil
        timeoutSource = nil
        lock.unlock()
        timeout?.cancel()
        pending?.resume(with: result)
    }
}

@MainActor
final class SystemTTSService: NSObject, SpeechSynthesizing, AVSpeechSynthesizerDelegate {
    static let shared = SystemTTSService()

    private let synthesizer = AVSpeechSynthesizer()
    private var utteranceContinuation: CheckedContinuation<Void, Never>?

    override init() {
        super.init()
        synthesizer.delegate = self
    }

    /// Awaits the utterance finishing (or being cancelled), so callers can
    /// keep an accurate "speaking" state for the UI.
    func speak(_ text: String, language: String, voiceIdentifier: String? = nil, preset: VoicePreset = .natural) async {
        let spokenText = Self.textForSpeech(from: text)
        guard !spokenText.isEmpty else { return }
        if synthesizer.isSpeaking || synthesizer.isPaused { synthesizer.stopSpeaking(at: .immediate) }
        let utterance = AVSpeechUtterance(string: spokenText)
        if let voiceIdentifier, let chosen = AVSpeechSynthesisVoice(identifier: voiceIdentifier) {
            utterance.voice = chosen
        } else {
            utterance.voice = AVSpeechSynthesisVoice(language: Self.locale(for: language))
        }
        utterance.rate = preset.rate
        utterance.pitchMultiplier = preset.pitch
        await withCheckedContinuation { continuation in
            utteranceContinuation = continuation
            synthesizer.speak(utterance)
        }
    }

    nonisolated func stop() {
        Task { @MainActor in
            synthesizer.stopSpeaking(at: .immediate)
            finishUtterance()
        }
    }

    private func finishUtterance() {
        let continuation = utteranceContinuation
        utteranceContinuation = nil
        continuation?.resume()
    }

    nonisolated func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didFinish utterance: AVSpeechUtterance) {
        Task { @MainActor in finishUtterance() }
    }

    nonisolated func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didCancel utterance: AVSpeechUtterance) {
        Task { @MainActor in finishUtterance() }
    }

    /// AVSpeechSynthesizer reads emoji accessibility names aloud (often in
    /// English), which sounds like unrelated text after an otherwise correct
    /// reply. Keep emoji in the chat bubble, but never send their Unicode
    /// presentation/sequence scalars to TTS.
    static func textForSpeech(from text: String) -> String {
        OutputTextSanitizer.removingEmoji(from: text)
            .split(whereSeparator: { $0.isWhitespace })
            .joined(separator: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    nonisolated static func locale(for language: String) -> String {
        switch language {
        case "日本語": "ja-JP"
        case "한국어": "ko-KR"
        case "中文": "zh-CN"
        case "Français": "fr-FR"
        case "Español": "es-ES"
        default: "en-US"
        }
    }
}

private enum OutputTextSanitizer {
    static func removingEmoji(from text: String) -> String {
        let filteredScalars = text.unicodeScalars.filter { scalar in
            let value = scalar.value
            if scalar.properties.isEmojiPresentation { return false }
            if scalar.properties.isEmoji && !scalar.isASCII { return false }
            if value == 0x200D || value == 0xFE0E || value == 0xFE0F || value == 0x20E3 { return false }
            if (0x1F3FB...0x1F3FF).contains(value) { return false }
            if (0x1F1E6...0x1F1FF).contains(value) { return false }
            return true
        }
        return String(String.UnicodeScalarView(filteredScalars))
    }
}

@MainActor
final class AudioRecorder: ObservableObject {
    @Published private(set) var isRecording = false
    @Published private(set) var level: CGFloat = 0
    private let engine = AVAudioEngine()
    private var file: AVAudioFile?
    private var outputURL: URL?
    private let levelMeter = AudioLevelMeter()
    private var levelTimer: Timer?

    static func requestPermission() async -> Bool {
        await withCheckedContinuation { continuation in
            AVAudioApplication.requestRecordPermission { granted in
                continuation.resume(returning: granted)
            }
        }
    }

    func start() throws {
        guard !isRecording, !engine.isRunning else {
            throw AudioRecorderError.alreadyRecording
        }
        let session = AVAudioSession.sharedInstance()
        try session.setCategory(.playAndRecord, mode: .spokenAudio, options: [.defaultToSpeaker, .allowBluetoothHFP])
        try session.setActive(true)

        let audioDirectory = try FileManager.default.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        ).appendingPathComponent("ChatAudio", isDirectory: true)
        try FileManager.default.createDirectory(at: audioDirectory, withIntermediateDirectories: true)
        let url = audioDirectory.appendingPathComponent("recording-\(UUID().uuidString).caf")
        let input = engine.inputNode
        let format = input.outputFormat(forBus: 0)
        guard format.sampleRate > 0, format.channelCount > 0 else {
            throw AudioRecorderError.inputUnavailable
        }
        // The audio tap executes on Core Audio's realtime queue. Capture the file
        // directly so that callback never reaches back into this @MainActor object.
        let recordingFile = try AVAudioFile(forWriting: url, settings: format.settings)
        let meter = levelMeter
        file = recordingFile
        outputURL = url
        // Construct the callback outside this @MainActor type. A closure literal
        // created here inherits main-actor isolation in Swift 6 even when it does
        // not capture `self`, which Core Audio correctly rejects at runtime.
        input.installTap(
            onBus: 0,
            bufferSize: 1024,
            format: format,
            block: makeRecorderTap(recordingFile: recordingFile, meter: meter)
        )
        engine.prepare()
        do {
            try engine.start()
        } catch {
            input.removeTap(onBus: 0)
            file = nil
            try? FileManager.default.removeItem(at: url)
            throw error
        }
        isRecording = true
        levelTimer?.invalidate()
        levelTimer = Timer.scheduledTimer(withTimeInterval: 0.05, repeats: true) { [weak self, meter] _ in
            let nextLevel = min(max(CGFloat(meter.load()) * 8, 0.08), 1)
            Task { @MainActor [weak self] in self?.level = nextLevel }
        }
    }

    func stop() -> URL? {
        levelTimer?.invalidate()
        levelTimer = nil
        engine.stop()
        engine.inputNode.removeTap(onBus: 0)
        isRecording = false
        level = 0
        file = nil
        let completedURL = outputURL
        outputURL = nil
        return completedURL
    }
}

/// Bridges scalar metering data from Core Audio's realtime callback without
/// allowing that callback to capture the main-actor recorder.
private final class AudioLevelMeter: @unchecked Sendable {
    private let lock = NSLock()
    private var value: Float = 0

    func store(_ newValue: Float) {
        lock.lock()
        value = newValue
        lock.unlock()
    }

    func load() -> Float {
        lock.lock()
        defer { lock.unlock() }
        return value
    }
}

private func makeRecorderTap(
    recordingFile: AVAudioFile,
    meter: AudioLevelMeter
) -> AVAudioNodeTapBlock {
    { buffer, _ in
        try? recordingFile.write(from: buffer)
        guard let data = buffer.floatChannelData?[0] else { return }
        let count = Int(buffer.frameLength)
        var sum: Float = 0
        for index in 0..<count { sum += data[index] * data[index] }
        meter.store(sqrt(sum / Float(max(count, 1))))
    }
}

enum AudioRecorderError: LocalizedError {
    case inputUnavailable
    case alreadyRecording

    var errorDescription: String? {
        switch self {
        case .inputUnavailable: "当前无法使用麦克风，请检查设备音频输入。"
        case .alreadyRecording: "录音已经开始，请稍后重试。"
        }
    }
}

@MainActor
final class AudioPlaybackService: NSObject, ObservableObject, AVAudioPlayerDelegate {
    @Published private(set) var playingPath: String?
    private var player: AVAudioPlayer?

    func toggle(path: String) {
        if playingPath == path {
            stop()
            return
        }
        do {
            let nextPlayer = try AVAudioPlayer(contentsOf: URL(fileURLWithPath: path))
            nextPlayer.delegate = self
            nextPlayer.prepareToPlay()
            nextPlayer.play()
            player = nextPlayer
            playingPath = path
        } catch {
            stop()
        }
    }

    func stop() {
        player?.stop()
        player = nil
        playingPath = nil
    }

    nonisolated func audioPlayerDidFinishPlaying(_ player: AVAudioPlayer, successfully flag: Bool) {
        Task { @MainActor in stop() }
    }
}
