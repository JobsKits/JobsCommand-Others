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
    echo "👉 按 [Enter] 继续：将依次执行  brew update && brew upgrade && brew cleanup && brew doctor && brew -v"
    echo "👉 输入任意字符后回车：跳过更新"

    local confirm
    IFS= read -r confirm
    if [[ -z "$confirm" ]]; then
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
    echo "👉 按 [Enter] 继续：将依次执行  brew upgrade fzf && brew cleanup"
    echo "👉 输入任意字符后回车：跳过升级"

    local confirm
    IFS= read -r confirm
    if [[ -z "$confirm" ]]; then
      info_echo "⏳ 正在升级 fzf..."
      brew upgrade fzf       || { error_echo "❌ fzf 升级失败"; return 1; }
      brew cleanup           || { warn_echo  "⚠️  brew cleanup 执行时有警告"; }
      success_echo "✅ fzf 已升级到最新版本"
    else
      note_echo "⏭️ 已选择跳过 fzf 升级"
    fi
  fi
}

MIN_SPLIT_SIZE="50M"   # find 用的阈值
SPLIT_CHUNK_SIZE="50m" # split 每个子卷大小
TARGET_DIR=""

print_intro() {
  bold_echo "======== 大文件拆分为子卷脚本（${SCRIPT_BASENAME}）========"
  note_echo "功能概要："
  echo "  1. 在目标目录中查找 ≥50MB 的文件（不递归子目录）；"
  echo "  2. 针对每一个大文件："
  echo "     - 创建与去掉后缀名后的文件名同名的子卷目录；"
  echo "     - 按 ${SPLIT_CHUNK_SIZE} 大小拆分成多个子卷文件；"
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

choose_target_directory() {
  echo ""
  note_echo "请拖入要处理的【目标目录】，然后回车。"
  echo "👉 直接按 [Enter]：使用脚本所在目录：$SCRIPT_DIR"
  local input
  IFS= read -r input

  if [[ -z "$input" ]]; then
    TARGET_DIR="$SCRIPT_DIR"
  else
    # 去掉可能包裹的引号和末尾的斜杠
    input="${input%/}"
    if [[ "${input:0:1}" == "'" && "${input: -1}" == "'" ]] || \
       [[ "${input:0:1}" == '"' && "${input: -1}" == '"' ]]; then
      input="${input:1:${#input}-2}"
    fi

    if [[ ! -d "$input" ]]; then
      error_echo "指定路径不是有效目录：$input"
      exit 1
    fi
    TARGET_DIR="$(cd "$input" && pwd)"
  fi

  info_echo "本次操作的目标目录为：$TARGET_DIR"
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

  note_echo "使用 split 按 ${SPLIT_CHUNK_SIZE} 拆分文件..."
  if ! split -b "$SPLIT_CHUNK_SIZE" -d -a 3 -- "$file" "$tmp_prefix"; then
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
  echo "👉 直接按 [Enter]：删除源文件 $filename"
  echo "👉 输入任意字符后回车：保留源文件"
  local confirm
  IFS= read -r confirm
  if [[ -z "$confirm" ]]; then
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
  note_echo "正在扫描目录中 ≥${MIN_SPLIT_SIZE} 的文件（不递归子目录）..."
  local large_files=()
  while IFS= read -r f; do
    large_files+=("$f")
  done < <(find "$TARGET_DIR" -maxdepth 1 -type f \( -size +"$MIN_SPLIT_SIZE" -o -size "$MIN_SPLIT_SIZE" \) -print 2>/dev/null | LC_ALL=C sort)

  if [[ ${#large_files[@]} -eq 0 ]]; then
    info_echo "未在 $TARGET_DIR 中找到任何 ≥${MIN_SPLIT_SIZE} 的文件，任务结束。"
    return 0
  fi

  note_echo "共找到 ${#large_files[@]} 个待拆分文件："
  local f
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
  choose_target_directory
  split_large_files
}

main "$@"

