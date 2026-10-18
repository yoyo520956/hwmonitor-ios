import Darwin
import Foundation
import Network

/// 网络采集器：NWPathMonitor（连接类型）+ getifaddrs（接口/IP/流量差分）
public final class NetworkProvider: @unchecked Sendable, StreamableProvider {
    public let category: MetricCategory = .network

    private let monitor = NWPathMonitor()
    private let monitorLock = NSLock()
    private var _pathStatus: NWPath.Status = .unsatisfied
    private var _interfaceType: String = "未知"
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
                self._interfaceType = "蜂窝网络"
            } else if path.usesInterfaceType(.wiredEthernet) {
                self._interfaceType = "以太网"
            } else if path.status == .satisfied {
                self._interfaceType = "其他"
            } else {
                self._interfaceType = "离线"
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
            rx &+= UInt64(ifData.pointee.ifi_ibytes)
            tx &+= UInt64(ifData.pointee.ifi_obytes)
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

    /// 全接口明细（en0/awdl0/utun0/pdp_ip0… 名称+地址族）
    public func readInterfaceList() -> String? {
        var ifaddr: UnsafeMutablePointer<ifaddrs>? = nil
        guard getifaddrs(&ifaddr) == 0, let first = ifaddr else { return nil }
        defer { freeifaddrs(ifaddr) }

        var seen: [String] = []
        var names: [String] = []
        var ptr: UnsafeMutablePointer<ifaddrs>? = first
        while let current = ptr {
            defer { ptr = current.pointee.ifa_next }
            let rawName = String(cString: current.pointee.ifa_name)
            // 去掉 % 接口索引后缀
            let name = rawName.split(separator: "%").first.map(String.init) ?? rawName
            if seen.contains(name) { continue }
            seen.append(name)
            let family: String
            if let addr = current.pointee.ifa_addr {
                switch addr.pointee.sa_family {
                case UInt8(AF_INET): family = "IPv4"
                case UInt8(AF_INET6): family = "IPv6"
                default: family = ""
                }
            } else {
                family = ""
            }
            if family.isEmpty {
                names.append(name)
            } else {
                names.append("\(name)(\(family))")
            }
        }
        guard !names.isEmpty else { return nil }
        return names.joined(separator: "  ")
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
            id: "net.status", name: "连接", value: connected ? type : "离线",
            source: .appleAPI, method: "NWPathMonitor.pathUpdateHandler",
            status: connected ? .ok : .degraded, collectedAt: now, category: .network
        ))
        if connected {
            cards.append(MetricCard(
                id: "net.expensive", name: "计费网络（蜂窝/热点）",
                value: expensive ? "是（蜂窝/热点）" : "否",
                source: .appleAPI, method: "NWPath.isExpensive", status: .ok,
                collectedAt: now, category: .network
            ))
            cards.append(MetricCard(
                id: "net.constrained", name: "低数据模式",
                value: constrained ? "开" : "关",
                source: .appleAPI, method: "NWPath.isConstrained", status: .ok,
                collectedAt: now, category: .network
            ))
        }
        if let ip = readPrimaryIPv4() {
            cards.append(MetricCard(
                id: "net.ip", name: "本机 IPv4", value: ip,
                source: .appleAPI, method: "getifaddrs + getnameinfo(NI_NUMERICHOST)",
                limitation: "仅局域网地址，不含公网出口/VPN IP",
                status: .ok, collectedAt: now, category: .network
            ))
        }
        if let (rx, tx) = readInterfaceBytes() {
            cards.append(MetricCard(
                id: "net.rx", name: "累计接收", value: ByteFormat.gigabytes(Double(rx)),
                numeric: Double(rx), unit: "bytes",
                source: .computed, method: "Σ ifa_data.ifi_ibytes（非回环接口，开机起累计）",
                status: .ok, collectedAt: now, category: .network
            ))
            cards.append(MetricCard(
                id: "net.tx", name: "累计发送", value: ByteFormat.gigabytes(Double(tx)),
                numeric: Double(tx), unit: "bytes",
                source: .computed, method: "Σ ifa_data.ifi_obytes（非回环接口，开机起累计）",
                status: .ok, collectedAt: now, category: .network
            ))
        }

        if let ifList = readInterfaceList() {
            cards.append(MetricCard(
                id: "net.iflist", name: "网络接口明细", value: ifList,
                source: .appleAPI, method: "getifaddrs 遍历全部接口（名称与地址族）",
                limitation: "en0=Wi-Fi，pdp_ip0=蜂窝，awdl0=隔空投送链路，utun*=VPN 隧道",
                status: .ok, collectedAt: now, category: .network
            ))
        }

        return cards
    }
}
