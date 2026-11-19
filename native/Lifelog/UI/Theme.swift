import SwiftUI

enum LifelogTheme {
    struct Palette {
        let background: Color
        let surface: Color
        let surfaceRaised: Color
        let text: Color
        let secondary: Color
        let tertiary: Color
        let accent: Color
        let accentSoft: Color
        let border: Color
        let success: Color
        let warning: Color
        let danger: Color
        let shadow: Color
    }

    static func palette(_ scheme: ColorScheme) -> Palette {
        if scheme == .dark {
            return Palette(
                background: Color(hex: 0x0E1013),
                surface: Color(hex: 0x171A1F),
                surfaceRaised: Color(hex: 0x20242A),
                text: Color(hex: 0xF3F0E9),
                secondary: Color(hex: 0xA9A69F),
                tertiary: Color(hex: 0x74736F),
                accent: Color(hex: 0xD89A7E),
                accentSoft: Color(hex: 0x4A352D),
                border: Color(hex: 0x2B2F35),
                success: Color(hex: 0x7FB69A),
                warning: Color(hex: 0xD7B36A),
                danger: Color(hex: 0xD47C70),
                shadow: Color.black.opacity(0.35)
            )
        }
        return Palette(
            background: Color(hex: 0xF5F1E8),
            surface: Color(hex: 0xFDFBF6),
            surfaceRaised: Color(hex: 0xFFFFFF),
            text: Color(hex: 0x1F1C18),
            secondary: Color(hex: 0x6A635A),
            tertiary: Color(hex: 0x948C81),
            accent: Color(hex: 0xA84F3A),
            accentSoft: Color(hex: 0xF1DED4),
            border: Color(hex: 0xE4DCCC),
            success: Color(hex: 0x4E8067),
            warning: Color(hex: 0xA8803E),
            danger: Color(hex: 0xA84F3A),
            shadow: Color(hex: 0x3B2E1D).opacity(0.09)
        )
    }

    static func serif(_ size: CGFloat, relativeTo: Font.TextStyle = .title) -> Font {
        Font.custom("Georgia", size: size, relativeTo: relativeTo)
    }

    static func sans(_ size: CGFloat, weight: Font.Weight = .regular, relativeTo: Font.TextStyle = .body) -> Font {
        Font.system(size: size, weight: weight, relativeTo: relativeTo, design: .default)
    }
}

struct LifelogPaletteKey: EnvironmentKey {
    static let defaultValue = LifelogTheme.palette(.light)
}

extension EnvironmentValues {
    var lifelogPalette: LifelogTheme.Palette {
        get { self[LifelogPaletteKey.self] }
        set { self[LifelogPaletteKey.self] = newValue }
    }
}

extension Color {
    init(hex: UInt32, opacity: Double = 1) {
        self.init(
            .sRGB,
            red: Double((hex >> 16) & 0xFF) / 255,
            green: Double((hex >> 8) & 0xFF) / 255,
            blue: Double(hex & 0xFF) / 255,
            opacity: opacity
        )
    }
}

// MARK: - Reusable styling

struct CardBackground: ViewModifier {
    @Environment(\.lifelogPalette) private var palette
    var padding: CGFloat = 18
    var radius: CGFloat = 20

    func body(content: Content) -> some View {
        content
            .padding(padding)
            .background(
                RoundedRectangle(cornerRadius: radius, style: .continuous)
                    .fill(palette.surface)
            )
            .overlay(
                RoundedRectangle(cornerRadius: radius, style: .continuous)
                    .stroke(palette.border, lineWidth: 0.8)
            )
            .shadow(color: palette.shadow, radius: 10, x: 0, y: 4)
    }
}

struct SoftButtonStyle: ButtonStyle {
    @Environment(\.lifelogPalette) private var palette
    var prominent = false

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(LifelogTheme.sans(14, weight: .semibold))
            .foregroundStyle(prominent ? palette.background : palette.text)
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .background(
                Capsule().fill(prominent ? palette.accent : palette.surfaceRaised)
            )
            .overlay(
                Capsule().stroke(prominent ? Color.clear : palette.border, lineWidth: 0.8)
            )
            .opacity(configuration.isPressed ? 0.75 : 1)
            .scaleEffect(configuration.isPressed ? 0.97 : 1)
    }
}

extension View {
    func lifelogCard(padding: CGFloat = 18, radius: CGFloat = 20) -> some View {
        modifier(CardBackground(padding: padding, radius: radius))
    }

    func lifelogScreenBackground() -> some View {
        modifier(ScreenBackground())
    }
}

struct ScreenBackground: ViewModifier {
    @Environment(\.lifelogPalette) private var palette

    func body(content: Content) -> some View {
        ZStack {
            palette.background.ignoresSafeArea()
            // A quiet, paper-like wash rather than a flat fill.
            LinearGradient(
                colors: [palette.accent.opacity(0.055), Color.clear],
                startPoint: .topLeading,
                endPoint: .center
            )
            .ignoresSafeArea()
            content
        }
    }
}

struct PaletteProvider: ViewModifier {
    @Environment(\.colorScheme) private var scheme

    func body(content: Content) -> some View {
        content.environment(\.lifelogPalette, LifelogTheme.palette(scheme))
    }
}

extension View {
    func lifelogPaletteProvider() -> some View { modifier(PaletteProvider()) }
}
