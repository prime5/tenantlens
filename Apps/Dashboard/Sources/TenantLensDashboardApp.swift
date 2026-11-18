import SwiftUI

@main
struct TenantLensDashboardApp: App {
    @State private var model: DashboardModel

    init() {
        // Launch arguments like `-seed 42 -db /tmp/tl.sqlite` land in UserDefaults automatically
        // (the "argument domain"). Python delta: argparse for free, looked up by flag name.
        // Phase 4's XCUITest sets these via `app.launchArguments` to get a deterministic dashboard.
        let defaults = UserDefaults.standard
        let seed = defaults.string(forKey: "seed").flatMap { UInt64($0) } ?? 42
        let dbPath = defaults.string(forKey: "db") ?? ":memory:"
        _model = State(initialValue: DashboardModel(seed: seed, dbPath: dbPath))
    }

    var body: some Scene {
        WindowGroup("TenantLens") {
            ContentView(model: model)
                .frame(minWidth: 900, minHeight: 620)
        }
    }
}
