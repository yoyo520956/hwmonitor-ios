import Darwin
import Foundation
import Network

/// 网络采集器：NWPathMonitor（连接类型）+ getifaddrs（接口/IP/流量差分）
public final class NetworkProvider: @unchecked Sendable, StreamableProvider {
    public let category: MetricCategory = .network

    private let monitor = NWPathMonitor()
    private let monitorLock = NSLock()
    private var _pathStatus: NWPath.Status = .unsatisfied
    private var _interfaceType: String = "Unknown"
    private var _expensive: Bool = false
    private var _constrained: Bool = false

    private let dataLock = NSLock()
    private var lastBytes: (rx: UInt64, tx: UInt64) = (0, 0)
    private var lastTime: Date = Date()
    private var _rxSpeed: Double = 0
    private var _txSpeed: Double = 0
    private var _history: [SamplePoint] = []

    public var history: [SamplePoint] {
        get { dataLock.lock(); defer { dataLock.unlock() }; return _history }
    }

    public init() {
        startMonitor()
    }

    private func startMonitor() {
        monitor.pathUpdateHandler = { [weak self] path in
            guard let self else { return }
            self.monitorLock.lock()
            self._pathStatus = path.status
            self._expensive = path.isExpensive
            self._constrained = path.isConstrained
            if path.usesInterfaceType(.wifi) {
                self._interfaceType = "Wi-Fi"
            } else if path.usesInterfaceType(.cellular) {
                self._interfaceType = "Cellular"
            } else if path.usesInterfaceType(.wiredEthernet) {
                self._interfaceType = "Ethernet"
            } else if path.status == .satisfied {
                self._interfaceType = "Other"
            } else {
                self._interfaceType = "Offline"
            }
            self.monitorLock.unlock()
        }
        monitor.start(queue: DispatchQueue(label: "com.qingyao.hwmonitor.nwmonitor"))
    }

    public func resetHistory() {
        dataLock.lock(); _history.removeAll(); dataLock.unlock()
    }

    public func tick() {
        // 流量差分 → 速率
        guard let (rx, tx) = readInterfaceBytes() else { return }
        dataLock.lock()
        let now = Date()
        let dt = now.timeIntervalSince(lastTime)
        if dt > 0.1, lastBytes.rx > 0 || lastBytes.tx > 0 {
            _rxSpeed = Double(rx &- lastBytes.rx) / dt
            _txSpeed = Double(tx &- lastBytes.tx) / dt
            _history.append(SamplePoint(timestamp: now, value: _rxSpeed + _txSpeed))
            if _history.count > 180 { _history.removeFirst(_history.count - 180) }
        }
        lastBytes = (rx, tx)
        lastTime = now
        dataLock.unlock()
    }

    /// 全接口字节统计（getifaddrs → if_data）
    public func readInterfaceBytes() -> (rx: UInt64, tx: UInt64)? {
        var ifaddr: UnsafeMutablePointer<ifaddrs>? = nil
        guard getifaddrs(&ifaddr) == 0, let first = ifaddr else { return nil }
        defer { freeifaddrs(ifaddr) }

        var rx: UInt64 = 0, tx: UInt64 = 0
        var ptr: UnsafeMutablePointer<ifaddrs>? = first
        while let current = ptr {
            defer { ptr = current.pointee.ifa_next }
            guard let addr = current.pointee.ifa_addr, addr.pointee.sa_family == UInt8(AF_LINK),
                  let data = current.pointee.ifa_data
            else { continue }
            let name = String(cString: current.pointee.ifa_name)
            // 排除 lo0 回环
            guard !name.hasPrefix("lo") else { continue }
            let ifData = data.assumingMemoryBound(to: if_data.self)
            rx &+= ifData.ifi_ibytes
            tx &+= ifData.ifi_obytes
        }
        return (rx, tx)
    }

    /// 获取主接口 IPv4 地址
    public func readPrimaryIPv4() -> String? {
        var ifaddr: UnsafeMutablePointer<ifaddrs>? = nil
        guard getifaddrs(&ifaddr) == 0, let first = ifaddr else { return nil }
        defer { freeifaddrs(ifaddr) }

        var ptr: UnsafeMutablePointer<ifaddrs>? = first
        while let current = ptr {
            defer { ptr = current.pointee.ifa_next }
            guard let addr = current.pointee.ifa_addr, addr.pointee.sa_family == UInt8(AF_INET) else { continue }
            let name = String(cString: current.pointee.ifa_name)
            guard !name.hasPrefix("lo") else { continue }
            var host = [CChar](repeating: 0, count: Int(NI_MAXHOST))
            let result = getnameinfo(
                addr, socklen_t(addr.pointee.sa_len), &host, socklen_t(host.count),
                nil, 0, NI_NUMERICHOST
            )
            if result == 0 {
                let ip = String(cString: host)
                if let ip = ip.split(separator: "%").first { return String(ip) }
                return ip
            }
        }
        return nil
    }

    public func collect() -> [MetricCard] {
        var cards: [MetricCard] = []
        let now = Date()
        monitorLock.lock()
        let status = _pathStatus
        let type = _interfaceType
        let expensive = _expensive
        let constrained = _constrained
        monitorLock.unlock()

        let connected = status == .satisfied
        cards.append(MetricCard(
            id: "net.status", name: "Connection", value: connected ? type : "Offline",
            source: .appleAPI, method: "NWPathMonitor.pathUpdateHandler",
            status: connected ? .ok : .degraded, collectedAt: now, category: .network
        ))
        if connected {
            cards.append(MetricCard(
                id: "net.expensive", name: "Expensive Link",
                value: expensive ? "Yes (cellular / hotspot)" : "No",
                source: .appleAPI, method: "NWPath.isExpensive", status: .ok,
                collectedAt: now, category: .network
            ))
            cards.append(MetricCard(
                id: "net.constrained", name: "Low Data Mode",
                value: constrained ? "On" : "Off",
                source: .appleAPI, method: "NWPath.isConstrained", status: .ok,
                collectedAt: now, category: .network
            ))
        }
        if let ip = readPrimaryIPv4() {
            cards.append(MetricCard(
                id: "net.ip", name: "Local IPv4", value: ip,
                source: .appleAPI, method: "getifaddrs + getnameinfo(NI_NUMERICHOST)",
                limitation: "Local network address only; not the public/VPN exit IP",
                status: .ok, collectedAt: now, category: .network
            ))
        }
        if let (rx, tx) = readInterfaceBytes() {
            cards.append(MetricCard(
                id: "net.rx", name: "Total Received", value: ByteFormat.gigabytes(Double(rx)),
                numeric: Double(rx), unit: "bytes",
                source: .computed, method: "Σ ifa_data.ifi_ibytes across non-loopback interfaces (since boot)",
                status: .ok, collectedAt: now, category: .network
            ))
            cards.append(MetricCard(
                id: "net.tx", name: "Total Sent", value: ByteFormat.gigabytes(Double(tx)),
                numeric: Double(tx), unit: "bytes",
                source: .computed, method: "Σ ifa_data.ifi_obytes across non-loopback interfaces (since boot)",
                status: .ok, collectedAt: now, category: .network
            ))
        }

        return cards
    }
}
