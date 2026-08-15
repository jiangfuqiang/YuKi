import SwiftUI
import SwiftData
import PhotosUI

struct CreateSeriesView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context
    @State private var name = ""
    @State private var photoItem: PhotosPickerItem?
    @State private var coverData: Data?

    var body: some View {
        NavigationStack {
            VStack(spacing: 22) {
                PhotosPicker(selection: $photoItem, matching: .images) {
                    if let coverData, let image = UIImage(data: coverData) {
                        Image(uiImage: image)
                            .resizable().scaledToFill()
                            .frame(maxWidth: .infinity).frame(height: 168)
                            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                            .overlay(alignment: .bottomTrailing) {
                                Image(systemName: "photo.badge.plus").font(.headline).foregroundStyle(.white)
                                    .padding(8).background(.black.opacity(0.45), in: Circle()).padding(10)
                            }
                    } else {
                        VStack(spacing: 10) {
                            Image(systemName: "photo.badge.plus").font(.system(size: 27, weight: .light)).foregroundStyle(AppTheme.purpleLight)
                            Text("添加封面（可选）").font(.system(size: 14, weight: .medium)).foregroundStyle(AppTheme.secondaryText)
                        }
                        .frame(maxWidth: .infinity).frame(height: 168)
                        .background(AppTheme.card.opacity(0.45), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                    }
                }
                .buttonStyle(.plain)

                VStack(alignment: .leading, spacing: 10) {
                    SectionLabel(title: "系列名称")
                    TextField("例如：美国旅行", text: $name)
                        .padding(16).appCard(cornerRadius: 13)
                }

                Button("创建系列", action: create)
                    .buttonStyle(PurpleButtonStyle())
                    .disabled(name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    .opacity(name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? 0.45 : 1)
                Spacer()
            }
            .padding(20)
            .navigationTitle("创建系列")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .topBarLeading) { Button("取消") { dismiss() } } }
            .appBackground()
            .onChange(of: photoItem) { _, item in
                Task { coverData = await Self.loadCoverData(from: item) }
            }
        }
    }

    private func create() {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        context.insert(Series(name: trimmed, coverImageData: coverData))
        try? context.save()
        dismiss()
    }

    /// Downscales the picked photo before storing; original camera shots are
    /// several MB and the cover never renders larger than a card.
    static func loadCoverData(from item: PhotosPickerItem?) async -> Data? {
        guard let item,
              let raw = try? await item.loadTransferable(type: Data.self),
              let image = UIImage(data: raw) else { return nil }
        let side = min(max(image.size.width, image.size.height), 1200)
        let target = CGSize(width: image.size.width * side / max(image.size.width, image.size.height),
                            height: image.size.height * side / max(image.size.width, image.size.height))
        let resized = image.preparingThumbnail(of: target) ?? image
        return resized.jpegData(compressionQuality: 0.8)
    }
}

struct SeriesDetailView: View {
    let series: Series
    @Environment(\.modelContext) private var context
    @Query(sort: \Scene.createdAt) private var allScenes: [Scene]
    @State private var showsAddScenes = false
    @State private var showsCreateScene = false
    @State private var showsRename = false
    @State private var newName = ""
    @State private var photoItem: PhotosPickerItem?

    private var memberScenes: [Scene] { allScenes.filter { $0.seriesId == series.id } }
    private var availableScenes: [Scene] { allScenes.filter { $0.seriesId != series.id } }

    var body: some View {
        List {
            if memberScenes.isEmpty {
                EmptyStateView(icon: "rectangle.stack.badge.plus", title: "系列中还没有场景", subtitle: "点击下方按钮，在这个系列里创建第一个场景。")
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
        .safeAreaInset(edge: .bottom) {
            Button { showsCreateScene = true } label: {
                Label("创建场景", systemImage: "plus")
            }
            .buttonStyle(PurpleButtonStyle())
            .padding(.horizontal, 20).padding(.vertical, 10)
            .background(AppTheme.background.opacity(0.96))
        }
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    Button("添加已有场景", systemImage: "tray.and.arrow.down") { showsAddScenes = true }
                    PhotosPicker(selection: $photoItem, matching: .images) {
                        Label(series.coverImageData == nil ? "设置封面" : "更换封面", systemImage: "photo")
                    }
                    Button("重命名", systemImage: "pencil") { newName = series.name; showsRename = true }
                } label: { Image(systemName: "ellipsis.circle") }
            }
        }
        .onChange(of: photoItem) { _, item in
            Task {
                if let data = await CreateSeriesView.loadCoverData(from: item) {
                    series.coverImageData = data
                    try? context.save()
                }
                photoItem = nil
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
        .sheet(isPresented: $showsCreateScene) { CreateSceneView(presetSeriesID: series.id) }
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
