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

# 授权一个路径。
authorize_path() {
  local path="$1"
  if [[ -e "$path" ]]; then
    chmod +x "$path" && success_echo "授权成功：$path" || error_echo "授权失败：$path"
  else
    error_echo "无效路径：$path"
  fi
}

# 授权当前目录 command 文件。
authorize_current_dir() {
  local files=("$SCRIPT_DIR"/*.command(N))
  [[ ${#files[@]} -gt 0 ]] || { error_echo "当前目录没有 .command 文件。"; return 1; }
  for file in "${files[@]}"; do
    authorize_path "$file"
  done
}

# 递归授权 command 文件。
authorize_recursively() {
  local found="false"
  while IFS= read -r -d '' file; do
    found="true"
    authorize_path "$file"
  done < <(find "$SCRIPT_DIR" -type f -name "*.command" -print0)
  [[ "$found" == "true" ]] || error_echo "没有找到任何 .command 文件。"
}

# 授权拖入路径。
authorize_dragged_paths() {
  local raw_input="$1"
  local paths=(${(z)raw_input})
  [[ ${#paths[@]} -gt 0 ]] || { error_echo "未检测到路径。"; return 1; }
  for raw_path in "${paths[@]}"; do
    authorize_path "$(strip_outer_quotes "$raw_path")"
  done
}

# 主流程统一收口。
main() {
  show_readme_and_wait
  echo "规则："
  echo "  直接回车：授权当前目录下所有 .command 文件"
  echo "  输入 r：递归授权当前目录及子目录下所有 .command 文件"
  echo "  拖入路径：授权拖入的文件或目录"
  echo ""
  read -r "?📥 拖入路径 / 输入 r / 直接回车：" input_paths

  if [[ -z "$input_paths" ]]; then
    authorize_current_dir
  elif [[ "$input_paths" == "r" || "$input_paths" == "R" ]]; then
    authorize_recursively
  else
    authorize_dragged_paths "$input_paths"
  fi

  success_echo "处理完成。"
  pause_to_exit
}

main "$@"
