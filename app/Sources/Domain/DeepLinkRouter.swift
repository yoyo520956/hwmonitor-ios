import Foundation

// MARK: - 深链路由表
// 迁移自 LiveContainer dispatchURL：URL host 作路由 key，统一入口分发。
// 支持：hwmonitor://cpu | memory | network | battery | sensors | privacy |
//      gpu | display | camera | storage | device | diagnostics | export | floating
//      hwmonitor://detail?id=cpu.usage   直达某张指标的详情页

enum DeepLinkRoute: Equatable {
    case tab(Int)                    // 跳页签
    case detail(String)              // 直达指标详情（card id）
    case diagnostics
    case export
    case floating                    // 展开悬浮面板
    case unknown(String)             // 未识别 host（进入总览并提示）
}

enum DeepLinkRouter {
    /// host → 路由映射表（域.页面.语义 风格命名）
    static func route(for url: URL) -> DeepLinkRoute? {
        guard url.scheme?.lowercased() == "hwmonitor" else { return nil }
        let host = (url.host ?? "").lowercased()

        // detail 路由：hwmonitor://detail?id=cpu.usage
        if host == "detail" {
            let comps = URLComponents(url: url, resolvingAgainstBaseURL: false)
            let id = comps?.queryItems?.first(where: { $0.name == "id" })?.value ?? ""
            return id.isEmpty ? .unknown("detail") : .detail(id)
        }

        switch host {
        case "cpu", "memory", "storage", "gpu", "battery", "thermal", "display", "camera", "device":
            return .tab(1)
        case "overview", "home":
            return .tab(0)
        case "monitor":
            return .tab(2)
        case "sensors":
            return .tab(3)
        case "network", "privacy", "system":
            return .tab(4)
        case "settings":
            return .tab(5)
        case "diagnostics":
            return .diagnostics
        case "export":
            return .export
        case "floating":
            return .floating
        default:
            return .unknown(host)
        }
    }

    /// 分发（经时间窗总线，防陈旧事件在场景切换后误触发）
    @discardableResult
    static func dispatch(_ url: URL) -> Bool {
        guard let route = route(for: url) else { return false }
        switch route {
        case .tab(let index):
            TimedEventBus.shared.post("hwmon.route.tab", userInfo: ["tab": index])
        case .detail(let id):
            TimedEventBus.shared.post("hwmon.route.detail", userInfo: ["id": id])
        case .diagnostics:
            TimedEventBus.shared.post("hwmon.route.diagnostics", userInfo: [:])
        case .export:
            TimedEventBus.shared.post("hwmon.route.export", userInfo: [:])
        case .floating:
            TimedEventBus.shared.post("hwmon.route.floating", userInfo: [:])
        case .unknown(let host):
            TimedEventBus.shared.post("hwmon.route.unknown", userInfo: ["host": host])
        }
        return true
    }

    /// 生成分享/快捷指令用的深链示例（设置页展示）
    static let examples: [(String, String)] = [
        ("跳转 CPU 概览", "hwmonitor://cpu"),
        ("跳转网络页", "hwmonitor://network"),
        ("直达 CPU 使用率详情", "hwmonitor://detail?id=cpu.usage"),
        ("打开自检页", "hwmonitor://diagnostics"),
        ("展开悬浮面板", "hwmonitor://floating"),
    ]
}
