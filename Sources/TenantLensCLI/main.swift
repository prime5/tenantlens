import Foundation
import ETLCore
import DataGen
import WarehouseSQLite

// Usage: tenantlens [path/to/warehouse.sqlite]
// With no path the warehouse is in-memory. With a path, run it twice: the second run should
// report inserted=0 unchanged=576 -- an idempotent re-run.
let config = GenConfig()
let generated = Generator.orders(config)
let dbPath = CommandLine.arguments.dropFirst().first ?? ":memory:"

do {
    let warehouse = try SQLiteWarehouse(path: dbPath, schema: OrdersPipeline.factSchema,
                                        primaryKey: OrdersPipeline.primaryKey)
    let report = try OrdersPipeline.make(csv: generated.csv).run(into: warehouse)
    print("db=\(dbPath) load_runs=\(try warehouse.loadRunCount())")
    print("extracted=\(report.extracted) loaded=\(report.loaded) rejected=\(report.rejected.count)")
    print("  inserted=\(report.load.inserted) updated=\(report.load.updated) unchanged=\(report.load.unchanged)")
    for s in report.stages {
        let name = s.name.padding(toLength: 22, withPad: " ", startingAt: 0)
        print("  \(name) in=\(s.rowsIn) out=\(s.rowsOut) rejected=\(s.rejected)")
    }
    print("rejected by reason: \(report.rejectedByReason)")
    if !report.ignoredColumns.isEmpty { print("ignored columns: \(report.ignoredColumns)") }

    for t in 1...config.tenants {
        let tenant = "T\(t)"
        print("\n\(tenant)")
        let rows = try warehouse.query(tenant: tenant, groupBy: ["region"], measures: [.count, .sum("revenue")])
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
