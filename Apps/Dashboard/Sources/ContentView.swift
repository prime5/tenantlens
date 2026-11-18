import SwiftUI
import Charts
import DashboardCore

// Python delta: a SwiftUI View is a struct whose `body` is a pure function of state --
// closer to a React render function than to a Tk widget you mutate.
struct ContentView: View {
    let model: DashboardModel   // @Observable: a plain property is enough; SwiftUI tracks what body reads

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            header
            if let error = model.errorMessage {
                Text(error).foregroundStyle(.red)
            }
            if let snap = model.snapshot {
                HStack(alignment: .top, spacing: 32) {
                    section("Revenue by region") {
                        RevenueChart(points: snap.revenueByRegion)
                        SeriesTable(points: snap.revenueByRegion, rowID: AccessibilityID.revenueRow) {
                            $0.formatted(.currency(code: "USD"))
                        }
                        HStack {
                            Text("Total").bold()
                            Text(snap.totalRevenue.formatted(.currency(code: "USD")))
                                .monospacedDigit()
                                .accessibilityIdentifier(AccessibilityID.totalRevenue)
                                .accessibilityValue(AXValue.number(snap.totalRevenue))
                        }
                    }
                    section("Orders by month") {
                        OrdersChart(points: snap.ordersByMonth)
                        SeriesTable(points: snap.ordersByMonth, rowID: AccessibilityID.ordersRow) {
                            Int($0).formatted()
                        }
                    }
                }
            }
            Spacer()
        }
        .padding(24)
    }

    private var header: some View {
        HStack(alignment: .center) {
            Text("TenantLens").font(.largeTitle).bold()
            Picker("Tenant", selection: Binding(get: { model.selectedTenant }, set: { model.select($0) })) {
                ForEach(model.tenants, id: \.self) { Text($0).tag($0) }
            }
            .pickerStyle(.segmented)
            .frame(maxWidth: 260)
            .accessibilityIdentifier(AccessibilityID.tenantPicker)
            Spacer()
            if let run = model.run { RunReportView(run: run) }
        }
    }

    private func section<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(title).font(.headline)
            content()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

struct RevenueChart: View {
    let points: [SeriesPoint]

    var body: some View {
        Chart(points) { p in
            BarMark(x: .value("Region", p.label), y: .value("Revenue", p.value))
                .accessibilityLabel(p.label)                     // what VoiceOver reads per bar
                .accessibilityValue(AXValue.number(p.value))
        }
        .frame(height: 220)
        .accessibilityIdentifier(AccessibilityID.revenueChart)
    }
}

struct OrdersChart: View {
    let points: [SeriesPoint]

    var body: some View {
        Chart(points) { p in
            LineMark(x: .value("Month", p.label), y: .value("Orders", p.value))
            PointMark(x: .value("Month", p.label), y: .value("Orders", p.value))
                .accessibilityLabel(p.label)
                .accessibilityValue(AXValue.number(p.value))
        }
        .chartXAxis {
            AxisMarks { value in
                AxisGridLine()
                AxisValueLabel {
                    // Data keeps "2026-03" (it is the reconciliation key); the axis shows "Mar".
                    if let label = value.as(String.self) { Text(Self.shortMonth(label)) }
                }
            }
        }
        .frame(height: 220)
        .accessibilityIdentifier(AccessibilityID.ordersChart)
    }

    static func shortMonth(_ label: String) -> String {
        guard let m = Int(label.suffix(2)), (1...12).contains(m) else { return label }
        return Calendar.current.shortMonthSymbols[m - 1]
    }
}

/// The dependable test surface: one row per series point, value tagged with a stable identifier
/// and a raw, locale-independent accessibility value.
struct SeriesTable: View {
    let points: [SeriesPoint]
    let rowID: (String) -> String
    let display: (Double) -> String

    var body: some View {
        Grid(alignment: .leading, horizontalSpacing: 16, verticalSpacing: 4) {
            ForEach(points) { p in
                GridRow {
                    Text(p.label).foregroundStyle(.secondary)
                    Text(display(p.value))
                        .monospacedDigit()
                        .accessibilityIdentifier(rowID(p.label))
                        .accessibilityValue(AXValue.number(p.value))
                }
            }
        }
    }
}

struct RunReportView: View {
    let run: RunSummary

    var body: some View {
        HStack(spacing: 16) {
            stat("Extracted", run.extracted, AccessibilityID.runExtracted)
            stat("Loaded", run.loaded, AccessibilityID.runLoaded)
            stat("Rejected", run.rejected, AccessibilityID.runRejected)
            Text("ins \(run.inserted) · upd \(run.updated) · same \(run.unchanged)")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private func stat(_ title: String, _ n: Int, _ id: String) -> some View {
        VStack(spacing: 2) {
            Text(title).font(.caption).foregroundStyle(.secondary)
            Text("\(n)")
                .font(.title3)
                .monospacedDigit()
                .accessibilityIdentifier(id)
                .accessibilityValue("\(n)")
        }
    }
}
