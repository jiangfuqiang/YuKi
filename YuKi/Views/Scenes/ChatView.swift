import SwiftUI
import SwiftData

struct ChatView: View {
    let scene: Scene
    let buddy: Buddy?
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context
    @StateObject private var model = ChatViewModel()
    @StateObject private var playback = AudioPlaybackService()
    @State private var showsLeaveConfirmation = false

    var body: some View {
        VStack(spacing: 0) {
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(spacing: 14) {
                        sceneContext
                        ForEach(model.messages) { message in
                            MessageBubble(message: message, buddyName: buddy?.name ?? "AI", playback: playback,
                                          isSpeaking: model.speakingMessageID == message.id,
                                          onToggleSpeech: message.role == .assistant ? { model.toggleReplyAudio(message, scene: scene, buddy: buddy) } : nil)
                                .id(message.id)
                                .transition(.opacity.combined(with: .move(edge: .bottom)))
                        }
                        if model.isThinking {
                            HStack(spacing: 8) {
                                Image(systemName: "ellipsis")
                                    .font(.caption.weight(.semibold))
                                    .foregroundStyle(AppTheme.purpleLight)
                                Text("正在回应…").font(.caption).foregroundStyle(AppTheme.secondaryText)
                                Spacer()
                            }
                                .padding(.horizontal, 8)
                                .accessibilityIdentifier("llm-thinking-indicator")
                        }
                    }.padding(16)
                }
                .onChange(of: model.messages.count) { _, _ in
                    if let last = model.messages.last { withAnimation { proxy.scrollTo(last.id, anchor: .bottom) } }
                }
            }

            VStack(spacing: 13) {
                HStack(spacing: 10) {
                    Group {
                        if model.recorder.isRecording {
                            RecordingLevelMeter(level: model.recorder.level)
                                .transition(.opacity)
                        } else {
                            TextField("输入文字…", text: $model.draft, axis: .vertical)
                                .lineLimit(1...3)
                                .padding(.horizontal, 15)
                                .accessibilityIdentifier("chat-text-field")
                                .transition(.opacity)
                        }
                    }
                    .frame(minHeight: 44)
                    .appCard(cornerRadius: 15)
                    .animation(.easeInOut(duration: 0.16), value: model.recorder.isRecording)
                    Button { model.sendText(scene: scene, buddy: buddy) } label: {
                        Image(systemName: "arrow.up").fontWeight(.bold).foregroundStyle(.white).frame(width: 42, height: 42).background(AppTheme.gradient, in: Circle())
                    }
                    .accessibilityIdentifier("send-text-button")
                    .disabled(model.recorder.isRecording || model.draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || model.isThinking)
                }
                HStack {
                    Spacer()
                    RecordButton(recorder: model.recorder, disabled: model.isThinking || model.isStartingRecording) {
                        if !model.recorder.isRecording { playback.stop() }
                        model.toggleRecording(scene: scene, buddy: buddy)
                    }
                    Spacer()
                }
                Text(model.recorder.isRecording ? "点击结束" : "点击或长按说话")
                    .font(.system(size: 11)).foregroundStyle(AppTheme.secondaryText)
            }
            .padding(.horizontal, 16).padding(.top, 12).padding(.bottom, 10)
            .background(AppTheme.background.overlay(alignment: .top) { Divider().opacity(0.12) })
        }
        .navigationTitle(scene.name)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarLeading) { Button { showsLeaveConfirmation = true } label: { Image(systemName: "chevron.left") } }
            ToolbarItem(placement: .principal) {
                VStack(spacing: 1) { Text(scene.name).font(.headline); Text(buddy?.name ?? "AI 搭子").font(.caption2).foregroundStyle(AppTheme.secondaryText) }
            }
            ToolbarItem(placement: .topBarTrailing) { Button("结束") { model.end(scene: scene) }.font(.subheadline) }
        }
        .onAppear { model.begin(scene: scene, buddy: buddy, context: context) }
        .interactiveDismissDisabled()
        .confirmationDialog("结束本次聊天？", isPresented: $showsLeaveConfirmation, titleVisibility: .visible) {
            Button("结束并返回", role: .destructive) {
                model.leaveWithoutSummary(scene: scene)
                dismiss()
            }
            Button("继续聊天", role: .cancel) {}
        } message: {
            Text("聊天记录会保存在本地。")
        }
        .alert("提示", isPresented: Binding(
            get: { model.errorMessage != nil },
            set: { if !$0 { model.errorMessage = nil } }
        )) {
            Button("好", role: .cancel) { model.errorMessage = nil }
        } message: {
            Text(model.errorMessage ?? "")
        }
        .fullScreenCover(isPresented: $model.showsEnd) {
            SessionEndView(scene: scene, messageCount: model.messages.count, elapsedSeconds: model.elapsedSeconds,
                           mistakes: sessionMistakes) {
                model.resume(scene: scene)
            } exit: { dismiss() }
        }
        .appBackground()
    }

    /// Corrections are collected silently during the chat and only surface here,
    /// capped by the buddy's correction level, so practice is never interrupted.
    private var sessionMistakes: [String] {
        let limit: Int
        switch buddy?.correctionLevel ?? .moderate {
        case .light: limit = 0
        case .moderate: limit = 2
        case .detailed: limit = 5
        }
        guard limit > 0 else { return [] }
        return Array(model.messages.compactMap(\.correction).filter { !$0.isEmpty }.prefix(limit))
    }

    private var sceneContext: some View {
        VStack(alignment: .leading, spacing: 7) {
            Text("场景背景").font(.caption).foregroundStyle(AppTheme.secondaryText)
            Text(scene.sceneDescription).font(.system(size: 13)).foregroundStyle(.white.opacity(0.72))
        }.padding(14).frame(maxWidth: .infinity, alignment: .leading).appCard(cornerRadius: 14)
    }
}

private struct RecordingLevelMeter: View {
    let level: CGFloat
    private let amplitudes: [CGFloat] = [0.35, 0.58, 0.82, 1, 0.72, 0.48, 0.3]

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "mic.fill")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(AppTheme.purpleLight)
            HStack(spacing: 4) {
                ForEach(amplitudes.indices, id: \.self) { index in
                    Capsule()
                        .fill(AppTheme.gradient)
                        .frame(width: 3, height: barHeight(at: index))
                }
            }
            .frame(height: 26)
            Text("正在聆听")
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(AppTheme.secondaryText)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 15)
        .frame(height: 44)
        .animation(.easeOut(duration: 0.1), value: level)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("麦克风电平")
        .accessibilityValue(level > 0.14 ? "正在收到声音" : "等待声音")
        .accessibilityIdentifier("recording-level-meter")
    }

    private func barHeight(at index: Int) -> CGFloat {
        let responsiveLevel = max(0.12, min(level, 1))
        let offset = CGFloat((index * 3) % 5) * 0.07
        return 5 + (responsiveLevel + offset) * 19 * amplitudes[index]
    }
}

private struct RecordButton: View {
    @ObservedObject var recorder: AudioRecorder
    let disabled: Bool
    let action: () -> Void
    @State private var pulse = false

    var body: some View {
        Button(action: action) {
            ZStack {
                if recorder.isRecording {
                    Circle().stroke(AppTheme.purpleLight.opacity(0.28), lineWidth: 3)
                        .frame(width: 80 + recorder.level * 30, height: 80 + recorder.level * 30)
                        .animation(.easeOut(duration: 0.12), value: recorder.level)
                    Circle().fill(AppTheme.purple.opacity(0.12)).frame(width: pulse ? 96 : 76, height: pulse ? 96 : 76).opacity(pulse ? 0 : 0.8)
                }
                Circle().fill(AppTheme.gradient).frame(width: 68, height: 68)
                    .shadow(color: AppTheme.purple.opacity(0.42), radius: 18)
                Image(systemName: recorder.isRecording ? "stop.fill" : "mic.fill")
                    .font(.system(size: 27, weight: .semibold)).foregroundStyle(.white)
            }
            // Meter-driven rings must not participate in layout. Without a
            // stable container their changing diameter moves the entire input
            // bar (including the text field) several times per second.
            .frame(width: 110, height: 110)
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("record-button")
        .disabled(disabled)
        .opacity(disabled ? 0.45 : 1)
        .onChange(of: recorder.isRecording) { _, recording in
            if recording { withAnimation(.easeOut(duration: 1).repeatForever(autoreverses: false)) { pulse = true } }
            else { pulse = false }
        }
        .simultaneousGesture(LongPressGesture(minimumDuration: 0.25).onEnded { _ in if !recorder.isRecording { action() } })
    }
}

/// Renders a structured correction "原句→更好的表达": the original struck
/// through and the suggestion emphasised. Falls back to plain text when the
/// model produced an unstructured correction.
private struct CorrectionView: View {
    let correction: String

    var body: some View {
        let parts = correction.components(separatedBy: "→").map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
        if parts.count == 2, !parts[0].isEmpty, !parts[1].isEmpty {
            VStack(alignment: .leading, spacing: 3) {
                Text(parts[0])
                    .font(.system(size: 12)).foregroundStyle(.white.opacity(0.45)).strikethrough()
                Text(parts[1])
                    .font(.system(size: 12, weight: .medium)).foregroundStyle(.white.opacity(0.85))
            }
        } else {
            Text(correction).font(.system(size: 12)).foregroundStyle(.white.opacity(0.7))
        }
    }
}

struct MessageBubble: View {
    let message: Message
    let buddyName: String
    @ObservedObject var playback: AudioPlaybackService
    /// Transcript/record views and the active chat both show corrections
    /// inline; the flag remains for surfaces that should stay clean.
    var showsCorrection = true
    /// Assistant-reply TTS replay; nil hides the button (e.g. transcripts).
    var isSpeaking = false
    var onToggleSpeech: (() -> Void)?

    var body: some View {
        HStack(alignment: .bottom, spacing: 9) {
            if message.role == .assistant { AvatarView(name: buddyName, size: 31) }
            if message.role == .user { Spacer(minLength: 48) }
            VStack(alignment: .leading, spacing: 8) {
                Text(message.content).font(.system(size: 15)).lineSpacing(3)
                if showsCorrection, let correction = message.correction {
                    Divider().overlay(Color.white.opacity(0.12))
                    HStack(alignment: .top, spacing: 6) {
                        Image(systemName: "sparkles").font(.caption).foregroundStyle(AppTheme.purpleLight)
                        CorrectionView(correction: correction)
                    }
                }
                HStack(spacing: 5) {
                    Text(message.timestamp.formatted(date: .omitted, time: .shortened)).font(.caption2).foregroundStyle(.white.opacity(0.34))
                    if let onToggleSpeech {
                        Button(action: onToggleSpeech) {
                            Image(systemName: isSpeaking ? "stop.circle.fill" : "speaker.wave.2.fill")
                                .font(.caption).foregroundStyle(.white.opacity(0.62))
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel(isSpeaking ? "停止朗读" : "朗读回复")
                    }
                    if let audioPath = message.audioPath {
                        Button { playback.toggle(path: audioPath) } label: {
                            Image(systemName: playback.playingPath == audioPath ? "stop.circle.fill" : "speaker.wave.2.fill")
                                .font(.caption).foregroundStyle(.white.opacity(0.62))
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel(playback.playingPath == audioPath ? "停止播放录音" : "播放原始录音")
                    }
                }
            }
            .padding(14)
            .background(message.role == .user ? AnyShapeStyle(LinearGradient(colors: [Color(hex: 0x302064), Color(hex: 0x211747)], startPoint: .topLeading, endPoint: .bottomTrailing)) : AnyShapeStyle(AppTheme.card), in: RoundedRectangle(cornerRadius: 17, style: .continuous))
            .accessibilityElement(children: .combine)
            .accessibilityIdentifier(message.role == .assistant ? "assistant-message" : "user-message")
            if message.role == .assistant { Spacer(minLength: 35) }
        }
    }
}
