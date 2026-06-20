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

# 主流程统一收口。
run_main_flow() {
  show_readme_and_wait
  ensure_git
  clone_or_update_repo
  success_echo "处理完成。"
  pause_to_exit
}

# 统一收口脚本入口，仅委托已经拆分完成的业务流程。
main() {
  # 主入口只负责委托完整业务流程，复杂逻辑统一下沉。
  run_main_flow "$@"
}

main "$@"
