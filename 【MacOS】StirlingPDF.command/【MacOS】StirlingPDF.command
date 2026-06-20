#!/bin/zsh

# ============================================================
# Stirling-PDF macOS 本地开发部署脚本
# - 每次正常打开脚本后，先主动扫描并关闭旧的 Stirling-PDF 后台服务和端口占用
# - 前置自检 Xcode Command Line Tools / git / clang / make
# - 自检安装 Homebrew
# - 使用 brew 自检安装 node / jenv / openjdk@21 / uv / go-task
# - 读取本地记录文件，并验证本地仓库是否属于官方 Stirling-PDF
# - 记录无效或首次运行时，让用户输入/拖入本地目录
# - 目录选择阶段：直接回车继续询问；输入空格后回车才使用桌面目录
# - 手动拖入/输入目录时，只允许父目录已存在；末级 Stirling-PDF 目录缺失时自动创建
# - SSH remote 会被识别为官方仓库，并统一修正为 HTTPS remote
# - 首次 clone 前进入确认页；目录已校验后直接回车继续，不要求输入 YES
# - 已有仓库时先人工确认是否拉取远程更新；直接回车跳过，输入任意字符后执行 fetch/pull
# - Caddy 端口映射阶段固定按前端、后端顺序询问域名；直接回车继续询问，输入空格后回车跳过当前项，输入域名则配置
# - 执行 task install / task check
# - 后台静默启动 backend:dev + frontend:dev
# - 打开 http://localhost:5173
# ============================================================

emulate -R zsh
setopt NO_NOMATCH
setopt PIPE_FAIL
unsetopt XTRACE VERBOSE 2>/dev/null || true
set +xv 2>/dev/null || true

# 兜底补齐 macOS 系统命令路径，避免 PATH 被污染后找不到基础命令
export PATH="/usr/bin:/bin:/usr/sbin:/sbin:/opt/homebrew/bin:/usr/local/bin:${PATH:-}"

# ----------------------------
# 基础路径
# ----------------------------
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]:-${(%):-%x}}")" && pwd)"
SCRIPT_PATH="${SCRIPT_DIR}/$(basename -- "$0")"

SCRIPT_FILENAME="$(basename -- "$0")"
SCRIPT_BASENAME="${SCRIPT_FILENAME%.*}"
LOG_FILE="/tmp/${SCRIPT_BASENAME}.log"

STATE_DIR="$HOME/.stirling-pdf-dev"
RECORD_FILE="${STATE_DIR}/stirling-pdf.record"
SERVICE_LOG_DIR="$HOME/Library/Logs/Stirling-PDF-Dev"

BACKEND_PID_FILE="${STATE_DIR}/backend.pid"
FRONTEND_PID_FILE="${STATE_DIR}/frontend.pid"
BACKEND_LOG_FILE="${SERVICE_LOG_DIR}/backend.log"
FRONTEND_LOG_FILE="${SERVICE_LOG_DIR}/frontend.log"

REPO_OWNER="Stirling-Tools"
REPO_NAME="Stirling-PDF"
REPO_REMOTE_GITHUB_URL="https://github.com/${REPO_OWNER}/${REPO_NAME}"
REPO_HTTPS_CLONE_URL="${REPO_REMOTE_GITHUB_URL}.git"
REPO_SSH_CLONE_URL="git@github.com:${REPO_OWNER}/${REPO_NAME}.git"

FRONTEND_URL="http://localhost:5173"
BACKEND_URL="http://localhost:8080"

CADDY_FORMULA="caddy"
CADDYFILE="/tmp/${SCRIPT_BASENAME}.Caddyfile"
CADDY_STATE_FILE="${STATE_DIR}/stirling-pdf-caddy.state"

CADDY_MAP_LABELS=()
CADDY_MAP_DOMAINS=()
CADDY_MAP_UPSTREAMS=()
CADDY_MAP_LOCAL_URLS=()
CADDY_MAP_CHECK_PATHS=()
CADDY_SELECTED_DOMAIN=""
CADDY_SELECTED_TARGET_KEY=""

JAVA_FORMULA="openjdk@21"

PARENT_DIR=""
REPO_DIR=""
INPUT_VALUE=""

mkdir -p "$STATE_DIR" "$SERVICE_LOG_DIR"
: > "$LOG_FILE"

# ----------------------------
# 彩色打印函数
# ----------------------------
log()            { printf "%b\n" "$1" | tee -a "$LOG_FILE"; }
# 按当前输出级别记录终端信息，并同步写入脚本日志。
color_echo()     { log "\033[1;32m$1\033[0m"; }
# 按当前输出级别记录终端信息，并同步写入脚本日志。
info_echo()      { log "\033[1;34mℹ $1\033[0m"; }
# 按当前输出级别记录终端信息，并同步写入脚本日志。
success_echo()   { log "\033[1;32m✔ $1\033[0m"; }
# 按当前输出级别记录终端信息，并同步写入脚本日志。
warn_echo()      { log "\033[1;33m⚠ $1\033[0m"; }
# 按当前输出级别记录终端信息，并同步写入脚本日志。
warm_echo()      { log "\033[1;33m$1\033[0m"; }
# 按当前输出级别记录终端信息，并同步写入脚本日志。
note_echo()      { log "\033[1;35m➤ $1\033[0m"; }
# 按当前输出级别记录终端信息，并同步写入脚本日志。
error_echo()     { log "\033[1;31m✖ $1\033[0m"; }
# 按当前输出级别记录终端信息，并同步写入脚本日志。
err_echo()       { log "\033[1;31m$1\033[0m"; }
# 按当前输出级别记录终端信息，并同步写入脚本日志。
debug_echo()     { log "\033[1;35m🐞 $1\033[0m"; }
# 按当前输出级别记录终端信息，并同步写入脚本日志。
highlight_echo() { log "\033[1;36m🔹 $1\033[0m"; }
# 按当前输出级别记录终端信息，并同步写入脚本日志。
gray_echo()      { log "\033[0;90m$1\033[0m"; }
# 按当前输出级别记录终端信息，并同步写入脚本日志。
bold_echo()      { log "\033[1m$1\033[0m"; }
# 按当前输出级别记录终端信息，并同步写入脚本日志。
underline_echo() { log "\033[4m$1\033[0m"; }

# ----------------------------
# 通用工具函数
# ----------------------------
disable_debug_trace() {
  unsetopt XTRACE VERBOSE 2>/dev/null || true
  set +xv 2>/dev/null || true
}

# 封装 read_input 对应的独立处理逻辑。
read_input() {
  disable_debug_trace
  INPUT_VALUE=""
  IFS= read -r INPUT_VALUE
  disable_debug_trace
}

# 封装 pause_enter 对应的独立处理逻辑。
pause_enter() {
  local prompt="${1:-按 [Enter] 继续...}"
  printf "%b" "\033[1;33m${prompt}\033[0m"
  read_input
}

# 执行已经拆分完成的独立业务步骤。
run_cmd() {
  info_echo "执行命令：$*"
  "$@" 2>&1 | tee -a "$LOG_FILE"

  local exit_code=${pipestatus[1]}

  if [[ "$exit_code" -ne 0 ]]; then
    error_echo "命令失败：$*"
  fi

  return "$exit_code"
}

# 封装 trim_text 对应的独立处理逻辑。
trim_text() {
  local text="$1"

  text="${text//$'\r'/}"
  text="${text//$'\n'/}"

  while [[ -n "$text" && "$text" == [[:space:]]* ]]; do
    text="${text#?}"
  done

  while [[ -n "$text" && "$text" == *[[:space:]] ]]; do
    text="${text%?}"
  done

  printf "%s" "$text"
}

# 封装 input_is_space_skip 对应的独立处理逻辑。
input_is_space_skip() {
  local raw="$1"
  local trimmed=""

  trimmed="$(trim_text "$raw")"
  [[ -n "$raw" && -z "$trimmed" ]]
}

# 封装 unwrap_input_text 对应的独立处理逻辑。
unwrap_input_text() {
  local raw="$1"
  raw="$(trim_text "$raw")"

  case "$raw" in
    confirm=*|confirm_raw=*|confirm_value=*|raw_input=*|value=*)
      raw="${raw#*=}"
      raw="$(trim_text "$raw")"
      ;;
  esac

  raw="${(Q)raw}"
  raw="$(trim_text "$raw")"

  printf "%s" "$raw"
}

# 检查当前运行条件是否满足后续流程要求。
is_cancel_input() {
  local value="$1"

  case "$value" in
    q|Q|quit|QUIT|exit|EXIT|cancel|CANCEL)
      return 0
      ;;
    *)
      return 1
      ;;
  esac
}

# 封装 looks_like_path_input 对应的独立处理逻辑。
looks_like_path_input() {
  local value="$1"

  [[ "$value" == /* ]] && return 0
  [[ "$value" == "~"* ]] && return 0
  [[ "$value" == ./* ]] && return 0
  [[ "$value" == ../* ]] && return 0
  [[ "$value" == file://* ]] && return 0
  [[ "$value" == *"/"* ]] && return 0

  return 1
}

# 封装 normalize_local_path 对应的独立处理逻辑。
normalize_local_path() {
  local raw="$1"
  local path
  path="$(unwrap_input_text "$raw")"

  path="${path#file://}"
  path="${path/#\~/$HOME}"
  path="${path//%20/ }"
  path="$(trim_text "$path")"

  if [[ -n "$path" && "$path" != /* ]]; then
    path="$PWD/$path"
  fi

  printf "%s" "$path"
}

# 检查当前运行条件是否满足后续流程要求。
is_dir_empty() {
  local dir="$1"

  [[ -d "$dir" ]] || return 1

  if [[ -z "$(/bin/ls -A "$dir" 2>/dev/null)" ]]; then
    return 0
  fi

  return 1
}

# 封装 derive_repo_paths_from_user_path 对应的独立处理逻辑。
derive_repo_paths_from_user_path() {
  local chosen_path="$1"

  if [[ "${chosen_path:t}" == "$REPO_NAME" ]]; then
    PARENT_DIR="${chosen_path:h}"
    REPO_DIR="$chosen_path"
  else
    PARENT_DIR="$chosen_path"
    REPO_DIR="${chosen_path}/${REPO_NAME}"
  fi
}

# 解析并返回后续流程需要的目标信息。
get_cpu_arch() {
  local machine
  machine="$(uname -m)"

  if [[ "$machine" == "arm64" ]]; then
    echo "arm64"
    return 0
  fi

  if [[ "$(sysctl -in hw.optional.arm64 2>/dev/null || true)" == "1" ]]; then
    echo "arm64"
    return 0
  fi

  echo "x86_64"
}

# 解析并返回后续流程需要的目标信息。
get_profile_file() {
  local shell_path="${SHELL##*/}"

  case "$shell_path" in
    zsh)  echo "$HOME/.zprofile" ;;
    bash) echo "$HOME/.bash_profile" ;;
    *)    echo "$HOME/.profile" ;;
  esac
}

# 收集并校验用户输入，决定后续执行路径。
ask_upgrade() {
  local name="$1"

  info_echo "$name 已安装。是否升级？"
  warm_echo "👉 直接按 [Enter]：跳过升级"
  warm_echo "👉 输入任意字符后回车：执行升级"
  printf "> "

  read_input
  [[ -n "$INPUT_VALUE" ]]
}

# 封装 inject_shellenv_block 对应的独立处理逻辑。
inject_shellenv_block() {
  local id="$1"
  local profile_file="$2"
  local shellenv="$3"

  local header="# >>> ${id} 环境变量 >>>"
  local footer="# <<< ${id} 环境变量 <<<"

  if [[ -z "$id" || -z "$profile_file" || -z "$shellenv" ]]; then
    error_echo "缺少参数：inject_shellenv_block <id> <profile_file> <shellenv>"
    return 1
  fi

  mkdir -p "$(dirname "$profile_file")"
  touch "$profile_file"

  if grep -Fq "$header" "$profile_file" || grep -Fq "$shellenv" "$profile_file"; then
    info_echo "环境变量已存在：$id"
  else
    {
      echo ""
      echo "$header"
      echo "$shellenv"
      echo "$footer"
    } >> "$profile_file"

    success_echo "已写入环境变量：$profile_file -> $id"
  fi

  eval "$shellenv"
  success_echo "当前终端已生效：$id"
}

# 封装 require_clone_confirmation 对应的独立处理逻辑。
require_clone_confirmation() {
  local title="$1"
  local detail="$2"

  while true; do
    echo ""
    warn_echo "$title"
    warm_echo "$detail"
    warm_echo "目录已经校验通过。"
    warm_echo "直接按 [Enter]：确认并开始 clone。"
    warm_echo "输入 r / reselect：重新选择代码目录。"
    warm_echo "也可以直接拖入/输入新的本地目录：脚本会重新校验。"
    warm_echo "输入 q / Q / quit / exit / cancel：取消并退出脚本。"
    printf "> "

    read_input

    local value
    value="$(unwrap_input_text "$INPUT_VALUE")"

    case "$value" in
      "" )
        success_echo "已按回车确认，继续执行。"
        return 0
        ;;
      y|Y|yes|YES|Yes)
        success_echo "已确认，继续执行。"
        return 0
        ;;
      r|R|reselect|RESELECT)
        choose_download_dir "force"
        detail="目标目录：$REPO_DIR"
        continue
        ;;
      q|Q|quit|QUIT|exit|EXIT|cancel|CANCEL)
        warn_echo "已主动取消执行。"
        exit 0
        ;;
      * )
        if looks_like_path_input "$value"; then
          info_echo "检测到你在确认页输入了本地路径，开始重新校验：$value"
          if set_repo_target_from_user_path "$value"; then
            detail="目标目录：$REPO_DIR"
            success_echo "新的目标目录已校验通过。直接按 [Enter] 即可开始 clone。"
          fi
          continue
        fi

        warn_echo "输入内容无法识别，脚本不会继续。"
        warm_echo "直接按 [Enter] 确认，输入 r 重新选择目录，输入 q 取消。"
        continue
        ;;
    esac
  done
}

# 封装 require_yes_for_stash 对应的独立处理逻辑。
require_yes_for_stash() {
  while true; do
    warn_echo "检测到本地存在未提交改动。"
    warm_echo "为了安全更新，建议先自动 stash。"
    warm_echo "请输入 YES：自动 git stash 后继续。"
    warm_echo "直接按 [Enter]：跳过本次远程更新，继续使用本地现有代码。"
    warm_echo "输入 q / quit / exit / cancel：取消并退出脚本。"
    printf "> "

    read_input

    local value
    value="$(unwrap_input_text "$INPUT_VALUE")"

    case "$value" in
      YES)
        return 0
        ;;
      "" )
        note_echo "已跳过自动 stash；本次远程更新取消，继续使用本地现有代码。"
        return 1
        ;;
      q|Q|quit|QUIT|exit|EXIT|cancel|CANCEL)
        warn_echo "已主动取消执行。"
        exit 0
        ;;
      * )
        warn_echo "输入内容不是 YES。"
        continue
        ;;
    esac
  done
}

# 收集并校验用户输入，决定后续执行路径。
ask_repo_remote_update() {
  echo ""
  info_echo "检测到已有 Stirling-PDF 本地仓库。是否拉取远程更新？"
  gray_echo "本地仓库：$REPO_DIR"
  warm_echo "👉 直接按 [Enter]：跳过拉取更新，立即使用本地现有代码"
  warm_echo "👉 输入任意字符后回车：立即拉取远程更新"
  printf "> "

  read_input

  if [[ -z "$INPUT_VALUE" ]]; then
    note_echo "已跳过远程更新，继续使用本地现有代码。"
    return 1
  fi

  success_echo "已选择拉取远程更新。"
  return 0
}

# 展示脚本用途和影响范围，并在执行前等待用户确认。
show_readme() {
  clear
  bold_echo "MacOS Stirling-PDF 本地部署 + Caddy 本地端口域名映射"
  color_echo "============================================================"
  note_echo "这个脚本会执行以下动作："
  gray_echo "1. 打开脚本后，先主动扫描并关闭旧的 Stirling-PDF 后台进程和 5173/8080 端口占用。"
  gray_echo "2. 前置自检 Xcode Command Line Tools。"
  gray_echo "3. 自检 git / clang / make，git 使用 macOS 系统自带，不走 brew 安装。"
  gray_echo "4. 自检 Homebrew；未安装则按芯片架构安装。"
  gray_echo "5. 使用 Homebrew 自检安装 node、jenv、${JAVA_FORMULA}、uv、go-task。"
  gray_echo "6. 读取本地记录文件，并验证本地仓库是否属于官方 Stirling-PDF。"
  gray_echo "7. 记录无效或首次运行时，要求输入/拖入本地目录。"
  gray_echo "8. 目录选择阶段：直接回车继续询问；输入空格后回车才使用桌面目录。"
  gray_echo "9. 手动拖入/输入目录时，只允许父目录已存在；末级 Stirling-PDF 目录缺失时自动创建。"
  gray_echo "10. SSH remote 会被识别为官方仓库，并统一修正为 HTTPS remote。"
  gray_echo "11. 首次 clone 前进入确认页；目录已校验后直接按 [Enter] 继续，不需要输入 YES。"
  gray_echo "12. 已有仓库时先询问是否拉取远程更新：直接按 [Enter] 跳过；输入任意字符后回车才执行 fetch/pull。"
  gray_echo "13. 进入 Stirling-PDF 后执行 task install 和 task check。"
  gray_echo "14. 后台静默启动 task backend:dev 和 task frontend:dev。"
  gray_echo "15. 打开前端地址：${FRONTEND_URL}，并打印后端地址：${BACKEND_URL}。"
  gray_echo "16. Stirling-PDF 启动完成后，按顺序询问前端、后端两个 Caddy 本地域名 HTTPS 映射。"
  gray_echo "17. 每个映射项都遵循同一规则：直接按 [Enter] 继续询问；输入一个空格后回车跳过当前项；输入域名后回车立即配置该项。"
  echo ""
  warn_echo "注意：正常启动脚本会先归零旧后台服务，然后重新启动。"
  warn_echo "注意：确认自述文件后，会先关闭旧的 Caddy 后台映射，避免历史配置干扰。"
  warn_echo "手动停止方式仍然保留：重新运行本脚本并追加参数 --stop"
  gray_echo "例如："
  gray_echo "  "${SCRIPT_PATH}" --stop"
  echo ""
  note_echo "参考来源：Stirling-PDF 官网 https://www.stirling.com/"
  note_echo "参考来源：Caddy 官网 https://caddyserver.com/"
  echo ""
  warn_echo "代码记录文件：$RECORD_FILE"
  warn_echo "脚本日志：$LOG_FILE"
  warm_echo "后端日志：$BACKEND_LOG_FILE"
  warm_echo "前端日志：$FRONTEND_LOG_FILE"
  color_echo "============================================================"
  pause_enter "确认理解后，按 [Enter] 开始..."
}

# ----------------------------
# 进程清理
# ----------------------------
is_pid_running() {
  local pid_file="$1"

  [[ -f "$pid_file" ]] || return 1

  local pid
  pid="$(cat "$pid_file" 2>/dev/null || true)"

  [[ -n "$pid" ]] || return 1
  kill -0 "$pid" >/dev/null 2>&1
}

# 封装 kill_process_tree 对应的独立处理逻辑。
kill_process_tree() {
  local pid="$1"

  [[ -n "$pid" ]] || return 0

  local children
  children="$(pgrep -P "$pid" 2>/dev/null || true)"

  local child
  for child in ${(f)children}; do
    kill_process_tree "$child"
  done

  kill "$pid" >/dev/null 2>&1 || true
}

# 封装 force_kill_process_tree 对应的独立处理逻辑。
force_kill_process_tree() {
  local pid="$1"

  [[ -n "$pid" ]] || return 0

  local children
  children="$(pgrep -P "$pid" 2>/dev/null || true)"

  local child
  for child in ${(f)children}; do
    force_kill_process_tree "$child"
  done

  kill -9 "$pid" >/dev/null 2>&1 || true
}

# 封装 kill_pid_if_running 对应的独立处理逻辑。
kill_pid_if_running() {
  local pid="$1"
  local reason="${2:-进程}"

  [[ -n "$pid" ]] || return 0

  if ! kill -0 "$pid" >/dev/null 2>&1; then
    return 0
  fi

  warn_echo "正在结束${reason}，PID：$pid"
  kill_process_tree "$pid"

  sleep 1

  if kill -0 "$pid" >/dev/null 2>&1; then
    warn_echo "${reason} 未正常退出，执行强制结束：$pid"
    force_kill_process_tree "$pid"
  fi
}

# 封装 stop_by_pid_file 对应的独立处理逻辑。
stop_by_pid_file() {
  local name="$1"
  local pid_file="$2"

  if [[ ! -f "$pid_file" ]]; then
    gray_echo "$name 没有 PID 文件"
    return 0
  fi

  local pid
  pid="$(cat "$pid_file" 2>/dev/null || true)"

  if [[ -z "$pid" ]]; then
    rm -f "$pid_file"
    gray_echo "$name PID 文件为空，已清理"
    return 0
  fi

  kill_pid_if_running "$pid" "$name"
  rm -f "$pid_file"
}

# 封装 kill_processes_by_port 对应的独立处理逻辑。
kill_processes_by_port() {
  local port="$1"
  local label="$2"

  local pids
  pids="$(lsof -ti tcp:"$port" 2>/dev/null || true)"

  if [[ -z "$pids" ]]; then
    gray_echo "$label 端口 $port 未发现占用"
    return 0
  fi

  warn_echo "检测到 $label 端口 $port 被占用，将主动释放。"

  local pid
  for pid in ${(f)pids}; do
    kill_pid_if_running "$pid" "$label 端口占用进程"
  done
}

# 封装 kill_matching_stirling_processes 对应的独立处理逻辑。
kill_matching_stirling_processes() {
  local pattern="$1"
  local label="$2"

  local pids
  pids="$(pgrep -f "$pattern" 2>/dev/null || true)"

  if [[ -z "$pids" ]]; then
    gray_echo "未发现匹配进程：$label"
    return 0
  fi

  local current_pid="$$"
  local pid

  for pid in ${(f)pids}; do
    [[ "$pid" == "$current_pid" ]] && continue
    kill_pid_if_running "$pid" "$label"
  done
}

# 封装 stop_all_stirling_pdf_processes 对应的独立处理逻辑。
stop_all_stirling_pdf_processes() {
  highlight_echo "主动清理旧的 Stirling-PDF 后台服务"

  stop_by_pid_file "frontend:dev" "$FRONTEND_PID_FILE"
  stop_by_pid_file "backend:dev" "$BACKEND_PID_FILE"

  kill_matching_stirling_processes "task frontend:dev" "Stirling-PDF frontend:dev"
  kill_matching_stirling_processes "task backend:dev" "Stirling-PDF backend:dev"

  kill_processes_by_port "5173" "Stirling-PDF 前端"
  kill_processes_by_port "8080" "Stirling-PDF 后端"

  rm -f "$FRONTEND_PID_FILE" "$BACKEND_PID_FILE"

  success_echo "旧后台服务清理完成"
}

# 封装 stop_services 对应的独立处理逻辑。
stop_services() {
  stop_all_stirling_pdf_processes
  stop_stirling_caddy_mapping
}

# 封装 status_services 对应的独立处理逻辑。
status_services() {
  highlight_echo "Stirling-PDF 后台服务状态"

  if is_pid_running "$BACKEND_PID_FILE"; then
    success_echo "backend:dev 正在运行，PID：$(cat "$BACKEND_PID_FILE")"
  else
    warn_echo "backend:dev 未运行"
  fi

  if is_pid_running "$FRONTEND_PID_FILE"; then
    success_echo "frontend:dev 正在运行，PID：$(cat "$FRONTEND_PID_FILE")"
  else
    warn_echo "frontend:dev 未运行"
  fi

  gray_echo "前端地址：$FRONTEND_URL"
  gray_echo "后端地址：$BACKEND_URL"

  if lsof -nP -iTCP:443 -sTCP:LISTEN 2>/dev/null | grep -q '^caddy'; then
    success_echo "Caddy 本地域名映射正在运行"
  else
    warn_echo "Caddy 本地域名映射未运行"
  fi

  if [[ -f "$CADDY_STATE_FILE" ]]; then
    gray_echo "Caddy 映射记录：$CADDY_STATE_FILE"
    grep '^MAP_DOMAIN=' "$CADDY_STATE_FILE" 2>/dev/null | sed 's/^/  /' | tee -a "$LOG_FILE" || true
  fi

  gray_echo "代码记录文件：$RECORD_FILE"
  gray_echo "后端日志：$BACKEND_LOG_FILE"
  gray_echo "前端日志：$FRONTEND_LOG_FILE"
  gray_echo "脚本日志：$LOG_FILE"
}

# ----------------------------
# 记录文件
# ----------------------------
write_record_file() {
  local local_dir="$1"

  mkdir -p "$STATE_DIR"

  STIRLING_PDF_LOCAL_DIR="$local_dir"
  STIRLING_PDF_REMOTE_GITHUB_URL="$REPO_REMOTE_GITHUB_URL"
  STIRLING_PDF_HTTPS_CLONE_URL="$REPO_HTTPS_CLONE_URL"
  STIRLING_PDF_SSH_CLONE_URL="$REPO_SSH_CLONE_URL"
  STIRLING_PDF_RECORD_UPDATED_AT="$(date '+%Y-%m-%d %H:%M:%S')"

  {
    echo "# Stirling-PDF 本地部署记录文件"
    echo "# 由脚本自动生成；如需重选目录，可以删除本文件后重跑脚本。"
    typeset -p STIRLING_PDF_LOCAL_DIR
    typeset -p STIRLING_PDF_REMOTE_GITHUB_URL
    typeset -p STIRLING_PDF_HTTPS_CLONE_URL
    typeset -p STIRLING_PDF_SSH_CLONE_URL
    typeset -p STIRLING_PDF_RECORD_UPDATED_AT
  } > "$RECORD_FILE"

  success_echo "已写入代码记录文件：$RECORD_FILE"
  gray_echo "本地代码地址：$STIRLING_PDF_LOCAL_DIR"
  gray_echo "远程 GitHub 地址：$STIRLING_PDF_REMOTE_GITHUB_URL"
  gray_echo "HTTPS 下载地址：$STIRLING_PDF_HTTPS_CLONE_URL"
  gray_echo "SSH 下载地址：$STIRLING_PDF_SSH_CLONE_URL"
}

# 封装 load_record_file 对应的独立处理逻辑。
load_record_file() {
  if [[ ! -f "$RECORD_FILE" ]]; then
    return 1
  fi

  source "$RECORD_FILE"
  return 0
}

# 检查当前运行条件是否满足后续流程要求。
validate_record_fields() {
  local ok="1"

  if [[ -z "${STIRLING_PDF_LOCAL_DIR:-}" ]]; then
    warn_echo "记录文件缺少：STIRLING_PDF_LOCAL_DIR"
    ok="0"
  fi

  [[ "$ok" == "1" ]]
}

# ----------------------------
# Git 仓库验证
# ----------------------------
canonical_github_repo_key() {
  local url="$1"

  url="$(trim_text "$url")"
  url="${url%#}"
  url="${url%.git}"
  url="${url%/}"

  case "$url" in
    git@github.com:*)
      url="${url#git@github.com:}"
      ;;
    ssh://git@github.com/*)
      url="${url#ssh://git@github.com/}"
      ;;
    https://github.com/*)
      url="${url#https://github.com/}"
      ;;
    http://github.com/*)
      url="${url#http://github.com/}"
      ;;
  esac

  url="${url%/}"
  printf "%s" "${url:l}"
}

# 检查当前运行条件是否满足后续流程要求。
is_expected_stirling_remote_url() {
  local remote_url="$1"
  local actual_key
  local expected_key

  actual_key="$(canonical_github_repo_key "$remote_url")"
  expected_key="${REPO_OWNER:l}/${REPO_NAME:l}"

  [[ "$actual_key" == "$expected_key" ]]
}

# 解析并返回后续流程需要的目标信息。
get_origin_remote_url() {
  local repo_dir="$1"
  git -C "$repo_dir" remote get-url origin 2>/dev/null || true
}

# 检查当前运行条件是否满足后续流程要求。
validate_stirling_repo_dir() {
  local repo_dir="$1"

  [[ -n "$repo_dir" ]] || return 1
  [[ -d "$repo_dir" ]] || return 1
  [[ -d "$repo_dir/.git" ]] || return 1

  local origin_url
  origin_url="$(get_origin_remote_url "$repo_dir")"

  [[ -n "$origin_url" ]] || return 1

  if is_expected_stirling_remote_url "$origin_url"; then
    return 0
  fi

  return 1
}

# 检查当前运行条件是否满足后续流程要求。
ensure_origin_https_remote() {
  local repo_dir="$1"
  local origin_url
  origin_url="$(get_origin_remote_url "$repo_dir")"

  if [[ "$origin_url" == "$REPO_HTTPS_CLONE_URL" ]]; then
    success_echo "origin 已是 HTTPS：$REPO_HTTPS_CLONE_URL"
    return 0
  fi

  if is_expected_stirling_remote_url "$origin_url"; then
    warn_echo "origin 当前不是标准 HTTPS，将自动修正。"
    gray_echo "原 origin：$origin_url"
    gray_echo "新 origin：$REPO_HTTPS_CLONE_URL"

    run_cmd git -C "$repo_dir" remote set-url origin "$REPO_HTTPS_CLONE_URL" || {
      error_echo "origin 修正失败：$repo_dir"
      return 1
    }

    success_echo "origin 已修正为 HTTPS：$REPO_HTTPS_CLONE_URL"
    return 0
  fi

  return 1
}

# 封装 print_repo_validation_failure 对应的独立处理逻辑。
print_repo_validation_failure() {
  local repo_dir="$1"

  if [[ -z "$repo_dir" ]]; then
    warn_echo "记录的代码目录为空。"
    return 0
  fi

  if [[ ! -e "$repo_dir" ]]; then
    warn_echo "记录的代码目录不存在：$repo_dir"
    return 0
  fi

  if [[ ! -d "$repo_dir" ]]; then
    warn_echo "记录路径不是目录：$repo_dir"
    return 0
  fi

  if [[ ! -d "$repo_dir/.git" ]]; then
    warn_echo "记录目录不是 Git 仓库：$repo_dir"
    return 0
  fi

  local origin_url
  origin_url="$(get_origin_remote_url "$repo_dir")"

  if [[ -z "$origin_url" ]]; then
    warn_echo "记录目录是 Git 仓库，但没有 origin remote：$repo_dir"
    return 0
  fi

  warn_echo "记录目录的 origin 不属于官方 Stirling-PDF 仓库：$origin_url"
  warm_echo "只接受与官方仓库相关的地址："
  gray_echo "  $REPO_HTTPS_CLONE_URL"
  gray_echo "  $REPO_SSH_CLONE_URL"
}

# ----------------------------
# Xcode Command Line Tools 自检
# ----------------------------
check_xcode_license() {
  highlight_echo "检查 Xcode / Command Line Tools 授权状态"

  if ! command -v xcodebuild >/dev/null 2>&1; then
    warn_echo "未检测到 xcodebuild，跳过 license 检查"
    return 0
  fi

  local tmp_file
  tmp_file="$(mktemp)"

  if xcodebuild -license check >"$tmp_file" 2>&1; then
    success_echo "Xcode / Command Line Tools license 已接受"
    rm -f "$tmp_file"
    return 0
  fi

  local output
  output="$(cat "$tmp_file" 2>/dev/null || true)"
  rm -f "$tmp_file"

  if echo "$output" | grep -qi "requires Xcode"; then
    warn_echo "当前只有 Command Line Tools，没有完整 Xcode，跳过 xcodebuild license 检查"
    return 0
  fi

  if echo "$output" | grep -qi "active developer directory"; then
    warn_echo "当前 Developer Directory 指向 Command Line Tools，跳过完整 Xcode license 检查"
    return 0
  fi

  warn_echo "检测到 Xcode / Command Line Tools license 可能尚未接受"
  warm_echo "脚本将执行：sudo xcodebuild -license accept"
  pause_enter "按 [Enter] 执行授权..."

  sudo xcodebuild -license accept || {
    error_echo "Xcode license 授权失败"
    err_echo "你可以手动执行：sudo xcodebuild -license accept"
    exit 1
  }

  success_echo "Xcode / Command Line Tools license 已接受"
}

# 检查当前运行条件是否满足后续流程要求。
ensure_xcode_command_line_tools() {
  highlight_echo "自检 Xcode Command Line Tools"

  local dev_dir=""
  dev_dir="$(xcode-select -p 2>/dev/null || true)"

  if [[ -n "$dev_dir" && -d "$dev_dir" ]]; then
    success_echo "已检测到 Developer Directory：$dev_dir"
  else
    warn_echo "未检测到 Xcode Command Line Tools"
    info_echo "正在唤起系统安装器：xcode-select --install"

    xcode-select --install >/dev/null 2>&1 || true

    warm_echo "如果系统弹出安装窗口，请完成安装。"
    pause_enter "安装完成后，按 [Enter] 继续自检..."

    dev_dir="$(xcode-select -p 2>/dev/null || true)"

    if [[ -z "$dev_dir" || ! -d "$dev_dir" ]]; then
      error_echo "Xcode Command Line Tools 仍不可用"
      err_echo "请手动执行：xcode-select --install"
      exit 1
    fi

    success_echo "Xcode Command Line Tools 安装完成：$dev_dir"
  fi

  info_echo "检查 xcrun / git / clang / make 是否可用"

  if ! command -v xcrun >/dev/null 2>&1; then
    error_echo "xcrun 不可用，请重新安装 Xcode Command Line Tools"
    exit 1
  fi

  local required_tools=("git" "clang" "make")
  local tool=""

  for tool in "${required_tools[@]}"; do
    if xcrun -find "$tool" >/dev/null 2>&1; then
      success_echo "$tool 可用：$(xcrun -find "$tool" 2>/dev/null)"
    else
      error_echo "$tool 不可用，Xcode Command Line Tools 可能安装不完整"
      exit 1
    fi
  done

  check_xcode_license

  success_echo "Xcode Command Line Tools 自检完成"
}

# 检查当前运行条件是否满足后续流程要求。
ensure_git() {
  highlight_echo "自检 git"

  if command -v git >/dev/null 2>&1 && git --version >/dev/null 2>&1; then
    success_echo "git 可用：$(command -v git)"
    git --version 2>&1 | tee -a "$LOG_FILE"
    return 0
  fi

  error_echo "git 不可用"
  err_echo "macOS 的 git 应该由 Xcode Command Line Tools 提供，不应该通过 brew 强行安装。"
  err_echo "请执行：xcode-select --install"
  exit 1
}

# ----------------------------
# Homebrew 自检安装
# ----------------------------
find_brew_bin() {
  if command -v brew >/dev/null 2>&1; then
    command -v brew
  elif [[ -x "/opt/homebrew/bin/brew" ]]; then
    echo "/opt/homebrew/bin/brew"
  elif [[ -x "/usr/local/bin/brew" ]]; then
    echo "/usr/local/bin/brew"
  else
    return 1
  fi
}

# 执行对应的环境配置或同步处理。
install_homebrew() {
  local arch
  arch="$(get_cpu_arch)"

  local brew_bin
  brew_bin="$(find_brew_bin 2>/dev/null || true)"

  if [[ -z "$brew_bin" ]]; then
    warn_echo "未检测到 Homebrew，正在安装中...（芯片架构：$arch）"

    if [[ "$arch" == "arm64" ]]; then
      arch -arm64 /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)" || {
        error_echo "Homebrew 安装失败（arm64）"
        exit 1
      }
      brew_bin="/opt/homebrew/bin/brew"
    else
      arch -x86_64 /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)" || {
        error_echo "Homebrew 安装失败（x86_64）"
        exit 1
      }
      brew_bin="/usr/local/bin/brew"
    fi

    success_echo "Homebrew 安装成功"
  else
    success_echo "已检测到 Homebrew：$brew_bin"
  fi

  local profile_file
  profile_file="$(get_profile_file)"

  inject_shellenv_block \
    "homebrew_env" \
    "$profile_file" \
    "eval \"\$(${brew_bin} shellenv)\""

  if ask_upgrade "Homebrew"; then
    info_echo "开始更新 Homebrew..."
    run_cmd brew update  || exit 1
    run_cmd brew upgrade || exit 1
    run_cmd brew cleanup || exit 1

    brew doctor 2>&1 | tee -a "$LOG_FILE"
    if [[ "${pipestatus[1]}" -ne 0 ]]; then
      warn_echo "brew doctor 有警告，请按 Homebrew 提示自行处理；脚本继续。"
    fi

    brew -v 2>&1 | tee -a "$LOG_FILE"
    success_echo "Homebrew 更新完成"
  else
    note_echo "已跳过 Homebrew 更新"
  fi
}

# 检查当前运行条件是否满足后续流程要求。
is_formula_installed() {
  local formula="$1"
  local short_name="${formula:t}"

  brew list --formula "$formula" >/dev/null 2>&1 && return 0
  brew list --formula "$short_name" >/dev/null 2>&1 && return 0

  return 1
}

# 检查当前运行条件是否满足后续流程要求。
ensure_brew_formula() {
  local formula="$1"
  local display_name="${2:-$formula}"

  if is_formula_installed "$formula"; then
    success_echo "$display_name 已通过 Homebrew 安装"

    if ask_upgrade "$display_name"; then
      run_cmd brew upgrade "$formula" || {
        warn_echo "$display_name 升级失败或已经是最新版，脚本继续。"
      }
    else
      note_echo "已跳过 $display_name 升级"
    fi
  else
    warn_echo "未检测到 $display_name，正在安装最新版..."
    run_cmd brew install "$formula" || {
      error_echo "$display_name 安装失败"
      exit 1
    }
    success_echo "$display_name 安装完成"
  fi
}

# 执行对应的环境配置或同步处理。
setup_java_and_jenv_env() {
  local profile_file
  profile_file="$(get_profile_file)"

  local java_prefix
  java_prefix="$(brew --prefix "$JAVA_FORMULA" 2>/dev/null || true)"

  if [[ -z "$java_prefix" || ! -d "$java_prefix" ]]; then
    error_echo "无法找到 $JAVA_FORMULA 的 Homebrew 安装路径"
    exit 1
  fi

  local java_home="${java_prefix}/libexec/openjdk.jdk/Contents/Home"

  if [[ ! -d "$java_home" ]]; then
    error_echo "JAVA_HOME 不存在：$java_home"
    exit 1
  fi

  inject_shellenv_block \
    "java_openjdk_21_env" \
    "$profile_file" \
    "export JAVA_HOME=\"${java_home}\"
export PATH=\"\$JAVA_HOME/bin:\$PATH\""

  inject_shellenv_block \
    "jenv_env" \
    "$profile_file" \
    "export JENV_ROOT=\"\$HOME/.jenv\"
export PATH=\"\$JENV_ROOT/bin:\$PATH\"
if command -v jenv >/dev/null 2>&1; then
  eval \"\$(jenv init -)\"
fi"

  if command -v jenv >/dev/null 2>&1; then
    jenv add "$java_home" >/dev/null 2>&1 || true
    jenv enable-plugin export >/dev/null 2>&1 || true
    success_echo "jenv 已接入：$java_home"
  else
    warn_echo "jenv 命令暂不可用，但 JAVA_HOME/PATH 已设置"
  fi

  info_echo "当前 Java 版本："
  java -version 2>&1 | tee -a "$LOG_FILE"
}

# 执行对应的环境配置或同步处理。
install_dependencies() {
  highlight_echo "开始自检依赖"

  ensure_git

  ensure_brew_formula "node" "node"
  ensure_brew_formula "jenv" "jenv"
  ensure_brew_formula "$JAVA_FORMULA" "$JAVA_FORMULA"
  ensure_brew_formula "uv" "uv"
  ensure_brew_formula "go-task/tap/go-task" "go-task / task"

  setup_java_and_jenv_env

  success_echo "依赖自检完成"
}

# ----------------------------
# 代码目录选择与验证
# ----------------------------
try_use_recorded_repo_dir() {
  if ! load_record_file; then
    warn_echo "未发现代码记录文件：$RECORD_FILE"
    return 1
  fi

  highlight_echo "读取 Stirling-PDF 代码记录文件"
  gray_echo "记录文件：$RECORD_FILE"

  if ! validate_record_fields; then
    warn_echo "记录文件字段不完整，不能直接复用。"
    return 1
  fi

  gray_echo "记录的本地代码地址：$STIRLING_PDF_LOCAL_DIR"

  if validate_stirling_repo_dir "$STIRLING_PDF_LOCAL_DIR"; then
    REPO_DIR="$STIRLING_PDF_LOCAL_DIR"
    PARENT_DIR="${REPO_DIR:h}"

    success_echo "记录目录验证通过：这是官方 Stirling-PDF 仓库"
    ensure_origin_https_remote "$REPO_DIR" || exit 1
    write_record_file "$REPO_DIR"
    success_echo "将复用该目录，并可按需手动拉取远程更新：$REPO_DIR"
    return 0
  fi

  print_repo_validation_failure "$STIRLING_PDF_LOCAL_DIR"
  warn_echo "本地记录未通过验证，不能复用。"
  return 1
}

# 封装 set_repo_target_from_user_path 对应的独立处理逻辑。
set_repo_target_from_user_path() {
  local user_value="$1"
  local chosen_path
  chosen_path="$(normalize_local_path "$user_value")"

  if [[ -z "$chosen_path" ]]; then
    error_echo "目录解析失败：$user_value"
    return 1
  fi

  derive_repo_paths_from_user_path "$chosen_path"

  if [[ ! -d "$PARENT_DIR" ]]; then
    error_echo "父目录不存在：$PARENT_DIR"
    err_echo "请确认拖入/输入的路径是否正确。脚本只会自动创建最后一级目录：$REPO_NAME。"
    return 1
  fi

  if [[ ! -w "$PARENT_DIR" ]]; then
    error_echo "父目录不可写：$PARENT_DIR"
    return 1
  fi

  if [[ -e "$REPO_DIR" && ! -d "$REPO_DIR" ]]; then
    error_echo "目标路径已存在但不是目录：$REPO_DIR"
    return 1
  fi

  if [[ ! -e "$REPO_DIR" ]]; then
    mkdir "$REPO_DIR" || {
      error_echo "无法创建目标目录：$REPO_DIR"
      return 1
    }
    success_echo "已创建目标目录：$REPO_DIR"
  fi

  if validate_stirling_repo_dir "$REPO_DIR"; then
    ensure_origin_https_remote "$REPO_DIR" || return 1
    write_record_file "$REPO_DIR"
    success_echo "选择的目录验证通过：$REPO_DIR"
    return 0
  fi

  if [[ -d "$REPO_DIR/.git" ]]; then
    print_repo_validation_failure "$REPO_DIR"
    warn_echo "这是一个 Git 仓库，但不是官方 Stirling-PDF 仓库，不能使用。"
    return 1
  fi

  if [[ -d "$REPO_DIR" ]] && ! is_dir_empty "$REPO_DIR"; then
    error_echo "目标目录已存在但不是 Git 仓库，且目录非空：$REPO_DIR"
    err_echo "请换一个目录，或删除/改名该目录后重试。"
    return 1
  fi

  warn_echo "目标目录尚未 clone；下一步确认页直接按 [Enter] 即可开始 clone。"
  gray_echo "待 clone 目录：$REPO_DIR"
  return 0
}

# 收集并校验用户输入，决定后续执行路径。
choose_download_dir_manually() {
  local default_parent="$HOME/Desktop"

  while true; do
    echo ""
    highlight_echo "请选择 Stirling-PDF 代码目录"
    gray_echo "代码记录文件：$RECORD_FILE"
    warm_echo "请拖入/输入一个本地目录。"
    warm_echo "这里必须先选择目录；直接按 [Enter] 不会继续，防止误操作。"
    warm_echo "输入一个空格后按 [Enter]：使用桌面目录：$default_parent"
    warm_echo "输入 q / Q / quit / exit / cancel：取消并退出脚本。"
    printf "> "

    read_input

    local raw_input="$INPUT_VALUE"
    local raw_trimmed
    raw_trimmed="$(trim_text "$raw_input")"

    if [[ -z "$raw_input" ]]; then
      warn_echo "检测到空回车，已拦截。请拖入/输入目录，或输入一个空格后回车使用桌面目录。"
      continue
    fi

    if [[ -z "$raw_trimmed" ]]; then
      info_echo "检测到空格输入，使用桌面目录：$default_parent"
      if set_repo_target_from_user_path "$default_parent"; then
        return 0
      fi
      continue
    fi

    local value
    value="$(unwrap_input_text "$raw_input")"

    if is_cancel_input "$value"; then
      warn_echo "已主动取消执行。"
      exit 0
    fi

    if ! looks_like_path_input "$value"; then
      warn_echo "输入内容不像本地路径：$value"
      warm_echo "请拖入/输入本地目录。若要使用桌面目录，请输入一个空格后按 Enter。"
      continue
    fi

    local chosen_path
    chosen_path="$(normalize_local_path "$value")"
    info_echo "已输入本地路径：$chosen_path"

    if set_repo_target_from_user_path "$chosen_path"; then
      return 0
    fi
  done
}

# 收集并校验用户输入，决定后续执行路径。
choose_download_dir() {
  local mode="${1:-normal}"

  if [[ "$mode" != "force" ]]; then
    if try_use_recorded_repo_dir; then
      return 0
    fi
  fi

  choose_download_dir_manually
}

# ----------------------------
# Git clone / 更新到最新
# ----------------------------
get_remote_default_branch() {
  git -C "$REPO_DIR" remote set-head origin -a >/dev/null 2>&1 || true

  local branch
  branch="$(git -C "$REPO_DIR" symbolic-ref --quiet --short refs/remotes/origin/HEAD 2>/dev/null || true)"
  branch="${branch#origin/}"

  if [[ -z "$branch" ]]; then
    branch="main"
  fi

  echo "$branch"
}

# 检查当前运行条件是否满足后续流程要求。
ensure_clean_or_stash() {
  local status_output
  status_output="$(git -C "$REPO_DIR" status --porcelain 2>/dev/null || true)"

  if [[ -z "$status_output" ]]; then
    return 0
  fi

  require_yes_for_stash || return 1

  run_cmd git -C "$REPO_DIR" stash push -u -m "auto-stash before Stirling-PDF update $(date '+%Y-%m-%d %H:%M:%S')" || {
    warn_echo "自动 stash 失败；本次远程更新取消，继续使用本地现有代码。"
    return 1
  }

  success_echo "本地改动已 stash。需要恢复时可进入仓库执行：git stash list / git stash pop"
  return 0
}

# 检查当前运行条件是否满足后续流程要求。
ensure_branch_ready_for_update() {
  UPDATE_CURRENT_BRANCH=""

  local current_branch
  current_branch="$(git -C "$REPO_DIR" symbolic-ref --quiet --short HEAD 2>/dev/null || true)"

  local target_branch
  target_branch="$(get_remote_default_branch)"

  if [[ -z "$current_branch" ]]; then
    warn_echo "当前仓库处于 detached HEAD，尝试切回远端默认分支：$target_branch"
    run_cmd git -C "$REPO_DIR" checkout -B "$target_branch" "origin/$target_branch" || return 1
    current_branch="$target_branch"
  fi

  if [[ "$current_branch" != "$target_branch" ]]; then
    warn_echo "当前分支：$current_branch；远端默认分支：$target_branch"
    warm_echo "👉 直接按 [Enter]：继续检查并更新当前分支"
    warm_echo "👉 输入任意字符后回车：切换到远端默认分支 $target_branch"
    printf "> "

    read_input

    if [[ -n "$INPUT_VALUE" ]]; then
      run_cmd git -C "$REPO_DIR" checkout "$target_branch" || run_cmd git -C "$REPO_DIR" checkout -B "$target_branch" "origin/$target_branch" || return 1
      current_branch="$target_branch"
    fi
  fi

  local upstream_ref="origin/$current_branch"

  if ! git -C "$REPO_DIR" rev-parse --verify "$upstream_ref" >/dev/null 2>&1; then
    warn_echo "远端不存在当前分支：$upstream_ref"
    warn_echo "尝试切换到远端默认分支：$target_branch"
    run_cmd git -C "$REPO_DIR" checkout "$target_branch" || run_cmd git -C "$REPO_DIR" checkout -B "$target_branch" "origin/$target_branch" || return 1
    current_branch="$target_branch"
  fi

  UPDATE_CURRENT_BRANCH="$current_branch"
  return 0
}

# 执行对应的环境配置或同步处理。
update_existing_repo_to_latest() {
  if ! validate_stirling_repo_dir "$REPO_DIR"; then
    print_repo_validation_failure "$REPO_DIR"
    error_echo "当前目录未通过官方 Stirling-PDF 仓库验证，拒绝更新。"
    exit 1
  fi

  success_echo "已验证 Git 仓库：$REPO_DIR"
  success_echo "origin：$(get_origin_remote_url "$REPO_DIR")"
  ensure_origin_https_remote "$REPO_DIR" || exit 1
  write_record_file "$REPO_DIR"

  if ! ask_repo_remote_update; then
    return 0
  fi

  run_cmd git -C "$REPO_DIR" fetch --progress --prune origin || {
    warn_echo "git fetch 失败，已跳过本次远程更新；继续使用本地现有代码。"
    return 0
  }

  local current_branch
  if ! ensure_branch_ready_for_update; then
    warn_echo "分支检查/切换失败，已跳过本次远程更新；继续使用本地现有代码。"
    return 0
  fi
  current_branch="$UPDATE_CURRENT_BRANCH"
  local upstream_ref="origin/$current_branch"

  local local_hash
  local remote_hash
  local base_hash

  local_hash="$(git -C "$REPO_DIR" rev-parse HEAD 2>/dev/null || true)"
  remote_hash="$(git -C "$REPO_DIR" rev-parse "$upstream_ref" 2>/dev/null || true)"
  base_hash="$(git -C "$REPO_DIR" merge-base HEAD "$upstream_ref" 2>/dev/null || true)"

  if [[ -z "$local_hash" || -z "$remote_hash" || -z "$base_hash" ]]; then
    warn_echo "无法判断本地与远端提交关系，已跳过本次远程更新；继续使用本地现有代码。"
    return 0
  fi

  if [[ "$local_hash" == "$remote_hash" ]]; then
    success_echo "本地代码已经是最新：$current_branch"
    return 0
  fi

  if [[ "$local_hash" == "$base_hash" ]]; then
    info_echo "检测到远程有更新，开始拉取：$upstream_ref"
    if ! ensure_clean_or_stash; then
      return 0
    fi

    run_cmd git -C "$REPO_DIR" pull --progress --ff-only origin "$current_branch" || {
      warn_echo "git pull --ff-only 失败，已跳过本次远程更新；继续使用本地现有代码。"
      return 0
    }
    success_echo "代码已更新到远程最新"
    return 0
  fi

  if [[ "$remote_hash" == "$base_hash" ]]; then
    warn_echo "本地分支领先远端，远端没有需要拉取的新提交。"
    warn_echo "脚本不会自动 push，也不会重置你的本地提交。"
    return 0
  fi

  warn_echo "本地分支和远端分支已经分叉。"
  warm_echo "直接按 [Enter]：跳过远程更新，继续使用本地现有代码。"
  warm_echo "输入 YES 后回车：强制重置到 $upstream_ref。"
  printf "> "

  read_input
  local reset_confirm
  reset_confirm="$(unwrap_input_text "$INPUT_VALUE")"

  if [[ "$reset_confirm" == "YES" ]]; then
    if ! ensure_clean_or_stash; then
      return 0
    fi

    warn_echo "执行强制重置：git reset --hard $upstream_ref"
    run_cmd git -C "$REPO_DIR" reset --hard "$upstream_ref" || {
      warn_echo "git reset --hard 失败，已跳过本次远程更新；继续使用本地现有代码。"
      return 0
    }
    success_echo "代码已强制同步到远端最新"
  else
    note_echo "已跳过分叉处理，继续使用本地现有代码。"
  fi
}

# 封装 clone_or_update_repo 对应的独立处理逻辑。
clone_or_update_repo() {
  highlight_echo "准备 Stirling-PDF 源码"

  if validate_stirling_repo_dir "$REPO_DIR"; then
    update_existing_repo_to_latest
    success_echo "源码准备完成：$REPO_DIR"
    return 0
  fi

  if [[ -d "$REPO_DIR/.git" ]]; then
    print_repo_validation_failure "$REPO_DIR"
    error_echo "目标目录是 Git 仓库，但不是官方 Stirling-PDF 仓库，拒绝继续。"
    exit 1
  fi

  if [[ -e "$REPO_DIR" && ! -d "$REPO_DIR" ]]; then
    error_echo "目标路径已存在但不是目录：$REPO_DIR"
    exit 1
  fi

  if [[ -d "$REPO_DIR" ]] && ! is_dir_empty "$REPO_DIR"; then
    error_echo "目标目录已存在但不是 Git 仓库，且目录非空：$REPO_DIR"
    exit 1
  fi

  require_clone_confirmation \
    "即将首次 clone Stirling-PDF 源码" \
    "目标目录：$REPO_DIR"

  info_echo "开始 clone：$REPO_HTTPS_CLONE_URL"
  run_cmd git clone --progress --depth=1 "$REPO_HTTPS_CLONE_URL" "$REPO_DIR" || {
    error_echo "git clone 失败"
    exit 1
  }

  if ! validate_stirling_repo_dir "$REPO_DIR"; then
    error_echo "clone 完成后仓库验证失败，请检查：$REPO_DIR"
    exit 1
  fi

  ensure_origin_https_remote "$REPO_DIR" || exit 1
  write_record_file "$REPO_DIR"

  success_echo "源码下载完成：$REPO_DIR"
  success_echo "源码准备完成：$REPO_DIR"
}

# ----------------------------
# Stirling-PDF 自检与启动
# ----------------------------
run_stirling_checks() {
  highlight_echo "开始 Stirling-PDF 自检"

  cd "$REPO_DIR" || {
    error_echo "无法进入目录：$REPO_DIR"
    exit 1
  }

  if ! command -v task >/dev/null 2>&1; then
    error_echo "未找到 task 命令，请确认 go-task 已安装"
    exit 1
  fi

  run_cmd task install || {
    error_echo "task install 失败"
    exit 1
  }

  run_cmd task check || {
    error_echo "task check 失败"
    exit 1
  }

  success_echo "Stirling-PDF 自检完成"
}

# 封装 start_background_task 对应的独立处理逻辑。
start_background_task() {
  local name="$1"
  local pid_file="$2"
  local log_file="$3"
  shift 3

  info_echo "后台静默启动 $name ..."
  gray_echo "$name 日志：$log_file"

  (
    cd "$REPO_DIR" || exit 1

    nohup "$@" >> "$log_file" 2>&1 &
    local pid=$!
    echo "$pid" > "$pid_file"
    disown "$pid" 2>/dev/null || true
  )

  sleep 1

  if is_pid_running "$pid_file"; then
    local new_pid
    new_pid="$(cat "$pid_file")"
    success_echo "$name 启动成功，PID：$new_pid"
  else
    error_echo "$name 启动失败，请查看日志：$log_file"
    exit 1
  fi
}

# 封装 start_dev_services 对应的独立处理逻辑。
start_dev_services() {
  highlight_echo "启动 Stirling-PDF 后端和前端"

  mkdir -p "$SERVICE_LOG_DIR"

  start_background_task \
    "backend:dev" \
    "$BACKEND_PID_FILE" \
    "$BACKEND_LOG_FILE" \
    task backend:dev

  start_background_task \
    "frontend:dev" \
    "$FRONTEND_PID_FILE" \
    "$FRONTEND_LOG_FILE" \
    task frontend:dev

  success_echo "后端和前端已在后台运行"
}

# 封装 wait_for_port 对应的独立处理逻辑。
wait_for_port() {
  local port="$1"
  local max_seconds="${2:-60}"
  local i=0

  info_echo "等待端口 $port 就绪..."

  while (( i < max_seconds )); do
    if nc -z 127.0.0.1 "$port" >/dev/null 2>&1; then
      success_echo "端口 $port 已就绪"
      return 0
    fi

    sleep 1
    (( i++ ))
  done

  warn_echo "等待端口 $port 超时，浏览器仍会尝试打开。"
  return 1
}

# 封装 open_frontend 对应的独立处理逻辑。
open_frontend() {
  wait_for_port 5173 60 || true

  info_echo "前端地址：$FRONTEND_URL"
  info_echo "后端地址：$BACKEND_URL"
  info_echo "正在打开浏览器：$FRONTEND_URL"

  open "$FRONTEND_URL" || {
    warn_echo "自动打开浏览器失败，请手动访问：$FRONTEND_URL"
  }
}


# ----------------------------
# Caddy 本地域名 HTTPS 映射
# ----------------------------
escape_sed_pattern() {
  printf "%s" "$1" | sed 's/[.[\*^$()+?{}|\\]/\\&/g'
}

# 封装 read_caddy_state_domains 对应的独立处理逻辑。
read_caddy_state_domains() {
  [[ -f "$CADDY_STATE_FILE" ]] || return 0
  grep '^MAP_DOMAIN=' "$CADDY_STATE_FILE" 2>/dev/null | sed 's/^MAP_DOMAIN=//' || true
}

# 编排完整业务流程，复杂步骤继续下沉到职责明确的函数。
remove_hosts_domain() {
  local domain="$1"
  domain="$(trim_text "$domain")"
  [[ -n "$domain" ]] || return 0

  local escaped_domain
  escaped_domain="$(escape_sed_pattern "$domain")"
  sudo sed -i '' "/[[:space:]]${escaped_domain}$/d" /etc/hosts 2>/dev/null || true
}

# 封装 stop_stirling_caddy_mapping 对应的独立处理逻辑。
stop_stirling_caddy_mapping() {
  highlight_echo "关闭旧的 Caddy 后台映射"

  local old_domains
  old_domains="$(read_caddy_state_domains)"

  if command -v caddy >/dev/null 2>&1; then
    sudo caddy stop >> "$LOG_FILE" 2>&1 || true
  else
    gray_echo "未检测到 Caddy 命令，跳过 Caddy stop。"
  fi

  sleep 1

  if pgrep -x caddy >/dev/null 2>&1; then
    warn_echo "仍检测到 Caddy 进程，正在强制结束旧后台映射。"
    sudo pkill -x caddy >> "$LOG_FILE" 2>&1 || true
    sleep 1
  fi

  local domain
  for domain in ${(f)old_domains}; do
    [[ -n "$domain" ]] || continue
    remove_hosts_domain "$domain"
    info_echo "已清理上次记录的 hosts：$domain"
  done

  rm -f "$CADDY_STATE_FILE" 2>/dev/null || true
  success_echo "旧 Caddy 后台映射清理完成"
}

# 检查当前运行条件是否满足后续流程要求。
ensure_caddy() {
  highlight_echo "自检 Caddy"
  ensure_brew_formula "$CADDY_FORMULA" "Caddy"

  if ! command -v caddy >/dev/null 2>&1; then
    error_echo "Caddy 安装后仍不可用，请检查 Homebrew 环境变量。"
    exit 1
  fi

  success_echo "Caddy 可用：$(command -v caddy)"
  caddy version 2>&1 | tee -a "$LOG_FILE"
}

# 编排完整业务流程，复杂步骤继续下沉到职责明确的函数。
normalize_caddy_domain() {
  local raw="$1"
  raw="$(trim_text "$raw")"
  raw="${raw#http://}"
  raw="${raw#https://}"
  raw="${raw%%/*}"
  raw="${raw%%:*}"
  raw="$(printf "%s" "$raw" | tr '[:upper:]' '[:lower:]')"

  [[ -n "$raw" ]] || return 1
  [[ "$raw" != "localhost" ]] || return 1
  echo "$raw" | grep -Eq '^[a-z0-9]([a-z0-9-]{0,61}[a-z0-9])?(\.[a-z0-9]([a-z0-9-]{0,61}[a-z0-9])?)+$' || return 1

  printf "%s" "$raw"
}

# 编排完整业务流程，复杂步骤继续下沉到职责明确的函数。
prompt_caddy_domain() {
  local label="$1"
  local local_url="${2:-}"
  local raw=""
  local domain=""
  CADDY_SELECTED_DOMAIN=""

  while true; do
    highlight_echo "配置 ${label} Caddy 本地域名映射"
    [[ -n "$local_url" ]] && gray_echo "本地地址：$local_url"
    case "$label" in
      前端) gray_echo "示例：jobs.pdf.com / jobs.pdf.test" ;;
      后端) gray_echo "示例：api.jobs.pdf.com / api.jobs.pdf.test" ;;
      *)    gray_echo "示例：jobs.pdf.com / jobs.pdf.test" ;;
    esac
    warm_echo "直接按 [Enter]：不跳过，继续等待输入${label}域名"
    warm_echo "输入一个空格后回车：跳过${label}映射"
    warm_echo "输入域名后回车：立即配置${label}映射"
    printf "> "

    read_input
    raw="$INPUT_VALUE"

    if [[ -z "$raw" ]]; then
      warn_echo "检测到空回车，已拦截。若要跳过${label}映射，请输入一个空格后回车。"
      continue
    fi

    if input_is_space_skip "$raw"; then
      note_echo "已跳过${label}映射。"
      return 1
    fi

    raw="$(trim_text "$raw")"
    domain="$(normalize_caddy_domain "$raw" 2>/dev/null || true)"

    if [[ -z "$domain" ]]; then
      warn_echo "域名格式不合法，请重新输入；若要跳过${label}映射，请输入一个空格后回车。"
      continue
    fi

    if [[ "$domain" == *.com ]]; then
      warn_echo ".com 是公网 TLD，本机开发更建议使用 .test。当前仍按你的输入继续。"
    fi

    CADDY_SELECTED_DOMAIN="$domain"
    return 0
  done
}

# 封装 caddy_target_upstream 对应的独立处理逻辑。
caddy_target_upstream() {
  local target_key="$1"
  case "$target_key" in
    frontend) printf "127.0.0.1:5173" ;;
    backend)  printf "127.0.0.1:8080" ;;
    *) return 1 ;;
  esac
}

# 封装 caddy_target_url 对应的独立处理逻辑。
caddy_target_url() {
  local target_key="$1"
  case "$target_key" in
    frontend) printf "%s" "$FRONTEND_URL" ;;
    backend)  printf "%s" "$BACKEND_URL" ;;
    *) return 1 ;;
  esac
}

# 封装 caddy_target_label 对应的独立处理逻辑。
caddy_target_label() {
  local target_key="$1"
  case "$target_key" in
    frontend) printf "前端" ;;
    backend)  printf "后端" ;;
    *) return 1 ;;
  esac
}

# 封装 caddy_target_check_path 对应的独立处理逻辑。
caddy_target_check_path() {
  local target_key="$1"
  case "$target_key" in
    frontend) printf "/" ;;
    backend)  printf "/api/v1/info/status" ;;
    *) printf "/" ;;
  esac
}

# 检查当前运行条件是否满足后续流程要求。
check_caddy_local_service_once() {
  local target_key="$1"
  local label local_url check_url http_code
  label="$(caddy_target_label "$target_key")"
  local_url="$(caddy_target_url "$target_key")"

  case "$target_key" in
    frontend) check_url="http://127.0.0.1:5173/" ;;
    backend)  check_url="http://127.0.0.1:8080/api/v1/info/status" ;;
    *)        check_url="$local_url" ;;
  esac

  http_code="$(curl --noproxy '*' -s -o /dev/null -w '%{http_code}' --max-time 8 "$check_url" 2>/dev/null || echo '000')"

  if [[ "$http_code" == 2* || "$http_code" == 3* || "$http_code" == 4* ]]; then
    success_echo "${label}本地服务可访问：$local_url（HTTP $http_code）"
    return 0
  fi

  warn_echo "${label}本地服务当前不可访问：$local_url（HTTP $http_code）"
  return 1
}

# 封装 add_caddy_mapping 对应的独立处理逻辑。
add_caddy_mapping() {
  local target_key="$1"
  local label upstream local_url check_path domain

  label="$(caddy_target_label "$target_key")"
  upstream="$(caddy_target_upstream "$target_key")"
  local_url="$(caddy_target_url "$target_key")"
  check_path="$(caddy_target_check_path "$target_key")"

  prompt_caddy_domain "$label" "$local_url" || return 1
  domain="$CADDY_SELECTED_DOMAIN"

  check_caddy_local_service_once "$target_key" || warn_echo "${label}本地服务当前不可访问，仍继续生成映射；如果服务未启动，浏览器会看到 502。"

  CADDY_MAP_LABELS+=("$label")
  CADDY_MAP_DOMAINS+=("$domain")
  CADDY_MAP_UPSTREAMS+=("$upstream")
  CADDY_MAP_LOCAL_URLS+=("$local_url")
  CADDY_MAP_CHECK_PATHS+=("$check_path")

  success_echo "已加入映射：${label} ${local_url} -> https://${domain}/"
  return 0
}

# 封装 collect_caddy_mappings 对应的独立处理逻辑。
collect_caddy_mappings() {
  local target_key=""

  CADDY_MAP_LABELS=()
  CADDY_MAP_DOMAINS=()
  CADDY_MAP_UPSTREAMS=()
  CADDY_MAP_LOCAL_URLS=()
  CADDY_MAP_CHECK_PATHS=()

  highlight_echo "Caddy 本地域名 HTTPS 映射配置"
  gray_echo "将按固定顺序询问两个页面：前端 ${FRONTEND_URL}，后端 ${BACKEND_URL}。"
  gray_echo "每一项都可以单独跳过：输入一个空格后回车即可。"

  for target_key in frontend backend; do
    echo ""
    add_caddy_mapping "$target_key" || true
  done

  (( ${#CADDY_MAP_DOMAINS[@]} > 0 ))
}

# 封装 write_caddy_hosts 对应的独立处理逻辑。
write_caddy_hosts() {
  highlight_echo "写入 /etc/hosts"

  local domain
  for domain in "${CADDY_MAP_DOMAINS[@]}"; do
    remove_hosts_domain "$domain"
    echo "127.0.0.1 $domain" | sudo tee -a /etc/hosts >/dev/null || {
      error_echo "写入 /etc/hosts 失败：$domain"
      exit 1
    }
    success_echo "已写入：127.0.0.1 $domain"
    dscacheutil -q host -a name "$domain" 2>&1 | tee -a "$LOG_FILE" || true
  done

  dscacheutil -flushcache 2>/dev/null || true
  sudo killall -HUP mDNSResponder 2>/dev/null || true
}

# 执行对应的环境配置或同步处理。
sync_caddy_proxy_bypass() {
  highlight_echo "同步系统代理绕过列表"

  local services
  services="$(networksetup -listallnetworkservices 2>/dev/null | tail -n +2 || true)"
  if [[ -z "$services" ]]; then
    warn_echo "未读取到网络服务列表，跳过代理绕过同步。"
    return 0
  fi

  local svc
  while IFS= read -r svc; do
    svc="$(trim_text "$svc")"
    [[ -n "$svc" ]] || continue
    [[ "$svc" == \** ]] && continue

    local existing_raw
    existing_raw="$(networksetup -getproxybypassdomains "$svc" 2>/dev/null | grep -v "There aren't any" || true)"

    local -a items unique
    items=()
    unique=()

    local line
    while IFS= read -r line; do
      line="$(trim_text "$line")"
      [[ -n "$line" ]] && items+=("$line")
    done <<< "$existing_raw"

    items+=("localhost" "127.0.0.1" "127.0.0.0/8" "::1")

    local domain root_domain
    for domain in "${CADDY_MAP_DOMAINS[@]}"; do
      items+=("$domain")
      root_domain="$(printf "%s" "$domain" | awk -F. '{if (NF>=2) print $(NF-1)"."$NF; else print $0}')"
      [[ -n "$root_domain" ]] && items+=("*.${root_domain}")
    done

    local item exists old
    for item in "${items[@]}"; do
      item="$(trim_text "$item")"
      [[ -n "$item" ]] || continue
      exists="0"
      for old in "${unique[@]}"; do
        [[ "$old" == "$item" ]] && exists="1" && break
      done
      [[ "$exists" == "0" ]] && unique+=("$item")
    done

    if networksetup -setproxybypassdomains "$svc" "${unique[@]}" >> "$LOG_FILE" 2>&1; then
      success_echo "已更新代理绕过：$svc"
    else
      warn_echo "代理绕过更新失败，已跳过：$svc"
    fi
  done <<< "$services"
}

# 封装 generate_stirling_caddyfile 对应的独立处理逻辑。
generate_stirling_caddyfile() {
  highlight_echo "生成 Caddyfile"

  {
    cat <<'EOF_CADDY_HEAD'
{
	# 封装 servers 对应的独立处理逻辑。
	servers {
		protocols h1 h2
	}
}
EOF_CADDY_HEAD
    echo ""

    local total idx domain upstream
    total=${#CADDY_MAP_DOMAINS[@]}
    for (( idx = 1; idx <= total; idx++ )); do
      domain="${CADDY_MAP_DOMAINS[$idx]}"
      upstream="${CADDY_MAP_UPSTREAMS[$idx]}"
      cat <<EOF_CADDY_SITE
${domain} {
	tls internal

	# 封装 header 对应的独立处理逻辑。
	header {
		-Alt-Svc
	}

	reverse_proxy ${upstream} {
		header_up Host {upstream_hostport}
		header_up X-Forwarded-Proto https
	}
}

EOF_CADDY_SITE
    done
  } > "$CADDYFILE"

  caddy fmt --overwrite "$CADDYFILE" >> "$LOG_FILE" 2>&1 || true

  success_echo "Caddyfile 已生成：$CADDYFILE"
  gray_echo "----------------------------------------"
  cat "$CADDYFILE" | tee -a "$LOG_FILE"
  gray_echo "----------------------------------------"
}

# 封装 save_stirling_caddy_state 对应的独立处理逻辑。
save_stirling_caddy_state() {
  {
    local total idx
    total=${#CADDY_MAP_DOMAINS[@]}
    for (( idx = 1; idx <= total; idx++ )); do
      echo "MAP_DOMAIN=${CADDY_MAP_DOMAINS[$idx]}"
      echo "LOCAL_UPSTREAM=${CADDY_MAP_UPSTREAMS[$idx]}"
      echo "LABEL=${CADDY_MAP_LABELS[$idx]}"
      echo "---"
    done
    echo "CADDYFILE=$CADDYFILE"
  } > "$CADDY_STATE_FILE"
}

# 执行已经拆分完成的独立业务步骤。
run_caddy_command_with_timeout() {
  local seconds="$1"
  shift

  "$@" >> "$LOG_FILE" 2>&1 &
  local cmd_pid=$!
  local waited=0

  while kill -0 "$cmd_pid" 2>/dev/null; do
    if (( waited >= seconds )); then
      kill -TERM "$cmd_pid" 2>/dev/null || true
      sleep 1
      kill -KILL "$cmd_pid" 2>/dev/null || true
      wait "$cmd_pid" 2>/dev/null || true
      return 124
    fi

    sleep 1
    waited=$((waited + 1))
  done

  wait "$cmd_pid"
  return $?
}

# 封装 wait_for_caddy_443 对应的独立处理逻辑。
wait_for_caddy_443() {
  local waited=0
  while (( waited < 10 )); do
    if sudo lsof -nP -iTCP:443 -sTCP:LISTEN 2>/dev/null | grep -q '^caddy'; then
      return 0
    fi
    sleep 1
    waited=$((waited + 1))
  done
  return 1
}

# 封装 start_stirling_caddy_background 对应的独立处理逻辑。
start_stirling_caddy_background() {
  highlight_echo "启动 Caddy HTTPS 反向代理"
  info_echo "正在后台启动 Caddy，详细日志写入：$LOG_FILE"

  sudo -v || {
    error_echo "管理员权限已失效，无法启动 Caddy。"
    return 1
  }

  local start_rc=0
  run_caddy_command_with_timeout 20 sudo caddy start --config "$CADDYFILE" --adapter caddyfile
  start_rc=$?

  if [[ "$start_rc" == "124" ]]; then
    error_echo "Caddy 启动命令超时，已终止。最近日志如下："
    tail -n 80 "$LOG_FILE"
    return 1
  elif [[ "$start_rc" != "0" ]]; then
    error_echo "Caddy 启动失败。最近日志如下："
    tail -n 80 "$LOG_FILE"
    return 1
  fi

  if ! wait_for_caddy_443; then
    error_echo "Caddy 未成功监听 443。最近日志如下："
    tail -n 80 "$LOG_FILE"
    return 1
  fi

  run_caddy_command_with_timeout 15 sudo caddy trust || warn_echo "Caddy trust 未完成或无需重复执行；如浏览器证书异常再手动执行：sudo caddy trust"

  success_echo "Caddy 已在后台运行"
  sudo lsof -nP -iTCP:443 -sTCP:LISTEN 2>/dev/null | tee -a "$LOG_FILE" || true
  return 0
}

# 封装 post_check_stirling_caddy_mappings 对应的独立处理逻辑。
post_check_stirling_caddy_mappings() {
  highlight_echo "Caddy 映射自检"

  local total idx label domain check_path http_code url
  total=${#CADDY_MAP_DOMAINS[@]}

  for (( idx = 1; idx <= total; idx++ )); do
    label="${CADDY_MAP_LABELS[$idx]}"
    domain="${CADDY_MAP_DOMAINS[$idx]}"
    check_path="${CADDY_MAP_CHECK_PATHS[$idx]}"
    url="https://${domain}${check_path}"

    http_code="$(curl --noproxy '*' -k -s -o /dev/null -w '%{http_code}' --max-time 8 "$url" 2>/dev/null || echo '000')"

    if [[ "$http_code" == 2* || "$http_code" == 3* ]]; then
      success_echo "${label} HTTPS 映射可访问：$url（HTTP $http_code）"
    elif [[ "$http_code" == "403" ]]; then
      warn_echo "${label} HTTPS 返回 403。若目标是 Vite，请检查 allowedHosts 或 Caddy Host 转发。"
    elif [[ "$http_code" == "502" ]]; then
      warn_echo "${label} HTTPS 返回 502。通常是本地服务已退出或端口不可访问。"
    else
      warn_echo "${label} HTTPS 自检返回 HTTP $http_code，可用 curl -vk $url 继续排查。"
    fi
  done
}

# 封装 open_caddy_mapping_urls 对应的独立处理逻辑。
open_caddy_mapping_urls() {
  local domain
  for domain in "${CADDY_MAP_DOMAINS[@]}"; do
    open "https://${domain}/" >/dev/null 2>&1 || true
  done
}

# 封装 restart_frontend_for_caddy_allowed_hosts_if_needed 对应的独立处理逻辑。
restart_frontend_for_caddy_allowed_hosts_if_needed() {
  local -a domains
  domains=()

  local total idx
  total=${#CADDY_MAP_DOMAINS[@]}
  for (( idx = 1; idx <= total; idx++ )); do
    if [[ "${CADDY_MAP_LABELS[$idx]}" == "前端" ]]; then
      domains+=("${CADDY_MAP_DOMAINS[$idx]}")
    fi
  done

  (( ${#domains[@]} > 0 )) || return 0

  local allowed_hosts
  allowed_hosts="${(j:,:)domains}"

  highlight_echo "检测到前端域名映射，重启 frontend:dev 并注入 Vite allowed host"
  info_echo "__VITE_ADDITIONAL_SERVER_ALLOWED_HOSTS=${allowed_hosts}"

  stop_by_pid_file "frontend:dev" "$FRONTEND_PID_FILE"
  kill_matching_stirling_processes "task frontend:dev" "Stirling-PDF frontend:dev"
  kill_processes_by_port "5173" "Stirling-PDF 前端"

  start_background_task \
    "frontend:dev" \
    "$FRONTEND_PID_FILE" \
    "$FRONTEND_LOG_FILE" \
    env "__VITE_ADDITIONAL_SERVER_ALLOWED_HOSTS=${allowed_hosts}" task frontend:dev

  wait_for_port 5173 60 || true
  success_echo "frontend:dev 已按 Caddy 映射域名重新启动"
}

# 执行已经拆分完成的独立业务步骤。
run_caddy_mapping_flow() {
  echo ""

  if ! collect_caddy_mappings; then
    note_echo "前端和后端映射均已跳过，Caddy 本地域名映射流程结束。"
    return 0
  fi

  ensure_caddy
  restart_frontend_for_caddy_allowed_hosts_if_needed

  write_caddy_hosts
  sync_caddy_proxy_bypass
  generate_stirling_caddyfile
  save_stirling_caddy_state

  if start_stirling_caddy_background; then
    post_check_stirling_caddy_mappings
    open_caddy_mapping_urls
    echo ""
    highlight_echo "Caddy 本地域名映射完成"
    local total idx
    total=${#CADDY_MAP_DOMAINS[@]}
    for (( idx = 1; idx <= total; idx++ )); do
      success_echo "${CADDY_MAP_LABELS[$idx]}：https://${CADDY_MAP_DOMAINS[$idx]}/ -> ${CADDY_MAP_LOCAL_URLS[$idx]}"
    done
    note_echo "Caddy 已后台运行；现在可以安全关闭此终端窗口。"
    note_echo "如果要结束映射：再次运行本脚本，确认自述文件后会先关闭旧映射；或执行：\"${SCRIPT_PATH}\" --stop"
  else
    warn_echo "Caddy 映射未启动成功；Stirling-PDF 本地服务仍保持运行。"
  fi
}

# 封装 show_usage 对应的独立处理逻辑。
show_usage() {
  bold_echo "用法："
  gray_echo "  双击运行：先清理旧进程 / 验证记录 / clone 或更新 / 自检 / 启动"
  gray_echo "  ${SCRIPT_PATH} --stop      停止后台服务"
  gray_echo "  ${SCRIPT_PATH} --status    查看后台服务状态"
  gray_echo "  ${SCRIPT_PATH} --help      查看帮助"
}

# 编排完整业务流程，复杂步骤继续下沉到职责明确的函数。
run_main_flow() {
  case "${1:-}" in
    --stop)
      stop_services
      return 0
      ;;
    --status)
      status_services
      return 0
      ;;
    --help|-h)
      show_usage
      return 0
      ;;
  esac

  show_readme

  # 0.1. 先关闭旧 Caddy 后台映射，避免历史本地域名配置干扰。
  stop_stirling_caddy_mapping

  # 0.2. 你要求的“新打开脚本就归零”：先主动扫描并关闭旧后台服务和端口占用。
  stop_all_stirling_pdf_processes

  # 1. 很多 macOS 开发工具都依赖 Xcode Command Line Tools，必须自检
  ensure_xcode_command_line_tools

  # 2. 安装 / 更新 Homebrew
  install_homebrew

  # 3. 自检 brew 依赖；git 不通过 brew 安装
  install_dependencies

  # 4. 读取记录文件并验证；无效或无记录时重新选择
  choose_download_dir

  # 5. clone 或按需手动更新 Stirling-PDF 代码
  clone_or_update_repo

  # 6. 执行 Stirling-PDF 自检
  run_stirling_checks

  # 7. 启动前再归零一次，确保 task install/check 期间没有残留进程重新占端口
  stop_all_stirling_pdf_processes

  # 8. 后台启动后端和前端
  start_dev_services

  # 9. 打开浏览器
  open_frontend

  echo ""
  success_echo "Stirling-PDF 本地开发环境已启动"
  highlight_echo "前端访问地址：$FRONTEND_URL"
  highlight_echo "后端访问地址：$BACKEND_URL"
  gray_echo "代码目录：$REPO_DIR"
  gray_echo "代码记录文件：$RECORD_FILE"
  gray_echo "后端日志：$BACKEND_LOG_FILE"
  gray_echo "前端日志：$FRONTEND_LOG_FILE"
  gray_echo "脚本日志：$LOG_FILE"
  echo ""
  warm_echo "关闭方式："
  gray_echo "  \"${SCRIPT_PATH}\" --stop"

  # 10. Stirling-PDF 已经启动完成后，再询问是否配置 Caddy 本地域名 HTTPS 映射。
  run_caddy_mapping_flow
}

# 统一收口脚本入口，仅委托已经拆分完成的业务流程。
main() {
  # 主入口只负责委托完整业务流程，复杂逻辑统一下沉。
  run_main_flow "$@"
}

main "$@"
