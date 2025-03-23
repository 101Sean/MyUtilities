import AppIntents
import Foundation

struct GetTodayHealthIntent: AppIntent {
    static var title = LocalizedStringResource("Get Today Health Metrics")
    static var description = IntentDescription("Retrieves today's exercise time, sleep time, weight, state of mind, and medication status from Apple Health.")
    static var parameterSummary: some ParameterSummary { Summary("Fetch today’s full health metrics") }
    
    func formatMinutesToHHMM(_ minutes: Double) -> String {
        let total = Int(minutes)
        let h = total / 60
        let m = total % 60
        return String(format: "%02d:%02d", h, m)
    }

    func perform() async throws -> some IntentResult & ReturnsValue<String> {
        let manager = HealthDataManager()
        let metrics = try await manager.getTodayMetrics()
        print("Intent metrics:", metrics)

        do {
            try await withCheckedThrowingContinuation { cont in
                manager.requestAuthorization { success, error in
                    if success { cont.resume() }
                    else { cont.resume(throwing: error!) }
                }
            }
            let metrics = try await manager.getTodayMetrics()
            let weightRounded = Double(round(metrics.weight * 10) / 10)
            
            let payload: [String:Any] = [
                "exerciseTime": Int(metrics.exerciseTime),
                "sleepTime": formatMinutesToHHMM(metrics.sleepTime),
                "awakeTime": Int(metrics.awakeTime),
                "weight": String(format: "%.1f", weightRounded),
                "stateOfMind": metrics.stateOfMind
                //"medicationTaken": metrics.medicationTaken
            ]
            let data = try JSONSerialization.data(withJSONObject: payload, options: .prettyPrinted)
            return .result(value: String(data: data, encoding: .utf8)!)
        }
        catch {
            return .result(value: "❗Error: \(error.localizedDescription)")
        }
    }
}
