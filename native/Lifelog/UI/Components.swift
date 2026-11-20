import SwiftUI
import UIKit
import ImageIO

// MARK: - Headings

/// The quiet editorial header used at the top of each destination.
struct PageHeader: View {
    let eyebrow: String
    let title: String
    var subtitle: String?

    var body: some View {
        VStack(alignment: .leading, spacing: Space.xs) {
            Text(eyebrow)
                .font(Typeface.micro)
                .textCase(.uppercase)
                .tracking(1.2)
                .foregroundStyle(Palette.inkTertiary)
            Text(title)
                .font(Typeface.display)
                .foregroundStyle(Palette.ink)
                .fixedSize(horizontal: false, vertical: true)
            if let subtitle {
                Text(subtitle)
                    .font(Typeface.label)
                    .foregroundStyle(Palette.inkSecondary)
                    .padding(.top, 2)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isHeader)
    }
}

struct SectionLabel: View {
    let title: String
    var detail: String?
    var actionTitle: String?
    var action: (() -> Void)?

    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            Text(title)
                .font(Typeface.heading)
                .foregroundStyle(Palette.ink)
                .accessibilityAddTraits(.isHeader)
            if let detail {
                Text(detail)
                    .font(Typeface.caption)
                    .foregroundStyle(Palette.inkTertiary)
            }
            Spacer(minLength: Space.sm)
            if let actionTitle, let action {
                Button(actionTitle, action: action)
                    .buttonStyle(QuietButtonStyle())
            }
        }
    }
}

// MARK: - Empty and info states

/// Quiet, honest empty state. Built from what is actually (not) stored.
struct EmptyNote: View {
    let title: String
    let message: String
    var actionTitle: String?
    var action: (() -> Void)?

    var body: some View {
        VStack(alignment: .leading, spacing: Space.sm) {
            Text(title)
                .font(Typeface.bodyStrong)
                .foregroundStyle(Palette.ink)
            Text(message)
                .font(Typeface.label)
                .foregroundStyle(Palette.inkSecondary)
                .fixedSize(horizontal: false, vertical: true)
            if let actionTitle, let action {
                Button(actionTitle, action: action)
                    .buttonStyle(QuietButtonStyle())
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .contain)
    }
}

struct InfoLine: View {
    let text: String
    var symbol: String?

    var body: some View {
        HStack(alignment: .top, spacing: Space.sm) {
            if let symbol {
                Image(systemName: symbol)
                    .font(Typeface.caption)
                    .foregroundStyle(Palette.inkTertiary)
                    .accessibilityHidden(true)
            }
            Text(text)
                .font(Typeface.caption)
                .foregroundStyle(Palette.inkSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

// MARK: - Rows

struct SourceGlyph: View {
    let source: TimelineSource
    var suggested = false

    var body: some View {
        Image(systemName: source.symbol)
            .font(.system(.footnote).weight(.semibold))
            .foregroundStyle(suggested ? Palette.inkTertiary : Palette.accent)
            .frame(width: 32, height: 32)
            .background(
                Circle().fill(suggested ? Palette.surface : Palette.accentSoft)
            )
            .overlay(Circle().strokeBorder(suggested ? Palette.line : Color.clear, lineWidth: 0.5))
            .accessibilityHidden(true)
    }
}

/// One record in a day, drawn without a box: glyph, time, title, detail.
struct DayRowView: View {
    let row: DayRow

    var body: some View {
        HStack(alignment: .top, spacing: Space.md) {
            SourceGlyph(source: row.source, suggested: row.suggested)
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    Text(Dates.formatTime(row.at))
                        .monospacedDigit()
                    Text(row.source.label)
                    if row.suggested {
                        Text("· Suggested")
                    }
                    if row.hidden {
                        Text("· Hidden")
                    }
                }
                .font(Typeface.micro)
                .foregroundStyle(Palette.inkTertiary)
                Text(row.title)
                    .font(Typeface.bodyStrong)
                    .foregroundStyle(Palette.ink)
                    .multilineTextAlignment(.leading)
                if !row.subtitle.isEmpty {
                    Text(row.subtitle)
                        .font(Typeface.label)
                        .foregroundStyle(Palette.inkSecondary)
                        .lineLimit(3)
                        .multilineTextAlignment(.leading)
                }
            }
            Spacer(minLength: 0)
        }
        .padding(.vertical, Space.sm)
        .frame(maxWidth: .infinity, alignment: .leading)
        .opacity(row.hidden ? 0.6 : 1)
        .accessibilityElement(children: .combine)
    }
}

struct TagLine: View {
    let tags: [String]

    var body: some View {
        FlowLayout(spacing: 6) {
            ForEach(tags, id: \.self) { tag in
                Text(tag.hasPrefix("#") ? tag : "#\(tag)")
                    .font(Typeface.micro)
                    .foregroundStyle(Palette.inkSecondary)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .background(Capsule().fill(Palette.surface))
                    .overlay(Capsule().strokeBorder(Palette.line, lineWidth: 0.5))
            }
        }
    }
}

struct FlowLayout: Layout {
    var spacing: CGFloat = 8

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let width = proposal.width ?? .infinity
        var x: CGFloat = 0
        var y: CGFloat = 0
        var rowHeight: CGFloat = 0
        var widest: CGFloat = 0
        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if x > 0, x + size.width > width {
                x = 0
                y += rowHeight + spacing
                rowHeight = 0
            }
            x += size.width + spacing
            rowHeight = max(rowHeight, size.height)
            widest = max(widest, x - spacing)
        }
        return CGSize(width: proposal.width ?? widest, height: y + rowHeight)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var x = bounds.minX
        var y = bounds.minY
        var rowHeight: CGFloat = 0
        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if x > bounds.minX, x + size.width > bounds.maxX {
                x = bounds.minX
                y += rowHeight + spacing
                rowHeight = 0
            }
            subview.place(at: CGPoint(x: x, y: y), proposal: ProposedViewSize(size))
            x += size.width + spacing
            rowHeight = max(rowHeight, size.height)
        }
    }
}

/// A figure with a quiet label, used instead of boxed stat tiles.
struct Figure: View {
    let value: String
    let label: String

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(value)
                .font(Typeface.figure)
                .foregroundStyle(Palette.ink)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
            Text(label)
                .font(Typeface.micro)
                .foregroundStyle(Palette.inkTertiary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
    }
}

// MARK: - Toast

struct ToastBanner: View {
    let message: String

    var body: some View {
        Text(message)
            .font(Typeface.label)
            .foregroundStyle(Palette.ink)
            .multilineTextAlignment(.leading)
            .padding(.horizontal, Space.lg)
            .padding(.vertical, Space.md)
            .background(Palette.raised, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .strokeBorder(Palette.line, lineWidth: 0.5)
            )
            .padding(.horizontal, Space.page)
            .accessibilityAddTraits(.updatesFrequently)
    }
}

// MARK: - Media

enum MediaImageCache {
    static let cache = NSCache<NSString, UIImage>()
}

/// Decodes at the size it will be drawn instead of loading full photos.
func downsampledImage(_ data: Data, maxPixel: CGFloat) -> UIImage? {
    let sourceOptions: [CFString: Any] = [kCGImageSourceShouldCache: false]
    guard let source = CGImageSourceCreateWithData(data as CFData, sourceOptions as CFDictionary) else { return nil }
    let options: [CFString: Any] = [
        kCGImageSourceCreateThumbnailFromImageAlways: true,
        kCGImageSourceShouldCacheImmediately: true,
        kCGImageSourceCreateThumbnailWithTransform: true,
        kCGImageSourceThumbnailMaxPixelSize: maxPixel,
    ]
    guard let image = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else { return nil }
    return UIImage(cgImage: image)
}

/// Shows an encrypted photo. Decryption and decoding happen off the main thread.
struct EncryptedMediaImage: View {
    @EnvironmentObject private var env: AppEnvironment
    let item: MediaItem
    var fullSize = false
    var fit = false
    var maxPixel: CGFloat = 480

    @State private var image: UIImage?
    @State private var failed = false

    var body: some View {
        ZStack {
            Palette.surface
            if let image {
                Image(uiImage: image)
                    .resizable()
                    .aspectRatio(contentMode: fit ? .fit : .fill)
            } else {
                Image(systemName: placeholderSymbol)
                    .font(.system(.title3))
                    .foregroundStyle(Palette.inkTertiary)
                    .opacity(failed || !item.isImage ? 1 : 0.4)
            }
        }
        .clipped()
        .task(id: item.id) { await load() }
        .accessibilityLabel(item.displayCaption)
    }

    private var placeholderSymbol: String {
        if item.isVideo { return "video" }
        if item.isAudio { return "waveform" }
        return failed ? "photo.badge.exclamationmark" : "photo"
    }

    private func load() async {
        guard item.isImage else { return }
        let pixels = fullSize ? 2400 : maxPixel
        let key = "\(item.id)-\(Int(pixels))" as NSString
        if let cached = MediaImageCache.cache.object(forKey: key) {
            image = cached
            return
        }
        let store = env.mediaStore
        let media = item
        let useFull = fullSize
        let decoded: UIImage? = await offMain {
            guard let data = try? (useFull ? store.readOriginal(media) : store.readThumbnail(media)) else { return nil }
            return downsampledImage(data, maxPixel: pixels)
        }
        guard !Task.isCancelled else { return }
        if let decoded {
            MediaImageCache.cache.setObject(decoded, forKey: key)
            image = decoded
        } else {
            failed = true
        }
    }
}

struct RemoteArtwork: View {
    let urlString: String?

    var body: some View {
        Group {
            if let urlString, !urlString.isEmpty, let url = URL(string: urlString) {
                AsyncImage(url: url) { phase in
                    if let image = phase.image {
                        image.resizable().aspectRatio(contentMode: .fill)
                    } else {
                        placeholder
                    }
                }
            } else {
                placeholder
            }
        }
        .clipped()
        .accessibilityHidden(true)
    }

    private var placeholder: some View {
        ZStack {
            Palette.accentSoft
            Image(systemName: "music.note").foregroundStyle(Palette.accent)
        }
    }
}

// MARK: - Permission guidance

/// Inline explanation shown when a feature needs a permission that was declined.
struct PermissionNotice: View {
    let message: String

    var body: some View {
        VStack(alignment: .leading, spacing: Space.sm) {
            InfoLine(text: message, symbol: "lock")
            Button("Open Settings") { PermissionCenter.openSystemSettings() }
                .buttonStyle(QuietButtonStyle())
        }
        .surface(padding: Space.md, radius: 14)
    }
}
