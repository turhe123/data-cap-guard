import SwiftUI
import Charts

/// Formats byte counts in decimal units, matching how carriers bill.
func formatBytes(_ value: Double) -> String {
    ByteCountFormatter.string(fromByteCount: Int64(max(value, 0)), countStyle: .decimal)
}

/// The MenuBarExtra popover: setup wizard, gauge, key numbers, 30-day chart and actions.
struct ContentView: View {
    @EnvironmentObject private var monitor: UsageMonitor
    @Environment(\.openSettings) private var openSettings
    @AppStorage(Keys.allowanceGB) private var allowanceGB = 0.0
    @State private var confirmReset = false

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            if allowanceGB > 0 {
                dashboard
            } else {
                SetupWizard()
            }
            Divider()
            actions
        }
        .padding(16)
        .frame(width: 340)
        .onAppear {
            monitor.refreshNotificationStatus()
            monitor.recompute()
        }
    }

    private var dashboard: some View {
        VStack(alignment: .leading, spacing: 14) {
            if monitor.notificationsDenied {
                Banner(text: "Notifications are off, so you won't get cap warnings.",
                       action: "Open Settings") {
                    if let url = URL(string: "x-apple.systempreferences:com.apple.Notifications-Settings.extension") {
                        NSWorkspace.shared.open(url)
                    }
                }
            }
            if let notice = monitor.hotspotNotice {
                Banner(text: notice, action: nil, perform: {})
            }
            HStack(spacing: 16) {
                Gauge(value: min(monitor.fraction, 1)) {
                    EmptyView()
                } currentValueLabel: {
                    Text("\(Int((monitor.fraction * 100).rounded()))%")
                        .font(.system(.title3, design: .rounded).weight(.semibold))
                }
                .gaugeStyle(.accessoryCircularCapacity)
                .tint(Color(nsColor: MenuBarIcon.color(for: monitor.fraction)))
                .scaleEffect(1.3)
                .frame(width: 72, height: 72)

                VStack(alignment: .leading, spacing: 4) {
                    stat("Used", formatBytes(Double(monitor.usedBytes)))
                    stat("Left", formatBytes(monitor.remainingBytes))
                    stat("Projected", formatBytes(monitor.projectedBytes),
                         warn: monitor.projectedBytes > monitor.allowanceBytes)
                    stat("Daily avg", formatBytes(monitor.dailyAverage))
                }
            }
            Text("Period \(monitor.period.start.formatted(date: .abbreviated, time: .omitted)) – "
                 + "\(monitor.period.end.addingTimeInterval(-1).formatted(date: .abbreviated, time: .omitted)) · "
                 + "cap \(formatBytes(monitor.allowanceBytes))")
                .font(.caption)
                .foregroundStyle(.secondary)

            Text("Last 30 days").font(.headline)
            Chart(monitor.lastThirtyDays) { day in
                BarMark(x: .value("Day", day.date, unit: .day),
                        y: .value("GB", Double(day.bytes) / UsageMonitor.gigabyte))
                    .foregroundStyle(monitor.period.contains(day.date) ? Color.accentColor : Color.secondary.opacity(0.5))
            }
            .chartYAxisLabel("GB")
            .chartXAxis {
                AxisMarks(values: .stride(by: .day, count: 7)) { _ in
                    AxisGridLine()
                    AxisValueLabel(format: .dateTime.day().month(.abbreviated))
                }
            }
            .frame(height: 120)
        }
    }

    private func stat(_ title: String, _ value: String, warn: Bool = false) -> some View {
        HStack {
            Text(title).foregroundStyle(.secondary)
            Spacer()
            Text(value).monospacedDigit().foregroundStyle(warn ? Color.red : Color.primary)
        }
        .font(.callout)
    }

    private var actions: some View {
        VStack(spacing: 8) {
            HStack {
                Button("Reset Counter") { confirmReset = true }
                    .disabled(allowanceGB <= 0)
                Button("Open Settings") {
                    NSApp.activate(ignoringOtherApps: true)
                    openSettings()
                }
                Spacer()
                Button("Quit") { NSApp.terminate(nil) }
            }
            Button("Support / Donate ❤️") { Support.openDonation() }
                .buttonStyle(.link)
                .frame(maxWidth: .infinity, alignment: .center)
        }
        .confirmationDialog("Reset this period's counter to zero?", isPresented: $confirmReset) {
            Button("Reset Counter", role: .destructive) { monitor.resetCounter() }
        } message: {
            Text("Daily history stays in the chart; only the current period total starts over.")
        }
    }
}

/// A compact warning strip shown at the top of the popover.
struct Banner: View {
    let text: String
    let action: String?
    let perform: () -> Void

    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.orange)
            Text(text).font(.caption).fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 4)
            if let action { Button(action, action: perform).controlSize(.small) }
        }
        .padding(8)
        .background(Color.orange.opacity(0.12), in: RoundedRectangle(cornerRadius: 8))
    }
}

/// First-run setup: asks only for the monthly allowance (and reset day).
struct SetupWizard: View {
    @EnvironmentObject private var monitor: UsageMonitor
    @AppStorage(Keys.allowanceGB) private var allowanceGB = 0.0
    @AppStorage(Keys.resetDay) private var resetDay = 1
    @State private var draft: Double?

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label("Welcome to DataCapGuard", systemImage: "gauge.with.dots.needle.67percent")
                .font(.headline)
            Text("Enter your monthly data allowance to start tracking. You can fine-tune interfaces, warnings and hotspot mode in Settings.")
                .font(.callout)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            HStack {
                TextField("Monthly allowance", value: $draft, format: .number)
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 120)
                    .onSubmit(save)
                Text("GB")
            }
            Stepper("Billing resets on day \(resetDay)", value: $resetDay, in: 1...31)
            Button("Start Tracking", action: save)
                .buttonStyle(.borderedProminent)
                .disabled((draft ?? 0) <= 0)
        }
    }

    private func save() {
        guard let value = draft, value > 0 else { return }
        allowanceGB = value
        monitor.recompute()
    }
}
