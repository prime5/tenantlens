import Foundation

public enum Measure: Sendable {
    case count
    case sum(String)
    case avg(String)

    public var label: String {
        switch self {
        case .count: return "count"
        case .sum(let c): return "sum_\(c)"
        case .avg(let c): return "avg_\(c)"
        }
    }

    public var column: String? {
        switch self {
        case .count: return nil
        case .sum(let c), .avg(let c): return c
        }
    }
}

public struct QueryRow: Equatable, Sendable {
    public let keys: [Value]
    public let values: [String: Double]

    public init(keys: [Value], values: [String: Double]) {
        self.keys = keys
        self.values = values
    }

    /// One ordering shared by every warehouse, so results (and UI charts) are deterministic
    /// and two warehouses' answers can be compared row by row.
    public static func sortedByKeys(_ rows: [QueryRow]) -> [QueryRow] {
        rows.sorted { a, b in
            a.keys.map(\.display).joined(separator: "|") < b.keys.map(\.display).joined(separator: "|")
        }
    }
}

/// Every read goes through a tenant -- there is deliberately NO unscoped query,
/// the way a BI "space" isolates one customer's data.
public protocol TenantQueryable {
    func query(tenant: String, groupBy: [String], measures: [Measure]) throws -> [QueryRow]
    func rowCount(tenant: String) throws -> Int
}

/// In-memory fact store. Also the reference implementation SQLiteWarehouse is checked against.
public final class Warehouse: Sink, TenantQueryable {
    public private(set) var facts: [Row] = []
    public let primaryKey: [String]
    private var positionByKey: [[Value]: Int] = [:]

    /// Empty `primaryKey` = append-only (Phase 1 behaviour). Non-empty = upsert by key.
    public init(primaryKey: [String] = []) {
        self.primaryKey = primaryKey
    }

    @discardableResult
    public func load(_ rows: [Row]) throws -> LoadResult {
        var result = LoadResult()
        for row in rows {
            if primaryKey.isEmpty {
                facts.append(row)
                result.inserted += 1
                continue
            }
            let key = primaryKey.map { row[$0] ?? .null }
            if let i = positionByKey[key] {
                if facts[i] == row {
                    result.unchanged += 1
                } else {
                    facts[i] = row
                    result.updated += 1
                }
            } else {
                positionByKey[key] = facts.count
                facts.append(row)
                result.inserted += 1
            }
        }
        return result
    }

    public func rowCount(tenant: String) -> Int {
        facts.filter { $0["tenant_id"]?.string == tenant }.count
    }

    public func query(tenant: String, groupBy: [String], measures: [Measure]) -> [QueryRow] {
        var buckets: [[Value]: [Row]] = [:]
        for row in facts where row["tenant_id"]?.string == tenant {
            let key = groupBy.map { row[$0] ?? .null }
            buckets[key, default: []].append(row)
        }

        let result = buckets.map { entry -> QueryRow in
            let rows = entry.value
            var values: [String: Double] = [:]
            for m in measures {
                switch m {
                case .count:
                    values[m.label] = Double(rows.count)
                case .sum(let c):
                    values[m.label] = rows.compactMap { $0[c]?.double }.reduce(0, +)
                case .avg(let c):
                    let xs = rows.compactMap { $0[c]?.double }
                    values[m.label] = xs.isEmpty ? 0 : xs.reduce(0, +) / Double(xs.count)
                }
            }
            return QueryRow(keys: entry.key, values: values)
        }
        return QueryRow.sortedByKeys(result)
    }
}
