# 阶段 A · 开源项目研究报告（2026-10-18）

## 一、候选项目评估表

| 项目 | 星标 | 许可证 | 语言 | 维护状态 | 评估结论 |
|---|---|---|---|---|---|
| Shmoopi/iOS-System-Services | 1996 | **MIT** ✓ | ObjC | 2026-07 推送 | ✅ 采纳：功能清单蓝图 + 每核 CPU 实现参考 |
| mysk-research/loupe | 1559 | **MIT** ✓（源码；品牌/logo 除外） | Swift | 2026-09 活跃 | ✅ 核心采纳：Provider/Signal 架构 + 隐私模块 + Metal |
| asido/SystemMonitor | 500 | MPL-2.0 | ObjC | **2016 停更** | ❌ 弃用（30MB 里 80% 是 HockeySDK 二进制残骸；OpenGL 仪表已过时）。仅保留"实时仪表盘"产品概念 |
| ITzTravelInTime/SwiftCPUDetect | 53 | **LGPL-2.1** ⚠ | Swift | 2023 停更 | ⚠ 不引入依赖、不抄源码（LGPL 传染）。仅参考公开 sysctl 键名（hw.machine 等，系统接口非版权物），自行实现 |
| Kyome22/SystemInfoKit | 68 | **Apache-2.0** ✓ | Swift 6 | 2026-08 活跃 | ✅ 核心采纳：架构模板 + CPU/内存/存储/网络实现参考 |

## 二、补充研究项目

| 项目 | 星标 | 许可证 | 结论 |
|---|---|---|---|
| devicekit/DeviceKit | 4738 | MIT ✓ | 采纳思路：hw.machine 标识符 → 市场名映射表（自建精简版，SE3=iPhone14,6） |
| andrealufino/Luminous | 349 | MIT ✓ | 采纳：thermalState/brightness/nativeScale/maximumRefreshRate 等细项实现参考 |
| Lakr233/mobilePillowTalkLite | 510 | BSD-3 | 仅 UI 图表观感参考（服务器监控方向不同） |
| degtiarev/MotionCollector | 111 | MIT | 传感器采集参考（CoreMotion 本身简单，自实现） |

## 三、源码级实现确认（已实际读码验证）

### SystemInfoKit（iOS 16+，零第三方依赖，SPM）
- CPU：`host_statistics64` + HOST_CPU_LOAD_INFO，user/system/idle/nice tick 差分 → 使用率。**iOS 可用 ✓**
- 内存：`vm_statistics64`（active/inactive/speculative/wired/compressor/purgeable/external 分类）+ `host_basic_info.max_mem`。**iOS 可用 ✓**
- 存储：`URL.resourceValues(volumeTotalCapacity + volumeAvailableCapacityForImportantUsage)`。**iOS 可用 ✓**
- 网络：`NWPathMonitor` 接口类型 + `getifaddrs` 遍历（IP 地址、字节流量差分）。**iOS 可用 ✓**
- ⚠️ 电池：`#if os(macOS)` IOKit AppleSmartBattery——**iOS 上整段不编译**，iOS 侧仅剩 UIDevice 公开 API。其仓库 MeasuredValues 全是 Mac 采样
- ⚠️ swift-tools 6.2：要求较新 Xcode；集成时用其实现思路而非整个包（Apache-2.0 合规，保留 NOTICE）

### Loupe（零依赖，纯 xcodeproj）
- `SysctlHelper`：sysctlbyname(string/int64/timeval) + uname 封装，hw.machine → "iPhone16,1"
- `MetalProvider`：MTLCreateSystemDefaultDevice → device.name（"Apple A18 Pro GPU"）、recommendedMaxWorkingSetSize、supportsRaytracing、MTLGPUFamily 枚举。**全部公开 API ✓**
- `PermissionKind`：10 类权限门（motion/location/camera/bluetooth/localNetwork/contacts/photos/calendar/reminders/musicLibrary），每类带 title + rationale 教育文案
- `SignalCategory`：30 个类别枚举驱动主页 UI；每条信号 name/value/rationale 三元组——**即任务书第六阶段"数据可信度"的产品化范式**
- MIT 含品牌限制：不用其图标/名称/文案，只用代码结构与 API 用法

### iOS-System-Services（ObjC）
- 每核使用率：`host_processor_info(PROCESSOR_CPU_LOAD_INFO)` → processor_info_array_t。**SystemInfoKit 没有的能力 ✓**
- 内存用 32 位 `host_statistics`（过时，用 SystemInfoKit 的 64 位版）
- 磁盘用 NSFileSystemSize（过时，用 URL resourceValues）
- 硬件识别含模拟器分支（SIMULATOR_MODEL_IDENTIFIER）
- 结论：只取"每核使用率"+ 功能清单广度

## 四、iOS 非越狱数据能力终判（数据可信度规范基础）

| 数据 | 来源 API | 可用性 |
|---|---|---|
| 设备型号标识符/市场名 | sysctl hw.machine + 映射表 | ✓ |
| 系统版本/构建号/内核版本 | UIDevice + sysctl kern.osversion + uname | ✓ |
| CPU 架构/核心数 | NSProcessInfo.processorCount / sysctl hw.ncpu | ✓ |
| CPU 总使用率 | host_statistics64 差分 | ✓ |
| CPU 每核使用率 | host_processor_info | ✓ |
| **CPU 主频/GPU 频率** | — | ✗ 系统不开放（hw.cpufrequency iOS 无返回）→ 标注 |
| 物理内存总量 | host_basic_info.max_mem | ✓ |
| 系统内存分类统计 | vm_statistics64 | ✓ |
| 当前 App 内存 | task_vm_info.phys_footprint | ✓ |
| 存储总/用/可用 | URL resourceValues | ✓ |
| 电池电量/充电状态 | UIDevice.batteryLevel/State | ✓ |
| **电池健康度/循环次数/温度/电压电流** | — | ✗ iOS 无公开 API（IOKit 不可用）→ 标注"系统未开放" |
| 热状态 | ProcessInfo.thermalState | ✓（4 级）|
| GPU 名称/工作集/特性 | MTLDevice | ✓ |
| **GPU 实时利用率** | — | ✗ 不开放 → 标注 |
| 网络类型/接口/IP/流量 | NWPathMonitor + getifaddrs | ✓ |
| 网速测试 | URLSession（用户触发）| ✓ |
| 传感器 | CoreMotion（需 Motion 权限）| ✓ |
| 屏幕分辨率/缩放/刷新率/亮度 | UIScreen | ✓ |
| 摄像头规格 | AVCaptureDevice.DiscoverySession | ✓（枚举不需授权）|
| 隐私权限状态 | 各框架 authorizationStatus | ✓ |

## 五、融合架构方案

分层（吸取三家之长）：
- **Provider 协议**（Loupe 模式）：每类数据一个 Provider，产出 `MetricCard{ id, name, value, unit, source, collectedAt, status, limitation }`——status ∈ ok/degraded/unauthorized/unavailable，unavailable 必须带 limitation 文案
- **Repository**（SystemInfoKit 模式）：CPU/Memory/Storage/Network 四个采集器，含 tick/page 差分状态管理
- **PermissionGate**（Loupe 模式）：权限前置说明 → 申请 → 拒绝降级路径
- **MonitoringEngine**：单例调度器，统一采样间隔（1s/5s/30s 三档），进入后台自动暂停，页面离开自动降频——避免重复计时
- **可视化**：Swift Charts（Apple 官方，iOS 16+，零依赖）
- **设计系统**：DesignTokens（Color/Typography/Spacing/Radius/Status）+ CardStyle + SF Symbols
- **导航**：总览 / 硬件 / 监控 / 传感器 / 系统 / 设置（六页签，SE3 375pt 实测排布）
- **导出**：JSON + CSV + 纯文本报告，ShareLink 原生分享，导出前预览

## 六、构建与交付方案（沿用已验证管线）

- GitHub Actions macos runner + Xcode 26.2（Pin，已证可过 iOS 构建）
- XcodeGen 生成工程（project.yml）
- deployment target iOS 16.0（覆盖 Swift Charts）
- Bundle ID：com.qingyao.hwmonitor（独立，不与现有 App 冲突）
- 交付：未签名 IPA → 用户 Feather + p12 签名安装（成熟流程）
- NOTICE.md 汇总四个采纳项目许可证

## 七、许可证合规清单

1. **Loupe**（MIT）：保留版权声明；不使用其名称/图标/文案
2. **iOS-System-Services**（MIT）：保留版权声明
3. **SystemInfoKit**（Apache-2.0）：保留 LICENSE + NOTICE 声明；注明修改
4. **DeviceKit/Luminous**（MIT）：参考思路，映射表数据自建
5. **SwiftCPUDetect**（LGPL-2.1）：零代码引入 ✓
6. **SystemMonitor**（MPL-2.0）：零代码引入 ✓

—— 阶段 A 完成。研究原始数据存 /var/minis/workspace/hwmon/research/
