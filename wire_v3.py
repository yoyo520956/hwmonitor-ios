#!/usr/bin/env python3
"""v3.0 收尾接线：Info.plist URL Types / project.yml 混编配置 / 页面入口 / 悬浮窗路由监听"""
import re

base = '/var/minis/workspace/hwmon/app'

# ── 1. Info.plist：加 URL Scheme + 汉化权限文案 ──
p = base + '/Resources/Info.plist'
s = open(p, encoding='utf-8').read()
s = s.replace(
    '<string>Motion permission is used to read accelerometer, gyroscope and magnetometer readings on the Sensors screen. All data stays on this device.</string>',
    '<string>用于在「传感器」页读取加速度计、陀螺仪与磁力计数据。所有数据仅在本机处理，不会上传。</string>'
)
url_types = '''	<key>CFBundleURLTypes</key>
	<array>
		<dict>
			<key>CFBundleURLName</key>
			<string>com.qingyao.hwmonitor.deeplink</string>
			<key>CFBundleURLSchemes</key>
			<array>
				<string>hwmonitor</string>
			</array>
		</dict>
	</array>
	<key>NSMotionUsageDescription</key>'''
assert '<key>CFBundleURLTypes</key>' not in s
s = s.replace('	<key>NSMotionUsageDescription</key>', url_types, 1)
open(p, 'w', encoding='utf-8').write(s)
print("✓ Info.plist: URL Scheme hwmonitor:// 已注册，权限文案已汉化")

# ── 2. project.yml：bridging header + 版本 3.0.0 ──
p = base + '/project.yml'
s = open(p, encoding='utf-8').read()
s = s.replace('CURRENT_PROJECT_VERSION: "20261018.02"', 'CURRENT_PROJECT_VERSION: "20261018.03"')
s = s.replace('MARKETING_VERSION: "2.0.0"', 'MARKETING_VERSION: "3.0.0"')
old = '        ASSETCATALOG_COMPILER_APPICON_NAME: AppIcon'
new = '''        ASSETCATALOG_COMPILER_APPICON_NAME: AppIcon
        SWIFT_OBJC_BRIDGING_HEADER: "Sources/Core/HWMonitor-Bridging-Header.h"'''
assert old in s and 'SWIFT_OBJC_BRIDGING_HEADER' not in s
s = s.replace(old, new, 1)
open(p, 'w', encoding='utf-8').write(s)
print("✓ project.yml: bridging header 已配置，版本 3.0.0 (20261018.03)")

# ── 3. Overview 诊断入口 → 自检页 ──
p = base + '/Sources/Views/OverviewHardwareSystemViews.swift'
s = open(p, encoding='utf-8').read()
s = s.replace('DiagnosticsView()', 'SelfCheckView()')
s = s.replace('Text("运行全面诊断")', 'Text("自检与能力矩阵")')
s = s.replace('Text("测试全部 11 个模块并查看状态")', 'Text("启动自检链 · 模块降级状态 · 深链快捷指令")')
open(p, 'w', encoding='utf-8').write(s)
print("✓ Overview: 诊断入口 → SelfCheckView")

# ── 4. SettingsView 加自检入口 + 版本号 ──
p = base + '/Sources/Views/SensorsTabView.swift'
s = open(p, encoding='utf-8').read()
old = '''                Section("报告") {
                    Button {
                        showExport = true
                    } label: {
                        Label("导出设备报告", systemImage: "square.and.arrow.up")
                    }
                }'''
new = '''                Section {
                    NavigationLink {
                        SelfCheckView()
                    } label: {
                        Label("自检与能力矩阵", systemImage: "stethoscope")
                    }
                    Button {
                        showExport = true
                    } label: {
                        Label("导出设备报告", systemImage: "square.and.arrow.up")
                    }
                } header: {
                    Text("诊断与报告")
                } footer: {
                    Text("自检页展示启动自检链结果、各模块降级状态，以及可在「快捷指令」中使用的深链。")
                }'''
assert old in s
s = s.replace(old, new, 1)
s = s.replace('LabeledContent("版本", value: "2.0.0")', 'LabeledContent("版本", value: "3.0.0")')
open(p, 'w', encoding='utf-8').write(s)
print("✓ SettingsView: 自检入口 + 版本 3.0.0")

# ── 5. 悬浮窗监听深链展开路由 ──
p = base + '/Sources/Floating/FloatingWindow.swift'
s = open(p, encoding='utf-8').read()
old = '''        .allowsHitTesting(enabled)
        .opacity(enabled ? 1 : 0)'''
new = '''        .allowsHitTesting(enabled)
        .opacity(enabled ? 1 : 0)
        .onReceive(NotificationCenter.default.publisher(for: Notification.Name("hwmon.route.floating"))) { _ in
            // 深链 hwmonitor://floating（过时间窗校验）
            guard enabled, TimedEventBus.shared.consume("hwmon.route.floating") != nil else { return }
            withAnimation(.spring(response: 0.35, dampingFraction: 0.85)) { expanded = true }
        }'''
assert old in s
s = s.replace(old, new, 1)
open(p, 'w', encoding='utf-8').write(s)
print("✓ FloatingWindow: 深链展开路由已接")

print("\n全部接线完成")
