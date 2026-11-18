import Foundation
import ETLCore

/// One labelled number in a chart series ("NA" -> 17534.99, "2026-03" -> 16).
public struct SeriesPoint: Equatable, Identifiable, Sendable {
    public let label: String
    public let value: Double
    public var id: String { label }

    public init(label: String, value: Double) {
        self.label = label
        self.value = value
    }
}

/// Everything one tenant's dashboard shows. Built by plain functions so it can be unit-tested
/// without any UI; the SwiftUI app only renders it.
public struct DashboardSnapshot: Equatable, Sendable {
    public let tenant: String
    public let revenueByRegion: [SeriesPoint]
    public let ordersByMonth: [SeriesPoint]
    public let totalRevenue: Double
}

/// The run-report panel's numbers.
public struct RunSummary: Equatable, Sendable {
    public let extracted: Int
    public let loaded: Int
    public let rejected: Int
    public let inserted: Int
    public let updated: Int
    public let unchanged: Int

    public init(extracted: Int, loaded: Int, rejected: Int, inserted: Int, updated: Int, unchanged: Int) {
        self.extracted = extracted
        self.loaded = loaded
        self.rejected = rejected
        self.inserted = inserted
        self.updated = updated
        self.unchanged = unchanged
    }

    public init(_ report: RunReport) {
        self.init(extracted: report.extracted, loaded: report.loaded, rejected: report.rejected.count,
                  inserted: report.load.inserted, updated: report.load.updated, unchanged: report.load.unchanged)
    }
}

public enum Dashboard {
    /// Each series is exactly one tenant-scoped warehouse query -- no re-aggregation in the UI layer,
    /// so a number on screen can be reconciled against one query.
    public static func snapshot(tenant: String, from store: any TenantQueryable) throws -> DashboardSnapshot {
        let byRegion = try store.query(tenant: tenant, groupBy: ["region"], measures: [.sum("revenue")])
        let byMonth = try store.query(tenant: tenant, groupBy: ["order_month"], measures: [.count])
        let total = try store.query(tenant: tenant, groupBy: [], measures: [.sum("revenue")])

        return DashboardSnapshot(
            tenant: tenant,
            revenueByRegion: byRegion.map { SeriesPoint(label: $0.keys.first?.display ?? "", value: $0.values["sum_revenue"] ?? 0) },
            ordersByMonth: byMonth.map { SeriesPoint(label: $0.keys.first?.display ?? "", value: $0.values["count"] ?? 0) },
            totalRevenue: total.first?.values["sum_revenue"] ?? 0
        )
    }
}
