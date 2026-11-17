import Foundation

/// Converts raw string cells into typed Values according to a Schema.
/// Rejects rows with a missing required column or an unparseable value.
public struct TypeCast: Transform {
    public let name = "typecast"
    public let schema: Schema

    public init(_ schema: Schema) { self.schema = schema }

    public func apply(_ rows: [Row]) -> TransformResult {
        var out = TransformResult()
        for row in rows {
            var typed = Row()
            var failure: String?

            for col in schema.columns {
                let raw = (row[col.name]?.string ?? "").trimmingCharacters(in: .whitespaces)
                if raw.isEmpty {
                    if col.required { failure = "missing:\(col.name)"; break }
                    typed[col.name] = .null
                    continue
                }
                switch col.type {
                case .string:
                    typed[col.name] = .string(raw)
                case .int:
                    if let v = Int(raw) { typed[col.name] = .int(v) } else { failure = "bad_int:\(col.name)" }
                case .double:
                    if let v = Double(raw) { typed[col.name] = .double(v) } else { failure = "bad_double:\(col.name)" }
                case .date:
                    if let v = DateParsing.parse(raw) { typed[col.name] = .date(v) } else { failure = "bad_date:\(col.name)" }
                }
                if failure != nil { break }
            }

            if let reason = failure {
                out.rejected.append(RejectedRow(stage: name, reason: reason, row: row))
            } else {
                out.kept.append(typed)
            }
        }
        return out
    }
}

/// Rejects rows for which `isValid` is false, tagging them with `reason`.
public struct Validate: Transform {
    public let name: String
    public let reason: String
    public let isValid: @Sendable (Row) -> Bool

    public init(name: String, reason: String, isValid: @escaping @Sendable (Row) -> Bool) {
        self.name = name
        self.reason = reason
        self.isValid = isValid
    }

    public func apply(_ rows: [Row]) -> TransformResult {
        var out = TransformResult()
        for row in rows {
            if isValid(row) {
                out.kept.append(row)
            } else {
                out.rejected.append(RejectedRow(stage: name, reason: reason, row: row))
            }
        }
        return out
    }
}

/// Keeps the first row per key; later rows with the same key are rejected as duplicates.
public struct Dedupe: Transform {
    public let name = "dedupe"
    public let keys: [String]

    public init(keys: [String]) { self.keys = keys }

    public func apply(_ rows: [Row]) -> TransformResult {
        var out = TransformResult()
        var seen = Set<[Value]>()
        for row in rows {
            let key = keys.map { row[$0] ?? .null }
            if seen.insert(key).inserted {
                out.kept.append(row)
            } else {
                out.rejected.append(RejectedRow(stage: name, reason: "duplicate:\(keys.joined(separator: ","))", row: row))
            }
        }
        return out
    }
}

/// Adds a computed column.
public struct Derive: Transform {
    public let name: String
    public let column: String
    public let compute: @Sendable (Row) -> Value

    public init(column: String, compute: @escaping @Sendable (Row) -> Value) {
        self.name = "derive_\(column)"
        self.column = column
        self.compute = compute
    }

    public func apply(_ rows: [Row]) -> TransformResult {
        let kept = rows.map { row -> Row in
            var r = row
            r[column] = compute(row)
            return r
        }
        return TransformResult(kept: kept, rejected: [])
    }
}
