import Foundation

/// UserDefaults keys shared by `@AppStorage` views and the background monitor.
enum Keys {
    static let allowanceGB = "allowanceGB"
    static let resetDay = "resetDay"
    static let countedInterfaces = "countedInterfaces"
    static let includeVirtual = "includeVirtual"
    static let thresholds = "thresholds"
    static let hotspotName = "hotspotName"
    static let hotspotInterface = "hotspotInterface"
    static let menuBarStyle = "menuBarStyle"
    static let adjustmentGB = "adjustmentGB"
}

/// Which physical interfaces contribute to the running total.
enum CountedInterfaces: String, CaseIterable, Identifiable {
    case all, wifi, ethernet
    var id: String { rawValue }
    var label: String {
        switch self {
        case .all: return "All physical interfaces"
        case .wifi: return "Wi-Fi only"
        case .ethernet: return "Ethernet only"
        }
    }
}

/// How usage is drawn in the menu bar.
enum MenuBarStyle: String, CaseIterable, Identifiable {
    case ring, text, both
    var id: String { rawValue }
    var label: String {
        switch self {
        case .ring: return "Ring"
        case .text: return "Percentage"
        case .both: return "Ring + percentage"
        }
    }
}

/// Helpers for parsing user-entered settings safely.
enum SettingsParser {
    /// Parses "75, 90, 100" into sorted unique integer percentages in 1...200.
    static func thresholds(_ raw: String) -> [Int] {
        let values = raw.split(whereSeparator: { $0 == "," || $0 == " " })
            .compactMap { Int($0.trimmingCharacters(in: .whitespaces)) }
            .filter { (1...200).contains($0) }
        return Array(Set(values)).sorted()
    }
}

/// A billing period bounded by the user's reset day; `end` is exclusive.
struct BillingPeriod: Equatable {
    let start: Date
    let end: Date

    var key: String { DayKey.string(from: start) }

    /// The period containing `now`. Reset days beyond a month's length clamp to its last day.
    static func current(resetDay: Int, now: Date = Date(), calendar: Calendar = .current) -> BillingPeriod {
        let day = min(max(resetDay, 1), 31)
        func anchor(monthOffset: Int) -> Date {
            let comps = calendar.dateComponents([.year, .month], from: now)
            guard let first = calendar.date(from: comps),
                  let month = calendar.date(byAdding: .month, value: monthOffset, to: first),
                  let range = calendar.range(of: .day, in: .month, for: month),
                  let date = calendar.date(byAdding: .day, value: min(day, range.count) - 1, to: month)
            else { return calendar.startOfDay(for: now) }
            return date
        }
        let thisMonth = anchor(monthOffset: 0)
        if thisMonth <= now {
            return BillingPeriod(start: thisMonth, end: anchor(monthOffset: 1))
        }
        return BillingPeriod(start: anchor(monthOffset: -1), end: thisMonth)
    }

    func contains(_ date: Date) -> Bool { date >= start && date < end }
}

/// Converts dates to the stable "yyyy-MM-dd" keys used in the JSON store.
enum DayKey {
    private static let formatter: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.calendar = Calendar(identifier: .gregorian)
        f.timeZone = .current
        f.dateFormat = "yyyy-MM-dd"
        return f
    }()

    static func string(from date: Date) -> String { formatter.string(from: date) }
    static func date(from key: String) -> Date? { formatter.date(from: key) }
}
