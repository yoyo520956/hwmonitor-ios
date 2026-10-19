#!/usr/bin/env python3
"""MemoryProvider 接入 C 核心 + 降级链（C 优先 / Swift 兜底，provenance 记录）"""
p = '/var/minis/workspace/hwmon/app/Sources/Providers/MemoryProvider.swift'
s = open(p, encoding='utf-8').read()
orig = s

# ── 1. pageSize：C 核心优先 ──
old = '''    private var pageSize: Double {
        var size: vm_size_t = 0
        let hostPort = mach_host_self()
        defer { _ = mach_port_deallocate(mach_task_self_, hostPort) }
        _ = host_page_size(hostPort, &size)
        return Double(size)
    }'''
new = '''    private var pageSize: Double {
        // C 核心优先（hwmon_page_size → sysctl hw.pagesize）
        let cPage = Double(hwmon_page_size())
        if cPage > 0 { return cPage }
        var size: vm_size_t = 0
        let hostPort = mach_host_self()
        defer { _ = mach_port_deallocate(mach_task_self_, hostPort) }
        _ = host_page_size(hostPort, &size)
        return Double(size)
    }'''
assert old in s, "pageSize 锚点未找到"
s = s.replace(old, new)

# ── 2. readPhysicalMemoryBytes：三级降级链 ──
old = '''    public func readPhysicalMemoryBytes() -> Double {
        let hostPort = mach_host_self()
        defer { _ = mach_port_deallocate(mach_task_self_, hostPort) }
        var info = host_basic_info()
        var count = mach_msg_type_number_t(
            MemoryLayout<host_basic_info_data_t>.size / MemoryLayout<integer_t>.size
        )
        let result = withUnsafeMutablePointer(to: &info) { ptr in
            ptr.withMemoryRebound(to: integer_t.self, capacity: Int(count)) { intPtr in
                host_info(hostPort, HOST_BASIC_INFO, intPtr, &count)
            }
        }
        guard result == KERN_SUCCESS else { return 0 }
        return Double(info.max_mem)
    }'''
new = '''    /// 物理内存总量（三级降级链：C 核心 host_info → Swift host_info → ProcessInfo）
    public func readPhysicalMemoryBytes() -> Double {
        let chain = FallbackChain<Double>("mem.total")
            .then("C 核心 host_info(HOST_BASIC_INFO).max_mem（混编）") {
                MachCore.physicalMemory()?.value
            }
            .then("Swift host_info(HOST_BASIC_INFO).max_mem") {
                let v = MemoryProvider.swiftPhysicalMemory()
                return v > 0 ? v : nil
            }
            .then("ProcessInfo.physicalMemory") {
                let v = Double(ProcessInfo.processInfo.physicalMemory)
                return v > 0 ? v : nil
            }
        guard let result = chain.run() else { return 0 }
        lastTotalPath = result.path
        return result.value
    }

    /// 物理内存总量采集路径（供卡片展示 provenance）
    private var lastTotalPath: String = "host_info(HOST_BASIC_INFO).max_mem"

    private static func swiftPhysicalMemory() -> Double {
        let hostPort = mach_host_self()
        defer { _ = mach_port_deallocate(mach_task_self_, hostPort) }
        var info = host_basic_info()
        var count = mach_msg_type_number_t(
            MemoryLayout<host_basic_info_data_t>.size / MemoryLayout<integer_t>.size
        )
        let result = withUnsafeMutablePointer(to: &info) { ptr in
            ptr.withMemoryRebound(to: integer_t.self, capacity: Int(count)) { intPtr in
                host_info(hostPort, HOST_BASIC_INFO, intPtr, &count)
            }
        }
        guard result == KERN_SUCCESS else { return 0 }
        return Double(info.max_mem)
    }

    /// VM 分类快照（统一中间结构：页数 + 命中路径）
    private struct VMSnapshot {
        let active: Double
        let inactive: Double
        let speculative: Double
        let wired: Double
        let compressed: Double
        let purgeable: Double
        let external: Double
        let free: Double
        let path: String
    }

    /// VM 统计（双路径：C 核心 vm_statistics64 → Swift vm_statistics64）
    private func readVMSnapshot() -> VMSnapshot? {
        if let c = MachCore.vmStats() {
            let path = c.degraded
                ? "降级：C 核心 32 位 host_statistics(HOST_VM_INFO)"
                : "C 核心 vm_statistics64（混编）"
            return VMSnapshot(
                active: c.stats.active, inactive: c.stats.inactive,
                speculative: c.stats.speculative, wired: c.stats.wired,
                compressed: c.stats.compressed, purgeable: c.stats.purgeable,
                external: c.stats.external, free: c.stats.free, path: path
            )
        }
        guard let stats = readVMStatistics64() else { return nil }
        return VMSnapshot(
            active: Double(stats.active_count), inactive: Double(stats.inactive_count),
            speculative: Double(stats.speculative_count), wired: Double(stats.wire_count),
            compressed: Double(stats.compressor_page_count), purgeable: Double(stats.purgeable_count),
            external: Double(stats.external_page_count), free: Double(stats.free_count),
            path: "降级：Swift vm_statistics64"
        )
    }'''
assert old in s, "readPhysicalMemoryBytes 锚点未找到"
s = s.replace(old, new)

# ── 3. collect：物理内存卡带 provenance ──
old = '''                source: .appleAPI, method: "host_info(HOST_BASIC_INFO).max_mem",
                status: .ok, collectedAt: now, category: .memory
            ))
        }'''
new = '''                source: .appleAPI, method: lastTotalPath,
                status: .ok, collectedAt: now, category: .memory
            ))
        }'''
assert old in s, "物理内存卡锚点未找到"
s = s.replace(old, new)

# ── 4. collect：VM 统计改用快照 ──
old = '''        if let stats = readVMStatistics64() {
            let active = Double(stats.active_count) * page
            let inactive = Double(stats.inactive_count) * page
            let speculative = Double(stats.speculative_count) * page
            let wired = Double(stats.wire_count) * page
            let compressed = Double(stats.compressor_page_count) * page
            let purgeable = Double(stats.purgeable_count) * page
            let external = Double(stats.external_page_count) * page
            let free = Double(stats.free_count) * page'''
new = '''        if let snap = readVMSnapshot() {
            let active = snap.active * page
            let inactive = snap.inactive * page
            let speculative = snap.speculative * page
            let wired = snap.wired * page
            let compressed = snap.compressed * page
            let purgeable = snap.purgeable * page
            let external = snap.external * page
            let free = snap.free * page
            let vmPath = snap.path'''
assert old in s, "VM 统计锚点未找到"
s = s.replace(old, new)

# ── 5. VM 相关 method 字符串带上 provenance ──
s = s.replace('method: "vm_statistics64 分类求和 × 页大小（app 段 + 压力段）"',
              'method: "\\(vmPath) 分类求和 × 页大小（app 段 + 压力段）"')
s = s.replace('method: "vm_statistics64 wired 页数（内核锁定不可换出）"',
              'method: "\\(vmPath) wired 页数（内核锁定不可换出）"')
s = s.replace('method: "vm_statistics64 active 页数（最近使用）"',
              'method: "\\(vmPath) active 页数（最近使用）"')
s = s.replace('method: "vm_statistics64 inactive 页数（可回收缓存）"',
              'method: "\\(vmPath) inactive 页数（可回收缓存）"')

open(p, 'w', encoding='utf-8').write(s)
print("MemoryProvider 接入完成")
print("检查:", "readVMSnapshot" in s, "| hwmon_page_size:", "hwmon_page_size" in s, "| vmPath:", s.count("vmPath"))
