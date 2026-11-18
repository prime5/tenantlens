import Foundation
import ETLCore

public enum QueryError: Error, Equatable {
    case unknownColumn(String)
    case noMeasures
}

/// Identifiers (table/column names) cannot be bound as `?` parameters, so they are validated
/// against the schema first and then quoted. Values are always bound, never interpolated.
private func quoteIdentifier(_ name: String) -> String {
    "\"" + name.replacingOccurrences(of: "\"", with: "\"\"") + "\""
}

private func sqlType(_ type: ColumnType) -> String {
    switch type {
    case .string: return "TEXT"
    case .int: return "INTEGER"
    case .double: return "REAL"   // 8-byte IEEE float, same as Swift Double / Python float
    case .date: return "TEXT"     // 'yyyy-MM-dd': sorts correctly as text, readable in the sqlite3 shell
    }
}

/// SQLite-backed warehouse: upsert by primary key, one row in `load_runs` per load,
/// tenant-scoped queries only.
public final class SQLiteWarehouse: Sink, TenantQueryable {
    public let schema: Schema
    public let primaryKey: [String]
    private let db: SQLiteDB
    private let columnsByName: [String: Column]

    /// `path` ":memory:" = a private in-memory database; any other path = a file that persists.
    public init(path: String = ":memory:", schema: Schema, primaryKey: [String]) throws {
        self.schema = schema
        self.primaryKey = primaryKey
        self.db = try SQLiteDB(path: path)
        self.columnsByName = Dictionary(uniqueKeysWithValues: schema.columns.map { ($0.name, $0) })

        let columnDefs = schema.columns.map {
            "\(quoteIdentifier($0.name)) \(sqlType($0.type))\($0.required ? " NOT NULL" : "")"
        }
        try db.execute("""
            CREATE TABLE IF NOT EXISTS facts (
                \(columnDefs.joined(separator: ",\n    ")),
                PRIMARY KEY (\(primaryKey.map(quoteIdentifier).joined(separator: ", ")))
            );
            CREATE TABLE IF NOT EXISTS load_runs (
                id INTEGER PRIMARY KEY AUTOINCREMENT,
                loaded_at TEXT NOT NULL,
                inserted INTEGER NOT NULL,
                updated INTEGER NOT NULL,
                unchanged INTEGER NOT NULL
            );
            """)
    }

    // MARK: Sink

    /// Per row: look up by primary key, then insert / update / leave alone. One transaction per
    /// load, so a failure part-way leaves the warehouse exactly as it was.
    @discardableResult
    public func load(_ rows: [Row]) throws -> LoadResult {
        let names = schema.columns.map { quoteIdentifier($0.name) }
        let byKey = primaryKey.map { "\(quoteIdentifier($0)) = ?" }.joined(separator: " AND ")
        let selectSQL = "SELECT \(names.joined(separator: ", ")) FROM facts WHERE \(byKey)"
        let insertSQL = "INSERT INTO facts (\(names.joined(separator: ", "))) VALUES (\(Array(repeating: "?", count: names.count).joined(separator: ", ")))"
        let updateSQL = "UPDATE facts SET \(names.map { "\($0) = ?" }.joined(separator: ", ")) WHERE \(byKey)"

        return try db.transaction {
            var result = LoadResult()
            for row in rows {
                let incoming = schema.columns.map { row[$0.name] ?? .null }
                let key = primaryKey.map { row[$0] ?? .null }

                var existing: [Value]?
                try db.query(selectSQL, key) { stmt in
                    existing = schema.columns.enumerated().map { i, col in
                        stmt.value(at: Int32(i), as: col.type)
                    }
                }

                if let old = existing {
                    if old == incoming {
                        result.unchanged += 1
                    } else {
                        try db.query(updateSQL, incoming + key)
                        result.updated += 1
                    }
                } else {
                    try db.query(insertSQL, incoming)
                    result.inserted += 1
                }
            }
            try db.query(
                "INSERT INTO load_runs (loaded_at, inserted, updated, unchanged) VALUES (?, ?, ?, ?)",
                [.string(ISO8601DateFormatter().string(from: Date())),
                 .int(result.inserted), .int(result.updated), .int(result.unchanged)]
            )
            return result
        }
    }

    // MARK: TenantQueryable

    public func query(tenant: String, groupBy: [String], measures: [Measure]) throws -> [QueryRow] {
        guard !measures.isEmpty else { throw QueryError.noMeasures }
        let groupColumns = try groupBy.map { name -> Column in
            guard let col = columnsByName[name] else { throw QueryError.unknownColumn(name) }
            return col
        }
        for m in measures {
            if let c = m.column, columnsByName[c] == nil { throw QueryError.unknownColumn(c) }
        }

        var select = groupColumns.map { quoteIdentifier($0.name) }
        for m in measures {
            switch m {
            case .count: select.append("COUNT(*)")
            case .sum(let c): select.append("TOTAL(\(quoteIdentifier(c)))")   // TOTAL = SUM that returns 0.0, not NULL
            case .avg(let c): select.append("AVG(\(quoteIdentifier(c)))")
            }
        }

        var sql = "SELECT \(select.joined(separator: ", ")) FROM facts WHERE \(quoteIdentifier("tenant_id")) = ?"
        if !groupColumns.isEmpty {
            sql += " GROUP BY " + groupColumns.map { quoteIdentifier($0.name) }.joined(separator: ", ")
        }
        // SQL returns one row for an aggregate over zero rows (COUNT 0, SUM NULL); the in-memory
        // warehouse returns no buckets. HAVING makes the two agree. The parity test pins this.
        sql += " HAVING COUNT(*) > 0"

        var out: [QueryRow] = []
        try db.query(sql, [.string(tenant)]) { stmt in
            let keys = groupColumns.enumerated().map { i, col in stmt.value(at: Int32(i), as: col.type) }
            var values: [String: Double] = [:]
            for (j, m) in measures.enumerated() {
                values[m.label] = stmt.double(at: Int32(groupColumns.count + j))
            }
            out.append(QueryRow(keys: keys, values: values))
        }
        return QueryRow.sortedByKeys(out)
    }

    public func rowCount(tenant: String) throws -> Int {
        var n = 0
        try db.query("SELECT COUNT(*) FROM facts WHERE \(quoteIdentifier("tenant_id")) = ?", [.string(tenant)]) {
            n = $0.int(at: 0)
        }
        return n
    }

    public func loadRunCount() throws -> Int {
        var n = 0
        try db.query("SELECT COUNT(*) FROM load_runs") { n = $0.int(at: 0) }
        return n
    }
}
