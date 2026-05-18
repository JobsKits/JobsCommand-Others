#!/usr/bin/env bash
set -euo pipefail

SCRIPT_BASENAME=$(basename "$0" | sed 's/\.[^.]*$//')
LOG_FILE="/tmp/${SCRIPT_BASENAME}.log"
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

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" && pwd)"

get_cpu_arch() {
  [[ $(uname -m) == "arm64" ]] && echo "arm64" || echo "x86_64"
}

inject_shellenv_block() {
  local profile_file="$1"
  local shellenv_cmd="$2"

  [[ -z "$profile_file" || -z "$shellenv_cmd" ]] && return 0

  if [[ ! -f "$profile_file" ]]; then
    touch "$profile_file"
    note_echo "已创建配置文件：$profile_file"
  fi

  if grep -Fq "$shellenv_cmd" "$profile_file"; then
    note_echo "已在 $profile_file 中检测到 Homebrew shellenv 配置，跳过注入"
  else
    {
      echo ""
      echo "# >>> Homebrew shellenv (added by ${SCRIPT_BASENAME}) >>>"
      echo "$shellenv_cmd"
      echo "# <<< Homebrew shellenv <<<"
    } >>"$profile_file"
    success_echo "已向 $profile_file 写入 Homebrew shellenv 配置"
  fi
}

install_homebrew() {
  local arch
  arch="$(get_cpu_arch)"
  local shell_path="${SHELL##*/}"
  local profile_file=""
  local brew_bin=""
  local shellenv_cmd=""

  if ! command -v brew &>/dev/null; then
    warn_echo "🧩 未检测到 Homebrew，正在安装中...（架构：$arch）"

    if [[ "$arch" == "arm64" ]]; then
      /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)" || {
        error_echo "❌ Homebrew 安装失败（arm64）"
        exit 1
      }
      brew_bin="/opt/homebrew/bin/brew"
    else
      /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)" || {
        error_echo "❌ Homebrew 安装失败（x86_64）"
        exit 1
      }
      brew_bin="/usr/local/bin/brew"
    fi

    success_echo "✅ Homebrew 安装成功"

    shellenv_cmd="eval \"\$(${brew_bin} shellenv)\""
    case "$shell_path" in
      zsh)  profile_file="$HOME/.zprofile" ;;
      bash) profile_file="$HOME/.bash_profile" ;;
      *)    profile_file="$HOME/.profile" ;;
    esac
    inject_shellenv_block "$profile_file" "$shellenv_cmd"

    eval "$(${brew_bin} shellenv)"

  else
    info_echo "🔄 Homebrew 已安装。是否执行更新？"
    echo "👉 直接按 [Enter]：跳过更新"
    echo "👉 输入任意字符后回车：执行 brew update && brew upgrade && brew cleanup && brew doctor && brew -v"

    local confirm
    IFS= read -r confirm
    if [[ -n "$confirm" ]]; then
      info_echo "⏳ 正在更新 Homebrew..."
      brew update       || { error_echo "❌ brew update 失败"; return 1; }
      brew upgrade      || { error_echo "❌ brew upgrade 失败"; return 1; }
      brew cleanup      || { error_echo "❌ brew cleanup 失败"; return 1; }
      brew doctor       || { warn_echo  "⚠️  brew doctor 有警告/错误，请按提示处理"; }
      brew -v           || { warn_echo  "⚠️  打印 brew 版本失败（可忽略）"; }
      success_echo "✅ Homebrew 已更新"
    else
      note_echo "⏭️ 已选择跳过 Homebrew 更新"
    fi
  fi
}

install_fzf() {
  if ! command -v fzf &>/dev/null; then
    note_echo "📦 未检测到 fzf，正在通过 Homebrew 安装..."
    brew install fzf || { error_echo "❌ fzf 安装失败"; exit 1; }
    success_echo "✅ fzf 安装成功"
  else
    info_echo "🔄 fzf 已安装。是否执行升级？"
    echo "👉 直接按 [Enter]：跳过升级"
    echo "👉 输入任意字符后回车：执行 brew upgrade fzf && brew cleanup"

    local confirm
    IFS= read -r confirm
    if [[ -n "$confirm" ]]; then
      info_echo "⏳ 正在升级 fzf..."
      brew upgrade fzf       || { error_echo "❌ fzf 升级失败"; return 1; }
      brew cleanup           || { warn_echo  "⚠️  brew cleanup 执行时有警告"; }
      success_echo "✅ fzf 已升级到最新版本"
    else
      note_echo "⏭️ 已选择跳过 fzf 升级"
    fi
  fi
}

MAX_CHUNK_BYTES=$((50 * 1024 * 1024))
MAX_CHUNK_LABEL="50 MB"
TARGET_DIR=""
TARGET_FILE=""

format_mb_to_gb() {
  local mb="$1"
  awk -v mb="$mb" 'BEGIN { printf "%.3f", mb / 1024 }'
}

format_bytes_human() {
  local bytes="$1"
  awk -v b="$bytes" 'BEGIN {
    split("B KiB MiB GiB TiB", u, " ")
    i = 1
    while (b >= 1024 && i < 5) {
      b /= 1024
      i++
    }
    if (i == 1) printf "%d %s", b, u[i]
    else printf "%.2f %s", b, u[i]
  }'
}

mb_to_bytes() {
  local mb="$1"
  awk -v mb="$mb" 'BEGIN { printf "%.0f", mb * 1024 * 1024 }'
}

get_file_size_bytes() {
  if stat -f %z "$1" >/dev/null 2>&1; then
    stat -f %z "$1"
  else
    stat -c %s "$1"
  fi
}

calc_balanced_chunk_size_bytes() {
  local file_size_bytes="$1"
  local limit_bytes="$2"

  if (( file_size_bytes <= limit_bytes )); then
    echo "$file_size_bytes"
    return 0
  fi

  local divisor_count
  divisor_count=$(awk -v n="$file_size_bytes" -v l="$limit_bytes" 'BEGIN { printf "%d", int(n / (l + 1)) + 1 }')
  (( divisor_count < 2 )) && divisor_count=2

  local chunk_size_bytes
  chunk_size_bytes=$(awk -v n="$file_size_bytes" -v d="$divisor_count" 'BEGIN { printf "%d", int(n / d) }')
  (( chunk_size_bytes < 1 )) && chunk_size_bytes=1

  echo "$chunk_size_bytes"
}

choose_split_standard() {
  local selected_key=""

  echo ""
  note_echo "请选择拆分标准："

  if command -v fzf &>/dev/null; then
    local -a options=(
      "50MB|脚本当前标准（警告线，默认）"
      "100MiB|GitHub 仓库限制线标准"
      "2GB|GitHub Releases 标准"
      "CUSTOM|自定义标准（单位：MB）"
    )

    selected_key="$(printf '%s
' "${options[@]}" |       fzf         --prompt='请选择拆分标准（Enter 确认，默认 50MB）> '         --height=10         --layout=reverse         --border         --delimiter='|'         --with-nth=2         --select-1         --exit-0 | cut -d'|' -f1)"

    [[ -z "$selected_key" ]] && selected_key="50MB"
  else
    warn_echo "未检测到 fzf，当前步骤将自动回退为数字输入模式。"
    echo "👉 直接按 [Enter]：使用脚本当前标准（50MB，警告线）"
    echo "👉 输入 1 后回车：使用 GitHub 仓库限制线标准（100 MiB）"
    echo "👉 输入 2 后回车：使用 GitHub Releases 标准（2GB）"
    echo "👉 输入 3 后回车：使用自定义标准（单位：MB）"

    local choice
    IFS= read -r choice

    case "$choice" in
      "") selected_key="50MB" ;;
      1)  selected_key="100MiB" ;;
      2)  selected_key="2GB" ;;
      3)  selected_key="CUSTOM" ;;
      *)  selected_key="50MB" ;;
    esac
  fi

  case "$selected_key" in
    50MB)
      MAX_CHUNK_BYTES=$((50 * 1024 * 1024))
      MAX_CHUNK_LABEL="50 MB"
      info_echo "已选择脚本当前标准：50 MB（上限，约 $(format_mb_to_gb 50) GB）"
      ;;
    100MiB)
      MAX_CHUNK_BYTES=$((100 * 1024 * 1024))
      MAX_CHUNK_LABEL="100 MiB"
      info_echo "已选择 GitHub 仓库限制线标准：100 MiB（上限，约 $(format_mb_to_gb 100) GB）"
      ;;
    2GB)
      MAX_CHUNK_BYTES=$((1900 * 1024 * 1024))
      MAX_CHUNK_LABEL="GitHub Releases 安全上限（1900 MiB）"
      info_echo "已选择 GitHub Releases 安全标准：1900 MiB（严格小于 2 GiB）"
      ;;
    CUSTOM)
      local custom_mb
      while true; do
        echo ""
        note_echo "请输入自定义拆分标准（单位：MB，必须大于 0，可带小数）："
        IFS= read -r custom_mb

        if [[ ! "$custom_mb" =~ ^[0-9]+([.][0-9]+)?$ ]]; then
          warn_echo "输入无效：必须是大于 0 的数字，例如 50、100、512、1024、2048。"
          continue
        fi

        if ! awk -v n="$custom_mb" 'BEGIN { exit !(n > 0) }'; then
          warn_echo "输入无效：必须大于 0。"
          continue
        fi

        local custom_gb
        custom_gb="$(format_mb_to_gb "$custom_mb")"
        echo ""
        info_echo "你输入的是：${custom_mb} MB（约 ${custom_gb} GB）"
        echo "👉 直接按 [Enter]：确认使用这个标准"
        echo "👉 输入任意字符后回车：重新输入"

        local confirm_custom
        IFS= read -r confirm_custom
        if [[ -z "$confirm_custom" ]]; then
          MAX_CHUNK_BYTES="$(mb_to_bytes "$custom_mb")"
          MAX_CHUNK_LABEL="${custom_mb} MB"
          success_echo "已选择自定义标准：${custom_mb} MB（约 ${custom_gb} GB）"
          break
        else
          note_echo "已取消本次输入，请重新设置。"
        fi
      done
      ;;
    *)
      MAX_CHUNK_BYTES=$((50 * 1024 * 1024))
      MAX_CHUNK_LABEL="50 MB"
      warn_echo "未识别的选项，已自动使用脚本当前标准：50 MB（上限，约 $(format_mb_to_gb 50) GB）"
      ;;
  esac
}

print_intro() {
  bold_echo "======== 大文件拆分为子卷脚本（${SCRIPT_BASENAME}）========"
  note_echo "功能概要："
  echo "  1. 支持拖入目标目录，也支持直接拖入单个待拆分文件；"
  echo "  2. 目录模式：在目标目录中查找达到拆分阈值的文件（不递归子目录）；"
  echo "  3. 文件模式：只处理你拖入的那个文件；"
  echo "  4. 针对每一个大文件："
  echo "     - 创建与去掉后缀名后的文件名同名的子卷目录；"
  echo "     - 按你选择的拆分标准拆分成多个子卷文件；"
  echo "     - 子卷命名形如：原文件名@001of005（代表第 1/5 卷）；"
  echo "     - 拆分成功后，询问是否删除源文件。"
  echo ""
  gray_echo "注意：文件名中不能包含 '/'，因此示例中的“1/5”会用“001of005”的形式替代。"
  echo ""
  note_echo "按 [Enter] 继续，或 Ctrl+C 退出..."
  IFS= read -r _
}

run_self_check_interactive() {
  echo ""
  note_echo "是否进行环境自检？"
  echo "👉 按 [Enter] 跳过自检（直接开始工作）；"
  echo "👉 输入任意字符后回车：开始执行 Homebrew / fzf 自检和安装/升级。"
  local answer
  IFS= read -r answer
  if [[ -n "$answer" ]]; then
    note_echo "开始环境自检..."
    install_homebrew
    install_fzf
    success_echo "环境自检完成"
  else
    note_echo "已跳过环境自检"
  fi
}

normalize_input_path() {
  local value="$1"
  value="${value%$'\r'}"
  value="${value%$'\n'}"
  value="$(printf '%s' "$value" | sed -e 's/^[[:space:]]*//' -e 's/[[:space:]]*$//')"

  if [[ "${value:0:1}" == "'" && "${value: -1}" == "'" ]] || \
     [[ "${value:0:1}" == '"' && "${value: -1}" == '"' ]]; then
    value="${value:1:${#value}-2}"
  fi

  value="${value%/}"
  value="$(printf '%s' "$value" | perl -pe 's/\\(.)/$1/g')"
  printf '%s
' "$value"
}

choose_target_directory() {
  echo ""
  note_echo "请拖入要处理的【目标目录】或【单个待拆分文件】，然后回车。"
  echo "👉 直接按 [Enter]：使用脚本所在目录：$SCRIPT_DIR"
  local input="${1:-}"

  if [[ -z "$input" ]]; then
    IFS= read -r input
  fi

  if [[ -z "$input" ]]; then
    TARGET_DIR="$SCRIPT_DIR"
    TARGET_FILE=""
  else
    input="$(normalize_input_path "$input")"

    if [[ -d "$input" ]]; then
      TARGET_DIR="$(cd "$input" && pwd)"
      TARGET_FILE=""
    elif [[ -f "$input" ]]; then
      TARGET_DIR="$(cd "$(dirname "$input")" && pwd)"
      TARGET_FILE="${TARGET_DIR}/$(basename "$input")"
    else
      error_echo "指定路径不是有效目录或有效文件：$input"
      exit 1
    fi
  fi

  if [[ -n "$TARGET_FILE" ]]; then
    info_echo "本次操作模式：单文件拆分"
    info_echo "本次操作的目标文件为：$TARGET_FILE"
    gray_echo "子卷目录将创建在源文件同级目录下。"
  else
    info_echo "本次操作模式：目录扫描"
    info_echo "本次操作的目标目录为：$TARGET_DIR"
  fi
}

split_one_file() {
  local file="$1"
  local filename
  filename=$(basename "$file")
  local dirname
  dirname=$(dirname "$file")

  local base_no_ext="$filename"
  if [[ "$filename" == *.* ]]; then
    base_no_ext="${filename%.*}"
  fi
  local subdir="$dirname/$base_no_ext"

  note_echo "开始处理大文件：$filename"

  if [[ -e "$subdir" && ! -d "$subdir" ]]; then
    error_echo "同名路径已存在且不是目录，无法创建子卷目录：$subdir"
    return 1
  fi

  if [[ ! -d "$subdir" ]]; then
    mkdir -p "$subdir" || { error_echo "创建子卷目录失败：$subdir"; return 1; }
    info_echo "已创建子卷目录：$subdir"
  fi

  local tmp_prefix="$subdir/.tmp_${filename}_part_"
  rm -f "${tmp_prefix}"* 2>/dev/null || true

  local file_size_bytes
  file_size_bytes=$(get_file_size_bytes "$file")

  local actual_chunk_size_bytes
  actual_chunk_size_bytes=$(calc_balanced_chunk_size_bytes "$file_size_bytes" "$MAX_CHUNK_BYTES")

  local estimated_main_parts
  estimated_main_parts=$(awk -v n="$file_size_bytes" -v s="$actual_chunk_size_bytes" 'BEGIN { printf "%d", int(n / s) }')

  local remainder_bytes
  remainder_bytes=$(awk -v n="$file_size_bytes" -v s="$actual_chunk_size_bytes" 'BEGIN { printf "%d", n % s }')

  note_echo "拆分上限：${MAX_CHUNK_LABEL}（$(format_bytes_human "$MAX_CHUNK_BYTES")）"
  info_echo "本文件大小：$(format_bytes_human "$file_size_bytes")"
  info_echo "本文件实际主卷大小：$(format_bytes_human "$actual_chunk_size_bytes")；预计主卷数：${estimated_main_parts}；尾卷余数：$(format_bytes_human "$remainder_bytes")"

  if ! split -b "$actual_chunk_size_bytes" -d -a 3 -- "$file" "$tmp_prefix"; then
    error_echo "split 命令执行失败，跳过此文件：$filename"
    rm -f "${tmp_prefix}"* 2>/dev/null || true
    return 1
  fi

  local parts=()
  while IFS= read -r p; do
    parts+=("$p")
  done < <(find "$subdir" -maxdepth 1 -type f -name ".tmp_${filename}_part_*" -print 2>/dev/null | LC_ALL=C sort)

  if [[ ${#parts[@]} -eq 0 ]]; then
    error_echo "未生成任何子卷文件，疑似 split 失败，保留源文件：$filename"
    return 1
  fi

  local total=${#parts[@]}
  local width=${#total}
  (( width < 3 )) && width=3
  local i=1

  for p in "${parts[@]}"; do
    local index_padded total_padded
    printf -v index_padded "%0${width}d" "$i"
    printf -v total_padded "%0${width}d" "$total"
    local newpart="$subdir/${filename}@${index_padded}of${total_padded}"
    mv -f -- "$p" "$newpart" || {
      error_echo "重命名子卷失败：$p"
      rm -f "${tmp_prefix}"* 2>/dev/null || true
      return 1
    }
    i=$((i + 1))
  done

  success_echo "文件 $filename 已成功拆分为 $total 个子卷，位于目录：$subdir"

  echo ""
  warn_echo "是否删除源文件？（高危操作）"
  gray_echo "必须输入 YES 后回车才会删除；其它输入一律保留。"
  local confirm
  IFS= read -r confirm
  if [[ "$confirm" == "YES" ]]; then
    if rm -f -- "$file"; then
      success_echo "已删除源文件：$filename"
    else
      error_echo "删除源文件失败：$filename"
    fi
  else
    note_echo "已选择保留源文件：$filename"
  fi
}

split_large_files() {
  local large_files=()
  local f

  if [[ -n "$TARGET_FILE" ]]; then
    local file_size_bytes
    file_size_bytes=$(get_file_size_bytes "$TARGET_FILE")
    if (( file_size_bytes > MAX_CHUNK_BYTES )); then
      large_files+=("$TARGET_FILE")
    else
      info_echo "目标文件未超过拆分上限（${MAX_CHUNK_LABEL}）：$(basename "$TARGET_FILE")，任务结束。"
      gray_echo "文件大小：$(format_bytes_human "$file_size_bytes")"
      return 0
    fi
  else
    note_echo "正在扫描目录中超过拆分上限（${MAX_CHUNK_LABEL}）的文件（不递归子目录）..."
    while IFS= read -r f; do
      local file_size_bytes
      file_size_bytes=$(get_file_size_bytes "$f")
      if (( file_size_bytes > MAX_CHUNK_BYTES )); then
        large_files+=("$f")
      fi
    done < <(find "$TARGET_DIR" -maxdepth 1 -type f -print 2>/dev/null | LC_ALL=C sort)
  fi

  if [[ ${#large_files[@]} -eq 0 ]]; then
    info_echo "未在 $TARGET_DIR 中找到任何超过 ${MAX_CHUNK_LABEL} 的文件，任务结束。"
    return 0
  fi

  note_echo "共找到 ${#large_files[@]} 个待拆分文件："
  for f in "${large_files[@]}"; do
    echo "  - $(basename "$f")"
  done

  echo ""
  note_echo "按 [Enter] 开始按顺序处理上述文件，或 Ctrl+C 取消。"
  IFS= read -r _

  for f in "${large_files[@]}"; do
    split_one_file "$f"
    echo ""
  done

  success_echo "所有大文件拆分流程已结束。"
}

main() {
  print_intro
  run_self_check_interactive
  choose_split_standard
  choose_target_directory "${1:-}"
  split_large_files
}

main "$@"

