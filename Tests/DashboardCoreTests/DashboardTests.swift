import XCTest
import ETLCore
import DataGen
import DashboardCore

/// The dashboard's numbers, checked without any UI: against the generator's GroundTruth and
/// hand-derived totals. Phase 4 then checks that the screen shows these same numbers.
final class DashboardTests: XCTestCase {
    private func loaded() throws -> (warehouse: Warehouse, truth: GroundTruth, report: RunReport) {
        let g = Generator.orders()
        let wh = Warehouse(primaryKey: OrdersPipeline.primaryKey)
        let report = try OrdersPipeline.make(csv: g.csv).run(into: wh)
        return (wh, g.truth, report)
    }

    func testRevenueByRegionReconcilesWithGroundTruth() throws {
        let (wh, truth, _) = try loaded()
        XCTAssertEqual(truth.revenueByTenant.count, 3)
        for (tenant, expected) in truth.revenueByTenant {
            let snap = try Dashboard.snapshot(tenant: tenant, from: wh)
            XCTAssertEqual(snap.revenueByRegion.map(\.label), ["APAC", "EMEA", "NA"], tenant)
            XCTAssertEqual(snap.revenueByRegion.map(\.value).reduce(0, +), expected, accuracy: 1e-6, tenant)
            XCTAssertEqual(snap.totalRevenue, expected, accuracy: 1e-6, tenant)
        }
    }

    func testOrdersByMonthCoversEveryLoadedOrder() throws {
        let (wh, _, _) = try loaded()
        let snap = try Dashboard.snapshot(tenant: "T1", from: wh)
        XCTAssertEqual(snap.ordersByMonth.map(\.label), (1...12).map { String(format: "2026-%02d", $0) })
        XCTAssertEqual(Int(snap.ordersByMonth.map(\.value).reduce(0, +)), 192)
    }

    func testUnknownTenantGivesEmptyDashboard() throws {
        let (wh, _, _) = try loaded()
        let snap = try Dashboard.snapshot(tenant: "T999", from: wh)
        XCTAssertTrue(snap.revenueByRegion.isEmpty)
        XCTAssertTrue(snap.ordersByMonth.isEmpty)
        XCTAssertEqual(snap.totalRevenue, 0)
    }

    func testRunSummaryMirrorsReport() throws {
        let (_, _, report) = try loaded()
        XCTAssertEqual(RunSummary(report),
                       RunSummary(extracted: 621, loaded: 576, rejected: 45, inserted: 576, updated: 0, unchanged: 0))
    }

    /// The Phase 4 UI tests look elements up by these strings.
    func testAccessibilityContractIsStable() {
        XCTAssertEqual(AccessibilityID.tenantPicker, "tenantPicker")
        XCTAssertEqual(AccessibilityID.revenueRow("NA"), "revenueRow.NA")
        XCTAssertEqual(AccessibilityID.ordersRow("2026-03"), "ordersRow.2026-03")
        XCTAssertEqual(AccessibilityID.totalRevenue, "totalRevenue")
        XCTAssertEqual(AccessibilityID.runExtracted, "runReport.extracted")
        XCTAssertEqual(AccessibilityID.runLoaded, "runReport.loaded")
        XCTAssertEqual(AccessibilityID.runRejected, "runReport.rejected")
    }

    func testAccessibilityNumbersAreLocaleIndependent() {
        XCTAssertEqual(AXValue.number(1234.5), "1234.50")
        XCTAssertEqual(AXValue.number(0), "0.00")
    }
}
