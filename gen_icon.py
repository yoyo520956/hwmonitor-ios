#!/usr/bin/env python3
"""HWMonitor App 图标生成：精密仪表盘风格（深空底 + 弧形仪表 + 指针 + 刻度）"""
from PIL import Image, ImageDraw
import math

SIZE = 1024
SS = 4  # 超采样抗锯齿
W = SIZE * SS

img = Image.new("RGB", (W, W))
d = ImageDraw.Draw(img)

# 1. 背景：对角深空渐变（藏蓝 → 近黑）
c1 = (16, 22, 40)   # 左上：深藏蓝
c2 = (6, 8, 16)     # 右下：近黑
for y in range(W):
    t = (y / W * 0.7) + (0.3 * 0.5)  # 简单对角近似
    row_c = tuple(int(a + (b - a) * t) for a, b in zip(c1, c2))
    d.line([(0, y), (W, y)], fill=row_c)
# 对角光晕：左上青蓝辉光
glow = Image.new("L", (W, W), 0)
gd = ImageDraw.Draw(glow)
gd.ellipse([-W * 0.3, -W * 0.3, W * 0.75, W * 0.75], fill=70)
from PIL import ImageFilter
glow = glow.filter(ImageFilter.GaussianBlur(W // 12))
cyan_layer = Image.new("RGB", (W, W), (38, 80, 160))
img = Image.composite(cyan_layer, img, glow)
d = ImageDraw.Draw(img)

CX, CY = W // 2, W // 2 + W * 0.04

# 2. 外弧仪表盘（270° 弧，从 135° 到 45°，即左下→右下开口向上）
R_OUT = W * 0.34
R_IN = W * 0.29
ARC_SPAN = 270
START_DEG = 135

def polar(cx, cy, r, deg):
    rad = math.radians(deg)
    return cx + r * math.cos(rad), cy - r * math.sin(rad)

# 弧形底槽
bbox = [CX - R_OUT, CY - R_OUT, CX + R_OUT, CY + R_OUT]
bbox_in = [CX - R_IN, CY - R_IN, CX + R_IN, CY + R_IN]
d.arc(bbox, start=START_DEG - 270 + 90, end=START_DEG + 90, fill=(60, 74, 110), width=int(R_OUT - R_IN))

# 3. 刻度线（每 10° 一根，主刻度每 30°）
TICK_OUT = R_OUT - (R_OUT - R_IN) - W * 0.012
for i in range(28):
    deg = START_DEG - i * 10
    if deg < START_DEG - 260:
        break
    major = (i % 3 == 0)
    tick_len = W * 0.030 if major else W * 0.016
    color = (150, 190, 255) if major else (90, 110, 150)
    w = int(W * 0.006) if major else int(W * 0.003)
    x1, y1 = polar(CX, CY, TICK_OUT, deg)
    x2, y2 = polar(CX, CY, TICK_OUT - tick_len, deg)
    d.line([(x1, y1), (x2, y2)], fill=color, width=w)

# 4. 中心数字区：圆角方块 + 内芯
CR = W * 0.155
rect = [CX - CR, CY - CR, CX + CR, CY + CR]
d.rounded_rectangle(rect, radius=int(CR * 0.42), fill=(10, 14, 26))
d.rounded_rectangle(rect, radius=int(CR * 0.42), outline=(70, 100, 160), width=int(W * 0.004))

# 中心数据条（模拟读数横线，装饰性——不是假数据，是图标语言）
bar_w = CR * 1.15
for k, (bw, col) in enumerate([(0.9, (64, 150, 255)), (0.62, (90, 200, 140)), (0.38, (255, 170, 80))]):
    y = CY - CR * 0.5 + k * CR * 0.42
    bwid = bar_w * bw
    d.rounded_rectangle(
        [CX - bar_w / 2, y - W * 0.008, CX - bar_w / 2 + bwid, y + W * 0.008],
        radius=int(W * 0.008), fill=col
    )

# 5. 指针：从中心指向 300° 位置（绿区）
needle_deg = 300
needle_len = R_IN - W * 0.005
nx, ny = polar(CX, CY, needle_len, needle_deg)
d.line([(CX, CY), (nx, ny)], fill=(120, 230, 180), width=int(W * 0.011))
# 指针配重圆点
d.ellipse([CX - W * 0.018, CY - W * 0.018, CX + W * 0.018, CY + W * 0.018], fill=(200, 240, 220))

# 6. 右下状态点（青色，"系统在线"语言）
dot_r = W * 0.030
dx, dy = CX + W * 0.26, CY + W * 0.30
d.ellipse([dx - dot_r, dy - dot_r, dx + dot_r, dy + dot_r], fill=(60, 210, 255))

# 7. 顶部微芯片纹理（四角小方块暗示"硬件"）
chip = W * 0.018
for (mx, my) in [(CX - W * 0.34, CY - W * 0.30), (CX + W * 0.32, CY - W * 0.33)]:
    d.rounded_rectangle([mx - chip, my - chip, mx + chip, my + chip],
                        radius=int(chip * 0.3), outline=(110, 140, 200), width=int(W * 0.003))

# 缩回标准尺寸（Lanczos 抗锯齿）
img = img.resize((SIZE, SIZE), Image.LANCZOS)
img.save("/var/minis/workspace/hwmon/appicon_1024.png", "PNG")
print("icon saved:", img.size)
