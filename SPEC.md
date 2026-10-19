# DataCapGuard — specification

**Tagline:** Track monthly internet usage against your data cap with a menu bar gauge and warnings before you run out.

**Category:** System Monitoring

**Inspired by (paid):** PeakHour 4 ($9.99 one-time)

**Frameworks:** SwiftUI, AppKit, SystemConfiguration, UserNotifications, ServiceManagement

**Donation URL (Support button):** https://ko-fi.com/leodavidai

## Spec

(1) What the paid app does and demand. PeakHour 4 is a network monitor sold at about 9.99 dollars one time that tracks bandwidth and total data usage, including a mode for users on capped or limited monthly allowances. Macworld reviewed it as a Mac Gem, and newer PeakHour versions continue to sell. Users on mobile hotspots and capped home plans want a simple gauge. Our clean-room version focuses only on cap tracking and leaves out Wi-Fi analysis.

(2) Feature set. The user sets a monthly allowance in gigabytes, a billing reset day, and which interfaces count, for example Wi-Fi only, Ethernet or all. The app samples the byte counters of the chosen interfaces every few seconds, adds the delta to the running total and stores daily subtotals so the total survives reboots. It shows used and remaining data, percent of the cap, the daily average, a projection of the month end total and a list of the last 30 days as a bar chart. Warnings fire at configurable thresholds such as 75, 90 and 100 percent. A Hotspot mode counts only the interface of a chosen network name, such as an iPhone hotspot, so home usage does not mix in.

(3) UI spec. A MenuBarExtra shows a ring or a text such as 62 percent with a color that goes amber and red as usage grows. The popover contains the gauge, numbers for used, left and projected, the 30 day bar chart built with Swift Charts, and buttons Reset Counter, Open Settings and Quit. Settings fields are Monthly allowance, Reset day, Counted interfaces, Warning thresholds, Hotspot network name, Menu bar style, and Launch at login. Empty state before setup shows a short wizard with the allowance field. Notifications use a clear title and body, for example 90 percent of your monthly data has been used.

(4) Technical approach. Read interface byte counters with getifaddrs, where AF_LINK entries expose if_data with input and output byte counts, and detect counter wrap around or resets by comparing against the previous sample. Interface names are mapped to friendly names with SCNetworkInterfaceCopyAll from SystemConfiguration. The current Wi-Fi network name for hotspot mode comes from CoreWLAN if available, otherwise the user picks an interface manually, which avoids a location prompt. Daily totals are stored as a Codable JSON in Application Support. A timer samples every five seconds, and a wake observer from NSWorkspace takes a sample after sleep. Notifications use UserNotifications with a permission request on first launch. Launch at login uses SMAppService. Swift Charts is part of the system SDK, so no packages are needed.

(5) Edge cases and error handling. Counters that go backwards after a reboot or interface reset are treated as a new baseline rather than negative traffic. Time spent asleep is not counted because counters do not change. Changing the reset day recomputes the current period from stored daily data. If the user turns off notifications in System Settings, the popover shows a small banner. Usage measured by the Mac can differ from provider billing, so the readme states this and Settings includes a manual adjustment field. Virtual and VPN interfaces are excluded by default to avoid double counting.
