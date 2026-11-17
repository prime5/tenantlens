import Foundation

// Python delta: a Swift `enum` with associated values is what you'd model in Python with a
// Union[str, int, float, date, None] plus isinstance checks -- except the compiler forces
// every `switch` over it to be exhaustive.
public enum Value: Equatable, Hashable, Sendable {
    case string(String)
    case int(Int)
    case double(Double)
    case date(Date)
    case null

    public var string: String? { if case .string(let s) = self { return s }; return nil }
    public var int: Int? { if case .int(let i) = self { return i }; return nil }
    public var date: Date? { if case .date(let d) = self { return d }; return nil }
    public var isNull: Bool { if case .null = self { return true }; return false }

    /// Numeric view: ints widen to Double, everything else is nil.
    public var double: Double? {
        switch self {
        case .double(let d): return d
        case .int(let i): return Double(i)
        default: return nil
        }
    }

    /// Stable text form, used for display and deterministic ordering.
    public var display: String {
        switch self {
        case .string(let s): return s
        case .int(let i): return String(i)
        case .double(let d): return String(d)
        case .date(let d): return DateParsing.format(d)
        case .null: return ""
        }
    }
}

/// One record. Python equivalent: dict[str, Value].
public typealias Row = [String: Value]

public enum ColumnType: Sendable { case string, int, double, date }

public struct Column: Sendable {
    public let name: String
    public let type: ColumnType
    public let required: Bool

    public init(_ name: String, _ type: ColumnType, required: Bool = true) {
        self.name = name
        self.type = type
        self.required = required
    }
}

public struct Schema: Sendable {
    public let columns: [Column]
    public init(_ columns: [Column]) { self.columns = columns }
}

public enum DateParsing {
    private static var calendar: Calendar {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "UTC")!
        return c
    }

    /// Strict `yyyy-MM-dd` (UTC). Returns nil for impossible dates such as 2026-02-31
    /// or 2026-13-45, which Calendar would otherwise silently roll over.
    public static func parse(_ text: String) -> Date? {
        let parts = text.split(separator: "-", omittingEmptySubsequences: false)
        guard parts.count == 3, parts[0].count == 4,
              let y = Int(parts[0]), let m = Int(parts[1]), let d = Int(parts[2])
        else { return nil }

        var comps = DateComponents()
        comps.year = y
        comps.month = m
        comps.day = d
        let cal = calendar
        guard let date = cal.date(from: comps) else { return nil }

        // Round-trip check: reject anything the calendar normalised.
        let back = cal.dateComponents([.year, .month, .day], from: date)
        guard back.year == y, back.month == m, back.day == d else { return nil }
        return date
    }

    public static func format(_ date: Date) -> String {
        let c = calendar.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d-%02d-%02d", c.year ?? 0, c.month ?? 0, c.day ?? 0)
    }
}
