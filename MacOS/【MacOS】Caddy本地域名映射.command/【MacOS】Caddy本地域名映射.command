#!/bin/zsh
# 脚本自述：
# - 脚本名称：【MacOS】Caddy本地域名映射.command
# - 核心用途：执行“Caddy本地域名映射”对应的自动化任务。
# - 影响范围：可能修改当前项目、用户环境或脚本指定的目标。
# - 运行提示：运行后会先打印内置自述；终端模式按回车确认后继续，按 Ctrl+C 可取消。

# >>> Jobs terminal style protection v1 >>>
# 临时保护当前终端配色，业务进程自行管理原有退出清理。
jobs_terminal_style_run() {
    # 无法可靠保存原色时，沿用脚本已有的纯文本约定。
    jobs_terminal_style_plain() {
        PLAIN_OUTPUT=1
        NO_COLOR=1
        FORCE_COLOR=0
        CLICOLOR=0
        ANSI_COLORS_DISABLED=1
        npm_config_color=false
        export PLAIN_OUTPUT NO_COLOR FORCE_COLOR CLICOLOR ANSI_COLORS_DISABLED npm_config_color
        if "$@"; then
            jobs_style_exit_status=0
        else
            jobs_style_exit_status=$?
        fi
        exit "$jobs_style_exit_status"
    }
    if [ ! -t 0 ] || [ ! -t 1 ] || [ -z "${TERM:-}" ] ||
       [ "${TERM:-}" = dumb ] || [ "${NO_COLOR+x}" = x ] ||
       [ "${PLAIN_OUTPUT:-0}" = 1 ] || [ "${IS_SOURCETREE_RUNTIME:-0}" = 1 ] ||
       env | LC_ALL=C grep -qiE '^(SOURCETREE|SOURCE_TREE)'; then
        if "$@"; then
            jobs_style_exit_status=0
        else
            jobs_style_exit_status=$?
        fi
        exit "$jobs_style_exit_status"
    fi
    if [ -n "${TMUX:-}${STY:-}" ]; then
        jobs_terminal_style_plain "$@"
    fi
    jobs_style_tty=$(tty 2>/dev/null) || jobs_terminal_style_plain "$@"
    if ! ps -o pgid= -o tpgid= -p "$$" 2>/dev/null |
         LC_ALL=C awk 'NF == 2 && $1 == $2 && $1 > 0 { foreground = 1 } END { exit !foreground }'; then
        jobs_terminal_style_plain "$@"
    fi
    case ${JOBS_TERMINAL_STYLE_OWNER:-} in
        ''|*[!0-9]*) ;;
        *)
            if [ "${JOBS_TERMINAL_STYLE_TTY:-}" = "$jobs_style_tty" ] &&
               kill -0 "$JOBS_TERMINAL_STYLE_OWNER" 2>/dev/null; then
                if "$@"; then
                    jobs_style_exit_status=0
                else
                    jobs_style_exit_status=$?
                fi
                exit "$jobs_style_exit_status"
            fi
            ;;
    esac
    jobs_style_stty=$(stty -g 2>/dev/null < /dev/tty) || jobs_terminal_style_plain "$@"
    jobs_style_saved=''
    jobs_style_saved_rows=''
    jobs_style_applied_rows=''
    jobs_style_changed=0
    jobs_style_applied_complete=0
    jobs_style_query_active=0
    jobs_style_recovery=''
    jobs_style_exit_status=0
    jobs_style_esc=$(printf '\033')
    jobs_style_bel=$(printf '\007')
    # 只接受本次请求对应的 RGB 响应；非协议输入使本次探测失败。
    jobs_terminal_style_query() {
        jobs_style_query_key=$1
        printf '\033]%s;?\007' "$jobs_style_query_key" > /dev/tty || return 1
        jobs_style_reply=''
        for jobs_style_attempt in 1 2 3; do
            jobs_style_piece=$(dd bs=256 count=1 2>/dev/null < /dev/tty)
            jobs_style_reply=$jobs_style_reply$jobs_style_piece
            case $jobs_style_reply in
                *"$jobs_style_bel"|*"$jobs_style_esc\\") break ;;
                '') ;;
                "$jobs_style_esc"*) ;;
                *) break ;;
            esac
        done
        case $jobs_style_reply in
            "$jobs_style_esc]$jobs_style_query_key;rgb:"*"$jobs_style_bel")
                jobs_style_rgb=${jobs_style_reply#"$jobs_style_esc]$jobs_style_query_key;rgb:"}
                jobs_style_rgb=${jobs_style_rgb%"$jobs_style_bel"}
                ;;
            "$jobs_style_esc]$jobs_style_query_key;rgb:"*"$jobs_style_esc\\")
                jobs_style_rgb=${jobs_style_reply#"$jobs_style_esc]$jobs_style_query_key;rgb:"}
                jobs_style_rgb=${jobs_style_rgb%"$jobs_style_esc\\"}
                ;;
            *) return 1 ;;
        esac
        jobs_style_normalized=$(printf '%s\n' "$jobs_style_rgb" | LC_ALL=C awk -F/ '
            NF != 3 { exit 1 }
            {
                for (i = 1; i <= 3; i++) {
                    h = tolower($i)
                    if (length(h) < 1 || length(h) > 4 || h ~ /[^0-9a-f]/) exit 1
                    n = 0
                    for (j = 1; j <= length(h); j++) n = n * 16 + index("0123456789abcdef", substr(h, j, 1)) - 1
                    value[i] = int(n * 65535 / (16 ^ length(h) - 1) + 0.5)
                }
                printf "%d/%d/%d", value[1], value[2], value[3]
            }
        ') || return 1
        [ -n "$jobs_style_normalized" ]
    }
    # 查询可用不代表终端允许改色，按目标值核对实际生效结果。
    jobs_terminal_style_accepts_target() {
        jobs_style_requested_hex=''
        case $1 in
            10|12) jobs_style_requested_hex=ffffff ;;
            11) jobs_style_requested_hex=000000 ;;
            '4;'*)
                jobs_style_requested_index=0
                for jobs_style_requested_color in 000000 ff5f56 5fd787 ffd75f 5fafff d787ff 5fd7ff eeeeee 9e9e9e ff8787 87ffaf ffff87 87bfff ffafff afffff ffffff; do
                    if [ "4;$jobs_style_requested_index" = "$1" ]; then
                        jobs_style_requested_hex=$jobs_style_requested_color
                        break
                    fi
                    jobs_style_requested_index=$((jobs_style_requested_index + 1))
                done
                ;;
        esac
        [ -n "$jobs_style_requested_hex" ] || return 1
        printf '%s|%s\n' "$jobs_style_normalized" "$jobs_style_requested_hex" | LC_ALL=C awk -F'|' '
            function hexbyte(h) {
                return (index("0123456789abcdef", substr(h, 1, 1)) - 1) * 16 + index("0123456789abcdef", substr(h, 2, 1)) - 1
            }
            {
                if (split($1, actual, "/") != 3 || length($2) != 6) exit 1
                for (i = 1; i <= 3; i++) {
                    difference = actual[i] - hexbyte(substr($2, i * 2 - 1, 2)) * 257
                    if (difference < -255 || difference > 255) exit 1
                }
            }
        '
    }
    # 检测到后续改色时只恢复仍由本次保护持有的项，保留独立恢复入口。
    jobs_terminal_style_cleanup() {
        jobs_style_result=$1
        trap '' HUP INT TERM
        if [ "$jobs_style_query_active" = 1 ]; then
            stty "$jobs_style_stty" 2>/dev/null < /dev/tty || :
            jobs_style_query_active=0
        fi
        if [ "$jobs_style_changed" = 1 ]; then
            jobs_style_cleanup_ok=0
            jobs_style_conflicts=''
            jobs_style_restore_safe=''
            if [ "$jobs_style_applied_complete" = 1 ]; then
                jobs_style_stty=$(stty -g 2>/dev/null < /dev/tty) || jobs_style_stty=''
                if [ -n "$jobs_style_stty" ] && stty -echo -icanon min 0 time 1 2>/dev/null < /dev/tty; then
                    jobs_style_query_active=1
                    jobs_style_cleanup_ok=1
                    while IFS='|' read -r jobs_style_key jobs_style_expected jobs_style_original; do
                        [ -n "$jobs_style_key" ] || continue
                        if ! jobs_terminal_style_query "$jobs_style_key"; then
                            jobs_style_cleanup_ok=0
                            break
                        fi
                        if [ "$jobs_style_normalized" = "$jobs_style_expected" ]; then
                            jobs_style_restore_safe=$jobs_style_restore_safe$jobs_style_original
                        else
                            jobs_style_conflicts="$jobs_style_conflicts $jobs_style_key"
                        fi
                    done <<JOBS_STYLE_APPLIED
$jobs_style_applied_rows
JOBS_STYLE_APPLIED
                    stty "$jobs_style_stty" 2>/dev/null < /dev/tty || jobs_style_cleanup_ok=0
                    jobs_style_query_active=0
                fi
            fi
            if [ "$jobs_style_cleanup_ok" = 1 ] && printf '%s\033[0m' "$jobs_style_restore_safe" > /dev/tty; then
                if [ -z "$jobs_style_conflicts" ]; then
                    rm -f "$jobs_style_recovery"
                    rmdir "${jobs_style_recovery%/*}" 2>/dev/null || :
                else
                    printf '检测到运行期间的配色变更，已保留这些项：%s\n' "$jobs_style_conflicts" >&2
                    printf '确认要覆盖后续改色时才使用恢复入口：sh "%s"\n' "$jobs_style_recovery" >&2
                    [ "$jobs_style_result" -ne 0 ] || jobs_style_result=1
                fi
            else
                printf '终端配色未能安全自动恢复；确认覆盖当前配色后可运行：sh "%s"\n' "$jobs_style_recovery" >&2
                [ "$jobs_style_result" -ne 0 ] || jobs_style_result=1
            fi
        fi
        if [ "${2:-}" = continue ]; then
            jobs_style_cleanup_status=$jobs_style_result
            return 0
        fi
        exit "$jobs_style_result"
    }
    trap 'jobs_terminal_style_cleanup "$jobs_style_exit_status"' 0
    trap 'jobs_style_exit_status=129; exit 129' HUP
    trap 'jobs_style_exit_status=130; exit 130' INT
    trap 'jobs_style_exit_status=143; exit 143' TERM
    if ! stty -echo -icanon min 0 time 1 2>/dev/null < /dev/tty; then
        jobs_terminal_style_plain "$@"
    fi
    jobs_style_query_active=1
    jobs_style_probe_ok=1
    for jobs_style_key in 10 11 12 '4;0' '4;1' '4;2' '4;3' '4;4' '4;5' '4;6' '4;7' '4;8' '4;9' '4;10' '4;11' '4;12' '4;13' '4;14' '4;15'; do
        if ! jobs_terminal_style_query "$jobs_style_key"; then
            jobs_style_probe_ok=0
            break
        fi
        jobs_style_saved=$jobs_style_saved$jobs_style_reply
        jobs_style_saved_rows="$jobs_style_saved_rows$jobs_style_key|$jobs_style_reply
"
    done
    stty "$jobs_style_stty" 2>/dev/null < /dev/tty || { jobs_style_exit_status=1; exit 1; }
    jobs_style_query_active=0
    if [ "$jobs_style_probe_ok" != 1 ]; then
        printf '%s\n' '终端不支持完整配色保存，或启动时收到其它输入；保留原配色并使用纯文本。' >&2
        jobs_terminal_style_plain "$@"
    fi
    jobs_style_recovery_dir=$(umask 077; mktemp -d "${TMPDIR:-/tmp}/jobs-terminal-style.XXXXXX") || jobs_terminal_style_plain "$@"
    jobs_style_recovery=$jobs_style_recovery_dir/restore.sh
    if ! (umask 077; {
        printf '#!/bin/sh\n'
        printf '[ -t 0 ] && [ "$(tty)" = '\''%s'\'' ] || { printf '\''请在原终端运行恢复入口。\\n'\'' >&2; exit 1; }\n' "$jobs_style_tty"
        printf 'printf '\''本操作会覆盖此终端当前配色。确认恢复脚本启动前的配色，请输入 YES：'\'' >&2\n'
        printf 'IFS= read -r jobs_restore_choice\n[ "$jobs_restore_choice" = YES ] || exit 1\n'
        printf 'printf '\''%%s\\033[0m'\'' '\''%s'\'' > /dev/tty\n' "$jobs_style_saved"
    } > "$jobs_style_recovery"); then
        printf '%s\n' '无法保存终端配色恢复入口；保留原配色并使用纯文本。' >&2
        jobs_terminal_style_plain "$@"
    fi
    printf '正在准备本次终端临时配色；强退后恢复入口：sh "%s"\n' "$jobs_style_recovery" >&2
    jobs_style_changed=1
    printf '\033]10;#ffffff\007\033]11;#000000\007\033]12;#ffffff\007' > /dev/tty
    jobs_style_index=0
    for jobs_style_color in 000000 ff5f56 5fd787 ffd75f 5fafff d787ff 5fd7ff eeeeee 9e9e9e ff8787 87ffaf ffff87 87bfff ffafff afffff ffffff; do
        printf '\033]4;%s;#%s\007' "$jobs_style_index" "$jobs_style_color" > /dev/tty
        jobs_style_index=$((jobs_style_index + 1))
    done
    printf '\033[0m' > /dev/tty
    jobs_style_stty=$(stty -g 2>/dev/null < /dev/tty) || { jobs_style_exit_status=1; exit 1; }
    stty -echo -icanon min 0 time 1 2>/dev/null < /dev/tty || { jobs_style_exit_status=1; exit 1; }
    jobs_style_query_active=1
    jobs_style_probe_ok=1
    jobs_style_targets_ok=1
    while IFS='|' read -r jobs_style_key jobs_style_original; do
        [ -n "$jobs_style_key" ] || continue
        if ! jobs_terminal_style_query "$jobs_style_key"; then
            jobs_style_probe_ok=0
            break
        fi
        jobs_style_applied_rows="$jobs_style_applied_rows$jobs_style_key|$jobs_style_normalized|$jobs_style_original
"
        if ! jobs_terminal_style_accepts_target "$jobs_style_key"; then
            jobs_style_targets_ok=0
        fi
    done <<JOBS_STYLE_ORIGINAL
$jobs_style_saved_rows
JOBS_STYLE_ORIGINAL
    stty "$jobs_style_stty" 2>/dev/null < /dev/tty || { jobs_style_exit_status=1; exit 1; }
    jobs_style_query_active=0
    if [ "$jobs_style_probe_ok" != 1 ]; then
        printf '%s\n' '无法核实本次临时配色，已停止启动业务。' >&2
        jobs_style_exit_status=1
        exit 1
    fi
    jobs_style_applied_complete=1
    if [ "$jobs_style_targets_ok" != 1 ]; then
        jobs_terminal_style_cleanup 0 continue
        jobs_style_changed=0
        if [ "$jobs_style_cleanup_status" != 0 ]; then
            jobs_style_exit_status=1
            exit 1
        fi
        trap 'jobs_style_exit_status=129; exit 129' HUP
        trap 'jobs_style_exit_status=130; exit 130' INT
        trap 'jobs_style_exit_status=143; exit 143' TERM
        printf '%s\n' '终端未接受本次配色，已恢复原配色并使用纯文本。' >&2
        jobs_terminal_style_plain "$@"
    fi
    printf '%s\n' '本次终端已临时使用黑底白字。' >&2
    JOBS_TERMINAL_STYLE_TTY=$jobs_style_tty
    JOBS_TERMINAL_STYLE_OWNER=$$
    export JOBS_TERMINAL_STYLE_TTY JOBS_TERMINAL_STYLE_OWNER
    if "$@"; then
        jobs_style_exit_status=0
    else
        jobs_style_exit_status=$?
    fi
    exit "$jobs_style_exit_status"
}
# 仅监督直接执行的入口；被 source 时不切换配色、不重新执行业务。
jobs_terminal_style_bootstrap() {
    jobs_style_bootstrap_script=$1
    shift
    if [ -n "${ZSH_VERSION:-}" ]; then
        case ${ZSH_EVAL_CONTEXT:-} in
            *:file|*:file:*) return 0 ;;
        esac
    elif [ -n "${BASH_VERSION:-}" ] && [ "${BASH_SOURCE:-$jobs_style_bootstrap_script}" != "$jobs_style_bootstrap_script" ]; then
        return 0
    fi
    if [ "${JOBS_TERMINAL_STYLE_REEXEC:-}" = "$jobs_style_bootstrap_script" ]; then
        unset JOBS_TERMINAL_STYLE_REEXEC
        return 0
    fi
    if [ ! -t 0 ] || [ ! -t 1 ] || [ -z "${TERM:-}" ] ||
       [ "${TERM:-}" = dumb ] || [ "${NO_COLOR+x}" = x ] ||
       [ "${PLAIN_OUTPUT:-0}" = 1 ] || [ "${IS_SOURCETREE_RUNTIME:-0}" = 1 ] ||
       [ -n "${TMUX:-}${STY:-}" ] ||
       env | LC_ALL=C grep -qiE '^(SOURCETREE|SOURCE_TREE)'; then
        return 0
    fi
    case ${JOBS_TERMINAL_STYLE_OWNER:-} in
        ''|*[!0-9]*) ;;
        *)
            if kill -0 "$JOBS_TERMINAL_STYLE_OWNER" 2>/dev/null &&
               [ "${JOBS_TERMINAL_STYLE_TTY:-}" = "$(tty 2>/dev/null)" ]; then
                return 0
            fi
            ;;
    esac
    JOBS_TERMINAL_STYLE_REEXEC=$jobs_style_bootstrap_script
    export JOBS_TERMINAL_STYLE_REEXEC
    jobs_terminal_style_run /bin/zsh "$jobs_style_bootstrap_script" "$@"
    jobs_style_bootstrap_result=$?
    exit "$jobs_style_bootstrap_result"
}
jobs_terminal_style_bootstrap "$0" "$@"
# <<< Jobs terminal style protection v1 <<<

# ============================================================
# Caddy macOS 本地域名 HTTPS 映射脚本
# ============================================================

# 仅渲染自述：标题红色加粗，编号正文蓝色常规字重；非彩色终端输出纯文本。
# >>> Jobs Homebrew install choice >>>
# 输出安装诊断，避免混入返回的命令路径。
# JOBS_INPUT_CHOICE_STYLE_BEGIN
# 只展示提示选项；不读取答案、不改变默认值、返回码或业务环境。
jobs_prompt_color_ready() {
  [ -z "${NO_COLOR+x}" ] && [ -n "${TERM:-}" ] && [ "${TERM:-}" != dumb ] &&
    [ "${PLAIN_OUTPUT:-0}" != 1 ] && [ "${IS_SOURCETREE_RUNTIME:-0}" != 1 ]
}
# 原生 awk 分段着色；任意/非空输入优先，括号内外沿用同一个选项。
jobs_prompt_format() {
  /usr/bin/awk -v color="${1:-0}" -v lines="${2:-0}" -v keep="${3:-0}" '
    function typedEnter(value, start, prefix) {
      prefix = substr(value, 1, start - 1)
      gsub(/[“”‘’「」『』"]/, "", prefix)
      gsub(sprintf("%c", 39), "", prefix)
      if (prefix ~ /(空格|[Ss][Pp][Aa][Cc][Ee])[[:space:]]*(后|再|并|[Tt][Hh][Ee][Nn])?[[:space:]]*$/) return 1
      return prefix ~ /(输入|键入|填写|[Tt]ype)[^；;|]*[[:alnum:]_+-]+[[:space:]]*(后|再|并)?[[:space:]]*$/
    }
    function greenPosition(value, token, start) {
      if (match(value, /(直接|仅|只需|只|按下|按)?[[:space:]]*(回车|回車)/)) {
        start = RSTART
        return typedEnter(value, start) ? 0 : start
      }
      if (!match(value, /(^|[^[:alnum:]_])([Ee][Nn][Tt][Ee][Rr]|[Rr][Ee][Tt][Uu][Rr][Nn])([^[:alnum:]_]|$)/)) return 0
      start = RSTART
      token = substr(value, RSTART, RLENGTH)
      match(token, /[Ee][Nn][Tt][Ee][Rr]|[Rr][Ee][Tt][Uu][Rr][Nn]/)
      start += RSTART - 1
      return typedEnter(value, start) ? 0 : start
    }
    function segment(value, inherited, start, kind, prefix, body, red, green, connector, left, right, splitAt) {
      if (value == "") return value
      kind = inherited
      start = 1
      if (!kind) {
        if (match(value, /(输入)?(任意|任何)(非空)?(字符|内容|输入|键)|非空(字符|内容|输入)?|其它输入|其他输入|[Tt]ype (anything|any[^ ]*)|[Pp]ress any key/)) {
          red = RSTART
        }
        green = greenPosition(value)
        if (red && green && green < red) {
          left = substr(value, 1, red - 1)
          right = substr(value, red)
          connector = ""
          if (match(left, /(或者|或)[[:space:]]*$/)) {
            connector = substr(left, RSTART)
            left = substr(left, 1, RSTART - 1)
          }
          return segment(left, 0) connector segment(right, 31)
        }
        if (red && green && red < green && match(value, /或[[:space:]]*(直接|仅|只需|只|按下|按)?(回车|回車)/)) {
          splitAt = RSTART
          return segment(substr(value, 1, splitAt - 1), 31) "或" segment(substr(value, splitAt + length("或")), 0)
        }
        if (red) {
          kind = 31
          start = red
        } else if (green) {
          kind = 32
          start = green
        }
      }
      if (!kind || !color) return value
      prefix = substr(value, 1, start - 1)
      body = substr(value, start)
      return prefix esc "[1;" kind "m" body esc "[0m"
    }
    function render(value, output, part, boundary, inherited, kind, consumed, depth, original) {
      original = value
      gsub(esc "\\[[0-9;]*m", "", value)
      if (color && keep && !greenPosition(value) && value !~ /(任意|任何|非空|其它输入|其他输入|[Tt]ype (anything|any[^ ]*)|[Pp]ress any key)/) return original
      output = ""
      inherited = 0
      depth = 0
      while (match(value, /[；;\/|，,、？?：:=＝（）()\[\]【】]/)) {
        part = substr(value, 1, RSTART - 1)
        boundary = substr(value, RSTART, RLENGTH)
        consumed = RSTART + RLENGTH
        output = output segment(part, inherited) boundary
        if (boundary ~ /[（(\[【]/) {
          depth++
          if (part ~ /(任意|任何|非空|其它输入|其他输入|[Tt]ype (anything|any[^ ]*)|[Pp]ress any key)/) inherited = 31
          else if (greenPosition(part)) inherited = 32
        } else if (boundary ~ /[）)\]】]/) {
          if (depth) depth--
        } else if (boundary ~ /[：:=＝]/) {
          if (!inherited) {
            if (part ~ /(任意|任何|非空|其它输入|其他输入)/) inherited = 31
            else if (greenPosition(part)) inherited = 32
          }
        } else if (!depth) inherited = 0
        value = substr(value, consumed)
      }
      return output segment(value, inherited)
    }
    BEGIN { esc = sprintf("%c", 27); first = 1 }
    {
      if (lines == 2) {
        if (!first) printf "%s\n", render(pending)
        pending = $0
        first = 0
        next
      }
      if (!lines && !first) printf "\n"
      printf "%s", render($0)
      if (lines) printf "\n"
      first = 0
    }
    END {
      if (lines == 2 && !first) {
        sub(sprintf("%c", 1) "$", "", pending)
        printf "%s", render(pending)
      }
    }
  '
}
# read 的命令替换会使 stdout 成为管道，按输入与提示所在 stderr 判断终端。
jobs_prompt_render() {
  local jobs_prompt_color=0
  if [ -t 0 ] && [ -t 2 ] && jobs_prompt_color_ready; then jobs_prompt_color=1; fi
  printf "%s" "$1" | jobs_prompt_format "$jobs_prompt_color" 0
}
# 仅放在显示链末端；tee 在此函数之前接收纯文本，不把 ANSI 写入日志。
jobs_prompt_stream() {
  local jobs_prompt_color=0
  if [ -t 1 ] && jobs_prompt_color_ready; then jobs_prompt_color=1; fi
  jobs_prompt_format "$jobs_prompt_color" 1 1
}
# 显示管道保留原末尾换行；只删除本轮追加的最后一个结束标记。
jobs_prompt_filter() {
  local jobs_prompt_color=0
  if [ -t 1 ] && jobs_prompt_color_ready; then jobs_prompt_color=1; fi
  { /bin/cat; printf '\001'; } | jobs_prompt_format "$jobs_prompt_color" 2 1
}
# 仅包装原 printf/echo/print 展示，原参数、尾换行与显示命令退出码保持不变。
jobs_prompt_output() {
  local jobs_prompt_status=0 jobs_prompt_stderr=0 jobs_prompt_arg="" jobs_prompt_previous=""
  if [ "${1:-}" = print ]; then
    for jobs_prompt_arg in "$@"; do
      case "$jobs_prompt_arg" in -?*u2*|-u2) jobs_prompt_stderr=1 ;; esac
      if [ "$jobs_prompt_previous" = -u ] && [ "$jobs_prompt_arg" = 2 ]; then jobs_prompt_stderr=1; fi
      jobs_prompt_previous="$jobs_prompt_arg"
      [ "$jobs_prompt_arg" != -- ] || break
    done
  fi
  if [ -n "${ZSH_VERSION:-}" ]; then
    if [ "$jobs_prompt_stderr" = 1 ]; then
      "$@" 2>&1 | jobs_prompt_filter >&2
      jobs_prompt_status=$(( ${pipestatus[1]} != 0 ? ${pipestatus[1]} : ${pipestatus[2]} ))
    else
      "$@" | jobs_prompt_filter
      jobs_prompt_status=$(( ${pipestatus[1]} != 0 ? ${pipestatus[1]} : ${pipestatus[2]} ))
    fi
  elif [ -n "${BASH_VERSION:-}" ]; then
    "$@" | jobs_prompt_filter
    jobs_prompt_status=$(( ${PIPESTATUS[0]} != 0 ? ${PIPESTATUS[0]} : ${PIPESTATUS[1]} ))
  else
    "$@" | jobs_prompt_filter
    jobs_prompt_status=$?
  fi
  return "$jobs_prompt_status"
}
# 仅替换日志 primitive 的 tee：磁盘同步追加纯文，终端保留非选项原色。
jobs_prompt_tee() {
  local jobs_prompt_log="$1" jobs_prompt_line="" jobs_prompt_newline=0
  while :; do
    jobs_prompt_line=""
    if IFS= read -r jobs_prompt_line; then jobs_prompt_newline=1; else jobs_prompt_newline=0; [ -n "$jobs_prompt_line" ] || break; fi
    if [ "$jobs_prompt_newline" = 1 ]; then
      { printf '%s\n' "$jobs_prompt_line"; printf '\001'; } | jobs_prompt_format 0 2 >> "$jobs_prompt_log" || return $?
      printf '%s\n' "$jobs_prompt_line" | jobs_prompt_filter || return $?
    else
      { printf '%s' "$jobs_prompt_line"; printf '\001'; } | jobs_prompt_format 0 2 >> "$jobs_prompt_log" || return $?
      printf '%s' "$jobs_prompt_line" | jobs_prompt_filter || return $?
    fi
  done
}
# JOBS_INPUT_CHOICE_STYLE_END

jobs_brew_note() {
  print -u2 -r -- "ℹ $*"
}
# 验证候选能够执行；共享安装只读不代表未安装。
jobs_brew_candidate_ok() {
  local candidate="$1" prefix
  [[ -n "$candidate" && -x "$candidate" ]] || return 1
  HOMEBREW_NO_AUTO_UPDATE=1 "$candidate" --version >/dev/null 2>&1 || return 1
  prefix="$("$candidate" --prefix 2>/dev/null)" || return 1
  [[ "$prefix" == /* && -d "$prefix" ]]
}
# 发现既有健康安装，不以目录可写性决定是否重新安装。
jobs_brew_find() {
  local candidate
  local -a candidates
  candidates=("${JOBS_HOMEBREW_BIN:-}" "$(command -v brew 2>/dev/null)" /opt/homebrew/bin/brew /usr/local/bin/brew
    "${JOBS_HOMEBREW_INSTALL_PREFIX:-$HOME/.local/homebrew}/bin/brew" "$HOME/.homebrew/bin/brew")
  for candidate in "${candidates[@]}"; do
    if jobs_brew_candidate_ok "$candidate"; then
      print -r -- "$candidate"
      return 0
    fi
  done
  return 1
}
# 计算官方系统目录；实际支持范围和授权交由官方安装器处理。
jobs_brew_system_prefix() {
  case "$(/usr/bin/uname -m)" in
    arm64) print -r -- /opt/homebrew ;;
    *) print -r -- /usr/local ;;
  esac
}
# 缺失时强提示选择安装路径；YES 只表示选择系统目录，不验证密码或权限。
jobs_brew_choose_installation() {
  local answer="" system_prefix="$(jobs_brew_system_prefix)"
  if [[ ! -t 0 || ! -t 2 || "${IS_SOURCETREE_RUNTIME:-0}" == 1 ]]; then
    jobs_brew_note "缺少 Homebrew，需要人工选择安装路径；请在可交互终端重新运行，未执行安装。"
    return 1
  fi
  print -u2 -r -- "⚠ Homebrew 尚未就绪，必须先选择安装路径："
  print -u2 -r -- "1、输入精确大写 YES：选择系统标准目录 $system_prefix（Apple Silicon：/opt/homebrew；Intel：/usr/local）。"
  print -u2 -r -- "   这表示你准备向系统目录安装；官方安装器可能随后要求管理员密码，并自行验证权限。"
  jobs_prompt_output print -u2 -r -- "2、其它输入或直接回车：选择用户目录 ${JOBS_HOMEBREW_INSTALL_PREFIX:-$HOME/.local/homebrew}，不使用 sudo；有管理员权限也可选此路径。"
  print -u2 -r -- "本步骤只选择路径，不收集或验证密码；选定路径失败就停止，不自动切换。按 Ctrl+C 取消整个任务。"
  print -u2 -n -r -- "➤ 安装路径选择："
  if ! IFS= read -r answer; then
    jobs_brew_note "输入已取消或结束，停止安装。"
    return 1
  fi
  if [[ "$answer" == YES ]]; then
    typeset -g JOBS_HOMEBREW_INSTALL_MODE=system
  else
    typeset -g JOBS_HOMEBREW_INSTALL_MODE=user
  fi
}
# 将官方系统安装器下载到临时文件后执行，失败不自动改装到用户目录。
jobs_brew_install_system() {
  local installer system_prefix="$(jobs_brew_system_prefix)" installer_result=0
  command -v curl >/dev/null 2>&1 || { jobs_brew_note "缺少 curl，无法获取官方安装器。"; return 1; }
  installer="$(mktemp "${TMPDIR:-/tmp}/jobs-homebrew-install.XXXXXX")" || return 1
  if curl -fsSL --connect-timeout 10 --max-time 120 https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh -o "$installer"; then
    /bin/bash "$installer" || installer_result=$?
  else
    installer_result=1
  fi
  rm -- "$installer"
  if (( installer_result != 0 )); then
    jobs_brew_note "系统目录安装失败（退出码 $installer_result）；停止，不自动切换安装路径。"
    return 1
  fi
  typeset -g JOBS_HOMEBREW_BIN="$system_prefix/bin/brew"
  jobs_brew_candidate_ok "$JOBS_HOMEBREW_BIN" || { jobs_brew_note "官方安装器结束后未找到健康 Homebrew：$JOBS_HOMEBREW_BIN"; return 1; }
}
# 克隆官方稳定版本到用户目录；不覆盖非空目录，不调用 sudo。
jobs_brew_install_user() {
  local prefix="${JOBS_HOMEBREW_INSTALL_PREFIX:-$HOME/.local/homebrew}" stage release_tag git_bin
  [[ "$prefix" == /* && "$prefix" != / && "$prefix" != *[[:space:]:]* ]] || {
    jobs_brew_note "Homebrew 用户前缀须为不含空白或冒号的绝对目录：$prefix"
    return 1
  }
  if [[ -L "$prefix" || ( -e "$prefix" && ! -d "$prefix" ) || ( -d "$prefix" && -n "$(ls -A "$prefix" 2>/dev/null)" ) ]]; then
    jobs_brew_note "用户安装目标非空或不是普通目录，不覆盖：$prefix"
    return 1
  fi
  git_bin="$(command -v git 2>/dev/null)"
  [[ -n "$git_bin" ]] && "$git_bin" --version >/dev/null 2>&1 || { jobs_brew_note "用户目录安装需要可用 Git；请先准备 Git / Command Line Tools。"; return 1; }
  command -v curl >/dev/null 2>&1 || { jobs_brew_note "缺少 curl，无法获取官方稳定版本。"; return 1; }
  export HOMEBREW_NO_SUDO=1
  mkdir -p "${prefix:h}" || return 1
  stage="$(mktemp -d "${prefix:h}/.jobs-homebrew.XXXXXX")" || return 1
  if ! curl -fsSL --connect-timeout 10 --max-time 60 https://api.github.com/repos/Homebrew/brew/releases/latest -o "$stage/release.json"; then
    rm -r -- "$stage"
    jobs_brew_note "获取官方稳定版本失败，停止安装。"
    return 1
  fi
  release_tag="$(sed -n 's/.*"tag_name"[[:space:]]*:[[:space:]]*"\([0-9][0-9.]*\)".*/\1/p' "$stage/release.json" | head -n 1)"
  if [[ ! "$release_tag" =~ '^[0-9]+\.[0-9]+\.[0-9]+$' ]] ||
     ! GIT_TERMINAL_PROMPT=0 "$git_bin" -c http.lowSpeedLimit=1 -c http.lowSpeedTime=60 clone --depth 1 --branch "$release_tag" --single-branch https://github.com/Homebrew/brew.git "$stage/brew" ||
     ! "$git_bin" -C "$stage/brew" checkout -b stable ||
     ! "$git_bin" -C "$stage/brew" config remote.origin.fetch '+refs/heads/*:refs/remotes/origin/*' ||
     ! mkdir -p "$stage/brew/Cellar" "$stage/brew/Caskroom" "$stage/brew/etc" "$stage/brew/var"; then
    rm -r -- "$stage"
    jobs_brew_note "Homebrew 用户目录初始化失败，停止安装。"
    return 1
  fi
  # 空目录也只在下载成功后移除，避免提前改动用户的目标目录。
  if [[ -d "$prefix" ]] && ! rmdir -- "$prefix"; then
    rm -r -- "$stage"
    return 1
  fi
  if ! mv "$stage/brew" "$prefix"; then
    rm -r -- "$stage"
    return 1
  fi
  rm -r -- "$stage"
  typeset -g JOBS_HOMEBREW_BIN="$prefix/bin/brew"
  jobs_brew_candidate_ok "$JOBS_HOMEBREW_BIN" || { jobs_brew_note "用户目录安装后复检失败：$prefix"; return 1; }
}
# 只更新本模块的 shellenv 配置块，并保留配置文件的符号链接和权限。
jobs_brew_save_shellenv() {
  local profile_file="$HOME/.zprofile" profile_stage shellenv_line current_shell="${SHELL:-/bin/zsh}"
  [[ "${current_shell##*/}" != bash ]] || profile_file="$HOME/.bash_profile"
  shellenv_line='eval "$('"${(q)JOBS_HOMEBREW_BIN}"' shellenv)"'
  profile_stage="$(mktemp "${TMPDIR:-/tmp}/jobs-homebrew-profile.XXXXXX")" || return 1
  if [[ -e "$profile_file" || -L "$profile_file" ]]; then
    awk '
      $0 == "# >>> Jobs Homebrew shellenv >>>" { inside = 1; block = $0 ORS; next }
      inside {
        block = block $0 ORS
        if ($0 == "# <<< Jobs Homebrew shellenv <<<") { inside = 0; block = "" }
        next
      }
      { print }
      END { if (inside) printf "%s", block }
    ' "$profile_file" > "$profile_stage" || { rm -- "$profile_stage"; return 1; }
  fi
  {
    print -r -- '# >>> Jobs Homebrew shellenv >>>'
    print -rl -- "$shellenv_line" '# <<< Jobs Homebrew shellenv <<<'
  } >> "$profile_stage"
  if ! cmp -s "$profile_stage" "$profile_file"; then
    cat "$profile_stage" > "$profile_file" || { rm -- "$profile_stage"; jobs_brew_note "无法写入用户配置：$profile_file"; return 1; }
  fi
  rm -- "$profile_stage"
}
# 激活当前进程并验证 Ruby 命令层；只有新安装才持久化 shellenv。
jobs_brew_activate() {
  local brew_env
  brew_env="$("$JOBS_HOMEBREW_BIN" shellenv)" || return 1
  eval "$brew_env" || return 1
  typeset -g JOBS_HOMEBREW_PREFIX="$("$JOBS_HOMEBREW_BIN" --prefix)"
  export PATH="$JOBS_HOMEBREW_PREFIX/bin:$JOBS_HOMEBREW_PREFIX/sbin:$PATH"
  rehash
  HOMEBREW_NO_AUTO_UPDATE=1 "$JOBS_HOMEBREW_BIN" config >/dev/null || { jobs_brew_note "Homebrew 命令层复检失败，停止后续业务。"; return 1; }
  if [[ "${1:-}" == installed ]]; then
    if [[ "${JOBS_HOMEBREW_INSTALL_MODE:-}" == user && -z "${HOMEBREW_CASK_OPTS:-}" ]]; then
      export HOMEBREW_CASK_OPTS="--appdir=$HOME/Applications"
    fi
    jobs_brew_save_shellenv || return 1
  fi
}
# 在原版安装位置复用或安装 Homebrew，安装失败必须终止外层业务。
jobs_brew_install_or_exit() {
  local installed=""
  if [[ "${DRY_RUN:-0}" == 1 ]]; then
    jobs_brew_note "演练：Homebrew 系统路径 $(jobs_brew_system_prefix)；用户路径 ${JOBS_HOMEBREW_INSTALL_PREFIX:-$HOME/.local/homebrew}；未询问或执行安装。"
    return 0
  fi
  if ! JOBS_HOMEBREW_BIN="$(jobs_brew_find)"; then
    jobs_brew_choose_installation || exit 1
    case "$JOBS_HOMEBREW_INSTALL_MODE" in
      system) jobs_brew_install_system || exit 1 ;;
      user) jobs_brew_install_user || exit 1 ;;
      *) jobs_brew_note "安装路径选择无效，停止。"; exit 1 ;;
    esac
    installed=installed
  fi
  jobs_brew_activate "$installed" || exit 1
}
# <<< Jobs Homebrew install choice <<<
jobs_intro_style() {
  local intro_color=0
  if [ -t 1 ] && [ -n "${TERM:-}" ] && [ "${TERM:-}" != dumb ] &&
     [ -z "${NO_COLOR+x}" ] && [ "${PLAIN_OUTPUT:-0}" != 1 ] &&
     [ "${IS_SOURCETREE_RUNTIME:-0}" != 1 ]; then
    intro_color=1
  fi
  /usr/bin/awk -v color="$intro_color" -v role="${1:-body}" '
    BEGIN { esc = sprintf("%c", 27) }
    {
      gsub(esc "\\[[0-9;]*m", "")
      gsub(/\\(033|e|x1[bB])\[[0-9;]*m/, "")
      if (!color || $0 ~ /^[[:space:]]*$/) { print; next }
      numbered = ($0 ~ /^[[:space:]➤ℹ🔹✔⚠]*([0-9]+[、.)）]|[0-9]+️⃣|[-•])/)
      heading = ($0 ~ /^[[:space:]]*#{1,6}[[:space:]]/ || $0 ~ /[：:][[:space:]]*$/ || $0 ~ /^[[:space:]]*[=━─-]{3}/)
      title = (!numbered && (role == "title" || heading))
      if (role == "auto" && !seen && !numbered) title = 1
      if ($0 !~ /^[[:space:]]*[=━─-]+[[:space:]]*$/) seen = 1
      printf "%s%s%s\n", esc (title ? "[1;31m" : "[0;34m"), $0, esc "[0m"
    }
  '
}
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]:-${(%):-%x}}")" && pwd)"
SCRIPT_PATH="${SCRIPT_DIR}/$(basename -- "$0")"
SCRIPT_BASENAME=$(basename "$0" | sed 's/\.[^.]*$//')
LOG_FILE="/tmp/${SCRIPT_BASENAME}.log"
CADDYFILE="/tmp/${SCRIPT_BASENAME}.Caddyfile"
STATE_DIR="$HOME/.caddy-local-mapper"
STATE_FILE="${STATE_DIR}/${SCRIPT_BASENAME}.state"
# 按当前输出级别记录终端信息，并同步写入脚本日志。
log()            { echo -e "$1" | jobs_prompt_tee "$LOG_FILE"; }
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
# 封装 escape_sed_pattern 对应的独立处理逻辑。
escape_sed_pattern() {
  printf '%s' "$1" | sed 's/[.[\*^$()+?{}|\\]/\\&/g'
}
# 解析并返回后续流程需要的目标信息。
get_cpu_arch() {
  uname -m
}
# 封装 pause_to_exit 对应的独立处理逻辑。
pause_to_exit() {
  echo ""
  note_echo "日志文件：$LOG_FILE"
  jobs_prompt_output echo "按 [Enter] 退出..."
  local _pause
  IFS= read -r _pause
}
# 展示脚本用途和影响范围，并在执行前等待用户确认。
show_readme() {
  clear
  cat <<EOF_README | jobs_intro_style auto | jobs_prompt_filter























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
# 检查当前运行条件是否满足后续流程要求。
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
# 编排完整业务流程，复杂步骤继续下沉到职责明确的函数。
remove_hosts_domain() {
  local domain="$1"
  domain="$(trim_text "$domain")"
  [[ -n "$domain" ]] || return 0

  local escaped_domain
  escaped_domain="$(escape_sed_pattern "$domain")"
  sudo sed -i '' "/[[:space:]]${escaped_domain}$/d" /etc/hosts 2>/dev/null || true
}
# 执行对应的清理操作，并保留必要的安全检查。
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
# 封装 maybe_stop_only_after_cleanup 对应的独立处理逻辑。
maybe_stop_only_after_cleanup() {
  if [[ "$STOP_ONLY" == "1" ]]; then
    success_echo "已按 --stop 只关闭旧后台映射。"
    note_echo "现在可以安全关闭此终端窗口。"
    pause_to_exit
    exit 0
  fi

  echo ""
  note_echo "旧后台映射已关闭。"
  jobs_prompt_output echo "👉 直接按 [Enter]：继续创建新的映射"
  jobs_prompt_output echo "👉 输入 q 后回车：只关闭旧映射并退出"
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
# 执行对应的环境配置或同步处理。
install_homebrew() {
  local jobs_existing_brew=""
  if jobs_existing_brew="$(jobs_brew_find)"; then
    JOBS_HOMEBREW_BIN="$jobs_existing_brew"
    jobs_brew_activate || exit 1
  fi
  local arch="$(get_cpu_arch)"
  local shell_path="${SHELL##*/}"
  local profile_file=""
  local brew_bin=""
  local shellenv_cmd=""

  brew_bin="$(jobs_brew_find 2>/dev/null || true)"

  if [[ -z "$brew_bin" ]]; then
    warn_echo "未检测到 Homebrew，正在安装中...（架构：$arch）"

    if [[ "$arch" == "arm64" ]]; then
      jobs_brew_install_or_exit || {
        error_echo "Homebrew 安装失败（arm64）"
        exit 1
      }
      brew_bin="${JOBS_HOMEBREW_BIN:-$(jobs_brew_find 2>/dev/null || true)}"
    else
      jobs_brew_install_or_exit || {
        error_echo "Homebrew 安装失败（x86_64）"
        exit 1
      }
      brew_bin="${JOBS_HOMEBREW_BIN:-$(jobs_brew_find 2>/dev/null || true)}"
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
  jobs_prompt_output echo "👉 直接按 [Enter]：跳过升级"
  jobs_prompt_output echo "👉 输入任意字符后回车：执行升级"
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
# 执行对应的环境配置或同步处理。
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
  jobs_prompt_output echo "👉 直接按 [Enter]：跳过升级"
  jobs_prompt_output echo "👉 输入任意字符后回车：执行升级"
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
# 编排完整业务流程，复杂步骤继续下沉到职责明确的函数。
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
# 收集并校验用户输入，决定后续执行路径。
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
# 编排完整业务流程，复杂步骤继续下沉到职责明确的函数。
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
# 封装 handle_args 对应的独立处理逻辑。
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
# 检查当前运行条件是否满足后续流程要求。
ensure_local_service() {
  highlight_echo "检查本地服务"

  while true; do
    if check_local_service_once; then
      return 0
    fi

    warn_echo "本地服务未运行时，启动映射会得到 502。"
    jobs_prompt_output echo "👉 直接按 [Enter]：重新检测"
    jobs_prompt_output echo "👉 输入 r 后回车：重新输入本地地址+端口"
    jobs_prompt_output echo "👉 输入 s 后回车：强制继续启动映射"
    jobs_prompt_output echo "👉 输入 q 后回车：取消并退出"
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
# 封装 write_hosts 对应的独立处理逻辑。
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
# 执行对应的环境配置或同步处理。
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
# 封装 generate_caddyfile 对应的独立处理逻辑。
generate_caddyfile() {
  highlight_echo "生成 Caddyfile"

  cat > "$CADDYFILE" <<EOF_CADDY
{
	# 封装 servers 对应的独立处理逻辑。
	servers {
		protocols h1 h2
	}
}

$MAP_DOMAIN {
	tls internal

	# 封装 header 对应的独立处理逻辑。
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
# 封装 save_state 对应的独立处理逻辑。
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
# 封装 start_caddy_background 对应的独立处理逻辑。
start_caddy_background() {
  highlight_echo "准备启动后台映射"
  jobs_prompt_output note_echo "按 [Enter]：启动 Caddy 后台映射；关闭终端不影响映射继续运行。"
  jobs_prompt_output echo "👉 输入 q 后回车：取消启动并退出"
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
# 封装 post_check 对应的独立处理逻辑。
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
# 封装 open_target_url 对应的独立处理逻辑。
open_target_url() {
  open "https://${MAP_DOMAIN}/" >/dev/null 2>&1 || true
}
# 打印脚本内置自述，并按运行入口决定是否等待用户确认。
show_script_intro_and_wait() {
  print -r -- '============================== 脚本内置自述 ==============================' | jobs_intro_style title
  print -r -- '脚本名称：【MacOS】Caddy本地域名映射.command' | jobs_intro_style title
  print -r -- '核心用途：执行“Caddy本地域名映射”对应的自动化任务。' | jobs_intro_style body
  print -r -- '影响范围：可能修改当前项目、用户环境或脚本指定的目标。' | jobs_intro_style body
  print -r -- '取消方式：确认前按 Ctrl+C 终止，不会继续执行后续业务。' | jobs_intro_style body
  print -r -- '============================================================================' | jobs_intro_style title
  if [[ ! -t 0 ]]; then
    print -u2 -r -- '当前没有可交互输入，请在终端中重新运行。'
    return 1
  fi
  read -r "?$(jobs_prompt_render "👉 已了解脚本用途与影响，按回车继续；按 Ctrl+C 取消：")" _
}
# ------------------------------------------------------------
# main 收口
# 执行入口下沉后的完整业务流程和控制逻辑。
run_main_business_flow() {
  # 展示脚本说明并等待用户确认影响范围。
  show_readme

  # 执行当前流程中的独立业务步骤：highlight_echo。
  highlight_echo "开始 Caddy 本地域名映射"
  # 执行当前流程中的独立业务步骤：info_echo。
  info_echo "脚本目录：$SCRIPT_DIR"
  # 执行当前流程中的独立业务步骤：info_echo。
  info_echo "脚本路径：$SCRIPT_PATH"
  # 执行当前流程中的独立业务步骤：info_echo。
  info_echo "日志文件：$LOG_FILE"

  # 执行当前流程中的独立业务步骤：handle_args。
  handle_args "$@"
  # 检查当前步骤所需的环境、路径或输入条件。
  ensure_sudo
  # 清理本次流程产生的临时内容或指定缓存。
  cleanup_old_mapping
  # 清理本次流程产生的临时内容或指定缓存。
  maybe_stop_only_after_cleanup

  # 执行当前流程中的独立业务步骤：处理当前语句。
  [[ -n "$LOCAL_URL" ]] || prompt_local_target ""
  # 执行当前流程中的独立业务步骤：处理当前语句。
  [[ -n "$MAP_DOMAIN" ]] || prompt_map_domain ""

  # 执行安装步骤，并保留命令失败信息供后续排查。
  install_homebrew
  # 执行安装步骤，并保留命令失败信息供后续排查。
  install_caddy
  # 检查当前步骤所需的环境、路径或输入条件。
  ensure_local_service
  # 执行当前流程中的独立业务步骤：write_hosts。
  write_hosts
  # 同步或复制当前流程要求的目标内容。
  sync_proxy_bypass
  # 执行当前流程中的独立业务步骤：generate_caddyfile。
  generate_caddyfile
  # 执行当前流程中的独立业务步骤：save_state。
  save_state
  # 执行当前流程中的独立业务步骤：start_caddy_background。
  start_caddy_background
  # 检查当前步骤所需的环境、路径或输入条件。
  post_check
  # 执行当前流程中的独立业务步骤：open_target_url。
  open_target_url

  # 输出当前流程的完成状态、摘要和日志位置。
  success_echo "全部完成"
  # 执行当前流程中的独立业务步骤：note_echo。
  note_echo "现在可以安全关闭终端；Caddy 后台映射仍会继续运行。"
  # 执行当前流程中的独立业务步骤：pause_to_exit。
  pause_to_exit
}
# 编排脚本的高层业务流程。
# 初始化脚本运行环境，并集中承载原有的顶层执行逻辑。
initialize_script_runtime() {
  mkdir -p "$STATE_DIR"
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
