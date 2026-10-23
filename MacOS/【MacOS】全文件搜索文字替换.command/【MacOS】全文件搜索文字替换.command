#!/bin/zsh
# shell: zsh
# 脚本自述：
# - 脚本名称：【MacOS】全文件搜索文字替换.command
# - 核心用途：执行“全文件搜索文字替换”对应的自动化任务。
# - 影响范围：可能修改当前项目、用户环境或脚本指定的目标。
# - 运行提示：运行后会先打印内置自述；终端模式按回车确认后继续，按 Ctrl+C 可取消。


# 仅渲染自述：标题红色加粗，编号正文蓝色常规字重；非彩色终端输出纯文本。
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
SCRIPT_SOURCE="${(%):-%x}"
SCRIPT_PATH="${SCRIPT_SOURCE:A}"
SCRIPT_DIR="${SCRIPT_PATH:h}"
SCRIPT_BASENAME="${SCRIPT_PATH:t:r}"
LOG_FILE=""
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

# 展示脚本用途和影响范围，并在执行前等待用户确认。
show_script_intro_and_wait() {
  [[ -t 1 && -n "${TERM:-}" && "$TERM" != dumb ]] && clear
  print -r -- '============================== 脚本内置自述 ==============================' | jobs_intro_style title
  print -r -- '脚本名称：【MacOS】全文件搜索文字替换.command' | jobs_intro_style title
  print -r -- '核心用途：执行“全文件搜索文字替换”对应的自动化任务。' | jobs_intro_style body
  print -r -- '影响范围：可能修改当前项目、用户环境或脚本指定的目标。' | jobs_intro_style body
  print -r -- '取消方式：确认前按 Ctrl+C 终止，不会继续执行后续业务。' | jobs_intro_style body
  print -r -- '============================================================================' | jobs_intro_style title
  echo "" | jobs_intro_style body
  [[ -t 0 ]] || { print -u2 -- '请在交互终端运行；未执行替换。'; exit 1; }
  read -r "?👉 已了解脚本用途与影响，按回车继续；按 Ctrl+C 取消：" _ || exit 1
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
  IFS= read -r "?${message}（直接回车跳过；输入任意字符后回车执行）：" answer || return 2
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
  local check_result=0 temporary_file=""

  [[ -f "$file_path" && ! -L "$file_path" ]] || return 1
  [[ -n "$search_term" ]] || { error_echo '搜索文本不能为空。'; return 2; }
  is_text_file "$file_path"
  check_result=$?
  if (( check_result > 1 )); then
    error_echo "文本检测读取失败：$file_path"
    return 2
  fi
  (( check_result == 0 )) || return 1
  grep -Fq -- "$search_term" "$file_path"
  check_result=$?
  if (( check_result > 1 )); then
    error_echo "搜索读取失败：$file_path"
    return 2
  fi
  (( check_result == 0 )) || return 1

  if [[ "$BACKUP_ENABLED" == "true" ]]; then
    if [[ -e "${file_path}.bak" || -L "${file_path}.bak" ]]; then
      error_echo "备份已存在，保留原文件：${file_path}.bak"
      return 2
    fi
    if ! cp -p -n -- "$file_path" "${file_path}.bak" || ! cmp -s -- "$file_path" "${file_path}.bak"; then
      error_echo "备份失败，未替换：$file_path"
      return 2
    fi
  fi
  # 先完整写好同目录副本；Perl -i 的部分 IO 警告不会返回失败，不能用作成功依据。
  temporary_file="$(umask 077; mktemp "${file_path:h}/.jobs-replace.XXXXXXXX")" || {
    error_echo "无法创建替换临时文件，原文件保留：$file_path"
    return 2
  }
  if ! cp -p -- "$file_path" "$temporary_file" || ! cmp -s -- "$file_path" "$temporary_file"; then
    rm -f -- "$temporary_file"
    error_echo "临时副本创建失败，原文件保留：$file_path"
    return 2
  fi
  if ! SEARCH_TERM="$search_term" REPLACE_TERM="$replace_term" perl -e '
    use strict;
    use warnings;
    my ($file) = @ARGV;
    open my $stream, "+<:raw", $file or die "打开替换副本失败: $!\n";
    my $text = "";
    while (1) {
      my $count = read($stream, my $chunk, 65536);
      defined $count or die "读取替换副本失败: $!\n";
      last if $count == 0;
      $text .= $chunk;
    }
    my ($search, $replace) = @ENV{"SEARCH_TERM", "REPLACE_TERM"};
    my $matches = ($text =~ s/\Q$search\E/$replace/g);
    $matches or die "副本中没有搜索文本，停止替换\n";
    seek($stream, 0, 0) or die "定位写入失败: $!\n";
    print {$stream} $text or die "写入替换副本失败: $!\n";
    truncate($stream, length($text)) or die "截断替换副本失败: $!\n";
    close $stream or die "关闭替换副本失败: $!\n";
  ' -- "$temporary_file"; then
    rm -f -- "$temporary_file"
    error_echo "替换失败，原文件保留：$file_path"
    return 2
  fi
  if ! mv -f -- "$temporary_file" "$file_path"; then
    rm -f -- "$temporary_file"
    error_echo "替换失败：$file_path"
    return 2
  fi
  success_echo "已替换：$file_path"
}
# 扫描目标。
replace_in_target() {
  local target_path="$1"
  local search_term="$2"
  local replace_term="$3"
  local count=0 failures=0 result=0
  local file_path inventory=""
  [[ -n "$search_term" ]] || { error_echo '搜索文本不能为空。'; return 1; }
  [[ ! -L "$target_path" ]] || { error_echo "拒绝符号链接目标：$target_path"; return 1; }

  if [[ -f "$target_path" ]]; then
    replace_in_file "$target_path" "$search_term" "$replace_term"
    result=$?
    (( result == 0 )) && count=$((count + 1))
    (( result > 1 )) && failures=$((failures + 1))
  elif [[ -d "$target_path" ]]; then
    inventory="$(umask 077; mktemp "${TMPDIR:-/tmp}/${SCRIPT_BASENAME}.scan.XXXXXXXX")" || return 1
    if ! find "$target_path" \
      -type d \( -name .git -o -name node_modules -o -name Pods -o -name .dart_tool \
      -o -name build -o -name dist -o -name .build -o -name DerivedData -o -name PodsManual \
      -o -name 'ManualBy*Pods@Pods' -o -name .venv -o -name venv -o -name __pycache__ \
      -o -name .next -o -name vendor -o -name vendors -o -name Vendor -o -name Vendors \
      -o -name ThirdParty -o -name third_party -o -name third-party \) -prune -o \
      -type f ! -name '*.bak' -print0 > "$inventory"; then
      rm -f -- "$inventory"
      error_echo "扫描失败，未执行替换：$target_path"
      return 1
    fi
    while IFS= read -r -d '' file_path; do
      replace_in_file "$file_path" "$search_term" "$replace_term"
      result=$?
      (( result == 0 )) && count=$((count + 1))
      (( result > 1 )) && failures=$((failures + 1))
    done < "$inventory"
    rm -f -- "$inventory"
  else
    error_echo "目标路径不存在：$target_path"
    return 1
  fi

  info_echo "成功替换文件数：$count；失败数：$failures"
  (( failures == 0 ))
}
# 执行入口下沉后的完整业务流程和控制逻辑。
run_main_business_flow() {
  # 收集用户输入，供后续业务判断使用。
  local search_term="" replace_term="" raw_path="" backup_result=0
  BACKUP_ENABLED="false"
  IFS= read -r "?请输入要搜索的文本：" search_term || return 1
  # 执行当前流程中的独立业务步骤：处理当前语句。
  [[ -z "$search_term" ]] && { error_echo "搜索文本不能为空。"; pause_to_exit; exit 1; }

  # 收集用户输入，供后续业务判断使用。
  IFS= read -r "?请输入替换后的文本：" replace_term || return 1
  # 收集用户输入，供后续业务判断使用。
  IFS= read -r "?请拖入目标文件或目录：" raw_path || return 1
  # 初始化当前流程后续步骤需要使用的变量。
  local target_path="$(strip_outer_quotes "$raw_path")"

  # 根据当前条件选择对应的执行分支。
  ask_any_to_run "是否在替换前为命中文件生成 .bak 备份"
  backup_result=$?
  if (( backup_result == 0 )); then
    BACKUP_ENABLED="true"
  elif (( backup_result > 1 )); then
    error_echo "输入结束，未执行替换。"
    return 1
  fi

  # 执行当前流程中的独立业务步骤：replace_in_target。
  replace_in_target "$target_path" "$search_term" "$replace_term" || return 1
  # 输出当前流程的完成状态、摘要和日志位置。
  success_echo "处理完成。"
  # 执行当前流程中的独立业务步骤：pause_to_exit。
  pause_to_exit
  return 0
}
# 编排脚本的高层业务流程。
# 初始化脚本运行环境，并集中承载原有的顶层执行逻辑。
initialize_script_runtime() {
  setopt NO_NOMATCH
  LOG_FILE="$(umask 077; mktemp "${TMPDIR:-/tmp}/${SCRIPT_BASENAME}.log.XXXXXXXX")" || exit 1
  info_echo "日志文件：$LOG_FILE"
}
# 编排脚本的高层业务流程。
main() {
  show_script_intro_and_wait # 展示用途并完成交互确认。
  initialize_script_runtime # 准备独立日志和 Shell 选项。
  run_main_business_flow "$@" # 收集输入，执行替换并传播失败。
}

main "$@"
