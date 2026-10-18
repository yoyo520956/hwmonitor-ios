# Open-Source Notices / 开源合规清单

硬核监测Pro (HWMonitor) 的架构与部分实现参考了以下开源项目，在此致谢并遵循其许可证条件。

## 采纳方式与许可证

### 1. Loupe — mysk-research/loupe
- **许可证**：MIT License, Copyright (c) 2026 Mysk
- **采纳**：Provider/Signal 架构模式、权限门（PermissionGate）设计、sysctl 封装思路、Metal GPU 信息读取方式（MTLDevice 公开 API）
- **合规声明**：仅使用其 MIT 授权的源码级思路。Loupe 的名称、图标、品牌、设计文件与文案未被使用，本应用使用独立品牌「硬核监测Pro」。

### 2. SystemInfoKit — Kyome22/SystemInfoKit
- **许可证**：Apache License 2.0, Copyright 2020 Takuto Nakamura
- **采纳**：CPU 使用率 tick 差分算法（host_statistics64/HOST_CPU_LOAD_INFO）、内存分类统计方法（vm_statistics64）、存储容量读取（URL volume resourceValues）、网络接口遍历（NWPathMonitor + getifaddrs）
- **合规声明**：遵循 Apache-2.0，保留原始版权声明；本项目的实现为独立编写，API 调用模式参考其已验证做法。

### 3. iOS-System-Services — Shmoopi/iOS-System-Services
- **许可证**：MIT License, Copyright (c) 2012 Shmoopi LLC
- **采纳**：每核 CPU 使用率的读取方式（host_processor_info / PROCESSOR_CPU_LOAD_INFO）、设备信息功能清单广度
- **合规声明**：保留原始版权声明。

### 4. DeviceKit — devicekit/DeviceKit
- **许可证**：MIT License
- **采纳**：型号标识符 → 市场名称映射表的概念（本项目的映射表为独立自建，覆盖 iPhone 11 至 17 系列）
- **合规声明**：保留原始版权声明。

### 5. Luminous — andrealufino/Luminous
- **许可证**：MIT License, Copyright (c) 2019 Andrea Lufino
- **采纳**：热状态（ProcessInfo.thermalState）、屏幕属性（nativeBounds/nativeScale/maximumRefreshRate）等细节实现参考
- **合规声明**：保留原始版权声明。

## 未采纳项目

- **SwiftCPUDetect**（LGPL-2.1）：因许可证传染性，未引入任何代码或依赖。
- **SystemMonitor**（MPL-2.0，2016 停更）：未引入任何代码或依赖。

## 数据可信度声明

本应用所有数据均通过 Apple 公开 API 采集，全部在设备本地处理，不上传任何数据。
iOS 系统不向第三方应用开放的数据（CPU 主频、GPU 实时利用率、电池健康度/循环次数/温度/电压等）
一律标注为 N/A 并说明原因，绝不使用模拟值或常量伪装实时数据。
