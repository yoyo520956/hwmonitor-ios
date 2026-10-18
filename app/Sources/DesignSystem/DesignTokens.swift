import SwiftUI

// MARK: - 设计系统 Tokens（全 App 共享，禁止页面自定义样式）

public enum DSTokens {
    // Spacing
    public static let spaceXS: CGFloat = 4
    public static let spaceS: CGFloat = 8
    public static let spaceM: CGFloat = 12
    public static let spaceL: CGFloat = 16
    public static let spaceXL: CGFloat = 20
    public static let spaceXXL: CGFloat = 28

    // Radius
    public static let radiusS: CGFloat = 10
    public static let radiusM: CGFloat = 14
    public static let radiusL: CGFloat = 18
    public static let radiusXL: CGFloat = 24

    // Icon
    public static let iconS: CGFloat = 13
    public static let iconM: CGFloat = 16
    public static let iconL: CGFloat = 22
    public static let iconXL: CGFloat = 28
}

// MARK: - 语义色（自动适配浅色/深色模式）

public enum DSColor {
    public static let accent = Color.blue
    public static let cpu = Color.blue
    public static let memory = Color.purple
    public static let storage = Color.orange
    public static let battery = Color.green
    public static let thermal = Color.red
    public static let network = Color.cyan
    public static let gpu = Color.indigo
    public static let sensors = Color.mint
    public static let display = Color.teal
    public static let privacy = Color.pink

    public static func statusColor(_ status: MetricStatus) -> Color {
        switch status {
        case .ok: return .green
        case .degraded: return .orange
        case .unauthorized: return .yellow
        case .unavailable: return Color(.systemGray)
        }
    }

    public static func categoryColor(_ category: MetricCategory) -> Color {
        switch category {
        case .overview: return .blue
        case .hardware: return .indigo
        case .cpu: return cpu
        case .memory: return memory
        case .storage: return storage
        case .battery, .thermal: return battery
        case .gpu: return gpu
        case .network: return network
        case .sensors: return sensors
        case .display: return display
        case .camera: return .cyan
        case .privacy: return privacy
        case .system: return .secondary
        }
    }

    public static func categoryIcon(_ category: MetricCategory) -> String {
        switch category {
        case .overview: return "gauge"
        case .hardware: return "cpu"
        case .cpu: return "waveform.path.ecg"
        case .memory: return "memorychip"
        case .storage: return "internaldrive"
        case .battery: return "battery.100"
        case .thermal: return "thermometer.medium"
        case .gpu: return "sparkles"
        case .network: return "wifi"
        case .sensors: return "sensor.tag.radiowaves.forward"
        case .display: return "display"
        case .camera: return "camera"
        case .privacy: return "hand.raised"
        case .system: return "gearshape"
        }
    }
}

// MARK: - 卡片样式

public struct DSCardStyle: ViewModifier {
    var tint: Color = DSColor.accent

    public func body(content: Content) -> some View {
        content
            .padding(DSTokens.spaceL)
            .background(
                RoundedRectangle(cornerRadius: DSTokens.radiusL, style: .continuous)
                    .fill(Color(.secondarySystemGroupedBackground))
            )
            .overlay(
                RoundedRectangle(cornerRadius: DSTokens.radiusL, style: .continuous)
                    .strokeBorder(tint.opacity(0.12), lineWidth: 1)
            )
    }
}

public extension View {
    func dsCard(tint: Color = DSColor.accent) -> some View {
        modifier(DSCardStyle(tint: tint))
    }
}

// MARK: - 指标卡片视图（信息层级：图标+名称+状态徽章 / 大数值 / 方法+限制）

public struct MetricCardView: View {
    let card: MetricCard
    var compact: Bool = false

    public init(card: MetricCard, compact: Bool = false) {
        self.card = card
        self.compact = compact
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: DSTokens.spaceS) {
            HStack(spacing: DSTokens.spaceS) {
                Image(systemName: DSColor.categoryIcon(card.category))
                    .font(.system(size: DSTokens.iconM, weight: .medium))
                    .foregroundStyle(DSColor.categoryColor(card.category))
                    .frame(width: 22)
                Text(card.name)
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(.primary)
                Spacer()
                StatusBadge(status: card.status)
            }

            Text(card.value)
                .font(card.value.count > 24 ? .callout.monospaced() : .title3.weight(.semibold).monospacedDigit())
                .foregroundStyle(card.status == .unavailable ? Color(.tertiaryLabel) : Color.primary)
                .lineLimit(2)
                .minimumScaleFactor(0.7)

            if !compact {
                Text(card.method)
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
                    .lineLimit(2)
                if let limitation = card.limitation {
                    Text(limitation)
                        .font(.caption2)
                        .foregroundStyle(DSColor.statusColor(.degraded))
                        .lineLimit(3)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .dsCard(tint: DSColor.categoryColor(card.category))
    }
}

// MARK: - 状态徽章

public struct StatusBadge: View {
    let status: MetricStatus

    public init(status: MetricStatus) {
        self.status = status
    }

    private var label: String {
        switch status {
        case .ok: return "OK"
        case .degraded: return "PARTIAL"
        case .unauthorized: return "PERM"
        case .unavailable: return "N/A"
        }
    }

    public var body: some View {
        Text(label)
            .font(.system(size: 9, weight: .bold, design: .rounded))
            .tracking(0.5)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(Capsule().fill(DSColor.statusColor(status).opacity(0.15)))
            .foregroundStyle(DSColor.statusColor(status))
    }
}

// MARK: - 章节头

public struct SectionHeader: View {
    let title: String
    let category: MetricCategory

    public init(title: String, category: MetricCategory) {
        self.title = title
        self.category = category
    }

    public var body: some View {
        HStack(spacing: DSTokens.spaceS) {
            Image(systemName: DSColor.categoryIcon(category))
                .font(.system(size: DSTokens.iconM, weight: .semibold))
                .foregroundStyle(DSColor.categoryColor(category))
            Text(title)
                .font(.headline)
            Spacer()
        }
        .padding(.top, DSTokens.spaceL)
    }
}

// MARK: - 通用按钮样式

public struct DSPrimaryButtonStyle: ButtonStyle {
    public init() {}
    public func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.subheadline.weight(.semibold))
            .padding(.horizontal, DSTokens.spaceL)
            .padding(.vertical, DSTokens.spaceM)
            .background(
                RoundedRectangle(cornerRadius: DSTokens.radiusM, style: .continuous)
                    .fill(DSColor.accent.opacity(configuration.isPressed ? 0.75 : 1))
            )
            .foregroundStyle(.white)
            .scaleEffect(configuration.isPressed ? 0.97 : 1)
            .animation(.spring(response: 0.25, dampingFraction: 0.7), value: configuration.isPressed)
    }
}
