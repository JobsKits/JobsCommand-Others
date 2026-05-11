#!/bin/zsh

setopt NO_NOMATCH

SCRIPT_BASENAME=$(basename "$0" | sed 's/\.[^.]*$//')   # 当前脚本名（去掉扩展名）
LOG_FILE="/tmp/${SCRIPT_BASENAME}.log"                  # 设置对应的日志文件路径
: > "$LOG_FILE"

log()            { echo -e "$1" | tee -a "$LOG_FILE"; }
color_echo()     { log "\033[1;32m$1\033[0m"; }         # ✅ 正常绿色输出
info_echo()      { log "\033[1;34mℹ $1\033[0m"; }       # ℹ 信息
success_echo()   { log "\033[1;32m✔ $1\033[0m"; }       # ✔ 成功
warn_echo()      { log "\033[1;33m⚠ $1\033[0m"; }       # ⚠ 警告
warm_echo()      { log "\033[1;33m$1\033[0m"; }         # 🟡 温馨提示（无图标）
note_echo()      { log "\033[1;35m➤ $1\033[0m"; }       # ➤ 说明
error_echo()     { log "\033[1;31m✖ $1\033[0m"; }       # ✖ 错误
err_echo()       { log "\033[1;31m$1\033[0m"; }         # 🔴 错误纯文本
debug_echo()     { log "\033[1;35m🐞 $1\033[0m"; }      # 🐞 调试
highlight_echo() { log "\033[1;36m🔹 $1\033[0m"; }      # 🔹 高亮
gray_echo()      { log "\033[0;90m$1\033[0m"; }         # ⚫ 次要信息
bold_echo()      { log "\033[1m$1\033[0m"; }            # 📝 加粗
underline_echo() { log "\033[4m$1\033[0m"; }            # 🔗 下划线

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]:-${(%):-%x}}")" && pwd)"
SCRIPT_PATH="${SCRIPT_DIR}/$(basename -- "$0")"

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

pause_to_exit() {
  echo ""
  read -r "?🔚 按回车退出..." _
}

ask_any_to_run() {
  local message="$1"
  local answer=""
  read -r "?${message}（直接回车跳过；输入任意字符后回车执行）：" answer
  [[ -n "$answer" ]]
}

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

SELECTED_APP_PATH=""

# 选择 App 路径。
select_app_path() {
  local raw_path=""
  local candidates=("$SCRIPT_DIR"/*.app(N))

  if [[ ${#candidates[@]} -eq 1 ]]; then
    warn_echo "检测到当前目录存在 App：${candidates[1]}"
    read -r "?直接回车使用它；或拖入其它 .app 路径：" raw_path
    if [[ -z "$raw_path" ]]; then
      SELECTED_APP_PATH="${candidates[1]}"
      return 0
    fi
  else
    read -r "?请拖入需要修复的 .app 文件：" raw_path
  fi

  SELECTED_APP_PATH="$(strip_outer_quotes "$raw_path")"
}

# 修复 App 隔离属性。
repair_app() {
  local app_path="$1"
  [[ -d "$app_path" && "$app_path" == *.app ]] || { error_echo "不是有效的 .app 路径：$app_path"; return 1; }

  warn_echo "即将修改 App 隔离属性：$app_path"
  warn_echo "只建议对你信任来源的 App 使用。"
  read -r "?确认继续请键入 YES 后回车：" confirm
  [[ "$confirm" == "YES" ]] || { warn_echo "已取消。"; return 1; }

  sudo xattr -rd com.apple.quarantine "$app_path" || {
    error_echo "移除 quarantine 失败。"
    return 1
  }
  success_echo "已移除 quarantine 属性。"

  if ask_any_to_run "是否执行 ad-hoc 重签名"; then
    sudo codesign --force --deep --sign - "$app_path" || warn_echo "重签名失败，可能不影响移除隔离属性。"
  else
    info_echo "已跳过重签名。"
  fi
}

# 主流程统一收口。
main() {
  show_readme_and_wait
  select_app_path
  repair_app "$SELECTED_APP_PATH"
  success_echo "处理完成。"
  pause_to_exit
}

main "$@"
