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

DEFAULT_FILE="$HOME/.bash_profile"
DEFAULT_LINE='export PATH="$PATH:/usr/local/bin"'

# 展开常见用户路径。
expand_user_path() {
  local path="$1"
  path="$(strip_outer_quotes "$path")"
  [[ -z "$path" ]] && path="$DEFAULT_FILE"
  path="${path/#\~/$HOME}"
  path="${path/\$HOME/$HOME}"
  print -r -- "$path"
}

# 判断非注释行是否已存在。
line_exists_as_active() {
  local file_path="$1"
  local target_line="$2"
  awk -v target="$target_line" '
    /^[[:space:]]*#/ { next }
    $0 == target { found = 1 }
    END { exit(found ? 0 : 1) }
  ' "$file_path"
}

# 写入唯一行。
append_unique_line() {
  local file_path="$1"
  local target_line="$2"
  mkdir -p "$(dirname "$file_path")"
  touch "$file_path" || { error_echo "无法创建文件：$file_path"; return 1; }

  if line_exists_as_active "$file_path" "$target_line"; then
    warn_echo "目标文件已存在相同的非注释行，跳过写入。"
  else
    echo "$target_line" >> "$file_path"
    success_echo "已写入：$target_line"
  fi
  note_echo "目标文件：$file_path"
}

# 主流程统一收口。
main() {
  show_readme_and_wait
  read -r "?请输入目标文件路径（直接回车默认 $DEFAULT_FILE）：" file_input
  read -r "?请输入要写入的字符串（直接回车使用默认 PATH 行）：" line_input

  local file_path="$(expand_user_path "$file_input")"
  local target_line="${line_input:-$DEFAULT_LINE}"

  append_unique_line "$file_path" "$target_line"
  success_echo "处理完成。"
  pause_to_exit
}

main "$@"
