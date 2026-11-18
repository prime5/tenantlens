import Foundation

/// The contract between the app and its UI tests: the app tags elements with these identifiers,
/// the XCUITest suite (Phase 4) finds elements by them. One definition, imported by both, so the
/// strings cannot drift apart. Changing a value is a breaking change -- DashboardCoreTests pins them.
public enum AccessibilityID {
    public static let tenantPicker = "tenantPicker"
    public static let revenueChart = "revenueChart"
    public static let ordersChart = "ordersChart"
    public static let totalRevenue = "totalRevenue"
    public static let runExtracted = "runReport.extracted"
    public static let runLoaded = "runReport.loaded"
    public static let runRejected = "runReport.rejected"

    public static func revenueRow(_ region: String) -> String { "revenueRow.\(region)" }
    public static func ordersRow(_ month: String) -> String { "ordersRow.\(month)" }
}

/// Accessibility values carry raw numbers. String(format:) does not localize, so "1234.50" is the
/// same on every machine -- unlike the visible currency text, which depends on the user's locale.
public enum AXValue {
    public static func number(_ value: Double) -> String { String(format: "%.2f", value) }
}
