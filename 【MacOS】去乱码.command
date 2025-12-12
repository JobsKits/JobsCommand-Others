#!/usr/bin/env bash
set -euo pipefail

# ============================== 输出样式 ==============================
_info()    { printf "ℹ️  %s\n" "$*"; }
_ok()      { printf "✅ %s\n" "$*"; }
_warn()    { printf "⚠️  %s\n" "$*"; }
_err()     { printf "❌ %s\n" "$*" >&2; }

# ============================== 剪切板复制 ==============================
# 只要有值就复制到系统剪切板（macOS: pbcopy；Linux: wl-copy/xclip/xsel）
_copy_clipboard() {
  local text="${1:-}"
  [[ -z "$text" ]] && return 0

  if command -v pbcopy >/dev/null 2>&1; then
    printf "%s" "$text" | pbcopy
    _ok "已复制到剪切板"
    return 0
  fi

  if command -v wl-copy >/dev/null 2>&1; then
    printf "%s" "$text" | wl-copy
    _ok "已复制到剪切板"
    return 0
  fi

  if command -v xclip >/dev/null 2>&1; then
    printf "%s" "$text" | xclip -selection clipboard
    _ok "已复制到剪切板"
    return 0
  fi

  if command -v xsel >/dev/null 2>&1; then
    printf "%s" "$text" | xsel --clipboard --input
    _ok "已复制到剪切板"
    return 0
  fi

  _warn "未检测到剪切板工具（pbcopy/wl-copy/xclip/xsel），已跳过复制。"
  return 0
}

# ============================== 解码函数 ==============================
# 默认：unquote（只做 %XX 解码）
# 可选：--plus（把 + 当空格，更适合解码 query/form 编码）
_decode_stdin() {
  local mode="${1:-unquote}"

  if command -v python3 >/dev/null 2>&1; then
    python3 -c 'import sys
from urllib.parse import unquote, unquote_plus
mode=sys.argv[1]
data=sys.stdin.read()
fn=unquote_plus if mode=="plus" else unquote
lines=data.splitlines()
out="\n".join(fn(l) for l in lines)
sys.stdout.write(out)
' "$mode"
    return 0
  fi

  if command -v python >/dev/null 2>&1; then
    python -c 'import sys
try:
  from urllib import unquote, unquote_plus
except Exception:
  from urllib.parse import unquote, unquote_plus
mode=sys.argv[1]
data=sys.stdin.read()
fn=unquote_plus if mode=="plus" else unquote
lines=data.splitlines()
out="\n".join(fn(l) for l in lines)
sys.stdout.write(out)
' "$mode"
    return 0
  fi

  if command -v ruby >/dev/null 2>&1; then
    ruby -e 'require "uri"
mode = ARGV[0]
data = STDIN.read
fn = if mode == "plus"
  ->(s){ URI.decode_www_form_component(s) }
else
  ->(s){ URI::DEFAULT_PARSER.unescape(s) }
end
puts data.lines.map{|l| fn.call(l.chomp)}.join("\n")
' "$mode"
    return 0
  fi

  if command -v perl >/dev/null 2>&1; then
    perl -CS -MEncode -e 'use strict; use warnings;
my $mode = shift @ARGV;
my $data = do { local $/; <STDIN> };
$data =~ s/\r\n/\n/g;
if ($mode eq "plus") { $data =~ tr/+/ /; }
$data =~ s/%([0-9A-Fa-f]{2})/chr(hex($1))/eg;
my $out = eval { Encode::decode("UTF-8", $data, 1) };
if ($@) { print $data; } else { print $out; }
' "$mode"
    return 0
  fi

  _err "缺少解码运行时：请安装 python3（推荐），或 ruby/perl。"
  return 1
}

# ============================== 主流程 ==============================
MODE="unquote"
if [[ "${1:-}" == "--plus" ]]; then
  MODE="plus"
  shift
fi

echo "======== URL 乱码解码脚本 ========"
_info "用途：把 %E7%... 这种 URL 编码字符串解码成中文/可读文本"
_info "退出：输入 q / quit / exit"
_info "提示：解码结果只要有值，将自动复制到系统剪切板"
if [[ "$MODE" == "plus" ]]; then
  _warn "已启用 --plus：会把 + 解析为空格（常用于 query 参数）"
fi

echo
read -r -p "按 [Enter] 开始..." _ || true
echo

# 传参：直接解码并退出（方便命令行一行搞定）
if (( $# > 0 )); then
  for s in "$@"; do
    _ok "原文：$s"
    decoded="$(printf "%s" "$s" | _decode_stdin "$MODE")"
    printf "%s\n" "$decoded"
    _copy_clipboard "$decoded"
    echo
  done
  exit 0
fi

# 交互循环：一直问下一个
while true; do
  read -r -p "➤ 输入 URL/字符串（q 退出）: " input || break
  [[ -z "${input}" ]] && continue
  case "$input" in
    q|quit|exit) _info "已退出。"; break ;;
  esac

  _ok "解码结果："
  decoded="$(printf "%s" "$input" | _decode_stdin "$MODE")"
  printf "%s\n" "$decoded"
  _copy_clipboard "$decoded"
  echo
done
