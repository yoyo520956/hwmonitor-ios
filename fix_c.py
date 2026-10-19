#!/usr/bin/env python3
"""修正 hwmon_core.c 的三处类型错误：
1. processor_cpu_load_info_t 是结构体指针（不是扁平 integer_t 数组）→ 用 .cpu_ticks[]
2. host_basic_info 字段名 max_memory → max_mem
3. 快照分配字节数按结构体算"""

p = '/var/minis/workspace/hwmon/app/Sources/Core/hwmon_core.c'
s = open(p, encoding='utf-8').read()

# ── 1. 全局快照类型 ──
s = s.replace(
    'static processor_cpu_load_info_t g_prev_percore = NULL;',
    'static processor_cpu_load_info_t g_prev_percore = NULL;  // 结构体数组（每核一个 cpu_ticks[4]）'
)

# ── 2. percore 逻辑整体替换 ──
old = '''    int result = -3;
    pthread_mutex_lock(&g_lock);
    if (g_prev_percore != NULL && g_prev_percore_count == num_cpus) {
        for (natural_t i = 0; i < num_cpus; i++) {
            natural_t base = i * CPU_STATE_MAX;
            uint32_t cur_user   = (uint32_t)cpu_info[base + CPU_STATE_USER];
            uint32_t cur_system = (uint32_t)cpu_info[base + CPU_STATE_SYSTEM];
            uint32_t cur_idle   = (uint32_t)cpu_info[base + CPU_STATE_IDLE];
            uint32_t cur_nice   = (uint32_t)cpu_info[base + CPU_STATE_NICE];
            uint32_t pv_user    = (uint32_t)g_prev_percore[base + CPU_STATE_USER];
            uint32_t pv_system  = (uint32_t)g_prev_percore[base + CPU_STATE_SYSTEM];
            uint32_t pv_idle    = (uint32_t)g_prev_percore[base + CPU_STATE_IDLE];
            uint32_t pv_nice    = (uint32_t)g_prev_percore[base + CPU_STATE_NICE];

            double user   = (double)(cur_user   - pv_user);
            double system = (double)(cur_system - pv_system);
            double idle   = (double)(cur_idle   - pv_idle);
            double nice   = (double)(cur_nice   - pv_nice);
            double total  = user + system + idle + nice;
            out[i] = total > 0 ? (user + system + nice) / total : 0.0;
        }
        result = (int)num_cpus;
    }

    // 保存本次快照作下次基准
    if (g_prev_percore != NULL) {
        vm_deallocate(mach_task_self_, (vm_address_t)g_prev_percore,
                      (vm_size_t)(g_prev_percore_count * CPU_STATE_MAX * sizeof(integer_t)));
        g_prev_percore = NULL;
    }
    vm_size_t bytes = (vm_size_t)(num_cpus * CPU_STATE_MAX * sizeof(integer_t));
    processor_cpu_load_info_t snapshot = NULL;
    if (vm_allocate(mach_task_self_, (vm_address_t *)&snapshot, bytes, VM_FLAGS_ANYWHERE) == KERN_SUCCESS) {
        memcpy(snapshot, cpu_info, bytes);
        g_prev_percore = snapshot;
        g_prev_percore_count = num_cpus;
    } else {
        g_prev_percore_count = 0;
    }
    pthread_mutex_unlock(&g_lock);'''

new = '''    processor_cpu_load_info_t percore = (processor_cpu_load_info_t)cpu_info;
    vm_size_t snapshot_bytes = (vm_size_t)(num_cpus * sizeof(processor_cpu_load_info));

    int result = -3;
    pthread_mutex_lock(&g_lock);
    if (g_prev_percore != NULL && g_prev_percore_count == num_cpus) {
        for (natural_t i = 0; i < num_cpus; i++) {
            uint32_t cur_user   = (uint32_t)percore[i].cpu_ticks[CPU_STATE_USER];
            uint32_t cur_system = (uint32_t)percore[i].cpu_ticks[CPU_STATE_SYSTEM];
            uint32_t cur_idle   = (uint32_t)percore[i].cpu_ticks[CPU_STATE_IDLE];
            uint32_t cur_nice   = (uint32_t)percore[i].cpu_ticks[CPU_STATE_NICE];
            uint32_t pv_user    = (uint32_t)g_prev_percore[i].cpu_ticks[CPU_STATE_USER];
            uint32_t pv_system  = (uint32_t)g_prev_percore[i].cpu_ticks[CPU_STATE_SYSTEM];
            uint32_t pv_idle    = (uint32_t)g_prev_percore[i].cpu_ticks[CPU_STATE_IDLE];
            uint32_t pv_nice    = (uint32_t)g_prev_percore[i].cpu_ticks[CPU_STATE_NICE];

            double user   = (double)(cur_user   - pv_user);
            double system = (double)(cur_system - pv_system);
            double idle   = (double)(cur_idle   - pv_idle);
            double nice   = (double)(cur_nice   - pv_nice);
            double total  = user + system + idle + nice;
            out[i] = total > 0 ? (user + system + nice) / total : 0.0;
        }
        result = (int)num_cpus;
    }

    // 保存本次快照作下次基准
    if (g_prev_percore != NULL) {
        vm_deallocate(mach_task_self_, (vm_address_t)g_prev_percore,
                      (vm_size_t)(g_prev_percore_count * sizeof(processor_cpu_load_info)));
        g_prev_percore = NULL;
    }
    processor_cpu_load_info_t snapshot = NULL;
    if (vm_allocate(mach_task_self_, (vm_address_t *)&snapshot, snapshot_bytes, VM_FLAGS_ANYWHERE) == KERN_SUCCESS) {
        memcpy(snapshot, percore, snapshot_bytes);
        g_prev_percore = snapshot;
        g_prev_percore_count = num_cpus;
    } else {
        g_prev_percore_count = 0;
    }
    pthread_mutex_unlock(&g_lock);'''
assert old in s, "percore 块锚点未找到"
s = s.replace(old, new)

# ── 3. host_basic_info 字段名 ──
s = s.replace('basic.max_memory > 0', 'basic.max_mem > 0')
s = s.replace('return (uint64_t)basic.max_memory;', 'return (uint64_t)basic.max_mem;')

open(p, 'w', encoding='utf-8').write(s)
print("C 修正完成")
print("残留 max_memory:", s.count('max_memory'), "| 残留 cpu_info[base:", s.count('cpu_info[base'))
print("percore[i].cpu_ticks:", s.count('percore[i].cpu_ticks'), "| max_mem:", s.count('max_mem'))
