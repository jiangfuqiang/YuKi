import SwiftUI
import SwiftData

struct SceneListView: View {
    @Environment(\.modelContext) private var context
    @Query(sort: \Series.createdAt, order: .reverse) private var series: [Series]
    @Query(sort: \Scene.createdAt, order: .reverse) private var scenes: [Scene]
    @State private var showsCreateSeries = false
    @State private var seriesPendingDeletion: Series?
    @State private var scenePendingDeletion: Scene?

    private var ungroupedScenes: [Scene] { scenes.filter { $0.seriesId == nil } }

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
                        Text("我的系列")
                            .font(.system(size: 28, weight: .bold))
                        Text("所有对话都在本地，完全离线")
                            .font(.system(size: 13))
                            .foregroundStyle(AppTheme.secondaryText)
                    }
                    Spacer()
                    CircleIconButton(systemName: "plus") { showsCreateSeries = true }
                }

                if series.isEmpty {
                    EmptyStateView(icon: "rectangle.stack.badge.plus", title: "创建你的第一个系列", subtitle: "比如“美国旅行”，再在系列里创建具体场景。")
                        .frame(maxWidth: .infinity)
                        .appCard()
                } else {
                    LazyVGrid(columns: [GridItem(.flexible(), spacing: 12), GridItem(.flexible())], spacing: 12) {
                        ForEach(Array(series.enumerated()), id: \.element.id) { index, item in
                            NavigationLink(value: item.id) {
                                SeriesCard(series: item, background: palette[index % palette.count].0, accent: palette[index % palette.count].1)
                            }
                            .buttonStyle(.plain)
                            .accessibilityIdentifier("series-\(item.name)")
                            .contextMenu {
                                Button("删除系列", systemImage: "trash", role: .destructive) {
                                    seriesPendingDeletion = item
                                }
                            }
                        }
                        Button { showsCreateSeries = true } label: {
                            VStack(spacing: 13) {
                                Image(systemName: "plus").font(.system(size: 27, weight: .light)).foregroundStyle(AppTheme.purpleLight)
                                Text("创建新系列").font(.system(size: 14, weight: .medium)).foregroundStyle(AppTheme.secondaryText)
                            }
                            .frame(maxWidth: .infinity, minHeight: 174)
                            .background(AppTheme.card.opacity(0.45), in: RoundedRectangle(cornerRadius: 20, style: .continuous))
                            .overlay(RoundedRectangle(cornerRadius: 20, style: .continuous).stroke(AppTheme.purple.opacity(0.45), style: StrokeStyle(lineWidth: 1, dash: [4])))
                        }
                        .buttonStyle(.plain)
                    }
                }

                if !ungroupedScenes.isEmpty {
                    Text("未分组场景")
                        .font(.system(size: 17, weight: .semibold))
                        .padding(.top, 6)
                    LazyVGrid(columns: [GridItem(.flexible(), spacing: 12), GridItem(.flexible())], spacing: 12) {
                        ForEach(Array(ungroupedScenes.enumerated()), id: \.element.id) { index, scene in
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
                    }
                }
            }
            .padding(.horizontal, 18)
            .padding(.top, 16)
            .padding(.bottom, 24)
        }
        .navigationBarHidden(true)
        .navigationDestination(for: UUID.self) { id in
            if let item = series.first(where: { $0.id == id }) {
                SeriesDetailView(series: item)
            } else if let scene = scenes.first(where: { $0.id == id }) {
                SceneDetailView(scene: scene)
            }
        }
        .sheet(isPresented: $showsCreateSeries) { CreateSeriesView() }
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
        .confirmationDialog("删除“\(seriesPendingDeletion?.name ?? "")”？", isPresented: Binding(
            get: { seriesPendingDeletion != nil },
            set: { if !$0 { seriesPendingDeletion = nil } }
        ), titleVisibility: .visible) {
            Button("删除系列", role: .destructive) {
                if let seriesPendingDeletion { LocalDataMaintenance.deleteSeries(seriesPendingDeletion, in: context) }
                seriesPendingDeletion = nil
            }
            Button("取消", role: .cancel) { seriesPendingDeletion = nil }
        } message: {
            Text("系列中的场景不会被删除，只会移出该系列。")
        }
        .appBackground()
    }
}

private struct SeriesCard: View {
    let series: Series
    let background: Color
    let accent: Color

    var body: some View {
        ZStack(alignment: .bottomLeading) {
            if let data = series.coverImageData, let image = UIImage(data: data) {
                Image(uiImage: image)
                    .resizable().scaledToFill()
                    .frame(maxWidth: .infinity, minHeight: 174, maxHeight: 174)
                    .overlay(LinearGradient(colors: [.clear, .black.opacity(0.62)], startPoint: .center, endPoint: .bottom))
            } else {
                VStack(alignment: .leading, spacing: 0) {
                    Image(systemName: "rectangle.stack.fill")
                        .font(.system(size: 29, weight: .semibold))
                        .foregroundStyle(accent)
                        .frame(height: 50)
                    Spacer()
                }
                .padding(17)
                .frame(maxWidth: .infinity, minHeight: 174, alignment: .leading)
                .background(
                    LinearGradient(colors: [background.opacity(0.9), AppTheme.card], startPoint: .topLeading, endPoint: .bottomTrailing)
                )
            }
            VStack(alignment: .leading, spacing: 5) {
                Text(series.name)
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(.white)
                    .lineLimit(1)
                Text("\(series.sceneIds.count) 个场景")
                    .font(.system(size: 11))
                    .foregroundStyle(.white.opacity(0.72))
            }
            .padding(17)
        }
        .frame(maxWidth: .infinity, minHeight: 174, alignment: .bottomLeading)
        .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
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
