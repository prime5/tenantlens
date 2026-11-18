import Foundation

/// Minimal RFC-4180-style parser: quoted fields, escaped quotes (""), LF and CRLF.
public enum CSV {
    public static func parse(_ text: String) -> [[String]] {
        var rows: [[String]] = []
        var row: [String] = []
        var field = ""
        var inQuotes = false

        // Swift gotcha: "\r\n" is a SINGLE Character (one grapheme cluster), so it needs its own case.
        let chars = Array(text)
        var i = 0
        while i < chars.count {
            let c = chars[i]
            if inQuotes {
                if c == "\"" {
                    if i + 1 < chars.count && chars[i + 1] == "\"" {
                        field.append("\"")
                        i += 1
                    } else {
                        inQuotes = false
                    }
                } else {
                    field.append(c)
                }
            } else {
                switch c {
                case "\"": inQuotes = true
                case ",":
                    row.append(field)
                    field = ""
                case "\n", "\r\n":
                    row.append(field)
                    field = ""
                    rows.append(row)
                    row = []
                case "\r": break
                default: field.append(c)
                }
            }
            i += 1
        }
        if !field.isEmpty || !row.isEmpty {
            row.append(field)
            rows.append(row)
        }
        return rows
    }
}

public protocol Extractor {
    /// Input column names, in source order. Used by the schema contract check.
    func columns() throws -> [String]
    func extract() throws -> [Row]
}

/// Reads CSV text into rows whose values are all `.string`; typing happens in the TypeCast stage.
public struct CSVExtractor: Extractor {
    public let text: String
    public init(text: String) { self.text = text }

    /// Parses the text a second time; fine at this size, and keeps Extractor stateless.
    public func columns() throws -> [String] {
        CSV.parse(text).first ?? []
    }

    public func extract() throws -> [Row] {
        let table = CSV.parse(text)
        guard let header = table.first else { return [] }
        return table.dropFirst()
            .filter { !($0.count == 1 && $0[0].isEmpty) }   // skip blank lines
            .map { cells in
                var r = Row()
                for (i, h) in header.enumerated() {
                    r[h] = .string(i < cells.count ? cells[i] : "")
                }
                return r
            }
    }
}
