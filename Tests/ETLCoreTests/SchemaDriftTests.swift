import XCTest
import ETLCore

/// What happens when the input's shape changes upstream. Policy:
///   extra column -> ignored and reported; missing optional -> null; reordered -> harmless;
///   missing required -> whole batch refused; type drift -> reject-rate guard refuses the batch.
final class SchemaDriftTests: XCTestCase {
    private let schema = Schema([
        Column("id", .string),
        Column("qty", .int),
        Column("note", .string, required: false),
    ])

    private func pipeline(_ csv: String, maxRejectRate: Double? = nil) -> Pipeline {
        Pipeline(extractor: CSVExtractor(text: csv), transforms: [TypeCast(schema)],
                 contract: schema, maxRejectRate: maxRejectRate)
    }

    func testExtraColumnIsIgnoredAndReported() throws {
        let wh = Warehouse()
        let report = try pipeline("id,qty,note,coupon\n1,2,hi,X\n").run(into: wh)
        XCTAssertEqual(report.ignoredColumns, ["coupon"])
        XCTAssertEqual(wh.facts, [["id": .string("1"), "qty": .int(2), "note": .string("hi")]])
    }

    func testMissingOptionalColumnLoadsAsNull() throws {
        let wh = Warehouse()
        try pipeline("id,qty\n1,2\n").run(into: wh)
        XCTAssertEqual(wh.facts.first?["note"], Value.null)
    }

    func testReorderedColumnsAreHarmless() throws {
        let wh = Warehouse()
        try pipeline("qty,note,id\n2,hi,1\n").run(into: wh)
        XCTAssertEqual(wh.facts, [["id": .string("1"), "qty": .int(2), "note": .string("hi")]])
    }

    func testMissingRequiredColumnRefusesWholeBatch() {
        let wh = Warehouse()
        XCTAssertThrowsError(try pipeline("id,note\n1,hi\n").run(into: wh)) { error in
            XCTAssertEqual(error as? PipelineError, .missingRequiredColumns(["qty"]))
        }
        XCTAssertTrue(wh.facts.isEmpty)
    }

    func testTypeDriftTripsRejectRateGuard() {
        // Upstream started sending qty as a decimal: every row fails the int cast.
        let wh = Warehouse()
        XCTAssertThrowsError(try pipeline("id,qty\n1,1.5\n2,2.5\n", maxRejectRate: 0.5).run(into: wh)) { error in
            XCTAssertEqual(error as? PipelineError, .rejectRateExceeded(rate: 1.0, limit: 0.5))
        }
        XCTAssertTrue(wh.facts.isEmpty)
    }
}
