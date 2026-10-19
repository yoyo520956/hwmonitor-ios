import SwiftUI

// MARK: - 悬浮窗模块定义（自定义面板的可用功能全集）

enum FloatingModule: String, CaseIterable, Identifiable {
    case device, cpu, memory, storage, battery, thermal
    case gpu, network, sensors, display, camera, privacy

    var id: String { rawValue }

    var title: String {
        switch self {
        case .device: return "设备"
        case .cpu: return "CPU"
        case .memory: return "内存"
        case .storage: return "存储"
        case .battery: return "电池与温度"
        case .thermal: return "热状态"
        case .gpu: return "GPU"
        case .network: return "网络"
        case .sensors: return "传感器"
        case .display: return "显示"
        case .camera: return "相机"
        case .privacy: return "隐私与权限"
        }
    }

    var icon: String {
        switch self {
        case .device: return "iphone.gen3"
        case .cpu: return "cpu"
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
        }
    }

    var color: Color { DSColor.categoryColor(category) }

    var category: MetricCategory {
        switch self {
        case .device: return .hardware
        case .cpu: return .cpu
        case .memory: return .memory
        case .storage: return .storage
        case .battery: return .battery
        case .thermal: return .thermal
        case .gpu: return .gpu
        case .network: return .network
        case .sensors: return .sensors
        case .display: return .display
        case .camera: return .camera
        case .privacy: return .privacy
        }
    }

    /// 点击模块卡后跳转的页签序号（总览0/硬件1/监控2/传感器3/系统4/设置5）
    var tabIndex: Int {
        switch self {
        case .cpu, .memory, .storage, .gpu: return 1
        case .network, .display, .camera: return 1
        case .battery, .thermal, .device: return 1
        case .sensors: return 3
        case .privacy: return 4
        }
    }

    /// 快照中该模块的卡片 id 前缀
    var idPrefixes: [String] {
        switch self {
        case .device: return ["dev."]
        case .cpu: return ["cpu."]
        case .memory: return ["mem."]
        case .storage: return ["sto."]
        case .battery: return ["bat.", "thermal.state"]
        case .thermal: return ["thermal."]
        case .gpu: return ["gpu."]
        case .network: return ["net."]
        case .sensors: return ["sensor."]
        case .display: return ["disp."]
        case .camera: return ["cam."]
        case .privacy: return ["priv."]
        }
    }

    /// 该模块在悬浮面板里最多显示的卡片数（保持面板紧凑）
    var maxCards: Int {
        switch self {
        case .cpu, .memory, .battery, .network: return 3
        case .device, .privacy: return 2
        default: return 2
        }
    }
}

// MARK: - 悬浮窗配置存储

enum FloatingConfig {
    static let enabledKey = "floating.enabled"
    static let modulesKey = "floating.modules"
    static let posXKey = "floating.posX"
    static let posYKey = "floating.posY"
    static let posValidKey = "floating.posValid"

    /// 默认模块：CPU / 内存 / 电池 / 网络
    static let defaultModules: [FloatingModule] = [.cpu, .memory, .battery, .network]

    static func loadModules() -> [FloatingModule] {
        let raw = UserDefaults.standard.string(forKey: modulesKey) ?? ""
        let ids = raw.split(separator: ",").compactMap { FloatingModule(rawValue: String($0)) }
        return ids.isEmpty ? defaultModules : ids
    }

    static func saveModules(_ modules: [FloatingModule]) {
        UserDefaults.standard.set(modules.map(\.rawValue).joined(separator: ","), forKey: modulesKey)
    }
}

// MARK: - 悬浮窗总成（球 + 可展开面板，挂 RootTabView overlay）

struct FloatingWindowOverlay: View {
    @EnvironmentObject var engine: MonitoringEngine

    @AppStorage(FloatingConfig.enabledKey) private var enabled = true
    @State private var expanded = false
    @State private var ballSize: CGSize = CGSize(width: 52, height: 52)

    // 拖动位置（View 尺寸就绪后初始化）
    @State private var position: CGPoint? = nil
    @AppStorage(FloatingConfig.posValidKey) private var posValid = false

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .topLeading) {
                if expanded { panelBackdrop }
                if expanded { FloatingPanelView(onClose: collapse, onJump: jump) }
                if !expanded { ball(at: geo.size) }
            }
            .frame(width: geo.size.width, height: geo.size.height, alignment: .topLeading)
        }
        .allowsHitTesting(enabled)
        .opacity(enabled ? 1 : 0)
        .onReceive(NotificationCenter.default.publisher(for: Notification.Name("hwmon.route.floating"))) { _ in
            // 深链 hwmonitor://floating（过时间窗校验）
            guard enabled, TimedEventBus.shared.consume("hwmon.route.floating") != nil else { return }
            withAnimation(.spring(response: 0.35, dampingFraction: 0.85)) { expanded = true }
        }
    }

    private func collapse() {
        withAnimation(.spring(response: 0.35, dampingFraction: 0.85)) { expanded = false }
    }

    private func jump(_ module: FloatingModule) {
        collapse()
        NotificationCenter.default.post(
            name: .floatingJumpToTab, object: nil, userInfo: ["tab": module.tabIndex]
        )
    }

    // MARK: 悬浮球

    @State private var dragging = false

    private func ball(at geoSize: CGSize) -> some View {
        let pos = initialPosition(in: geoSize)
        return FloatingBallShape(expanded: false)
            .frame(width: ballSize.width, height: ballSize.height)
            .position(pos)
            .shadow(color: .black.opacity(0.25), radius: dragging ? 10 : 5, y: 2)
            .scaleEffect(dragging ? 1.08 : 1.0)
            .animation(.spring(response: 0.3, dampingFraction: 0.7), value: dragging)
            .gesture(
                DragGesture(minimumDistance: 2)
                    .onChanged { value in
                        dragging = true
                        var x = pos.x + value.translation.width
                        var y = pos.y + value.translation.height
                        x = min(max(x, ballSize.width / 2), geoSize.width - ballSize.width / 2)
                        y = min(max(y, ballSize.height / 2), geoSize.height - ballSize.height / 2)
                        position = CGPoint(x: x, y: y)
                    }
                    .onEnded { _ in
                        dragging = false
                        // 边缘吸附：横向吸到左/右边缘
                        guard let cur = position else { return }
                        let snapLeft = ballSize.width / 2 + 6
                        let snapRight = geoSize.width - ballSize.width / 2 - 6
                        let targetX = cur.x < geoSize.width / 2 ? snapLeft : snapRight
                        withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
                            position = CGPoint(x: targetX, y: cur.y)
                        }
                        UserDefaults.standard.set(targetX, forKey: FloatingConfig.posXKey)
                        UserDefaults.standard.set(cur.y, forKey: FloatingConfig.posYKey)
                        posValid = true
                    }
            )
            .simultaneousGesture(TapGesture().onEnded {
                withAnimation(.spring(response: 0.35, dampingFraction: 0.85)) { expanded = true }
            })
    }

    private func initialPosition(in size: CGSize) -> CGPoint {
        if posValid {
            let x = UserDefaults.standard.double(forKey: FloatingConfig.posXKey)
            let y = UserDefaults.standard.double(forKey: FloatingConfig.posYKey)
            if x > 0, y > 0 { return CGPoint(x: x, y: y) }
        }
        // 默认：右边缘 38% 高度
        return CGPoint(x: size.width - ballSize.width / 2 - 6, y: size.height * 0.38)
    }

    // MARK: 面板背景（点击空白关闭）

    private var panelBackdrop: some View {
        Color.black.opacity(0.25)
            .ignoresSafeArea()
            .onTapGesture { collapse() }
    }
}

// MARK: - 悬浮球外形（半透明玻璃圆 + 仪表指针意象）

struct FloatingBallShape: View {
    let expanded: Bool

    var body: some View {
        ZStack {
            Circle()
                .fill(.ultraThinMaterial)
            Circle()
                .strokeBorder(
                    LinearGradient(
                        colors: [DSColor.accent.opacity(0.9), DSColor.gpu.opacity(0.7)],
                        startPoint: .topLeading, endPoint: .bottomTrailing
                    ), lineWidth: 1.5
                )
            VStack(spacing: 2) {
                Image(systemName: "gauge.with.needle")
                    .font(.system(size: 19, weight: .semibold))
                    .foregroundStyle(DSColor.accent)
                Text("监测")
                    .font(.system(size: 9, weight: .bold))
                    .foregroundStyle(.secondary)
            }
        }
    }
}

// MARK: - 悬浮面板（所选模块实时数据）

struct FloatingPanelView: View {
    @EnvironmentObject var engine: MonitoringEngine
    @State private var modules: [FloatingModule] = FloatingConfig.loadModules()
    let onClose: () -> Void
    let onJump: (FloatingModule) -> Void

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            if modules.isEmpty {
                emptyState
            } else {
                ScrollView {
                    VStack(spacing: DSTokens.spaceS) {
                        ForEach(modules) { module in
                            moduleSection(module)
                        }
                        footerHint
                    }
                    .padding(DSTokens.spaceL)
                }
            }
        }
        .frame(maxWidth: 380)
        .frame(maxHeight: 560)
        .background(
            RoundedRectangle(cornerRadius: DSTokens.radiusXL, style: .continuous)
                .fill(.regularMaterial)
                .shadow(color: .black.opacity(0.3), radius: 18, y: 6)
        )
        .clipShape(RoundedRectangle(cornerRadius: DSTokens.radiusXL, style: .continuous))
        .padding(.horizontal, DSTokens.spaceL)
        .padding(.top, 60)
        .transition(.scale(scale: 0.9, anchor: .top).combined(with: .opacity))
    }

    private var header: some View {
        HStack(spacing: DSTokens.spaceS) {
            Image(systemName: "gauge.with.needle")
                .foregroundStyle(DSColor.accent)
            Text("快捷监测")
                .font(.headline)
            Spacer()
            Button(action: onClose) {
                Image(systemName: "xmark.circle.fill")
                    .font(.title3)
                    .foregroundStyle(.tertiary)
            }
        }
        .padding(.horizontal, DSTokens.spaceL)
        .padding(.vertical, DSTokens.spaceM)
    }

    private var emptyState: some View {
        VStack(spacing: DSTokens.spaceM) {
            Image(systemName: "slider.horizontal.3")
                .font(.largeTitle)
                .foregroundStyle(.tertiary)
            Text("尚未选择任何模块")
                .font(.subheadline)
                .foregroundStyle(.secondary)
            Text("前往 设置 → 悬浮窗 自定义显示内容")
                .font(.caption)
                .foregroundStyle(.tertiary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 40)
        .padding(.bottom, 20)
    }

    private var footerHint: some View {
        Text("点击模块卡片可跳转到对应功能页")
            .font(.caption2)
            .foregroundStyle(.tertiary)
            .frame(maxWidth: .infinity)
            .padding(.top, DSTokens.spaceS)
    }

    // MARK: 单模块区块

    private func moduleSection(_ module: FloatingModule) -> some View {
        let cards = cardsFor(module)
        return VStack(alignment: .leading, spacing: DSTokens.spaceXS) {
            Button { onJump(module) } label: {
                HStack(spacing: 6) {
                    Image(systemName: module.icon)
                        .font(.system(size: DSTokens.iconS, weight: .semibold))
                        .foregroundStyle(module.color)
                    Text(module.title)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.primary)
                    Spacer()
                    Image(systemName: "chevron.right")
                        .font(.system(size: 10))
                        .foregroundStyle(.tertiary)
                }
            }
            .buttonStyle(.plain)
            if cards.isEmpty {
                Text("数据采集中…")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
                    .padding(.leading, 4)
            } else {
                ForEach(cards) { card in
                    HStack(alignment: .firstTextBaseline) {
                        Text(card.name)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                        Spacer()
                        Text(card.value)
                            .font(.caption.weight(.semibold).monospacedDigit())
                            .foregroundStyle(DSColor.statusColor(card.status))
                            .lineLimit(1)
                            .minimumScaleFactor(0.7)
                    }
                    .padding(.vertical, 1)
                }
            }
        }
        .padding(DSTokens.spaceM)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: DSTokens.radiusM, style: .continuous)
                .fill(Color(.secondarySystemGroupedBackground))
        )
    }

    private func cardsFor(_ module: FloatingModule) -> [MetricCard] {
        let all = engine.snapshot.allCards
        var result: [MetricCard] = []
        for prefix in module.idPrefixes {
            for card in all where card.id.hasPrefix(prefix) {
                if result.first(where: { $0.id == card.id }) == nil {
                    result.append(card)
                }
            }
        }
        // 按预设优先级排序：总是先显示"主指标"
        return Array(result.prefix(module.maxCards))
    }
}

extension Notification.Name {
    static let floatingJumpToTab = Notification.Name("floatingJumpToTab")
}
