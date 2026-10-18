#!/usr/bin/env python3
"""HWMonitor App 图标 v2：修正指针几何（不穿方块、不越弧）"""
from PIL import Image, ImageDraw, ImageFilter
import math

SIZE = 1024
SS = 4
W = SIZE * SS

img = Image.new("RGB", (W, W))
d = ImageDraw.Draw(img)

c1 = (16, 22, 40)
c2 = (6, 8, 16)
for y in range(W):
    t = (y / W * 0.7) + 0.15
    row_c = tuple(int(a + (b - a) * t) for a, b in zip(c1, c2))
    d.line([(0, y), (W, y)], fill=row_c)

glow = Image.new("L", (W, W), 0)
gd = ImageDraw.Draw(glow)
gd.ellipse([-W * 0.3, -W * 0.3, W * 0.75, W * 0.75], fill=70)
glow = glow.filter(ImageFilter.GaussianBlur(W // 12))
cyan_layer = Image.new("RGB", (W, W), (38, 80, 160))
img = Image.composite(cyan_layer, img, glow)
d = ImageDraw.Draw(img)

CX, CY = W // 2, W // 2 + W * 0.03

def polar(cx, cy, r, deg):
    rad = math.radians(deg)
    return cx + r * math.cos(rad), cy - r * math.sin(rad)

# 1. 弧形仪表槽（135°→405°，开口朝上）
R_OUT = W * 0.345
R_IN = W * 0.295
d.arc([CX - R_OUT, CY - R_OUT, CX + R_OUT, CY + R_OUT],
      start=135, end=405, fill=(58, 72, 108), width=int(R_OUT - R_IN))

# 2. 刻度（弧槽内缘向内）
TICK_BASE = R_IN - W * 0.008
for i in range(27):
    deg = 135 + i * 10
    if deg > 402:
        break
    major = (i % 3 == 0)
    tick_len = W * 0.030 if major else W * 0.015
    color = (150, 190, 255) if major else (88, 106, 145)
    w = int(W * 0.006) if major else int(W * 0.003)
    x1, y1 = polar(CX, CY, TICK_BASE, deg)
    x2, y2 = polar(CX, CY, TICK_BASE - tick_len, deg)
    d.line([(x1, y1), (x2, y2)], fill=color, width=w)

# 3. 中心读数方块（略缩）
CR = W * 0.140
rect = [CX - CR, CY - CR, CX + CR, CY + CR]
d.rounded_rectangle(rect, radius=int(CR * 0.40), fill=(10, 14, 26))
d.rounded_rectangle(rect, radius=int(CR * 0.40), outline=(70, 100, 160), width=int(W * 0.0035))

# 数据条（三行读数）
bar_w = CR * 1.05
for k, (bw, col) in enumerate([(0.88, (64, 150, 255)), (0.58, (90, 200, 140)), (0.34, (255, 170, 80))]):
    y = CY - CR * 0.52 + k * CR * 0.46
    bwid = bar_w * bw
    d.rounded_rectangle(
        [CX - bar_w / 2, y - W * 0.007, CX - bar_w / 2 + bwid, y + W * 0.007],
        radius=int(W * 0.007), fill=col
    )

# 4. 指针：起点=方块边缘外一点，终点=刻度内缘；方向 315°（右下，指向高值区）
needle_deg = 318
start_r = CR * 1.42          # 从方块外沿起步
end_r = TICK_BASE - W * 0.012  # 止于刻度内
sx, sy = polar(CX, CY, start_r, needle_deg)
ex, ey = polar(CX, CY, end_r, needle_deg)
# 针身（渐亮绿）
d.line([(sx, sy), (ex, ey)], fill=(110, 225, 175), width=int(W * 0.013))
# 针头小三角
tip_len = W * 0.028
tx, ty = polar(CX, CY, end_r - tip_len * 0.3, needle_deg)
perp = needle_deg + 90
px1, py1 = polar(0, 0, tip_len * 0.55, perp)
d.polygon([(ex + px1, ey + py1), (ex - px1, ey - py1), (tx, ty)], fill=(140, 245, 200))
# 起点圆轴（盖住方块边缘，仪表轴心语言）
hub = W * 0.020
hx, hy = polar(CX, CY, start_r, needle_deg)
d.ellipse([hx - hub, hy - hub, hx + hub, hy + hub], fill=(210, 250, 230))

# 5. 右下状态点
dot_r = W * 0.028
dx, dy = CX + W * 0.245, CY + W * 0.285
d.ellipse([dx - dot_r, dy - dot_r, dx + dot_r, dy + dot_r], fill=(60, 210, 255))

# 6. 顶部芯片纹理
chip = W * 0.017
for (mx, my) in [(CX - W * 0.33, CY - W * 0.31), (CX + W * 0.31, CY - W * 0.34)]:
    d.rounded_rectangle([mx - chip, my - chip, mx + chip, my + chip],
                        radius=int(chip * 0.3), outline=(105, 135, 195), width=int(W * 0.003))

img = img.resize((SIZE, SIZE), Image.LANCZOS)
img.save("/var/minis/workspace/hwmon/appicon_1024.png", "PNG")
print("icon v2 saved")
