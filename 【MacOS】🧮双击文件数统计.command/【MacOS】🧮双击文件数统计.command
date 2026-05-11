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

TOTAL_FILE_COUNT=0

# 打印目录文件数。
print_folder_report() {
  local folder_path="$1"
  local root_len=${#folder_path}

  while IFS= read -r -d '' dir_path; do
    local rel="${dir_path#$folder_path}"
    local depth=0
    local indent=""
    [[ -z "$rel" ]] && rel="/"
    depth=$(echo "$rel" | awk -F/ '{print NF-1}')
    for ((i=0; i<depth; i++)); do indent="  $indent"; done

    local count="$(find "$dir_path" -maxdepth 1 -type f | wc -l | tr -d ' ')"
    TOTAL_FILE_COUNT=$((TOTAL_FILE_COUNT + count))
    log "${indent}📁 $(basename "$dir_path") - ${count} 个文件"
  done < <(find "$folder_path" -type d -print0)
}

# 主流程统一收口。
main() {
  show_readme_and_wait
  local folder_path="${1:-}"
  if [[ -z "$folder_path" ]]; then
    read -r "?📂 请拖入一个文件夹路径后回车：" folder_path
  fi
  folder_path="$(strip_outer_quotes "$folder_path")"

  [[ -d "$folder_path" ]] || { error_echo "路径无效或不是文件夹：$folder_path"; pause_to_exit; exit 1; }

  highlight_echo "📊 文件夹报告：$folder_path"
  highlight_echo "======================================================================="
  print_folder_report "$folder_path"
  highlight_echo "======================================================================="
  success_echo "总文件数：$TOTAL_FILE_COUNT 个"
  pause_to_exit
}

main "$@"
