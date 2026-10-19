#!/usr/bin/env python3
"""修复 CPU 降级路径：swiftTotalUsage + swiftLoadBreakdown 连续调用会互相吞噬差分基准
→ 合并为单次读取 swiftSample()"""
p = '/var/minis/workspace/hwmon/app/Sources/Providers/CPUProvider.swift'
s = open(p, encoding='utf-8').read()

# 1. sampleOnce 的降级分支
old = '''        // 降级：Swift 路径
        cCoreHealthy = false
        guard let usage = swiftTotalUsage(), let bd = swiftLoadBreakdown() else { return nil }
        lock.lock(); lastUsagePath = "降级：纯 Swift host_statistics64 差分"; lock.unlock()
        return MachCore.CPUSample(usage: usage, user: bd.user, system: bd.system, idle: bd.idle)'''
new = '''        // 降级：Swift 路径（单次读取，避免连续调用吞噬差分基准）
        cCoreHealthy = false
        guard let sample = swiftSample() else { return nil }
        lock.lock(); lastUsagePath = "降级：纯 Swift host_statistics64 差分"; lock.unlock()
        return sample'''
assert old in s, "sampleOnce 降级分支锚点未找到"
s = s.replace(old, new)

# 2. 用 swiftSample 替换 swiftTotalUsage + swiftLoadBreakdown 两个函数
start = s.find('    private func swiftTotalUsage() -> Double? {')
end = s.find('    /// 每核使用率：C 核心优先')
assert start > 0 and end > start, "降级函数块锚点未找到"

new_block = '''    private func swiftSample() -> MachCore.CPUSample? {
        guard let load = hostLoadInfo() else { return nil }
        lock.lock()
        guard hasPrevLoad else {
            previousLoad = load
            hasPrevLoad = true
            lock.unlock()
            return nil   // 首拍只建立基准
        }
        let prev = previousLoad
        previousLoad = load
        lock.unlock()

        let user = Double(load.cpu_ticks.0 &- prev.cpu_ticks.0)
        let system = Double(load.cpu_ticks.1 &- prev.cpu_ticks.1)
        let idle = Double(load.cpu_ticks.2 &- prev.cpu_ticks.2)
        let nice = Double(load.cpu_ticks.3 &- prev.cpu_ticks.3)
        let total = user + system + idle + nice
        guard total > 0 else { return nil }
        return MachCore.CPUSample(
            usage: min((user + system + nice) / total, 1.0),
            user: user / total,
            system: system / total,
            idle: idle / total
        )
    }

'''
s = s[:start] + new_block + s[end:]

open(p, 'w', encoding='utf-8').write(s)
print("修复完成")
print("swiftTotalUsage 残留:", s.count('swiftTotalUsage'),
      "| swiftLoadBreakdown 残留:", s.count('swiftLoadBreakdown'),
      "| swiftSample:", s.count('swiftSample'))
