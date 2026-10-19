import Foundation
import UIKit

// MARK: - 运行时安全层
// 迁移自 LiveContainer 工程细节宝库：
// ① 哨兵标志（SigningInProgress）② 错误持久化跨进程 ③ watchdog 预写遗言 ④ 时间窗防重放

/// 哨兵 + 异常遗言：让"上一次运行发生了什么"跨启动可见
enum CrashSentinel {
    private static let lastErrorKey = "hwmon.lastError"
    private static let sentinelPrefix = "hwmon.sentinel."
    private static let cleanExitKey = "hwmon.cleanExit"
    private static let heartbeatKey = "hwmon.heartbeat"

    // MARK: 异常捕获（ObjC 异常 + 信号）

    static func install() {
        NSSetUncaughtExceptionHandler { exception in
            writeError(
                title: "未捕获异常",
                reason: exception.reason ?? exception.name.rawValue,
                stack: exception.callStackSymbols
            )
        }
        // 标记"本次运行尚未正常退出"
        UserDefaults.standard.set(false, forKey: cleanExitKey)
        // 记录启动时间作为心跳初值
        touchHeartbeat()
    }

    /// 正常退出的场合由 scenePhase 调（进入后台即视为健康状态）
    static func markHealthy() {
        UserDefaults.standard.set(true, forKey: cleanExitKey)
    }

    static func touchHeartbeat() {
        UserDefaults.standard.set(Date().timeIntervalSince1970, forKey: heartbeatKey)
    }

    // MARK: 哨兵（危险/慢操作前后）

    /// 慢操作开始前调用（预写遗言：若进程被杀，下次启动读到残留即知死在这里）
    static func beginSentinel(_ name: String, note: String) {
        UserDefaults.standard.set(
            ["note": note, "at": Date().timeIntervalSince1970] as [String: Any],
            forKey: sentinelPrefix + name
        )
    }

    /// 慢操作成功后调用（删除遗言）
    static func endSentinel(_ name: String) {
        UserDefaults.standard.removeObject(forKey: sentinelPrefix + name)
    }

    /// 启动时检查：残留哨兵 = 上次运行死在对应操作中
    static func leftoverSentinels() -> [String] {
        UserDefaults.standard.dictionaryRepresentation().keys
            .filter { $0.hasPrefix(sentinelPrefix) }
            .map { String($0.dropFirst(sentinelPrefix.count)) }
            .sorted()
    }

    // MARK: 错误持久化

    private static func writeError(title: String, reason: String, stack: [String]) {
        let payload: [String: Any] = [
            "title": title,
            "reason": String(reason.prefix(1200)),
            "stack": Array(stack.prefix(12)),
            "at": Date().timeIntervalSince1970,
        ]
        UserDefaults.standard.set(payload, forKey: lastErrorKey)
    }

    /// 读上次异常（读后即删，避免重复弹窗）
    static func consumeLastError() -> (title: String, reason: String, stack: [String], at: Date)? {
        guard let payload = UserDefaults.standard.dictionary(forKey: lastErrorKey) else { return nil }
        UserDefaults.standard.removeObject(forKey: lastErrorKey)
        let title = payload["title"] as? String ?? "未知错误"
        let reason = payload["reason"] as? String ?? ""
        let stack = payload["stack"] as? [String] ?? []
        let ts = payload["at"] as? TimeInterval ?? 0
        return (title, reason, stack, Date(timeIntervalSince1970: ts))
    }

    /// 上次会话是否异常中断（心跳陈旧 或 未标记健康退出）
    static func lastRunWasAbnormal() -> Bool {
        let clean = UserDefaults.standard.bool(forKey: cleanExitKey)
        return !clean
    }
}

// MARK: - 时间窗事件总线（防重放）
// 迁移自 LiveContainer：跨进程任务带 ±3 秒时间窗，过期即丢弃。
// 这里把同一机制用于 App 内跨场景事件（深链跳转/悬浮窗/前台恢复），
// 避免「陈旧事件」在场景切换后被误执行。

final class TimedEventBus {
    static let shared = TimedEventBus()

    /// 事件有效期（秒）——LC 原版为 3 秒
    static let window: TimeInterval = 3.0

    private struct Payload {
        let userInfo: [String: Any]
        let createdAt: Date
    }

    private var inbox: [String: Payload] = [:]
    private let lock = NSLock()

    /// 投递事件（带时间戳）
    func post(_ name: String, userInfo: [String: Any] = [:]) {
        lock.lock()
        inbox[name] = Payload(userInfo: userInfo, createdAt: Date())
        lock.unlock()
        // 兼容旧的通知机制（UI 层监听者）
        NotificationCenter.default.post(name: Notification.Name(name), object: nil, userInfo: userInfo)
    }

    /// 消费事件：超窗（>3s）直接丢弃返回 nil
    func consume(_ name: String) -> [String: Any]? {
        lock.lock()
        defer { lock.unlock() }
        guard let payload = inbox.removeValue(forKey: name) else { return nil }
        let age = Date().timeIntervalSince(payload.createdAt)
        guard age <= Self.window else {
            // 过期任务丢弃（防重放）
            return nil
        }
        return payload.userInfo
    }

    /// 是否存在待消费的新鲜事件
    func hasFresh(_ name: String) -> Bool {
        lock.lock()
        defer { lock.unlock() }
        guard let payload = inbox[name] else { return false }
        return Date().timeIntervalSince(payload.createdAt) <= Self.window
    }
}
