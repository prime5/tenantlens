import Foundation
import SQLite3
import ETLCore

public enum SQLiteError: Error, CustomStringConvertible {
    case open(String)
    case prepare(String, sql: String)
    case step(String)
    case bind(String)

    public var description: String {
        switch self {
        case .open(let m): return "sqlite open: \(m)"
        case .prepare(let m, let sql): return "sqlite prepare: \(m) [\(sql)]"
        case .step(let m): return "sqlite step: \(m)"
        case .bind(let m): return "sqlite bind: \(m)"
        }
    }
}

// SQLITE_TRANSIENT is a C macro (-1 cast to a function pointer) that Swift cannot import.
// It tells SQLite to copy the bound string, because Swift's temporary C string dies after the call.
private let transientDestructor = unsafeBitCast(-1, to: sqlite3_destructor_type.self)

/// Thin wrapper over the C API. Python delta: this is the part `sqlite3.connect()` hides.
public final class SQLiteDB {
    private var handle: OpaquePointer?

    public init(path: String) throws {
        if sqlite3_open(path, &handle) != SQLITE_OK {
            let message = String(cString: sqlite3_errmsg(handle))
            sqlite3_close(handle)
            handle = nil
            throw SQLiteError.open(message)
        }
    }

    /// ARC runs this as soon as the last reference goes away -- deterministic, unlike CPython's __del__.
    deinit {
        sqlite3_close(handle)
    }

    private var errorMessage: String { String(cString: sqlite3_errmsg(handle)) }

    /// Runs one or more statements with no parameters and no results (DDL, BEGIN/COMMIT).
    public func execute(_ sql: String) throws {
        var err: UnsafeMutablePointer<CChar>?
        if sqlite3_exec(handle, sql, nil, nil, &err) != SQLITE_OK {
            let message = err.map { String(cString: $0) } ?? errorMessage
            sqlite3_free(err)
            throw SQLiteError.step(message)
        }
    }

    /// Prepares `sql`, binds `params` to its `?` placeholders, and calls `row` per result row.
    /// The Statement passed to `row` is only valid inside the closure.
    public func query(_ sql: String, _ params: [Value] = [], row: (Statement) throws -> Void = { _ in }) throws {
        var prepared: OpaquePointer?
        guard sqlite3_prepare_v2(handle, sql, -1, &prepared, nil) == SQLITE_OK, let stmt = prepared else {
            throw SQLiteError.prepare(errorMessage, sql: sql)
        }
        defer { sqlite3_finalize(stmt) }   // Python delta: try/finally

        for (i, p) in params.enumerated() {
            try bind(p, at: Int32(i + 1), stmt)   // SQLite parameters are 1-based
        }
        while true {
            let rc = sqlite3_step(stmt)
            if rc == SQLITE_ROW {
                try row(Statement(stmt: stmt))
            } else if rc == SQLITE_DONE {
                return
            } else {
                throw SQLiteError.step(errorMessage)
            }
        }
    }

    public func transaction<T>(_ body: () throws -> T) throws -> T {
        try execute("BEGIN")
        do {
            let result = try body()
            try execute("COMMIT")
            return result
        } catch {
            try? execute("ROLLBACK")
            throw error
        }
    }

    private func bind(_ value: Value, at i: Int32, _ stmt: OpaquePointer) throws {
        let rc: Int32
        switch value {
        case .string(let s): rc = sqlite3_bind_text(stmt, i, s, -1, transientDestructor)
        case .int(let n): rc = sqlite3_bind_int64(stmt, i, Int64(n))
        case .double(let d): rc = sqlite3_bind_double(stmt, i, d)
        case .date(let d): rc = sqlite3_bind_text(stmt, i, DateParsing.format(d), -1, transientDestructor)
        case .null: rc = sqlite3_bind_null(stmt, i)
        }
        guard rc == SQLITE_OK else { throw SQLiteError.bind(errorMessage) }
    }
}

/// A cursor positioned on one result row.
public struct Statement {
    let stmt: OpaquePointer

    /// Reads column `i` back into a typed Value, using the schema's type (SQLite itself is loosely typed).
    public func value(at i: Int32, as type: ColumnType) -> Value {
        if sqlite3_column_type(stmt, i) == SQLITE_NULL { return .null }
        switch type {
        case .string:
            return .string(String(cString: sqlite3_column_text(stmt, i)))
        case .int:
            return .int(Int(sqlite3_column_int64(stmt, i)))
        case .double:
            return .double(sqlite3_column_double(stmt, i))
        case .date:
            let text = String(cString: sqlite3_column_text(stmt, i))
            return DateParsing.parse(text).map { .date($0) } ?? .null
        }
    }

    public func double(at i: Int32) -> Double { sqlite3_column_double(stmt, i) }
    public func int(at i: Int32) -> Int { Int(sqlite3_column_int64(stmt, i)) }
}
