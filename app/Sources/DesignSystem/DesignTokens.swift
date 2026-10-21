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
    public static let radiusL: CGFloat = 20
    public static let radiusXL: CGFloat = 26

    // Icon
    public static let iconS: CGFloat = 13
    public static let iconM: CGFloat = 16
    public static let iconL: CGFloat = 22
    public static let iconXL: CGFloat = 28
}

// MARK: - 语义色（自动适配浅色/深色模式）+ 2026 渐变体系

public enum DSColor {
    public static let accent = Color(red: 0.35, green: 0.45, blue: 0.98)
    public static let cpu = Color(red: 0.25, green: 0.51, blue: 0.96)
    public static let memory = Color(red: 0.6, green: 0.35, blue: 0.92)
    public static let storage = Color(red: 0.95, green: 0.58, blue: 0.2)
    public static let battery = Color(red: 0.2, green: 0.75, blue: 0.5)
    public static let thermal = Color(red: 0.92, green: 0.35, blue: 0.35)
    public static let network = Color(red: 0.15, green: 0.7, blue: 0.85)
    public static let gpu = Color(red: 0.5, green: 0.4, blue: 0.95)
    public static let sensors = Color(red: 0.2, green: 0.8, blue: 0.65)
    public static let display = Color(red: 0.15, green: 0.65, blue: 0.6)
    public static let privacy = Color(red: 0.9, green: 0.35, blue: 0.6)

    // MARK: 渐变（主视觉）

    /// 主色渐变（用于强调按钮 / 装饰）
    public static var accentGradient: LinearGradient {
        LinearGradient(colors: [accent, accent.opacity(0.7)],
                       startPoint: .topLeading, endPoint: .bottomTrailing)
    }

    /// 任意基础色 → 柔和双段渐变
    public static func gradient(_ c: Color) -> LinearGradient {
        LinearGradient(colors: [c, c.opacity(0.62)],
                       startPoint: .topLeading, endPoint: .bottomTrailing)
    }

    /// 分类渐变色对（图标徽章 / 卡片顶光）
    public static func categoryGradient(_ category: MetricCategory) -> LinearGradient {
        gradient(categoryColor(category))
    }

    public static func statusColor(_ status: MetricStatus) -> Color {
        switch status {
        case .ok: return Color(red: 0.2, green: 0.75, blue: 0.5)
        case .degraded: return Color(red: 0.95, green: 0.58, blue: 0.2)
        case .unauthorized: return Color(red: 0.9, green: 0.78, blue: 0.25)
        case .unavailable: return Color(.systemGray)
        }
    }

    public static func categoryColor(_ category: MetricCategory) -> Color {
        switch category {
        case .overview: return accent
        case .hardware: return gpu
        case .cpu: return cpu
        case .memory: return memory
        case .storage: return storage
        case .battery, .thermal: return battery
        case .gpu: return gpu
        case .network: return network
        case .sensors: return sensors
        case .display: return display
        case .camera: return network
        case .privacy: return privacy
        case .system: return Color(.systemGray)
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

// MARK: - 图标徽章（圆角 squircle + 渐变 + 柔和投影）

public struct IconBadge: View {
    let systemName: String
    let color: Color
    var size: CGFloat = 34
    var fontSize: CGFloat? = nil

    public init(systemName: String, color: Color, size: CGFloat = 34, fontSize: CGFloat? = nil) {
        self.systemName = systemName
        self.color = color
        self.size = size
        self.fontSize = fontSize
    }

    public var body: some View {
        Image(systemName: systemName)
            .font(.system(size: fontSize ?? size * 0.46, weight: .semibold))
            .foregroundStyle(.white)
            .frame(width: size, height: size)
            .background(
                RoundedRectangle(cornerRadius: size * 0.30, style: .continuous)
                    .fill(DSColor.gradient(color))
            )
            .shadow(color: color.opacity(0.28), radius: 5, x: 0, y: 3)
    }
}

// MARK: - 卡片样式（现代：连续圆角 + 层级投影 + 顶光渐变 + 细描边）

public struct DSCardStyle: ViewModifier {
    var tint: Color = DSColor.accent
    var shadow: Bool = true

    public func body(content: Content) -> some View {
        content
            .padding(DSTokens.spaceL)
            .background {
                RoundedRectangle(cornerRadius: DSTokens.radiusL, style: .continuous)
                    .fill(Color(.secondarySystemGroupedBackground))
                    .overlay(
                        LinearGradient(
                            colors: [tint.opacity(0.10), tint.opacity(0.0)],
                            startPoint: .top, endPoint: .center
                        )
                        .clipShape(RoundedRectangle(cornerRadius: DSTokens.radiusL, style: .continuous))
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: DSTokens.radiusL, style: .continuous)
                            .strokeBorder(
                                LinearGradient(colors: [tint.opacity(0.18), tint.opacity(0.05)],
                                             startPoint: .topLeading, endPoint: .bottomTrailing),
                                lineWidth: 1
                            )
                    )
            }
            .shadow(color: tint.opacity(shadow ? 0.10 : 0), radius: 12, x: 0, y: 6)
            .contentShape(RoundedRectangle(cornerRadius: DSTokens.radiusL, style: .continuous))
    }
}

public extension View {
    func dsCard(tint: Color = DSColor.accent, shadow: Bool = true) -> some View {
        modifier(DSCardStyle(tint: tint, shadow: shadow))
    }
}

// MARK: - 指标卡片视图（信息层级：图标徽章+名称+状态点 / 大数值 / 方法+限制）

public struct MetricCardView: View {
    let card: MetricCard
    var compact: Bool = false

    public init(card: MetricCard, compact: Bool = false) {
        self.card = card
        self.compact = compact
    }

    private var tint: Color { DSColor.categoryColor(card.category) }

    public var body: some View {
        VStack(alignment: .leading, spacing: compact ? 6 : 10) {
            HStack(spacing: 10) {
                IconBadge(systemName: DSColor.categoryIcon(card.category),
                          color: tint,
                          size: compact ? 30 : 34)
                VStack(alignment: .leading, spacing: 2) {
                    Text(card.name)
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(.primary)
                        .lineLimit(1)
                    statusDot
                }
                Spacer(minLength: 0)
            }

            Text(card.value)
                .font(compact ? .title3 : .title2)
                .fontWeight(compact ? .bold : .heavy)
                .fontDesign(.rounded)
                .foregroundStyle(card.status == .unavailable ? Color(.tertiaryLabel) : Color.primary)
                .lineLimit(2)
                .minimumScaleFactor(0.6)

            if !compact {
                Text(card.method)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
                if let limitation = card.limitation {
                    Label(limitation, systemImage: "info.circle")
                        .font(.caption2)
                        .foregroundStyle(DSColor.statusColor(.degraded))
                        .lineLimit(3)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .dsCard(tint: tint)
    }

    // 状态点 + 徽章
    @ViewBuilder private var statusDot: some View {
        HStack(spacing: 4) {
            Circle()
                .fill(DSColor.statusColor(card.status))
                .frame(width: 7, height: 7)
            StatusBadge(status: card.status)
        }
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
        case .ok: return "正常"
        case .degraded: return "部分"
        case .unauthorized: return "权限"
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

// MARK: - 章节头（图标徽章 + 标题）

public struct SectionHeader: View {
    let title: String
    let category: MetricCategory

    public init(title: String, category: MetricCategory) {
        self.title = title
        self.category = category
    }

    public var body: some View {
        HStack(spacing: 10) {
            IconBadge(systemName: DSColor.categoryIcon(category),
                      color: DSColor.categoryColor(category),
                      size: 28)
            Text(title)
                .font(.headline.weight(.semibold))
                .foregroundStyle(.primary)
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
                    .fill(configuration.isPressed ? AnyShapeStyle(DSColor.accent.opacity(0.85)) : AnyShapeStyle(DSColor.accentGradient))
            )
            .foregroundStyle(.white)
            .shadow(color: DSColor.accent.opacity(0.3), radius: 6, y: 3)
            .scaleEffect(configuration.isPressed ? 0.97 : 1)
            .animation(.spring(response: 0.25, dampingFraction: 0.7), value: configuration.isPressed)
    }
}

// MARK: - 英雄卡（渐变底 + 白字，用于总览顶部）

public struct HeroCard: ViewModifier {
    var color: Color = DSColor.accent

    public func body(content: Content) -> some View {
        content
            .tint(.white)
            .foregroundStyle(.white)
            .padding(DSTokens.spaceL)
            .background(
                RoundedRectangle(cornerRadius: DSTokens.radiusXL, style: .continuous)
                    .fill(DSColor.gradient(color))
            )
            .overlay(
                RoundedRectangle(cornerRadius: DSTokens.radiusXL, style: .continuous)
                    .strokeBorder(.white.opacity(0.25), lineWidth: 1)
            )
            .shadow(color: color.opacity(0.35), radius: 14, x: 0, y: 8)
    }
}

public extension View {
    func heroCard(_ color: Color = DSColor.accent) -> some View {
        modifier(HeroCard(color: color))
    }
}
