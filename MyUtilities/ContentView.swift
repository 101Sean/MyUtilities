import SwiftUI

struct ContentView: View {
    @StateObject var manager = HealthDataManager()
    @State private var status = "Tap to authorize HealthKit"

    var body: some View {
        VStack(spacing: 20) {
            Text("My Utilities")
                        .font(.largeTitle)
                        .bold()
                        .multilineTextAlignment(.center)
            Text(status).multilineTextAlignment(.center)
            Button("Authorize HealthKit") {
                manager.requestAuthorization { success, error in
                    status = success ? "✅ Authorized" : "❌ Failed: \(error?.localizedDescription ?? "Unknown")"
                }
            }
            /*
            Button("Test Fetch") {
                Task {
                    do {
                        print("▶️ Starting fetch…")
                        let metrics = try await HealthDataManager().getTodayMetrics()
                        print("✅ Metrics fetched:", metrics)
                    }
                    catch {
                        print("❌ Fetch error:", error.localizedDescription)
                    }
                }
            }*/
        }
        .padding()
    }
}

struct ContentView_Previews: PreviewProvider {
    static var previews: some View {
        ContentView()
    }
}
