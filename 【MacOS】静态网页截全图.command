#!/bin/zsh

# 获取当前脚本所在目录
SCRIPT_DIR=$(cd "$(dirname "$0")"; pwd)
TEMP_DIR="${SCRIPT_DIR}/.puppeteer_temp"
ASSETS_DIR="${SCRIPT_DIR}/assets"
mkdir -p "$TEMP_DIR"
mkdir -p "$ASSETS_DIR"
cd "$TEMP_DIR"

echo "📦 正在检查 Node.js..."
if ! command -v node &>/dev/null; then
  echo "❌ Node.js 未安装，尝试通过 Homebrew 安装..."
  brew install node
else
  echo "✅ Node.js 已安装"
fi

echo "📦 正在检查 Puppeteer..."
if [ ! -d "node_modules/puppeteer" ]; then
  echo "📥 安装 Puppeteer..."
  npm init -y &>/dev/null
  npm install puppeteer &>/dev/null
else
  echo "✅ Puppeteer 已存在"
fi

# 循环等待用户输入 HTML 文件路径，直到有效
while true; do
  echo "📄 请拖入你的 HTML 文件（例如 timeline.html）："
  read -r raw_path
  raw_path=${raw_path//\"/}      # 去除引号
  html_path=$(realpath "$raw_path" 2>/dev/null)

  if [[ -f "$html_path" && "$html_path" == *.html ]]; then
    echo "✅ 检测到 HTML 文件：$html_path"
    break
  else
    echo "❌ 无效的 HTML 文件路径，请重新拖入。"
  fi
done

# 提取文件名（不含扩展名）
html_filename=$(basename "$html_path")
output_filename="${html_filename%.*}.png"
OUTPUT_PATH="${ASSETS_DIR}/${output_filename}"

# 生成 puppeteer 脚本
cat <<EOF > screenshot.js
const puppeteer = require('puppeteer');
const path = require('path');

(async () => {
  const browser = await puppeteer.launch();
  const page = await browser.newPage();

  await page.setViewport({ width: 1600, height: 1000 });
  await page.goto('file://' + path.resolve('${html_path}'));

  const boundingBox = await page.evaluate(() => {
    const el = document.querySelector('.timeline-wrapper');
    const rect = el.getBoundingClientRect();
    return {
      top: rect.top,
      left: rect.left,
      width: rect.width,
      height: rect.height
    };
  });

  await page.setViewport({
    width: Math.ceil(boundingBox.width),
    height: Math.ceil(boundingBox.height)
  });

  await page.screenshot({
    path: '${OUTPUT_PATH}',
    fullPage: false
  });

  await browser.close();
  console.log("✅ 精准截图完成，已保存到：${OUTPUT_PATH}");
})();
EOF

echo "📸 正在生成截图..."
node screenshot.js
