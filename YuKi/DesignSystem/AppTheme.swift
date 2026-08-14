import SwiftUI

enum AppTheme {
    static let background = Color(hex: 0x0B0B10)
    static let card = Color(hex: 0x16161D)
    static let cardElevated = Color(hex: 0x1C1C24)
    static let purple = Color(hex: 0x6C4BFF)
    static let purpleLight = Color(hex: 0x8B5CFF)
    static let secondaryText = Color.white.opacity(0.55)
    static let tertiaryText = Color.white.opacity(0.30)
    static let separator = Color.white.opacity(0.07)

    static let gradient = LinearGradient(
        colors: [purple, purpleLight],
        startPoint: .leading,
        endPoint: .trailing
    )
}

extension Color {
    init(hex: UInt, alpha: Double = 1) {
        self.init(
            .sRGB,
            red: Double((hex >> 16) & 0xff) / 255,
            green: Double((hex >> 8) & 0xff) / 255,
            blue: Double(hex & 0xff) / 255,
            opacity: alpha
        )
    }
}

struct AppBackground: ViewModifier {
    func body(content: Content) -> some View {
        content
            .background(AppTheme.background.ignoresSafeArea())
            .tint(AppTheme.purpleLight)
    }
}

extension View {
    func appBackground() -> some View { modifier(AppBackground()) }

    func appCard(cornerRadius: CGFloat = 18) -> some View {
        background(AppTheme.card, in: RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
    }
}

struct PurpleButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 16, weight: .semibold))
            .foregroundStyle(.white)
            .frame(maxWidth: .infinity)
            .frame(height: 54)
            .background(AppTheme.gradient, in: RoundedRectangle(cornerRadius: 17, style: .continuous))
            .scaleEffect(configuration.isPressed ? 0.98 : 1)
            .opacity(configuration.isPressed ? 0.85 : 1)
            .animation(.easeOut(duration: 0.16), value: configuration.isPressed)
    }
}

struct SectionLabel: View {
    let title: String
    var body: some View {
        Text(title)
            .font(.system(size: 15, weight: .semibold))
            .foregroundStyle(.white.opacity(0.9))
            .frame(maxWidth: .infinity, alignment: .leading)
    }
}

