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
                id: "sto.total", name: "存储", value: "—",
                source: .appleAPI, method: "URL.resourceValues(volumeTotalCapacity)",
                limitation: "卷资源信息不可用", status: .unavailable,
                collectedAt: now, category: .storage
            ))
            return cards
        }
        let used = total - available

        cards.append(MetricCard(
            id: "sto.total", name: "总容量", value: ByteFormat.gigabytes(total),
            numeric: total, unit: "bytes",
            source: .appleAPI, method: "URL.resourceValues(volumeTotalCapacity)",
            limitation: "文件系统口径，与营销容量略有差异",
            status: .ok, collectedAt: now, category: .storage
        ))
        cards.append(MetricCard(
            id: "sto.used", name: "已用", value: ByteFormat.gigabytes(used),
            numeric: used, unit: "bytes",
            source: .computed, method: "公式：total - available", status: .ok,
            collectedAt: now, category: .storage
        ))
        cards.append(MetricCard(
            id: "sto.free", name: "可用", value: ByteFormat.gigabytes(available),
            numeric: available, unit: "bytes",
            source: .appleAPI, method: "volumeAvailableCapacityForImportantUsage",
            status: .ok, collectedAt: now, category: .storage
        ))
        cards.append(MetricCard(
            id: "sto.pct", name: "使用率", value: PercentFormat.string(used / total),
            numeric: used / total, unit: "%",
            source: .computed, method: "公式：used / total", status: .ok,
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
                id: "bat.level", name: "电量", value: PercentFormat.string(Double(level), digits: 0),
                numeric: Double(level), unit: "%",
                source: .appleAPI, method: "UIDevice.batteryLevel（精度约 1-5%）",
                status: .ok, collectedAt: now, category: .battery
            ))
        } else {
            cards.append(MetricCard(
                id: "bat.level", name: "电量", value: "—",
                source: .appleAPI, method: "UIDevice.batteryLevel",
                limitation: "未上报电量（模拟器或硬件不可用）",
                status: .unavailable, collectedAt: now, category: .battery
            ))
        }

        let state = device.batteryState
        let stateText: String
        switch state {
        case .charging: stateText = "充电中"
        case .full: stateText = "完全"
        case .unplugged: stateText = "未充电"
        case .unknown: stateText = "未知"
        @unknown default: stateText = "未知"
        }
        cards.append(MetricCard(
            id: "bat.state", name: "充电状态", value: stateText,
            source: .appleAPI, method: "UIDevice.batteryState", status: .ok,
            collectedAt: now, category: .battery
        ))
        cards.append(MetricCard(
            id: "bat.lowpower", name: "低电量模式", value: ProcessInfo.processInfo.isLowPowerModeEnabled ? "开" : "关",
            source: .appleAPI, method: "ProcessInfo.isLowPowerModeEnabled", status: .ok,
            collectedAt: now, category: .battery
        ))

        // 系统未开放项（明确标注，不伪装）
        cards.append(.restricted(
            "bat.health", "电池健康度（最大容量）",
            reason: "iOS provides no public API for battery health. IOKit AppleSmartBattery is not accessible on iOS — only system apps can read it. Check Settings → Battery → Battery Health.",
            category: .battery
        ))
        cards.append(.restricted(
            "bat.cycle", "循环次数",
            reason: "任何公开 iOS API 均不提供此数据",
            category: .battery
        ))
        cards.append(.restricted(
            "bat.temp", "电池温度",
            reason: "无公开 API，仅有定性热状态（见温度模块）",
            category: .battery
        ))
        cards.append(.restricted(
            "bat.elec", "电压 / 电流",
            reason: "iOS 公开 API 未开放此数据",
            category: .battery
        ))

        // 热状态（系统公开的定性指标）
        let thermal = ProcessInfo.processInfo.thermalState
        let thermalText: String
        switch thermal {
        case .nominal: thermalText = "正常"
        case .fair: thermalText = "一般"
        case .serious: thermalText = "严重"
        case .critical: thermalText = "危急"
        @unknown default: thermalText = "未知"
        }
        cards.append(MetricCard(
            id: "thermal.state", name: "热状态", value: thermalText,
            source: .appleAPI, method: "ProcessInfo.thermalState",
            limitation: "系统仅提供 4 级定性状态，不开放具体温度数值",
            status: .ok, collectedAt: now, category: .thermal
        ))

        return cards
    }
}
