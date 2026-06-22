#!/bin/zsh
# 脚本自述：
# - 脚本名称：【MacOS】Mock.command
# - 核心用途：执行“Mock”对应的自动化任务。
# - 影响范围：可能修改当前项目、用户环境或脚本指定的目标。
# - 运行提示：运行后会先打印内置自述；终端模式按回车确认后继续，按 Ctrl+C 可取消。

# ================================== 基础信息 ==================================

SCRIPT_PATH="${0:A}"
SCRIPT_BASENAME="$(basename "$0" | sed 's/\.[^.]*$//')"
SCRIPT_DIR="$(cd "$(dirname "$SCRIPT_PATH")" && pwd)"
LOG_FILE="/tmp/${SCRIPT_BASENAME}.log"
HTTP_LOG_FILE="/tmp/${SCRIPT_BASENAME}_http_server.log"
PID_FILE="/tmp/${SCRIPT_BASENAME}_http_server.pid"
PORT="8080"
HOST="127.0.0.1"
JSON_DIR_NAME="jsons"
# ================================== 日志与彩色输出 ==================================
# 按当前输出级别记录终端信息，并同步写入脚本日志。
log()            { echo -e "$1" | tee -a "$LOG_FILE"; }
# 按当前输出级别记录终端信息，并同步写入脚本日志。
color_echo()     { log "\033[1;32m$1\033[0m"; }
# 按当前输出级别记录终端信息，并同步写入脚本日志。
info_echo()      { log "\033[1;34mℹ $1\033[0m"; }
# 按当前输出级别记录终端信息，并同步写入脚本日志。
success_echo()   { log "\033[1;32m✔ $1\033[0m"; }
# 按当前输出级别记录终端信息，并同步写入脚本日志。
warn_echo()      { log "\033[1;33m⚠ $1\033[0m"; }
# 按当前输出级别记录终端信息，并同步写入脚本日志。
note_echo()      { log "\033[1;35m➤ $1\033[0m"; }
# 按当前输出级别记录终端信息，并同步写入脚本日志。
error_echo()     { log "\033[1;31m✖ $1\033[0m"; }
# 按当前输出级别记录终端信息，并同步写入脚本日志。
highlight_echo() { log "\033[1;36m🔹 $1\033[0m"; }
# 按当前输出级别记录终端信息，并同步写入脚本日志。
gray_echo()      { log "\033[0;90m$1\033[0m"; }
# 按当前输出级别记录终端信息，并同步写入脚本日志。
bold_echo()      { log "\033[1m$1\033[0m"; }
# 封装 print_divider 对应的独立处理逻辑。
print_divider() {
  gray_echo "=================================================="
}
# 封装 pause_enter 对应的独立处理逻辑。
pause_enter() {
  echo -n $'\n'"按回车继续..."$'\n' | tee -a "$LOG_FILE"
  IFS= read -r _
}
# 收集并校验用户输入，决定后续执行路径。
prompt_optional_upgrade() {
  local name="$1"
  local choice=""
  echo -n $'\n' | tee -a "$LOG_FILE"
  read -r -p "检测到已安装 ${name}，输入任意字符升级，直接回车跳过： " choice
  [[ -n "$choice" ]]
}
# ================================== 通用工具 ==================================
# 封装 require_macos 对应的独立处理逻辑。
require_macos() {
  if [[ "$(uname -s)" != "Darwin" ]]; then
    error_echo "该脚本当前仅针对 macOS 设计，检测到系统不是 macOS"
    exit 1
  fi
}
# 封装 require_basic_commands 对应的独立处理逻辑。
require_basic_commands() {
  local missing=()
  local cmd

  for cmd in basename sed tee uname find sort grep cat ps kill sleep mkdir touch; do
    command -v "$cmd" >/dev/null 2>&1 || missing+=("$cmd")
  done

  if [[ ${#missing[@]} -gt 0 ]]; then
    error_echo "缺少基础命令：${missing[*]}"
    exit 1
  fi
}
# 封装 command_exists 对应的独立处理逻辑。
command_exists() {
  command -v "$1" >/dev/null 2>&1
}
# 解析并返回后续流程需要的目标信息。
get_cpu_arch() {
  [[ "$(uname -m)" == "arm64" ]] && echo "arm64" || echo "x86_64"
}
# 解析并返回后续流程需要的目标信息。
get_shell_name() {
  echo "${SHELL##*/}"
}
# 解析并返回后续流程需要的目标信息。
get_shell_profile_file() {
  local shell_name
  shell_name="$(get_shell_name)"

  case "$shell_name" in
    zsh)  echo "$HOME/.zprofile" ;;
    bash) echo "$HOME/.bash_profile" ;;
    *)    echo "$HOME/.profile" ;;
  esac
}
# 检查当前运行条件是否满足后续流程要求。
ensure_file_exists() {
  local file="$1"
  mkdir -p "$(dirname "$file")"
  touch "$file" 2>/dev/null || {
    error_echo "无法创建或写入配置文件：$file"
    return 1
  }
}
# ================================== 幂等环境注入 ==================================
# 封装 append_block_if_missing 对应的独立处理逻辑。
append_block_if_missing() {
  local file="$1"
  local block_id="$2"
  local content="$3"

  local begin_marker="# >>> ${block_id} >>>"
  local end_marker="# <<< ${block_id} <<<"

  ensure_file_exists "$file" || return 1

  if grep -Fq "$begin_marker" "$file" 2>/dev/null; then
    info_echo "配置块已存在：$block_id -> $file"
    return 0
  fi

  {
    echo ""
    echo "$begin_marker"
    printf "%s\n" "$content"
    echo "$end_marker"
  } >> "$file"

  success_echo "已写入配置块：$block_id -> $file"
}
# 封装 apply_shellenv_now 对应的独立处理逻辑。
apply_shellenv_now() {
  local shellenv_cmd="$1"
  eval "$shellenv_cmd"
  success_echo "环境已在当前终端生效"
}
# ================================== Homebrew 环境处理 ==================================
# 封装 brew_bin_candidates 对应的独立处理逻辑。
brew_bin_candidates() {
  cat <<'BREWEOF'
/opt/homebrew/bin/brew
/usr/local/bin/brew
BREWEOF
}
# 解析并返回后续流程需要的目标信息。
detect_brew_bin() {
  local candidate

  if command_exists brew; then
    command -v brew
    return 0
  fi

  while IFS= read -r candidate; do
    if [[ -x "$candidate" ]]; then
      echo "$candidate"
      return 0
    fi
  done < <(brew_bin_candidates)

  return 1
}
# 检查当前运行条件是否满足后续流程要求。
ensure_brew_env() {
  local brew_bin=""

  if brew_bin="$(detect_brew_bin)"; then
    eval "\$(${brew_bin} shellenv)"
    return 0
  fi

  return 1
}
# 封装 inject_brew_shellenv_if_needed 对应的独立处理逻辑。
inject_brew_shellenv_if_needed() {
  local brew_bin="$1"
  local profile_file shellenv_cmd

  profile_file="$(get_shell_profile_file)"
  shellenv_cmd="eval \"\$(${brew_bin} shellenv)\""

  append_block_if_missing "$profile_file" "homebrew-shellenv" "$shellenv_cmd"
  apply_shellenv_now "$shellenv_cmd"
}
# ================================== Homebrew 检查/安装/升级 ==================================
# 执行对应的环境配置或同步处理。
install_homebrew() {
  local arch brew_bin

  arch="$(get_cpu_arch)"
  warn_echo "未检测到 Homebrew，开始安装...（架构：$arch）"

  if ! command_exists curl; then
    error_echo "安装 Homebrew 依赖 curl，但当前系统未检测到 curl"
    exit 1
  fi

  /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"

  if [[ "$arch" == "arm64" ]]; then
    brew_bin="/opt/homebrew/bin/brew"
  else
    brew_bin="/usr/local/bin/brew"
  fi

  [[ -x "$brew_bin" ]] || {
    error_echo "Homebrew 安装后仍未找到 brew，可执行文件不存在：$brew_bin"
    exit 1
  }

  inject_brew_shellenv_if_needed "$brew_bin"

  if ! command_exists brew; then
    error_echo "Homebrew 安装后 brew 仍不可用"
    exit 1
  fi

  success_echo "Homebrew 安装完成：$(command -v brew)"
}
# 执行对应的环境配置或同步处理。
upgrade_brew_if_needed() {
  if prompt_optional_upgrade "brew"; then
    note_echo "开始执行 brew update"
    brew update
    note_echo "开始执行 brew upgrade"
    brew upgrade
    note_echo "开始执行 brew cleanup"
    brew cleanup || true
    note_echo "开始执行 brew doctor"
    brew doctor || warn_echo "brew doctor 有告警，请按提示自行处理"
    success_echo "brew 升级完成"
  else
    gray_echo "已跳过 brew 升级"
  fi
}
# 检查当前运行条件是否满足后续流程要求。
ensure_brew() {
  print_divider
  bold_echo "第 1 步：检查 Homebrew"

  if ! ensure_brew_env; then
    install_homebrew
  else
    success_echo "已检测到 Homebrew：$(command -v brew)"
    inject_brew_shellenv_if_needed "$(detect_brew_bin)"
    upgrade_brew_if_needed
  fi

  ensure_brew_env || {
    error_echo "Homebrew 环境初始化失败"
    exit 1
  }
}
# ================================== 通用 brew 包检查/安装/升级 ==================================
# 封装 brew_install_or_upgrade_pkg 对应的独立处理逻辑。
brew_install_or_upgrade_pkg() {
  local command_name="$1"
  local brew_pkg_name="$2"
  local display_name="$3"

  print_divider
  bold_echo "检查 ${display_name}"

  if ! command_exists "$command_name"; then
    warn_echo "未检测到 ${display_name}，开始安装..."
    brew install "$brew_pkg_name"

    if ! command_exists "$command_name"; then
      error_echo "${display_name} 安装后仍不可用"
      exit 1
    fi

    success_echo "${display_name} 安装完成"
  else
    success_echo "已检测到 ${display_name}：$(command -v "$command_name")"
  fi

  case "$command_name" in
    python3) gray_echo "当前版本：$(python3 --version 2>/dev/null || true)" ;;
    fzf)     gray_echo "当前版本：$(fzf --version 2>/dev/null || true)" ;;
  esac

  if prompt_optional_upgrade "$display_name"; then
    note_echo "开始升级 ${display_name} ..."
    brew upgrade "$brew_pkg_name" || true
    success_echo "${display_name} 升级流程已执行完毕"
  else
    gray_echo "已跳过 ${display_name} 升级"
  fi
}
# 检查当前运行条件是否满足后续流程要求。
ensure_python3() {
  brew_install_or_upgrade_pkg "python3" "python" "python3"
}
# 检查当前运行条件是否满足后续流程要求。
ensure_fzf() {
  brew_install_or_upgrade_pkg "fzf" "fzf" "fzf"
}
# ================================== 目录与服务 ==================================
# 封装 cd_to_script_dir 对应的独立处理逻辑。
cd_to_script_dir() {
  cd "$SCRIPT_DIR"
  success_echo "已切换到脚本所在目录：$SCRIPT_DIR"
}
# 解析并返回后续流程需要的目标信息。
find_port_owner() {
  if command_exists lsof; then
    lsof -nP -iTCP:"$PORT" -sTCP:LISTEN 2>/dev/null || true
  fi
}
# 解析并返回后续流程需要的目标信息。
get_pid_from_file() {
  [[ -f "$PID_FILE" ]] || return 1
  local pid
  pid="$(cat "$PID_FILE" 2>/dev/null || true)"
  [[ -n "$pid" ]] || return 1
  printf "%s" "$pid"
}
# 检查当前运行条件是否满足后续流程要求。
is_pid_running() {
  local pid="$1"
  ps -p "$pid" >/dev/null 2>&1
}
# 检查当前运行条件是否满足后续流程要求。
is_server_running() {
  local pid=""

  if pid="$(get_pid_from_file)"; then
    if is_pid_running "$pid"; then
      return 0
    fi
    rm -f "$PID_FILE"
  fi

  return 1
}
# 检查当前运行条件是否满足后续流程要求。
check_port_available_for_new_server() {
  if command_exists lsof && lsof -nP -iTCP:"$PORT" -sTCP:LISTEN >/dev/null 2>&1; then
    if is_server_running; then
      warn_echo "后台服务已在运行，无需重复启动"
      return 1
    fi

    error_echo "端口 ${PORT} 已被其他进程占用，请先释放后再运行脚本"
    gray_echo "占用信息如下："
    find_port_owner | tee -a "$LOG_FILE" || true
    exit 1
  fi

  return 0
}
# 封装 wait_for_http_server_ready 对应的独立处理逻辑。
wait_for_http_server_ready() {
  local url="http://${HOST}:${PORT}/"
  local i

  for i in {1..30}; do
    if curl -fsS "$url" >/dev/null 2>&1; then
      return 0
    fi
    sleep 0.3
  done

  return 1
}
# 封装 start_local_http_server_detached 对应的独立处理逻辑。
start_local_http_server_detached() {
  local pid=""

  print_divider
  bold_echo "启动本地 HTTP 服务（后台模式）"

  if is_server_running; then
    pid="$(get_pid_from_file)"
    success_echo "后台服务已在运行：http://${HOST}:${PORT}（PID: ${pid}）"
    return 0
  fi

  check_port_available_for_new_server || return 0

  : > "$HTTP_LOG_FILE"
  note_echo "执行：nohup python3 -m http.server ${PORT} --bind ${HOST}"
  nohup python3 -m http.server "$PORT" --bind "$HOST" >"$HTTP_LOG_FILE" 2>&1 < /dev/null &
  pid=$!
  disown "$pid" 2>/dev/null || true
  echo "$pid" > "$PID_FILE"

  if ! wait_for_http_server_ready; then
    error_echo "本地 HTTP 服务启动失败"
    gray_echo "日志如下："
    cat "$HTTP_LOG_FILE" || true
    rm -f "$PID_FILE"
    exit 1
  fi

  success_echo "本地 HTTP 服务已后台启动：http://${HOST}:${PORT}（PID: ${pid}）"
  gray_echo "现在可以直接关闭这个终端，服务不会跟着退出"
}
# 封装 stop_local_http_server 对应的独立处理逻辑。
stop_local_http_server() {
  local pid=""

  print_divider
  bold_echo "停止本地 HTTP 服务"

  if ! pid="$(get_pid_from_file)"; then
    warn_echo "未找到 PID 文件，可能服务并不是由本脚本启动"
    return 0
  fi

  if ! is_pid_running "$pid"; then
    warn_echo "PID 文件存在，但进程已不在运行，现已清理 PID 文件"
    rm -f "$PID_FILE"
    return 0
  fi

  kill "$pid" >/dev/null 2>&1 || true
  sleep 0.5

  if is_pid_running "$pid"; then
    warn_echo "普通停止失败，尝试强制结束 PID: ${pid}"
    kill -9 "$pid" >/dev/null 2>&1 || true
  fi

  rm -f "$PID_FILE"
  success_echo "本地 HTTP 服务已停止"
}
# 封装 show_status 对应的独立处理逻辑。
show_status() {
  print_divider
  bold_echo "服务状态"

  if is_server_running; then
    local pid
    pid="$(get_pid_from_file)"
    success_echo "运行中：http://${HOST}:${PORT}（PID: ${pid}）"
    gray_echo "脚本目录：$SCRIPT_DIR"
    gray_echo "日志文件：$LOG_FILE"
    gray_echo "HTTP 日志：$HTTP_LOG_FILE"
  else
    warn_echo "当前未运行"
  fi
}
# ================================== JSON 选择与 URL 处理 ==================================
# 解析并返回后续流程需要的目标信息。
get_json_search_root() {
  if [[ -d "$SCRIPT_DIR/$JSON_DIR_NAME" ]]; then
    printf "%s" "$SCRIPT_DIR/$JSON_DIR_NAME"
  else
    printf "%s" "$SCRIPT_DIR"
  fi
}
# 解析并返回后续流程需要的目标信息。
find_json_files() {
  local search_root relative_prefix

  search_root="$(get_json_search_root)"

  if [[ "$search_root" == "$SCRIPT_DIR/$JSON_DIR_NAME" ]]; then
    relative_prefix="$JSON_DIR_NAME/"
  else
    relative_prefix=""
  fi

  find "$search_root" -type f -name '*.json' ! -path '*/.git/*' | while IFS= read -r file; do
    file="${file#"$search_root"/}"
    printf "%s%s\n" "$relative_prefix" "$file"
  done | sort
}
# 检查当前运行条件是否满足后续流程要求。
ensure_json_files_exist() {
  if [[ -z "$(find_json_files)" ]]; then
    warn_echo "未找到任何 JSON 文件"

    if [[ -d "$SCRIPT_DIR/$JSON_DIR_NAME" ]]; then
      gray_echo "已检测到目录：$SCRIPT_DIR/$JSON_DIR_NAME，但里面没有 .json 文件"
    else
      gray_echo "未检测到目录：$SCRIPT_DIR/$JSON_DIR_NAME，已回退为扫描脚本所在目录"
    fi

    exit 0
  fi
}
# 封装 pick_json_file 对应的独立处理逻辑。
pick_json_file() {
  local selected_json

  ensure_json_files_exist

  selected_json="$(find_json_files | fzf --prompt='请选择一个 JSON 文件: ' --height=40% --reverse)"

  if [[ -z "$selected_json" ]]; then
    warn_echo "未选择任何 JSON 文件，脚本结束"
    exit 0
  fi

  printf "%s" "$selected_json"
}
# 封装 url_encode_with_python 对应的独立处理逻辑。
url_encode_with_python() {
  local raw="$1"
  python3 - <<'PY' "$raw"
import sys
import urllib.parse
print(urllib.parse.quote(sys.argv[1]))
PY
}
# 封装 open_url 对应的独立处理逻辑。
open_url() {
  local url="$1"

  if command_exists open; then
    open "$url"
  else
    error_echo "未检测到 open 命令，无法自动打开浏览器"
    return 1
  fi
}
# 封装 open_json_in_browser 对应的独立处理逻辑。
open_json_in_browser() {
  local json_file="$1"
  local encoded_path url

  encoded_path="$(url_encode_with_python "$json_file")"
  url="http://${HOST}:${PORT}/${encoded_path}"

  print_divider
  highlight_echo "你选择的是：$json_file"
  note_echo "浏览器即将打开：$url"

  open_url "$url"
  success_echo "浏览器已打开"
}
# ================================== 自述说明 ==================================
# 展示脚本用途和影响范围，并在执行前等待用户确认。
show_intro() {
  print_divider
  bold_echo "本脚本将执行以下流程："
  log "1. 自述说明，并等待你回车"
  log "2. 检查 Homebrew：没有就安装，有就可选升级"
  log "3. 检查 python3：没有就安装，有就可选升级"
  log "4. 检查 fzf：没有就安装，有就可选升级"
  log "5. 切换到脚本所在目录"
  log "6. 后台启动本地服务：http://${HOST}:${PORT}"
  log "7. 优先从 jsons 文件夹里用 fzf 选择一个 json 文件；若 jsons 不存在则回退扫描脚本目录"
  log "8. 浏览器自动打开对应地址（已处理空格/中文等 URL 编码）"
  log "9. 脚本退出后服务仍保持运行，可直接关闭终端"
  log "10. 以后可用 start / stop / status / restart 管理服务"
  print_divider
  pause_enter
}
# 封装 show_runtime_summary 对应的独立处理逻辑。
show_runtime_summary() {
  print_divider
  success_echo "当前流程已完成，服务仍在后台运行"
  gray_echo "脚本目录：$SCRIPT_DIR"
  gray_echo "日志文件：$LOG_FILE"
  gray_echo "HTTP 日志：$HTTP_LOG_FILE"
  gray_echo "JSON 目录：$(get_json_search_root)"
  gray_echo "PID 文件：$PID_FILE"
  gray_echo "关闭终端是安全的；下次停止服务可运行：$(basename "$0") stop"
}
# 封装 show_usage 对应的独立处理逻辑。
show_usage() {
  print_divider
  bold_echo "用法"
  log "直接双击 / 直接运行：交互式启动并打开 JSON"
  log "$(basename "$0") start   -> 启动后台服务并交互选择 JSON"
  log "$(basename "$0") stop    -> 停止后台服务"
  log "$(basename "$0") status  -> 查看后台服务状态"
  log "$(basename "$0") restart -> 重启后台服务并交互选择 JSON"
}
# ================================== 主流程 ==================================
# 封装 main_start_flow 对应的独立处理逻辑。
main_start_flow() {
  show_intro
  ensure_brew
  ensure_python3
  ensure_fzf
  cd_to_script_dir
  start_local_http_server_detached

  local selected_json
  selected_json="$(pick_json_file)"
  open_json_in_browser "$selected_json"

  show_runtime_summary
}
# 打印脚本内置自述，并按运行入口决定是否等待用户确认。
show_script_intro_and_wait() {
  print -r -- '============================== 脚本内置自述 =============================='
  print -r -- '脚本名称：【MacOS】Mock.command'
  print -r -- '核心用途：执行“Mock”对应的自动化任务。'
  print -r -- '影响范围：可能修改当前项目、用户环境或脚本指定的目标。'
  print -r -- '取消方式：确认前按 Ctrl+C 终止，不会继续执行后续业务。'
  print -r -- '============================================================================'
  if [[ ! -t 0 ]]; then
    print -u2 -r -- '当前没有可交互输入，请在终端中重新运行。'
    return 1
  fi
  read -r "?👉 已了解脚本用途与影响，按回车继续；按 Ctrl+C 取消：" _
}
# 执行入口下沉后的完整业务流程和控制逻辑。
run_main_business_flow() {
  # 检查当前步骤所需的环境、路径或输入条件。
  require_macos
  # 检查当前步骤所需的环境、路径或输入条件。
  require_basic_commands

  # 执行当前流程中的独立业务步骤：处理当前语句。
  : > "$LOG_FILE"

  # 初始化当前流程后续步骤需要使用的变量。
  local action="${1:-start}"

  # 根据当前条件选择对应的执行分支。
  case "$action" in
    # 执行当前流程中的独立业务步骤：start。
    start)
      # 执行当前流程中的独立业务步骤：main_start_flow。
      main_start_flow
      ;;
    # 执行当前流程中的独立业务步骤：stop。
    stop)
      # 执行当前流程中的独立业务步骤：stop_local_http_server。
      stop_local_http_server
      ;;
    # 执行当前流程中的独立业务步骤：status。
    status)
      # 执行当前流程中的独立业务步骤：show_status。
      show_status
      ;;
    # 执行当前流程中的独立业务步骤：restart。
    restart)
      # 执行当前流程中的独立业务步骤：stop_local_http_server。
      stop_local_http_server || true
      # 执行当前流程中的独立业务步骤：main_start_flow。
      main_start_flow
      ;;
    # 执行当前流程中的独立业务步骤：help。
    help|-h|--help)
      # 执行当前流程中的独立业务步骤：show_usage。
      show_usage
      ;;
    # 执行当前流程中的独立业务步骤：处理当前语句。
    *)
      # 执行当前流程中的独立业务步骤：error_echo。
      error_echo "不支持的参数：$action"
      # 执行当前流程中的独立业务步骤：show_usage。
      show_usage
      # 执行当前流程中的独立业务步骤：exit。
      exit 1
      ;;
  esac
}
# 编排脚本的高层业务流程。
# 初始化脚本运行环境，并集中承载原有的顶层执行逻辑。
initialize_script_runtime() {
  set -euo pipefail
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
