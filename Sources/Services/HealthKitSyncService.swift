import Foundation
import HealthKit

struct HealthKitTimeBlock {
    let sourceIdentifier: String
    let name: String
    let category: String
    let startDate: Date
    let endDate: Date
    let extra: [String: String]
}

enum HealthKitSyncError: LocalizedError {
    case unavailable
    case noTypesSelected
    case typeUnavailable

    var errorDescription: String? {
        switch self {
        case .unavailable:
            return "这台设备暂时无法读取 Apple 健康数据。"
        case .noTypesSelected:
            return "请选择要同步的 Apple 健康数据。"
        case .typeUnavailable:
            return "暂时无法读取对应的 Apple 健康数据类型。"
        }
    }
}

final class HealthKitSyncService {
    static let shared = HealthKitSyncService()

    private let store = HKHealthStore()
    private let calendar = Calendar.current
    private let sleepSessionGap: TimeInterval = 90 * 60

    private init() {}

    func requestAuthorization(readSleep: Bool, readWorkouts: Bool) async throws {
        guard HKHealthStore.isHealthDataAvailable() else { throw HealthKitSyncError.unavailable }
        let readTypes = try healthTypes(readSleep: readSleep, readWorkouts: readWorkouts)
        guard !readTypes.isEmpty else { throw HealthKitSyncError.noTypesSelected }
        try await store.requestAuthorization(toShare: [], read: readTypes)
    }

    func fetchTimeBlocks(readSleep: Bool, readWorkouts: Bool, since startDate: Date, until endDate: Date) async throws -> [HealthKitTimeBlock] {
        var blocks: [HealthKitTimeBlock] = []
        if readSleep {
            blocks.append(contentsOf: try await fetchSleepBlocks(since: startDate, until: endDate))
        }
        if readWorkouts {
            blocks.append(contentsOf: try await fetchWorkoutBlocks(since: startDate, until: endDate))
        }
        return blocks.sorted { $0.startDate < $1.startDate }
    }

    private func healthTypes(readSleep: Bool, readWorkouts: Bool) throws -> Set<HKObjectType> {
        var types = Set<HKObjectType>()
        if readSleep {
            guard let sleepType = HKObjectType.categoryType(forIdentifier: .sleepAnalysis) else {
                throw HealthKitSyncError.typeUnavailable
            }
            types.insert(sleepType)
        }
        if readWorkouts {
            types.insert(HKObjectType.workoutType())
        }
        return types
    }

    private func fetchSleepBlocks(since startDate: Date, until endDate: Date) async throws -> [HealthKitTimeBlock] {
        guard let sleepType = HKObjectType.categoryType(forIdentifier: .sleepAnalysis) else {
            throw HealthKitSyncError.typeUnavailable
        }
        let predicate = HKQuery.predicateForSamples(withStart: startDate, end: endDate, options: .strictEndDate)
        let sort = NSSortDescriptor(key: HKSampleSortIdentifierStartDate, ascending: true)
        let samples = try await categorySamples(type: sleepType, predicate: predicate, sortDescriptors: [sort])
        let intervals = mergedSleepSessions(from: samples)

        return intervals.map { interval in
            let sourceID = "sleep:\(Self.sourceDateFormatter.string(from: interval.start)):\(Self.sourceDateFormatter.string(from: interval.end))"
            return HealthKitTimeBlock(
                sourceIdentifier: sourceID,
                name: "睡觉",
                category: "睡觉",
                startDate: interval.start,
                endDate: interval.end,
                extra: [
                    HealthKitTimeEntryKey.source: HealthKitTimeEntryKey.sourceValue,
                    HealthKitTimeEntryKey.kind: HealthKitTimeEntryKey.kindSleep,
                    HealthKitTimeEntryKey.sourceID: sourceID
                ]
            )
        }
    }

    private func fetchWorkoutBlocks(since startDate: Date, until endDate: Date) async throws -> [HealthKitTimeBlock] {
        let workoutType = HKObjectType.workoutType()
        let predicate = HKQuery.predicateForSamples(withStart: startDate, end: endDate, options: .strictEndDate)
        let sort = NSSortDescriptor(key: HKSampleSortIdentifierStartDate, ascending: true)
        let workouts = try await workoutSamples(type: workoutType, predicate: predicate, sortDescriptors: [sort])

        return workouts.compactMap { workout in
            guard workout.endDate > workout.startDate else { return nil }
            let sourceID = "workout:\(workout.uuid.uuidString)"
            var extra: [String: String] = [
                HealthKitTimeEntryKey.source: HealthKitTimeEntryKey.sourceValue,
                HealthKitTimeEntryKey.kind: HealthKitTimeEntryKey.kindWorkout,
                HealthKitTimeEntryKey.sourceID: sourceID,
                HealthKitTimeEntryKey.workoutActivityType: "\(workout.workoutActivityType.rawValue)"
            ]
            if let calories = activeEnergyKilocalories(for: workout) {
                extra[HealthKitTimeEntryKey.activeEnergyKilocalories] = calories
            }
            if let distance = distanceMeters(for: workout) {
                extra[HealthKitTimeEntryKey.distanceMeters] = distance
            }
            return HealthKitTimeBlock(
                sourceIdentifier: sourceID,
                name: workoutName(for: workout.workoutActivityType),
                category: "运动",
                startDate: workout.startDate,
                endDate: workout.endDate,
                extra: extra
            )
        }
    }

    private func categorySamples(type: HKCategoryType, predicate: NSPredicate, sortDescriptors: [NSSortDescriptor]) async throws -> [HKCategorySample] {
        try await withCheckedThrowingContinuation { continuation in
            let query = HKSampleQuery(sampleType: type, predicate: predicate, limit: HKObjectQueryNoLimit, sortDescriptors: sortDescriptors) { _, samples, error in
                if let error {
                    continuation.resume(throwing: error)
                    return
                }
                continuation.resume(returning: samples as? [HKCategorySample] ?? [])
            }
            store.execute(query)
        }
    }

    private func workoutSamples(type: HKWorkoutType, predicate: NSPredicate, sortDescriptors: [NSSortDescriptor]) async throws -> [HKWorkout] {
        try await withCheckedThrowingContinuation { continuation in
            let query = HKSampleQuery(sampleType: type, predicate: predicate, limit: HKObjectQueryNoLimit, sortDescriptors: sortDescriptors) { _, samples, error in
                if let error {
                    continuation.resume(throwing: error)
                    return
                }
                continuation.resume(returning: samples as? [HKWorkout] ?? [])
            }
            store.execute(query)
        }
    }

    private func isAsleepValue(_ rawValue: Int) -> Bool {
        guard let value = HKCategoryValueSleepAnalysis(rawValue: rawValue) else { return false }
        return HKCategoryValueSleepAnalysis.allAsleepValues.contains(value)
    }

    private func mergedSleepSessions(from samples: [HKCategorySample]) -> [(start: Date, end: Date)] {
        let intervals = samples
            .filter { isAsleepValue($0.value) }
            .map { (start: $0.startDate, end: $0.endDate) }
            .filter { $0.end > $0.start }
            .sorted { $0.start < $1.start }
        guard var current = intervals.first else { return [] }

        var result: [(start: Date, end: Date)] = []
        for interval in intervals.dropFirst() {
            if interval.start.timeIntervalSince(current.end) <= sleepSessionGap {
                current.end = max(current.end, interval.end)
            } else {
                result.append(current)
                current = interval
            }
        }
        result.append(current)
        return result
    }

    private func workoutName(for type: HKWorkoutActivityType) -> String {
        switch type {
        case .running: return "跑步"
        case .walking: return "散步"
        case .cycling: return "骑行"
        case .yoga: return "瑜伽"
        case .swimming: return "游泳"
        case .traditionalStrengthTraining, .functionalStrengthTraining: return "力量训练"
        case .hiking: return "徒步"
        case .dance: return "跳舞"
        case .pilates: return "普拉提"
        case .taiChi: return "太极"
        default: return "运动"
        }
    }

    private func activeEnergyKilocalories(for workout: HKWorkout) -> String? {
        guard let type = HKQuantityType.quantityType(forIdentifier: .activeEnergyBurned),
              let sum = workout.statistics(for: type)?.sumQuantity() else { return nil }
        return String(format: "%.0f", sum.doubleValue(for: .kilocalorie()))
    }

    private func distanceMeters(for workout: HKWorkout) -> String? {
        guard let type = HKQuantityType.quantityType(forIdentifier: .distanceWalkingRunning),
              let sum = workout.statistics(for: type)?.sumQuantity() else { return nil }
        return String(format: "%.0f", sum.doubleValue(for: .meter()))
    }

    private static let sourceDateFormatter: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }()
}

enum HealthKitTimeEntryKey {
    static let source = "source"
    static let sourceValue = "healthkit"
    static let kind = "healthkitKind"
    static let kindSleep = "sleep"
    static let kindWorkout = "workout"
    static let sourceID = "healthkitSourceID"
    static let workoutActivityType = "workoutActivityType"
    static let activeEnergyKilocalories = "activeEnergyKilocalories"
    static let distanceMeters = "distanceMeters"
}
