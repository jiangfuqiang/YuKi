import SwiftUI
import SwiftData

struct BuddyListView: View {
    @Query(sort: \Buddy.createdAt) private var buddies: [Buddy]
    @State private var editedBuddy: Buddy?
    @State private var showsCreate = false

    var body: some View {
        ScrollView {
            VStack(spacing: 18) {
                HStack {
                    Text("我的搭子").font(.system(size: 28, weight: .bold))
                    Spacer()
                    CircleIconButton(systemName: "plus") { showsCreate = true }
                }
                if buddies.isEmpty {
                    EmptyStateView(icon: "figure.2", title: "还没有搭子", subtitle: "创建一个属于你的 AI 口语搭子。")
                        .frame(maxWidth: .infinity).appCard()
                } else {
                    ForEach(buddies) { buddy in
                        Button { editedBuddy = buddy } label: {
                            HStack(spacing: 14) {
                                AvatarView(name: buddy.name, size: 53, isOnline: true)
                                VStack(alignment: .leading, spacing: 5) {
                                    Text(buddy.name).font(.system(size: 17, weight: .semibold))
                                    Text("\(buddy.language) · \(buddy.relationship.title)").font(.system(size: 12)).foregroundStyle(AppTheme.secondaryText)
                                }
                                Spacer()
                                Image(systemName: "chevron.right").font(.caption).foregroundStyle(AppTheme.secondaryText)
                            }.foregroundStyle(.white).padding(16).appCard()
                        }.buttonStyle(.plain)
                    }
                }
            }.padding(18)
        }
        .navigationBarHidden(true)
        .sheet(item: $editedBuddy) { BuddyEditorView(buddy: $0) }
        .sheet(isPresented: $showsCreate) { BuddyEditorView(buddy: nil) }
        .appBackground()
    }
}

