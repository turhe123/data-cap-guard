import Foundation
import SystemConfiguration
import CoreWLAN

/// Raw input/output byte counters for one interface at one instant.
struct InterfaceSample {
    let input: UInt64
    let output: UInt64
}

/// A network interface the user can recognise, as reported by SystemConfiguration.
struct NetworkInterfaceInfo: Identifiable, Hashable {
    let bsdName: String
    let displayName: String
    let isWiFi: Bool
    let isEthernet: Bool
    var id: String { bsdName }
}

/// Reads per-interface byte counters with `getifaddrs` and resolves friendly names.
enum InterfaceReader {
    /// Interface name prefixes that are virtual, tunnels or VPNs and would double count traffic.
    static let virtualPrefixes = ["lo", "utun", "ipsec", "ppp", "gif", "stf", "bridge", "awdl", "llw",
                                  "anpi", "ap", "vmenet", "feth", "tap", "tun"]

    static func isVirtual(_ name: String) -> Bool {
        virtualPrefixes.contains { name.hasPrefix($0) }
    }

    /// Current counters for every AF_LINK interface, keyed by BSD name.
    static func readCounters() -> [String: InterfaceSample] {
        var head: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&head) == 0, let first = head else { return [:] }
        defer { freeifaddrs(head) }

        var result: [String: InterfaceSample] = [:]
        for pointer in sequence(first: first, next: { $0.pointee.ifa_next }) {
            let entry = pointer.pointee
            guard let addr = entry.ifa_addr, addr.pointee.sa_family == UInt8(AF_LINK),
                  let raw = entry.ifa_data else { continue }
            let data = raw.assumingMemoryBound(to: if_data.self).pointee
            let name = String(cString: entry.ifa_name)
            result[name] = InterfaceSample(input: UInt64(data.ifi_ibytes), output: UInt64(data.ifi_obytes))
        }
        return result
    }

    /// Bytes transferred between two readings of a single 32-bit counter.
    /// A small backwards step is a counter wrap; anything else is a reset and becomes a new baseline.
    static func delta(old: UInt64, new: UInt64) -> UInt64 {
        if new >= old { return new - old }
        let wrapped = (UInt64(UInt32.max) + 1) - old + new
        let halfRange = UInt64(UInt32.max) / 2
        return (old > halfRange && wrapped < halfRange) ? wrapped : 0
    }

    /// Physical interfaces known to SystemConfiguration (Wi-Fi, Ethernet, iPhone USB, …).
    static func knownInterfaces() -> [NetworkInterfaceInfo] {
        guard let all = SCNetworkInterfaceCopyAll() as? [SCNetworkInterface] else { return [] }
        return all.compactMap { iface in
            guard let bsd = SCNetworkInterfaceGetBSDName(iface) as String?, !isVirtual(bsd) else { return nil }
            let type = SCNetworkInterfaceGetInterfaceType(iface) as String? ?? ""
            let name = SCNetworkInterfaceGetLocalizedDisplayName(iface) as String? ?? bsd
            return NetworkInterfaceInfo(bsdName: bsd, displayName: name,
                                        isWiFi: type == (kSCNetworkInterfaceTypeIEEE80211 as String),
                                        isEthernet: type == (kSCNetworkInterfaceTypeEthernet as String))
        }
        .sorted { $0.bsdName < $1.bsdName }
    }
}

/// Wraps CoreWLAN. The SSID may be nil without Location access, in which case
/// hotspot mode falls back to the interface the user picked manually.
enum WiFiInfo {
    static func current() -> (interface: String, ssid: String?)? {
        guard let iface = CWWiFiClient.shared().interface(), let name = iface.interfaceName else { return nil }
        return (name, iface.ssid())
    }
}
