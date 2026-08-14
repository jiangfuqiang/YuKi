import SwiftUI
import SwiftData

struct ProfileView: View {
    @Query private var scenes: [Scene]
    @Query private var sessions: [ChatSession]
    @Query private var messages: [Message]
    @State private var destination: SettingsDestination?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                HStack(spacing: 15) {
                    AvatarView(name: "Ling", size: 72)
                    VStack(alignment: .leading, spacing: 5) { Text("Ling").font(.system(size: 22, weight: .bold)); Text("专注口语练习").font(.caption).foregroundStyle(AppTheme.secondaryText) }
                }
                VStack(spacing: 0) {
                    statRow("场景总数", "\(scenes.count)")
                    Divider().overlay(AppTheme.separator)
                    statRow("本地对话", "\(sessions.count)")
                    Divider().overlay(AppTheme.separator)
                    statRow("消息数量", "\(messages.count)")
                }.appCard()
                VStack(spacing: 0) {
                    setting(.language, "character.bubble", "语言设置")
                    Divider().overlay(AppTheme.separator)
                    setting(.voice, "speaker.wave.2.fill", "语音设置")
                    Divider().overlay(AppTheme.separator)
                    setting(.models, "cpu", "模型管理")
                    Divider().overlay(AppTheme.separator)
                    setting(.privacy, "lock.fill", "隐私设置")
                    Divider().overlay(AppTheme.separator)
                    setting(.storage, "externaldrive.fill", "存储管理")
                }.appCard()
                Text("所有场景、录音和对话均保存在此设备。")
                    .font(.caption).foregroundStyle(AppTheme.secondaryText).frame(maxWidth: .infinity)
            }.padding(18)
        }
        .navigationBarHidden(true)
        .navigationDestination(item: $destination) { SettingsDetailView(destination: $0) }
        .appBackground()
    }

    private func statRow(_ name: String, _ value: String) -> some View {
        HStack { Text(name); Spacer(); Text(value).foregroundStyle(AppTheme.secondaryText) }.font(.system(size: 15)).padding(.horizontal, 17).frame(height: 56)
    }
    private func setting(_ item: SettingsDestination, _ icon: String, _ title: String) -> some View {
        Button { destination = item } label: { SettingsRow(icon: icon, title: title) }.buttonStyle(.plain)
    }
}

enum SettingsDestination: String, Identifiable {
    case language = "语言设置", voice = "语音设置", models = "模型管理", privacy = "隐私设置", storage = "存储管理"
    var id: String { rawValue }
}

struct SettingsDetailView: View {
    let destination: SettingsDestination
    @AppStorage("defaultSceneLanguage") private var defaultSceneLanguage = "日本語"
    @AppStorage("autoTTS") private var autoTTS = true
    @AppStorage("keepAudio") private var keepAudio = true
    @AppStorage("denoiseEnabled") private var denoiseEnabled = true
    @State private var storageUsage = "计算中…"

    var body: some View {
        Form {
            switch destination {
            case .language:
                Picker("新场景默认语言", selection: $defaultSceneLanguage) {
                    ForEach(["English", "日本語", "한국어", "中文", "Français", "Español"], id: \.self) { Text($0) }
                }
            case .voice:
                Toggle("自动播放 AI 回复", isOn: $autoTTS)
                Toggle("DeepFilterNet 降噪", isOn: $denoiseEnabled)
                Toggle("保留原始录音", isOn: $keepAudio)
                LabeledContent("录音引擎", value: "AVAudioEngine")
            case .models:
                LabeledContent("语音识别", value: "whisper.cpp · 252 MB")
                LabeledContent("人声降噪", value: "DeepFilterNet3 · 7.6 MB")
                LabeledContent("对话模型", value: "Qwen3.5 0.8B · Q4_K_M")
                LabeledContent("推理引擎", value: "llama.cpp · Metal")
                Label("模型已内置，可完全离线使用", systemImage: "checkmark.circle.fill")
                    .foregroundStyle(.green)
                Text("聊天时会读取场景、搭子设定、最近对话和纠错程度；所有推理均在本机完成。")
                    .font(.footnote).foregroundStyle(AppTheme.secondaryText)
            case .privacy:
                Label("数据不会上传到服务器", systemImage: "checkmark.shield.fill")
                Label("核心功能支持完全离线", systemImage: "wifi.slash")
            case .storage:
                LabeledContent("场景与对话", value: "本地 SwiftData")
                LabeledContent("本地数据占用", value: storageUsage)
                Text("当前版本不会自动删除你的聊天记录。").font(.footnote).foregroundStyle(AppTheme.secondaryText)
            }
        }
        .scrollContentBackground(.hidden)
        .navigationTitle(destination.rawValue)
        .task { if destination == .storage { storageUsage = Self.localStorageUsage() } }
        .appBackground()
    }

    private static func localStorageUsage() -> String {
        guard let support = try? FileManager.default.url(for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: false),
              let enumerator = FileManager.default.enumerator(at: support, includingPropertiesForKeys: [.fileSizeKey]) else { return "0 MB" }
        var bytes = 0
        for case let url as URL in enumerator {
            bytes += (try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0
        }
        return ByteCountFormatter.string(fromByteCount: Int64(bytes), countStyle: .file)
    }
}
