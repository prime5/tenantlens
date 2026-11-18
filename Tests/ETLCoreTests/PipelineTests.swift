import XCTest
import ETLCore
import DataGen

/// Layer-1 tests: is the data right after the ETL? Every expectation comes from the
/// generator's GroundTruth (an independent oracle), never from the pipeline's own output.
final class PipelineTests: XCTestCase {
    private func runPipeline(_ config: GenConfig = GenConfig()) throws -> (report: RunReport, warehouse: Warehouse, truth: GroundTruth) {
        let g = Generator.orders(config)
        let wh = Warehouse()
        let report = try OrdersPipeline.make(csv: g.csv).run(into: wh)
        return (report, wh, g.truth)
    }

    func testExtractedAndLoadedCountsMatchGroundTruth() throws {
        let r = try runPipeline()
        XCTAssertEqual(r.report.extracted, r.truth.totalDataLines)
        XCTAssertEqual(r.report.loaded, r.truth.cleanOrders)
        XCTAssertEqual(r.warehouse.facts.count, r.truth.cleanOrders)
    }

    func testNoRowIsSilentlyLost() throws {
        let r = try runPipeline()
        XCTAssertEqual(r.report.extracted, r.report.loaded + r.report.rejected.count)
    }

    func testRejectionsMatchInjectedDefectsByReason() throws {
        let r = try runPipeline()
        XCTAssertEqual(r.report.rejectedByReason, [
            "bad_date:order_date": r.truth.badDate,
            "non_positive:quantity": r.truth.negativeQuantity,
            "duplicate:order_id": r.truth.duplicates,
        ])
    }

    func testRevenueReconcilesPerTenant() throws {
        let r = try runPipeline()
        XCTAssertFalse(r.truth.revenueByTenant.isEmpty)
        for (tenant, expected) in r.truth.revenueByTenant {
            let rows = r.warehouse.query(tenant: tenant, groupBy: [], measures: [.sum("revenue")])
            XCTAssertEqual(rows.count, 1, "tenant \(tenant)")
            let actual = try XCTUnwrap(rows.first?.values["sum_revenue"])
            XCTAssertEqual(actual, expected, accuracy: 1e-6, "tenant \(tenant)")
        }
    }

    func testTenantIsolation() throws {
        let r = try runPipeline()
        for t in 1...3 {
            let tenant = "T\(t)"
            let rows = r.warehouse.query(tenant: tenant, groupBy: ["tenant_id"], measures: [.count])
            XCTAssertEqual(rows.count, 1, "only one tenant key may appear in \(tenant)'s results")
            XCTAssertEqual(rows.first?.keys, [.string(tenant)])
        }
        XCTAssertTrue(r.warehouse.query(tenant: "T999", groupBy: [], measures: [.count]).isEmpty)
    }

    func testRegionBucketsSumToTenantTotal() throws {
        let r = try runPipeline()
        let byRegion = r.warehouse.query(tenant: "T1", groupBy: ["region"], measures: [.count])
        let total = byRegion.reduce(0.0) { $0 + ($1.values["count"] ?? 0) }
        XCTAssertEqual(Int(total), r.warehouse.rowCount(tenant: "T1"))
    }

    func testSameSeedIsDeterministicAndDifferentSeedDiffers() throws {
        let a = Generator.orders(GenConfig(seed: 7))
        let b = Generator.orders(GenConfig(seed: 7))
        let c = Generator.orders(GenConfig(seed: 8))
        XCTAssertEqual(a.csv, b.csv)
        XCTAssertNotEqual(a.csv, c.csv)
    }

    func testPipelineReportsStageCounts() throws {
        let r = try runPipeline()
        XCTAssertEqual(r.report.stages.map(\.name),
                       ["typecast", "positive_quantity", "dedupe", "derive_revenue", "derive_order_month"])
        XCTAssertEqual(r.report.stages.first?.rowsIn, r.truth.totalDataLines)
    }

    /// Golden check, independent of GroundTruth: hand-derived from the defect schedule for
    /// 3 tenants x 200 orders. Per tenant: 5 negative (i%40), 3 bad dates (55,110,165),
    /// 7 duplicates (i%25, excluding 200) -> 207 lines, 192 loaded, 15 rejected.
    /// Catches a bug shared by the generator and its oracle (they are computed in one loop).
    func testDefaultRunMatchesHandComputedTotals() throws {
        let r = try runPipeline()
        XCTAssertEqual(r.report.extracted, 621)
        XCTAssertEqual(r.report.loaded, 576)
        XCTAssertEqual(r.report.rejected.count, 45)
    }
}
