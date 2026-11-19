import SwiftUI

struct OnboardingView: View {
    @EnvironmentObject private var env: AppEnvironment
    @Environment(\.lifelogPalette) private var palette
    @State private var page = 0

    private let pages: [(String, String, String)] = [
        ("One archive.", "Entries, photos, places, habits, and listening live in one encrypted archive.", "book.closed"),
        ("Private by default.", "Your journal stays on this device. Cloudflare sync and Last.fm are optional additions.", "lock.shield"),
        ("Begin gently.", "No streaks to protect and no perfect routine to keep. Record what matters, when it matters.", "leaf"),
    ]

    var body: some View {
        VStack(spacing: 26) {
            Spacer(minLength: 20)
            TabView(selection: $page) {
                ForEach(Array(pages.enumerated()), id: \.offset) { index, item in
                    VStack(spacing: 18) {
                        ZStack {
                            Circle().fill(palette.accentSoft).frame(width: 108, height: 108)
                            Image(systemName: item.2)
                                .font(.system(size: 38, weight: .light))
                                .foregroundStyle(palette.accent)
                        }
                        Text(item.0)
                            .font(LifelogTheme.serif(32, relativeTo: .largeTitle))
                            .foregroundStyle(palette.text)
                        Text(item.1)
                            .font(LifelogTheme.sans(15))
                            .foregroundStyle(palette.secondary)
                            .multilineTextAlignment(.center)
                            .frame(maxWidth: 340)
                    }
                    .tag(index)
                    .padding(.horizontal, 28)
                }
            }
            .tabViewStyle(.page(indexDisplayMode: .never))
            .frame(height: 360)

            HStack(spacing: 7) {
                ForEach(0..<pages.count, id: \.self) { index in
                    Capsule().fill(index == page ? palette.accent : palette.border)
                        .frame(width: index == page ? 22 : 7, height: 7)
                        .animation(.easeOut, value: page)
                }
            }

            VStack(spacing: 12) {
                Button {
                    if page < pages.count - 1 {
                        page += 1
                    } else {
                        env.settings.onboardingComplete = true
                        env.save()
                    }
                } label: {
                    Text(page == pages.count - 1 ? "Open my journal" : "Continue")
                        .font(LifelogTheme.sans(15, weight: .semibold))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 4)
                }
                .buttonStyle(.borderedProminent)
                .tint(palette.accent)
                .padding(.horizontal, 32)

                if page < pages.count - 1 {
                    Button("Skip") {
                        env.settings.onboardingComplete = true
                        env.save()
                    }
                    .font(LifelogTheme.sans(12))
                    .foregroundStyle(palette.secondary)
                }
            }
            Spacer()
        }
        .lifelogScreenBackground()
    }
}
