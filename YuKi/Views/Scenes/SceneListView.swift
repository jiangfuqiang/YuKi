import SwiftUI
import SwiftData

struct SceneListView: View {
    @Environment(\.modelContext) private var context
    @Query(sort: \Scene.createdAt, order: .reverse) private var scenes: [Scene]
    @State private var showsCreateScene = false
    @State private var showsSeries = false
    @State private var scenePendingDeletion: Scene?

    private let palette: [(Color, Color)] = [
        (Color(hex: 0x1B1940), Color(hex: 0x7657FF)),
        (Color(hex: 0x14261D), Color(hex: 0x6ACB78)),
        (Color(hex: 0x352016), Color(hex: 0xF18B43)),
        (Color(hex: 0x17252B), Color(hex: 0x9BDDF6)),
        (Color(hex: 0x281A38), Color(hex: 0x9A65E7))
    ]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: 5) {
                        Text("我的场景")
                            .font(.system(size: 28, weight: .bold))
                        Text("所有对话都在本地，完全离线")
                            .font(.system(size: 13))
                            .foregroundStyle(AppTheme.secondaryText)
                    }
                    Spacer()
                    CircleIconButton(systemName: "plus") { showsCreateScene = true }
                }

                if scenes.isEmpty {
                    EmptyStateView(icon: "rectangle.stack.badge.plus", title: "创建你的第一个场景", subtitle: "决定聊什么、和谁聊，一切由你控制。")
                        .frame(maxWidth: .infinity)
                        .appCard()
                } else {
                    LazyVGrid(columns: [GridItem(.flexible(), spacing: 12), GridItem(.flexible())], spacing: 12) {
                        ForEach(Array(scenes.enumerated()), id: \.element.id) { index, scene in
                            NavigationLink(value: scene.id) {
                                SceneCard(scene: scene, background: palette[index % palette.count].0, accent: palette[index % palette.count].1)
                            }
                            .buttonStyle(.plain)
                            .accessibilityIdentifier("scene-\(scene.name)")
                            .contextMenu {
                                Button("删除场景", systemImage: "trash", role: .destructive) {
                                    scenePendingDeletion = scene
                                }
                            }
                        }
                        Button { showsCreateScene = true } label: {
                            VStack(spacing: 13) {
                                Image(systemName: "plus").font(.system(size: 27, weight: .light)).foregroundStyle(AppTheme.purpleLight)
                                Text("创建新场景").font(.system(size: 14, weight: .medium)).foregroundStyle(AppTheme.secondaryText)
                            }
                            .frame(maxWidth: .infinity, minHeight: 174)
                            .background(AppTheme.card.opacity(0.45), in: RoundedRectangle(cornerRadius: 20, style: .continuous))
                            .overlay(RoundedRectangle(cornerRadius: 20, style: .continuous).stroke(AppTheme.purple.opacity(0.45), style: StrokeStyle(lineWidth: 1, dash: [4])))
                        }
                        .buttonStyle(.plain)
                    }
                }

                Button { showsSeries = true } label: {
                    Label("管理场景系列", systemImage: "rectangle.stack.fill")
                        .font(.system(size: 14, weight: .medium))
                        .foregroundStyle(AppTheme.secondaryText)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                }
            }
            .padding(.horizontal, 18)
            .padding(.top, 16)
            .padding(.bottom, 24)
        }
        .navigationBarHidden(true)
        .navigationDestination(for: UUID.self) { id in
            if let scene = scenes.first(where: { $0.id == id }) { SceneDetailView(scene: scene) }
        }
        .sheet(isPresented: $showsCreateScene) { CreateSceneView() }
        .sheet(isPresented: $showsSeries) { NavigationStack { SeriesListView() } }
        .confirmationDialog("删除“\(scenePendingDeletion?.name ?? "")”？", isPresented: Binding(
            get: { scenePendingDeletion != nil },
            set: { if !$0 { scenePendingDeletion = nil } }
        ), titleVisibility: .visible) {
            Button("删除场景及其聊天记录", role: .destructive) {
                if let scenePendingDeletion { LocalDataMaintenance.deleteScene(scenePendingDeletion, in: context) }
                scenePendingDeletion = nil
            }
            Button("取消", role: .cancel) { scenePendingDeletion = nil }
        } message: {
            Text("此操作无法撤销，保存在本地的相关录音也会被删除。")
        }
        .appBackground()
    }
}

private struct SceneCard: View {
    let scene: Scene
    let background: Color
    let accent: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Image(systemName: scene.coverImage)
                .font(.system(size: 29, weight: .semibold))
                .foregroundStyle(accent)
                .frame(height: 50)
            Spacer()
            Text(scene.name)
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(.white)
                .lineLimit(1)
            Text("创建于 \(relativeDate)")
                .font(.system(size: 11))
                .foregroundStyle(AppTheme.secondaryText)
                .padding(.top, 8)
        }
        .padding(17)
        .frame(maxWidth: .infinity, minHeight: 174, alignment: .leading)
        .background(
            LinearGradient(colors: [background.opacity(0.9), AppTheme.card], startPoint: .topLeading, endPoint: .bottomTrailing),
            in: RoundedRectangle(cornerRadius: 20, style: .continuous)
        )
    }

    private var relativeDate: String {
        let days = max(0, Calendar.current.dateComponents([.day], from: scene.createdAt, to: .now).day ?? 0)
        if days == 0 { return "今天" }
        if days < 7 { return "\(days) 天前" }
        let weeks = max(1, days / 7)
        return "\(weeks) 周前"
    }
}
