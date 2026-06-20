#!/bin/zsh

setopt NO_NOMATCH

SCRIPT_BASENAME=$(basename "$0" | sed 's/\.[^.]*$//')   # 当前脚本名（去掉扩展名）
LOG_FILE="/tmp/${SCRIPT_BASENAME}.log"                  # 设置对应的日志文件路径
: > "$LOG_FILE"

# 按当前输出级别记录终端信息，并同步写入脚本日志。
log()            { echo -e "$1" | tee -a "$LOG_FILE"; }
# 按当前输出级别记录终端信息，并同步写入脚本日志。
color_echo()     { log "\033[1;32m$1\033[0m"; }         # ✅ 正常绿色输出
# 按当前输出级别记录终端信息，并同步写入脚本日志。
info_echo()      { log "\033[1;34mℹ $1\033[0m"; }       # ℹ 信息
# 按当前输出级别记录终端信息，并同步写入脚本日志。
success_echo()   { log "\033[1;32m✔ $1\033[0m"; }       # ✔ 成功
# 按当前输出级别记录终端信息，并同步写入脚本日志。
warn_echo()      { log "\033[1;33m⚠ $1\033[0m"; }       # ⚠ 警告
# 按当前输出级别记录终端信息，并同步写入脚本日志。
warm_echo()      { log "\033[1;33m$1\033[0m"; }         # 🟡 温馨提示（无图标）
# 按当前输出级别记录终端信息，并同步写入脚本日志。
note_echo()      { log "\033[1;35m➤ $1\033[0m"; }       # ➤ 说明
# 按当前输出级别记录终端信息，并同步写入脚本日志。
error_echo()     { log "\033[1;31m✖ $1\033[0m"; }       # ✖ 错误
# 按当前输出级别记录终端信息，并同步写入脚本日志。
err_echo()       { log "\033[1;31m$1\033[0m"; }         # 🔴 错误纯文本
# 按当前输出级别记录终端信息，并同步写入脚本日志。
debug_echo()     { log "\033[1;35m🐞 $1\033[0m"; }      # 🐞 调试
# 按当前输出级别记录终端信息，并同步写入脚本日志。
highlight_echo() { log "\033[1;36m🔹 $1\033[0m"; }      # 🔹 高亮
# 按当前输出级别记录终端信息，并同步写入脚本日志。
gray_echo()      { log "\033[0;90m$1\033[0m"; }         # ⚫ 次要信息
# 按当前输出级别记录终端信息，并同步写入脚本日志。
bold_echo()      { log "\033[1m$1\033[0m"; }            # 📝 加粗
# 按当前输出级别记录终端信息，并同步写入脚本日志。
underline_echo() { log "\033[4m$1\033[0m"; }            # 🔗 下划线

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]:-${(%):-%x}}")" && pwd)"
SCRIPT_PATH="${SCRIPT_DIR}/$(basename -- "$0")"

# 展示脚本用途和影响范围，并在执行前等待用户确认。
show_readme_and_wait() {
  local readme_path="${SCRIPT_DIR}/README.md"
  clear
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

# 封装 pause_to_exit 对应的独立处理逻辑。
pause_to_exit() {
  echo ""
  read -r "?🔚 按回车退出..." _
}

# 收集并校验用户输入，决定后续执行路径。
ask_any_to_run() {
  local message="$1"
  local answer=""
  read -r "?${message}（直接回车跳过；输入任意字符后回车执行）：" answer
  [[ -n "$answer" ]]
}

# 封装 strip_outer_quotes 对应的独立处理逻辑。
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

# 打印脚本定位。
print_builtin_intro() {
  highlight_echo "🧰 Homebrew 与常用开发工具安装脚本"
  note_echo "日志文件：$LOG_FILE"
  note_echo "脚本路径：$SCRIPT_PATH"
}

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

# 安装缺失的 formula。
install_formulae() {
  local formulae=(
    git wget curl openssl readline sqlite3 xz pkg-config coreutils lrzsz
    clang-format git-flow ffmpeg watchman gnupg node nvm python3 ruby yarn
    carthage maven openjdk php mysql nginx tomcat autojump
  )

  highlight_echo "开始检查常用 formula。"
  for pkg in "${formulae[@]}"; do
    if brew list --formula "$pkg" >/dev/null 2>&1; then
      info_echo "已安装，跳过：$pkg"
    else
      note_echo "安装：$pkg"
      brew install "$pkg" || warn_echo "安装失败或已不可用：$pkg"
    fi
  done
}

# 安装缺失的 cask。
install_casks() {
  local casks=(docker iterm2 flutter)

  highlight_echo "开始检查常用 cask。"
  for pkg in "${casks[@]}"; do
    if brew list --cask "$pkg" >/dev/null 2>&1; then
      info_echo "已安装，跳过：$pkg"
    else
      note_echo "安装：$pkg"
      brew install --cask "$pkg" || warn_echo "安装失败或已不可用：$pkg"
    fi
  done
}

# 主流程统一收口。
run_main_flow() {
  show_readme_and_wait
  print_builtin_intro
  ensure_homebrew
  install_formulae
  install_casks
  brew cleanup || true
  success_echo "处理完成。"
  pause_to_exit
}

# 统一收口脚本入口，仅委托已经拆分完成的业务流程。
main() {
  # 主入口只负责委托完整业务流程，复杂逻辑统一下沉。
  run_main_flow "$@"
}

main "$@"
