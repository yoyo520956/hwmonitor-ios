//
//  hwmon_core.c
//  C 采集核心实现（mach / sysctl 直调）
//

#include "hwmon_core.h"

#include <mach/mach.h>
#include <mach/mach_host.h>
#include <mach/processor_info.h>
#include <mach/vm_statistics.h>
#include <pthread.h>
#include <string.h>
#include <sys/sysctl.h>
#include <unistd.h>

// ── 内部状态（pthread 保护，多线程安全） ──
static pthread_mutex_t g_lock = PTHREAD_MUTEX_INITIALIZER;
static host_cpu_load_info_data_t g_prev_load;
static int g_has_prev_load = 0;
static processor_cpu_load_info_t g_prev_percore = NULL;  // 结构体数组（每核一个 cpu_ticks[4]）
static natural_t g_prev_percore_count = 0;
static int g_port_acquire_count = 0;

static host_t hwmon_host_port(void) {
    host_t port = mach_host_self();
    pthread_mutex_lock(&g_lock);
    g_port_acquire_count++;
    pthread_mutex_unlock(&g_lock);
    return port;
}

hwmon_cpu_load_t hwmon_cpu_load_delta(void) {
    hwmon_cpu_load_t r;
    memset(&r, 0, sizeof(r));

    host_t host = hwmon_host_port();
    mach_msg_type_number_t count = HOST_CPU_LOAD_INFO_COUNT;
    host_cpu_load_info_data_t info;
    kern_return_t kr = host_statistics(host, HOST_CPU_LOAD_INFO,
                                       (host_info_t)&info, &count);
    (void)mach_port_deallocate(mach_task_self_, host);
    if (kr != KERN_SUCCESS) {
        r.ok = 0;
        return r;
    }

    pthread_mutex_lock(&g_lock);
    if (g_has_prev_load) {
        host_cpu_load_info_data_t prev = g_prev_load;
        g_prev_load = info;
        pthread_mutex_unlock(&g_lock);

        r.user   = (double)(info.cpu_ticks[CPU_STATE_USER]   - prev.cpu_ticks[CPU_STATE_USER]);
        r.system = (double)(info.cpu_ticks[CPU_STATE_SYSTEM] - prev.cpu_ticks[CPU_STATE_SYSTEM]);
        r.idle   = (double)(info.cpu_ticks[CPU_STATE_IDLE]   - prev.cpu_ticks[CPU_STATE_IDLE]);
        r.nice   = (double)(info.cpu_ticks[CPU_STATE_NICE]   - prev.cpu_ticks[CPU_STATE_NICE]);
        r.total  = r.user + r.system + r.idle + r.nice;
        r.ok = r.total > 0 ? 1 : 0;
    } else {
        g_prev_load = info;
        g_has_prev_load = 1;
        pthread_mutex_unlock(&g_lock);
        r.ok = 0; // 首拍无差分基准
    }
    return r;
}

int hwmon_percore_usage(double *out, int max_count) {
    if (!out || max_count <= 0) return -1;

    host_t host = hwmon_host_port();
    processor_info_array_t cpu_info = NULL;
    mach_msg_type_number_t num_cpu_info = 0;
    natural_t num_cpus = 0;

    kern_return_t kr = host_processor_info(host, PROCESSOR_CPU_LOAD_INFO,
                                           &num_cpus, &cpu_info, &num_cpu_info);
    (void)mach_port_deallocate(mach_task_self_, host);
    if (kr != KERN_SUCCESS || cpu_info == NULL) return -2;
    if ((int)num_cpus > max_count) num_cpus = (natural_t)max_count;

    processor_cpu_load_info_t percore = (processor_cpu_load_info_t)cpu_info;
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
    pthread_mutex_unlock(&g_lock);

    (void)vm_deallocate(mach_task_self_, (vm_address_t)cpu_info,
                        (vm_size_t)(num_cpu_info * sizeof(integer_t)));
    return result;
}

hwmon_vm_stats_t hwmon_vm_stats(void) {
    hwmon_vm_stats_t r;
    memset(&r, 0, sizeof(r));

    host_t host = hwmon_host_port();
    vm_statistics64_data_t stats;
    mach_msg_type_number_t count = HOST_VM_INFO64_COUNT;
    kern_return_t kr = host_statistics64(host, HOST_VM_INFO64,
                                         (host_info64_t)&stats, &count);
    if (kr == KERN_SUCCESS) {
        r.active       = stats.active_count;
        r.inactive     = stats.inactive_count;
        r.speculative  = stats.speculative_count;
        r.wired        = stats.wire_count;
        r.compressed   = stats.compressor_page_count;
        r.purgeable    = stats.purgeable_count;
        r.external     = stats.external_page_count;
        r.free_pages   = stats.free_count;
        r.ok = 1;
    } else {
        // 降级：32 位 host_statistics 版（无 compressed/purgeable/external 语义）
        vm_statistics_data_t legacy;
        mach_msg_type_number_t legacy_count = HOST_VM_INFO_COUNT;
        kern_return_t kr2 = host_statistics(host, HOST_VM_INFO,
                                            (host_info_t)&legacy, &legacy_count);
        if (kr2 == KERN_SUCCESS) {
            r.active      = legacy.active_count;
            r.inactive    = legacy.inactive_count;
            r.wired       = legacy.wire_count;
            r.free_pages  = legacy.free_count;
            r.speculative = legacy.speculative_count;
            r.compressed  = 0;
            r.purgeable   = 0;
            r.external    = 0;
            r.ok = 2; // 2 = 降级路径命中
        }
    }
    (void)mach_port_deallocate(mach_task_self_, host);
    return r;
}

int hwmon_sysctl_u64(const char *name, uint64_t *out) {
    if (!name || !out) return 0;
    uint64_t value = 0;
    size_t size = sizeof(value);
    if (sysctlbyname(name, &value, &size, NULL, 0) == 0) {
        *out = value;
        return 1;
    }
    uint32_t small = 0;
    size = sizeof(small);
    if (sysctlbyname(name, &small, &size, NULL, 0) == 0) {
        *out = (uint64_t)small;
        return 1;
    }
    return 0;
}

int hwmon_sysctl_str(const char *name, char *buf, int bufsize) {
    if (!name || !buf || bufsize <= 0) return 0;
    size_t size = (size_t)bufsize;
    if (sysctlbyname(name, buf, &size, NULL, 0) == 0 && size > 0) {
        buf[bufsize - 1] = '\0';
        return 1;
    }
    return 0;
}

uint64_t hwmon_page_size(void) {
    uint64_t ps = 0;
    if (hwmon_sysctl_u64("hw.pagesize", &ps)) return ps;
    return (uint64_t)sysconf(_SC_PAGESIZE);
}

uint64_t hwmon_physical_memory(void) {
    // 一级：host_info(HOST_BASIC_INFO).max_mem
    host_t host = hwmon_host_port();
    host_basic_info_data_t basic;
    mach_msg_type_number_t count = HOST_BASIC_INFO_COUNT;
    kern_return_t kr = host_info(host, HOST_BASIC_INFO, (host_info_t)&basic, &count);
    (void)mach_port_deallocate(mach_task_self_, host);
    if (kr == KERN_SUCCESS && basic.max_mem > 0) {
        return (uint64_t)basic.max_mem;
    }
    // 二级：sysctl hw.memsize
    uint64_t memsize = 0;
    if (hwmon_sysctl_u64("hw.memsize", &memsize)) return memsize;
    // 三级：失败返回 0（调用方继续降级到 ProcessInfo.physicalMemory）
    return 0;
}

int hwmon_core_probe(void) {
    pthread_mutex_lock(&g_lock);
    int n = g_port_acquire_count;
    pthread_mutex_unlock(&g_lock);
    return n;
}
