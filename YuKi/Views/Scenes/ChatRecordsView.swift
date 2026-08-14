import SwiftUI
import SwiftData

struct ChatRecordsView: View {
    let scene: Scene
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context
    @Query(sort: \ChatSession.startedAt, order: .reverse) private var sessions: [ChatSession]

    private var sceneSessions: [ChatSession] { sessions.filter { $0.sceneId == scene.id } }

    var body: some View {
        List {
            ForEach(sceneSessions) { session in
                NavigationLink {
                    SessionTranscriptView(session: session)
                } label: {
                    VStack(alignment: .leading, spacing: 6) {
                        Text(session.startedAt.formatted(date: .abbreviated, time: .shortened)).font(.headline)
                        Text(session.isEnded ? "已结束" : "未结束").font(.caption).foregroundStyle(AppTheme.secondaryText)
                    }.padding(.vertical, 7)
                }.listRowBackground(AppTheme.card)
            }.onDelete { offsets in offsets.forEach { LocalDataMaintenance.deleteSession(sceneSessions[$0], in: context) } }
        }.scrollContentBackground(.hidden)
            .navigationTitle("对话记录")
            .toolbar { ToolbarItem(placement: .topBarTrailing) { Button("完成") { dismiss() } } }
            .appBackground()
    }
}

private struct SessionTranscriptView: View {
    let session: ChatSession
    @Query(sort: \Message.timestamp) private var messages: [Message]
    @StateObject private var playback = AudioPlaybackService()
    private var filtered: [Message] { messages.filter { $0.sessionId == session.id } }
    var body: some View {
        ScrollView { LazyVStack(spacing: 14) { ForEach(filtered) { MessageBubble(message: $0, buddyName: "AI", playback: playback) } }.padding() }
            .navigationTitle("对话详情").navigationBarTitleDisplayMode(.inline).appBackground()
    }
}
