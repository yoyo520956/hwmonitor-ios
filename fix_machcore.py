#!/usr/bin/env python3
"""把 MachCore 的 cpuUsage/cpuBreakdown 合并为单入口 cpuSample（防差分快照连续推进）"""
p = '/var/minis/workspace/hwmon/app/Sources/Core/MachCore.swift'
s = open(p, encoding='utf-8').read()

old_marker = '/// CPU 总负载差分（C 核心）→ 使用率 0...1'
idx = s.find(old_marker)
assert idx > 0, "锚点未找到"
end_marker = '    /// 每核使用率（C 核心）'
end = s.find(end_marker, idx)
assert end > idx, "结束锚点未找到"

new_block = '''/// CPU 单次采样（唯一入口）：一次 mach 调用取全部字段，避免差分快照被连续推进
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

'''
s = s[:idx] + new_block + s[end:]
open(p, 'w', encoding='utf-8').write(s)
print("done, cpuUsage/cpuBreakdown → cpuSample")
print("cpuUsage 残留:", s.count('func cpuUsage'), "| cpuSample:", s.count('func cpuSample'))
