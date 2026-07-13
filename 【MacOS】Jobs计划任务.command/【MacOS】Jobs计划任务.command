#!/bin/zsh
# shell: zsh
# 脚本自述：
# - 脚本名称：Jobs计划任务.command
# - 核心用途：编译、安装、启动、修复或卸载 Jobs 计划任务菜单栏 App。
# - 影响范围：写入当前用户的 Applications、Application Support 和 LaunchAgents 目录。
# - 运行提示：运行后先展示说明并等待确认；卸载等危险动作必须输入 YES。

readonly SCRIPT_DIR="$(cd "$(dirname "${(%):-%x}")" && pwd)"
readonly APP_NAME="Jobs计划任务.app"
readonly INSTALL_DIR="$HOME/Applications"
readonly APP_PATH="$INSTALL_DIR/$APP_NAME"
readonly BUILD_BINARY="$SCRIPT_DIR/.build/release/JobsScheduler"
readonly DATA_DIR="$HOME/Library/Application Support/com.jobs.scheduler"
readonly LOG_FILE="$TMPDIR/Jobs计划任务.log"

# 记录终端信息并同步写入日志。
log() { print -r -- "$1" | tee -a "$LOG_FILE"; }
# 输出普通信息。
info_echo() { log "ℹ $1"; }
# 输出成功信息。
success_echo() { log "✔ $1"; }
# 输出警告信息。
warn_echo() { log "⚠ $1"; }
# 输出错误信息。
error_echo() { log "✖ $1"; }
# 打印脚本内置自述并等待明确确认。
show_script_intro_and_wait() {
  clear
  log "============================== 脚本自述 =============================="
  log "当前脚本：$SCRIPT_DIR/Jobs计划任务.command"
  log "核心用途：管理 Jobs 计划任务菜单栏 App 的安装、启动、升级和卸载。"
  log "影响范围：$APP_PATH、$DATA_DIR 和当前用户的 LaunchAgents。"
  log "安全边界：不保存管理员密码；危险卸载操作必须输入 YES。"
  log "日志位置：$LOG_FILE"
  log "取消方式：按 Ctrl+C 终止。"
  log "======================================================================="
  print ""
  read -r "?👉 已了解脚本用途与影响，按回车继续；按 Ctrl+C 取消：" _
}
# 初始化运行环境和日志文件。
initialize_environment() {
  setopt NO_NOMATCH
  : > "$LOG_FILE"
}
# 检查构建和系统管理依赖。
check_environment() {
  local command_name=""
  for command_name in swift codesign open launchctl plutil; do
    if ! command -v "$command_name" >/dev/null 2>&1; then
      error_echo "缺少命令：$command_name"
      return 1
    fi
  done
}
# 编译 Swift 工程并组装原生 App Bundle。
build_and_install_app() {
  info_echo "开始 Release 编译，请稍候……"
  if ! swift build -c release --package-path "$SCRIPT_DIR" 2>&1 | tee -a "$LOG_FILE"; then
    error_echo "Swift 编译失败。"
    return 1
  fi
  mkdir -p "$INSTALL_DIR" "$APP_PATH/Contents/MacOS" "$APP_PATH/Contents/Resources"
  cp "$BUILD_BINARY" "$APP_PATH/Contents/MacOS/JobsScheduler"
  cp "$SCRIPT_DIR/Resources/Info.plist" "$APP_PATH/Contents/Info.plist"
  chmod 755 "$APP_PATH/Contents/MacOS/JobsScheduler"
  if ! codesign --force --deep --sign - "$APP_PATH" 2>&1 | tee -a "$LOG_FILE"; then
    error_echo "App 临时签名失败。"
    return 1
  fi
  success_echo "已安装：$APP_PATH"
}
# 启动已经安装的菜单栏 App。
open_installed_app() {
  if [[ ! -d "$APP_PATH" ]]; then
    warn_echo "尚未安装，先执行安装。"
    build_and_install_app || return 1
  fi
  open "$APP_PATH"
  success_echo "Jobs 计划任务已启动，菜单栏会显示日历时钟图标。"
}
# 重新安装 App 并保持任务数据不变。
upgrade_app() {
  /usr/bin/pkill -x JobsScheduler >/dev/null 2>&1 || true
  build_and_install_app || return 1
  open_installed_app
}
# 输出 App、数据和 LaunchAgent 的诊断结果。
diagnose_app() {
  info_echo "系统版本：$(sw_vers -productVersion)"
  info_echo "Swift：$(swift --version 2>&1 | head -n 1)"
  [[ -d "$APP_PATH" ]] && success_echo "App 已安装：$APP_PATH" || warn_echo "App 尚未安装"
  [[ -d "$DATA_DIR" ]] && success_echo "数据目录存在：$DATA_DIR" || info_echo "数据目录尚未创建"
  local count
  count=$(find "$HOME/Library/LaunchAgents" -maxdepth 1 -name 'com.jobs.scheduler.task.*.plist' 2>/dev/null | wc -l | tr -d ' ')
  info_echo "当前已生成 $count 个任务 LaunchAgent。"
  plutil -lint "$SCRIPT_DIR/Resources/Info.plist" 2>&1 | tee -a "$LOG_FILE"
}
# 卸载 App 和任务注册，并按选择保留或删除数据。
uninstall_app() {
  warn_echo "将退出 App、注销全部 Jobs 计划任务并删除已安装 App。"
  read -r "?危险操作必须输入 YES 后回车；其它输入一律取消：" answer
  if [[ "$answer" != "YES" ]]; then
    info_echo "已取消卸载。"
    return 0
  fi
  /usr/bin/pkill -x JobsScheduler >/dev/null 2>&1 || true
  local plist=""
  for plist in "$HOME/Library/LaunchAgents"/com.jobs.scheduler.task.*.plist; do
    [[ -e "$plist" ]] || continue
    launchctl bootout "gui/$(id -u)" "$plist" >/dev/null 2>&1 || true
    rm -f "$plist"
  done
  rm -rf "$APP_PATH"
  read -r "?是否同时删除任务数据和日志？必须输入 DELETE 后回车才会删除：" delete_answer
  if [[ "$delete_answer" == "DELETE" ]]; then
    rm -rf "$DATA_DIR"
    warn_echo "任务数据和日志已删除。"
  else
    info_echo "任务数据和日志已保留：$DATA_DIR"
  fi
  success_echo "卸载完成。"
}
# 展示管理菜单并执行用户选中的动作。
show_menu_and_run() {
  print ""
  log "1. 安装并启动"
  log "2. 直接启动"
  log "3. 重新编译升级"
  log "4. 环境诊断"
  log "5. 卸载"
  log "0. 退出"
  print ""
  read -r "?👉 请输入序号，默认 1：" choice
  case "${choice:-1}" in
    1) build_and_install_app && open_installed_app ;;
    2) open_installed_app ;;
    3) upgrade_app ;;
    4) diagnose_app ;;
    5) uninstall_app ;;
    0) info_echo "已退出。" ;;
    *) error_echo "无效序号：$choice"; return 1 ;;
  esac
}
# 编排脚本说明、环境检查和 App 管理流程。
main() {
  show_script_intro_and_wait # 展示脚本影响范围，并在用户确认前阻止真实操作。
  initialize_environment # 初始化 zsh 选项并创建本次运行日志。
  check_environment # 检查 Swift、签名和系统调度依赖是否可用。
  show_menu_and_run # 展示 App 管理入口并执行用户选择的动作。
}

main "$@"
