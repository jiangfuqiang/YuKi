import SwiftUI
import SwiftData

struct BuddyEditorView: View {
    let buddy: Buddy?
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context
    @State private var name: String
    @State private var language: String
    @State private var relationship: BuddyRelationship
    @State private var personality: String
    @State private var correction: CorrectionLevel
    @State private var voiceIdentifier: String?
    @State private var voicePreset: VoicePreset

    init(buddy: Buddy?) {
        self.buddy = buddy
        _name = State(initialValue: buddy?.name ?? "")
        _language = State(initialValue: buddy?.language ?? "English")
        _relationship = State(initialValue: buddy?.relationship ?? .friend)
        _personality = State(initialValue: buddy?.personality ?? "友好、耐心")
        _correction = State(initialValue: buddy?.correctionLevel ?? .moderate)
        _voiceIdentifier = State(initialValue: buddy?.voiceIdentifier)
        _voicePreset = State(initialValue: buddy?.voicePreset ?? .natural)
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 22) {
                    AvatarView(name: name.isEmpty ? "AI" : name, size: 92, isOnline: true).padding(.vertical, 6)
                    field("名字") { TextField("搭子的名字", text: $name) }
                    field("语言") {
                        Picker("语言", selection: $language) {
                            ForEach(["English", "日本語", "한국어", "中文", "Français", "Español"], id: \.self) { Text($0).tag($0) }
                        }.pickerStyle(.menu).frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .onChange(of: language) { _, _ in voiceIdentifier = nil }
                    field("关系") { Picker("关系", selection: $relationship) { ForEach(BuddyRelationship.allCases) { Text($0.title).tag($0) } }.pickerStyle(.segmented) }
                    field("性格") { TextField("例如：友好、耐心", text: $personality) }
                    field("纠错程度") { Picker("纠错程度", selection: $correction) { ForEach(CorrectionLevel.allCases) { Text($0.title).tag($0) } }.pickerStyle(.segmented) }
                    field("声音") {
                        VStack(alignment: .leading, spacing: 10) {
                            Picker("声音", selection: $voiceIdentifier) {
                                Text("系统默认").tag(String?.none)
                                ForEach(VoiceCatalog.voices(for: language)) { voice in
                                    Text(voice.isEnhancedQuality ? "\(voice.name)（增强）" : voice.name).tag(Optional(voice.id))
                                }
                            }.pickerStyle(.menu).frame(maxWidth: .infinity, alignment: .leading)
                            Text("更多声音可在 系统设置 → 辅助功能 → 朗读内容 中下载。")
                                .font(.caption2).foregroundStyle(AppTheme.secondaryText)
                        }
                    }
                    field("声线") {
                        HStack(spacing: 10) {
                            Picker("声线", selection: $voicePreset) { ForEach(VoicePreset.allCases) { Text($0.title).tag($0) } }.pickerStyle(.segmented)
                            Button { Task { await SystemTTSService.shared.speak(Self.previewText(for: language), language: language, voiceIdentifier: voiceIdentifier, preset: voicePreset) } } label: {
                                Image(systemName: "play.circle.fill").font(.title2).foregroundStyle(AppTheme.purpleLight)
                            }
                            .buttonStyle(.plain)
                            .accessibilityLabel("试听")
                        }
                    }
                    Button(buddy == nil ? "创建搭子" : "保存修改", action: save).buttonStyle(PurpleButtonStyle()).padding(.top, 8)
                }.padding(20)
            }
            .navigationTitle(buddy == nil ? "创建搭子" : "编辑搭子")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .topBarLeading) { Button("取消") { dismiss() } } }
            .appBackground()
        }
    }

    private func field<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 9) { SectionLabel(title: title); content().padding(14).appCard(cornerRadius: 13) }
    }

    private func save() {
        guard !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        if let buddy {
            buddy.name = name; buddy.language = language; buddy.relationship = relationship; buddy.personality = personality; buddy.correctionLevel = correction
            buddy.voiceIdentifier = voiceIdentifier; buddy.voicePreset = voicePreset
        } else {
            context.insert(Buddy(name: name, language: language, relationship: relationship, personality: personality, correctionLevel: correction,
                                 voiceIdentifier: voiceIdentifier, voicePreset: voicePreset))
        }
        try? context.save(); dismiss()
    }

    static func previewText(for language: String) -> String {
        switch language {
        case "日本語": "こんにちは！今日も一緒に練習しましょう。"
        case "한국어": "안녕하세요! 오늘도 같이 연습해요."
        case "中文": "你好！今天也一起练习吧。"
        case "Français": "Salut ! On pratique ensemble aujourd’hui."
        case "Español": "¡Hola! Practiquemos juntos hoy."
        default: "Hi! Let's practice together today."
        }
    }
}

