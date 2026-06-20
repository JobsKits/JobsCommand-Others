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

PROJECT_TYPE="unknown"
PROJECT_ROOT="$SCRIPT_DIR"
FASTLANE_DIR="$SCRIPT_DIR/fastlane"
FASTFILE_PATH="$FASTLANE_DIR/Fastfile"

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

# 检查工程类型并确定 Fastfile 目录。
detect_project_type() {
  if [[ -f "$SCRIPT_DIR/pubspec.yaml" && -d "$SCRIPT_DIR/ios" ]]; then
    PROJECT_TYPE="flutter"
    PROJECT_ROOT="$SCRIPT_DIR/ios"
    FASTLANE_DIR="$PROJECT_ROOT/fastlane"
    FASTFILE_PATH="$FASTLANE_DIR/Fastfile"
    success_echo "检测到 Flutter 工程，Fastfile 将放在 ios/fastlane。"
  elif ls "$SCRIPT_DIR"/*.xcodeproj >/dev/null 2>&1 || ls "$SCRIPT_DIR"/*.xcworkspace >/dev/null 2>&1; then
    PROJECT_TYPE="ios"
    PROJECT_ROOT="$SCRIPT_DIR"
    FASTLANE_DIR="$PROJECT_ROOT/fastlane"
    FASTFILE_PATH="$FASTLANE_DIR/Fastfile"
    success_echo "检测到原生 iOS 工程。"
  else
    warn_echo "未识别到 Flutter / iOS 工程，将按当前目录处理。"
  fi
}

# 安装或按需升级 brew 包。
ensure_brew_formula() {
  local formula="$1"
  if brew list --formula "$formula" >/dev/null 2>&1; then
    success_echo "$formula 已安装。"
    if ask_any_to_run "是否升级 $formula"; then
      brew upgrade "$formula" || warn_echo "$formula 升级失败或无需升级。"
    else
      info_echo "已跳过 $formula 升级。"
    fi
  else
    note_echo "安装 $formula。"
    brew install "$formula" || {
      error_echo "$formula 安装失败。"
      exit 1
    }
  fi
}

# 创建默认 Fastfile。
create_default_fastfile() {
  mkdir -p "$FASTLANE_DIR"
  if [[ -f "$FASTFILE_PATH" ]]; then
    success_echo "Fastfile 已存在：$FASTFILE_PATH"
    return 0
  fi

  cat > "$FASTFILE_PATH" <<'EOF'
default_platform(:ios)

platform :ios do
  desc "Build app locally"
  lane :build do
    build_app
  end
end
EOF
  success_echo "已创建 Fastfile：$FASTFILE_PATH"
}

# 选择编辑器打开 Fastfile。
open_fastfile() {
  local editor=""
  if command -v fzf >/dev/null 2>&1; then
    editor="$(printf "Xcode\nVSCode\nAndroid Studio\nFinder\n跳过" | fzf --prompt="🎨 选择打开方式: " --height=10 --reverse)"
  else
    echo "1) Xcode"
    echo "2) VSCode"
    echo "3) Android Studio"
    echo "4) Finder"
    echo "5) 跳过"
    read -r "?请选择打开方式：" editor_choice
    case "$editor_choice" in
      1) editor="Xcode" ;;
      2) editor="VSCode" ;;
      3) editor="Android Studio" ;;
      4) editor="Finder" ;;
      *) editor="跳过" ;;
    esac
  fi

  case "$editor" in
    "Xcode") open -a Xcode "$FASTFILE_PATH" ;;
    "VSCode") open -a "Visual Studio Code" "$FASTFILE_PATH" ;;
    "Android Studio") open -a "Android Studio" "$FASTFILE_PATH" ;;
    "Finder") open -R "$FASTFILE_PATH" ;;
    *) info_echo "已跳过打开 Fastfile。" ;;
  esac
}

# 主流程统一收口。
run_main_flow() {
  show_readme_and_wait
  detect_project_type
  ensure_homebrew
  ensure_brew_formula "fzf"
  ensure_brew_formula "fastlane"
  create_default_fastfile
  open_fastfile
  success_echo "处理完成。"
  pause_to_exit
}

# 统一收口脚本入口，仅委托已经拆分完成的业务流程。
main() {
  # 主入口只负责委托完整业务流程，复杂逻辑统一下沉。
  run_main_flow "$@"
}

main "$@"
