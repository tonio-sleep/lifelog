import Foundation
import HealthKit

struct DailyHealthSummary {
    var steps: Int?
    var sleepHours: Double?
    var sleepSampleCount: Int = 0
    var syncedAt: Date?

    var hasData: Bool { steps != nil || sleepHours != nil }
}

/// Reads steps and sleep from Apple Health. HealthKit never exposes read
/// permission status on iOS, so a successful authorization request is the only
/// reliable signal that the user was offered and accepted the permission sheet.
struct HealthService {
    private let store = HKHealthStore()

    private var readTypes: Set<HKObjectType> {
        var types: Set<HKObjectType> = []
        if let steps = HKObjectType.quantityType(forIdentifier: .stepCount) { types.insert(steps) }
        // Sleep stages are values of the single sleepAnalysis category type,
        // not separate HealthKit category type identifiers.
        if let sleep = HKObjectType.categoryType(forIdentifier: .sleepAnalysis) { types.insert(sleep) }
        return types
    }

    static var isAvailable: Bool { HKHealthStore.isHealthDataAvailable() }

    /// True when iOS would still show the Health permission sheet, meaning the
    /// person has not been asked yet. iOS never reveals whether read access was
    /// granted, so "already asked" is the most Lifelog can honestly report.
    func authorizationStillNeeded() async -> Bool {
        guard HKHealthStore.isHealthDataAvailable() else { return false }
        let types = readTypes
        return await withCheckedContinuation { (continuation: CheckedContinuation<Bool, Never>) in
            store.getRequestStatusForAuthorization(toShare: [], read: types) { status, _ in
                continuation.resume(returning: status == .shouldRequest)
            }
        }
    }

    func requestPermission() async -> Bool {
        guard HKHealthStore.isHealthDataAvailable() else { return false }
        do {
            try await store.requestAuthorization(toShare: [], read: readTypes)
            return true
        } catch {
            return false
        }
    }

    func dailySummary(for day: Date, includeSteps: Bool = true, includeSleep: Bool = true) async throws -> DailyHealthSummary {
        var summary = DailyHealthSummary(syncedAt: Date())
        guard HKHealthStore.isHealthDataAvailable() else { return summary }

        let start = Dates.dayStart(day)
        let end = min(Dates.dayEnd(day), Date())

        if includeSteps, end > start {
            summary.steps = try await steps(from: start, to: end)
        }

        if includeSleep {
            let sleep = try await sleepHours(for: day, start: start, end: Dates.dayEnd(day))
            summary.sleepHours = sleep.hours
            summary.sleepSampleCount = sleep.count
        }

        return summary
    }

    private func steps(from start: Date, to end: Date) async throws -> Int? {
        guard let type = HKQuantityType.quantityType(forIdentifier: .stepCount) else { return nil }
        let predicate = HKQuery.predicateForSamples(withStart: start, end: end, options: .strictStartDate)
        return try await withCheckedThrowingContinuation { continuation in
            let query = HKStatisticsQuery(quantityType: type, quantitySamplePredicate: predicate, options: .cumulativeSum) { _, result, error in
                if let error {
                    continuation.resume(throwing: error)
                    return
                }
                let value = result?.sumQuantity()?.doubleValue(for: .count())
                continuation.resume(returning: value.flatMap { SafeNumber.int($0) }.map { max(0, $0) })
            }
            store.execute(query)
        }
    }

    private func sleepHours(for day: Date, start: Date, end: Date) async throws -> (hours: Double?, count: Int) {
        guard let sleepType = HKObjectType.categoryType(forIdentifier: .sleepAnalysis) else { return (nil, 0) }
        let predicate = HKQuery.predicateForSamples(
            withStart: Dates.addingDays(-1, to: Dates.dayStart(day)),
            end: Dates.addingDays(1, to: Dates.dayEnd(day)),
            options: []
        )
        let samples: [HKSample] = try await withCheckedThrowingContinuation { continuation in
            let query = HKSampleQuery(sampleType: sleepType, predicate: predicate, limit: HKObjectQueryNoLimit, sortDescriptors: nil) { _, result, error in
                if let error { continuation.resume(throwing: error) } else { continuation.resume(returning: result ?? []) }
            }
            store.execute(query)
        }

        let asleepValues = Set(HKCategoryValueSleepAnalysis.allAsleepValues)
        var asleepSamples: [HKCategorySample] = []
        var inBedSamples: [HKCategorySample] = []
        for sample in samples.compactMap({ $0 as? HKCategorySample }) {
            guard let value = HKCategoryValueSleepAnalysis(rawValue: sample.value) else { continue }
            if asleepValues.contains(value) {
                asleepSamples.append(sample)
            } else if value == .inBed {
                inBedSamples.append(sample)
            }
        }
        let source = asleepSamples.isEmpty ? inBedSamples : asleepSamples

        var intervals: [(Date, Date)] = []
        for sample in source {
            let from = max(sample.startDate, start)
            let to = min(sample.endDate, end)
            if to > from { intervals.append((from, to)) }
        }
        intervals.sort { $0.0 < $1.0 }

        var mergedMinutes = 0.0
        var current: (Date, Date)?
        for interval in intervals {
            if let active = current, interval.0 <= active.1 {
                current = (active.0, max(active.1, interval.1))
            } else {
                if let active = current { mergedMinutes += active.1.timeIntervalSince(active.0) / 60 }
                current = interval
            }
        }
        if let active = current { mergedMinutes += active.1.timeIntervalSince(active.0) / 60 }
        guard mergedMinutes > 0 else { return (nil, source.count) }
        let rounded = (mergedMinutes / 60 * 100).rounded() / 100
        return (rounded, source.count)
    }
}
