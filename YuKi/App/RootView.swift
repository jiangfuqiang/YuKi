import SwiftUI

struct RootView: View {
    @State private var selection = 0

    var body: some View {
        TabView(selection: $selection) {
            NavigationStack { SceneListView() }
                .tabItem { Label("系列", systemImage: "house.fill") }
                .tag(0)
            NavigationStack { BuddyListView() }
                .tabItem { Label("搭子", systemImage: "figure.2") }
                .tag(1)
            NavigationStack { ProfileView() }
                .tabItem { Label("我的", systemImage: "person.fill") }
                .tag(2)
        }
        .tint(AppTheme.purpleLight)
        .toolbarBackground(AppTheme.background.opacity(0.96), for: .tabBar)
        .toolbarBackground(.visible, for: .tabBar)
    }
}
