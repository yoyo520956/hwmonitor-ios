import Foundation
import Metal
import UIKit

/// GPU 采集器：Metal 公开 API（Loupe 验证过的做法）
/// 实时利用率/频率：iOS 不开放 → 标注
public final class GPUProvider: @unchecked Sendable {
    public let category: MetricCategory = .gpu

    public init() {}

    public func collect() -> [MetricCard] {
        var cards: [MetricCard] = []
        let now = Date()

        guard let device = MTLCreateSystemDefaultDevice() else {
            cards.append(MetricCard(
                id: "gpu.device", name: "GPU", value: "—",
                source: .appleAPI, method: "MTLCreateSystemDefaultDevice",
                limitation: "No default Metal device (simulator may not report a GPU)",
                status: .unavailable, collectedAt: now, category: .gpu
            ))
            return cards
        }

        cards.append(MetricCard(
            id: "gpu.name", name: "GPU Name", value: device.name,
            source: .appleAPI, method: "MTLDevice.name (e.g. Apple A15 GPU)",
            status: .ok, collectedAt: now, category: .gpu
        ))
        cards.append(MetricCard(
            id: "gpu.workingset", name: "Recommended Max Working Set", value: ByteFormat.gibibytes(Double(device.recommendedMaxWorkingSetSize)),
            numeric: Double(device.recommendedMaxWorkingSetSize), unit: "bytes",
            source: .appleAPI, method: "MTLDevice.recommendedMaxWorkingSetSize",
            status: .ok, collectedAt: now, category: .gpu
        ))

        // 统一内存
        if #available(iOS 13.0, *) {
            cards.append(MetricCard(
                id: "gpu.unified", name: "Unified Memory", value: device.hasUnifiedMemory ? "Yes" : "No",
                source: .appleAPI, method: "MTLDevice.hasUnifiedMemory", status: .ok,
                collectedAt: now, category: .gpu
            ))
        }

        // Metal 特性
        let features: [(String, Bool)] = [
            ("Ray Tracing", device.supportsRaytracing),
            ("Function Pointers", device.supportsFunctionPointers),
            ("32-bit Float Filtering", device.supports32BitFloatFiltering),
        ]
        for (name, supported) in features {
            let idPart = name.lowercased().replacingOccurrences(of: " ", with: "")
            cards.append(MetricCard(
                id: "gpu.\(idPart)",
                name: name, value: supported ? "Yes" : "No",
                source: .appleAPI, method: "MTLDevice feature flag", status: .ok,
                collectedAt: now, category: .gpu
            ))
        }

        // GPU Family 枚举（apple10 为 iOS 18+ case，单独检查）
        var supportedFamilies: [String] = []
        let families: [(MTLGPUFamily, String)] = [
            (.apple2, "Apple 2"), (.apple3, "Apple 3"), (.apple4, "Apple 4"),
            (.apple5, "Apple 5"), (.apple6, "Apple 6"), (.apple7, "Apple 7"),
            (.apple8, "Apple 8"), (.apple9, "Apple 9"),
            (.metal3, "Metal 3"),
        ]
        for (family, label) in families where device.supportsFamily(family) {
            supportedFamilies.append(label)
        }
        if #available(iOS 18.0, *) {
            if device.supportsFamily(.apple10) {
                supportedFamilies.append("Apple 10")
            }
        }
        if #available(iOS 26.0, *) {
            if device.supportsFamily(.metal4) {
                supportedFamilies.append("Metal 4")
            }
        }
        if !supportedFamilies.isEmpty {
            cards.append(MetricCard(
                id: "gpu.families", name: "Metal GPU Families", value: supportedFamilies.joined(separator: ", "),
                source: .appleAPI, method: "MTLDevice.supportsFamily enumeration",
                status: .ok, collectedAt: now, category: .gpu
            ))
        }

        // 系统限制
        cards.append(.restricted(
            "gpu.util", "GPU Utilization",
            reason: "iOS does not expose real-time GPU utilization or frequency to apps. Apps claiming live GPU meters are using animations or estimates.",
            category: .gpu
        ))

        return cards
    }
}

/// 屏幕采集器：UIScreen 公开属性
public final class DisplayProvider: @unchecked Sendable {
    public let category: MetricCategory = .display

    public init() {}

    public func collect() -> [MetricCard] {
        var cards: [MetricCard] = []
        let now = Date()
        let screen = UIScreen.main

        let nativeBounds = screen.nativeBounds
        let bounds = screen.bounds
        cards.append(MetricCard(
            id: "disp.native", name: "Native Resolution", value: "\(Int(nativeBounds.width)) × \(Int(nativeBounds.height)) px",
            numeric: Double(nativeBounds.width * nativeBounds.height), unit: "px",
            source: .appleAPI, method: "UIScreen.nativeBounds", status: .ok,
            collectedAt: now, category: .display
        ))
        cards.append(MetricCard(
            id: "disp.logical", name: "Logical Resolution", value: "\(Int(bounds.width)) × \(Int(bounds.height)) pt",
            numeric: Double(bounds.width * bounds.height), unit: "pt",
            source: .appleAPI, method: "UIScreen.bounds", status: .ok,
            collectedAt: now, category: .display
        ))
        cards.append(MetricCard(
            id: "disp.scale", name: "Scale Factor", value: "@\(Int(screen.nativeScale))x",
            numeric: Double(screen.nativeScale), unit: "x",
            source: .appleAPI, method: "UIScreen.nativeScale", status: .ok,
            collectedAt: now, category: .display
        ))
        cards.append(MetricCard(
            id: "disp.refresh", name: "Max Refresh Rate", value: "\(screen.maximumFramesPerSecond) Hz",
            numeric: Double(screen.maximumFramesPerSecond), unit: "Hz",
            source: .appleAPI, method: "UIScreen.maximumFramesPerSecond",
            limitation: "Maximum supported rate; ProMotion devices adapt dynamically and iOS does not expose the live rate",
            status: .ok, collectedAt: now, category: .display
        ))
        cards.append(MetricCard(
            id: "disp.brightness", name: "Brightness", value: PercentFormat.string(Double(screen.brightness), digits: 0),
            numeric: Double(screen.brightness), unit: "%",
            source: .appleAPI, method: "UIScreen.brightness (0...1)", status: .ok,
            collectedAt: now, category: .display
        ))

        return cards
    }
}
