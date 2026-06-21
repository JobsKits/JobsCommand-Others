#!/bin/zsh
# 脚本自述：
# - 脚本名称：【MacOS】静态网页截全图.command
# - 核心用途：执行“静态网页截全图”对应的自动化任务。
# - 影响范围：可能修改当前项目、用户环境或脚本指定的目标。
# - 运行提示：运行后会先打印内置自述；终端模式按回车确认后继续，按 Ctrl+C 可取消。


SCRIPT_BASENAME=$(basename "$0" | sed 's/\.[^.]*$//')   # 当前脚本名（去掉扩展名）
LOG_FILE="/tmp/${SCRIPT_BASENAME}.log"                  # 设置对应的日志文件路径
# 统一输出终端信息并同步记录日志。
log()            { echo -e "$1" | tee -a "$LOG_FILE"; }
# 输出 color echo 对应级别的日志信息。
color_echo()     { log "\033[1;32m$1\033[0m"; }         # ✅ 正常绿色输出
# 输出 info echo 对应级别的日志信息。
info_echo()      { log "\033[1;34mℹ $1\033[0m"; }       # ℹ 信息
# 输出 success echo 对应级别的日志信息。
success_echo()   { log "\033[1;32m✔ $1\033[0m"; }       # ✔ 成功
# 输出 warn echo 对应级别的日志信息。
warn_echo()      { log "\033[1;33m⚠ $1\033[0m"; }       # ⚠ 警告
# 输出 warm echo 对应级别的日志信息。
warm_echo()      { log "\033[1;33m$1\033[0m"; }         # 🟡 温馨提示（无图标）
# 输出 note echo 对应级别的日志信息。
note_echo()      { log "\033[1;35m➤ $1\033[0m"; }       # ➤ 说明
# 输出 error echo 对应级别的日志信息。
error_echo()     { log "\033[1;31m✖ $1\033[0m"; }       # ✖ 错误
# 输出 err echo 对应级别的日志信息。
err_echo()       { log "\033[1;31m$1\033[0m"; }         # 🔴 错误纯文本
# 输出 debug echo 对应级别的日志信息。
debug_echo()     { log "\033[1;35m🐞 $1\033[0m"; }      # 🐞 调试
# 输出 highlight echo 对应级别的日志信息。
highlight_echo() { log "\033[1;36m🔹 $1\033[0m"; }      # 🔹 高亮
# 输出 gray echo 对应级别的日志信息。
gray_echo()      { log "\033[0;90m$1\033[0m"; }         # ⚫ 次要信息
# 输出 bold echo 对应级别的日志信息。
bold_echo()      { log "\033[1m$1\033[0m"; }            # 📝 加粗
# 输出 underline echo 对应级别的日志信息。
underline_echo() { log "\033[4m$1\033[0m"; }            # 🔗 下划线

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]:-${(%):-%x}}")" && pwd)"
SCRIPT_PATH="${SCRIPT_DIR}/$(basename -- "$0")"
# 输出 show readme and wait 对应的说明与结果。
show_readme_and_wait() {
  local readme_path="${SCRIPT_DIR}/README.md"
  clear
  print -r -- '============================== 脚本内置自述 =============================='
  print -r -- '脚本名称：【MacOS】静态网页截全图.command'
  print -r -- '核心用途：执行“静态网页截全图”对应的自动化任务。'
  print -r -- '影响范围：可能修改当前项目、用户环境或脚本指定的目标。'
  print -r -- '取消方式：确认前按 Ctrl+C 终止，不会继续执行后续业务。'
  print -r -- '============================================================================'
  if [[ -f "$readme_path" ]]; then
    highlight_echo "============================== README.md =============================="
    cat "$readme_path" | tee -a "$LOG_FILE"
    highlight_echo "======================================================================="
  else
    warn_echo "未找到 README.md，继续执行内置流程说明。"
  fi
  echo ""
  read -r "?👉 已阅读自述文件，按回车继续执行；按 Ctrl+C 取消：" _
}
# 封装 pause to exit 对应的独立处理逻辑。
pause_to_exit() {
  echo ""
  read -r "?🔚 按回车退出..." _
}
# 收集并校验 ask any to run 对应的用户确认。
ask_any_to_run() {
  local message="$1"
  local answer=""
  read -r "?${message}（直接回车跳过；输入任意字符后回车执行）：" answer
  [[ -n "$answer" ]]
}
# 封装 strip outer quotes 对应的独立处理逻辑。
strip_outer_quotes() {
  local value="$1"
  value="${value%$'\r'}"
  value="${value%$'\n'}"
  value="${value#\"}"
  value="${value%\"}"
  value="${value#\'}"
  value="${value%\'}"
  print -r -- "$value"
}

TEMP_DIR="${SCRIPT_DIR}/.puppeteer_temp"
ASSETS_DIR="${SCRIPT_DIR}/assets"
# 判断芯片架构。
get_cpu_arch() {
  [[ "$(uname -m)" == "arm64" ]] && echo "arm64" || echo "x86_64"
}
# 查找 brew 可执行文件。
find_brew_bin() {
  if command -v brew >/dev/null 2>&1; then
    command -v brew
  elif [[ -x "/opt/homebrew/bin/brew" ]]; then
    echo "/opt/homebrew/bin/brew"
  elif [[ -x "/usr/local/bin/brew" ]]; then
    echo "/usr/local/bin/brew"
  fi
}
# 根据当前 shell 选择配置文件。
get_profile_file() {
  local shell_path="${SHELL##*/}"
  case "$shell_path" in
    zsh)  echo "$HOME/.zprofile" ;;
    bash) echo "$HOME/.bash_profile" ;;
    *)    echo "$HOME/.profile" ;;
  esac
}
# 写入 Homebrew shellenv，避免重复追加。
# 安装或接入 Homebrew；已安装时按规范选择是否更新。
install_homebrew() {
  local arch="$(get_cpu_arch)"
  local profile_file="$(get_profile_file)"
  local brew_bin="$(find_brew_bin)"
  local shellenv_cmd=""
  local confirm=""

  if [[ -z "$brew_bin" ]]; then
    warn_echo "未检测到 Homebrew，正在安装中...（架构：$arch）"

    if [[ "$arch" == "arm64" ]]; then
      /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)" || {
        error_echo "Homebrew 安装失败（arm64）"
        exit 1
      }
      brew_bin="/opt/homebrew/bin/brew"
    else
      arch -x86_64 /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)" || {
        error_echo "Homebrew 安装失败（x86_64）"
        exit 1
      }
      brew_bin="/usr/local/bin/brew"
    fi

    [[ -x "$brew_bin" ]] || brew_bin="$(find_brew_bin)"
    [[ -n "$brew_bin" && -x "$brew_bin" ]] || {
      error_echo "Homebrew 安装后仍未找到 brew 可执行文件"
      exit 1
    }

    success_echo "Homebrew 安装成功：$brew_bin"
    shellenv_cmd="eval \"\$(${brew_bin} shellenv)\""
    inject_shellenv_block "$profile_file" "$shellenv_cmd"
    return 0
  fi

  shellenv_cmd="eval \"\$(${brew_bin} shellenv)\""
  inject_shellenv_block "$profile_file" "$shellenv_cmd"
  success_echo "Homebrew 已安装：$brew_bin"

  info_echo "是否执行 Homebrew 更新？"
  echo "👉 直接按 [Enter]：跳过更新" | tee -a "$LOG_FILE"
  echo "👉 输入任意字符后回车：执行 brew update && brew upgrade && brew cleanup && brew doctor && brew -v" | tee -a "$LOG_FILE"
  IFS= read -r confirm

  if [[ -z "$confirm" ]]; then
    note_echo "已选择跳过 Homebrew 更新"
    return 0
  fi

  info_echo "正在更新 Homebrew..."
  brew update  || { error_echo "brew update 失败"; exit 1; }
  brew upgrade || { error_echo "brew upgrade 失败"; exit 1; }
  brew cleanup || { error_echo "brew cleanup 失败"; exit 1; }
  brew doctor  || { warn_echo  "brew doctor 有警告/错误，请按提示处理"; }
  brew -v      || { warn_echo  "打印 brew 版本失败，可忽略"; }
  success_echo "Homebrew 已更新"
}
# 兼容脚本主流程里的命名。
ensure_homebrew() {
  install_homebrew
}
# 安装或按需升级 Node.js。
ensure_node() {
  if command -v node >/dev/null 2>&1 && command -v npm >/dev/null 2>&1; then
    success_echo "Node.js / npm 已安装。"

    local brew_bin="$(find_brew_bin)"
    if [[ -n "$brew_bin" ]]; then
      local shellenv_cmd="eval \"\$(${brew_bin} shellenv)\""
      eval "$shellenv_cmd"
      if brew list --formula node >/dev/null 2>&1; then
        if ask_any_to_run "是否升级 node"; then
          brew upgrade node || warn_echo "node 升级失败或无需升级。"
        else
          info_echo "已跳过 node 升级。"
        fi
      fi
    fi
    return 0
  fi

  warn_echo "未检测到 Node.js / npm，将通过 Homebrew 安装 node。"
  install_homebrew
  brew install node || { error_echo "Node.js 安装失败。"; exit 1; }
  success_echo "Node.js 安装完成。"
}
# 安装或按需升级 Puppeteer。
ensure_puppeteer() {
  mkdir -p "$TEMP_DIR"
  cd "$TEMP_DIR" || exit 1

  [[ -f package.json ]] || npm init -y >/dev/null 2>&1
  if [[ -d "node_modules/puppeteer" ]]; then
    success_echo "Puppeteer 已安装。"
    if ask_any_to_run "是否升级 Puppeteer"; then
      npm install puppeteer@latest || { error_echo "Puppeteer 升级失败。"; exit 1; }
    else
      info_echo "已跳过 Puppeteer 升级。"
    fi
  else
    note_echo "开始安装 Puppeteer。"
    npm install puppeteer || { error_echo "Puppeteer 安装失败。"; exit 1; }
  fi
}

HTML_PATH=""
# 获取 HTML 路径。
read_html_path() {
  local raw_path=""
  while true; do
    read -r "?📄 请拖入 HTML 文件：" raw_path
    HTML_PATH="$(strip_outer_quotes "$raw_path")"
    if [[ -f "$HTML_PATH" && "$HTML_PATH" == *.html ]]; then
      return 0
    fi
    error_echo "无效 HTML 文件，请重新拖入。"
  done
}
# 计算输出路径。
build_output_path() {
  local html_path="$1"
  mkdir -p "$ASSETS_DIR"
  local html_filename="$(basename "$html_path")"
  local base_name="${html_filename%.*}"
  local output_path="${ASSETS_DIR}/${base_name}.png"
  if [[ -e "$output_path" ]]; then
    output_path="${ASSETS_DIR}/${base_name}_$(date +%Y%m%d_%H%M%S).png"
  fi
  print -r -- "$output_path"
}
# 生成截图脚本。
write_screenshot_js() {
  cat > "$TEMP_DIR/screenshot.js" <<'EOF'
const puppeteer = require('puppeteer');
const path = require('path');

(async () => {
  const htmlPath = process.argv[2];
  const outputPath = process.argv[3];
  const selector = process.argv[4] || '';

  const browser = await puppeteer.launch({ headless: true });
  const page = await browser.newPage();
  await page.setViewport({ width: 1600, height: 1000, deviceScaleFactor: 1 });
  await page.goto('file://' + path.resolve(htmlPath), { waitUntil: 'networkidle0' });

  if (selector) {
    const element = await page.$(selector);
    if (element) {
      await element.screenshot({ path: outputPath });
    } else {
      console.warn(`未找到选择器：${selector}，改为截取整页。`);
      await page.screenshot({ path: outputPath, fullPage: true });
    }
  } else {
    await page.screenshot({ path: outputPath, fullPage: true });
  }

  await browser.close();
  console.log(`截图完成：${outputPath}`);
})();
EOF
}
# 执行入口下沉后的完整业务流程和控制逻辑。
run_main_business_flow() {
  # 检查当前步骤所需的环境、路径或输入条件。
  ensure_node
  # 检查当前步骤所需的环境、路径或输入条件。
  ensure_puppeteer

  # 执行当前流程中的独立业务步骤：read_html_path。
  read_html_path
  # 收集用户输入，供后续业务判断使用。
  read -r "?请输入要精准截图的 CSS 选择器（直接回车截取整页）：" selector
  # 初始化当前流程后续步骤需要使用的变量。
  local output_path="$(build_output_path "$HTML_PATH")"

  # 执行当前流程中的独立业务步骤：write_screenshot_js。
  write_screenshot_js
  # 执行当前流程中的独立业务步骤：note_echo。
  note_echo "开始截图。"
  # 执行当前流程中的独立业务步骤：node。
  node "$TEMP_DIR/screenshot.js" "$HTML_PATH" "$output_path" "$selector" || { error_echo "截图失败。"; pause_to_exit; exit 1; }
  # 输出当前流程的完成状态、摘要和日志位置。
  success_echo "截图已保存：$output_path"
  # 执行当前流程中的独立业务步骤：open。
  open -R "$output_path" >/dev/null 2>&1 || true
  # 执行当前流程中的独立业务步骤：pause_to_exit。
  pause_to_exit
}
# 编排脚本的高层业务流程。
# 初始化脚本运行环境，并集中承载原有的顶层执行逻辑。
# 将 Homebrew shellenv 写入用户配置并在当前终端生效。
inject_shellenv_block() {
  local profile_file="$1"
  local shellenv_cmd="$2"
  local header="# >>> Jobs Homebrew shellenv >>>"
  local footer="# <<< Jobs Homebrew shellenv <<<"
  if [[ -z "$profile_file" || -z "$shellenv_cmd" ]]; then
    error_echo "缺少参数：inject_shellenv_block <profile_file> <shellenv_cmd>"
    return 1
  fi
  mkdir -p "$(dirname "$profile_file")"
  touch "$profile_file"
  if grep -Fq "$shellenv_cmd" "$profile_file"; then
    info_echo "Homebrew shellenv 已存在：$profile_file"
  else
    {
      echo ""
      echo "$header"
      echo "$shellenv_cmd"
      echo "$footer"
    } >> "$profile_file"
    success_echo "已写入 Homebrew shellenv：$profile_file"
  fi
  eval "$shellenv_cmd"
  success_echo "Homebrew shellenv 已在当前终端生效"
}
# 初始化脚本运行环境和后续流程所需状态。
initialize_script_runtime() {
  setopt NO_NOMATCH
  : > "$LOG_FILE"
}
# 编排脚本的高层业务流程。
main() {
  # 展示脚本内置自述，并按运行入口完成防误触确认。
  show_readme_and_wait
  # 初始化 Shell 选项、日志、依赖和入口运行状态。
  initialize_script_runtime
  # 执行入口下沉后的完整业务流程。
  run_main_business_flow "$@"
}

main "$@"
