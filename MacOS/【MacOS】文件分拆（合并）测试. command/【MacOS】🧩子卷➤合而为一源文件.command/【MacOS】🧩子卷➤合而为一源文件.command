#!/bin/zsh
# 脚本自述：
# - 脚本名称：Jobs 子卷合并（运行时按当前文件名显示）。
# - 核心用途：识别当前目录及一级子目录的 文件名@序号of总数，逐组校验并按数字顺序合并。
# - 影响范围：在目标目录发布完整文件；已有文件不覆盖，仅输入 YES 才删除本组分卷。
# - 运行提示：先阅读内置自述并回车；依赖只检查，不安装或升级；Ctrl+C 随时停止。

SCRIPT_VERSION="2026.10.28"
SCRIPT_SOURCE_PATH="$0"
SCRIPT_DIR=""
SCRIPT_PATH=""
SCRIPT_BASENAME=""
LOG_FILE=""
TARGET_DIR=""
TARGET_EXPLICIT=0
TARGET_IS_VOLUME_DIR=0
USE_COLOR=0
NORMALIZED_DIR=""
PARSED_NAME=""
PARSED_INDEX=0
PARSED_TOTAL=0
GROUP_DIRS=()
GROUP_NAMES=()
SELECTED_GROUPS=()
CHUNKS=()
CHUNK_STATES=()
GROUP_BYTES=0
ACTIVE_TEMP=""
# 准备自述需要的路径和颜色，不写文件或改变工作目录。
prepare_display() {
  SCRIPT_PATH="${SCRIPT_SOURCE_PATH:A}"
  SCRIPT_DIR="${SCRIPT_PATH:h}"
  SCRIPT_BASENAME="${SCRIPT_PATH:t:r}"
  LOG_FILE="${TMPDIR:-/tmp}/${SCRIPT_BASENAME}.log"
  if [[ -t 1 && -n "${TERM:-}" && "${TERM:-}" != dumb && -z "${NO_COLOR+x}" ]]; then
    USE_COLOR=1
  fi
}
# 打印说明，日志始终保留纯文本。
message() {
  local text="$1" tone="${2:-34}"
  if (( USE_COLOR )); then
    printf '\033[%sm%s\033[0m\n' "$tone" "$text"
  else
    print -r -- "$text"
  fi
  if [[ "${LOG_READY:-0}" == 1 ]]; then
    print -r -- "$text" >> "$LOG_FILE"
  fi
}
# 首屏展示用途与删除边界，确认前不进行真实业务。
show_script_intro_and_wait() {
  prepare_display
  message "======== Jobs 子卷合并（${SCRIPT_PATH:t}）========" '1;31'
  message "工具版本：$SCRIPT_VERSION" '0;34'
  message '1、拖入目录或用一个位置参数指定；扫描本层与一级子目录，兼容平铺及分卷目录。' '0;34'
  message '2、按完整原文件名分组，检查总数、重复及缺号；按数字卷号合并，兼容补零编号。' '0;34'
  message '3、显式指定分卷目录时在父目录还原；扫描父目录或默认目录时在该目录输出。' '0;34'
  message '4、默认保留分卷；只有精确输入 YES 才删除本组分卷，不递归删除目录。' '0;34'
  message '5、只检查本机 fzf 和系统命令，不安装、不升级、不修改 Shell 配置。' '0;34'
  message "日志：${LOG_FILE}；按 Ctrl+C 退出。" '0;34'
  if [[ ! -t 0 ]]; then
    message '✖ 缺少交互终端，请在 Terminal 中运行。' '1;31'
    exit 1
  fi
  print -n -r -- '➤ 按 [Enter] 继续，或 Ctrl+C 退出：'
  IFS= read -r _ || exit 1
}
# 在用户确认后初始化日志与中断处理。
initialize_runtime() {
  setopt NO_NOMATCH PIPE_FAIL
  umask 077
  : > "$LOG_FILE" || exit 1
  LOG_READY=1
  trap 'report_interruption; exit 130' INT
  trap 'report_interruption; exit 143' TERM
}
# 中断时保留候选，不把残缺结果发布为完整文件。
report_interruption() {
  message '⚠ 已中止；原有文件及未确认删除的分卷保留。' '1;33'
  [[ -z "$ACTIVE_TEMP" ]] || message "⚠ 未发布的候选：$ACTIVE_TEMP" '1;33'
}
# 检查本机工具和实际使用的选择器选项，不写入环境。
check_environment() {
  local utility
  for utility in fzf find stat cat tee shasum mktemp link rm rmdir; do
    if ! command -v "$utility" >/dev/null 2>&1; then
      message "✖ 缺少命令：$utility。fzf 可手动运行 brew install fzf 安装。" '1;31'
      exit 1
    fi
  done
  if ! fzf --version >/dev/null 2>&1 || ! printf 'check\n' | FZF_DEFAULT_OPTS= FZF_DEFAULT_OPTS_FILE= fzf \
    --filter=check --multi --footer='检查' --bind='space:transform:echo abort' >/dev/null 2>&1; then
    message '✖ fzf 不可用或不支持 footer / transform，请手动修复后重试。' '1;31'
    exit 1
  fi
}
# 优先保留真实目录名，仅在原输入无效时去除拖入产生的边缘空白。
normalize_directory_input() {
  local candidate="$1"
  local -a words
  NORMALIZED_DIR=""
  if [[ -d "$candidate" ]]; then
    NORMALIZED_DIR="${candidate:A}"
    return 0
  fi
  while [[ "$candidate" == [[:space:]]* || "$candidate" == $'\u00a0'* || "$candidate" == $'\u3000'* ]]; do
    candidate="${candidate#?}"
  done
  while [[ "$candidate" == *[[:space:]] || "$candidate" == *$'\u00a0' || "$candidate" == *$'\u3000' ]]; do
    candidate="${candidate%?}"
  done
  if [[ -d "$candidate" ]]; then
    NORMALIZED_DIR="${candidate:A}"
    return 0
  fi
  # 只做词法去引号，不执行 eval、变量替换或命令替换。
  words=("${(@z)candidate}")
  (( ${#words} == 1 )) || return 1
  candidate="${(Q)words[1]}"
  if [[ "$candidate" == '~/'* ]]; then
    candidate="$HOME/${candidate#\~/}"
  fi
  [[ -d "$candidate" ]] || return 1
  NORMALIZED_DIR="${candidate:A}"
}
# 接收单个拖入目录，空行使用脚本目录，输入无效可重试。
choose_target_directory() {
  local input=""
  (( $# <= 1 )) || { message '✖ 只接受一个目录位置参数。' '1;31'; return 1; }
  while true; do
    if (( $# == 1 )); then
      input="$1"
    else
      message "➤ 拖入父目录或分卷目录；直接回车扫描脚本目录：$SCRIPT_DIR"
      IFS= read -r input || return 1
    fi
    if [[ -z "$input" ]]; then
      TARGET_DIR="$SCRIPT_DIR"
      TARGET_EXPLICIT=0
      break
    fi
    if normalize_directory_input "$input"; then
      TARGET_DIR="$NORMALIZED_DIR"
      TARGET_EXPLICIT=1
      break
    fi
    message '✖ 不是有效的单个目录；支持引号、拖入转义和尾随空白，请重新输入。' '1;31'
    (( $# == 0 )) || return 1
  done
  message "ℹ 扫描目录：$TARGET_DIR"
}
# 目标输入失败时立即停止，避免随后扫描默认目录。
require_target_directory() {
  if ! choose_target_directory "$@"; then
    exit 1
  fi
}
# 从最后一个合法后缀解析完整原文件名，保留名称中的 @。
parse_volume_name() {
  local filename="$1"
  if [[ "$filename" =~ '^(.+)@([0-9]+)of([0-9]+)$' ]]; then
    PARSED_NAME="$match[1]"
    (( ${#match[2]} <= 9 && ${#match[3]} <= 9 )) || return 1
    PARSED_INDEX=$(( 10#${match[2]} ))
    PARSED_TOTAL=$(( 10#${match[3]} ))
    [[ "$PARSED_NAME" != . && "$PARSED_NAME" != .. ]] || return 1
    return 0
  fi
  return 1
}
# 为一个目录内的每个原文件建立独立分卷组。
scan_volume_directory() {
  local dir="$1" file="" found=0 i
  while IFS= read -r -d '' file; do
    parse_volume_name "${file:t}" || continue
    found=0
    for (( i=1; i<=${#GROUP_NAMES}; i++ )); do
      if [[ "${GROUP_DIRS[i]}" == "$dir" && "${GROUP_NAMES[i]}" == "$PARSED_NAME" ]]; then
        found=1
        break
      fi
    done
    if (( ! found )); then
      GROUP_DIRS+=("$dir")
      GROUP_NAMES+=("$PARSED_NAME")
    fi
  done < <(find "$dir" -maxdepth 1 -type f -print0)
}
# 扫描平铺文件及一级普通子目录，跳过缓存和第三方目录。
find_volume_groups() {
  GROUP_DIRS=()
  GROUP_NAMES=()
  scan_volume_directory "$TARGET_DIR"
  TARGET_IS_VOLUME_DIR=0
  if (( TARGET_EXPLICIT && ${#GROUP_NAMES} > 0 )); then
    TARGET_IS_VOLUME_DIR=1
    message "ℹ 当前目录直接包含分卷，其本层组将还原到父目录：${TARGET_DIR:h}"
  fi
  local dir=""
  while IFS= read -r -d '' dir; do
    case "${dir:t}" in
      .*|node_modules|Pods|ManualBy*Pods@Pods|PodsManual|build|DerivedData) continue ;;
    esac
    scan_volume_directory "$dir"
  done < <(find "$TARGET_DIR" -mindepth 1 -maxdepth 1 -type d -print0)
  if (( ${#GROUP_NAMES} == 0 )); then
    message 'ℹ 未找到 文件名@序号of总数 格式的分卷；.partial 断点不参与合并。'
    exit 0
  fi
  message "ℹ 共检测到 ${#GROUP_NAMES} 组分卷。"
}
# 检查总数、索引唯一性和连续性，建立数值顺序。
validate_group() {
  local dir="$1" name="$2" file="" total=0 count=0 size=0 i index_key
  local -A indexed states
  CHUNKS=()
  CHUNK_STATES=()
  GROUP_BYTES=0
  while IFS= read -r -d '' file; do
    parse_volume_name "${file:t}" || continue
    [[ "$PARSED_NAME" == "$name" ]] || continue
    if (( PARSED_TOTAL < 1 || PARSED_INDEX < 1 || PARSED_INDEX > PARSED_TOTAL )); then
      message "✖ 非法卷号：$file" '1;31'
      return 1
    fi
    if (( total != 0 && total != PARSED_TOTAL )); then
      message "✖ 同组标记总卷数不一致：$name" '1;31'
      return 1
    fi
    total=$PARSED_TOTAL
    index_key="$PARSED_INDEX"
    if [[ -n "${indexed[$index_key]-}" ]]; then
      message "✖ 卷号重复（含补零后的重复编号）：$file" '1;31'
      return 1
    fi
    size="$(stat -f %z "$file")" || return 1
    if (( size <= 0 )); then
      message "✖ 空分卷不能合并：$file" '1;31'
      return 1
    fi
    indexed[$index_key]="$file"
    states[$index_key]="$(stat -f '%d:%i:%z:%m:%c' "$file")" || return 1
    GROUP_BYTES=$(( GROUP_BYTES + size ))
    count=$(( count + 1 ))
  done < <(find "$dir" -maxdepth 1 -type f -print0)
  if (( count == 0 || count != total )); then
    message "✖ 缺卷：$name，已完成 $count/$total 卷；请先补齐下载，.partial 不参与合并。" '1;31'
    return 1
  fi
  for (( i=1; i<=total; i++ )); do
    if [[ -z "${indexed[$i]-}" ]]; then
      message "✖ 缺少第 $i 卷：$name" '1;31'
      return 1
    fi
    CHUNKS+=("${indexed[$i]}")
    CHUNK_STATES+=("${states[$i]}")
  done
}
# 用编号映射选择分卷组，显示名中的特殊字符不参与路径解析。
select_volume_groups() {
  local -a options
  local i selection="" row="" rc=0 label=""
  local hint='回车勾选 / 取消，空格确认，Ctrl+A 全选，Ctrl+D 清空，Esc 取消'
  for (( i=1; i<=${#GROUP_NAMES}; i++ )); do
    label="${GROUP_DIRS[i]} / ${GROUP_NAMES[i]}"
    options+=("$i"$'\t'"${(q)label}")
  done
  selection="$(printf '%s\n' "${options[@]}" | FZF_DEFAULT_OPTS= FZF_DEFAULT_OPTS_FILE= fzf \
    --multi --height=80% --layout=reverse --border \
    --delimiter=$'\t' --with-nth=2.. --prompt='选择分卷组 > ' \
    --header="$hint" --footer="$hint" \
    --bind='enter:toggle,ctrl-a:select-all,ctrl-d:deselect-all' \
    --bind='space:transform:if [ "${FZF_SELECT_COUNT:-0}" -gt 0 ]; then echo accept; else echo abort; fi')" || rc=$?
  if (( rc == 130 || rc == 1 )) || [[ -z "$selection" && "$rc" == 0 ]]; then
    message 'ℹ 已取消或空选，没有执行合并。'
    exit 0
  fi
  if (( rc != 0 )); then
    message "✖ fzf 选择失败（退出码 $rc）。" '1;31'
    exit 1
  fi
  SELECTED_GROUPS=()
  while IFS= read -r row; do
    i="${row%%$'\t'*}"
    if [[ "$i" != <-> ]] || (( i < 1 || i > ${#GROUP_NAMES} )); then
      message '✖ 选择结果无效，停止。' '1;31'
      exit 1
    fi
    SELECTED_GROUPS+=("$i")
  done <<< "$selection"
}
# 按数值顺序输出分卷内容，读取失败使整个管道失败。
stream_chunks() {
  local file
  for file in "${CHUNKS[@]}"; do
    cat "$file" || return 1
  done
}
# 确认分卷在合并期间未被替换、增删或改写。
check_chunk_states() {
  local i current=""
  for (( i=1; i<=${#CHUNKS}; i++ )); do
    [[ -f "${CHUNKS[i]}" && ! -L "${CHUNKS[i]}" ]] || return 1
    current="$(stat -f '%d:%i:%z:%m:%c' "${CHUNKS[i]}")" || return 1
    [[ "$current" == "${CHUNK_STATES[i]}" ]] || return 1
  done
}
# 只删除已合并且未变化的精确清单，空子目录才尝试移除。
offer_delete_chunks() {
  local dir="$1" output_dir="$2" answer="" file
  message '⚠ 默认保留分卷。删除本组分卷请输入 YES；回车、其它输入或 EOF 均保留。' '1;33'
  IFS= read -r answer || answer=""
  if [[ "$answer" != YES ]]; then
    message 'ℹ 已保留全部分卷。'
    return 0
  fi
  if ! check_chunk_states; then
    message '✖ 分卷已发生变化，取消删除。' '1;31'
    return 1
  fi
  for file in "${CHUNKS[@]}"; do
    if ! /bin/rm -f -- "$file"; then
      message "✖ 删除失败：$file" '1;31'
      return 1
    fi
  done
  if [[ "$dir" != "$output_dir" ]]; then
    /bin/rmdir "$dir" 2>/dev/null || message "ℹ 目录仍有其它内容，保留：$dir"
  fi
  message '✔ 已删除本组分卷；其它文件保留。' '1;32'
}
# 写入独占候选，核对大小与流摘要后以硬链接原子发布。
merge_one_group() {
  local dir="$1" name="$2" output_dir="$TARGET_DIR" output=""
  if (( TARGET_IS_VOLUME_DIR )) && [[ "$dir" == "$TARGET_DIR" ]]; then
    output_dir="${TARGET_DIR:h}"
  fi
  output="$output_dir/$name"
  local stream_hash="" output_hash="" output_size=0
  message "➤ 分卷来源：$dir；原文件名：$name"
  validate_group "$dir" "$name" || return 1
  if [[ -e "$output" || -L "$output" ]]; then
    message "✖ 目标已存在，保留原文件，拒绝覆盖：$output" '1;31'
    return 1
  fi
  ACTIVE_TEMP="$(mktemp "$output_dir/.merge.XXXXXXXX")" || return 1
  message "ℹ 按卷号合并 ${#CHUNKS} 卷，共 $GROUP_BYTES 字节；目标：$output"
  if ! stream_hash="$(stream_chunks | tee "$ACTIVE_TEMP" | shasum -a 256)"; then
    message "✖ 读取或写入失败，保留未发布候选：$ACTIVE_TEMP" '1;31'
    return 1
  fi
  output_size="$(stat -f %z "$ACTIVE_TEMP")" || return 1
  output_hash="$(shasum -a 256 < "$ACTIVE_TEMP")" || return 1
  if (( output_size != GROUP_BYTES )) || [[ "${stream_hash%% *}" != "${output_hash%% *}" ]] || ! check_chunk_states; then
    message "✖ 大小、SHA-256 或分卷状态校验失败；候选保留：$ACTIVE_TEMP" '1;31'
    return 1
  fi
  # link(1) 对已存在的文件、目录和符号链接均失败，不覆盖并发创建的目标。
  if ! /bin/link "$ACTIVE_TEMP" "$output"; then
    message "✖ 发布失败，保留原目标与候选：$ACTIVE_TEMP" '1;31'
    return 1
  fi
  /bin/rm -f -- "$ACTIVE_TEMP" || return 1
  ACTIVE_TEMP=""
  message "✔ 已合并：$output；SHA-256：${output_hash%% *}" '1;32'
  message 'ℹ 此校验确认复制内容一致；没有可信原文件摘要时，不能据此验证镜像来源。'
  offer_delete_chunks "$dir" "$output_dir"
}
# 批量处理选中分组，保留失败状态并报告真实汇总。
merge_selected_groups() {
  local i failed=0 completed=0
  for i in "${SELECTED_GROUPS[@]}"; do
    if merge_one_group "${GROUP_DIRS[i]}" "${GROUP_NAMES[i]}"; then
      completed=$(( completed + 1 ))
    else
      failed=$(( failed + 1 ))
    fi
  done
  message "ℹ 流程结束：成功 $completed 组，失败 $failed 组。日志：$LOG_FILE"
  (( failed == 0 ))
}
# 编排自述、依赖、目录选择和分组合并。
main() {
  show_script_intro_and_wait # 先展示用途与影响，等待回车后继续。
  initialize_runtime # 确认后初始化日志和中断处理。
  check_environment # 只检查实际依赖，不安装或修改环境。
  require_target_directory "$@" # 解析目录参数或拖入路径，默认扫描脚本目录。
  find_volume_groups # 识别平铺与一级子目录分卷。
  select_volume_groups # 明确勾选分卷组，空选和取消不执行。
  merge_selected_groups # 按组校验合并并传播失败状态。
}

main "$@"
