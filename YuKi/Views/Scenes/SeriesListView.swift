import SwiftUI
import SwiftData

struct SeriesListView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context
    @Query(sort: \Series.createdAt) private var series: [Series]
    @State private var showsNewSeries = false
    @State private var newName = ""

    var body: some View {
        List {
            ForEach(series) { item in
                NavigationLink {
                    SeriesDetailView(series: item)
                } label: {
                    HStack(spacing: 13) {
                        Image(systemName: "rectangle.stack.fill").foregroundStyle(AppTheme.purpleLight).frame(width: 34, height: 34).background(AppTheme.purple.opacity(0.14), in: RoundedRectangle(cornerRadius: 9))
                        VStack(alignment: .leading, spacing: 4) { Text(item.name).font(.headline); Text("\(item.sceneIds.count) 个场景").font(.caption).foregroundStyle(AppTheme.secondaryText) }
                    }.padding(.vertical, 7)
                }.listRowBackground(AppTheme.card)
            }.onDelete { offsets in offsets.forEach { LocalDataMaintenance.deleteSeries(series[$0], in: context) } }
        }
        .scrollContentBackground(.hidden)
        .navigationTitle("我的系列")
        .toolbar {
            ToolbarItem(placement: .topBarLeading) { Button("关闭") { dismiss() } }
            ToolbarItem(placement: .topBarTrailing) { Button { showsNewSeries = true } label: { Image(systemName: "plus") } }
        }
        .alert("创建系列", isPresented: $showsNewSeries) {
            TextField("系列名称", text: $newName)
            Button("取消", role: .cancel) { newName = "" }
            Button("创建") {
                let trimmed = newName.trimmingCharacters(in: .whitespacesAndNewlines)
                if !trimmed.isEmpty { context.insert(Series(name: trimmed)); try? context.save() }
                newName = ""
            }
        }
        .appBackground()
    }
}

private struct SeriesDetailView: View {
    let series: Series
    @Environment(\.modelContext) private var context
    @Query(sort: \Scene.createdAt) private var allScenes: [Scene]
    @State private var showsAddScenes = false
    @State private var showsRename = false
    @State private var newName = ""

    private var memberScenes: [Scene] { allScenes.filter { $0.seriesId == series.id } }
    private var availableScenes: [Scene] { allScenes.filter { $0.seriesId != series.id } }

    var body: some View {
        List {
            if memberScenes.isEmpty {
                EmptyStateView(icon: "rectangle.stack.badge.plus", title: "系列中还没有场景", subtitle: "场景只会由你手动加入。")
                    .frame(maxWidth: .infinity).listRowBackground(Color.clear)
            } else {
                ForEach(memberScenes) { scene in
                    NavigationLink { SceneDetailView(scene: scene) } label: {
                        HStack(spacing: 12) {
                            Image(systemName: scene.coverImage).foregroundStyle(AppTheme.purpleLight).frame(width: 36)
                            VStack(alignment: .leading, spacing: 4) {
                                Text(scene.name).font(.headline)
                                Text(scene.language).font(.caption).foregroundStyle(AppTheme.secondaryText)
                            }
                        }.padding(.vertical, 6)
                    }
                    .listRowBackground(AppTheme.card)
                    .swipeActions {
                        Button("移出系列", role: .destructive) {
                            scene.seriesId = nil
                            series.sceneIds.removeAll { $0 == scene.id }
                            try? context.save()
                        }
                    }
                }
            }
        }
        .scrollContentBackground(.hidden)
        .navigationTitle(series.name)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    Button("添加场景", systemImage: "plus") { showsAddScenes = true }
                    Button("重命名", systemImage: "pencil") { newName = series.name; showsRename = true }
                } label: { Image(systemName: "ellipsis.circle") }
            }
        }
        .sheet(isPresented: $showsAddScenes) {
            NavigationStack {
                List {
                    if availableScenes.isEmpty {
                        Text("没有可添加的场景").foregroundStyle(AppTheme.secondaryText).listRowBackground(Color.clear)
                    }
                    ForEach(availableScenes) { scene in
                        Button {
                            if let oldSeriesID = scene.seriesId,
                               let oldSeries = try? context.fetch(FetchDescriptor<Series>()).first(where: { $0.id == oldSeriesID }) {
                                oldSeries.sceneIds.removeAll { $0 == scene.id }
                            }
                            scene.seriesId = series.id
                            if !series.sceneIds.contains(scene.id) { series.sceneIds.append(scene.id) }
                            try? context.save()
                        } label: {
                            HStack { Text(scene.name); Spacer(); Image(systemName: "plus.circle").foregroundStyle(AppTheme.purpleLight) }
                        }.listRowBackground(AppTheme.card)
                    }
                }
                .scrollContentBackground(.hidden).navigationTitle("添加场景")
                .toolbar { ToolbarItem(placement: .topBarTrailing) { Button("完成") { showsAddScenes = false } } }
                .appBackground()
            }
        }
        .alert("重命名系列", isPresented: $showsRename) {
            TextField("系列名称", text: $newName)
            Button("取消", role: .cancel) {}
            Button("保存") {
                let value = newName.trimmingCharacters(in: .whitespacesAndNewlines)
                if !value.isEmpty { series.name = value; try? context.save() }
            }
        }
        .appBackground()
    }
}
