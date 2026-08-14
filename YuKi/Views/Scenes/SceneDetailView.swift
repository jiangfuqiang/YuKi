import SwiftUI
import SwiftData

struct SceneDetailView: View {
    let scene: Scene
    @Query private var buddies: [Buddy]
    @Query private var sessions: [ChatSession]
    @Environment(\.modelContext) private var context
    @State private var showsChat = false
    @State private var showsRecords = false
    @State private var editedBuddy: Buddy?

    private var buddy: Buddy? { buddies.first { $0.id == scene.buddyId } }
    private var sessionCount: Int { sessions.filter { $0.sceneId == scene.id }.count }

    var body: some View {
        ScrollView {
            VStack(spacing: 22) {
                ZStack {
                    RoundedRectangle(cornerRadius: 26, style: .continuous)
                        .fill(LinearGradient(colors: [AppTheme.purple.opacity(0.26), AppTheme.card], startPoint: .topLeading, endPoint: .bottomTrailing))
                    VStack(spacing: 16) {
                        Image(systemName: scene.coverImage)
                            .font(.system(size: 42, weight: .semibold)).foregroundStyle(AppTheme.purpleLight)
                        Text(scene.name).font(.system(size: 25, weight: .bold))
                        Text(scene.language).font(.subheadline).foregroundStyle(AppTheme.secondaryText)
                    }
                }.frame(height: 220)

                VStack(alignment: .leading, spacing: 10) {
                    Text("场景背景").font(.caption).foregroundStyle(AppTheme.secondaryText)
                    Text(scene.sceneDescription).font(.system(size: 15)).foregroundStyle(.white.opacity(0.88)).lineSpacing(5)
                }.padding(18).frame(maxWidth: .infinity, alignment: .leading).appCard()

                if let buddy {
                    Button { editedBuddy = buddy } label: {
                        HStack(spacing: 13) {
                            AvatarView(name: buddy.name, size: 48, isOnline: true)
                            VStack(alignment: .leading, spacing: 4) {
                                Text(buddy.name).font(.headline)
                                Text("\(buddy.relationship.title) · \(buddy.personality)").font(.caption).foregroundStyle(AppTheme.secondaryText)
                            }
                            Spacer()
                            Image(systemName: "chevron.right").foregroundStyle(AppTheme.secondaryText)
                        }.foregroundStyle(.white).padding(16).appCard()
                    }.buttonStyle(.plain)
                }

                Button("开始聊天") { showsChat = true }
                    .buttonStyle(PurpleButtonStyle())
                    .accessibilityIdentifier("start-chat-button")
                if sessionCount > 0 {
                    Button { showsRecords = true } label: {
                        Text("查看对话记录（\(sessionCount)）")
                            .font(.system(size: 15, weight: .medium)).foregroundStyle(AppTheme.purpleLight)
                            .frame(maxWidth: .infinity).frame(height: 50).appCard(cornerRadius: 16)
                    }
                }
            }.padding(18)
        }
        .navigationTitle(scene.name)
        .navigationBarTitleDisplayMode(.inline)
        .fullScreenCover(isPresented: $showsChat) { NavigationStack { ChatView(scene: scene, buddy: buddy) } }
        .sheet(isPresented: $showsRecords) { NavigationStack { ChatRecordsView(scene: scene) } }
        .sheet(item: $editedBuddy) { BuddyEditorView(buddy: $0) }
        .appBackground()
    }
}
