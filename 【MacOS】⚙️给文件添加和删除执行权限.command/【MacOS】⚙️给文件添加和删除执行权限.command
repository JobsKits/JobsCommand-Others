#!/bin/zsh
# 脚本自述：
# - 脚本名称：【MacOS】⚙️给文件添加和删除执行权限.command
# - 核心用途：执行“⚙️给文件添加和删除执行权限”对应的清理任务。
# - 影响范围：可能删除缓存、生成物、配置记录或解除已有跟踪关系。
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
  print -r -- '脚本名称：【MacOS】⚙️给文件添加和删除执行权限.command'
  print -r -- '核心用途：执行“⚙️给文件添加和删除执行权限”对应的清理任务。'
  print -r -- '影响范围：可能删除缓存、生成物、配置记录或解除已有跟踪关系。'
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
# 执行入口下沉后的完整业务流程和控制逻辑。
run_main_business_flow() {
  # 输出当前步骤的提示或执行进度。
  echo "1) 添加执行权限 chmod +x"
  # 输出当前步骤的提示或执行进度。
  echo "2) 删除执行权限 chmod -x"
  # 收集用户输入，供后续业务判断使用。
  read -r "?请选择操作类型（1/2）：" choice

  # 初始化当前流程后续步骤需要使用的变量。
  local mode=""
  # 根据当前条件选择对应的执行分支。
  case "$choice" in
    # 执行当前流程中的独立业务步骤：处理当前语句。
    1) mode="add" ;;
    # 执行当前流程中的独立业务步骤：处理当前语句。
    2) mode="remove" ;;
    # 执行当前流程中的独立业务步骤：处理当前语句。
    *) error_echo "无效选择。"; pause_to_exit; exit 1 ;;
  esac

  # 输出当前步骤的提示或执行进度。
  echo ""
  # 收集用户输入，供后续业务判断使用。
  read -r "?请拖入一个或多个文件 / 目录，然后回车：" input_paths
  # 执行当前流程中的独立业务步骤：handle_paths。
  handle_paths "$mode" "$input_paths"
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
  show_readme_and_wait
  # 初始化 Shell 选项、日志、依赖和入口运行状态。
  initialize_script_runtime
  # 执行入口下沉后的完整业务流程。
  run_main_business_flow "$@"
}

main "$@"
