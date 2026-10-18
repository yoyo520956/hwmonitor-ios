import Foundation

// MARK: - Provider 协议（Loupe 范式 + SystemInfoKit 差分状态）

/// 所有采集器的统一协议
/// - collect() 返回该模块当前全部指标卡片
/// - 采集器内部自行管理差分状态（如 CPU tick 缓存），必须线程安全
public protocol MetricsProvider: Sendable {
    /// 模块分类
    var category: MetricCategory { get }
    /// 采集当前数据（同步快速调用，内部不得做耗时 IO）
    func collect() -> [MetricCard]
}

/// 支持持续采样历史的采集器（监控页使用）
public protocol StreamableProvider: MetricsProvider {
    /// 追加一个采样点到历史序列（由 MonitoringEngine 按统一节拍调用）
    func tick()
    /// 当前历史序列（供 Swift Charts 绘制）
    var history: [SamplePoint] { get }
    /// 清空历史
    func resetHistory()
}

/// 采样点
public struct SamplePoint: Identifiable, Codable, Sendable, Hashable {
    public var id: Date { timestamp }
    public let timestamp: Date
    public let value: Double

    public init(timestamp: Date = Date(), value: Double) {
        self.timestamp = timestamp
        self.value = value
    }
}

// MARK: - 数值与单位工具

public enum ByteFormat {
    /// 统一单位换算：字节 → 人读字符串（1 GB = 1000³ B，与系统存储口径一致）
    public static func gigabytes(_ bytes: Double) -> String {
        ByteCountFormatter.string(fromByteCount: Int64(bytes), countStyle: .decimal)
    }

    /// 内存用二进制口径（host_* 返回的是 1024 进制页计数）
    public static func gibibytes(_ bytes: Double) -> String {
        ByteCountFormatter.string(fromByteCount: Int64(bytes), countStyle: .memory)
    }
}

public enum PercentFormat {
    public static func string(_ fraction: Double, digits: Int = 1) -> String {
        String(format: "%.\(digits)f%%", fraction * 100)
    }
}
