#!/bin/zsh
# 脚本自述：
# - 脚本名称：【MacOS】⚙️『 已损坏，无法打开: 来自身份不明的开发者』等问题修复工具.command
# - 核心用途：执行“⚙️『 已损坏，无法打开: 来自身份不明的开发者』等问题修复工具”对应的快捷打开任务。
# - 影响范围：主要影响应用启动与路径跳转，不主动改写业务文件。
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
  print -r -- '脚本名称：【MacOS】⚙️『 已损坏，无法打开: 来自身份不明的开发者』等问题修复工具.command'
  print -r -- '核心用途：执行“⚙️『 已损坏，无法打开: 来自身份不明的开发者』等问题修复工具”对应的快捷打开任务。'
  print -r -- '影响范围：主要影响应用启动与路径跳转，不主动改写业务文件。'
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
  # 执行 select_app_path 对应的独立业务步骤。
  select_app_path
  # 执行 repair_app 对应的独立业务步骤。
  repair_app "$SELECTED_APP_PATH"
  # 输出脚本执行结果、摘要和日志位置。
  success_echo "处理完成。"
  # 执行 pause_to_exit 对应的独立业务步骤。
  pause_to_exit
}

main "$@"
