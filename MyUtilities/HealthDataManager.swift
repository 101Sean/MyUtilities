import HealthKit
import Foundation

struct TodayHealthMetrics {
    let exerciseTime: Double
    let sleepTime: Double
    let weight: Double
    let stateOfMind: String
}

class HealthDataManager: ObservableObject {
    private let store = HKHealthStore()

    // Authorization
    func requestAuthorization(completion: @escaping (Bool, Error?) -> Void) {
        guard HKHealthStore.isHealthDataAvailable() else {
            completion(false, NSError(domain: "HealthKitError", code: 0))
            return
        }

        var read: Set<HKObjectType> = [
            HKQuantityType.quantityType(forIdentifier: .appleExerciseTime)!,
            HKCategoryType.categoryType(forIdentifier: .sleepAnalysis)!,
            HKQuantityType.quantityType(forIdentifier: .bodyMass)!
        ]

        if #available(iOS 17.0, *) {
            read.insert(HKObjectType.stateOfMindType())
        }

        store.requestAuthorization(toShare: nil, read: read) { success, error in
            DispatchQueue.main.async { completion(success, error) }
        }
    }

    // Public API
    func getMetrics(for date: Date) async throws -> TodayHealthMetrics {
        async let ex = fetchExerciseTime(on: date)
        async let sl = fetchSleepTime(on: date)
        async let wt = fetchWeight(on: date)
        async let mind = fetchStateOfMind(on: date)

        return TodayHealthMetrics(
            exerciseTime: try await ex,
            sleepTime: try await sl,
            weight: try await wt,
            stateOfMind: try await mind
        )
    }

    // Fetchers
    private func fetchExerciseTime(on date: Date) async throws -> Double {
        return try await queryStatistics(
            type: HKQuantityType.quantityType(forIdentifier: .appleExerciseTime)!,
            predicate: dailyPredicate(for: date),
            unit: HKUnit.minute()
        )
    }

    private func fetchSleepTime(on date: Date) async throws -> Double {
        let sleepType = HKCategoryType.categoryType(forIdentifier: .sleepAnalysis)!
        let samples = try await querySamples(type: sleepType, predicate: dailyPredicate(for: date))

        return samples.reduce(0) { total, sample in
            guard let cat = sample as? HKCategorySample else { return total }

            switch cat.value {
            case HKCategoryValueSleepAnalysis.asleepCore.rawValue,
                 HKCategoryValueSleepAnalysis.asleepDeep.rawValue,
                 HKCategoryValueSleepAnalysis.asleepREM.rawValue,
                 HKCategoryValueSleepAnalysis.asleepUnspecified.rawValue:

                let start = max(cat.startDate, Calendar.current.startOfDay(for: date))
                let end = min(cat.endDate, Calendar.current.date(byAdding: .day, value: 1, to: Calendar.current.startOfDay(for: date))!)
                return total + max(end.timeIntervalSince(start), 0) / 60

            default:
                return total
            }
        }
    }

    private func fetchWeight(on date: Date) async throws -> Double {
        let type = HKQuantityType.quantityType(forIdentifier: .bodyMass)!
        let sort = [NSSortDescriptor(key: HKSampleSortIdentifierEndDate, ascending: false)]

        let daily = try await querySamples(
            type: type,
            predicate: dailyPredicate(for: date),
            limit: 1,
            sortDescriptors: sort
        )
        if let sample = daily.first as? HKQuantitySample {
            return sample.quantity.doubleValue(for: HKUnit.gramUnit(with: .kilo))
        }

        let fallback = try await querySamples(
            type: type,
            predicate: HKQuery.predicateForSamples(withStart: nil, end: Date(), options: []),
            limit: 1,
            sortDescriptors: sort
        )
        guard let latest = fallback.first as? HKQuantitySample else { return 0.0 }
        return latest.quantity.doubleValue(for: HKUnit.gramUnit(with: .kilo))
    }

    private func fetchStateOfMind(on date: Date) async throws -> String {
        guard #available(iOS 17.0, *) else { return "Unknown" }
        let sort = [NSSortDescriptor(key: HKSampleSortIdentifierEndDate, ascending: false)]
        let samples = try await querySamples(
            type: HKCategoryType.stateOfMindType(),
            predicate: dailyPredicate(for: date),
            limit: 1,
            sortDescriptors: sort
        )
        guard let sample = samples.first as? HKStateOfMind,
              let label = sample.labels.first else { return "Unknown" }
        return label.displayName
    }

    // Helpers
    private func dailyPredicate(for date: Date) -> NSPredicate {
        let start = Calendar.current.startOfDay(for: date)
        let end = Calendar.current.date(byAdding: .day, value: 1, to: start)!
        return HKQuery.predicateForSamples(withStart: start, end: end, options: [])
    }

    private func queryStatistics(type: HKQuantityType, predicate: NSPredicate, unit: HKUnit) async throws -> Double {
        try await withCheckedThrowingContinuation { cont in
            let query = HKStatisticsQuery(quantityType: type, quantitySamplePredicate: predicate, options: .cumulativeSum) { _, stats, error in
                if let error = error { cont.resume(throwing: error) }
                else { cont.resume(returning: stats?.sumQuantity()?.doubleValue(for: unit) ?? 0) }
            }
            store.execute(query)
        }
    }

    private func querySamples(type: HKSampleType, predicate: NSPredicate, limit: Int = HKObjectQueryNoLimit,
                              sortDescriptors: [NSSortDescriptor]? = nil) async throws -> [HKSample] {
        try await withCheckedThrowingContinuation { cont in
            let query = HKSampleQuery(sampleType: type, predicate: predicate, limit: limit, sortDescriptors: sortDescriptors) { _, samples, error in
                if let error = error { cont.resume(throwing: error) }
                else { cont.resume(returning: samples ?? []) }
            }
            store.execute(query)
        }
    }
}

extension HKStateOfMind.Label {
    var displayName: String {
        switch self {
        case .amazed:        return "Amazed"
        case .amused:        return "Amused"
        case .angry:         return "Angry"
        case .annoyed:       return "Annoyed"
        case .anxious:       return "Anxious"
        case .ashamed:       return "Ashamed"
        case .brave:         return "Brave"
        case .calm:          return "Calm"
        case .confident:     return "Confident"
        case .content:       return "Content"
        case .disappointed:  return "Disappointed"
        case .discouraged:   return "Discouraged"
        case .disgusted:     return "Disgusted"
        case .drained:       return "Drained"
        case .embarrassed:   return "Embarrassed"
        case .excited:       return "Excited"
        case .frustrated:    return "Frustrated"
        case .grateful:      return "Grateful"
        case .guilty:        return "Guilty"
        case .happy:         return "Happy"
        case .hopeful:       return "Hopeful"
        case .hopeless:      return "Hopeless"
        case .indifferent:   return "Indifferent"
        case .irritated:     return "Irritated"
        case .jealous:       return "Jealous"
        case .joyful:        return "Joyful"
        case .lonely:        return "Lonely"
        case .overwhelmed:   return "Overwhelmed"
        case .passionate:    return "Passionate"
        case .peaceful:      return "Peaceful"
        case .proud:         return "Proud"
        case .relieved:      return "Relieved"
        case .sad:           return "Sad"
        case .satisfied:     return "Satisfied"
        case .scared:        return "Scared"
        case .stressed:      return "Stressed"
        case .surprised:     return "Surprised"
        case .worried:       return "Worried"
        @unknown default:    return "Unknown"
        }
    }
}
