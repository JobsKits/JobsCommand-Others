#!/bin/zsh

setopt NO_NOMATCH

SCRIPT_BASENAME=$(basename "$0" | sed 's/\.[^.]*$//')   # 当前脚本名（去掉扩展名）
LOG_FILE="/tmp/${SCRIPT_BASENAME}.log"                  # 设置对应的日志文件路径
: > "$LOG_FILE"

log()            { echo -e "$1" | tee -a "$LOG_FILE"; }
color_echo()     { log "\033[1;32m$1\033[0m"; }         # ✅ 正常绿色输出
info_echo()      { log "\033[1;34mℹ $1\033[0m"; }       # ℹ 信息
success_echo()   { log "\033[1;32m✔ $1\033[0m"; }       # ✔ 成功
warn_echo()      { log "\033[1;33m⚠ $1\033[0m"; }       # ⚠ 警告
warm_echo()      { log "\033[1;33m$1\033[0m"; }         # 🟡 温馨提示（无图标）
note_echo()      { log "\033[1;35m➤ $1\033[0m"; }       # ➤ 说明
error_echo()     { log "\033[1;31m✖ $1\033[0m"; }       # ✖ 错误
err_echo()       { log "\033[1;31m$1\033[0m"; }         # 🔴 错误纯文本
debug_echo()     { log "\033[1;35m🐞 $1\033[0m"; }      # 🐞 调试
highlight_echo() { log "\033[1;36m🔹 $1\033[0m"; }      # 🔹 高亮
gray_echo()      { log "\033[0;90m$1\033[0m"; }         # ⚫ 次要信息
bold_echo()      { log "\033[1m$1\033[0m"; }            # 📝 加粗
underline_echo() { log "\033[4m$1\033[0m"; }            # 🔗 下划线

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]:-${(%):-%x}}")" && pwd)"
SCRIPT_PATH="${SCRIPT_DIR}/$(basename -- "$0")"

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

pause_to_exit() {
  echo ""
  read -r "?🔚 按回车退出..." _
}

ask_any_to_run() {
  local message="$1"
  local answer=""
  read -r "?${message}（直接回车跳过；输入任意字符后回车执行）：" answer
  [[ -n "$answer" ]]
}

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

BACKUP_ENABLED="false"

# 判断文本文件。
is_text_file() {
  grep -Iq . "$1" 2>/dev/null
}

# 替换单个文件。
replace_in_file() {
  local file_path="$1"
  local search_term="$2"
  local replace_term="$3"

  [[ -f "$file_path" ]] || return 1
  is_text_file "$file_path" || return 1
  grep -Fq -- "$search_term" "$file_path" || return 1

  [[ "$BACKUP_ENABLED" == "true" ]] && cp "$file_path" "${file_path}.bak"
  SEARCH_TERM="$search_term" REPLACE_TERM="$replace_term" perl -0pi -e 'BEGIN { $s=$ENV{"SEARCH_TERM"}; $r=$ENV{"REPLACE_TERM"}; } s/\Q$s\E/$r/g' "$file_path"
  success_echo "已替换：$file_path"
}

# 扫描目标。
replace_in_target() {
  local target_path="$1"
  local search_term="$2"
  local replace_term="$3"
  local count=0

  if [[ -f "$target_path" ]]; then
    replace_in_file "$target_path" "$search_term" "$replace_term" && count=$((count + 1))
  elif [[ -d "$target_path" ]]; then
    while IFS= read -r -d '' file_path; do
      if grep -Fq -- "$search_term" "$file_path" 2>/dev/null; then
        replace_in_file "$file_path" "$search_term" "$replace_term"
        count=$((count + 1))
      fi
    done < <(find "$target_path" \
      -path "*/.git" -prune -o \
      -path "*/node_modules" -prune -o \
      -path "*/Pods" -prune -o \
      -type f -print0)
  else
    error_echo "目标路径不存在：$target_path"
    return 1
  fi

  success_echo "命中文件数：$count"
}

# 主流程统一收口。
main() {
  show_readme_and_wait
  read -r "?请输入要搜索的文本：" search_term
  [[ -z "$search_term" ]] && { error_echo "搜索文本不能为空。"; pause_to_exit; exit 1; }

  read -r "?请输入替换后的文本：" replace_term
  read -r "?请拖入目标文件或目录：" raw_path
  local target_path="$(strip_outer_quotes "$raw_path")"

  if ask_any_to_run "是否在替换前为命中文件生成 .bak 备份"; then
    BACKUP_ENABLED="true"
  fi

  replace_in_target "$target_path" "$search_term" "$replace_term"
  success_echo "处理完成。"
  pause_to_exit
}

main "$@"
