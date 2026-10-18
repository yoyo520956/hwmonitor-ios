import Darwin
import Foundation

/// CPU 采集器
/// 总使用率：host_statistics64(HOST_CPU_LOAD_INFO) tick 差分（SystemInfoKit 验证过的做法）
/// 每核使用率：host_processor_info(PROCESSOR_CPU_LOAD_INFO)（iOS-System-Services 验证过的做法）
/// CPU 频率：iOS 无公开 API（hw.cpufrequency 无返回）→ 系统限制标注
public final class CPUProvider: @unchecked Sendable, StreamableProvider {
    public let category: MetricCategory = .cpu

    private let lock = NSLock()
    private var previousLoad: host_cpu_load_info = host_cpu_load_info()
    /// 每核 tick 缓存：[核][user,system,idle,nice]
    private var previousPerCore: [[UInt32]] = []
    private var _history: [SamplePoint] = []
    public var history: [SamplePoint] { get { lock.lock(); defer { lock.unlock() }; return _history } }

    public init() {}

    public func resetHistory() {
        lock.lock(); _history.removeAll(); lock.unlock()
    }

    /// 追加采样点（MonitoringEngine 统一节拍调用）
    public func tick() {
        guard let usage = readTotalUsage() else { return }
        lock.lock()
        _history.append(SamplePoint(value: usage))
        if _history.count > 180 { _history.removeFirst(_history.count - 180) }
        lock.unlock()
    }

    // MARK: - 总使用率（tick 差分）

    private func hostLoadInfo() -> host_cpu_load_info? {
        var size: mach_msg_type_number_t = UInt32(
            MemoryLayout<host_cpu_load_info_data_t>.size / MemoryLayout<integer_t>.size
        )
        let hostPort = mach_host_self()
        defer { _ = mach_port_deallocate(mach_task_self_, hostPort) }
        var info = host_cpu_load_info()
        let result = withUnsafeMutablePointer(to: &info) { pointer in
            pointer.withMemoryRebound(to: integer_t.self, capacity: Int(size)) { intPtr in
                host_statistics64(hostPort, HOST_CPU_LOAD_INFO, intPtr, &size)
            }
        }
        return result == KERN_SUCCESS ? info : nil
    }

    /// 返回 0...1 的总使用率（相对上次调用的差分）
    public func readTotalUsage() -> Double? {
        guard let load = hostLoadInfo() else { return nil }
        lock.lock()
        let prev = previousLoad
        previousLoad = load
        lock.unlock()

        let user = Double(load.cpu_ticks.0 &- prev.cpu_ticks.0)
        let system = Double(load.cpu_ticks.1 &- prev.cpu_ticks.1)
        let idle = Double(load.cpu_ticks.2 &- prev.cpu_ticks.2)
        let nice = Double(load.cpu_ticks.3 &- prev.cpu_ticks.3)
        let total = user + system + idle + nice
        guard total > 0 else { return nil }
        return min((user + system + nice) / total, 1.0)
    }

    /// user/system/idle 三分量（差分）
    public func readLoadBreakdown() -> (user: Double, system: Double, idle: Double)? {
        guard let load = hostLoadInfo() else { return nil }
        lock.lock()
        let prev = previousLoad
        previousLoad = load
        lock.unlock()

        let user = Double(load.cpu_ticks.0 &- prev.cpu_ticks.0)
        let system = Double(load.cpu_ticks.1 &- prev.cpu_ticks.1)
        let idle = Double(load.cpu_ticks.2 &- prev.cpu_ticks.2)
        let nice = Double(load.cpu_ticks.3 &- prev.cpu_ticks.3)
        let total = user + system + idle + nice
        guard total > 0 else { return nil }
        return (user / total, system / total, idle / total)
    }

    // MARK: - 每核使用率

    /// 每核使用率（0...1 数组，按核序）
    public func readPerCoreUsage() -> [Double]? {
        var cpuInfo: processor_info_array_t? = nil
        var numCPUInfo: mach_msg_type_number_t = 0
        var numCPUs: natural_t = 0
        let hostPort = mach_host_self()
        defer { _ = mach_port_deallocate(mach_task_self_, hostPort) }

        let result = host_processor_info(
            hostPort, PROCESSOR_CPU_LOAD_INFO, &numCPUs, &cpuInfo, &numCPUInfo
        )
        guard result == KERN_SUCCESS, let info = cpuInfo else { return nil }
        defer {
            let size = vm_size_t(numCPUInfo) * vm_size_t(MemoryLayout<integer_t>.size)
            _ = vm_deallocate(mach_task_self_, vm_address_t(bitPattern: info), size)
        }

        var current: [[UInt32]] = []
        for core in 0..<Int(numCPUs) {
            let base = Int(CPU_STATE_MAX) * core
            current.append([
                UInt32(info[base + Int(CPU_STATE_USER)]),
                UInt32(info[base + Int(CPU_STATE_SYSTEM)]),
                UInt32(info[base + Int(CPU_STATE_IDLE)]),
                UInt32(info[base + Int(CPU_STATE_NICE)]),
            ])
        }

        lock.lock()
        let prev = previousPerCore
        previousPerCore = current
        lock.unlock()

        guard prev.count == current.count else { return nil }

        var usages: [Double] = []
        for i in 0..<current.count {
            let cur = current[i]
            let old = prev[i]
            let user = Double(cur[0] &- old[0])
            let system = Double(cur[1] &- old[1])
            let idle = Double(cur[2] &- old[2])
            let nice = Double(cur[3] &- old[3])
            let total = user + system + idle + nice
            let usage = total > 0 ? min((user + system + nice) / total, 1.0) : 0.0
            usages.append(usage)
        }
        return usages
    }

    // MARK: - MetricsProvider（拆分为小函数，防止 type-check 超时）

    public func collect() -> [MetricCard] {
        var cards: [MetricCard] = []
        let now = Date()
        cards.append(contentsOf: staticCards(now: now))
        cards.append(contentsOf: usageCards(now: now))
        cards.append(contentsOf: perCoreCards(now: now))
        cards.append(Self.frequencyCard())
        return cards
    }

    /// 架构与核心数（静态项）
    private func staticCards(now: Date) -> [MetricCard] {
        let procInfo = ProcessInfo.processInfo
        var machine = SysctlReader.unameFields()["machine"] ?? "unknown"
        if machine.isEmpty { machine = "unknown" }

        let coreCount = procInfo.processorCount
        let activeCores = procInfo.activeProcessorCount
        let coreLimitation: String? = (activeCores != coreCount)
            ? "\(activeCores) active cores"
            : nil

        let archCard = MetricCard(
            id: "cpu.arch", name: "架构", value: machine,
            source: .appleAPI, method: "uname(3) machine 字段", status: .ok,
            collectedAt: now, category: .cpu
        )
        let coresCard = MetricCard(
            id: "cpu.cores", name: "核心数", value: "\(coreCount)",
            numeric: Double(coreCount), unit: "cores",
            source: .appleAPI, method: "ProcessInfo.processorCount",
            limitation: coreLimitation,
            status: .ok, collectedAt: now, category: .cpu
        )
        return [archCard, coresCard, perfCoreCards(now: now)]
    }

    /// 性能核 / 能效核数量（A 系芯片大小核，iOS 15+ 可读）
    private func perfCoreCards(now: Date) -> MetricCard {
        let pCores = SysctlReader.int64("hw.perflevel0.physicalcpu") ?? 0
        let eCores = SysctlReader.int64("hw.perflevel1.physicalcpu") ?? 0
        let total = pCores + eCores
        if total > 0 {
            return MetricCard(
                id: "cpu.cluster", name: "性能核 / 能效核",
                value: "\(pCores) 性能核 + \(eCores) 能效核",
                source: .appleAPI,
                method: "sysctl hw.perflevel0/1.physicalcpu（A 系芯片大小核拓扑）",
                status: .ok, collectedAt: now, category: .cpu
            )
        }
        return MetricCard(
            id: "cpu.cluster", name: "性能核 / 能效核", value: "—",
            source: .appleAPI, method: "sysctl hw.perflevel0/1.physicalcpu",
            limitation: "此设备的系统接口未返回大小核拓扑",
            status: .unavailable, collectedAt: now, category: .cpu
        )
    }

    /// 总使用率与分量
    private func usageCards(now: Date) -> [MetricCard] {
        var cards: [MetricCard] = []
        if let usage = readTotalUsage() {
            cards.append(MetricCard(
                id: "cpu.usage", name: "CPU 使用率（总体）", value: PercentFormat.string(usage),
                numeric: usage, unit: "%",
                source: .computed, method: "host_statistics64(HOST_CPU_LOAD_INFO) 差分计算",
                status: .ok, collectedAt: now, category: .cpu
            ))
        }
        if let breakdown = readLoadBreakdown() {
            cards.append(MetricCard(
                id: "cpu.user", name: "用户态占比", value: PercentFormat.string(breakdown.user),
                numeric: breakdown.user, unit: "%",
                source: .computed, method: "tick 差分 ÷ 总 tick 数", status: .ok,
                collectedAt: now, category: .cpu
            ))
            cards.append(MetricCard(
                id: "cpu.system", name: "系统态占比", value: PercentFormat.string(breakdown.system),
                numeric: breakdown.system, unit: "%",
                source: .computed, method: "tick 差分 ÷ 总 tick 数", status: .ok,
                collectedAt: now, category: .cpu
            ))
        }
        if cards.isEmpty {
            cards.append(MetricCard(
                id: "cpu.usage", name: "CPU 使用率（总体）", value: "—",
                source: .appleAPI, method: "host_statistics64(HOST_CPU_LOAD_INFO) 差分计算",
                limitation: "等待首次采样或系统接口不可用",
                status: .degraded, collectedAt: now, category: .cpu
            ))
        }
        return cards
    }

    /// 每核使用率
    private func perCoreCards(now: Date) -> [MetricCard] {
        guard let perCore = readPerCoreUsage(), !perCore.isEmpty else { return [] }
        let sum = perCore.reduce(0, +)
        let count = Double(perCore.count)
        let avg = sum / count

        var parts: [String] = []
        for (idx, u) in perCore.enumerated() {
            let pct = Int((u * 100).rounded())
            parts.append("C\(idx): \(pct)%")
        }
        let coreText = parts.joined(separator: "  ")

        return [MetricCard(
            id: "cpu.percore", name: "每核使用率", value: coreText,
            numeric: avg, unit: "%",
            source: .computed, method: "host_processor_info(PROCESSOR_CPU_LOAD_INFO) 差分计算",
            status: .ok, collectedAt: now, category: .cpu
        )]
    }

    /// CPU 频率：系统限制卡
    private static func frequencyCard() -> MetricCard {
        MetricCard.restricted(
            "cpu.freq", "CPU 频率",
            reason: "iOS does not expose CPU frequency to apps (hw.cpufrequency is unavailable on iOS). Frequency-based claims in other apps are constants, not measurements.",
            category: .cpu
        )
    }
}
