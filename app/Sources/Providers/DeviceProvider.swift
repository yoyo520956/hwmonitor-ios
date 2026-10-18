import Foundation
import UIKit

/// 设备信息采集器：型号标识符 + 市场名映射 + 系统/内核信息
public final class DeviceProvider: @unchecked Sendable {
    public let category: MetricCategory = .hardware

    public init() {}

    // MARK: - 型号映射表（自建精简版，覆盖 iPhone 11 → 最新）

    public static let modelNames: [String: String] = [
        "iPhone11,2": "iPhone XS", "iPhone11,4": "iPhone XS Max", "iPhone11,6": "iPhone XS Max (CN)",
        "iPhone11,8": "iPhone XR",
        "iPhone12,1": "iPhone 11", "iPhone12,3": "iPhone 11 Pro", "iPhone12,5": "iPhone 11 Pro Max",
        "iPhone12,8": "iPhone SE (2nd generation)",
        "iPhone13,1": "iPhone 12 mini", "iPhone13,2": "iPhone 12", "iPhone13,3": "iPhone 12 Pro",
        "iPhone13,4": "iPhone 12 Pro Max",
        "iPhone14,2": "iPhone 13 Pro", "iPhone14,3": "iPhone 13 Pro Max",
        "iPhone14,4": "iPhone 13 mini", "iPhone14,5": "iPhone 13",
        "iPhone14,6": "iPhone SE (3rd generation)",
        "iPhone14,7": "iPhone 14", "iPhone14,8": "iPhone 14 Plus",
        "iPhone15,2": "iPhone 14 Pro", "iPhone15,3": "iPhone 14 Pro Max",
        "iPhone15,4": "iPhone 15", "iPhone15,5": "iPhone 15 Plus",
        "iPhone16,1": "iPhone 15 Pro", "iPhone16,2": "iPhone 15 Pro Max",
        "iPhone16,3": "iPhone 16 Pro", "iPhone16,4": "iPhone 16 Pro Max",
        "iPhone16,5": "iPhone 16", "iPhone16,6": "iPhone 16 Plus",
        "iPhone17,3": "iPhone 16e", "iPhone17,4": "iPhone 17",
        "iPhone17,5": "iPhone 17 Pro", "iPhone17,6": "iPhone 17 Pro Max",
    ]

    public static func marketingName(for identifier: String) -> String {
        if let name = modelNames[identifier] { return name }
        if identifier.contains("模拟器") || identifier.hasPrefix("arm64") { return "模拟器" }
        return identifier
    }

    public static let chipNames: [String: String] = [
        "iPhone11,2": "A12 Bionic", "iPhone11,4": "A12 Bionic", "iPhone11,6": "A12 Bionic",
        "iPhone11,8": "A12 Bionic",
        "iPhone12,1": "A13 Bionic", "iPhone12,3": "A13 Bionic", "iPhone12,5": "A13 Bionic",
        "iPhone12,8": "A13 Bionic",
        "iPhone13,1": "A14 Bionic", "iPhone13,2": "A14 Bionic", "iPhone13,3": "A14 Bionic",
        "iPhone13,4": "A14 Bionic",
        "iPhone14,2": "A15 Bionic", "iPhone14,3": "A15 Bionic", "iPhone14,4": "A15 Bionic",
        "iPhone14,5": "A15 Bionic", "iPhone14,6": "A15 Bionic",
        "iPhone14,7": "A15 Bionic", "iPhone14,8": "A15 Bionic",
        "iPhone15,2": "A16 Bionic", "iPhone15,3": "A16 Bionic",
        "iPhone15,4": "A16 Bionic", "iPhone15,5": "A16 Bionic",
        "iPhone16,1": "A17 Pro", "iPhone16,2": "A17 Pro",
        "iPhone16,3": "A18 Pro", "iPhone16,4": "A18 Pro",
        "iPhone16,5": "A18", "iPhone16,6": "A18",
        "iPhone17,3": "A18", "iPhone17,4": "A19", "iPhone17,5": "A19 Pro", "iPhone17,6": "A19 Pro",
    ]

    public static func chipName(for identifier: String) -> String? {
        chipNames[identifier]
    }

    public func collect() -> [MetricCard] {
        var cards: [MetricCard] = []
        let now = Date()
        let device = UIDevice.current
        let proc = ProcessInfo.processInfo

        let identifier = SysctlReader.machineIdentifier() ?? "unknown"
        let marketing = Self.marketingName(for: identifier)
        let chip = Self.chipName(for: identifier)

        cards.append(MetricCard(
            id: "dev.identifier", name: "设备型号标识", value: identifier,
            source: .appleAPI, method: "系统接口 sysctl（hw.machine）",
            limitation: identifier.hasPrefix("arm64") ? "模拟器上报的是 CPU 架构而非设备型号" : nil,
            status: .ok, collectedAt: now, category: .hardware
        ))
        cards.append(MetricCard(
            id: "dev.name", name: "市场名称", value: marketing,
            source: .derived, method: "hw.machine → 自建型号映射表（DeviceKit 思路）",
            status: .ok, collectedAt: now, category: .hardware
        ))
        if let chip = chip {
            cards.append(MetricCard(
                id: "dev.chip", name: "处理器芯片", value: chip,
                source: .derived, method: "型号标识 → 芯片映射表（Apple 官方规格）",
                status: .ok, collectedAt: now, category: .hardware
            ))
        }
        cards.append(MetricCard(
            id: "dev.systemname", name: "系统", value: "\(device.systemName) \(device.systemVersion)",
            source: .appleAPI, method: "UIDevice.systemName / systemVersion", status: .ok,
            collectedAt: now, category: .hardware
        ))
        if let osBuild = SysctlReader.string("kern.osversion") {
            cards.append(MetricCard(
                id: "dev.build", name: "系统版本号 (Build)", value: osBuild,
                source: .appleAPI, method: "系统接口 sysctl（kern.osversion）", status: .ok,
                collectedAt: now, category: .hardware
            ))
        }
        let uname = SysctlReader.unameFields()
        if let kernelRelease = uname["release"] {
            cards.append(MetricCard(
                id: "dev.kernel", name: "内核版本", value: kernelRelease,
                source: .appleAPI, method: "uname(3) release（Darwin 内核版本）",
                status: .ok, collectedAt: now, category: .hardware
            ))
        }
        cards.append(MetricCard(
            id: "dev.uptime", name: "系统运行时长", value: formatUptime(proc.systemUptime),
            numeric: proc.systemUptime, unit: "s",
            source: .appleAPI, method: "ProcessInfo.systemUptime", status: .ok,
            collectedAt: now, category: .hardware
        ))
        cards.append(MetricCard(
            id: "dev.simulator", name: "环境", value: isSimulator() ? "模拟器" : "真机",
            source: .appleAPI, method: "targetEnvironment check", status: .ok,
            collectedAt: now, category: .hardware
        ))

        return cards
    }

    private func isSimulator() -> Bool {
        #if targetEnvironment(simulator)
        return true
        #else
        return false
        #endif
    }

    private func formatUptime(_ interval: TimeInterval) -> String {
        let days = Int(interval) / 86400
        let hours = (Int(interval) % 86400) / 3600
        let minutes = (Int(interval) % 3600) / 60
        if days > 0 { return "\(days)d \(hours)h \(minutes)m" }
        return "\(hours)h \(minutes)m"
    }
}
