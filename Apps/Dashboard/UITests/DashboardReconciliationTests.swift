import XCTest
import ETLCore
import DataGen
import DashboardCore

/// Black-box UI reconciliation. The app runs in its own process (SQLite warehouse); this test
/// process recomputes the expected dashboard from the same seed (in-memory warehouse) and checks
/// every value the app exposes through accessibility. Three oracle layers:
///   a. recompute  -- UI vs an independent recomputation of the same queries
///   b. ground truth -- per-tenant totals vs what the generator injected
///   c. goldens    -- hand-derived counts that do not depend on any shared code
@MainActor
final class DashboardReconciliationTests: XCTestCase {
    private static let seed: UInt64 = 42
    private static let tenants = ["T1", "T2", "T3"]
    /// Values are rendered with 2 decimals; allow half a cent plus float noise.
    private static let tolerance = 0.006

    // MARK: Expected values (computed in this process)

    private struct Expected {
        let truth: GroundTruth
        let run: RunSummary
        let snapshots: [String: DashboardSnapshot]
    }

    private static func expected(seed: UInt64) throws -> Expected {
        let config = GenConfig(seed: seed)
        let generated = Generator.orders(config)
        let warehouse = Warehouse(primaryKey: OrdersPipeline.primaryKey)
        let report = try OrdersPipeline.make(csv: generated.csv).run(into: warehouse)
        var snapshots: [String: DashboardSnapshot] = [:]
        for tenant in tenants {
            snapshots[tenant] = try Dashboard.snapshot(tenant: tenant, from: warehouse)
        }
        return Expected(truth: generated.truth, run: RunSummary(report), snapshots: snapshots)
    }

    // MARK: Driving the app

    private func launch(seed: UInt64) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["-seed", String(seed)]   // read by the app via UserDefaults
        app.launch()
        addTeardownBlock { app.terminate() }
        return app
    }

    /// Find by identifier regardless of element type (SwiftUI decides how a view is exposed).
    private func element(_ app: XCUIApplication, _ id: String) -> XCUIElement {
        app.descendants(matching: .any).matching(identifier: id).firstMatch
    }

    private func number(_ app: XCUIApplication, _ id: String,
                        file: StaticString = #filePath, line: UInt = #line) throws -> Double {
        let e = element(app, id)
        // waitForExistence polls on ~1 s ticks even when the element is already there;
        // check `exists` first so 30+ reads per tenant don't cost a second each.
        if !e.exists {
            XCTAssertTrue(e.waitForExistence(timeout: 5), "missing element \(id)", file: file, line: line)
        }
        let text = try XCTUnwrap(e.value as? String, "no accessibility value on \(id)", file: file, line: line)
        return try XCTUnwrap(Double(text), "\(id) value '\(text)' is not a number", file: file, line: line)
    }

    private func count(_ app: XCUIApplication, idPrefix: String) -> Int {
        app.descendants(matching: .any)
            .matching(NSPredicate(format: "identifier BEGINSWITH %@", idPrefix))
            .count
    }

    /// SwiftUI's segmented Picker surfaces on macOS as radio buttons (or buttons): match by label.
    private func select(_ tenant: String, in app: XCUIApplication,
                        file: StaticString = #filePath, line: UInt = #line) {
        let segment = app.descendants(matching: .any).matching(NSPredicate(
            format: "(elementType == %lu OR elementType == %lu) AND label == %@",
            XCUIElement.ElementType.radioButton.rawValue, XCUIElement.ElementType.button.rawValue, tenant
        )).firstMatch
        XCTAssertTrue(segment.waitForExistence(timeout: 5), "tenant segment \(tenant) not found", file: file, line: line)
        segment.click()
    }

    /// Condition-based wait (bounded polling), never a fixed sleep.
    private func waitUntil(timeout: TimeInterval = 5, _ condition: () -> Bool) -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if condition() { return true }
            RunLoop.current.run(until: Date().addingTimeInterval(0.1))
        }
        return condition()
    }

    private func attachScreenshot(_ app: XCUIApplication, named name: String) {
        let shot = XCTAttachment(screenshot: app.windows.firstMatch.screenshot())
        shot.name = name
        shot.lifetime = .deleteOnSuccess    // kept only when the test fails
        add(shot)
    }

    // MARK: Tests

    func testRunReportMatchesPipeline() throws {
        let app = launch(seed: Self.seed)
        let expected = try Self.expected(seed: Self.seed)

        // c. golden, independent of shared code
        XCTAssertEqual(expected.run, RunSummary(extracted: 621, loaded: 576, rejected: 45,
                                                inserted: 576, updated: 0, unchanged: 0))
        // a. UI vs recompute
        XCTAssertEqual(try number(app, AccessibilityID.runExtracted), Double(expected.run.extracted))
        XCTAssertEqual(try number(app, AccessibilityID.runLoaded), Double(expected.run.loaded))
        XCTAssertEqual(try number(app, AccessibilityID.runRejected), Double(expected.run.rejected))
    }

    func testEveryTenantMatchesWarehouse() throws {
        let app = launch(seed: Self.seed)
        let expected = try Self.expected(seed: Self.seed)

        for tenant in Self.tenants {
            try XCTContext.runActivity(named: "Reconcile \(tenant)") { _ in
                let snap = try XCTUnwrap(expected.snapshots[tenant])
                select(tenant, in: app)

                // Sync point: the total for this tenant is on screen, so the rows are too.
                let total = element(app, AccessibilityID.totalRevenue)
                let shown = waitUntil {
                    guard let v = total.value as? String, let n = Double(v) else { return false }
                    return abs(n - snap.totalRevenue) < Self.tolerance
                }
                attachScreenshot(app, named: tenant)
                XCTAssertTrue(shown, "\(tenant): total never showed \(AXValue.number(snap.totalRevenue))")

                // b. ground truth
                XCTAssertEqual(snap.totalRevenue, expected.truth.revenueByTenant[tenant] ?? -1,
                               accuracy: Self.tolerance, "\(tenant) total vs ground truth")

                // a. every row, and no extra rows
                XCTAssertEqual(count(app, idPrefix: "revenueRow."), snap.revenueByRegion.count, "\(tenant) region rows")
                for p in snap.revenueByRegion {
                    XCTAssertEqual(try number(app, AccessibilityID.revenueRow(p.label)), p.value,
                                   accuracy: Self.tolerance, "\(tenant) revenue \(p.label)")
                }
                XCTAssertEqual(count(app, idPrefix: "ordersRow."), snap.ordersByMonth.count, "\(tenant) month rows")
                for p in snap.ordersByMonth {
                    XCTAssertEqual(try number(app, AccessibilityID.ordersRow(p.label)), p.value,
                                   accuracy: Self.tolerance, "\(tenant) orders \(p.label)")
                }

                // c. golden: every tenant loads 192 orders, spread over 12 months
                XCTAssertEqual(snap.ordersByMonth.count, 12, tenant)
                XCTAssertEqual(Int(snap.ordersByMonth.map(\.value).reduce(0, +)), 192, tenant)
            }
        }
    }

    /// Tests the test: with different data on screen, a seed-42 expectation must NOT match.
    /// Guards against a suite that passes because it is not really looking.
    func testDifferentSeedChangesTheNumbers() throws {
        let app = launch(seed: 7)
        let na42 = try XCTUnwrap(try Self.expected(seed: 42).snapshots["T1"]?.revenueByRegion.first { $0.label == "NA" }?.value)
        let na7 = try XCTUnwrap(try Self.expected(seed: 7).snapshots["T1"]?.revenueByRegion.first { $0.label == "NA" }?.value)
        XCTAssertGreaterThan(abs(na42 - na7), 1.0, "precondition: seeds 7 and 42 must differ")

        let shown = try number(app, AccessibilityID.revenueRow("NA"))
        XCTAssertEqual(shown, na7, accuracy: Self.tolerance, "UI tracks the seed it was launched with")
        XCTAssertNotEqual(shown, na42, accuracy: Self.tolerance, "a stale seed-42 expectation would fail here")
    }

    /// Stretch: read the bars themselves. If this macOS version does not expose Swift Charts marks
    /// to XCUITest, report a skip with the reason instead of silently not testing.
    func testRevenueChartMarksExposeValues() throws {
        let app = launch(seed: Self.seed)
        let snap = try XCTUnwrap(try Self.expected(seed: Self.seed).snapshots["T1"])
        let chart = element(app, AccessibilityID.revenueChart)
        XCTAssertTrue(chart.waitForExistence(timeout: 5), "missing revenue chart")

        var found: [String: Double] = [:]
        for p in snap.revenueByRegion {
            // Axis labels share the region name; keep only the element that carries a numeric value.
            let candidates = chart.descendants(matching: .any)
                .matching(NSPredicate(format: "label == %@", p.label)).allElementsBoundByIndex
            if let n = candidates.lazy.compactMap({ ($0.value as? String).flatMap(Double.init) }).first {
                found[p.label] = n
            }
        }
        if found.isEmpty {
            attachScreenshot(app, named: "chart")
            throw XCTSkip("Swift Charts marks are not exposed to XCUITest here; the tables remain the reconciliation surface.")
        }
        for p in snap.revenueByRegion {
            XCTAssertEqual(found[p.label] ?? .nan, p.value, accuracy: Self.tolerance, "bar \(p.label)")
        }
    }
}
