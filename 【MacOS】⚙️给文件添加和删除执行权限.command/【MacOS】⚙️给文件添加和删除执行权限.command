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

# 处理拖入路径。
handle_paths() {
  local mode="$1"
  local raw_input="$2"
  local paths=(${(z)raw_input})

  if [[ ${#paths[@]} -eq 0 ]]; then
    error_echo "未检测到路径。"
    return 1
  fi

  for raw_path in "${paths[@]}"; do
    local path="$(strip_outer_quotes "$raw_path")"
    if [[ ! -e "$path" ]]; then
      error_echo "路径不存在：$path"
      continue
    fi

    if [[ "$mode" == "add" ]]; then
      chmod +x "$path" && success_echo "已添加执行权限：$path" || error_echo "添加失败：$path"
    else
      chmod -x "$path" && success_echo "已删除执行权限：$path" || error_echo "删除失败：$path"
    fi
  done
}

# 主流程统一收口。
main() {
  show_readme_and_wait
  echo "1) 添加执行权限 chmod +x"
  echo "2) 删除执行权限 chmod -x"
  read -r "?请选择操作类型（1/2）：" choice

  local mode=""
  case "$choice" in
    1) mode="add" ;;
    2) mode="remove" ;;
    *) error_echo "无效选择。"; pause_to_exit; exit 1 ;;
  esac

  echo ""
  read -r "?请拖入一个或多个文件 / 目录，然后回车：" input_paths
  handle_paths "$mode" "$input_paths"
  success_echo "处理完成。"
  pause_to_exit
}

main "$@"
