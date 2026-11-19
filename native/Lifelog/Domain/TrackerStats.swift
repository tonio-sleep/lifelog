import Foundation

/// Pure aggregation helpers for tracker records.
enum TrackerMath {
    static func recordsOn(_ records: [TrackerRecord], trackerId: String, day: Date) -> [TrackerRecord] {
        records.filter { $0.trackerId == trackerId && Dates.sameDay($0.recordedAt, day) }
            .sorted { $0.recordedAt < $1.recordedAt }
    }

    static func loggedOn(_ records: [TrackerRecord], trackerId: String, day: Date) -> Bool {
        records.contains { $0.trackerId == trackerId && Dates.sameDay($0.recordedAt, day) }
    }

    /// Missing values count as 1 here (asymmetric with averageOn).
    static func totalOn(_ records: [TrackerRecord], trackerId: String, day: Date) -> Double {
        recordsOn(records, trackerId: trackerId, day: day)
            .reduce(0) { $0 + ($1.value ?? 1) }
    }

    /// Missing values count as 0 here (asymmetric with totalOn).
    static func averageOn(_ records: [TrackerRecord], trackerId: String, day: Date) -> Double? {
        let matching = recordsOn(records, trackerId: trackerId, day: day)
        guard !matching.isEmpty else { return nil }
        return matching.reduce(0) { $0 + ($1.value ?? 0) } / Double(matching.count)
    }

    static func dailyLabel(_ tracker: TrackerDefinition, _ records: [TrackerRecord], _ day: Date) -> String? {
        let matching = recordsOn(records, trackerId: tracker.id, day: day)
        guard !matching.isEmpty else { return nil }

        func withDurationAndCount(_ base: String) -> String {
            var out = base
            let extraCount = matching.reduce(0) { $0 + ($1.count ?? 0) }
            if extraCount > 0 && tracker.type != .count && tracker.type != .event {
                out += " · \(Dates.formatCompactNumber(extraCount))×"
            }
            let mins = matching.reduce(0) { $0 + ($1.effectiveDurationMinutes ?? 0) }
            if mins > 0 { out += " · \(Dates.formatDurationMinutes(mins))" }
            return out
        }

        switch tracker.type {
        case .boolean:
            let yes = matching.contains { ($0.value ?? 0) > 0 }
            return withDurationAndCount(yes ? "Yes" : "No")
        case .count, .event:
            let total = SafeNumber.int(totalOn(records, trackerId: tracker.id, day: day)) ?? 0
            return withDurationAndCount(total == 1 ? "1 time" : "\(total) times")
        case .duration:
            let mins = matching.reduce(0) { $0 + ($1.value ?? $1.effectiveDurationMinutes ?? 0) }
            let fallback = totalOn(records, trackerId: tracker.id, day: day)
            return withDurationAndCount(Dates.formatDurationMinutes(mins <= 0 ? fallback : mins))
        case .number:
            let total = totalOn(records, trackerId: tracker.id, day: day)
            let unit = tracker.unit.trimmingCharacters(in: .whitespacesAndNewlines)
            return withDurationAndCount("\(Dates.formatCompactNumber(total))\(unit.isEmpty ? "" : " \(unit)")")
        case .rating:
            let average = averageOn(records, trackerId: tracker.id, day: day) ?? 0
            return withDurationAndCount(String(format: "%.1f / 5", average))
        case .text:
            if matching.count == 1 {
                return withDurationAndCount(matching[0].text.isEmpty ? "1 note" : matching[0].text)
            }
            return withDurationAndCount("\(matching.count) notes")
        }
    }

    static func recordLabel(_ tracker: TrackerDefinition, _ record: TrackerRecord) -> String {
        var parts: [String] = []
        switch tracker.type {
        case .boolean:
            parts.append((record.value ?? 0) > 0 ? "Yes" : "No")
        case .count, .event:
            parts.append("\(Dates.formatCompactNumber(record.value ?? record.count ?? 1))×")
        case .duration:
            parts.append(Dates.formatDurationMinutes(record.value ?? record.effectiveDurationMinutes ?? 0))
        case .number:
            let value = Dates.formatCompactNumber(record.value ?? 0)
            let unit = tracker.unit.trimmingCharacters(in: .whitespacesAndNewlines)
            parts.append(unit.isEmpty ? value : "\(value) \(unit)")
        case .rating:
            parts.append("\(Dates.formatCompactNumber(record.value ?? 0)) / 5")
        case .text:
            parts.append(record.text.isEmpty ? "Note" : record.text)
        }
        if tracker.type != .count && tracker.type != .event,
           let count = record.count, count > 0 {
            parts.append("\(Dates.formatCompactNumber(count))×")
        }
        if let duration = record.effectiveDurationMinutes, duration > 0, tracker.type != .duration {
            parts.append(Dates.formatDurationMinutes(duration))
        }
        if let start = record.startedAt, let end = record.endedAt {
            parts.append("\(Dates.formatTime(start))–\(Dates.formatTime(end))")
        } else if let start = record.startedAt {
            parts.append(Dates.formatTime(start))
        }
        return parts.isEmpty ? "Logged" : parts.joined(separator: " · ")
    }

    static func dailySeries(
        _ tracker: TrackerDefinition,
        _ records: [TrackerRecord],
        endDay: Date,
        days: Int
    ) -> [(day: Date, value: Double)] {
        let end = Dates.dayStart(endDay)
        return (0..<days).map { index in
            let day = Dates.addingDays(index - (days - 1), to: end)
            let value: Double
            switch tracker.type {
            case .rating:
                value = averageOn(records, trackerId: tracker.id, day: day) ?? 0
            case .boolean:
                value = loggedOn(records, trackerId: tracker.id, day: day) ? 1 : 0
            case .text:
                value = Double(recordsOn(records, trackerId: tracker.id, day: day).count)
            default:
                value = totalOn(records, trackerId: tracker.id, day: day)
            }
            return (day, value)
        }
    }
}

/// Per-tracker history indexed by day. Build one per tracker per frame, not per cell.
struct HabitHistory {
    let tracker: TrackerDefinition
    private var totals: [String: Double] = [:]
    private var logged: Set<String> = []
    private var positive: Set<String> = []

    init(_ tracker: TrackerDefinition, _ records: [TrackerRecord]) {
        self.tracker = tracker
        for record in records where record.trackerId == tracker.id {
            let key = Dates.dayKey(record.recordedAt)
            let value = record.value ?? 1
            totals[key, default: 0] += value
            logged.insert(key)
            if value > 0 { positive.insert(key) }
        }
    }

    private func doneKey(_ key: String) -> Bool {
        switch tracker.type {
        case .boolean:
            return positive.contains(key)
        case .count, .number, .duration, .event:
            if let target = tracker.target, target > 0 {
                return (totals[key] ?? 0) >= target
            }
            return logged.contains(key)
        case .rating, .text:
            return logged.contains(key)
        }
    }

    func loggedOn(_ day: Date) -> Bool { logged.contains(Dates.dayKey(day)) }

    func skippedOn(_ day: Date) -> Bool {
        let key = Dates.dayKey(day)
        return tracker.type == .boolean && logged.contains(key) && !positive.contains(key)
    }

    func doneOn(_ day: Date) -> Bool { doneKey(Dates.dayKey(day)) }
    func totalOn(_ day: Date) -> Double { totals[Dates.dayKey(day)] ?? 0 }

    func progressOn(_ day: Date) -> Double {
        let key = Dates.dayKey(day)
        let numeric = [TrackerType.count, .number, .duration, .event].contains(tracker.type)
        if numeric, let target = tracker.target, target > 0 {
            return min(1, max(0, (totals[key] ?? 0) / target))
        }
        return doneKey(key) ? 1 : 0
    }

    func currentStreak(_ today: Date) -> Int {
        var cursor = Dates.dayStart(today)
        if !doneOn(cursor) { cursor = Dates.addingDays(-1, to: cursor) }
        var streak = 0
        while doneOn(cursor) {
            streak += 1
            cursor = Dates.addingDays(-1, to: cursor)
        }
        return streak
    }

    func bestStreak() -> Int {
        let keys = logged.filter(doneKey).sorted()
        var best = 0
        var run = 0
        var previous: Date?
        for key in keys {
            let day = Dates.parseDayKey(key)
            if let previous, Dates.sameDay(day, Dates.addingDays(1, to: previous)) {
                run += 1
            } else {
                run = 1
            }
            best = max(best, run)
            previous = day
        }
        return best
    }

    func lastDays(_ end: Date, count: Int) -> [Bool] {
        let last = Dates.dayStart(end)
        return (0..<count).map { index in
            doneOn(Dates.addingDays(index - (count - 1), to: last))
        }
    }
}
