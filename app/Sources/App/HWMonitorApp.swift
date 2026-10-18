import SwiftUI

@main
struct HWMonitorApp: App {
    @StateObject private var engine = MonitoringEngine.shared

    var body: some Scene {
        WindowGroup {
            RootTabView()
                .environmentObject(engine)
        }
    }
}

// MARK: - 六页签根导航 + 悬浮窗（SE3 375pt 宽实测：iconOnly 紧凑排布）

struct RootTabView: View {
    @EnvironmentObject var engine: MonitoringEngine
    @State private var selectedTab = 0

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
        .onReceive(NotificationCenter.default.publisher(for: .floatingJumpToTab)) { note in
            if let tab = note.userInfo?["tab"] as? Int { selectedTab = tab }
        }
        .onAppear {
            engine.rebuildSnapshot()
            engine.resume()
        }
    }
}
