import SwiftUI
import UIKit
import UIKit.UIGestureRecognizerSubclass

/// Runs pure, CPU-bound work off the main actor.
func offMain<T>(_ work: @escaping @Sendable () -> T) async -> T {
    await Task.detached(priority: .userInitiated, operation: work).value
}

/// Locale-tolerant number parsing, so "7,5" and "7.5" both work.
enum NumberInput {
    static func double(_ text: String) -> Double? {
        let cleaned = text
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: ",", with: ".")
        guard !cleaned.isEmpty, let value = Double(cleaned), value.isFinite else { return nil }
        return value
    }

    static func int(_ text: String) -> Int? {
        guard let value = double(text), value >= 0, value < 10_000_000 else { return nil }
        return Int(value.rounded())
    }

    static func display(_ value: Double?) -> String {
        guard let value else { return "" }
        return Dates.formatCompactNumber(value)
    }
}

// MARK: - Idle tracking

/// Remembers when the screen was last touched without touching SwiftUI state, so
/// tracking activity never re-renders any view.
final class ActivityClock {
    static let shared = ActivityClock()
    private(set) var lastTouch = Date()
    private var installed = false

    func touch() { lastTouch = Date() }
    func reset() { lastTouch = Date() }

    var idleSeconds: TimeInterval { Date().timeIntervalSince(lastTouch) }

    /// Installs a passive recognizer on the key window. It never claims a touch.
    @MainActor
    func installIfNeeded() {
        guard !installed else { return }
        let windows = UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .flatMap { $0.windows }
        guard let window = windows.first(where: { $0.isKeyWindow }) ?? windows.first else { return }
        let sniffer = TouchSniffer()
        sniffer.cancelsTouchesInView = false
        sniffer.delaysTouchesBegan = false
        sniffer.delaysTouchesEnded = false
        window.addGestureRecognizer(sniffer)
        installed = true
    }
}

private final class TouchSniffer: UIGestureRecognizer {
    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent) {
        ActivityClock.shared.touch()
        state = .failed
    }
}

// MARK: - Journal helpers

extension JournalEntry {
    /// An entry that only carries Health numbers (steps/sleep), as written by sync.
    var isMetricsOnly: Bool {
        let blank = { (text: String) in text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
        return blank(title) && blank(body) && blank(highlight) && blank(meals)
            && !hasVocabContent && tags.isEmpty && mood == nil && energy == nil
            && (steps != nil || sleepHours != nil)
    }
}

// MARK: - Day rows

/// A display-ready timeline row. Built once per archive revision, off the main thread.
struct DayRow: Identifiable {
    var id: String
    var at: Date
    var title: String
    var subtitle: String
    var source: TimelineSource
    var suggested: Bool
    var sourceId: String?
    var hidden = false

    static func rows(_ archive: Archive, _ day: Date, includeHidden: Bool = false) -> [DayRow] {
        let hiddenEventIds = Set(archive.events.filter(\.hidden).map(\.id))
        return buildTimelineForDay(archive, day, includeHidden: includeHidden).map { item in
            var title = item.title
            var subtitle = item.subtitle
            if item.source == .journal, let id = item.sourceId,
               let entry = archive.entryById(id), entry.isMetricsOnly {
                title = "Sleep and steps"
                var parts: [String] = []
                if let sleep = entry.sleepHours { parts.append(Dates.formatCompactNumber(sleep) + " h sleep") }
                if let steps = entry.steps { parts.append("\(steps) steps") }
                subtitle = parts.joined(separator: " · ")
            }
            return DayRow(
                id: item.id,
                at: item.at,
                title: title,
                subtitle: subtitle,
                source: item.source,
                suggested: item.confidence == .suggested,
                sourceId: item.sourceId,
                hidden: item.source == .manual && hiddenEventIds.contains(item.sourceId ?? "")
            )
        }
    }
}

extension TimelineSource {
    var symbol: String {
        switch self {
        case .journal: return "book.closed"
        case .tracker: return "checkmark.circle"
        case .location: return "mappin"
        case .music: return "music.note"
        case .photo: return "photo"
        case .manual: return "sparkle"
        }
    }
}

extension Date {
    /// The creation time for something added "to" a day: now for today, noon otherwise.
    var momentForDay: Date { Dates.momentForDay(self) }
}
