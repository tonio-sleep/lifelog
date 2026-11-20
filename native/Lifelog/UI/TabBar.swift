import SwiftUI
import UIKit

/// A quiet floating bar. The system tab bar is not used on iPhone, so the bar
/// can be thin, tinted, and entirely under our control.
struct LifelogTabBar: View {
    @EnvironmentObject private var navigator: Navigator
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        HStack(spacing: 0) {
            ForEach(Destination.allCases) { destination in
                let chosen = navigator.selection == destination
                Button { select(destination) } label: {
                    VStack(spacing: 3) {
                        Image(systemName: destination.symbol)
                            .font(.system(size: 19, weight: chosen ? .semibold : .regular))
                        Text(destination.title)
                            .font(Typeface.micro)
                            .lineLimit(1)
                    }
                    .foregroundStyle(chosen ? Palette.accent : Palette.inkTertiary)
                    .frame(maxWidth: .infinity, minHeight: 44)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(destination.title)
                .accessibilityAddTraits(chosen ? .isSelected : [])
            }
        }
        .padding(.horizontal, 6)
        .padding(.top, 8)
        .padding(.bottom, homeInset + 8)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 26, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 26, style: .continuous)
                .strokeBorder(Palette.line, lineWidth: 0.5)
        )
        .shadow(color: Color.black.opacity(0.10), radius: 16, y: 6)
        .padding(.horizontal, 14)
        .animation(reduceMotion ? nil : Animation.snappy(duration: 0.22), value: navigator.selection)
    }

    private func select(_ destination: Destination) {
        guard navigator.selection != destination else { return }
        Taptic.selection()
        navigator.selection = destination
    }

    private var homeInset: CGFloat {
        UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .flatMap { $0.windows }
            .first(where: { $0.isKeyWindow })?.safeAreaInsets.bottom ?? 0
    }
}
