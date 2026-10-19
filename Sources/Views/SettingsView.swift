import SwiftUI
import ServiceManagement

/// The Settings window: allowance, reset day, interfaces, warnings, hotspot mode, appearance and login item.
struct SettingsView: View {
    @EnvironmentObject private var monitor: UsageMonitor
    @AppStorage(Keys.allowanceGB) private var allowanceGB = 0.0
    @AppStorage(Keys.resetDay) private var resetDay = 1
    @AppStorage(Keys.countedInterfaces) private var countedRaw = CountedInterfaces.all.rawValue
    @AppStorage(Keys.includeVirtual) private var includeVirtual = false
    @AppStorage(Keys.thresholds) private var thresholds = "75, 90, 100"
    @AppStorage(Keys.hotspotName) private var hotspotName = ""
    @AppStorage(Keys.hotspotInterface) private var hotspotInterface = ""
    @AppStorage(Keys.menuBarStyle) private var styleRaw = MenuBarStyle.both.rawValue
    @AppStorage(Keys.adjustmentGB) private var adjustmentGB = 0.0

    @State private var launchAtLogin = SMAppService.mainApp.status == .enabled
    @State private var loginError: String?
    @State private var interfaces: [NetworkInterfaceInfo] = []

    var body: some View {
        Form {
            Section("Plan") {
                TextField("Monthly allowance (GB)", value: $allowanceGB, format: .number)
                Stepper("Reset day: \(resetDay)", value: $resetDay, in: 1...31)
                TextField("Manual adjustment (GB)", value: $adjustmentGB, format: .number)
                Text("Add or subtract data so the total matches your provider's meter. Cleared by Reset Counter.")
                    .font(.caption).foregroundStyle(.secondary)
            }

            Section("Counting") {
                Picker("Counted interfaces", selection: $countedRaw) {
                    ForEach(CountedInterfaces.allCases) { Text($0.label).tag($0.rawValue) }
                }
                Toggle("Include virtual and VPN interfaces", isOn: $includeVirtual)
                    .disabled(countedRaw != CountedInterfaces.all.rawValue)
                Text("Off by default: VPN tunnels carry traffic that is already counted on Wi-Fi or Ethernet.")
                    .font(.caption).foregroundStyle(.secondary)
            }

            Section("Hotspot mode") {
                TextField("Hotspot network name", text: $hotspotName, prompt: Text("e.g. My iPhone"))
                Picker("Hotspot interface (fallback)", selection: $hotspotInterface) {
                    Text("None").tag("")
                    ForEach(interfaces) { Text("\($0.displayName) (\($0.bsdName))").tag($0.bsdName) }
                }
                Text("When a name is set, only traffic on that network counts. If macOS doesn't reveal the Wi-Fi name (it requires Location access), the selected interface is counted instead.")
                    .font(.caption).foregroundStyle(.secondary)
            }

            Section("Warnings") {
                TextField("Warning thresholds (%)", text: $thresholds, prompt: Text("75, 90, 100"))
                let parsed = SettingsParser.thresholds(thresholds)
                Text(parsed.isEmpty ? "No valid thresholds — warnings disabled."
                                    : "Notify at " + parsed.map { "\($0)%" }.joined(separator: ", "))
                    .font(.caption).foregroundStyle(parsed.isEmpty ? .red : .secondary)
                if monitor.notificationsDenied {
                    HStack {
                        Text("Notifications are turned off for DataCapGuard.").foregroundStyle(.orange)
                        Spacer()
                        Button("Open System Settings") {
                            if let url = URL(string: "x-apple.systempreferences:com.apple.Notifications-Settings.extension") {
                                NSWorkspace.shared.open(url)
                            }
                        }
                    }
                }
            }

            Section("General") {
                Picker("Menu bar style", selection: $styleRaw) {
                    ForEach(MenuBarStyle.allCases) { Text($0.label).tag($0.rawValue) }
                }
                Toggle("Launch at login", isOn: $launchAtLogin)
                    .onChange(of: launchAtLogin) { _, enabled in setLaunchAtLogin(enabled) }
                if let loginError {
                    Text(loginError).font(.caption).foregroundStyle(.red)
                }
            }

            Section {
                HStack {
                    Text("Usage measured on this Mac may differ from your provider's billing.")
                        .font(.caption).foregroundStyle(.secondary)
                    Spacer()
                    Button("Support / Donate ❤️") { Support.openDonation() }
                }
            }
        }
        .formStyle(.grouped)
        .frame(width: 480, height: 640)
        .onAppear {
            interfaces = InterfaceReader.knownInterfaces()
            monitor.refreshNotificationStatus()
        }
        .onChange(of: allowanceGB) { monitor.recompute() }
        .onChange(of: resetDay) { monitor.recompute() }
        .onChange(of: adjustmentGB) { monitor.recompute() }
        .onChange(of: thresholds) { monitor.recompute() }
    }

    private func setLaunchAtLogin(_ enabled: Bool) {
        do {
            if enabled {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
            loginError = nil
        } catch {
            loginError = "Couldn't update login item: \(error.localizedDescription)"
            launchAtLogin = SMAppService.mainApp.status == .enabled
        }
    }
}
