import Foundation
import UIKit

/// 存储采集器：URL resourceValues（SystemInfoKit 验证过的做法，口径与系统设置一致）
public final class StorageProvider: @unchecked Sendable, StreamableProvider {
    public let category: MetricCategory = .storage

    private let lock = NSLock()
    private var _history: [SamplePoint] = []
    public var history: [SamplePoint] {
        get { lock.lock(); defer { lock.unlock() }; return _history }
    }

    public init() {}

    public func resetHistory() { lock.lock(); _history.removeAll(); lock.unlock() }

    public func tick() {
        guard let (total, available) = readVolumes() else { return }
        lock.lock()
        _history.append(SamplePoint(value: (total - available) / total))
        if _history.count > 180 { _history.removeFirst(_history.count - 180) }
        lock.unlock()
    }

    /// 返回 (total, available) 字节数；iOS 11+ 的 importantUsage 口径更接近系统设置
    public func readVolumes() -> (total: Double, available: Double)? {
        let url = URL(filePath: "/")
        let keys: Set<URLResourceKey> = [
            .volumeTotalCapacityKey,
            .volumeAvailableCapacityForImportantUsageKey,
        ]
        guard let values = try? url.resourceValues(forKeys: keys),
              let total = values.volumeTotalCapacity,
              let available = values.volumeAvailableCapacityForImportantUsage
        else { return nil }
        return (Double(total), Double(available))
    }

    public func collect() -> [MetricCard] {
        var cards: [MetricCard] = []
        let now = Date()
        guard let (total, available) = readVolumes() else {
            cards.append(MetricCard(
                id: "sto.total", name: "Storage", value: "—",
                source: .appleAPI, method: "URL.resourceValues(volumeTotalCapacity)",
                limitation: "Volume resource values unavailable", status: .unavailable,
                collectedAt: now, category: .storage
            ))
            return cards
        }
        let used = total - available

        cards.append(MetricCard(
            id: "sto.total", name: "Total Capacity", value: ByteFormat.gigabytes(total),
            numeric: total, unit: "bytes",
            source: .appleAPI, method: "URL.resourceValues(volumeTotalCapacity)",
            limitation: "Filesystem capacity; differs slightly from marketing storage size",
            status: .ok, collectedAt: now, category: .storage
        ))
        cards.append(MetricCard(
            id: "sto.used", name: "Used", value: ByteFormat.gigabytes(used),
            numeric: used, unit: "bytes",
            source: .computed, method: "total - available", status: .ok,
            collectedAt: now, category: .storage
        ))
        cards.append(MetricCard(
            id: "sto.free", name: "Available", value: ByteFormat.gigabytes(available),
            numeric: available, unit: "bytes",
            source: .appleAPI, method: "volumeAvailableCapacityForImportantUsage",
            status: .ok, collectedAt: now, category: .storage
        ))
        cards.append(MetricCard(
            id: "sto.pct", name: "Usage Ratio", value: PercentFormat.string(used / total),
            numeric: used / total, unit: "%",
            source: .computed, method: "used / total", status: .ok,
            collectedAt: now, category: .storage
        ))
        return cards
    }
}

/// 电池与热状态采集器
/// iOS 公开 API 只有 UIDevice.batteryLevel/batteryState + ProcessInfo.thermalState
/// 健康度/循环次数/温度/电压/电流：无公开 API（IOKit 在 iOS 不可用）→ 系统限制标注
public final class BatteryProvider: @unchecked Sendable {
    public let category: MetricCategory = .battery

    public init() {}

    public func collect() -> [MetricCard] {
        var cards: [MetricCard] = []
        let now = Date()
        let device = UIDevice.current
        device.isBatteryMonitoringEnabled = true

        // 电量：UIDevice.batteryLevel 0.0-1.0，未知时 -1
        let level = device.batteryLevel
        if level >= 0 {
            cards.append(MetricCard(
                id: "bat.level", name: "Battery Level", value: PercentFormat.string(Double(level), digits: 0),
                numeric: Double(level), unit: "%",
                source: .appleAPI, method: "UIDevice.batteryLevel (granularity ≈ 1-5%)",
                status: .ok, collectedAt: now, category: .battery
            ))
        } else {
            cards.append(MetricCard(
                id: "bat.level", name: "Battery Level", value: "—",
                source: .appleAPI, method: "UIDevice.batteryLevel",
                limitation: "Battery level not reported (simulator or hardware off)",
                status: .unavailable, collectedAt: now, category: .battery
            ))
        }

        let state = device.batteryState
        let stateText: String
        switch state {
        case .charging: stateText = "Charging"
        case .full: stateText = "Full"
        case .unplugged: stateText = "Unplugged"
        case .unknown: stateText = "Unknown"
        @unknown default: stateText = "Unknown"
        }
        cards.append(MetricCard(
            id: "bat.state", name: "Charging State", value: stateText,
            source: .appleAPI, method: "UIDevice.batteryState", status: .ok,
            collectedAt: now, category: .battery
        ))
        cards.append(MetricCard(
            id: "bat.lowpower", name: "Low Power Mode", value: ProcessInfo.processInfo.isLowPowerModeEnabled ? "On" : "Off",
            source: .appleAPI, method: "ProcessInfo.isLowPowerModeEnabled", status: .ok,
            collectedAt: now, category: .battery
        ))

        // 系统未开放项（明确标注，不伪装）
        cards.append(.restricted(
            "bat.health", "Battery Health (Maximum Capacity)",
            reason: "iOS provides no public API for battery health. IOKit AppleSmartBattery is not accessible on iOS — only system apps can read it. Check Settings → Battery → Battery Health.",
            category: .battery
        ))
        cards.append(.restricted(
            "bat.cycle", "Cycle Count",
            reason: "Not exposed by any public iOS API.",
            category: .battery
        ))
        cards.append(.restricted(
            "bat.temp", "Battery Temperature",
            reason: "No public API. Only qualitative thermal state (see Thermal module).",
            category: .battery
        ))
        cards.append(.restricted(
            "bat.elec", "Voltage / Current",
            reason: "Not exposed by public APIs on iOS.",
            category: .battery
        ))

        // 热状态（系统公开的定性指标）
        let thermal = ProcessInfo.processInfo.thermalState
        let thermalText: String
        switch thermal {
        case .nominal: thermalText = "Nominal"
        case .fair: thermalText = "Fair"
        case .serious: thermalText = "Serious"
        case .critical: thermalText = "Critical"
        @unknown default: thermalText = "Unknown"
        }
        cards.append(MetricCard(
            id: "thermal.state", name: "Thermal State", value: thermalText,
            source: .appleAPI, method: "ProcessInfo.thermalState",
            limitation: "Qualitative 4-level system state only; numeric °C values are not exposed",
            status: .ok, collectedAt: now, category: .thermal
        ))

        return cards
    }
}
