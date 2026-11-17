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

public protocol Sink {
    func load(_ rows: [Row]) throws
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
    public let loaded: Int

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

    public init(extractor: any Extractor, transforms: [any Transform]) {
        self.extractor = extractor
        self.transforms = transforms
    }

    /// Invariant (asserted in tests): extracted == loaded + rejected.count -- no row silently lost.
    public func run(into sink: any Sink) throws -> RunReport {
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

        try sink.load(rows)
        return RunReport(extracted: extracted, stages: stages, rejected: rejected, loaded: rows.count)
    }
}
