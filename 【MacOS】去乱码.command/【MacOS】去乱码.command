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

MODE="unquote"

# 复制到剪切板。
copy_clipboard() {
  local text="$1"
  [[ -z "$text" ]] && return 0
  if command -v pbcopy >/dev/null 2>&1; then
    printf "%s" "$text" | pbcopy
    success_echo "已复制到系统剪切板。"
  else
    warn_echo "未检测到 pbcopy，已跳过复制。"
  fi
}

# URL 解码。
decode_text() {
  local mode="$1"
  if command -v python3 >/dev/null 2>&1; then
    python3 -c 'import sys
from urllib.parse import unquote, unquote_plus
mode=sys.argv[1]
data=sys.stdin.read()
fn=unquote_plus if mode=="plus" else unquote
sys.stdout.write("\n".join(fn(line) for line in data.splitlines()))
' "$mode"
  elif command -v ruby >/dev/null 2>&1; then
    ruby -e 'require "uri"
mode=ARGV[0]
data=STDIN.read
fn = mode == "plus" ? ->(s){ URI.decode_www_form_component(s) } : ->(s){ URI::DEFAULT_PARSER.unescape(s) }
print data.lines.map { |line| fn.call(line.chomp) }.join("\n")
' "$mode"
  else
    error_echo "缺少 python3 或 ruby，无法解码。"
    return 1
  fi
}

# 处理一个输入。
handle_one() {
  local input="$1"
  local decoded=""
  decoded="$(printf "%s" "$input" | decode_text "$MODE")" || return 1
  success_echo "解码结果："
  printf "%s\n" "$decoded" | tee -a "$LOG_FILE"
  copy_clipboard "$decoded"
}

# 主流程统一收口。
run_main_flow() {
  if [[ "${1:-}" == "--plus" ]]; then
    MODE="plus"
    shift
  fi

  show_readme_and_wait
  [[ "$MODE" == "plus" ]] && warn_echo "已启用 --plus：+ 会被解析为空格。"

  if (( $# > 0 )); then
    for item in "$@"; do
      note_echo "原文：$item"
      handle_one "$item"
    done
    pause_to_exit
    return 0
  fi

  while true; do
    echo ""
    read -r "?➤ 输入 URL 编码字符串（q / quit / exit 退出）：" input
    case "$input" in
      q|quit|exit) info_echo "已退出。"; break ;;
      "") continue ;;
      *) handle_one "$input" ;;
    esac
  done
}

# 统一收口脚本入口，仅委托已经拆分完成的业务流程。
main() {
  # 主入口只负责委托完整业务流程，复杂逻辑统一下沉。
  run_main_flow "$@"
}

main "$@"
