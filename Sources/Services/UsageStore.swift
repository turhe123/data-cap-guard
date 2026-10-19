import Foundation

/// Codable record of daily byte subtotals plus per-period bookkeeping, persisted as JSON
/// in Application Support so totals survive relaunches and reboots.
struct UsageStore: Codable {
    /// Bytes per local day, keyed by "yyyy-MM-dd".
    var days: [String: UInt64] = [:]
    /// Bytes subtracted from the period identified by `resetPeriodKey` after "Reset Counter".
    var resetOffset: UInt64 = 0
    var resetPeriodKey: String = ""
    /// Warning thresholds already delivered during the period identified by `firedPeriodKey`.
    var firedThresholds: [Int] = []
    var firedPeriodKey: String = ""

    private static var fileURL: URL? {
        guard let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
        else { return nil }
        return base.appendingPathComponent("DataCapGuard", isDirectory: true)
            .appendingPathComponent("usage.json")
    }

    static func load() -> UsageStore {
        guard let url = fileURL, let data = try? Data(contentsOf: url),
              let store = try? JSONDecoder().decode(UsageStore.self, from: data)
        else { return UsageStore() }
        return store
    }

    func save() {
        guard let url = Self.fileURL else { return }
        do {
            try FileManager.default.createDirectory(at: url.deletingLastPathComponent(),
                                                    withIntermediateDirectories: true)
            let data = try JSONEncoder().encode(self)
            try data.write(to: url, options: .atomic)
        } catch {
            NSLog("DataCapGuard: failed to save usage store: \(error.localizedDescription)")
        }
    }

    mutating func add(_ bytes: UInt64, on date: Date) {
        guard bytes > 0 else { return }
        let key = DayKey.string(from: date)
        days[key, default: 0] &+= bytes
    }

    /// Raw bytes recorded inside `period`, before reset offset and manual adjustment.
    func rawTotal(in period: BillingPeriod) -> UInt64 {
        days.reduce(0) { sum, entry in
            guard let date = DayKey.date(from: entry.key), period.contains(date) else { return sum }
            return sum &+ entry.value
        }
    }

    /// Drops entries older than ~400 days to keep the file small.
    mutating func prune(now: Date = Date()) {
        guard let cutoff = Calendar.current.date(byAdding: .day, value: -400, to: now) else { return }
        days = days.filter { (DayKey.date(from: $0.key) ?? now) >= cutoff }
    }
}
