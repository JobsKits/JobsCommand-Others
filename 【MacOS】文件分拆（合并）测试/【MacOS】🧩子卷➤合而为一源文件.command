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

TARGET_DIR=""
VOLUME_DIRS=()
SELECTED_DIRS=()

print_intro() {
  bold_echo "======== 子卷合并脚本（${SCRIPT_BASENAME}）========"
  note_echo "功能概要："
  echo "  1. 选择一个“目标目录”；"
  echo "  2. 扫描其一级子目录，识别其中的子卷目录（包含类似 原文件@1of4 的文件）；"
  echo "  3. 使用 fzf 选择需要合并的子卷目录（或对全部目录执行）；"
  echo "  4. 按顺序合并子卷为一个完整文件输出到目标目录；"
  echo "  5. 合并成功后，询问是否删除对应的子卷目录。"
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

# ==== 扫描一级子目录，找出含 @ 的“子卷目录” ====
find_volume_dirs() {
  VOLUME_DIRS=()
  local dir

  for dir in "$TARGET_DIR"/*; do
    [[ -d "$dir" ]] || continue

    shopt -s nullglob
    local candidates=("$dir"/*@*)
    shopt -u nullglob

    local has_volume=false
    local f
    for f in "${candidates[@]}"; do
      [[ -f "$f" ]] || continue
      has_volume=true
      break
    done

    if $has_volume; then
      VOLUME_DIRS+=("$dir")
    fi
  done

  if [[ ${#VOLUME_DIRS[@]} -eq 0 ]]; then
    info_echo "未在 $TARGET_DIR 下检测到任何符合子卷规则的目录，任务结束。"
    exit 0
  fi

  note_echo "检测到以下疑似子卷目录："
  local d
  for d in "${VOLUME_DIRS[@]}"; do
    echo "  - $(basename "$d")"
  done
}

# ==== 用 fzf 选择要操作的子卷目录（或全部） ====
select_volume_dirs() {
  local options=()
  local dir
  for dir in "${VOLUME_DIRS[@]}"; do
    local name
    name=$(basename "$dir")
    # 注意两侧空格只在左边，方便后面用“:: ”切分
    options+=("$name :: $dir")
  done

  local selection=""
  if [[ ${#VOLUME_DIRS[@]} -eq 1 ]]; then
    selection="${options[0]}"
    info_echo "仅检测到 1 个子卷目录，将直接处理：${selection%% :: *}"
  else
    # ALL 选项也做成“描述 :: token”的形式，方便统一解析
    options+=("【全部子卷目录】 :: __ALL__")

    note_echo "在 fzf 中选择要合并的子卷目录："
    selection=$(printf '%s\n' "${options[@]}" | fzf --prompt="请选择要合并的子卷目录：" --height=15 --border) || {
      warn_echo "未选择任何目录，任务取消。"
      exit 1
    }
  fi

  # 关键修复点：用“:: ”（两个冒号+空格）切掉左边，只保留 token，不带前导空格
  local selected_token="${selection#*:: }"

  if [[ "$selected_token" == "__ALL__" ]]; then
    SELECTED_DIRS=("${VOLUME_DIRS[@]}")
    info_echo "将对所有 ${#SELECTED_DIRS[@]} 个子卷目录执行合并。"
  else
    SELECTED_DIRS=("$selected_token")
    info_echo "已选择子卷目录：$(basename "$selected_token")"
  fi
}

# ==== 合并单个子卷目录 ====
merge_one_dir() {
  local dir="$1"
  local name
  name=$(basename "$dir")

  note_echo "开始合并子卷目录：$name"

  # 收集子卷文件（只要文件名里有 @ 就认为是子卷）
  local chunks=()
  shopt -s nullglob
  local f
  for f in "$dir"/*@*; do
    [[ -f "$f" ]] || continue
    chunks+=("$f")
  done
  shopt -u nullglob

  if [[ ${#chunks[@]} -eq 0 ]]; then
    warn_echo "目录 $name 中未找到任何子卷文件，跳过。"
    return 1
  fi

  # bash 的 glob 默认按字典序展开，这里直接认为顺序是正确的
  local first_filename
  first_filename=$(basename "${chunks[0]}")

  # 原始文件名 = @ 之前的部分
  local original_name="${first_filename%%@*}"
  if [[ -z "$original_name" ]]; then
    warn_echo "无法从子卷文件名推断原始文件名（目录：$name），跳过。"
    return 1
  fi

  # 从 “1of4” 这类后缀解析总卷数
  local meta="${first_filename#*@}"   # 例如 1of4
  local total_expected=""
  if [[ "$meta" =~ ^[0-9]+of([0-9]+)$ ]]; then
    total_expected="${BASH_REMATCH[1]}"
    local t_no0="${total_expected#0}"
    [[ -n "$t_no0" ]] && total_expected="$t_no0"
  fi

  local total_actual=${#chunks[@]}
  if [[ -n "$total_expected" && "$total_expected" != "$total_actual" ]]; then
    warn_echo "检测到目录 $name 子卷数量异常：标记总数=$total_expected，实际数量=$total_actual，建议手动检查，跳过。"
    return 1
  fi

  local output_file="$TARGET_DIR/$original_name"
  if [[ -e "$output_file" ]]; then
    warn_echo "目标文件已存在：$output_file"
    echo "👉 直接回车：覆盖现有文件"
    echo "👉 输入任意字符后回车：跳过此目录"
    local confirm
    IFS= read -r confirm
    if [[ -z "$confirm" ]]; then
      note_echo "将覆盖现有文件：$output_file"
    else
      note_echo "已选择跳过目录：$name"
      return 0
    fi
  fi

  {
    > "$output_file"
    local chunk
    for chunk in "${chunks[@]}"; do
      cat "$chunk" >> "$output_file" || {
        error_echo "合并过程中出错，文件：$chunk"
        rm -f "$output_file"
        return 1
      }
    done
  } 2>>"$LOG_FILE"

  success_echo "已完成合并：$output_file"

  echo ""
  warn_echo "是否删除子卷目录？（高危操作）"
  echo "👉 直接回车：删除目录 $name"
  echo "👉 输入任意字符后回车：保留目录"
  local confirm_rm
  IFS= read -r confirm_rm
  if [[ -z "$confirm_rm" ]]; then
    if rm -rf -- "$dir"; then
      success_echo "已删除子卷目录：$name"
    else
      error_echo "删除子卷目录失败：$name"
    fi
  else
    note_echo "已保留子卷目录：$name"
  fi
}

merge_selected_dirs() {
  local dir
  for dir in "${SELECTED_DIRS[@]}"; do
    merge_one_dir "$dir"
    echo ""
  done

  success_echo "所有选定的子卷目录合并流程已结束。"
}

main() {
  print_intro
  run_self_check_interactive
  choose_target_directory
  find_volume_dirs
  select_volume_dirs
  merge_selected_dirs
}

main "$@"
