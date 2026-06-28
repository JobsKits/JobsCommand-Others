#!/bin/zsh
# 脚本自述：
# - 脚本名称：【MacOS】全文件搜索文字替换.command
# - 核心用途：执行“全文件搜索文字替换”对应的自动化任务。
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
show_script_intro_and_wait() {
  clear
  print -r -- '============================== 脚本内置自述 =============================='
  print -r -- '脚本名称：【MacOS】全文件搜索文字替换.command'
  print -r -- '核心用途：执行“全文件搜索文字替换”对应的自动化任务。'
  print -r -- '影响范围：可能修改当前项目、用户环境或脚本指定的目标。'
  print -r -- '取消方式：确认前按 Ctrl+C 终止，不会继续执行后续业务。'
  print -r -- '============================================================================'
  echo ""
  read -r "?👉 已了解脚本用途与影响，按回车继续；按 Ctrl+C 取消：" _
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

BACKUP_ENABLED="false"
# 判断文本文件。
is_text_file() {
  grep -Iq . "$1" 2>/dev/null
}
# 替换单个文件。
replace_in_file() {
  local file_path="$1"
  local search_term="$2"
  local replace_term="$3"

  [[ -f "$file_path" ]] || return 1
  is_text_file "$file_path" || return 1
  grep -Fq -- "$search_term" "$file_path" || return 1

  [[ "$BACKUP_ENABLED" == "true" ]] && cp "$file_path" "${file_path}.bak"
  SEARCH_TERM="$search_term" REPLACE_TERM="$replace_term" perl -0pi -e 'BEGIN { $s=$ENV{"SEARCH_TERM"}; $r=$ENV{"REPLACE_TERM"}; } s/\Q$s\E/$r/g' "$file_path"
  success_echo "已替换：$file_path"
}
# 扫描目标。
replace_in_target() {
  local target_path="$1"
  local search_term="$2"
  local replace_term="$3"
  local count=0

  if [[ -f "$target_path" ]]; then
    replace_in_file "$target_path" "$search_term" "$replace_term" && count=$((count + 1))
  elif [[ -d "$target_path" ]]; then
    while IFS= read -r -d '' file_path; do
      if grep -Fq -- "$search_term" "$file_path" 2>/dev/null; then
        replace_in_file "$file_path" "$search_term" "$replace_term"
        count=$((count + 1))
      fi
    done < <(find "$target_path" \
      -path "*/.git" -prune -o \
      -path "*/node_modules" -prune -o \
      -path "*/Pods" -prune -o \
      -type f -print0)
  else
    error_echo "目标路径不存在：$target_path"
    return 1
  fi

  success_echo "命中文件数：$count"
}
# 执行入口下沉后的完整业务流程和控制逻辑。
run_main_business_flow() {
  # 收集用户输入，供后续业务判断使用。
  read -r "?请输入要搜索的文本：" search_term
  # 执行当前流程中的独立业务步骤：处理当前语句。
  [[ -z "$search_term" ]] && { error_echo "搜索文本不能为空。"; pause_to_exit; exit 1; }

  # 收集用户输入，供后续业务判断使用。
  read -r "?请输入替换后的文本：" replace_term
  # 收集用户输入，供后续业务判断使用。
  read -r "?请拖入目标文件或目录：" raw_path
  # 初始化当前流程后续步骤需要使用的变量。
  local target_path="$(strip_outer_quotes "$raw_path")"

  # 根据当前条件选择对应的执行分支。
  if ask_any_to_run "是否在替换前为命中文件生成 .bak 备份"; then
    # 初始化当前流程后续步骤需要使用的变量。
    BACKUP_ENABLED="true"
  fi

  # 执行当前流程中的独立业务步骤：replace_in_target。
  replace_in_target "$target_path" "$search_term" "$replace_term"
  # 输出当前流程的完成状态、摘要和日志位置。
  success_echo "处理完成。"
  # 执行当前流程中的独立业务步骤：pause_to_exit。
  pause_to_exit
}
# 编排脚本的高层业务流程。
# 初始化脚本运行环境，并集中承载原有的顶层执行逻辑。
initialize_script_runtime() {
  setopt NO_NOMATCH
  : > "$LOG_FILE"
}
# 编排脚本的高层业务流程。
main() {
  # 展示脚本内置自述，并按运行入口完成防误触确认。
  show_script_intro_and_wait
  # 初始化 Shell 选项、日志、依赖和入口运行状态。
  initialize_script_runtime
  # 执行入口下沉后的完整业务流程。
  run_main_business_flow "$@"
}

main "$@"
