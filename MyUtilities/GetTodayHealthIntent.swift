import AppIntents
import Foundation

struct GetTodayHealthIntent: AppIntent {
    static var title = LocalizedStringResource("Get Health Metrics for Date")
    static var description = IntentDescription("Retrieves exercise time, sleep time, weight, and state of mind for a specific date from Apple Health.")
    static var parameterSummary: some ParameterSummary { Summary("Fetch health metrics for \(\.$dateString)") }

    @Parameter(title: "Date (yyyy‑MM‑dd)")
    var dateString: String

    private static let isoFormatter: DateFormatter = {
        let df = DateFormatter()
        df.dateFormat = "yyyy-MM-dd"
        df.locale = Locale(identifier: "en_US_POSIX")
        df.timeZone = .current
        return df
    }()

    func formatMinutesToHHMM(_ minutes: Double) -> String {
        let total = Int(minutes.rounded())
        let h = total / 60
        let m = total % 60
        return String(format: "%02d:%02d", h, m)
    }

    func perform() async throws -> some IntentResult & ReturnsValue<String> {
        guard let targetDate = Self.isoFormatter.date(from: dateString) else {
            return .result(value: "❗Invalid date format. Use yyyy‑MM‑dd")
        }

        let manager = HealthDataManager()
        do {
            try await withCheckedThrowingContinuation { cont in
                manager.requestAuthorization { success, error in
                    if success { cont.resume() }
                    else { cont.resume(throwing: error!) }
                }
            }

            let metrics = try await manager.getMetrics(for: targetDate)
            let weightRounded = String(format: "%.1f", Double(round(metrics.weight * 10) / 10))

            let payload: [String:Any] = [
                "date": dateString,
                "exerciseTime": formatMinutesToHHMM(metrics.exerciseTime),
                "sleepTime": formatMinutesToHHMM(metrics.sleepTime),
                "weight": weightRounded,
                "stateOfMind": metrics.stateOfMind
            ]

            let data = try JSONSerialization.data(withJSONObject: payload, options: .prettyPrinted)
            return .result(value: String(data: data, encoding: .utf8)!)
        }
        catch {
            return .result(value: "❗Error: \(error.localizedDescription)")
        }
    }
}
