import HealthKit
import Foundation

struct TodayHealthMetrics {
    let exerciseTime: Double
    let sleepTime: Double
    let awakeTime: Double
    let weight: Double
    let stateOfMind: String
    //let medicationTaken: Bool
}

class HealthDataManager: ObservableObject {
    private let store = HKHealthStore()

    func requestAuthorization(completion: @escaping (Bool, Error?) -> Void) {
        guard HKHealthStore.isHealthDataAvailable() else { completion(false, NSError(domain: "HealthKitError", code: 0)); return }
        var read: Set<HKObjectType> = [
            HKQuantityType.quantityType(forIdentifier: .appleExerciseTime)!,
            HKCategoryType.categoryType(forIdentifier: .sleepAnalysis)!,
            HKQuantityType.quantityType(forIdentifier: .bodyMass)!
        ]
        if #available(iOS 17.0, *) {
            read.insert(HKObjectType.stateOfMindType())
            //read.insert(HKCategoryType.categoryType(forIdentifier: .medicationRecord)!)
        }
        store.requestAuthorization(toShare: nil, read: read) { success, error in
            DispatchQueue.main.async { completion(success, error) }
        }
    }
    
    func getTodayMetrics() async throws -> TodayHealthMetrics {
        async let ex = fetchExerciseTime()
        async let sl = fetchSleepTime()
        async let aw = fetchAwakeTime()
        async let wt = fetchWeight()
        async let mind = fetchStateOfMind()
        //async let med = fetchMedicationTaken()

        return TodayHealthMetrics(
            exerciseTime: try await ex,
            sleepTime: try await sl,
            awakeTime: try await aw,
            weight: try await wt,
            stateOfMind: try await mind
            //medicationTaken: try await med
        )
    }

    private func fetchExerciseTime() async throws -> Double {
        do {
            return try await queryStatistics(
                type: HKQuantityType.quantityType(forIdentifier: .appleExerciseTime)!,
                predicate: HKQuery.predicateForSamples(
                    withStart: Calendar.current.startOfDay(for: Date()),
                    end: Date(),
                    options: []
                ),
                unit: HKUnit.minute()
            )
        } catch {
            return 0.0    // 기본값
        }
    }

    private func fetchSleepTime() async throws -> Double {
        do {
            let sleepType = HKCategoryType.categoryType(forIdentifier: .sleepAnalysis)!
            let now = Date()
            let start = Calendar.current.startOfDay(for: now)
            let predicate = HKQuery.predicateForSamples(withStart: start, end: now, options: .strictStartDate)

            let samples = try await querySamples(type: sleepType, predicate: predicate)
            let totalMinutes = samples.compactMap { sample -> Double? in
                guard let cat = sample as? HKCategorySample else { return nil }
                switch cat.value {
                case HKCategoryValueSleepAnalysis.asleepCore.rawValue,
                     HKCategoryValueSleepAnalysis.asleepDeep.rawValue,
                     HKCategoryValueSleepAnalysis.asleepREM.rawValue,
                     HKCategoryValueSleepAnalysis.asleepUnspecified.rawValue:
                    return cat.endDate.timeIntervalSince(cat.startDate) / 60.0
                default:
                    return nil
                }
            }.reduce(0, +)

            return totalMinutes
        } catch {
            return 0.0
        }
    }
    
    private func fetchAwakeTime() async throws -> Double {
        do {
            let sleepType = HKCategoryType.categoryType(forIdentifier: .sleepAnalysis)!
            let now = Date(), start = Calendar.current.startOfDay(for: now)
            let predicate = HKQuery.predicateForSamples(withStart: start, end: now, options: .strictStartDate)

            let samples = try await querySamples(type: sleepType, predicate: predicate)
            let awakeMinutes = samples.compactMap { sample -> Double? in
                guard let cat = sample as? HKCategorySample,
                      cat.value == HKCategoryValueSleepAnalysis.awake.rawValue
                else { return nil }
                return cat.endDate.timeIntervalSince(cat.startDate) / 60.0
            }.reduce(0, +)

            return awakeMinutes
        } catch {
            return 0.0
        }
    }

    private func fetchWeight() async throws -> Double {
        do {
            let type = HKQuantityType.quantityType(forIdentifier: .bodyMass)!
            let sort = [NSSortDescriptor(key: HKSampleSortIdentifierEndDate, ascending: false)]
            let samples = try await querySamples(
                type: type,
                predicate: HKQuery.predicateForSamples(
                    withStart: Calendar.current.date(byAdding: .year, value: -1, to: Date()),
                    end: Date(),
                    options: .strictStartDate
                ),
                limit: 1,
                sortDescriptors: sort
            )
            
            guard let sample = samples.first as? HKQuantitySample else { return 0.0 }
            return sample.quantity.doubleValue(for: HKUnit.gramUnit(with: .kilo))
        } catch {
            return 0.0
        }
    }

    private func fetchStateOfMind() async throws -> String {
        guard #available(iOS 17.0, *) else { return "Unknown" }
        do {
            let type = HKCategoryType.stateOfMindType()
            let sort = [NSSortDescriptor(key: HKSampleSortIdentifierEndDate, ascending: false)]
            let samples = try await querySamples(
                type: type,
                predicate: HKQuery.predicateForSamples(
                    withStart: Calendar.current.startOfDay(for: Date()),
                    end: Date(),
                    options: .strictStartDate
                ),
                limit: 1,
                sortDescriptors: sort
            )
            
            guard let stateSample = samples.first as? HKStateOfMind,
                  let label = stateSample.labels.first else {
                return "Unknown"
            }

            return label.displayName
        } catch {
            return "Unknown"
        }
    }
    /*
    private func fetchMedicationTaken() async throws -> Bool {
        guard #available(iOS 17.0, *) else { return false }
        do {
            let type = HKCategoryType.categoryType(forIdentifier: .medicationRecord)!
            let samples = try await querySamples(
                type: type,
                predicate: HKQuery.predicateForSamples(
                    withStart: Calendar.current.startOfDay(for: Date()),
                    end: Date(),
                    options: []
                ),
                limit: 1
            )
            return (samples.first as? HKCategorySample)?.value == HKCategoryValueMedicationRecord.taken.rawValue
        } catch {
            return false
        }
    }*/

    private func queryStatistics(type: HKQuantityType, predicate: NSPredicate, unit: HKUnit) async throws -> Double {
        return try await withCheckedThrowingContinuation { cont in
            let query = HKStatisticsQuery(quantityType: type, quantitySamplePredicate: predicate, options: .cumulativeSum) { _, stats, err in
                if let err = err { cont.resume(throwing: err) } else { cont.resume(returning: stats?.sumQuantity()?.doubleValue(for: unit) ?? 0) }
            }
            store.execute(query)
        }
    }

    private func querySamples(type: HKSampleType, predicate: NSPredicate, limit: Int = HKObjectQueryNoLimit,
                              sortDescriptors: [NSSortDescriptor]? = nil) async throws -> [HKSample] {
        return try await withCheckedThrowingContinuation { cont in
            let query = HKSampleQuery(sampleType: type, predicate: predicate, limit: limit, sortDescriptors: sortDescriptors) { _, samples, err in
                if let err = err { cont.resume(throwing: err) } else { cont.resume(returning: samples ?? []) }
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
