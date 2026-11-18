import XCTest
import ETLCore
import DataGen
import WarehouseSQLite

/// Incremental loads, run against BOTH warehouses. Expectations are composed from each
/// batch's GroundTruth, never from what a warehouse reports about itself.
final class IncrementalLoadTests: XCTestCase {
    typealias Store = any Sink & TenantQueryable

    private var stores: [(name: String, make: () throws -> Store)] {
        [
            ("memory", { Warehouse(primaryKey: OrdersPipeline.primaryKey) }),
            ("sqlite", { try SQLiteWarehouse(schema: OrdersPipeline.factSchema, primaryKey: OrdersPipeline.primaryKey) }),
        ]
    }

    private let batch1 = GenConfig(orderRange: 1...120)
    private let batch2 = GenConfig(orderRange: 101...200, correctedOrders: [102, 107, 115])

    private func revenue(_ store: Store, _ tenant: String) throws -> Double {
        try store.query(tenant: tenant, groupBy: [], measures: [.sum("revenue")]).first?.values["sum_revenue"] ?? 0
    }

    func testRerunningTheSameBatchChangesNothing() throws {
        let g = Generator.orders(batch1)
        for (name, make) in stores {
            let store = try make()
            let first = try OrdersPipeline.make(csv: g.csv).run(into: store)
            let second = try OrdersPipeline.make(csv: g.csv).run(into: store)
            XCTAssertEqual(first.load, LoadResult(inserted: g.truth.cleanOrders), name)
            XCTAssertEqual(second.load, LoadResult(unchanged: g.truth.cleanOrders), name)
            for t in 1...batch1.tenants {
                let tenant = "T\(t)"
                XCTAssertEqual(try revenue(store, tenant), g.truth.revenueByTenant[tenant] ?? -1,
                               accuracy: 1e-6, "\(name) \(tenant)")
            }
        }
    }

    func testOverlappingBatchInsertsNewRowsAndAppliesCorrections() throws {
        let g1 = Generator.orders(batch1)
        let g2 = Generator.orders(batch2)
        let old = g1.truth.cleanRevenueByOrder
        let new = g2.truth.cleanRevenueByOrder

        var expected = LoadResult()
        for (id, rev) in new {
            if let previous = old[id] {
                if previous == rev { expected.unchanged += 1 } else { expected.updated += 1 }
            } else {
                expected.inserted += 1
            }
        }
        // Golden, hand-derived per tenant: overlap 101...120 has 18 clean orders (110 bad date,
        // 120 negative), 3 of them corrected; 121...200 has 77 new clean orders (160, 200
        // negative; 165 bad date). x3 tenants.
        XCTAssertEqual(expected, LoadResult(inserted: 231, updated: 9, unchanged: 45))

        let merged = old.merging(new) { _, newer in newer }
        for (name, make) in stores {
            let store = try make()
            try OrdersPipeline.make(csv: g1.csv).run(into: store)
            let report = try OrdersPipeline.make(csv: g2.csv).run(into: store)

            XCTAssertEqual(report.load, expected, name)
            XCTAssertEqual(report.extracted, report.load.total + report.rejected.count, name)
            for t in 1...batch2.tenants {
                let tenant = "T\(t)"
                let mine = merged.filter { $0.key.hasPrefix("\(tenant)-") }
                XCTAssertEqual(try store.rowCount(tenant: tenant), mine.count, "\(name) \(tenant)")
                XCTAssertEqual(try revenue(store, tenant), mine.values.reduce(0, +),
                               accuracy: 1e-6, "\(name) \(tenant)")
            }
        }
    }
}
