#!/bin/zsh
# 脚本自述：
# - 脚本名称：【MacOS】⏬下载Mock数据.command
# - 核心用途：执行“⏬下载Mock数据”对应的自动化任务。
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
  print -r -- '脚本名称：【MacOS】⏬下载Mock数据.command'
  print -r -- '核心用途：执行“⏬下载Mock数据”对应的自动化任务。'
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

REPO_URL="https://github.com/JobsKits/JobsMockData.git"
REPO_NAME="JobsMockData"
TARGET_DIR="${SCRIPT_DIR}/${REPO_NAME}"
# 检查 git。
ensure_git() {
  if ! command -v git >/dev/null 2>&1; then
    error_echo "未检测到 git。请先安装 Xcode Command Line Tools 或 Git。"
    exit 1
  fi
}
# 校验本地仓库来源。
validate_repo() {
  local origin=""
  origin="$(git -C "$TARGET_DIR" remote get-url origin 2>/dev/null || true)"
  if [[ -z "$origin" ]]; then
    warn_echo "本地仓库没有 origin，跳过远程校验。"
    return 0
  fi
  if [[ "$origin" == "https://github.com/JobsKits/JobsMockData.git" || "$origin" == "git@github.com:JobsKits/JobsMockData.git" ]]; then
    return 0
  fi
  error_echo "目标目录是 Git 仓库，但 origin 不是 JobsKits/JobsMockData：$origin"
  exit 1
}
# 克隆或按需更新 Mock 数据仓库。
clone_or_update_repo() {
  info_echo "脚本目录：$SCRIPT_DIR"
  info_echo "目标目录：$TARGET_DIR"

  if [[ -d "$TARGET_DIR/.git" || -f "$TARGET_DIR/.git" ]]; then
    validate_repo
    warn_echo "检测到本地仓库已存在。"
    if ask_any_to_run "是否拉取远程更新"; then
      git -C "$TARGET_DIR" pull --rebase --autostash || {
        error_echo "仓库更新失败。请进入目录手动处理冲突：$TARGET_DIR"
        exit 1
      }
      success_echo "Mock 数据仓库已更新。"
    else
      info_echo "已跳过仓库更新。"
    fi
  elif [[ -e "$TARGET_DIR" ]]; then
    error_echo "目标路径已存在，但不是 Git 仓库：$TARGET_DIR"
    exit 1
  else
    note_echo "开始克隆仓库：$REPO_URL"
    git clone "$REPO_URL" "$TARGET_DIR" || {
      error_echo "仓库克隆失败。请检查网络或 GitHub 访问。"
      exit 1
    }
    success_echo "Mock 数据仓库已下载。"
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
  show_script_intro_and_wait
  # 初始化 Shell 选项、日志、依赖和入口运行状态。
  initialize_script_runtime
  # 检查当前环境与执行条件是否满足脚本要求。
  ensure_git
  # 执行 clone_or_update_repo 对应的核心业务步骤。
  clone_or_update_repo
  # 输出脚本执行结果、摘要和日志位置。
  success_echo "处理完成。"
  # 执行 pause_to_exit 对应的独立业务步骤。
  pause_to_exit
}

main "$@"
