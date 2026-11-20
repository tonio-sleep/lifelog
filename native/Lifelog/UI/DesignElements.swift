import SwiftUI
import UIKit

/// The flat serif monogram. No gradient, no icon-set glyph, no glow.
struct LifelogMark: View {
    var size: CGFloat = 36

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: size * 0.28, style: .continuous)
                .fill(Palette.accent)
            Text("L")
                .font(.system(size: size * 0.58, design: .serif).weight(.semibold))
                .foregroundStyle(Palette.onAccent)
                .offset(y: -size * 0.02)
        }
        .frame(width: size, height: size)
        .accessibilityHidden(true)
    }
}

/// Small, quiet feedback. Taps should feel physical without becoming a game.
enum Taptic {
    static func selection() {
        let generator = UISelectionFeedbackGenerator()
        generator.selectionChanged()
    }

    static func tap() {
        let generator = UIImpactFeedbackGenerator(style: .light)
        generator.impactOccurred()
    }
}

/// Three bars for a recently played track. Static when motion is reduced.
struct MiniEqualizer: View {
    var active: Bool
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var heights: [CGFloat] = [3, 7, 5]

    var body: some View {
        HStack(alignment: .bottom, spacing: 2) {
            ForEach(0..<3, id: \.self) { index in
                Capsule()
                    .fill(Palette.accent)
                    .frame(width: 2.5, height: heights[index])
            }
        }
        .frame(width: 12, height: 12, alignment: .bottom)
        .onAppear { update() }
        .onChange(of: active) { _, _ in update() }
        .accessibilityHidden(true)
    }

    private func update() {
        guard active, !reduceMotion else {
            withAnimation(nil) { heights = [3, 7, 5] }
            return
        }
        withAnimation(.easeInOut(duration: 0.55).repeatForever(autoreverses: true)) {
            heights = [9, 4, 7]
        }
    }
}

/// Short human time labels. "Just now" beats a timestamp for recent plays.
enum MomentText {
    static func relative(_ date: Date, now: Date = Date()) -> String {
        let seconds = max(0, Int(now.timeIntervalSince(date)))
        if seconds < 60 { return "Just now" }
        let minutes = seconds / 60
        if minutes < 60 { return "\(minutes) min ago" }
        let hours = minutes / 60
        if hours < 24 { return "\(hours) h ago" }
        if hours < 48 { return "Yesterday" }
        return Dates.formatShortDate(date)
    }
}
