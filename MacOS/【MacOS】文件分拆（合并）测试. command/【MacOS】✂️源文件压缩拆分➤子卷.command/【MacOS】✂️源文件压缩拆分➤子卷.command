#!/bin/zsh
# 脚本自述：
# - 脚本名称：Jobs 文件拆分（运行时按当前文件名显示）。
# - 核心用途：拖入单文件或目录，按上限拆成可由 Jobs 合并工具还原的分卷。
# - 影响范围：只新增分卷目录；校验成功后精确输入 YES 才删除源文件。
# - 运行提示：先确认自述，再检查系统工具和 fzf；不安装软件或修改 Shell 配置。

SCRIPT_VERSION="2026.10.28"
SCRIPT_SOURCE_PATH="$0"
SCRIPT_DIR=""
SCRIPT_PATH=""
SCRIPT_BASENAME=""
LOG_FILE=""
TARGET_DIR=""
TARGET_FILE=""
MAX_CHUNK_BYTES=$((50 * 1024 * 1024))
MAX_CHUNK_LABEL="50 MiB"
STANDARD_QUERY=""
FILE_QUERY=""
REPLY=""
FZF_LINES=()
LARGE_FILES=()
SELECTED_FILES=()
ACTIVE_STAGING_DIR=""

# 在自述之前只解析脚本位置，不创建日志或修改目标。
prepare_display() {
  SCRIPT_PATH="${SCRIPT_SOURCE_PATH:A}"
  SCRIPT_DIR="${SCRIPT_PATH:h}"
  SCRIPT_BASENAME="${SCRIPT_PATH:t:r}"
  LOG_FILE="${TMPDIR:-/tmp}/${SCRIPT_BASENAME}.log"
}

# 按终端能力显示自述，日志始终保留可搜索的纯文本。
print_styled() {
  local style="$1" message="$2"
  if [[ -t 1 && -n "${TERM:-}" && "${TERM:-}" != dumb && -z "${NO_COLOR+x}" ]]; then
    printf '\033[%sm%s\033[0m\n' "$style" "$message"
  else
    printf '%s\n' "$message"
  fi
}
# 同步显示业务信息和纯文本日志。
log() {
  local message="$1"
  print_styled "${2:-0}" "$message"
  [[ "${LOG_READY:-0}" != 1 ]] || printf '%s\n' "$message" >> "$LOG_FILE"
}
# 以信息级别记录当前处理状态。
info_echo() {
  log "ℹ $1" '1;34'
}
# 以成功级别记录已验证的操作结果。
success_echo() {
  log "✔ $1" '1;32'
}
# 以警告级别记录取消、跳过或需关注的状态。
warn_echo() {
  log "⚠ $1" '1;33'
}
# 以错误级别记录失败对象与原因。
error_echo() {
  log "✖ $1" '1;31'
}
# 第一屏说明影响范围，确认之前不创建日志或写入目标。
show_script_intro_and_wait() {
  prepare_display
  print_styled '1;31' "======== Jobs 文件拆分（${SCRIPT_PATH:t}）========"
  print_styled '0;34' "工具版本：$SCRIPT_VERSION"
  print_styled '0;34' '1、拖入单文件或目录，或用一个位置参数指定；目录模式不递归子目录。'
  print_styled '0;34' '2、分卷上限：50 MiB、100 MiB、1900 MiB 或自定义 MiB。'
  print_styled '0;34' '3、先在独占临时目录生成分卷，大小和 SHA-256 校验成功后发布。'
  print_styled '0;34' '4、已有分卷目录不覆盖；删除源文件必须精确输入 YES，回车保留。'
  print_styled '0;34' '5、仅检查系统工具与 fzf，不安装或升级软件，不修改 Shell 配置。'
  print_styled '0;34' "日志：${LOG_FILE}；Ctrl+C 可取消。"
  if [[ ! -t 0 ]]; then
    print_styled '1;31' '✖ 缺少可交互输入，请在终端中运行。'
    exit 1
  fi
  printf '➤ 按 [Enter] 继续，或 Ctrl+C 退出：'
  IFS= read -r REPLY || exit 1
}
# 确认后初始化运行选项、相对定位和日志。
initialize_runtime() {
  setopt NO_NOMATCH ERR_EXIT PIPE_FAIL
  SCRIPT_PATH="${SCRIPT_SOURCE_PATH:A}"
  SCRIPT_DIR="${SCRIPT_PATH:h}"
  : > "$LOG_FILE"
  LOG_READY=1
  trap 'handle_interruption INT' INT
  trap 'handle_interruption TERM' TERM
}
# 取消时保留独占临时目录，显示恢复排查所需的位置。
handle_interruption() {
  warn_echo "收到 $1，已停止拆分；源文件保留。"
  [[ -z "$ACTIVE_STAGING_DIR" ]] || warn_echo "临时结果保留：$ACTIVE_STAGING_DIR"
  [[ "$1" == INT ]] && exit 130
  exit 143
}
# 验证真实执行所需工具及当前 fzf 选项，不触发安装或升级。
check_environment() {
  local executable probe_rc=0
  for executable in /usr/bin/split /usr/bin/stat /usr/bin/shasum /usr/bin/find /usr/bin/mktemp /bin/cat /bin/mv /usr/bin/osascript; do
    if [[ ! -x "$executable" ]]; then
      error_echo "系统工具不可用：$executable"
      exit 1
    fi
  done
  if ! command -v fzf >/dev/null 2>&1 || ! fzf --version >/dev/null 2>&1; then
    error_echo 'fzf 缺失或损坏；请先安装或修复 fzf 后重试。'
    exit 1
  fi
  printf '' | FZF_DEFAULT_OPTS='' FZF_DEFAULT_OPTS_FILE='' fzf --filter='' --multi --print-query --expect=left \
    --header='' --footer='' --bind='enter:toggle,ctrl-a:select-all,ctrl-d:deselect-all,space:transform:if [ "${FZF_SELECT_COUNT:-0}" -gt 0 ]; then echo accept; else echo abort; fi' \
    >/dev/null 2>> "$LOG_FILE" || probe_rc=$?
  if (( probe_rc > 1 )); then
    error_echo '当前 fzf 不支持所需选项，请更新 fzf 后重试。'
    exit 1
  fi
  info_echo "环境检查完成；日志：$LOG_FILE"
}
# 原路径优先，再安全解析拖入引用和转义；不执行输入中的任何代码。
normalize_target_input() {
  local candidate="$1"
  local -a tokens=()
  REPLY=''
  if [[ ( -d "$candidate" || -f "$candidate" ) && ! -L "$candidate" ]]; then
    REPLY="${candidate:A}"
    return 0
  fi
  while [[ "$candidate" == [\ $'\t\r\n\u00a0\u3000']* ]]; do
    candidate="${candidate[2,-1]}"
  done
  while [[ "$candidate" == *[\ $'\t\r\n\u00a0\u3000'] ]]; do
    candidate="${candidate[1,-2]}"
  done
  [[ -n "$candidate" ]] || { REPLY="$SCRIPT_DIR"; return 0; }
  if [[ ( -d "$candidate" || -f "$candidate" ) && ! -L "$candidate" ]]; then
    REPLY="${candidate:A}"
    return 0
  fi
  tokens=("${(@z)candidate}")
  (( ${#tokens} == 1 )) || return 1
  candidate="${(Q)tokens[1]}"
  [[ "$candidate" != '~/'* ]] || candidate="${HOME}/${candidate#'~/'}"
  [[ ( -d "$candidate" || -f "$candidate" ) && ! -L "$candidate" ]] || return 1
  REPLY="${candidate:A}"
}
# 接收一个目标目录，空输入默认使用脚本所在目录。
choose_target_directory() {
  local input=''
  (( $# <= 1 )) || { error_echo '只接受一个单文件或目录位置参数。'; return 1; }
  while true; do
    if (( $# == 1 )); then
      input="$1"
    else
      log "➤ 拖入单文件或目录；直接回车使用：$SCRIPT_DIR"
      IFS= read -r input || return 1
    fi
    if normalize_target_input "$input"; then
      if [[ -f "$REPLY" ]]; then
        TARGET_FILE="$REPLY"
        TARGET_DIR="${REPLY:h}"
        info_echo "单文件模式：$TARGET_FILE；分卷生成在源文件同级的新目录。"
      else
        TARGET_FILE=''
        TARGET_DIR="$REPLY"
        info_echo "目录模式：$TARGET_DIR；仅处理随后明确勾选的文件。"
      fi
      return 0
    fi
    error_echo '不是有效的普通单文件或目录；支持引号、拖入转义和尾随空白，不接受符号链接。'
    (( $# == 0 )) || return 1
  done
}
# 目标输入失败时立即停止，避免随后扫描默认目录。
require_target_directory() {
  if ! choose_target_directory "$@"; then
    exit 1
  fi
}
# 保留 fzf 空查询和空按键行，以区分返回、空选与选择器失败。
parse_fzf_output() {
  local output="$1" line=''
  FZF_LINES=()
  while IFS= read -r line; do
    FZF_LINES+=("$line")
  done <<< "$output"
}
# 验证 MiB 输入并转换成至少一个字节的整数上限。
set_custom_limit() {
  local custom_mb='' answer='' bytes=''
  while true; do
    log '➤ 输入自定义上限（MiB，可带小数）；直接回车返回标准选择：'
    IFS= read -r custom_mb || return 2
    [[ -n "$custom_mb" ]] || return 3
    if [[ ! "$custom_mb" =~ '^[0-9]+([.][0-9]+)?$' ]]; then
      warn_echo '请输入大于 0 的数字。'
      continue
    fi
    bytes="$(/usr/bin/awk -v mb="$custom_mb" 'BEGIN { n = mb * 1048576; if (n >= 1 && n <= 9007199254740991) printf "%.0f", int(n) }')"
    if [[ -z "$bytes" ]]; then
      warn_echo '上限必须至少为 1 字节，且不能超过可精确表示的范围。'
      continue
    fi
    log "➤ 分卷上限：${custom_mb} MiB（${bytes} 字节）；回车确认，任意字符重新输入："
    IFS= read -r answer || return 2
    if [[ -z "$answer" ]]; then
      MAX_CHUNK_BYTES="$bytes"
      MAX_CHUNK_LABEL="${custom_mb} MiB"
      return 0
    fi
  done
}
# 通过根层 fzf 选择上限，取消时不形成执行计划。
choose_split_standard() {
  local output='' choice='' selection_rc=0 custom_rc=0
  while true; do
    selection_rc=0
    output="$(printf '%s\n' '50MiB|50 MiB（默认）' '100MiB|100 MiB' '1900MiB|1900 MiB' 'CUSTOM|自定义 MiB' | \
      FZF_DEFAULT_OPTS='' FZF_DEFAULT_OPTS_FILE='' fzf --no-multi --print-query --query="$STANDARD_QUERY" \
        --height=12 --layout=reverse --border --delimiter='|' --with-nth=2 \
        --header='Enter 确认；Esc 取消' --footer='Enter 确认；Esc 取消' --prompt='分卷上限 > ')" || selection_rc=$?
    parse_fzf_output "$output"
    STANDARD_QUERY="${FZF_LINES[1]:-}"
    if (( selection_rc == 130 || selection_rc == 1 )); then
      return 2
    fi
    if (( selection_rc != 0 )); then
      error_echo "fzf 标准选择失败（退出码 $selection_rc）。"
      return 1
    fi
    choice="${FZF_LINES[2]%%|*}"
    case "$choice" in
      50MiB) MAX_CHUNK_BYTES=$((50 * 1024 * 1024)); MAX_CHUNK_LABEL='50 MiB' ;;
      100MiB) MAX_CHUNK_BYTES=$((100 * 1024 * 1024)); MAX_CHUNK_LABEL='100 MiB' ;;
      1900MiB) MAX_CHUNK_BYTES=$((1900 * 1024 * 1024)); MAX_CHUNK_LABEL='1900 MiB' ;;
      CUSTOM)
        custom_rc=0
        set_custom_limit || custom_rc=$?
        (( custom_rc == 3 )) && continue
        (( custom_rc == 0 )) || return "$custom_rc"
        ;;
      *) error_echo 'fzf 返回了无法识别的标准。'; return 1 ;;
    esac
    info_echo "分卷上限：$MAX_CHUNK_LABEL（$MAX_CHUNK_BYTES 字节）"
    return 0
  done
}
# 仅扫描目标目录的普通大文件，避免再次拆分已有分卷。
find_large_files() {
  local file='' size=0 filename=''
  LARGE_FILES=()
  if [[ -n "$TARGET_FILE" ]]; then
    [[ -f "$TARGET_FILE" && ! -L "$TARGET_FILE" ]] || { error_echo '指定文件已失效。'; return 1; }
    size="$(/usr/bin/stat -f %z "$TARGET_FILE")" || return 1
    if (( size > MAX_CHUNK_BYTES )); then
      LARGE_FILES=("$TARGET_FILE")
      return 0
    fi
    info_echo "指定文件未超过 $MAX_CHUNK_LABEL；可返回调低上限。"
    return 2
  fi
  while IFS= read -r -d '' file; do
    filename="${file:t}"
    [[ "$filename" == .* ]] && continue
    [[ "$filename" =~ '@[0-9]+of[0-9]+$' ]] && continue
    size="$(/usr/bin/stat -f %z "$file")" || return 1
    (( size > MAX_CHUNK_BYTES )) && LARGE_FILES+=("$file")
  done < <(/usr/bin/find "$TARGET_DIR" -mindepth 1 -maxdepth 1 -type f -print0)
  if (( ${#LARGE_FILES} == 0 )); then
    info_echo "没有超过 $MAX_CHUNK_LABEL 的普通文件。"
    return 2
  fi
  LARGE_FILES=("${(@on)LARGE_FILES}")
}
# 无大文件时保留返回上限选择的入口，方便调低阈值。
select_empty_files_action() {
  local output='' selection_rc=0
  output="$(printf '%s\n' 'RETURN|重新选择分卷上限' 'CANCEL|结束' | \
    FZF_DEFAULT_OPTS='' FZF_DEFAULT_OPTS_FILE='' fzf --no-multi --print-query --expect=left \
      --height=12 --layout=reverse --border --delimiter='|' --with-nth=2 \
      --header='没有符合条件的文件；← 返回标准；Enter 确认；Esc 取消' \
      --footer='← 返回标准；Enter 确认；Esc 取消' --prompt='无待拆分文件 > ')" || selection_rc=$?
  parse_fzf_output "$output"
  [[ "${FZF_LINES[2]:-}" == left ]] && return 3
  (( selection_rc == 130 || selection_rc == 1 )) && return 2
  if (( selection_rc != 0 )); then
    error_echo "fzf 无数据选择失败（退出码 $selection_rc）。"
    return 1
  fi
  [[ "${FZF_LINES[3]%%|*}" == RETURN ]] && return 3
  return 2
}
# 通过多选面板形成计划，左方向键返回标准，空选不会选中高亮项。
select_large_files() {
  local output='' selection_rc=0 row='' id='' i=1
  local -a rows=()
  SELECTED_FILES=()
  for row in "${LARGE_FILES[@]}"; do
    rows+=("${i}"$'\t'"${(q)row:t}")
    (( i += 1 ))
  done
  local hints='Enter 勾选/取消；Space 确认；Ctrl+A 全选；Ctrl+D 清空；← 返回标准；Esc 取消'
  output="$(printf '%s\n' "${rows[@]}" | FZF_DEFAULT_OPTS='' FZF_DEFAULT_OPTS_FILE='' fzf \
    --multi --print-query --expect=left --query="$FILE_QUERY" --height=80% --layout=reverse --border \
    --delimiter=$'\t' --with-nth=2.. --header="$hints" --footer="$hints" --prompt='待拆分文件 > ' \
    --bind='enter:toggle,ctrl-a:select-all,ctrl-d:deselect-all,space:transform:if [ "${FZF_SELECT_COUNT:-0}" -gt 0 ]; then echo accept; else echo abort; fi')" || selection_rc=$?
  parse_fzf_output "$output"
  FILE_QUERY="${FZF_LINES[1]:-}"
  [[ "${FZF_LINES[2]:-}" == left ]] && return 3
  if (( selection_rc == 130 || selection_rc == 1 )); then
    return 2
  fi
  if (( selection_rc != 0 )); then
    error_echo "fzf 文件选择失败（退出码 $selection_rc）。"
    return 1
  fi
  for row in "${FZF_LINES[@]:2}"; do
    [[ -n "$row" ]] || continue
    id="${row%%$'\t'*}"
    if [[ "$id" != <-> ]] || (( id < 1 || id > ${#LARGE_FILES} )); then
      error_echo 'fzf 返回了无效的文件编号。'
      return 1
    fi
    SELECTED_FILES+=("${LARGE_FILES[id]}")
  done
  (( ${#SELECTED_FILES} > 0 )) || return 2
}
# 读取源文件摘要，不依赖文件名输出格式。
file_sha256() {
  /usr/bin/shasum -a 256 < "$1" | /usr/bin/awk '{ print $1 }'
}
# 串联分卷内容，为校验提供恒定内存的输入流。
stream_parts() {
  local part=''
  for part in "$@"; do
    /bin/cat "$part" || return 1
  done
}
# 校验完成后仅接受精确 YES 删除源文件，其它输入和 EOF 均保留。
confirm_delete_source() {
  local source_file="$1" expected_hash="$2" expected_identity="${3:-}" answer='' current_hash='' current_identity=''
  log "➤ 是否删除源文件：$source_file"
  log '危险操作：只有输入 YES 后回车才删除；直接回车、其它输入或输入结束均保留。'
  IFS= read -r answer || answer=''
  if [[ "$answer" != YES ]]; then
    info_echo "已保留源文件：$source_file"
    return 0
  fi
  if [[ ! -f "$source_file" || -L "$source_file" ]]; then
    error_echo "源文件已被替换或不再是普通文件，拒绝删除：$source_file"
    return 1
  fi
  current_identity="$(/usr/bin/stat -f '%d:%i' "$source_file")" || return 1
  if [[ -n "$expected_identity" && "$current_identity" != "$expected_identity" ]]; then
    error_echo "源文件身份发生变化，拒绝删除：$source_file"
    return 1
  fi
  current_hash="$(file_sha256 "$source_file")" || return 1
  if [[ "$current_hash" != "$expected_hash" ]]; then
    error_echo "源文件已变化，拒绝删除：$source_file"
    return 1
  fi
  if /bin/rm -f -- "$source_file"; then
    success_echo "已删除源文件：$source_file"
  else
    error_echo "删除源文件失败：$source_file"
    return 1
  fi
}
# 以系统排他重命名发布整个目录，目标并发出现时失败，不套入已有目录。
publish_directory_exclusively() {
  /usr/bin/osascript -l JavaScript - "$1" "$2" <<'JOBS_RENAME'
ObjC.import('Foundation');
ObjC.bindFunction('renamex_np', ['int', ['char *', 'char *', 'unsigned int']]);
ObjC.bindFunction('__error', ['int *', []]);
ObjC.bindFunction('strerror', ['char *', ['int']]);
function run(args) {
  if ($.renamex_np(args[0], args[1], 4) !== 0) {
    var code = $.__error()[0];
    throw new Error('排他发布失败（' + code + '）：' + $.strerror(code));
  }
}
JOBS_RENAME
}

# 在独占临时目录拆分并验证，完整目录只在校验通过后发布一次。
split_one_file() {
  local file="$1" filename="${1:t}" parent_dir="${1:h}" base_no_ext='' output_dir=''
  local file_size=0 planned_count=0 chunk_size=0 suffix_width=1 capacity=26 actual_count=0
  local staging_dir='' part='' renamed_part='' source_hash='' parts_hash='' final_hash='' source_identity=''
  local total_bytes=0 part_size=0 index=1 width=1 index_padded='' total_padded=''
  local -a parts=() published_parts=()
  [[ -f "$file" && ! -L "$file" ]] || { error_echo "不是普通源文件：$file"; return 1; }
  file_size="$(/usr/bin/stat -f %z "$file")" || return 1
  if (( file_size <= MAX_CHUNK_BYTES || file_size == 0 )); then
    info_echo "文件未超过分卷上限，跳过：$file"
    return 0
  fi
  base_no_ext="${filename%.*}"
  [[ -n "$base_no_ext" ]] || base_no_ext="$filename"
  output_dir="${parent_dir}/${base_no_ext}"
  [[ "$base_no_ext" == "$filename" ]] && output_dir="${file}.parts"
  if [[ -e "$output_dir" || -L "$output_dir" ]]; then
    error_echo "分卷目标已存在，拒绝覆盖：$output_dir"
    return 1
  fi
  planned_count=$(( 1 + (file_size - 1) / MAX_CHUNK_BYTES ))
  chunk_size=$(( 1 + (file_size - 1) / planned_count ))
  actual_count=$(( 1 + (file_size - 1) / chunk_size ))
  while (( capacity < actual_count )); do
    (( suffix_width += 1 ))
    (( capacity *= 26 ))
  done
  staging_dir="$(/usr/bin/mktemp -d "${parent_dir}/.split.XXXXXXXX")" || return 1
  ACTIVE_STAGING_DIR="$staging_dir"
  info_echo "临时结果（失败或中断时保留）：$staging_dir"
  info_echo "来源：$file"
  info_echo "目标：$output_dir；上限 $MAX_CHUNK_BYTES 字节；计划 $actual_count 卷，主卷 $chunk_size 字节。"
  source_identity="$(/usr/bin/stat -f '%d:%i' "$file")" || return 1
  source_hash="$(file_sha256 "$file")" || return 1
  if ! /usr/bin/split -b "$chunk_size" -a "$suffix_width" "$file" "${staging_dir}/part_" 2>> "$LOG_FILE"; then
    error_echo "split 执行失败；保留源文件和临时结果：$staging_dir"
    return 1
  fi
  while IFS= read -r -d '' part; do
    parts+=("$part")
  done < <(/usr/bin/find "$staging_dir" -mindepth 1 -maxdepth 1 -type f -print0)
  parts=("${(@o)parts}")
  if (( ${#parts} != actual_count )); then
    error_echo "分卷数量不符；保留临时结果：$staging_dir"
    return 1
  fi
  for part in "${parts[@]}"; do
    part_size="$(/usr/bin/stat -f %z "$part")" || return 1
    if (( part_size < 1 || part_size > MAX_CHUNK_BYTES )); then
      error_echo "分卷大小超出上限或为空：$part"
      return 1
    fi
    (( total_bytes += part_size ))
  done
  parts_hash="$(stream_parts "${parts[@]}" | /usr/bin/shasum -a 256 | /usr/bin/awk '{ print $1 }')" || return 1
  final_hash="$(file_sha256 "$file")" || return 1
  if (( total_bytes != file_size )) || [[ "$source_hash" != "$parts_hash" || "$source_hash" != "$final_hash" ]]; then
    error_echo "大小或 SHA-256 校验失败；保留源文件和临时结果：$staging_dir"
    return 1
  fi
  width="${#actual_count}"
  printf -v total_padded "%0${width}d" "$actual_count"
  for part in "${parts[@]}"; do
    printf -v index_padded "%0${width}d" "$index"
    renamed_part="${staging_dir}/${filename}@${index_padded}of${total_padded}"
    if ! /bin/mv -n "$part" "$renamed_part"; then
      error_echo "分卷命名失败；保留临时结果：$staging_dir"
      return 1
    fi
    published_parts+=("${output_dir}/${filename}@${index_padded}of${total_padded}")
    (( index += 1 ))
  done
  if [[ -e "$output_dir" || -L "$output_dir" ]]; then
    error_echo "发布前发现目标已存在；保留临时结果：$staging_dir"
    return 1
  fi
  if ! publish_directory_exclusively "$staging_dir" "$output_dir" 2>> "$LOG_FILE"; then
    error_echo "分卷发布失败；保留临时结果：$staging_dir"
    return 1
  fi
  if [[ -d "${output_dir}/${staging_dir:t}" ]]; then
    ACTIVE_STAGING_DIR="${output_dir}/${staging_dir:t}"
  else
    ACTIVE_STAGING_DIR="$output_dir"
  fi
  parts=()
  while IFS= read -r -d '' part; do
    parts+=("$part")
  done < <(/usr/bin/find "$output_dir" -mindepth 1 -maxdepth 1 -type f -print0)
  if [[ -L "$output_dir" ]] || (( ${#parts} != actual_count )); then
    error_echo "发布目录清单不符，拒绝删除源文件；结果：$ACTIVE_STAGING_DIR"
    return 1
  fi
  for part in "${published_parts[@]}"; do
    if [[ ! -f "$part" || -L "$part" ]]; then
      error_echo "发布分卷未位于目标根部，拒绝删除源文件；结果：$ACTIVE_STAGING_DIR"
      return 1
    fi
  done
  parts_hash="$(stream_parts "${published_parts[@]}" | /usr/bin/shasum -a 256 | /usr/bin/awk '{ print $1 }')" || return 1
  if [[ "$parts_hash" != "$source_hash" ]]; then
    error_echo "发布后 SHA-256 校验失败；保留源文件和结果：$ACTIVE_STAGING_DIR"
    return 1
  fi
  ACTIVE_STAGING_DIR=''
  success_echo "已拆分并通过 SHA-256 校验：$output_dir（$actual_count 卷）"
  confirm_delete_source "$file" "$source_hash" "$source_identity"
}
# 顺序执行已确认计划，单项失败仍汇总真实失败状态。
run_selected_files() {
  local file='' failures=0
  info_echo "待拆分文件：${#SELECTED_FILES} 个。"
  for file in "${SELECTED_FILES[@]}"; do
    ACTIVE_STAGING_DIR=''
    if ! split_one_file "$file"; then
      [[ -z "$ACTIVE_STAGING_DIR" ]] || warn_echo "保留待排查结果：$ACTIVE_STAGING_DIR"
      (( failures += 1 ))
    fi
  done
  if (( failures > 0 )); then
    error_echo "拆分流程结束，失败 $failures 项；日志：$LOG_FILE"
    return 1
  fi
  success_echo "拆分流程结束；日志：$LOG_FILE"
}
# 循环编排标准和文件选择，返回动作只改变计划，不执行拆分。
plan_and_split() {
  local selection_rc=0
  while true; do
    selection_rc=0
    choose_split_standard || selection_rc=$?
    if (( selection_rc == 2 )); then
      info_echo '已取消标准选择。'
      return 0
    fi
    (( selection_rc == 0 )) || return 1
    selection_rc=0
    find_large_files || selection_rc=$?
    if (( selection_rc == 2 )); then
      selection_rc=0
      select_empty_files_action || selection_rc=$?
      (( selection_rc == 3 )) && continue
      (( selection_rc == 2 )) && return 0
      return 1
    fi
    (( selection_rc == 0 )) || return 1
    if [[ -n "$TARGET_FILE" ]]; then
      SELECTED_FILES=("$TARGET_FILE")
      run_selected_files
      return $?
    fi
    selection_rc=0
    select_large_files || selection_rc=$?
    (( selection_rc == 3 )) && continue
    if (( selection_rc == 2 )); then
      info_echo '未勾选文件或已取消，未执行拆分。'
      return 0
    fi
    (( selection_rc == 0 )) || return 1
    run_selected_files
    return $?
  done
}
# 编排自述、只读检查、路径输入和分卷执行。
main() {
  show_script_intro_and_wait # 首先显示用途与影响范围，回车确认后继续。
  initialize_runtime # 确认后初始化日志、脚本定位和运行选项。
  check_environment # 验证系统工具及 fzf，缺失时安全停止。
  require_target_directory "$@" # 接收单文件、目录或位置参数。
  plan_and_split # 先完成可返回的选择，再拆分并校验已选文件。
}

main "$@"
