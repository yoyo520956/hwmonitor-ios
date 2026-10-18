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

// MARK: - 六页签根导航（SE3 375pt 宽实测：iconOnly 紧凑排布）

struct RootTabView: View {
    @EnvironmentObject var engine: MonitoringEngine

    var body: some View {
        TabView {
            OverviewView()
                .tabItem { Label("Overview", systemImage: "gauge") }
            HardwareView()
                .tabItem { Label("Hardware", systemImage: "cpu") }
            MonitorView()
                .tabItem { Label("Monitor", systemImage: "chart.xyaxis.line") }
            SensorsTabView()
                .tabItem { Label("Sensors", systemImage: "sensor.tag.radiowaves.forward") }
            SystemView()
                .tabItem { Label("System", systemImage: "shield.lefthalf.filled") }
            SettingsView()
                .tabItem { Label("Settings", systemImage: "gearshape") }
        }
        .tint(DSColor.accent)
        .onAppear {
            engine.rebuildSnapshot()
            engine.resume()
        }
    }
}
