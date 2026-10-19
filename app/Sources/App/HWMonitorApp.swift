import SwiftUI

@main
struct HWMonitorApp: App {
    @StateObject private var engine = MonitoringEngine.shared

    init() {
        // 启动自检第 0 步：安装异常哨兵（必须在任何采集之前）
        CrashSentinel.install()
    }

    var body: some Scene {
        WindowGroup {
            RootTabView()
                .environmentObject(engine)
        }
    }
}

// MARK: - 六页签根导航 + 悬浮窗 + 深链路由（v3.0）

struct RootTabView: View {
    @EnvironmentObject var engine: MonitoringEngine
    @Environment(\.scenePhase) private var scenePhase
    @State private var selectedTab = 0

    // 深链路由目标
    @State private var deepLinkCard: MetricCard?
    @State private var showSelfCheck = false
    @State private var showExport = false
    @State private var routeToast: String?

    var body: some View {
        TabView(selection: $selectedTab) {
            OverviewView()
                .tabItem { Label("总览", systemImage: "gauge") }
                .tag(0)
            HardwareView()
                .tabItem { Label("硬件", systemImage: "cpu") }
                .tag(1)
            MonitorView()
                .tabItem { Label("监控", systemImage: "chart.xyaxis.line") }
                .tag(2)
            SensorsTabView()
                .tabItem { Label("传感器", systemImage: "sensor.tag.radiowaves.forward") }
                .tag(3)
            SystemView()
                .tabItem { Label("系统", systemImage: "shield.lefthalf.filled") }
                .tag(4)
            SettingsView()
                .tabItem { Label("设置", systemImage: "gearshape") }
                .tag(5)
        }
        .tint(DSColor.accent)
        .overlay { FloatingWindowOverlay() }
        .overlay(alignment: .top) { toastView }
        // 深链入口（hwmonitor://…）
        .onOpenURL { url in
            _ = DeepLinkRouter.dispatch(url)
        }
        // 路由消费（经时间窗校验：>3 秒的陈旧事件丢弃）
        .onReceive(NotificationCenter.default.publisher(for: Notification.Name("hwmon.route.tab"))) { _ in
            guard let info = TimedEventBus.shared.consume("hwmon.route.tab"),
                  let tab = info["tab"] as? Int else { return }
            selectedTab = tab
        }
        .onReceive(NotificationCenter.default.publisher(for: Notification.Name("hwmon.route.detail"))) { _ in
            guard let info = TimedEventBus.shared.consume("hwmon.route.detail"),
                  let id = info["id"] as? String else { return }
            if let card = engine.snapshot.allCards.first(where: { $0.id == id }) {
                deepLinkCard = card
            } else {
                showToast("未找到指标：\(id)")
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: Notification.Name("hwmon.route.diagnostics"))) { _ in
            guard TimedEventBus.shared.consume("hwmon.route.diagnostics") != nil else { return }
            showSelfCheck = true
        }
        .onReceive(NotificationCenter.default.publisher(for: Notification.Name("hwmon.route.export"))) { _ in
            guard TimedEventBus.shared.consume("hwmon.route.export") != nil else { return }
            showExport = true
        }
        .onReceive(NotificationCenter.default.publisher(for: Notification.Name("hwmon.route.unknown"))) { _ in
            guard let info = TimedEventBus.shared.consume("hwmon.route.unknown"),
                  let host = info["host"] as? String else { return }
            showToast("未识别的深链：hwmonitor://\(host)")
        }
        // 悬浮窗跳页签（兼容 v2 机制，同样过时间窗）
        .onReceive(NotificationCenter.default.publisher(for: .floatingJumpToTab)) { note in
            if let tab = note.userInfo?["tab"] as? Int { selectedTab = tab }
        }
        .sheet(item: $deepLinkCard) { card in
            NavigationStack {
                CardDetailView(card: card)
                    .toolbar {
                        ToolbarItem(placement: .topBarLeading) {
                            Button("关闭") { deepLinkCard = nil }
                        }
                    }
            }
            .environmentObject(engine)
        }
        .sheet(isPresented: $showSelfCheck) {
            NavigationStack {
                SelfCheckView()
                    .environmentObject(engine)
                    .toolbar {
                        ToolbarItem(placement: .topBarLeading) {
                            Button("关闭") { showSelfCheck = false }
                        }
                    }
            }
        }
        .sheet(isPresented: $showExport) {
            ExportView()
                .environmentObject(engine)
        }
        .onAppear {
            engine.rebuildSnapshot()
            engine.resume()
            // 启动自检链（进入 UI 即跑，结果进自检页）
            Task { _ = await LaunchSelfCheck.shared.runAll() }
        }
        .onChange(of: scenePhase) { phase in
            switch phase {
            case .active:
                engine.resume()
                CrashSentinel.touchHeartbeat()
            case .background:
                engine.pause()
                // 进入后台视为健康状态（下次启动不再报"异常中断"）
                CrashSentinel.markHealthy()
            default:
                break
            }
        }
    }

    // MARK: 轻提示

    @ViewBuilder
    private var toastView: some View {
        if let toast = routeToast {
            Text(toast)
                .font(.caption.weight(.medium))
                .padding(.horizontal, 14)
                .padding(.vertical, 8)
                .background(Capsule().fill(.regularMaterial))
                .shadow(radius: 4)
                .padding(.top, 8)
                .transition(.move(edge: .top).combined(with: .opacity))
        }
    }

    private func showToast(_ text: String) {
        withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) { routeToast = text }
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.2) {
            withAnimation { routeToast = nil }
        }
    }
}
