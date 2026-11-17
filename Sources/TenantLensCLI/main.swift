import Foundation
import ETLCore
import DataGen

// Generate synthetic multi-tenant orders, run the ETL, print the run report and a
// per-tenant revenue-by-region rollup. Phase 3 renders the same rollup in SwiftUI.
let config = GenConfig()
let generated = Generator.orders(config)
let warehouse = Warehouse()

do {
    let report = try OrdersPipeline.make(csv: generated.csv).run(into: warehouse)
    print("extracted=\(report.extracted) loaded=\(report.loaded) rejected=\(report.rejected.count)")
    for s in report.stages {
        let name = s.name.padding(toLength: 22, withPad: " ", startingAt: 0)
        print("  \(name) in=\(s.rowsIn) out=\(s.rowsOut) rejected=\(s.rejected)")
    }
    print("rejected by reason: \(report.rejectedByReason)")

    for t in 1...config.tenants {
        let tenant = "T\(t)"
        print("\n\(tenant)")
        let rows = warehouse.query(tenant: tenant, groupBy: ["region"], measures: [.count, .sum("revenue")])
        for r in rows {
            let region = r.keys.first?.display ?? "?"
            let orders = Int(r.values["count"] ?? 0)
            let revenue = String(format: "%.2f", r.values["sum_revenue"] ?? 0)
            print("  \(region.padding(toLength: 6, withPad: " ", startingAt: 0)) orders=\(orders) revenue=\(revenue)")
        }
    }
} catch {
    print("pipeline failed: \(error)")
    exit(1)
}
