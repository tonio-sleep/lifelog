import Foundation

// MARK: - ISO 8601 codec matching Dart's DateTime.toIso8601String()

/// Dart writes local wall-clock ISO strings such as `2026-11-18T14:03:00.000`
/// and UTC strings such as `2026-11-18T14:03:00.000Z`. It always writes three
/// millisecond digits and appends three more digits only when microseconds are
/// non-zero. ISO8601DateFormatter cannot express that exactly, so the codec is
/// implemented directly against Gregorian date components.
enum DateCodec {
    static func parse(_ value: String?) -> Date? {
        guard let value, !value.isEmpty else { return nil }
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        let chars = Array(trimmed)
        guard chars.count >= 19,
              chars[10] == "T",
              let year = number(chars, 0, 4),
              let month = number(chars, 5, 2),
              let day = number(chars, 8, 2),
              let hour = number(chars, 11, 2),
              let minute = number(chars, 14, 2),
              let second = number(chars, 17, 2) else {
            return fallbackParse(trimmed)
        }
        guard chars[4] == "-", chars[7] == "-",
              chars[13] == ":", chars[16] == ":" else {
            return fallbackParse(trimmed)
        }

        var index = 19
        var nanosecond = 0
        if index < chars.count, chars[index] == "." {
            index += 1
            let start = index
            var fraction = ""
            while index < chars.count, chars[index].isNumber, fraction.count < 6 {
                fraction.append(chars[index])
                index += 1
            }
            guard !fraction.isEmpty, index == chars.count || !chars[index].isNumber else {
                return fallbackParse(trimmed)
            }
            let padded = fraction.padding(toLength: 6, withPad: "0", startingAt: 0)
            nanosecond = (Int(padded) ?? 0) * 1_000
        }

        let suffix = String(chars[index...])
        let timeZone: TimeZone
        if suffix.isEmpty {
            timeZone = .current
        } else if suffix == "Z" || suffix == "z" {
            timeZone = TimeZone(secondsFromGMT: 0) ?? .gmt
        } else if suffix.count == 6,
                  suffix.first == "+" || suffix.first == "-",
                  let hours = number(Array(suffix), 1, 2),
                  let minutes = number(Array(suffix), 4, 2),
                  Array(suffix)[3] == ":" {
            let offset = hours * 3600 + minutes * 60
            timeZone = TimeZone(secondsFromGMT: suffix.first == "-" ? -offset : offset) ?? .current
        } else {
            return fallbackParse(trimmed)
        }

        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        var components = DateComponents()
        components.calendar = calendar
        components.timeZone = timeZone
        components.year = year
        components.month = month
        components.day = day
        components.hour = hour
        components.minute = minute
        components.second = second
        components.nanosecond = nanosecond
        return calendar.date(from: components) ?? fallbackParse(trimmed)
    }

    static func string(_ date: Date) -> String { encode(date, timeZone: .current, suffix: "") }
    static func utcString(_ date: Date) -> String {
        encode(date, timeZone: TimeZone(secondsFromGMT: 0) ?? .gmt, suffix: "Z")
    }

    private static func encode(_ date: Date, timeZone: TimeZone, suffix: String) -> String {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        let parts = calendar.dateComponents(
            [.year, .month, .day, .hour, .minute, .second, .nanosecond], from: date
        )
        let nanos = parts.nanosecond ?? 0
        let millis = nanos / 1_000_000
        let micros = (nanos / 1_000) % 1_000
        let base = String(
            format: "%04d-%02d-%02dT%02d:%02d:%02d.%03d",
            parts.year ?? 1970, parts.month ?? 1, parts.day ?? 1,
            parts.hour ?? 0, parts.minute ?? 0, parts.second ?? 0, millis
        )
        let fraction = micros == 0 ? "" : String(format: "%03d", micros)
        return base + fraction + suffix
    }

    private static func number(_ chars: [Character], _ start: Int, _ length: Int) -> Int? {
        guard start >= 0, length > 0, start + length <= chars.count else { return nil }
        return Int(String(chars[start..<(start + length)]))
    }

    private static func fallbackParse(_ value: String) -> Date? {
        let withFraction = ISO8601DateFormatter()
        withFraction.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = withFraction.date(from: value) { return date }
        let plain = ISO8601DateFormatter()
        plain.formatOptions = [.withInternetDateTime]
        return plain.date(from: value)
    }
}

/// Converts untrusted numeric JSON values without trapping on NaN, infinity,
/// or values outside `Int`'s range.
enum SafeNumber {
    static func int(_ value: Double?) -> Int? {
        guard let value, value.isFinite else { return nil }
        return Int(exactly: value.rounded(.toNearestOrAwayFromZero))
    }

    static func truncatingInt(_ value: Double?) -> Int? {
        guard let value, value.isFinite else { return nil }
        return Int(exactly: value.rounded(.towardZero))
    }
}

extension JSONDecoder {
    /// Lenient decoder used for every Lifelog document. Corrupt dates fall back to
    /// "now", mirroring Dart's `DateTime.tryParse(...) ?? DateTime.now()`.
    static var lifelog: JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .custom { decoder in
            let container = try decoder.singleValueContainer()
            let raw = try container.decode(String.self)
            return DateCodec.parse(raw) ?? Date()
        }
        return decoder
    }
}

extension JSONEncoder {
    static var lifelog: JSONEncoder {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .custom { date, encoder in
            var container = encoder.singleValueContainer()
            try container.encode(DateCodec.string(date))
        }
        encoder.outputFormatting = []
        return encoder
    }
}

// MARK: - Lenient keyed decoding helpers

/// A recursive JSON value used where Dart accepts mixed scalar or object values.
/// Archives store lists of objects, so this must preserve dictionaries and arrays.
indirect enum AnyJSON: Codable {
    case string(String)
    case int(Int)
    case double(Double)
    case bool(Bool)
    case null
    case array([AnyJSON])
    case object([String: AnyJSON])

    init(from decoder: Decoder) throws {
        let c = try decoder.singleValueContainer()
        if c.decodeNil() { self = .null; return }
        if let value = try? c.decode(Int.self) { self = .int(value); return }
        if let value = try? c.decode(Double.self) { self = .double(value); return }
        if let value = try? c.decode(Bool.self) { self = .bool(value); return }
        if let value = try? c.decode(String.self) { self = .string(value); return }
        if let value = try? c.decode([AnyJSON].self) { self = .array(value); return }
        if let value = try? c.decode([String: AnyJSON].self) { self = .object(value); return }
        self = .null
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.singleValueContainer()
        switch self {
        case .string(let v): try c.encode(v)
        case .int(let v): try c.encode(v)
        case .double(let v): try c.encode(v)
        case .bool(let v): try c.encode(v)
        case .null: try c.encodeNil()
        case .array(let v): try c.encode(v)
        case .object(let v): try c.encode(v)
        }
    }

    var encodedData: Data? { try? JSONEncoder().encode(self) }
}

struct LooseDecode<K: CodingKey> {
    let c: KeyedDecodingContainer<K>

    func string(_ key: K) -> String {
        (try? c.decodeIfPresent(String.self, forKey: key)) ?? ""
    }

    func optionalString(_ key: K) -> String? {
        try? c.decodeIfPresent(String.self, forKey: key)
    }

    func bool(_ key: K, default fallback: Bool = false) -> Bool {
        (try? c.decodeIfPresent(Bool.self, forKey: key)) ?? fallback
    }

    func int(_ key: K) -> Int? {
        guard let value = try? c.decodeIfPresent(Double.self, forKey: key) else { return nil }
        return SafeNumber.int(value)
    }

    func double(_ key: K) -> Double? {
        try? c.decodeIfPresent(Double.self, forKey: key)
    }

    func date(_ key: K) -> Date {
        (try? c.decodeIfPresent(Date.self, forKey: key)) ?? Date()
    }

    func optionalDate(_ key: K) -> Date? {
        try? c.decodeIfPresent(Date.self, forKey: key)
    }

    func strings(_ key: K) -> [String] {
        (try? c.decodeIfPresent([String].self, forKey: key)) ?? []
    }

    func any(_ key: K) -> AnyJSON? {
        try? c.decodeIfPresent(AnyJSON.self, forKey: key)
    }

    /// Mirrors `Archive.fromJson`'s list(map) normalisation.
    func objects<T: Decodable>(_ key: K, as type: T.Type = T.self) -> [T] {
        guard let raw = try? c.decodeIfPresent([AnyJSON].self, forKey: key) else { return [] }
        return raw.compactMap { value -> T? in
            guard let data = value.encodedData else { return nil }
            return try? JSONDecoder.lifelog.decode(T.self, from: data)
        }
    }
}

// MARK: - Calendar day helpers (local components, never UTC boundaries)

enum Dates {
    static let calendar: Calendar = {
        var cal = Calendar.current
        cal.timeZone = .current
        return cal
    }()

    static func dayStart(_ value: Date) -> Date {
        let parts = calendar.dateComponents([.year, .month, .day], from: value)
        return calendar.date(from: parts) ?? value
    }

    static func dayEnd(_ value: Date) -> Date {
        addingDays(1, to: dayStart(value))
    }

    static func addingDays(_ count: Int, to date: Date) -> Date {
        calendar.date(byAdding: .day, value: count, to: date) ?? date
    }

    static func sameDay(_ a: Date, _ b: Date) -> Bool {
        let ca = calendar.dateComponents([.year, .month, .day], from: a)
        let cb = calendar.dateComponents([.year, .month, .day], from: b)
        return ca.year == cb.year && ca.month == cb.month && ca.day == cb.day
    }

    static func dayKey(_ value: Date) -> String {
        let parts = calendar.dateComponents([.year, .month, .day], from: value)
        return String(format: "%04d-%02d-%02d", parts.year ?? 2000, parts.month ?? 1, parts.day ?? 1)
    }

    static func parseDayKey(_ key: String) -> Date {
        let parts = key.split(separator: "-").map { Int($0) }
        guard parts.count == 3 else { return Date() }
        var comps = DateComponents()
        comps.year = parts[0] ?? 2000
        comps.month = parts[1] ?? 1
        comps.day = parts[2] ?? 1
        return calendar.date(from: comps) ?? Date()
    }

    /// DateTime(y, m, d) in Dart normalises out-of-range days; DateComponents does too.
    static func date(year: Int, month: Int, day: Int, hour: Int = 0, minute: Int = 0) -> Date {
        var comps = DateComponents()
        comps.year = year
        comps.month = month
        comps.day = day
        comps.hour = hour
        comps.minute = minute
        return calendar.date(from: comps) ?? Date()
    }

    static func momentForDay(_ day: Date) -> Date {
        sameDay(day, Date()) ? Date() : date(year: component(.year, of: day),
                                              month: component(.month, of: day),
                                              day: component(.day, of: day),
                                              hour: 12)
    }

    static func component(_ component: Calendar.Component, of date: Date) -> Int {
        calendar.component(component, from: date)
    }

    private static let timeFormatter: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US")
        f.timeZone = .current
        f.dateStyle = .none
        f.timeStyle = .short
        return f
    }()

    private static func fixed(_ format: String) -> DateFormatter {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US")
        f.timeZone = .current
        f.dateFormat = format
        return f
    }

    private static let dayHeader = fixed("EEEE, MMMM d")
    private static let dayLong = fixed("EEEE, MMMM d, y")
    private static let monthYear = fixed("MMMM y")
    private static let shortDate = fixed("MMM d")
    private static let weekday = fixed("EEEE")
    private static let weekdayShort = fixed("EEE, MMM d")
    private static let monthDayYear = fixed("MMM d, y")

    static func formatTime(_ value: Date) -> String { timeFormatter.string(from: value) }

    static func formatTimeRange(_ start: Date, _ end: Date?) -> String {
        guard let end else { return formatTime(start) }
        return "\(formatTime(start)) – \(formatTime(end))"
    }

    static func formatDayHeader(_ value: Date) -> String { dayHeader.string(from: value) }
    static func formatDayLong(_ value: Date) -> String { dayLong.string(from: value) }
    static func formatMonthYear(_ value: Date) -> String { monthYear.string(from: value) }
    static func formatShortDate(_ value: Date) -> String { shortDate.string(from: value) }

    static func relativeDayLabel(_ value: Date, now: Date = Date()) -> String {
        let today = dayStart(now)
        let target = dayStart(value)
        let diff = calendar.dateComponents([.day], from: today, to: target).day ?? 0
        if diff == 0 { return "Today" }
        if diff == -1 { return "Yesterday" }
        if diff == 1 { return "Tomorrow" }
        if diff < 0 && diff > -7 { return weekday.string(from: value) }
        if component(.year, of: target) == component(.year, of: today) {
            return weekdayShort.string(from: value)
        }
        return monthDayYear.string(from: value)
    }

    static func formatDurationMinutes(_ minutes: Double) -> String {
        let rounded = SafeNumber.int(minutes) ?? 0
        if rounded < 60 { return "\(rounded) min" }
        let hours = rounded / 60
        let rest = rounded % 60
        return rest == 0 ? "\(hours)h" : "\(hours)h \(rest)m"
    }

    static func formatCompactNumber(_ value: Double) -> String {
        guard value.isFinite else { return String(format: "%.1f", value) }
        if value == value.rounded(), let whole = Int(exactly: value) { return String(whole) }
        return String(format: "%.1f", value)
    }

    static func plural(_ count: Int, _ singular: String, _ pluralForm: String? = nil) -> String {
        count == 1 ? singular : (pluralForm ?? "\(singular)s")
    }
}
