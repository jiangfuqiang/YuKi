import Foundation
import SwiftData

@MainActor
final class ChatViewModel: ObservableObject {
    @Published var messages: [Message] = []
    @Published var isThinking = false
    @Published var showsEnd = false
    @Published var elapsedSeconds = 0
    @Published var draft = ""
    @Published var errorMessage: String?
    @Published private(set) var isStartingRecording = false

    let recorder = AudioRecorder()
    private let transcriber: SpeechTranscribing
    private let llm: LocalLLMResponding
    private let tts: SpeechSynthesizing
    private var timer: Timer?
    private(set) var session: ChatSession?
    private var context: ModelContext?
    private var responseTask: Task<Void, Never>?

    init(transcriber: SpeechTranscribing = WhisperKitAdapter(), llm: LocalLLMResponding = LocalLLMAdapter(), tts: SpeechSynthesizing = SystemTTSService()) {
        self.transcriber = transcriber
        self.llm = llm
        self.tts = tts
    }

    func begin(scene: Scene, buddy: Buddy?, context: ModelContext) {
        guard session == nil else { return }
        self.context = context
        let newSession = ChatSession(sceneId: scene.id)
        context.insert(newSession)
        session = newSession
        timer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.elapsedSeconds += 1 }
        }
        let welcome = Self.welcomeMessage(language: scene.language)
        add(role: .assistant, content: welcome)
    }

    func toggleRecording(scene: Scene, buddy: Buddy?) {
        guard !isThinking, !isStartingRecording else { return }
        if recorder.isRecording {
            guard let url = recorder.stop() else { return }
            responseTask = Task { await processAudio(url, scene: scene, buddy: buddy) }
        } else {
            // Starting to record must cut off any AI reply still being spoken,
            // otherwise TTS leaks into the microphone and pollutes transcription.
            tts.stop()
            isStartingRecording = true
            responseTask = Task {
                defer { isStartingRecording = false }
                guard await AudioRecorder.requestPermission() else {
                    errorMessage = "没有麦克风权限。请在系统设置中允许“YuKi”访问麦克风。"
                    return
                }
                do { try Task.checkCancellation() }
                catch { return }
                do { try recorder.start() }
                catch { errorMessage = error.localizedDescription }
            }
        }
    }

    func sendText(scene: Scene, buddy: Buddy?) {
        let text = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        draft = ""
        guard !isThinking else { return }
        responseTask = Task { await process(text, audioPath: nil, scene: scene, buddy: buddy) }
    }

    func end(scene: Scene) {
        responseTask?.cancel()
        isStartingRecording = false
        if recorder.isRecording, let abandonedURL = recorder.stop() {
            try? FileManager.default.removeItem(at: abandonedURL)
        }
        timer?.invalidate()
        session?.endedAt = .now
        session?.isEnded = true
        scene.lastChatTime = .now
        try? context?.save()
        showsEnd = true
    }

    func leaveWithoutSummary(scene: Scene) {
        responseTask?.cancel()
        isStartingRecording = false
        if recorder.isRecording, let abandonedURL = recorder.stop() {
            try? FileManager.default.removeItem(at: abandonedURL)
        }
        timer?.invalidate()
        session?.endedAt = .now
        session?.isEnded = true
        scene.lastChatTime = .now
        try? context?.save()
    }

    func resume(scene: Scene) {
        session?.isEnded = false
        session?.endedAt = nil
        scene.lastChatTime = .now
        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.elapsedSeconds += 1 }
        }
        try? context?.save()
        showsEnd = false
    }

    private func processAudio(_ url: URL, scene: Scene, buddy: Buddy?) async {
        isThinking = true
        do {
            // Qwen and Whisper are both large GGML models. Keep peak memory
            // bounded by unloading Qwen before speech recognition; Whisper is
            // released by its adapter before Qwen is loaded again.
            await QwenLocalEngine.shared.releaseModel()
            let text = try await transcriber.transcribe(audioURL: url, language: scene.language)
            try Task.checkCancellation()
            guard !text.isEmpty else {
                isThinking = false
                try? FileManager.default.removeItem(at: url)
                errorMessage = "没有识别到清晰语音，请靠近麦克风后重试。"
                return
            }
            let keepAudio = UserDefaults.standard.object(forKey: "keepAudio") == nil || UserDefaults.standard.bool(forKey: "keepAudio")
            let audioPath = keepAudio ? url.path : nil
            if !keepAudio { try? FileManager.default.removeItem(at: url) }
            await process(text, audioPath: audioPath, scene: scene, buddy: buddy)
        } catch is CancellationError {
            isThinking = false
            try? FileManager.default.removeItem(at: url)
        } catch {
            isThinking = false
            try? FileManager.default.removeItem(at: url)
            errorMessage = error.localizedDescription
        }
    }

    private func process(_ text: String, audioPath: String?, scene: Scene, buddy: Buddy?) async {
        add(role: .user, content: text, audioPath: audioPath)
        isThinking = true
        do {
            try Task.checkCancellation()
            let recentMessages = messages.dropLast().suffix(10).map {
                DialogueTurn(role: $0.role, content: $0.content)
            }
            let sceneContext = SceneContext(name: scene.name, language: scene.language, description: scene.sceneDescription,
                                            buddyName: buddy?.name ?? "AI 搭子",
                                            relationship: buddy?.relationship ?? .friend,
                                            personality: buddy?.personality ?? "友好",
                                            correctionLevel: buddy?.correctionLevel ?? .moderate,
                                            recentMessages: Array(recentMessages),
                                            flow: scene.sceneFlow ?? "",
                                            userRole: scene.userRole ?? "",
                                            aiRole: scene.aiRole ?? "",
                                            level: scene.level ?? "",
                                            goals: scene.goals ?? "",
                                            recentMistakes: recentMistakes(for: scene),
                                            grammarHints: GrammarHintEngine.hints(for: text, language: scene.language))
            let response = try await llm.respond(to: text, scene: sceneContext)
            try Task.checkCancellation()
            add(role: .assistant, content: response.content, correction: response.correction)
            isThinking = false
            let defaults = UserDefaults.standard
            let shouldSpeak = defaults.object(forKey: "autoTTS") == nil || defaults.bool(forKey: "autoTTS")
            if shouldSpeak { await tts.speak(response.content, language: scene.language) }
        } catch is CancellationError {
            isThinking = false
        } catch {
            isThinking = false
            errorMessage = "AI 搭子暂时无法回应：\(error.localizedDescription)"
        }
    }

    private func add(role: MessageRole, content: String, audioPath: String? = nil, correction: String? = nil) {
        guard let session, let context else { return }
        let message = Message(sessionId: session.id, role: role, content: content, audioPath: audioPath, correction: correction)
        context.insert(message)
        messages.append(message)
        try? context.save()
    }

    /// The learner's recent recurring mistakes in this scene ("原句→更好的表达"),
    /// newest first, deduplicated. Fed back into the system prompt so the buddy
    /// can naturally create opportunities to practice exactly these points.
    private func recentMistakes(for scene: Scene) -> [String] {
        guard let context else { return [] }
        let sceneId = scene.id
        let sessionDescriptor = FetchDescriptor<ChatSession>(predicate: #Predicate { $0.sceneId == sceneId })
        let sessionIds = Set(((try? context.fetch(sessionDescriptor)) ?? []).map(\.id))
        guard !sessionIds.isEmpty else { return [] }
        var messageDescriptor = FetchDescriptor<Message>(sortBy: [SortDescriptor(\.timestamp, order: .reverse)])
        messageDescriptor.fetchLimit = 100
        let recentMessages = (try? context.fetch(messageDescriptor)) ?? []
        var seen = Set<String>()
        var mistakes: [String] = []
        for message in recentMessages where sessionIds.contains(message.sessionId) {
            guard let correction = message.correction,
                  !correction.isEmpty,
                  seen.insert(correction).inserted else { continue }
            mistakes.append(correction)
            if mistakes.count == 5 { break }
        }
        return mistakes
    }

    private static func welcomeMessage(language: String) -> String {
        switch language {
        case "日本語": "こんにちは！今日はどんなことを話しましょうか？"
        case "한국어": "안녕하세요! 오늘은 어떤 이야기를 나눠 볼까요?"
        case "中文": "你好！今天想聊些什么？"
        case "Français": "Bonjour ! De quoi aimerais-tu parler aujourd’hui ?"
        case "Español": "¡Hola! ¿De qué te gustaría hablar hoy?"
        default: "Hi! What would you like to talk about today?"
        }
    }
}
