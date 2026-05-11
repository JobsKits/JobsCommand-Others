#!/bin/zsh

# ============================================================
# Caddy macOS 本地域名 HTTPS 映射脚本
# ============================================================

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]:-${(%):-%x}}")" && pwd)"
SCRIPT_PATH="${SCRIPT_DIR}/$(basename -- "$0")"
SCRIPT_BASENAME=$(basename "$0" | sed 's/\.[^.]*$//')
LOG_FILE="/tmp/${SCRIPT_BASENAME}.log"
CADDYFILE="/tmp/${SCRIPT_BASENAME}.Caddyfile"
STATE_DIR="$HOME/.caddy-local-mapper"
STATE_FILE="${STATE_DIR}/${SCRIPT_BASENAME}.state"

mkdir -p "$STATE_DIR"
: > "$LOG_FILE"

log()            { echo -e "$1" | tee -a "$LOG_FILE"; }
color_echo()     { log "\033[1;32m$1\033[0m"; }
info_echo()      { log "\033[1;34mℹ $1\033[0m"; }
success_echo()   { log "\033[1;32m✔ $1\033[0m"; }
warn_echo()      { log "\033[1;33m⚠ $1\033[0m"; }
warm_echo()      { log "\033[1;33m$1\033[0m"; }
note_echo()      { log "\033[1;35m➤ $1\033[0m"; }
error_echo()     { log "\033[1;31m✖ $1\033[0m"; }
err_echo()       { log "\033[1;31m$1\033[0m"; }
debug_echo()     { log "\033[1;35m🐞 $1\033[0m"; }
highlight_echo() { log "\033[1;36m🔹 $1\033[0m"; }
gray_echo()      { log "\033[0;90m$1\033[0m"; }
bold_echo()      { log "\033[1m$1\033[0m"; }
underline_echo() { log "\033[4m$1\033[0m"; }

LOCAL_HOST=""
LOCAL_PORT=""
LOCAL_UPSTREAM=""
LOCAL_URL=""
MAP_DOMAIN=""
STOP_ONLY="0"

# ------------------------------------------------------------
# 基础工具
# ------------------------------------------------------------
trim_text() {
  printf '%s' "$1" | sed 's/^[[:space:]]*//; s/[[:space:]]*$//'
}

escape_sed_pattern() {
  printf '%s' "$1" | sed 's/[.[\*^$()+?{}|\\]/\\&/g'
}

get_cpu_arch() {
  uname -m
}

pause_to_exit() {
  echo ""
  note_echo "日志文件：$LOG_FILE"
  echo "按 [Enter] 退出..."
  local _pause
  IFS= read -r _pause
}

show_readme() {
  clear
  cat <<EOF_README























Caddy macOS 本地域名 HTTPS 映射脚本
============================================================
➤ 这个脚本会执行以下动作：
1. 显示自述文件并阻塞，确认后才执行任何系统修改。
2. 确认后第一件事先关闭旧 Caddy 后台映射，避免历史配置干扰。
3. 接收 2 个参数：本地地址+端口、需要映射的 URL 字符串名。
4. 自检 Homebrew；未安装则按芯片架构自动安装。
5. 自检 Caddy；未安装则通过 Homebrew 安装。
6. 所有升级类操作统一为：直接按 [Enter] 跳过；输入任意字符后回车执行升级。
7. 检测本地服务是否可访问；不可访问时默认不继续启动映射，避免直接 502。
8. 写入 /etc/hosts，把映射域名指向 127.0.0.1。
9. 自动把映射域名加入 macOS 系统代理绕过列表。
10. 生成 Caddyfile，禁用 HTTP/3，只保留 HTTP/1.1 + HTTP/2。
11. localhost 会自动转为 127.0.0.1，避免 Caddy 优先访问 ::1 导致 502。
12. Caddy 反代时把上游 Host 改成本地地址，降低 Vite allowedHosts 拦截概率。
13. 最后按 [Enter] 后启动 Caddy 后台 HTTPS 反向代理；关闭终端不影响映射继续运行。

使用示例：
  直接双击运行，然后按提示输入：
    本地地址+端口：localhost:5173
    映射 URL 字符串名：jobs.pdf.com

  或者命令行传参：
    "脚本路径" "localhost:5173" "jobs.pdf.com"

  只关闭旧后台映射：
    "脚本路径" --stop

⚠ 注意：
1. 本脚本会占用 443 端口；如果 443 被非 Caddy 服务占用，脚本不会强杀。
2. Caddy 只负责反向代理，不负责启动你的本地服务。
3. 如果本地服务未运行，浏览器会看到 502；新版脚本默认会拦住这种情况。
4. 如果目标服务是 Vite，仍建议启动服务时显式加入 allowed host。
5. .com 是公网 TLD，本机映射依赖 /etc/hosts；长期开发更建议使用 .test。
6. 映射启动后可以直接关闭终端；再次运行脚本会先关闭旧后台映射。

日志文件：
  $LOG_FILE

脚本路径：
  $SCRIPT_PATH
============================================================
确认理解后，按 [Enter] 开始...
EOF_README
  local _confirm
  IFS= read -r _confirm
}

ensure_sudo() {
  info_echo "即将需要管理员权限，用于停止旧 Caddy、写入 hosts、启动 443 HTTPS。"
  sudo -v || {
    error_echo "管理员权限验证失败"
    exit 1
  }
}

# ------------------------------------------------------------
# 旧映射清理
# ------------------------------------------------------------
read_state_domain() {
  [[ -f "$STATE_FILE" ]] || return 0
  grep '^MAP_DOMAIN=' "$STATE_FILE" 2>/dev/null | tail -n 1 | sed 's/^MAP_DOMAIN=//'
}

remove_hosts_domain() {
  local domain="$1"
  domain="$(trim_text "$domain")"
  [[ -n "$domain" ]] || return 0

  local escaped_domain
  escaped_domain="$(escape_sed_pattern "$domain")"
  sudo sed -i '' "/[[:space:]]${escaped_domain}$/d" /etc/hosts 2>/dev/null || true
}

cleanup_old_mapping() {
  highlight_echo "关闭旧的后台映射"

  local old_domain
  old_domain="$(read_state_domain)"

  if command -v caddy >/dev/null 2>&1; then
    sudo caddy stop >> "$LOG_FILE" 2>&1 || true
  fi

  sleep 1

  if pgrep -x caddy >/dev/null 2>&1; then
    warn_echo "仍检测到 Caddy 进程，正在强制结束旧后台映射。"
    sudo pkill -x caddy >> "$LOG_FILE" 2>&1 || true
    sleep 1
  fi

  if [[ -n "$old_domain" ]]; then
    remove_hosts_domain "$old_domain"
    info_echo "已清理上次记录的 hosts：$old_domain"
  fi

  rm -f "$STATE_FILE" 2>/dev/null || true

  local port_443_line
  port_443_line="$(sudo lsof -nP -iTCP:443 -sTCP:LISTEN 2>/dev/null | tail -n +2 | head -n 1 || true)"
  if [[ -n "$port_443_line" ]]; then
    if [[ "$port_443_line" == caddy* ]]; then
      warn_echo "443 仍由 Caddy 占用，请稍后重试。"
    else
      error_echo "443 被非 Caddy 服务占用，脚本不会强杀："
      err_echo "$port_443_line"
      pause_to_exit
      exit 1
    fi
  fi

  success_echo "旧映射清理完成"
}

maybe_stop_only_after_cleanup() {
  if [[ "$STOP_ONLY" == "1" ]]; then
    success_echo "已按 --stop 只关闭旧后台映射。"
    note_echo "现在可以安全关闭此终端窗口。"
    pause_to_exit
    exit 0
  fi

  echo ""
  note_echo "旧后台映射已关闭。"
  echo "👉 直接按 [Enter]：继续创建新的映射"
  echo "👉 输入 q 后回车：只关闭旧映射并退出"
  local choice
  IFS= read -r choice
  choice="$(trim_text "$choice")"
  case "$choice" in
    q|Q|quit|exit|cancel)
      success_echo "已关闭旧后台映射，未创建新映射。"
      note_echo "现在可以安全关闭此终端窗口。"
      pause_to_exit
      exit 0
      ;;
  esac
}

# ------------------------------------------------------------
# Homebrew / Caddy 自检
# ------------------------------------------------------------
inject_shellenv_block() {
  local profile_file="$1"
  local id="$2"
  local shellenv="$3"
  local header="# >>> ${id} 环境变量 >>>"

  [[ -n "$profile_file" && -n "$id" && -n "$shellenv" ]] || {
    error_echo "缺少参数：inject_shellenv_block <profile_file> <id> <shellenv>"
    return 1
  }

  touch "$profile_file"

  if grep -Fq "$header" "$profile_file"; then
    info_echo "环境变量块已存在：$id"
  elif grep -Fq "$shellenv" "$profile_file"; then
    info_echo "shellenv 已存在：$shellenv"
  else
    {
      echo ""
      echo "$header"
      echo "$shellenv"
      echo "# <<< ${id} 环境变量 <<<"
    } >> "$profile_file"
    success_echo "已写入环境变量：$id -> $profile_file"
  fi

  eval "$shellenv"
  success_echo "当前终端已生效：$id"
}

install_homebrew() {
  local arch="$(get_cpu_arch)"
  local shell_path="${SHELL##*/}"
  local profile_file=""
  local brew_bin=""
  local shellenv_cmd=""

  if command -v brew >/dev/null 2>&1; then
    brew_bin="$(command -v brew)"
  elif [[ -x "/opt/homebrew/bin/brew" ]]; then
    brew_bin="/opt/homebrew/bin/brew"
  elif [[ -x "/usr/local/bin/brew" ]]; then
    brew_bin="/usr/local/bin/brew"
  fi

  if [[ -z "$brew_bin" ]]; then
    warn_echo "未检测到 Homebrew，正在安装中...（架构：$arch）"

    if [[ "$arch" == "arm64" ]]; then
      /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)" || {
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

  shellenv_cmd="eval \"\$(${brew_bin} shellenv)\""
  case "$shell_path" in
    zsh)  profile_file="$HOME/.zprofile" ;;
    bash) profile_file="$HOME/.bash_profile" ;;
    *)    profile_file="$HOME/.profile" ;;
  esac

  inject_shellenv_block "$profile_file" "homebrew_env" "$shellenv_cmd"

  info_echo "Homebrew 已安装。是否升级？"
  echo "👉 直接按 [Enter]：跳过升级"
  echo "👉 输入任意字符后回车：执行升级"
  local confirm
  IFS= read -r confirm
  if [[ -n "$confirm" ]]; then
    info_echo "正在更新 Homebrew..."
    brew update  || { error_echo "brew update 失败"; exit 1; }
    brew upgrade || { error_echo "brew upgrade 失败"; exit 1; }
    brew cleanup || { error_echo "brew cleanup 失败"; exit 1; }
    brew doctor  || { warn_echo "brew doctor 有警告，请按提示处理。"; }
    brew -v      || { warn_echo "打印 brew 版本失败，可忽略。"; }
    success_echo "Homebrew 已更新"
  else
    note_echo "已跳过 Homebrew 更新"
  fi
}

install_caddy() {
  highlight_echo "自检 Caddy"

  if ! command -v caddy >/dev/null 2>&1; then
    warn_echo "未检测到 Caddy，正在通过 Homebrew 安装..."
    brew install caddy || {
      error_echo "Caddy 安装失败"
      exit 1
    }
    hash -r 2>/dev/null || true
    success_echo "Caddy 安装完成"
    return 0
  fi

  success_echo "Caddy 可用：$(command -v caddy)"
  caddy version 2>&1 | tee -a "$LOG_FILE"

  info_echo "Caddy 已安装。是否升级？"
  echo "👉 直接按 [Enter]：跳过升级"
  echo "👉 输入任意字符后回车：执行升级"
  local confirm
  IFS= read -r confirm
  if [[ -n "$confirm" ]]; then
    info_echo "正在升级 Caddy..."
    brew upgrade caddy || { error_echo "Caddy 升级失败"; exit 1; }
    success_echo "Caddy 已升级"
  else
    note_echo "已跳过 Caddy 升级"
  fi
}

# ------------------------------------------------------------
# 输入与校验
# ------------------------------------------------------------
parse_local_target() {
  local raw="$1"
  raw="$(trim_text "$raw")"
  raw="${raw%/}"

  [[ -n "$raw" ]] || return 1

  raw="${raw#http://}"
  raw="${raw#https://}"
  raw="${raw%%/*}"

  [[ "$raw" == *:* ]] || return 1

  local host="${raw%:*}"
  local port="${raw##*:}"
  host="$(trim_text "$host")"
  port="$(trim_text "$port")"

  [[ -n "$host" && -n "$port" ]] || return 1
  echo "$port" | grep -Eq '^[0-9]+$' || return 1
  (( port >= 1 && port <= 65535 )) || return 1

  if [[ "$host" == "localhost" ]]; then
    LOCAL_HOST="127.0.0.1"
  else
    LOCAL_HOST="$host"
  fi

  LOCAL_PORT="$port"
  LOCAL_UPSTREAM="${LOCAL_HOST}:${LOCAL_PORT}"
  LOCAL_URL="http://${LOCAL_UPSTREAM}/"
  return 0
}

parse_map_domain() {
  local raw="$1"
  raw="$(trim_text "$raw")"
  raw="${raw#http://}"
  raw="${raw#https://}"
  raw="${raw%%/*}"
  raw="${raw%%:*}"
  raw="$(printf '%s' "$raw" | tr '[:upper:]' '[:lower:]')"

  [[ -n "$raw" ]] || return 1
  [[ "$raw" != localhost ]] || return 1
  echo "$raw" | grep -Eq '^[a-z0-9]([a-z0-9-]{0,61}[a-z0-9])?(\.[a-z0-9]([a-z0-9-]{0,61}[a-z0-9])?)+$' || return 1

  MAP_DOMAIN="$raw"
  return 0
}

prompt_local_target() {
  local input="${1:-}"

  while true; do
    if [[ -z "$input" ]]; then
      highlight_echo "请输入本地地址+端口"
      echo "示例：localhost:5173 或 127.0.0.1:8080 或 http://localhost:5173"
      printf "> "
      IFS= read -r input
    fi

    input="$(trim_text "$input")"

    if [[ -z "$input" ]]; then
      warn_echo "本地地址+端口不能为空，请重新输入。"
      input=""
      continue
    fi

    if parse_local_target "$input"; then
      success_echo "本地目标已确认：$LOCAL_URL"
      if [[ "$input" == *localhost* ]]; then
        info_echo "已将 localhost 规整为 127.0.0.1，避免 ::1 连接拒绝。"
      fi
      return 0
    fi

    warn_echo "本地地址+端口格式不合法，请重新输入。"
    echo "示例：localhost:5173 / 127.0.0.1:8080 / http://localhost:5173"
    input=""
  done
}

prompt_map_domain() {
  local input="${1:-}"

  while true; do
    if [[ -z "$input" ]]; then
      highlight_echo "请输入需要映射的 URL 字符串名"
      echo "示例：jobs.pdf.com 或 jobs.pdf.test"
      printf "> "
      IFS= read -r input
    fi

    input="$(trim_text "$input")"

    if [[ -z "$input" ]]; then
      warn_echo "映射 URL 字符串名不能为空，请重新输入。"
      input=""
      continue
    fi

    if parse_map_domain "$input"; then
      success_echo "映射域名已确认：$MAP_DOMAIN"
      if [[ "$MAP_DOMAIN" == *.com ]]; then
        warn_echo ".com 是公网 TLD，本机开发更建议使用 .test。当前仍按你的输入继续。"
      fi
      return 0
    fi

    warn_echo "映射 URL 字符串名格式不合法，请重新输入。"
    echo "示例：jobs.pdf.com / jobs.pdf.test"
    input=""
  done
}

handle_args() {
  if [[ "${1:-}" == "--stop" || "${1:-}" == "stop" ]]; then
    STOP_ONLY="1"
    return 0
  fi

  if [[ -n "${1:-}" ]]; then
    if ! parse_local_target "$1"; then
      warn_echo "命令行参数 1 不合法，将进入交互输入。"
    else
      success_echo "本地目标已确认：$LOCAL_URL"
    fi
  fi

  if [[ -n "${2:-}" ]]; then
    if ! parse_map_domain "$2"; then
      warn_echo "命令行参数 2 不合法，将进入交互输入。"
    else
      success_echo "映射域名已确认：$MAP_DOMAIN"
    fi
  fi
}

# ------------------------------------------------------------
# 本地服务、hosts、代理、Caddyfile
# ------------------------------------------------------------
check_local_service_once() {
  local code
  code="$(curl --noproxy '*' -s -o /dev/null -w '%{http_code}' --max-time 5 "$LOCAL_URL" 2>/dev/null || echo '000')"

  if [[ "$code" == 2* || "$code" == 3* || "$code" == 4* ]]; then
    success_echo "本地服务可访问：$LOCAL_URL（HTTP $code）"
    return 0
  fi

  warn_echo "当前无法访问：$LOCAL_URL（HTTP $code）"
  return 1
}

ensure_local_service() {
  highlight_echo "检查本地服务"

  while true; do
    if check_local_service_once; then
      return 0
    fi

    warn_echo "本地服务未运行时，启动映射会得到 502。"
    echo "👉 直接按 [Enter]：重新检测"
    echo "👉 输入 r 后回车：重新输入本地地址+端口"
    echo "👉 输入 s 后回车：强制继续启动映射"
    echo "👉 输入 q 后回车：取消并退出"
    printf "> "

    local choice
    IFS= read -r choice
    choice="$(trim_text "$choice")"

    case "$choice" in
      "")
        continue
        ;;
      r|R|reselect)
        LOCAL_HOST=""
        LOCAL_PORT=""
        LOCAL_UPSTREAM=""
        LOCAL_URL=""
        prompt_local_target ""
        ;;
      s|S|skip|force)
        warn_echo "已选择强制继续。若本地服务仍未运行，浏览器会看到 502。"
        return 0
        ;;
      q|Q|quit|exit|cancel)
        note_echo "已取消。"
        pause_to_exit
        exit 0
        ;;
      *)
        warn_echo "无法识别输入，请重新选择。"
        ;;
    esac
  done
}

write_hosts() {
  highlight_echo "写入 /etc/hosts"
  remove_hosts_domain "$MAP_DOMAIN"
  echo "127.0.0.1 $MAP_DOMAIN" | sudo tee -a /etc/hosts >/dev/null || {
    error_echo "写入 /etc/hosts 失败"
    exit 1
  }

  success_echo "已写入：127.0.0.1 $MAP_DOMAIN"
  dscacheutil -flushcache 2>/dev/null || true
  sudo killall -HUP mDNSResponder 2>/dev/null || true
  dscacheutil -q host -a name "$MAP_DOMAIN" 2>&1 | tee -a "$LOG_FILE" || true
}

sync_proxy_bypass() {
  highlight_echo "同步系统代理绕过列表"

  local services
  services="$(networksetup -listallnetworkservices 2>/dev/null | tail -n +2 || true)"
  [[ -n "$services" ]] || {
    warn_echo "未读取到网络服务列表，跳过代理绕过同步。"
    return 0
  }

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

    items+=("localhost" "127.0.0.1" "127.0.0.0/8" "::1" "$MAP_DOMAIN")

    local root_domain
    root_domain="$(printf '%s' "$MAP_DOMAIN" | awk -F. '{if (NF>=2) print $(NF-1)"."$NF; else print $0}')"
    [[ -n "$root_domain" ]] && items+=("*.${root_domain}")

    local item exists
    for item in "${items[@]}"; do
      item="$(trim_text "$item")"
      [[ -n "$item" ]] || continue
      exists="0"
      local old
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

generate_caddyfile() {
  highlight_echo "生成 Caddyfile"

  cat > "$CADDYFILE" <<EOF_CADDY
{
	servers {
		protocols h1 h2
	}
}

$MAP_DOMAIN {
	tls internal

	header {
		-Alt-Svc
	}

	reverse_proxy $LOCAL_UPSTREAM {
		header_up Host {upstream_hostport}
		header_up X-Forwarded-Proto https
	}
}
EOF_CADDY

  caddy fmt --overwrite "$CADDYFILE" >> "$LOG_FILE" 2>&1 || true

  success_echo "Caddyfile 已生成：$CADDYFILE"
  gray_echo "----------------------------------------"
  cat "$CADDYFILE" | tee -a "$LOG_FILE"
  gray_echo "----------------------------------------"
}

save_state() {
  cat > "$STATE_FILE" <<EOF_STATE
MAP_DOMAIN=$MAP_DOMAIN
LOCAL_UPSTREAM=$LOCAL_UPSTREAM
CADDYFILE=$CADDYFILE
EOF_STATE
}

# ------------------------------------------------------------
# Caddy 后台启动与自检
# ------------------------------------------------------------
run_with_timeout() {
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

start_caddy_background() {
  highlight_echo "准备启动后台映射"
  note_echo "按 [Enter]：启动 Caddy 后台映射；关闭终端不影响映射继续运行。"
  echo "👉 输入 q 后回车：取消启动并退出"
  printf "> "

  local choice
  IFS= read -r choice
  choice="$(trim_text "$choice")"
  case "$choice" in
    q|Q|quit|exit|cancel)
      note_echo "已取消启动。"
      pause_to_exit
      exit 0
      ;;
  esac

  highlight_echo "启动 Caddy HTTPS 反向代理"
  info_echo "正在后台启动 Caddy，详细日志写入：$LOG_FILE"

  sudo -v || {
    error_echo "管理员权限已失效，无法启动 Caddy。"
    exit 1
  }

  local start_rc=0
  run_with_timeout 20 sudo caddy start --config "$CADDYFILE" --adapter caddyfile
  start_rc=$?

  if [[ "$start_rc" == "124" ]]; then
    error_echo "Caddy 启动命令超时，已终止。最近日志如下："
    tail -n 80 "$LOG_FILE"
    pause_to_exit
    exit 1
  elif [[ "$start_rc" != "0" ]]; then
    error_echo "Caddy 启动失败。最近日志如下："
    tail -n 80 "$LOG_FILE"
    pause_to_exit
    exit 1
  fi

  if ! wait_for_caddy_443; then
    error_echo "Caddy 未成功监听 443。最近日志如下："
    tail -n 80 "$LOG_FILE"
    pause_to_exit
    exit 1
  fi

  run_with_timeout 15 sudo caddy trust || warn_echo "Caddy trust 未完成或无需重复执行，可先忽略；如浏览器证书异常再手动执行：sudo caddy trust"

  success_echo "Caddy 已在后台运行"
  sudo lsof -nP -iTCP:443 -sTCP:LISTEN 2>/dev/null | tee -a "$LOG_FILE" || true
}

post_check() {
  highlight_echo "映射自检"

  local http_code
  http_code="$(curl --noproxy '*' -k -s -o /dev/null -w '%{http_code}' --max-time 8 "https://${MAP_DOMAIN}/" 2>/dev/null || echo '000')"

  if [[ "$http_code" == 2* || "$http_code" == 3* ]]; then
    success_echo "HTTPS 映射可访问：https://${MAP_DOMAIN}/（HTTP $http_code）"
  elif [[ "$http_code" == "403" ]]; then
    warn_echo "HTTPS 返回 403。若目标是 Vite，请确认服务启动时已允许该 Host，或检查项目配置。"
  elif [[ "$http_code" == "502" ]]; then
    warn_echo "HTTPS 返回 502。通常是本地服务已退出或端口不可访问：$LOCAL_URL"
  else
    warn_echo "HTTPS 自检返回 HTTP $http_code，可用下面命令继续排查：curl -vk https://${MAP_DOMAIN}/"
  fi

  echo ""
  highlight_echo "映射完成"
  success_echo "访问地址：https://${MAP_DOMAIN}/"
  note_echo "本地目标：$LOCAL_URL"
  note_echo "Caddy 已后台运行；现在可以安全关闭此终端窗口。"
  note_echo "如果要结束映射：再次运行本脚本，确认自述文件后选择只关闭旧映射即可。"

  echo ""
  note_echo "常用自检命令："
  echo "curl -vk https://${MAP_DOMAIN}/"
  echo "dscacheutil -q host -a name ${MAP_DOMAIN}"
  echo "sudo lsof -nP -iTCP:443 -sTCP:LISTEN"
  echo "cat ${CADDYFILE}"
}

open_target_url() {
  open "https://${MAP_DOMAIN}/" >/dev/null 2>&1 || true
}

# ------------------------------------------------------------
# main 收口
# ------------------------------------------------------------
main() {
  show_readme

  highlight_echo "开始 Caddy 本地域名映射"
  info_echo "脚本目录：$SCRIPT_DIR"
  info_echo "脚本路径：$SCRIPT_PATH"
  info_echo "日志文件：$LOG_FILE"

  handle_args "$@"
  ensure_sudo
  cleanup_old_mapping
  maybe_stop_only_after_cleanup

  [[ -n "$LOCAL_URL" ]] || prompt_local_target ""
  [[ -n "$MAP_DOMAIN" ]] || prompt_map_domain ""

  install_homebrew
  install_caddy
  ensure_local_service
  write_hosts
  sync_proxy_bypass
  generate_caddyfile
  save_state
  start_caddy_background
  post_check
  open_target_url

  success_echo "全部完成"
  note_echo "现在可以安全关闭终端；Caddy 后台映射仍会继续运行。"
  pause_to_exit
}

main "$@"
