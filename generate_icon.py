import os
import json
from PIL import Image, ImageDraw, ImageFont

# 配置
base_dir = "TrollNFC/Assets.xcassets"
icon_set_dir = os.path.join(base_dir, "AppIcon.appiconset")
icon_filename = "icon.png"

# 创建目录
os.makedirs(icon_set_dir, exist_ok=True)

# 1. 创建图标
size = 1024
img = Image.new('RGB', (size, size), color=(20, 20, 20)) # 深灰/黑色背景
draw = ImageDraw.Draw(img)

# 尝试绘制一个简单的图形 (NFC 信号波纹 + T)
# 绘制圆圈
center = size // 2
for r in [300, 220, 140]:
    bbox = [center - r, center - r, center + r, center + r]
    draw.arc(bbox, start=-60, end=60, fill=(0, 122, 255), width=40) # 蓝色波纹
    draw.arc(bbox, start=120, end=240, fill=(0, 122, 255), width=40)

# 绘制文字
try:
    # 尝试加载系统字体，否则用默认
    font_size = 180
    try:
        font = ImageFont.truetype("arial.ttf", font_size)
    except:
        font = ImageFont.load_default()
    
    text = "TrollNFC"
    # 获取文字大小 (Pillow 10+ 使用 textbbox)
    left, top, right, bottom = draw.textbbox((0, 0), text, font=font)
    text_w = right - left
    text_h = bottom - top
    
    draw.text(((size - text_w) / 2, (size - text_h) / 2), text, font=font, fill=(255, 255, 255))
except Exception as e:
    print(f"Warning: Could not draw text properly: {e}")

# 保存图标
img.save(os.path.join(icon_set_dir, icon_filename))

# 2. 创建 AppIcon Contents.json
contents = {
  "images" : [
    {
      "size" : "20x20",
      "idiom" : "iphone",
      "filename" : icon_filename,
      "scale" : "2x"
    },
    {
      "size" : "20x20",
      "idiom" : "iphone",
      "filename" : icon_filename,
      "scale" : "3x"
    },
    {
      "size" : "29x29",
      "idiom" : "iphone",
      "filename" : icon_filename,
      "scale" : "2x"
    },
    {
      "size" : "29x29",
      "idiom" : "iphone",
      "filename" : icon_filename,
      "scale" : "3x"
    },
    {
      "size" : "40x40",
      "idiom" : "iphone",
      "filename" : icon_filename,
      "scale" : "2x"
    },
    {
      "size" : "40x40",
      "idiom" : "iphone",
      "filename" : icon_filename,
      "scale" : "3x"
    },
    {
      "size" : "60x60",
      "idiom" : "iphone",
      "filename" : icon_filename,
      "scale" : "2x"
    },
    {
      "size" : "60x60",
      "idiom" : "iphone",
      "filename" : icon_filename,
      "scale" : "3x"
    },
    {
      "size" : "1024x1024",
      "idiom" : "ios-marketing",
      "filename" : icon_filename,
      "scale" : "1x"
    }
  ],
  "info" : {
    "author" : "xcode",
    "version" : 1
  }
}

with open(os.path.join(icon_set_dir, "Contents.json"), "w") as f:
    json.dump(contents, f, indent=2)

# 3. 创建 Assets.xcassets Contents.json
assets_info = {
  "info" : {
    "author" : "xcode",
    "version" : 1
  }
}

with open(os.path.join(base_dir, "Contents.json"), "w") as f:
    json.dump(assets_info, f, indent=2)

print("Icon assets generated successfully.")
