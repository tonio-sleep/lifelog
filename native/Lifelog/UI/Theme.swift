import SwiftUI
import UIKit

// MARK: - Color

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

private extension UIColor {
    convenience init(hex: UInt32) {
        self.init(
            red: CGFloat((hex >> 16) & 0xFF) / 255,
            green: CGFloat((hex >> 8) & 0xFF) / 255,
            blue: CGFloat(hex & 0xFF) / 255,
            alpha: 1
        )
    }
}

/// Warm paper and ink. Every color is dynamic, so it follows the real interface
/// style of whatever view it is drawn in (including sheets), with no environment
/// plumbing and no stale palette when the theme is forced.
enum Palette {
    private static func dynamic(light: UInt32, dark: UInt32) -> Color {
        Color(uiColor: UIColor { traits in
            traits.userInterfaceStyle == .dark ? UIColor(hex: dark) : UIColor(hex: light)
        })
    }

    static let paper = dynamic(light: 0xF6F2EA, dark: 0x121315)
    static let surface = dynamic(light: 0xFCFAF5, dark: 0x1B1C1F)
    static let raised = dynamic(light: 0xFFFFFF, dark: 0x25272B)
    static let ink = dynamic(light: 0x24211C, dark: 0xF2EEE5)
    static let inkSecondary = dynamic(light: 0x5F584D, dark: 0xB4AEA2)
    static let inkTertiary = dynamic(light: 0x756E62, dark: 0x8F897D)
    static let line = dynamic(light: 0xE2DACA, dark: 0x303236)
    static let accent = dynamic(light: 0x9A4733, dark: 0xE2A58A)
    static let accentSoft = dynamic(light: 0xF0DED3, dark: 0x3B2C26)
    static let onAccent = dynamic(light: 0xFFFFFF, dark: 0x1C1410)
    static let moss = dynamic(light: 0x47755E, dark: 0x8BBFA2)
    static let amber = dynamic(light: 0x92692A, dark: 0xDCB872)
    static let danger = dynamic(light: 0xA3362B, dark: 0xEB8F85)
}

// MARK: - Type

/// Semantic type roles built on text styles, so everything scales with Dynamic Type.
enum Typeface {
    static let display = Font.system(.largeTitle, design: .serif)
    static let title = Font.system(.title2, design: .serif)
    static let heading = Font.system(.title3, design: .serif)
    static let reading = Font.system(.body, design: .serif)
    static let readingLarge = Font.system(.title3, design: .serif)
    static let body = Font.system(.body)
    static let bodyStrong = Font.system(.body).weight(.semibold)
    static let label = Font.system(.subheadline)
    static let labelStrong = Font.system(.subheadline).weight(.semibold)
    static let caption = Font.system(.footnote)
    static let captionStrong = Font.system(.footnote).weight(.semibold)
    static let micro = Font.system(.caption).weight(.medium)
    static let figure = Font.system(.title2, design: .serif).monospacedDigit()
}

enum Space {
    static let xs: CGFloat = 4
    static let sm: CGFloat = 8
    static let md: CGFloat = 12
    static let lg: CGFloat = 16
    static let xl: CGFloat = 24
    static let xxl: CGFloat = 36
    static let page: CGFloat = 20
}

// MARK: - Surfaces

struct Hairline: View {
    var body: some View {
        Rectangle()
            .fill(Palette.line)
            .frame(height: 0.5)
            .accessibilityHidden(true)
    }
}

private struct SurfaceModifier: ViewModifier {
    var padding: CGFloat
    var radius: CGFloat

    func body(content: Content) -> some View {
        content
            .padding(padding)
            .background(Palette.surface, in: RoundedRectangle(cornerRadius: radius, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: radius, style: .continuous)
                    .strokeBorder(Palette.line, lineWidth: 0.5)
            )
    }
}

private struct PaperScreenModifier: ViewModifier {
    func body(content: Content) -> some View {
        content.background(Palette.paper.ignoresSafeArea())
    }
}

extension View {
    /// A quiet panel: paper surface with a hairline edge and no shadow.
    func surface(padding: CGFloat = Space.lg, radius: CGFloat = 16) -> some View {
        modifier(SurfaceModifier(padding: padding, radius: radius))
    }

    func paperScreen() -> some View { modifier(PaperScreenModifier()) }

    /// Hides the default grouped-list background so the paper shows through.
    func paperList() -> some View {
        self.scrollContentBackground(.hidden).background(Palette.paper.ignoresSafeArea())
    }
}

// MARK: - Buttons

struct PrimaryButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(Typeface.labelStrong)
            .foregroundStyle(Palette.onAccent)
            .padding(.horizontal, Space.xl)
            .padding(.vertical, 13)
            .frame(maxWidth: .infinity, minHeight: 44)
            .background(Palette.accent, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            .opacity(isEnabled ? (configuration.isPressed ? 0.85 : 1) : 0.4)
    }
}

struct QuietButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(Typeface.labelStrong)
            .foregroundStyle(Palette.accent)
            .opacity(configuration.isPressed ? 0.6 : 1)
            .frame(minHeight: 44)
            .contentShape(Rectangle())
    }
}

struct ChipStyle: ButtonStyle {
    var selected: Bool

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(Typeface.micro)
            .foregroundStyle(selected ? Palette.onAccent : Palette.inkSecondary)
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(
                Capsule().fill(selected ? Palette.accent : Palette.surface)
            )
            .overlay(Capsule().strokeBorder(selected ? Color.clear : Palette.line, lineWidth: 0.5))
            .opacity(configuration.isPressed ? 0.8 : 1)
            .frame(minHeight: 44)
            .contentShape(Capsule())
    }
}

/// A plain row button that keeps the whole row tappable and gives gentle feedback.
struct RowButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .contentShape(Rectangle())
            .opacity(configuration.isPressed ? 0.6 : 1)
    }
}
