//
//  hwmon_core.h
//  硬件监测 Pro — C 采集核心（LiveContainer 混编技法：高频 mach 调用下沉到 C 层）
//
//  设计要点（迁移自 LiveContainer 工程实践）：
//  - 高频 tick 采集（CPU 差分、每核差分、VM 统计）用 C 直接调 mach API，
//    免去 Swift ↔ mach 的桥接与元数据开销；
//  - 每个接口返回 ok 标志：调用方据此走降级链下一级（nil 检测推进原则）；
//  - 内部状态（上次 tick 快照）用 pthread_mutex 保护，多线程安全。
//

#ifndef HWMON_CORE_H
#define HWMON_CORE_H

#include <stdint.h>

#ifdef __cplusplus
extern "C" {
#endif

/// CPU 总负载差分结果（百分比已归一到 0...1 计算前的原始 tick 数）
typedef struct {
    double user;    // 用户态 tick 差
    double system;  // 系统态 tick 差
    double idle;    // 空闲 tick 差
    double nice;    // nice tick 差
    double total;   // user+system+idle+nice
    int    ok;      // 1 = 成功；0 = mach 调用失败（走降级）
} hwmon_cpu_load_t;

/// VM 统计（页数，调用方乘页大小）
typedef struct {
    uint64_t active;
    uint64_t inactive;
    uint64_t speculative;
    uint64_t wired;
    uint64_t compressed;
    uint64_t purgeable;
    uint64_t external;
    uint64_t free_pages;
    int      ok;
} hwmon_vm_stats_t;

/// CPU 总负载差分（内部保存上次快照；首次调用返回 ok=0 之外的 total=0，由调用方忽略首拍）
hwmon_cpu_load_t hwmon_cpu_load_delta(void);

/// 每核使用率写入 out（0...1），返回写入的核数；<0 表示失败（走降级）
int hwmon_percore_usage(double *out, int max_count);

/// VM 统计（vm_statistics64，失败自动降级 host_statistics 32 位版）
hwmon_vm_stats_t hwmon_vm_stats(void);

/// sysctl 读取（成功返回 1，值写入 *out）
int hwmon_sysctl_u64(const char *name, uint64_t *out);

/// sysctl 字符串（成功返回 1，写入 buf）
int hwmon_sysctl_str(const char *name, char *buf, int bufsize);

/// 系统页大小（字节）
uint64_t hwmon_page_size(void);

/// 物理内存总量（多级降级：host_info max_mem → sysctl hw.memsize → 0 表示失败）
uint64_t hwmon_physical_memory(void);

/// 诊断：返回本核心内部已完成的 host port 获取次数（用于自检报告）
int hwmon_core_probe(void);

#ifdef __cplusplus
}
#endif

#endif /* HWMON_CORE_H */
