#!/usr/bin/env bash
set -euo pipefail

# ======================== 基础信息 ========================
SCRIPT_BASENAME=$(basename "$0" | sed 's/\.[^.]*$//')
LOG_FILE="/tmp/${SCRIPT_BASENAME}.log"
: > "$LOG_FILE"

# 按当前输出级别记录终端信息，并同步写入脚本日志。
log()            { echo -e "$1" | tee -a "$LOG_FILE"; }
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

MD5_TOOL=""

# ======================== 自述 ========================
print_intro() {
  bold_echo "======== 文件 MD5 计算助手（${SCRIPT_BASENAME}）========"
  note_echo "使用方法："
  echo "  1. 运行脚本之后，按提示操作；"
  echo "  2. 每次需要计算 MD5 时，把目标文件从 Finder 拖到终端里，回车；"
  echo "  3. 计算完成后，脚本不会退出，会继续等待你拖下一个文件；"
  echo "  4. 如果不想继续算了，直接按 [Enter]（空输入）即可退出。"
  echo ""
  note_echo "按 [Enter] 开始使用，或 Ctrl+C 取消..."
  IFS= read -r _
}

# ======================== 检测 MD5 工具 ========================
detect_md5_tool() {
  if command -v md5 &>/dev/null; then
    MD5_TOOL="md5"       # macOS 自带
  elif command -v md5sum &>/dev/null; then
    MD5_TOOL="md5sum"    # Linux 常见
  else
    error_echo "当前系统未找到 md5 / md5sum 命令，无法计算 MD5。"
    exit 1
  fi
  info_echo "已选择 MD5 工具：$MD5_TOOL"
}

# ======================== 计算单个文件的 MD5 ========================
calc_md5_for_file() {
  local file="$1"
  local hash=""

  case "$MD5_TOOL" in
    md5)
      # macOS：优先 -q 只输出哈希
      if hash=$(md5 -q "$file" 2>/dev/null); then
        :
      else
        # 部分系统无 -q，退化为解析最后一个字段
        hash=$(md5 "$file" | awk '{print $NF}')
      fi
      ;;
    md5sum)
      hash=$(md5sum "$file" | awk '{print $1}')
      ;;
  esac

  if [[ -z "$hash" ]]; then
    error_echo "计算失败：$file"
    return 1
  fi

  success_echo "文件：$file"
  highlight_echo "MD5：$hash"
}

# ======================== 主循环：反复要文件 ========================
interactive_loop() {
  while true; do
    echo ""
    note_echo "请拖入要计算 MD5 的文件，然后回车："
    echo "👉 不想算了就按 Ctrl+C 结束脚本"

    local input raw
    IFS= read -r raw

    # 空输入：继续下一轮（不退出）
    if [[ -z "$raw" ]]; then
      note_echo "未输入任何路径，如需退出请按 Ctrl+C。"
      continue
    fi

    # 1) 去掉结尾的 \r（某些终端会带）
    input="${raw%$'\r'}"

    # 2) 去掉首尾所有空白字符（空格 / Tab / 换行等）
    #   前导空白
    input="${input#"${input%%[![:space:]]*}"}"
    #   末尾空白
    input="${input%"${input##*[![:space:]]}"}"

    # 3) 去掉首尾成对引号（Finder 拖拽常见）
    if [[ ( "$input" == \"*\" && "$input" == *\" ) || ( "$input" == \'*\' && "$input" == *\' ) ]]; then
      input="${input:1:${#input}-2}"
    fi

    # 再做一遍空字符串检查（比如用户只输入了几个空格）
    if [[ -z "$input" ]]; then
      note_echo "只输入了空白字符，如需退出请按 Ctrl+C。"
      continue
    fi

    # 校验文件
    if [[ ! -e "$input" ]]; then
      error_echo "路径不存在：$input"
      continue
    fi
    if [[ ! -f "$input" ]]; then
      warn_echo "目标不是普通文件（可能是目录或其他类型）：$input"
      continue
    fi

    calc_md5_for_file "$input"
    # 计算完自动回到 while true 的下一轮，继续等下一个文件
  done
}

# ======================== main ========================
run_main_flow() {
  print_intro
  detect_md5_tool
  interactive_loop
}

# 统一收口脚本入口，仅委托已经拆分完成的业务流程。
main() {
  # 主入口只负责委托完整业务流程，复杂逻辑统一下沉。
  run_main_flow "$@"
}

main "$@"
