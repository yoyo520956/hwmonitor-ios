import Foundation

// MARK: - 数据可信度模型（任务书第六阶段硬性要求）
// 每一项数据必须能追溯到：Apple 官方 API / 真实采样计算 / 明确规则推导 / 系统未开放

/// 数据来源标注
public enum MetricSource: String, Codable, Sendable {
    case appleAPI = "Apple Official API"       // Apple 官方 API 直接读取
    case computed = "Real Sampling"            // 基于真实采样值计算
    case derived = "Derived"                   // 根据明确规则推导
    case systemRestricted = "Not Exposed"      // 当前系统无法提供
}

/// 采集状态：不可用的数据绝不能看起来像检测成功
public enum MetricStatus: String, Codable, Sendable {
    case ok                 // 采集成功
    case degraded           // 部分可用（如只拿到部分字段）
    case unauthorized       // 需要权限且被拒绝
    case unavailable        // 系统不提供 / 采集失败
}

/// 单条指标卡片：UI 的最小数据单元
public struct MetricCard: Identifiable, Codable, Sendable, Hashable {
    public var id: String
    /// 显示名（如 "CPU Usage (Total)"）
    public var name: String
    /// 主值（已格式化字符串，如 "23.4%"、"6.02 GB"）
    public var value: String
    /// 数值部分（原始值，供图表使用；nil 表示纯文本）
    public var numeric: Double?
    /// 单位
    public var unit: String?
    /// 来源标注
    public var source: MetricSource
    /// 采集 API 或计算方式说明
    public var method: String
    /// 限制与可信度说明（unavailable 时必填原因）
    public var limitation: String?
    /// 状态
    public var status: MetricStatus
    /// 最后更新时间
    public var collectedAt: Date
    /// 所属模块（用于分组与图标）
    public var category: MetricCategory

    public init(
        id: String, name: String, value: String, numeric: Double? = nil,
        unit: String? = nil, source: MetricSource, method: String,
        limitation: String? = nil, status: MetricStatus,
        collectedAt: Date = Date(), category: MetricCategory
    ) {
        self.id = id
        self.name = name
        self.value = value
        self.numeric = numeric
        self.unit = unit
        self.source = source
        self.method = method
        self.limitation = limitation
        self.status = status
        self.collectedAt = collectedAt
        self.category = category
    }

    /// 系统未开放的标准占位卡片（绝不用假数据填充）
    public static func restricted(
        _ id: String, _ name: String, reason: String, category: MetricCategory
    ) -> MetricCard {
        MetricCard(
            id: id, name: name,
            value: "—",
            source: .systemRestricted,
            method: "No public iOS API",
            limitation: reason,
            status: .unavailable,
            category: category
        )
    }
}

/// 指标大类（决定导航分组与 SF Symbol 图标）
public enum MetricCategory: String, Codable, Sendable, CaseIterable, Identifiable {
    case overview
    case hardware
    case cpu
    case memory
    case storage
    case battery
    case thermal
    case gpu
    case network
    case sensors
    case display
    case camera
    case privacy
    case system

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .overview: return "Overview"
        case .hardware: return "Hardware"
        case .cpu: return "CPU"
        case .memory: return "Memory"
        case .storage: return "Storage"
        case .battery: return "Battery"
        case .thermal: return "Thermal"
        case .gpu: return "GPU"
        case .network: return "Network"
        case .sensors: return "Sensors"
        case .display: return "Display"
        case .camera: return "Camera"
        case .privacy: return "Privacy"
        case .system: return "System"
        }
    }
}

// MARK: - 快照模型（导出用）

/// 一次完整快照：所有模块当前数据，用于诊断报告与历史记录
public struct Snapshot: Codable, Sendable {
    public var createdAt: Date
    public var device: [MetricCard]
    public var cpu: [MetricCard]
    public var memory: [MetricCard]
    public var storage: [MetricCard]
    public var battery: [MetricCard]
    public var gpu: [MetricCard]
    public var network: [MetricCard]
    public var sensors: [MetricCard]
    public var display: [MetricCard]
    public var privacy: [MetricCard]

    public init(
        createdAt: Date = Date(), device: [MetricCard] = [], cpu: [MetricCard] = [],
        memory: [MetricCard] = [], storage: [MetricCard] = [], battery: [MetricCard] = [],
        gpu: [MetricCard] = [], network: [MetricCard] = [], sensors: [MetricCard] = [],
        display: [MetricCard] = [], privacy: [MetricCard] = []
    ) {
        self.createdAt = createdAt
        self.device = device
        self.cpu = cpu
        self.memory = memory
        self.storage = storage
        self.battery = battery
        self.gpu = gpu
        self.network = network
        self.sensors = sensors
        self.display = display
        self.privacy = privacy
    }

    public var allCards: [MetricCard] {
        device + cpu + memory + storage + battery + gpu + network + sensors + display + privacy
    }
}
