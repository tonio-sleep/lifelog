import SwiftUI

/// The most recent scrobble for the selected day. Lifelog only learns about a
/// play after it has been scrobbled, so the label says "just played", not live.
struct LastPlayedCard: View {
    @EnvironmentObject private var env: AppEnvironment
    @EnvironmentObject private var navigator: Navigator
    let scrobbles: [MusicScrobble]
    let day: Date

    @State private var syncing = false

    private var latest: MusicScrobble? { scrobbles.last }

    var body: some View {
        VStack(alignment: .leading, spacing: Space.sm) {
            SectionLabel(
                title: "Listening",
                detail: scrobbles.isEmpty ? nil : "\(scrobbles.count) \(Dates.plural(scrobbles.count, "track"))"
            )

            if let track = latest {
                Button { navigator.push(.journal(day)) } label: {
                    trackPanel(track)
                }
                .buttonStyle(RowButtonStyle())
                .accessibilityElement(children: .combine)

                footer
            } else {
                emptyPanel
            }
        }
    }

    // MARK: Track

    @ViewBuilder
    private func trackPanel(_ track: MusicScrobble) -> some View {
        let recent = Date().timeIntervalSince(track.playedAt) < 300 &&
            Dates.sameDay(track.playedAt, Date())

        HStack(alignment: .center, spacing: Space.md) {
            if env.settings.showArtwork {
                RemoteArtwork(urlString: track.artworkUrl)
                    .frame(width: 58, height: 58)
                    .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
            }

            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    MiniEqualizer(active: recent)
                    Text(recent ? "Just played" : "Last played")
                        .font(Typeface.micro)
                        .foregroundStyle(Palette.accent)
                }
                Text(track.displayTitle)
                    .font(Typeface.bodyStrong)
                    .foregroundStyle(Palette.ink)
                    .lineLimit(1)
                Text(track.displayArtist)
                    .font(Typeface.label)
                    .foregroundStyle(Palette.inkSecondary)
                    .lineLimit(1)
            }

            Spacer(minLength: Space.xs)

            Text(MomentText.relative(track.playedAt))
                .font(Typeface.micro)
                .foregroundStyle(Palette.inkTertiary)
                .fixedSize(horizontal: true, vertical: false)
        }
        .padding(Space.md)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Palette.surface, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .strokeBorder(Palette.line, lineWidth: 0.5)
        )
    }

    @ViewBuilder
    private var footer: some View {
        let summary = MusicDaySummary.fromScrobbles(scrobbles)
        HStack(spacing: Space.md) {
            if let artist = summary.topArtistName {
                Text("Most played: \(artist)")
                    .font(Typeface.caption)
                    .foregroundStyle(Palette.inkSecondary)
                    .lineLimit(1)
            }
            Spacer(minLength: 0)
            if env.settings.lastfmConnected {
                Button { Task { await sync() } } label: {
                    HStack(spacing: 4) {
                        if syncing {
                            ProgressView().scaleEffect(0.7)
                        } else {
                            Image(systemName: "arrow.clockwise")
                        }
                        Text("Sync")
                    }
                    .font(Typeface.micro)
                    .foregroundStyle(Palette.accent)
                    .frame(minHeight: 32)
                }
                .buttonStyle(.plain)
                .disabled(syncing)
                .accessibilityLabel("Sync listening history")
            }
        }
        .padding(.horizontal, Space.xs)
    }

    // MARK: Empty

    private var emptyPanel: some View {
        VStack(alignment: .leading, spacing: Space.sm) {
            Text(env.settings.lastfmConnected
                 ? "No tracks were scrobbled on this day."
                 : "Connect Last.fm to bring in what you listened to.")
                .font(Typeface.label)
                .foregroundStyle(Palette.inkSecondary)
                .fixedSize(horizontal: false, vertical: true)

            HStack(spacing: Space.md) {
                Button("Add a track") { navigator.present(.addTrack) }
                    .buttonStyle(QuietButtonStyle())
                if !env.settings.lastfmConnected {
                    Button("Connect Last.fm") { navigator.present(.lastfmConnect) }
                        .buttonStyle(QuietButtonStyle())
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(Space.md)
        .background(Palette.surface, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .strokeBorder(Palette.line, lineWidth: 0.5)
        )
    }

    @MainActor
    private func sync() async {
        syncing = true
        if let added = await env.syncLastfm() {
            env.present(added == 0 ? "Listening is up to date." : "Added \(added) \(Dates.plural(added, "track")).")
        }
        syncing = false
    }
}
