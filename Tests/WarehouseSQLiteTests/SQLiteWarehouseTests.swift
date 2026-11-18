import XCTest
import ETLCore
import DataGen
import WarehouseSQLite

/// Differential tests: the in-memory Warehouse is the reference; SQLite must give the same answers.
final class SQLiteWarehouseTests: XCTestCase {
    private func loadedPair() throws -> (memory: Warehouse, sqlite: SQLiteWarehouse) {
        let csv = Generator.orders().csv
        let memory = Warehouse(primaryKey: OrdersPipeline.primaryKey)
        let sqlite = try SQLiteWarehouse(schema: OrdersPipeline.factSchema, primaryKey: OrdersPipeline.primaryKey)
        try OrdersPipeline.make(csv: csv).run(into: memory)
        try OrdersPipeline.make(csv: csv).run(into: sqlite)
        return (memory, sqlite)
    }

    private func assertSameRows(_ a: [QueryRow], _ b: [QueryRow], _ label: String,
                                file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertEqual(a.map(\.keys), b.map(\.keys), label, file: file, line: line)
        for (x, y) in zip(a, b) {
            XCTAssertEqual(Set(x.values.keys), Set(y.values.keys), label, file: file, line: line)
            for (measure, v) in x.values {
                // Summation order differs between the two engines; floats differ in the last bits.
                XCTAssertEqual(v, y.values[measure] ?? .nan, accuracy: 1e-6, "\(label) \(measure)", file: file, line: line)
            }
        }
    }

    func testSameAnswersAsInMemoryForEveryQueryShape() throws {
        let (memory, sqlite) = try loadedPair()
        let shapes: [[String]] = [[], ["region"], ["product"], ["region", "product"], ["order_date"], ["order_month"]]
        let measures: [Measure] = [.count, .sum("revenue"), .avg("quantity")]
        for tenant in ["T1", "T2", "T3", "T999"] {
            for groupBy in shapes {
                let expected = memory.query(tenant: tenant, groupBy: groupBy, measures: measures)
                let actual = try sqlite.query(tenant: tenant, groupBy: groupBy, measures: measures)
                assertSameRows(expected, actual, "\(tenant) by \(groupBy)")
            }
        }
    }

    func testUnknownColumnsAreRejectedNotInterpolated() throws {
        let (_, sqlite) = try loadedPair()
        XCTAssertThrowsError(try sqlite.query(tenant: "T1", groupBy: ["region; DROP TABLE facts"], measures: [.count]))
        XCTAssertThrowsError(try sqlite.query(tenant: "T1", groupBy: [], measures: [.sum("nope")]))
        XCTAssertEqual(try sqlite.rowCount(tenant: "T1"), 192)
    }

    func testTenantIsBoundAsAValue() throws {
        let (_, sqlite) = try loadedPair()
        XCTAssertTrue(try sqlite.query(tenant: "T1' OR '1'='1", groupBy: [], measures: [.count]).isEmpty)
    }

    func testDataAndRunHistoryPersistAcrossConnections() throws {
        let path = FileManager.default.temporaryDirectory
            .appendingPathComponent("tenantlens-\(UUID().uuidString).sqlite").path
        addTeardownBlock { try? FileManager.default.removeItem(atPath: path) }
        let csv = Generator.orders().csv

        do {
            let first = try SQLiteWarehouse(path: path, schema: OrdersPipeline.factSchema,
                                            primaryKey: OrdersPipeline.primaryKey)
            try OrdersPipeline.make(csv: csv).run(into: first)
        }   // `first` goes out of scope here; ARC frees it and deinit closes the connection.

        let reopened = try SQLiteWarehouse(path: path, schema: OrdersPipeline.factSchema,
                                           primaryKey: OrdersPipeline.primaryKey)
        XCTAssertEqual(try reopened.rowCount(tenant: "T1"), 192)
        let rerun = try OrdersPipeline.make(csv: csv).run(into: reopened)
        XCTAssertEqual(rerun.load, LoadResult(unchanged: 576))
        XCTAssertEqual(try reopened.loadRunCount(), 2)
    }
}
