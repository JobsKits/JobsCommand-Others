#!/bin/zsh
# 脚本自述：
# - 脚本名称：【MacOS】去乱码.command
# - 核心用途：执行“去乱码”对应的自动化任务。
# - 影响范围：可能修改当前项目、用户环境或脚本指定的目标。
# - 运行提示：运行后会先打印内置自述；终端模式按回车确认后继续，按 Ctrl+C 可取消。


SCRIPT_BASENAME=$(basename "$0" | sed 's/\.[^.]*$//')   # 当前脚本名（去掉扩展名）
LOG_FILE="/tmp/${SCRIPT_BASENAME}.log"                  # 设置对应的日志文件路径
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
  print -r -- '============================== 脚本内置自述 =============================='
  print -r -- '脚本名称：【MacOS】去乱码.command'
  print -r -- '核心用途：执行“去乱码”对应的自动化任务。'
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
# 编排脚本的高层业务流程。
# 解析解码模式及命令行参数。
parse_arguments() {
  if [[ "${1:-}" == "--plus" ]]; then
    MODE="plus"
    shift
  fi
  REMAINING_ARGUMENTS=("$@")
}
# 执行参数批处理或终端交互解码流程。
run_decode_flow() {
  set -- "${REMAINING_ARGUMENTS[@]}"
  # 执行当前流程中的独立业务步骤：处理当前语句。
  [[ "$MODE" == "plus" ]] && warn_echo "已启用 --plus：+ 会被解析为空格。"

  # 根据当前条件选择对应的执行分支。
  if (( $# > 0 )); then
    # 循环处理用户输入或当前批次中的全部目标。
    for item in "$@"; do
      # 执行当前流程中的独立业务步骤：note_echo。
      note_echo "原文：$item"
      # 执行当前流程中的独立业务步骤：handle_one。
      handle_one "$item"
    done
    # 执行当前流程中的独立业务步骤：pause_to_exit。
    pause_to_exit
    # 执行当前流程中的独立业务步骤：return。
    return 0
  fi

  # 循环处理用户输入或当前批次中的全部目标。
  while true; do
    # 输出当前步骤的提示或执行进度。
    echo ""
    # 收集用户输入，供后续业务判断使用。
    read -r "?➤ 输入 URL 编码字符串（q / quit / exit 退出）：" input
    # 根据当前条件选择对应的执行分支。
    case "$input" in
      # 执行当前流程中的独立业务步骤：q。
      q|quit|exit) info_echo "已退出。"; break ;;
      # 执行当前流程中的独立业务步骤：处理当前语句。
      "") continue ;;
      # 执行当前流程中的独立业务步骤：处理当前语句。
      *) handle_one "$input" ;;
    esac
  done
}
# 编排脚本的高层业务流程。
# 初始化脚本运行环境，并集中承载原有的顶层执行逻辑。
initialize_script_runtime() {
  setopt NO_NOMATCH
  : > "$LOG_FILE"
}
# 编排脚本的高层业务流程。
main() {
  # 展示脚本说明并等待用户确认影响范围。
  show_readme_and_wait
  # 初始化 Shell 选项、日志、依赖和入口运行状态。
  initialize_script_runtime
  # 解析解码模式并保存剩余命令行参数。
  parse_arguments "$@"
  # 执行批量参数或终端交互解码流程。
  run_decode_flow
}

main "$@"
