#!/usr/bin/env python3
"""硬核监测Pro v2.0 全面汉化：精确引号字面量替换，不碰任何标识符。"""
import re, glob, sys

M = {
  # ── 状态徽章 ──
  "OK": "正常", "PARTIAL": "部分", "PERM": "权限",
  "Authorized": "已授权", "Denied": "已拒绝", "Restricted": "受限",
  "Not Requested": "未请求", "Limited": "受限访问",
  "Available": "可用", "Unavailable": "不可用", "Unknown": "未知",
  "Nominal": "正常", "Fair": "一般", "Serious": "严重", "Critical": "危急",
  # ── 来源 ──
  "Apple Official API": "Apple 官方 API", "Real Sampling": "真实采样计算",
  "Derived": "规则推导", "Not Exposed": "系统未开放",
  # ── 分类标题 ──
  "Overview": "总览", "Hardware": "硬件", "Monitor": "监控",
  "Sensors": "传感器", "System": "系统", "Settings": "设置",
  "Memory": "内存", "Storage": "存储", "Battery": "电池", "Thermal": "温度",
  "Network": "网络", "Display": "显示", "Camera": "相机", "Privacy": "隐私",
  "Device": "设备", "Diagnostics": "诊断",
  # ── 通用 UI ──
  "Yes": "是", "No": "否", "On": "开", "Off": "关", "Back": "返回",
  "Close": "关闭", "Share": "分享", "Refresh": "刷新", "Pause": "暂停",
  "Resume": "继续", "Results": "结果", "Report": "报告", "Version": "版本",
  "Value": "数值", "Time": "时间", "Format": "格式", "Interval": "间隔",
  "Text": "文本", "JSON": "JSON", "About": "关于",
  "While Using": "使用期间", "Always": "始终", "Full Access": "完全访问",
  "Simulator": "模拟器", "Physical Device": "真机", "Front": "前置",
  "Open Settings": "打开设置", "Data Policy": "数据政策", "All local": "全部本地",
  "Open-Source Notices": "开源致谢",
  # ── 采样 ──
  "Sampling Interval": "采样间隔", "Auto-refresh": "自动刷新",
  "Live Sensor Readings": "传感器实时读数", "Sampling paused": "采样已暂停",
  "No data available": "暂无数据", "Collecting samples…": "正在采集样本…",
  "Running…": "运行中…", "Clear History": "清除历史",
  "1 second": "1 秒", "5 seconds": "5 秒", "30 seconds": "30 秒",
  "1 / current update interval (configurable up to hardware max)":
      "1 / 当前刷新间隔（上限为硬件最大值）",
  # ── 设备模块 ──
  "Device Model": "设备型号标识", "Marketing Name": "市场名称",
  "OS Build": "系统版本号 (Build)", "Kernel Release": "内核版本",
  "System Uptime": "系统运行时长",
  "sysctl hw.machine": "系统接口 sysctl（hw.machine）",
  "sysctl kern.osversion": "系统接口 sysctl（kern.osversion）",
  "uname(3) machine field": "uname(3) machine 字段",
  "uname(3) release (Darwin kernel version)": "uname(3) release（Darwin 内核版本）",
  "hw.machine → mapped model table (DeviceKit-style)":
      "hw.machine → 自建型号映射表（DeviceKit 思路）",
  "Simulator reports CPU architecture, not device model":
      "模拟器上报的是 CPU 架构而非设备型号",
  "Model-identifier mapping table concept (table rebuilt independently).":
      "型号标识映射表思路（表内容独立重建）",
  # ── CPU 模块 ──
  "CPU Usage (Total)": "CPU 使用率（总体）", "CPU Usage": "CPU 使用率",
  "User Time": "用户态占比", "System Time": "系统态占比",
  "Per-Core Usage": "每核使用率", "CPU Cores": "核心数",
  "CPU Frequency": "CPU 频率", "Architecture": "架构",
  "host_statistics64(HOST_CPU_LOAD_INFO) tick delta":
      "host_statistics64(HOST_CPU_LOAD_INFO) 差分计算",
  "host_processor_info(PROCESSOR_CPU_LOAD_INFO) delta":
      "host_processor_info(PROCESSOR_CPU_LOAD_INFO) 差分计算",
  "Tick delta / total ticks": "tick 差分 ÷ 总 tick 数",
  "NSProcessInfo.processorCount": "ProcessInfo.processorCount",
  "First sample pending or host API unavailable": "等待首次采样或系统接口不可用",
  "No public API. Only qualitative thermal state (see Thermal module).":
      "无公开 API，仅有定性热状态（见温度模块）",
  # ── 内存模块 ──
  "Memory In Use": "已用内存", "Memory Pressure": "内存压力",
  "App Memory": "应用内存", "Physical Memory": "物理内存",
  "This App (Phys Footprint)": "本 App 占用 (phys_footprint)",
  "This App Memory (phys_footprint)": "本 App 内存 (phys_footprint)",
  "Compressed": "已压缩", "Used": "已用", "Free": "可用",
  "host_info(HOST_BASIC_INFO).max_mem": "host_info(HOST_BASIC_INFO).max_mem",
  "task_info(TASK_VM_INFO).phys_footprint": "task_info(TASK_VM_INFO).phys_footprint",
  "vm_statistics64.compressor_page_count": "vm_statistics64 压缩器页数",
  "vm_statistics64.free_count": "vm_statistics64 空闲页数",
  "vm_statistics64.wire_count": "vm_statistics64 wired 页数",
  "(wired + compressed) / max_mem": "公式：(wired + compressed) / max_mem",
  "active + inactive + speculative - purgeable - external (pages × page size)":
      "公式：active + inactive + speculative - purgeable - external（页数 × 页大小）",
  "Measures this app only; iOS does not expose other apps' memory":
      "仅统计本 App；iOS 不开放其他 App 的内存占用",
  # ── 存储模块 ──
  "Total Capacity": "总容量", "Usage Ratio": "使用率",
  "Storage Usage Ratio": "存储使用率",
  "URL.resourceValues(volumeTotalCapacity)": "URL.resourceValues(volumeTotalCapacity)",
  "volumeAvailableCapacityForImportantUsage": "volumeAvailableCapacityForImportantUsage",
  "Filesystem capacity; differs slightly from marketing storage size":
      "文件系统口径，与营销容量略有差异",
  "Volume resource values unavailable": "卷资源信息不可用",
  "used / total": "公式：used / total",
  "total - available": "公式：total - available",
  # ── 电池与温度 ──
  "Battery Level": "电量", "Charging State": "充电状态",
  "Battery Health (Maximum Capacity)": "电池健康度（最大容量）",
  "Cycle Count": "循环次数", "Battery Temperature": "电池温度",
  "Voltage / Current": "电压 / 电流", "Thermal State": "热状态",
  "Battery & Thermal": "电池与温度",
  "Charging": "充电中", "Unplugged": "未充电", "Wired": "有线充电",
  "UIDevice.batteryLevel (granularity ≈ 1-5%)": "UIDevice.batteryLevel（精度约 1-5%）",
  "Battery level not reported (simulator or hardware off)":
      "未上报电量（模拟器或硬件不可用）",
  "Qualitative 4-level system state only; numeric °C values are not exposed":
      "系统仅提供 4 级定性状态，不开放具体温度数值",
  "No public iOS API": "无公开 iOS API",
  "Not exposed by any public iOS API.": "任何公开 iOS API 均不提供此数据",
  "Not exposed by public APIs on iOS.": "iOS 公开 API 未开放此数据",
  # ── GPU ──
  "GPU Name": "GPU 名称", "GPU Utilization": "GPU 利用率",
  "Unified Memory": "统一内存", "Recommended Max Working Set": "建议最大工作集",
  "Metal GPU Families": "Metal 支持家族", "Ray Tracing": "光线追踪",
  "MTLDevice.name (e.g. Apple A15 GPU)": "MTLDevice.name（如 Apple A15 GPU）",
  "MTLDevice.supportsFamily enumeration": "MTLDevice.supportsFamily 枚举",
  "MTLDevice feature flag": "MTLDevice 特性标志",
  "32-bit Float Filtering": "32 位浮点过滤", "Function Pointers": "函数指针",
  "No default Metal device (simulator may not report a GPU)":
      "无默认 Metal 设备（模拟器可能无 GPU）",
  # ── 网络 ──
  "Connection": "连接", "Local IPv4": "本机 IPv4",
  "Network Throughput (all interfaces)": "网络吞吐（全部接口）",
  "Total Received": "累计接收", "Total Sent": "累计发送",
  "Cellular": "蜂窝网络", "Ethernet": "以太网",
  "Offline": "离线", "Expensive Link": "计费网络（蜂窝/热点）",
  "Low Data Mode": "低数据模式", "Low Power Mode": "低电量模式",
  "NWPathMonitor.pathUpdateHandler": "NWPathMonitor.pathUpdateHandler",
  "NWPath.isConstrained": "NWPath.isConstrained",
  "NWPath.isExpensive": "NWPath.isExpensive",
  "getifaddrs + getnameinfo(NI_NUMERICHOST)": "getifaddrs + getnameinfo(NI_NUMERICHOST)",
  "Σ ifa_data.ifi_ibytes across non-loopback interfaces (since boot)":
      "Σ ifa_data.ifi_ibytes（非回环接口，开机起累计）",
  "Σ ifa_data.ifi_obytes across non-loopback interfaces (since boot)":
      "Σ ifa_data.ifi_obytes（非回环接口，开机起累计）",
  "Local network address only; not the public/VPN exit IP":
      "仅局域网地址，不含公网出口/VPN IP",
  # ── 显示 ──
  "Brightness": "屏幕亮度", "Native Resolution": "物理分辨率",
  "Logical Resolution": "逻辑分辨率", "Scale Factor": "缩放系数",
  "Max Refresh Rate": "最大刷新率", "24-hour Time": "24 小时制",
  "Calendar Type": "日历类型", "Time Zone": "时区", "Region": "地区",
  "Preferred Language": "首选语言",
  "Locale dateFormat template 'j' inspection": "Locale dateFormat 模板 'j' 检查",
  # ── 相机 ──
  "Cameras Found": "发现的摄像头", "Camera Hardware": "相机硬件",
  "TrueDepth": "深感 (TrueDepth)", "Depth camera": "景深镜头",
  "Cameras": "摄像头", "Cameras list": "摄像头列表",
  "No cameras discovered (simulator or restricted device)":
      "未发现摄像头（模拟器或受限设备）",
  # ── 传感器 ──
  "Motion Sensors": "运动传感器", "Accelerometer": "加速度计",
  "Gyroscope": "陀螺仪", "Magnetometer": "磁力计",
  "Device Motion (fused)": "融合运动 (Device Motion)",
  "Accelerometer Max Rate": "加速度计最大采样率",
  "Motion Permission": "运动与健身权限",
  "iOS does not expose the hardware maximum rate constant":
      "iOS 不开放硬件最大采样率常量",
  # ── 隐私 ──
  "Privacy & Permissions": "隐私与权限", "Location": "定位",
  "Contacts": "通讯录", "Calendar": "日历", "Reminders": "提醒事项",
  "Photos": "照片", "Microphone": "麦克风",
  "Calendar / Reminders": "日历 / 提醒事项",
  "Identifier for Vendor": "供应商标识 (IDFV)",
  "Same across apps from one vendor; changes if all vendor apps are removed":
      "同一开发者所有 App 共享；全部卸载后改变",
  "Change in Settings → Privacy & Security":
      "可在 设置 → 隐私与安全性 中修改",
  "Change in Settings → Privacy & Security → Location Services":
      "可在 设置 → 隐私与安全性 → 定位服务 中修改",
  "Change in Settings → Privacy & Security → Photos":
      "可在 设置 → 隐私与安全性 → 照片 中修改",
  # ── 诊断/导出 ──
  "Run Diagnostics": "运行全面诊断", "Run Full Diagnostics": "运行全面诊断",
  "Test all 11 modules and review status": "测试全部 11 个模块并查看状态",
  "Export Device Report": "导出设备报告", "Device Report": "设备报告",
  "Tap Refresh to generate the report from current live data.":
      "点击「刷新」用当前实时数据生成报告。",
  "Reference for thermal state, display and process info details.":
      "热状态/屏幕/进程信息细节参考",
  # ── 许可证 ──
  "MIT License": "MIT 许可证",
  "MIT License © 2012 Shmoopi LLC": "MIT 许可证 © 2012 Shmoopi LLC",
  "MIT License © 2019 Andrea Lufino": "MIT 许可证 © 2019 Andrea Lufino",
  "MIT License © 2026 Mysk": "MIT 许可证 © 2026 Mysk",
  "Apache License 2.0 © 2020 Takuto Nakamura": "Apache 2.0 许可证 © 2020 Takuto Nakamura",
}

files = sorted(glob.glob('/var/minis/workspace/hwmon/app/Sources/**/*.swift', recursive=True))
total = 0
for f in files:
    src = open(f, encoding='utf-8').read()
    orig = src
    for en, zh in M.items():
        src = src.replace(f'"{en}"', f'"{zh}"')
    if src != orig:
        open(f, 'w', encoding='utf-8').write(src)
        n = sum(orig.count(f'"{k}"') for k in M)
        total += n
        print(f"{f.split('/')[-1]}: {n} 处")
print(f"\n共 {total} 处汉化完成")
