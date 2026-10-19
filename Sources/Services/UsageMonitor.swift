import AppKit
import Foundation
import UserNotifications

/// One day's usage, for the 30-day chart.
struct DayUsage: Identifiable {
    let date: Date
    let bytes: UInt64
    var id: Date { date }
}

/// Samples interface counters every five seconds (and after wake), accumulates deltas into
/// the persisted store, derives period statistics and fires threshold notifications.
@MainActor
final class UsageMonitor: ObservableObject {
    static let gigabyte: Double = 1_000_000_000

    @Published private(set) var usedBytes: UInt64 = 0
    @Published private(set) var lastThirtyDays: [DayUsage] = []
    @Published private(set) var period = BillingPeriod.current(resetDay: 1)
    @Published private(set) var notificationsDenied = false
    @Published private(set) var hotspotNotice: String?

    private var store = UsageStore.load()
    private var previous: [String: InterfaceSample] = [:]
    private var timer: Timer?
    private var wakeObserver: NSObjectProtocol?
    private var unsavedSamples = 0
    private let defaults = UserDefaults.standard

    init() {
        defaults.register(defaults: [
            Keys.allowanceGB: 0.0, Keys.resetDay: 1, Keys.countedInterfaces: CountedInterfaces.all.rawValue,
            Keys.includeVirtual: false, Keys.thresholds: "75, 90, 100", Keys.hotspotName: "",
            Keys.hotspotInterface: "", Keys.menuBarStyle: MenuBarStyle.both.rawValue, Keys.adjustmentGB: 0.0,
        ])
        store.prune()
        previous = InterfaceReader.readCounters()
        recompute()
        timer = Timer.scheduledTimer(withTimeInterval: 5, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.sample() }
        }
        timer?.tolerance = 1
        wakeObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didWakeNotification, object: nil, queue: .main
        ) { [weak self] _ in
            Task { @MainActor in self?.sample() }
        }
        NotificationCenter.default.addObserver(
            forName: NSApplication.willTerminateNotification, object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.store.save() }
        }
        requestNotificationPermission()
    }

    // MARK: Derived values

    var allowanceBytes: Double { max(defaults.double(forKey: Keys.allowanceGB), 0) * Self.gigabyte }
    var isConfigured: Bool { allowanceBytes > 0 }
    var fraction: Double { isConfigured ? Double(usedBytes) / allowanceBytes : 0 }
    var remainingBytes: Double { max(allowanceBytes - Double(usedBytes), 0) }

    private var elapsedDays: Double {
        max(Date().timeIntervalSince(period.start) / 86_400, 1)
    }

    var dailyAverage: Double { Double(usedBytes) / elapsedDays }

    var projectedBytes: Double {
        let total = period.end.timeIntervalSince(period.start) / 86_400
        return dailyAverage * max(total, 1)
    }

    // MARK: Sampling

    /// Takes a reading, adds the counted deltas to today and refreshes statistics.
    func sample() {
        let now = Date()
        let current = InterfaceReader.readCounters()
        let counted = countedInterfaceNames(available: Array(current.keys))
        var added: UInt64 = 0
        for (name, reading) in current {
            guard let old = previous[name], counted.contains(name) else { continue }
            added &+= InterfaceReader.delta(old: old.input, new: reading.input)
            added &+= InterfaceReader.delta(old: old.output, new: reading.output)
        }
        previous = current
        if added > 0 {
            store.add(added, on: now)
            unsavedSamples += 1
            if unsavedSamples >= 6 { store.save(); unsavedSamples = 0 }
        }
        recompute(now: now)
    }

    /// Chooses the interfaces whose traffic counts, honouring hotspot mode first.
    private func countedInterfaceNames(available: [String]) -> Set<String> {
        let hotspot = (defaults.string(forKey: Keys.hotspotName) ?? "").trimmingCharacters(in: .whitespaces)
        if !hotspot.isEmpty {
            if let wifi = WiFiInfo.current(), let ssid = wifi.ssid {
                hotspotNotice = ssid == hotspot ? nil : "Hotspot mode: not connected to “\(hotspot)” — not counting."
                return ssid == hotspot ? [wifi.interface] : []
            }
            let manual = defaults.string(forKey: Keys.hotspotInterface) ?? ""
            hotspotNotice = manual.isEmpty
                ? "Hotspot mode: network name unavailable. Pick a hotspot interface in Settings." : nil
            return manual.isEmpty ? [] : [manual]
        }
        hotspotNotice = nil

        let mode = CountedInterfaces(rawValue: defaults.string(forKey: Keys.countedInterfaces) ?? "") ?? .all
        let known = InterfaceReader.knownInterfaces()
        switch mode {
        case .wifi: return Set(known.filter(\.isWiFi).map(\.bsdName))
        case .ethernet: return Set(known.filter(\.isEthernet).map(\.bsdName))
        case .all:
            if defaults.bool(forKey: Keys.includeVirtual) {
                return Set(available.filter { !$0.hasPrefix("lo") })
            }
            return Set(known.map(\.bsdName))
        }
    }

    /// Recomputes the period (e.g. after the reset day changes), totals and chart data.
    func recompute(now: Date = Date()) {
        period = BillingPeriod.current(resetDay: defaults.integer(forKey: Keys.resetDay), now: now)
        var raw = store.rawTotal(in: period)
        if store.resetPeriodKey == period.key { raw = raw > store.resetOffset ? raw - store.resetOffset : 0 }
        let adjusted = Double(raw) + defaults.double(forKey: Keys.adjustmentGB) * Self.gigabyte
        usedBytes = UInt64(max(adjusted, 0))

        let calendar = Calendar.current
        let today = calendar.startOfDay(for: now)
        lastThirtyDays = (0..<30).reversed().compactMap { offset in
            guard let day = calendar.date(byAdding: .day, value: -offset, to: today) else { return nil }
            return DayUsage(date: day, bytes: store.days[DayKey.string(from: day)] ?? 0)
        }
        checkThresholds()
    }

    /// Zeroes the current period's counter while keeping daily history for the chart.
    func resetCounter() {
        store.resetPeriodKey = period.key
        store.resetOffset = store.rawTotal(in: period)
        store.firedThresholds = []
        defaults.set(0.0, forKey: Keys.adjustmentGB)
        store.save()
        recompute()
    }

    // MARK: Notifications

    private func checkThresholds() {
        guard isConfigured else { return }
        if store.firedPeriodKey != period.key {
            store.firedPeriodKey = period.key
            store.firedThresholds = []
        }
        let percent = fraction * 100
        let thresholds = SettingsParser.thresholds(defaults.string(forKey: Keys.thresholds) ?? "")
        let due = thresholds.filter { Double($0) <= percent && !store.firedThresholds.contains($0) }
        guard let highest = due.max() else { return }
        store.firedThresholds.append(contentsOf: due)
        store.save()
        notify(percent: highest)
    }

    private func notify(percent: Int) {
        let content = UNMutableNotificationContent()
        content.title = percent >= 100 ? "Data cap reached" : "Data usage warning"
        let left = ByteCountFormatter.string(fromByteCount: Int64(remainingBytes), countStyle: .decimal)
        content.body = percent >= 100
            ? "You have used \(percent)% of your monthly data allowance."
            : "\(percent)% of your monthly data has been used. \(left) left this period."
        content.sound = .default
        let request = UNNotificationRequest(identifier: "threshold-\(period.key)-\(percent)",
                                            content: content, trigger: nil)
        UNUserNotificationCenter.current().add(request) { error in
            if let error { NSLog("DataCapGuard: notification failed: \(error.localizedDescription)") }
        }
    }

    private func requestNotificationPermission() {
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { _, _ in
            Task { @MainActor in self.refreshNotificationStatus() }
        }
    }

    /// Updates the "notifications are off" banner state.
    func refreshNotificationStatus() {
        UNUserNotificationCenter.current().getNotificationSettings { settings in
            let denied = settings.authorizationStatus == .denied
            Task { @MainActor in self.notificationsDenied = denied }
        }
    }
}
