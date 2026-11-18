import Foundation
import Observation
import ETLCore
import DataGen
import WarehouseSQLite
import DashboardCore

/// The app's state. Python delta: think of an object whose attribute writes notify subscribers;
/// SwiftUI re-renders exactly the views whose `body` read the attributes that changed.
@MainActor
@Observable
final class DashboardModel {
    let tenants: [String]
    private(set) var selectedTenant: String
    private(set) var snapshot: DashboardSnapshot? = nil
    private(set) var run: RunSummary? = nil
    private(set) var errorMessage: String? = nil
    private let store: SQLiteWarehouse?

    init(seed: UInt64, dbPath: String) {
        let config = GenConfig(seed: seed)
        // Tenants come from configuration (a registry), not from scanning the facts:
        // the warehouse deliberately has no unscoped query.
        let names = (1...config.tenants).map { "T\($0)" }
        tenants = names
        selectedTenant = names.first ?? "T1"

        // Work in locals, then assign: a class may not touch its own properties' setters until
        // every stored property has a value (Swift's two-phase initialization).
        var opened: SQLiteWarehouse?
        var summary: RunSummary?
        var failure: String?
        do {
            let warehouse = try SQLiteWarehouse(path: dbPath, schema: OrdersPipeline.factSchema,
                                                primaryKey: OrdersPipeline.primaryKey)
            let report = try OrdersPipeline.make(csv: Generator.orders(config).csv).run(into: warehouse)
            opened = warehouse
            summary = RunSummary(report)
        } catch {
            failure = "\(error)"
        }
        store = opened
        run = summary
        errorMessage = failure
        refresh()
    }

    func select(_ tenant: String) {
        selectedTenant = tenant
        refresh()
    }

    private func refresh() {
        guard let store else { return }
        do {
            snapshot = try Dashboard.snapshot(tenant: selectedTenant, from: store)
        } catch {
            errorMessage = "\(error)"
        }
    }
}
