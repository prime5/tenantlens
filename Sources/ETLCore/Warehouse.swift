import Foundation

/// In-memory fact store. Phase 2 swaps this for a SQLite-backed Sink behind the same protocol.
public final class Warehouse: Sink {
    public private(set) var facts: [Row] = []

    public init() {}

    public func load(_ rows: [Row]) throws {
        facts.append(contentsOf: rows)
    }

    public func rowCount(tenant: String) -> Int {
        facts.filter { $0["tenant_id"]?.string == tenant }.count
    }
}

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
}

public struct QueryRow: Equatable {
    public let keys: [Value]
    public let values: [String: Double]
}

extension Warehouse {
    /// Tenant-scoped aggregate query. There is deliberately NO unscoped variant:
    /// every read goes through a tenant, the way a BI "space" isolates one customer's data.
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

        // Dictionaries are unordered; sort so results (and UI charts) are deterministic.
        return result.sorted { a, b in
            a.keys.map(\.display).joined(separator: "|") < b.keys.map(\.display).joined(separator: "|")
        }
    }
}
