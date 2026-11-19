import SwiftUI
import UIKit

struct SectionHeader: View {
    @Environment(\.lifelogPalette) private var palette
    let title: String
    var subtitle: String?
    var action: (() -> Void)?
    var actionLabel: String = "See all"

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(LifelogTheme.serif(21, relativeTo: .title2))
                    .foregroundStyle(palette.text)
                if let subtitle {
                    Text(subtitle)
                        .font(LifelogTheme.sans(13))
                        .foregroundStyle(palette.secondary)
                }
            }
            Spacer(minLength: 8)
            if let action {
                Button(action: action) {
                    Text(actionLabel)
                        .font(LifelogTheme.sans(13, weight: .semibold))
                        .foregroundStyle(palette.accent)
                }
                .buttonStyle(.plain)
            }
        }
    }
}

struct Eyebrow: View {
    @Environment(\.lifelogPalette) private var palette
    let text: String

    var body: some View {
        Text(text.uppercased())
            .font(LifelogTheme.sans(10, weight: .bold))
            .tracking(1.4)
            .foregroundStyle(palette.tertiary)
    }
}

struct StatTile: View {
    @Environment(\.lifelogPalette) private var palette
    let value: String
    let label: String
    var systemImage: String?
    var accent: Bool = false

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                if let systemImage {
                    Image(systemName: systemImage)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(accent ? palette.accent : palette.secondary)
                }
                Eyebrow(text: label)
            }
            Text(value)
                .font(LifelogTheme.serif(28, relativeTo: .title))
                .foregroundStyle(palette.text)
                .lineLimit(1)
                .minimumScaleFactor(0.75)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .lifelogCard(padding: 16, radius: 16)
    }
}

struct TagPill: View {
    @Environment(\.lifelogPalette) private var palette
    let text: String

    var body: some View {
        Text(text.hasPrefix("#") ? text : "#\(text)")
            .font(LifelogTheme.sans(11, weight: .medium))
            .foregroundStyle(palette.secondary)
            .padding(.horizontal, 9)
            .padding(.vertical, 5)
            .background(Capsule().fill(palette.surfaceRaised))
            .overlay(Capsule().stroke(palette.border, lineWidth: 0.6))
    }
}

struct EmptyState: View {
    @Environment(\.lifelogPalette) private var palette
    let title: String
    let message: String
    var systemImage: String = "book.closed"
    var action: (() -> Void)?
    var actionTitle: String = "Add entry"

    var body: some View {
        VStack(spacing: 14) {
            ZStack {
                Circle().fill(palette.accentSoft.opacity(0.55))
                    .frame(width: 62, height: 62)
                Image(systemName: systemImage)
                    .font(.system(size: 24, weight: .light))
                    .foregroundStyle(palette.accent)
            }
            Text(title)
                .font(LifelogTheme.serif(20, relativeTo: .title3))
                .foregroundStyle(palette.text)
            Text(message)
                .font(LifelogTheme.sans(14))
                .foregroundStyle(palette.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 340)
            if let action {
                Button(action: action) {
                    Text(actionTitle)
                }
                .buttonStyle(.borderedProminent)
                .tint(palette.accent)
            }
        }
        .padding(.vertical, 34)
        .frame(maxWidth: .infinity)
    }
}

struct EncryptedMediaImage: View {
    @EnvironmentObject private var env: AppEnvironment
    @Environment(\.lifelogPalette) private var palette
    let item: MediaItem
    var thumbnail: Bool = true
    var contentMode: ContentMode = .fill

    @State private var image: UIImage?
    @State private var isLoading = true

    var body: some View {
        ZStack {
            if let image {
                Image(uiImage: image)
                    .resizable()
                    .aspectRatio(contentMode: contentMode)
            } else {
                Rectangle().fill(palette.surfaceRaised)
                if isLoading {
                    ProgressView().tint(palette.secondary)
                } else {
                    Image(systemName: item.isVideo ? "video" : item.isAudio ? "waveform" : "photo")
                        .font(.system(size: 24, weight: .light))
                        .foregroundStyle(palette.tertiary)
                }
            }
        }
        .clipped()
        .task(id: item.id) {
            isLoading = true
            let data = thumbnail ? (try? env.mediaStore.readThumbnail(item)) : (try? env.mediaStore.readOriginal(item))
            image = data.flatMap { UIImage(data: $0) }
            isLoading = false
        }
    }
}

struct RemoteArtwork: View {
    let urlString: String?
    @Environment(\.lifelogPalette) private var palette

    var body: some View {
        Group {
            if let urlString, let url = URL(string: urlString), !urlString.isEmpty {
                AsyncImage(url: url) { phase in
                    switch phase {
                    case .success(let image):
                        image.resizable().aspectRatio(contentMode: .fill)
                    default:
                        placeholder
                    }
                }
            } else {
                placeholder
            }
        }
        .clipped()
    }

    private var placeholder: some View {
        ZStack {
            palette.accentSoft
            Image(systemName: "music.note")
                .foregroundStyle(palette.accent)
        }
    }
}

struct TimelineRow: View {
    @Environment(\.lifelogPalette) private var palette
    let item: TimelineItem

    var body: some View {
        HStack(alignment: .top, spacing: 14) {
            VStack(spacing: 6) {
                Text(Dates.formatTime(item.at))
                    .font(LifelogTheme.sans(11, weight: .semibold))
                    .foregroundStyle(palette.secondary)
                    .frame(width: 48)
                Circle()
                    .fill(item.confidence == .suggested ? palette.tertiary : palette.accent)
                    .frame(width: 7, height: 7)
            }
            VStack(alignment: .leading, spacing: 5) {
                HStack(spacing: 7) {
                    Image(systemName: icon)
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(palette.accent)
                    Text(item.title)
                        .font(LifelogTheme.sans(15, weight: .semibold))
                        .foregroundStyle(palette.text)
                        .lineLimit(2)
                    if item.confidence == .suggested {
                        Text("Suggested")
                            .font(LifelogTheme.sans(9, weight: .bold))
                            .foregroundStyle(palette.tertiary)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 3)
                            .background(Capsule().fill(palette.surfaceRaised))
                    }
                }
                if !item.subtitle.isEmpty {
                    Text(item.subtitle)
                        .font(LifelogTheme.sans(13))
                        .foregroundStyle(palette.secondary)
                        .lineLimit(2)
                }
            }
            Spacer(minLength: 4)
        }
        .padding(.vertical, 10)
        .padding(.horizontal, 14)
        .background(
            RoundedRectangle(cornerRadius: 15, style: .continuous)
                .fill(palette.surface)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 15, style: .continuous)
                .stroke(palette.border, lineWidth: 0.7)
        )
    }

    private var icon: String {
        switch item.source {
        case .journal: return "book.closed"
        case .tracker: return "checkmark.circle"
        case .location: return "mappin"
        case .music: return "music.note"
        case .photo: return "photo"
        case .manual: return "sparkle"
        }
    }
}

struct BarChart: View {
    @Environment(\.lifelogPalette) private var palette
    let values: [Double]
    var labels: [String] = []
    var height: CGFloat = 90

    var body: some View {
        let maxValue = max(values.max() ?? 1, 1)
        HStack(alignment: .bottom, spacing: 6) {
            ForEach(Array(values.enumerated()), id: \.offset) { index, value in
                VStack(spacing: 5) {
                    RoundedRectangle(cornerRadius: 4, style: .continuous)
                        .fill(value > 0 ? palette.accent.opacity(0.85) : palette.border)
                        .frame(height: max(3, CGFloat(value / maxValue) * height))
                    if index < labels.count {
                        Text(labels[index])
                            .font(LifelogTheme.sans(9))
                            .foregroundStyle(palette.tertiary)
                            .lineLimit(1)
                    }
                }
                .frame(maxWidth: .infinity)
            }
        }
        .frame(height: height + 18)
    }
}

struct LabeledDivider: View {
    @Environment(\.lifelogPalette) private var palette
    let label: String

    var body: some View {
        HStack {
            Rectangle().fill(palette.border).frame(height: 1)
            Text(label)
                .font(LifelogTheme.sans(10, weight: .semibold))
                .foregroundStyle(palette.tertiary)
            Rectangle().fill(palette.border).frame(height: 1)
        }
    }
}
