import SwiftUI

/// Entry point: a menu-bar-only app with a gauge popover and a Settings window.
@main
struct DataCapGuardApp: App {
    @StateObject private var monitor = UsageMonitor()
    @AppStorage(Keys.menuBarStyle) private var styleRaw = MenuBarStyle.both.rawValue
    @AppStorage(Keys.allowanceGB) private var allowanceGB = 0.0

    var body: some Scene {
        MenuBarExtra {
            ContentView()
                .environmentObject(monitor)
        } label: {
            Image(nsImage: MenuBarIcon.image(fraction: monitor.fraction,
                                             style: MenuBarStyle(rawValue: styleRaw) ?? .both,
                                             configured: allowanceGB > 0))
                .accessibilityLabel("Data used: \(Int(monitor.fraction * 100)) percent")
        }
        .menuBarExtraStyle(.window)

        Settings {
            SettingsView()
                .environmentObject(monitor)
        }
    }
}

/// Opens the project's donation page.
enum Support {
    static func openDonation() {
        NSWorkspace.shared.open(URL(string: "https://ko-fi.com/leodavidai")!)
    }
}
