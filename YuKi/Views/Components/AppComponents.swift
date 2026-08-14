import SwiftUI

struct CircleIconButton: View {
    let systemName: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(.white)
                .frame(width: 38, height: 38)
                .background(AppTheme.gradient, in: Circle())
        }
        .buttonStyle(.plain)
    }
}

struct AvatarView: View {
    let name: String
    var size: CGFloat = 48
    var isOnline = false

    private var color: Color {
        let colors: [Color] = [.purple, .blue, .orange, .teal, .pink]
        let stableValue = name.unicodeScalars.reduce(0) { ($0 &* 31) &+ Int($1.value) }
        return colors[abs(stableValue) % colors.count]
    }

    var body: some View {
        ZStack(alignment: .bottomTrailing) {
            Circle()
                .fill(color.opacity(0.27))
                .overlay {
                    Text(String(name.prefix(1)))
                        .font(.system(size: size * 0.4, weight: .semibold))
                        .foregroundStyle(.white)
                }
                .frame(width: size, height: size)
            if isOnline {
                Circle().fill(.green).frame(width: 9, height: 9)
                    .overlay(Circle().stroke(AppTheme.background, lineWidth: 2))
            }
        }
    }
}

struct SettingsRow: View {
    let icon: String
    let title: String
    var value: String? = nil
    var color: Color = .white

    var body: some View {
        HStack(spacing: 13) {
            Image(systemName: icon)
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(color)
                .frame(width: 22)
            Text(title).font(.system(size: 15, weight: .medium))
            Spacer()
            if let value { Text(value).foregroundStyle(AppTheme.secondaryText) }
            Image(systemName: "chevron.right")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(AppTheme.secondaryText)
        }
        .foregroundStyle(.white)
        .padding(.horizontal, 16)
        .frame(height: 57)
        .contentShape(Rectangle())
    }
}

struct EmptyStateView: View {
    let icon: String
    let title: String
    let subtitle: String

    var body: some View {
        VStack(spacing: 14) {
            Image(systemName: icon)
                .font(.system(size: 35, weight: .medium))
                .foregroundStyle(AppTheme.purpleLight)
            Text(title).font(.headline).foregroundStyle(.white)
            Text(subtitle).font(.subheadline).foregroundStyle(AppTheme.secondaryText).multilineTextAlignment(.center)
        }
        .padding(32)
    }
}
