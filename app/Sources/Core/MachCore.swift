import Foundation

// MARK: - C 采集核心的 Swift 封装（混编层）
// LiveContainer 技法：重活下沉 C，Swift 只做编排与降级决策。
// 每级返回 provenance（命中路径），供详情页与自检页展示。

/// 降级链命中路径（显示在"采集方法"中，让数据来源可追溯）
enum ProvenanceLevel: Int, Comparable {
    case primary = 1      // 首选路径（C 核心 / 最优 API）
    case secondary = 2    // 一级降级
    case tertiary = 3     // 二级降级
    case none = 99        // 全部失败

    static func < (lhs: ProvenanceLevel, rhs: ProvenanceLevel) -> Bool {
        lhs.rawValue < rhs.rawValue
    }

    var label: String {
        switch self {
        case .primary: return "首选路径"
        case .secondary: return "降级路径 2"
        case .tertiary: return "降级路径 3"
        case .none: return "无可用路径"
        }
    }

    var isDegraded: Bool { self != .primary }
}

/// 一次采集的结果 + 来源链
struct Traced<T> {
    let value: T
    let level: ProvenanceLevel
    let path: String   // 命中的具体路径描述
}

// MARK: C 核心桥

enum MachCore {
    /// CPU 单次采样（唯一入口）：一次 mach 调用取全部字段，避免差分快照被连续推进
    struct CPUSample {
        let usage: Double   // 0...1
        let user: Double    // 0...1
        let system: Double  // 0...1
        let idle: Double    // 0...1
    }

    static func cpuSample() -> CPUSample? {
        let load = hwmon_cpu_load_delta()
        guard load.ok == 1, load.total > 0 else { return nil }
        return CPUSample(
            usage: min((load.user + load.system + load.nice) / load.total, 1.0),
            user: load.user / load.total,
            system: load.system / load.total,
            idle: load.idle / load.total
        )
    }

    /// 每核使用率（C 核心）
    static func perCoreUsage(maxCores: Int = 16) -> [Double]? {
        var buffer = [Double](repeating: 0, count: maxCores)
        let n = buffer.withUnsafeMutableBufferPointer { ptr -> Int in
            Int(hwmon_percore_usage(ptr.baseAddress, Int32(maxCores)))
        }
        guard n > 0 else { return nil }
        return Array(buffer.prefix(n))
    }

    /// VM 分类统计 + 页大小
    static func vmStats() -> (stats: (active: Double, inactive: Double, speculative: Double,
                                     wired: Double, compressed: Double, purgeable: Double,
                                     external: Double, free: Double),
                              pageSize: Double, degraded: Bool)? {
        let s = hwmon_vm_stats()
        guard s.ok != 0 else { return nil }
        let page = Double(hwmon_page_size())
        let stats = (
            active: Double(s.active) * page,
            inactive: Double(s.inactive) * page,
            speculative: Double(s.speculative) * page,
            wired: Double(s.wired) * page,
            compressed: Double(s.compressed) * page,
            purgeable: Double(s.purgeable) * page,
            external: Double(s.external) * page,
            free: Double(s.free_pages) * page
        )
        return (stats, page, s.ok == 2)
    }

    /// 物理内存总量（C 核心三级降级：host_info → sysctl → 0）
    static func physicalMemory() -> Traced<Double>? {
        let mem = hwmon_physical_memory()
        if mem > 0 {
            // 区分是 host_info 命中还是 sysctl 命中
            var sysctlMem: UInt64 = 0
            let isSysctl = hwmon_sysctl_u64("hw.memsize", &sysctlMem) == 1
            let sameValue = isSysctl && sysctlMem == mem
            // host_info 与 hw.memsize 通常相同，无法完全区分；以 sysctl 可读状态描述
            let path = sameValue
                ? "C 核心 host_info(HOST_BASIC_INFO).max_mem（sysctl hw.memsize 交叉验证一致）"
                : "C 核心 host_info(HOST_BASIC_INFO).max_mem"
            return Traced(value: Double(mem), level: .primary, path: path)
        }
        var memsize: UInt64 = 0
        if hwmon_sysctl_u64("hw.memsize", &memsize) == 1, memsize > 0 {
            return Traced(value: Double(memsize), level: .secondary, path: "降级：C 核心 sysctl hw.memsize")
        }
        return nil
    }

    /// sysctl u64（C 核心）
    static func sysctlU64(_ name: String) -> UInt64? {
        var value: UInt64 = 0
        let ok = name.withCString { hwmon_sysctl_u64($0, &value) }
        return ok == 1 ? value : nil
    }

    /// sysctl 字符串（C 核心）
    static func sysctlString(_ name: String, maxLength: Int = 256) -> String? {
        var buffer = [CChar](repeating: 0, count: maxLength)
        let ok = name.withCString { cname in
            buffer.withUnsafeMutableBufferPointer { ptr in
                hwmon_sysctl_str(cname, ptr.baseAddress, Int32(maxLength))
            }
        }
        guard ok == 1 else { return nil }
        let s = String(cString: buffer)
        return s.isEmpty ? nil : s
    }

    /// 自检：C 核心内部 host port 获取次数（>0 表示核心可正常调用）
    static var probeCallCount: Int { Int(hwmon_core_probe()) }
}
