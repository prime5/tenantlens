import Foundation

public struct RejectedRow {
    public let stage: String
    public let reason: String
    public let row: Row
    public init(stage: String, reason: String, row: Row) {
        self.stage = stage
        self.reason = reason
        self.row = row
    }
}

public struct TransformResult {
    public var kept: [Row]
    public var rejected: [RejectedRow]
    public init(kept: [Row] = [], rejected: [RejectedRow] = []) {
        self.kept = kept
        self.rejected = rejected
    }
}

public protocol Transform {
    var name: String { get }
    func apply(_ rows: [Row]) -> TransformResult
}

/// What a sink did with the rows it was handed. With a primary key, re-sending a row is an
/// `unchanged` no-op and re-sending it with different values is an `updated`.
public struct LoadResult: Equatable, Sendable {
    public var inserted: Int
    public var updated: Int
    public var unchanged: Int

    public init(inserted: Int = 0, updated: Int = 0, unchanged: Int = 0) {
        self.inserted = inserted
        self.updated = updated
        self.unchanged = unchanged
    }

    public var total: Int { inserted + updated + unchanged }
}

public protocol Sink {
    func load(_ rows: [Row]) throws -> LoadResult
}

/// Batch-level failures: the whole batch is refused and nothing reaches the sink.
public enum PipelineError: Error, Equatable, CustomStringConvertible {
    case missingRequiredColumns([String])
    case rejectRateExceeded(rate: Double, limit: Double)

    public var description: String {
        switch self {
        case .missingRequiredColumns(let cols):
            return "schema contract: missing required column(s) \(cols.joined(separator: ", "))"
        case .rejectRateExceeded(let rate, let limit):
            return String(format: "reject rate %.1f%% exceeds limit %.1f%%; nothing loaded", rate * 100, limit * 100)
        }
    }
}

public struct StageReport {
    public let name: String
    public let rowsIn: Int
    public let rowsOut: Int
    public let rejected: Int
    public let seconds: Double
}

public struct RunReport {
    public let extracted: Int
    public let stages: [StageReport]
    public let rejected: [RejectedRow]
    /// Rows handed to the sink (== load.total).
    public let loaded: Int
    public let load: LoadResult
    /// Input columns the contract does not know about; dropped, but reported.
    public let ignoredColumns: [String]

    /// reason -> count. Tests compare this against the generator's injected defects.
    public var rejectedByReason: [String: Int] {
        var out: [String: Int] = [:]
        for r in rejected { out[r.reason, default: 0] += 1 }
        return out
    }
}

public struct Pipeline {
    public let extractor: any Extractor
    public let transforms: [any Transform]
    /// Checked against the input header before any row is processed.
    public let contract: Schema?
    /// If more than this fraction of rows is rejected, refuse the batch (catches upstream type drift,
    /// which otherwise looks like "every row is bad data").
    public let maxRejectRate: Double?

    public init(extractor: any Extractor, transforms: [any Transform],
                contract: Schema? = nil, maxRejectRate: Double? = nil) {
        self.extractor = extractor
        self.transforms = transforms
        self.contract = contract
        self.maxRejectRate = maxRejectRate
    }

    /// Invariant (asserted in tests): extracted == load.total + rejected.count -- no row silently lost.
    @discardableResult
    public func run(into sink: any Sink) throws -> RunReport {
        var ignored: [String] = []
        if let contract {
            let columns = try extractor.columns()
            let present = Set(columns)
            let missing = contract.columns.filter { $0.required && !present.contains($0.name) }.map(\.name)
            if !missing.isEmpty { throw PipelineError.missingRequiredColumns(missing) }
            let known = Set(contract.columns.map(\.name))
            ignored = columns.filter { !known.contains($0) }
        }

        var rows = try extractor.extract()
        let extracted = rows.count
        var stages: [StageReport] = []
        var rejected: [RejectedRow] = []

        for t in transforms {
            let start = Date()
            let result = t.apply(rows)
            stages.append(StageReport(
                name: t.name,
                rowsIn: rows.count,
                rowsOut: result.kept.count,
                rejected: result.rejected.count,
                seconds: Date().timeIntervalSince(start)
            ))
            rejected.append(contentsOf: result.rejected)
            rows = result.kept
        }

        if let limit = maxRejectRate, extracted > 0 {
            let rate = Double(rejected.count) / Double(extracted)
            if rate > limit { throw PipelineError.rejectRateExceeded(rate: rate, limit: limit) }
        }

        let load = try sink.load(rows)
        return RunReport(extracted: extracted, stages: stages, rejected: rejected,
                         loaded: rows.count, load: load, ignoredColumns: ignored)
    }
}
