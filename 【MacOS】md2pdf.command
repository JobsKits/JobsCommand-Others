#!/bin/zsh

echo "📂 请拖入 Markdown 文件或文件夹路径后回车："
read input_path

if [ ! -e "$input_path" ]; then
  echo "❌ 无效路径: $input_path"
  exit 1
fi

# ========== 环境变量修复 ==========
export PATH="$HOME/.local/bin:$PATH"

# ========== 工具检测函数 ==========

check_and_install_brew() {
  if ! command -v brew >/dev/null 2>&1; then
    echo "❌ 未安装 Homebrew，请手动安装：https://brew.sh"
    exit 1
  fi
}

install_weasyprint_native_libs() {
  echo "🧱 安装 WeasyPrint 所需底层图形库..."
  brew install pango gdk-pixbuf cairo libffi gettext freetype
}

check_and_install_pandoc() {
  if ! command -v pandoc >/dev/null 2>&1; then
    echo "🔍 安装 pandoc..."
    brew install pandoc
  else
    echo "✅ pandoc 已安装"
  fi
}

check_and_install_weasyprint() {
  if ! command -v weasyprint >/dev/null 2>&1; then
    echo "🔍 未检测到 weasyprint，尝试用 pipx 安装..."

    if ! command -v pipx >/dev/null 2>&1; then
      echo "📦 安装 pipx..."
      brew install pipx
    fi

    echo "🔧 修复 pipx 权限问题（如果有）..."
    mkdir -p ~/.local/pipx/venvs 2>/dev/null
    sudo chown -R "$USER" ~/.local >/dev/null 2>&1

    echo "📦 初始化 pipx..."
    pipx ensurepath --force

    echo "🚀 安装 weasyprint..."
    pipx install weasyprint
  else
    echo "✅ weasyprint 已安装"
  fi
}

# ========== 工具安装流程 ==========
check_and_install_brew
install_weasyprint_native_libs
check_and_install_pandoc
check_and_install_weasyprint

# ========== 转换函数 ==========
convert_md_to_pdf() {
  local md_file="$1"
  local html_file="${md_file:r}.html"
  local pdf_file="${md_file:r}.pdf"

  echo "📄 转换 Markdown → HTML: ${md_file:t} → ${html_file:t}"
  pandoc "$md_file" -s -o "$html_file"

  echo "📄 转换 HTML → PDF: ${html_file:t} → ${pdf_file:t}"
  weasyprint "$html_file" "$pdf_file"

  if [ $? -eq 0 ]; then
    echo "✅ 成功输出 PDF: ${pdf_file}"
    echo "🧹 删除中间文件: $html_file"
    rm -f "$html_file"
  else
    echo "❌ 转换失败: $md_file"
  fi
}

# ========== 处理输入路径 ==========
if [ -f "$input_path" ]; then
  [[ "$input_path" == *.md ]] && convert_md_to_pdf "$input_path"
elif [ -d "$input_path" ]; then
  md_files=("${input_path}"/*.md(N))
  if [ ${#md_files[@]} -eq 0 ]; then
    echo "⚠️ 文件夹中未找到 Markdown 文件"
  else
    for md_file in "${md_files[@]}"; do
      convert_md_to_pdf "$md_file"
    done
  fi
else
  echo "❌ 不支持的输入类型"
  exit 1
fi
