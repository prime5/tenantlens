import XCTest
import ETLCore

final class CSVTests: XCTestCase {
    func testQuotedCommaAndEscapedQuote() {
        let t = CSV.parse("a,b\n\"x,y\",\"he said \"\"hi\"\"\"\n")
        XCTAssertEqual(t, [["a", "b"], ["x,y", "he said \"hi\""]])
    }

    func testCRLFLineEndings() {
        XCTAssertEqual(CSV.parse("a,b\r\n1,2\r\n"), [["a", "b"], ["1", "2"]])
    }

    func testNoTrailingNewline() {
        XCTAssertEqual(CSV.parse("a,b\n1,2"), [["a", "b"], ["1", "2"]])
    }

    func testExtractorBuildsStringRowsAndSkipsBlankLines() throws {
        let rows = try CSVExtractor(text: "id,qty\n1,5\n\n2,6\n").extract()
        XCTAssertEqual(rows, [
            ["id": .string("1"), "qty": .string("5")],
            ["id": .string("2"), "qty": .string("6")],
        ])
    }

    func testShortRowGetsEmptyStrings() throws {
        let rows = try CSVExtractor(text: "a,b,c\n1,2\n").extract()
        XCTAssertEqual(rows, [["a": .string("1"), "b": .string("2"), "c": .string("")]])
    }

    func testStrictDateParsing() {
        XCTAssertNotNil(DateParsing.parse("2026-02-28"))
        XCTAssertNil(DateParsing.parse("2026-02-31"))   // calendar would roll this over
        XCTAssertNil(DateParsing.parse("2026-13-45"))
        XCTAssertNil(DateParsing.parse("26-01-01"))
        XCTAssertEqual(DateParsing.parse("2026-03-09").map(DateParsing.format), "2026-03-09")
    }
}
