import SwiftUI
import SwiftData

struct CreateSceneView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context
    @Query(sort: \Buddy.createdAt) private var buddies: [Buddy]
    @Query(sort: \Series.createdAt) private var series: [Series]
    @StateObject private var model = CreateSceneViewModel()

    private var compatibleBuddies: [Buddy] { buddies.filter { $0.language == model.language } }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                HStack(spacing: 7) {
                    ForEach(1...3, id: \.self) { step in
                        Capsule().fill(step <= model.step ? AppTheme.purpleLight : AppTheme.cardElevated).frame(height: 4)
                    }
                }
                .padding(.horizontal, 20)
                .padding(.top, 8)

                ScrollView {
                    Group {
                        if model.step == 1 { sceneInfoStep }
                        else if model.step == 2 { buddyStep }
                        else { descriptionStep }
                    }
                    .padding(20)
                    .transition(.opacity.combined(with: .move(edge: .trailing)))
                }

                Button(model.step == 3 ? "创建场景" : "继续") {
                    if model.step < 3 {
                        withAnimation(.easeInOut(duration: 0.25)) { model.step += 1 }
                    } else {
                        model.create(in: context)
                        dismiss()
                    }
                }
                .buttonStyle(PurpleButtonStyle())
                .disabled(!model.canContinue)
                .opacity(model.canContinue ? 1 : 0.45)
                .padding(20)
            }
            .navigationTitle(model.step == 1 ? "创建新场景" : model.step == 2 ? "选择 AI 搭子" : "描述场景")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button { model.step == 1 ? dismiss() : withAnimation { model.step -= 1 } } label: { Image(systemName: "chevron.left") }
                }
            }
            .appBackground()
        }
    }

    private var sceneInfoStep: some View {
        VStack(alignment: .leading, spacing: 24) {
            VStack(alignment: .leading, spacing: 10) {
                SectionLabel(title: "这个场景叫什么？")
                TextField("例如：日本旅行", text: $model.name)
                    .padding(16).appCard(cornerRadius: 13)
            }
            VStack(alignment: .leading, spacing: 10) {
                SectionLabel(title: "选择语言")
                ForEach(model.languages, id: \.self) { language in
                    Button { model.language = language } label: {
                        HStack {
                            Text(flag(for: language)); Text(language); Spacer()
                            if model.language == language { Image(systemName: "checkmark.circle.fill").foregroundStyle(AppTheme.purpleLight) }
                        }
                        .foregroundStyle(.white).padding(.horizontal, 16).frame(height: 50).appCard(cornerRadius: 13)
                    }.buttonStyle(.plain)
                }
            }
        }
    }

    private var buddyStep: some View {
        VStack(alignment: .leading, spacing: 22) {
            if !compatibleBuddies.isEmpty {
                SectionLabel(title: "使用已有搭子")
                ForEach(compatibleBuddies) { buddy in
                    Button { model.selectedBuddyID = buddy.id } label: {
                        HStack(spacing: 12) {
                            AvatarView(name: buddy.name, size: 42)
                            VStack(alignment: .leading) { Text(buddy.name).fontWeight(.semibold); Text("\(buddy.relationship.title) · \(buddy.personality)").font(.caption).foregroundStyle(AppTheme.secondaryText) }
                            Spacer()
                            if model.selectedBuddyID == buddy.id { Image(systemName: "checkmark.circle.fill").foregroundStyle(AppTheme.purpleLight) }
                        }.foregroundStyle(.white).padding(14).appCard(cornerRadius: 14)
                    }.buttonStyle(.plain)
                }
                if model.selectedBuddyID != nil {
                    Button("改为新建搭子") { model.selectedBuddyID = nil }
                        .font(.caption).foregroundStyle(AppTheme.purpleLight).frame(maxWidth: .infinity)
                } else {
                    Text("或者新建搭子").font(.caption).foregroundStyle(AppTheme.secondaryText).frame(maxWidth: .infinity)
                }
            }
            if model.selectedBuddyID == nil {
                SectionLabel(title: "关系")
                Picker("关系", selection: $model.relationship) {
                    ForEach(BuddyRelationship.allCases) { Text($0.title).tag($0) }
                }.pickerStyle(.segmented)
                SectionLabel(title: "名字")
                TextField("搭子的名字", text: $model.buddyName).padding(16).appCard(cornerRadius: 13)
                SectionLabel(title: "性格")
                TextField("例如：友好、耐心", text: $model.personality).padding(16).appCard(cornerRadius: 13)
                SectionLabel(title: "纠错程度")
                Picker("纠错程度", selection: $model.correctionLevel) {
                    ForEach(CorrectionLevel.allCases) { Text($0.title).tag($0) }
                }.pickerStyle(.segmented)
            }
        }
    }

    private var descriptionStep: some View {
        VStack(alignment: .leading, spacing: 22) {
            SectionLabel(title: "你想在这个场景里聊什么？")
            ZStack(alignment: .topLeading) {
                if model.description.isEmpty {
                    Text("例如：我要练习第一次去日本旅游，包括机场、酒店、餐厅交流。")
                        .foregroundStyle(AppTheme.tertiaryText).padding(17)
                }
                TextEditor(text: $model.description)
                    .scrollContentBackground(.hidden).frame(minHeight: 170).padding(10)
            }.appCard(cornerRadius: 16)
            if !series.isEmpty {
                SectionLabel(title: "加入系列（可选）")
                Picker("系列", selection: $model.selectedSeriesID) {
                    Text("不加入系列").tag(UUID?.none)
                    ForEach(series) { Text($0.name).tag(Optional($0.id)) }
                }.pickerStyle(.menu).frame(maxWidth: .infinity, alignment: .leading).padding(12).appCard(cornerRadius: 13)
            }
            Text("场景只会由你创建，AI 不会自动生成后续场景。")
                .font(.caption).foregroundStyle(AppTheme.secondaryText)
        }
    }

    private func flag(for language: String) -> String {
        ["English":"🇺🇸", "日本語":"🇯🇵", "한국어":"🇰🇷", "中文":"🇨🇳", "Français":"🇫🇷", "Español":"🇪🇸"][language] ?? "🌐"
    }
}
