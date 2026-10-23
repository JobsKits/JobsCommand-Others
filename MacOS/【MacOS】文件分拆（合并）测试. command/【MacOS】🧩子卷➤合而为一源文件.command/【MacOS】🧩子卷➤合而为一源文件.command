#!/bin/zsh
# 脚本自述：
# - 脚本名称：【MacOS】🧩子卷➤合而为一源文件.command
# - 核心用途：执行“🧩子卷➤合而为一源文件”对应的自动化任务。
# - 影响范围：可能修改当前项目、用户环境或脚本指定的目标。
# - 运行提示：运行后会先打印内置自述；终端模式按回车确认后继续，按 Ctrl+C 可取消。

# 仅渲染自述：标题红色加粗，编号正文蓝色常规字重；非彩色终端输出纯文本。
# >>> Jobs Homebrew install choice >>>
# 输出安装诊断，避免混入返回的命令路径。
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
  print -u2 -r -- "2、其它输入或直接回车：选择用户目录 ${JOBS_HOMEBREW_INSTALL_PREFIX:-$HOME/.local/homebrew}，不使用 sudo；有管理员权限也可选此路径。"
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
SCRIPT_BASENAME=$(basename "$0" | sed 's/\.[^.]*$//')
LOG_FILE="/tmp/${SCRIPT_BASENAME}.log"
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

SCRIPT_DIR="$(cd "$(dirname "${(%):-%x}")" && pwd)"
# 解析并返回后续流程需要的目标信息。
get_cpu_arch() {
  [[ $(uname -m) == "arm64" ]] && echo "arm64" || echo "x86_64"
}
# 封装 inject_shellenv_block 对应的独立处理逻辑。
# 执行对应的环境配置或同步处理。
install_homebrew() {
  local jobs_existing_brew=""
  if jobs_existing_brew="$(jobs_brew_find)"; then
    JOBS_HOMEBREW_BIN="$jobs_existing_brew"
    jobs_brew_activate || exit 1
  fi
  local arch
  arch="$(get_cpu_arch)"
  local shell_path="${SHELL##*/}"
  local profile_file=""
  local brew_bin=""
  local shellenv_cmd=""

  if ! jobs_brew_find >/dev/null; then
    warn_echo "🧩 未检测到 Homebrew，正在安装中...（架构：$arch）"

    if [[ "$arch" == "arm64" ]]; then
      jobs_brew_install_or_exit || {
        error_echo "❌ Homebrew 安装失败（arm64）"
        exit 1
      }
      brew_bin="${JOBS_HOMEBREW_BIN:-$(jobs_brew_find 2>/dev/null || true)}"
    else
      jobs_brew_install_or_exit || {
        error_echo "❌ Homebrew 安装失败（x86_64）"
        exit 1
      }
      brew_bin="${JOBS_HOMEBREW_BIN:-$(jobs_brew_find 2>/dev/null || true)}"
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
# 执行对应的环境配置或同步处理。
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

TARGET_DIR=""
TARGET_IS_VOLUME_DIR=0
VOLUME_DIRS=()
SELECTED_DIRS=()
# 封装 collect_volume_chunks 对应的独立处理逻辑。
collect_volume_chunks() {
  local dir="$1"
  find "$dir" -maxdepth 1 -type f -name '*@*of*' -print 2>/dev/null | LC_ALL=C sort
}
# 封装 infer_original_name_from_dir 对应的独立处理逻辑。
infer_original_name_from_dir() {
  local dir="$1"
  local first_filename
  first_filename="$(collect_volume_chunks "$dir" | head -n 1 | xargs -I{} basename "{}")"
  [[ -n "$first_filename" ]] || return 1
  local original_name="${first_filename%%@*}"
  [[ -n "$original_name" ]] || return 1
  printf '%s\n' "$original_name"
}
# 封装 merge_one_dir_to_output_dir 对应的独立处理逻辑。
merge_one_dir_to_output_dir() {
  local dir="$1"
  local output_dir="$2"
  local name
  name=$(basename "$dir")

  note_echo "开始合并子卷目录：$name"

  local chunks=()
  while IFS= read -r chunk; do
    [[ -f "$chunk" ]] && chunks+=("$chunk")
  done < <(collect_volume_chunks "$dir")

  if [[ ${#chunks[@]} -eq 0 ]]; then
    warn_echo "目录 $name 中未找到任何子卷文件，跳过。"
    return 1
  fi

  local first_filename
  first_filename=$(basename "${chunks[1]}")
  local original_name="${first_filename%%@*}"
  if [[ -z "$original_name" ]]; then
    warn_echo "无法从子卷文件名推断原始文件名（目录：$name），跳过。"
    return 1
  fi

  local meta="${first_filename#*@}"
  local total_expected=""
  if [[ "$meta" =~ ^[0-9]+of([0-9]+)$ ]]; then
    total_expected="${match[1]}"
    total_expected=$((10#$total_expected))
  fi

  local total_actual=${#chunks[@]}
  if [[ -n "$total_expected" && "$total_expected" != "$total_actual" ]]; then
    warn_echo "检测到目录 $name 子卷数量异常：标记总数=$total_expected，实际数量=$total_actual，建议手动检查，跳过。"
    return 1
  fi

  mkdir -p "$output_dir"
  local output_file="$output_dir/$original_name"
  if [[ -e "$output_file" ]]; then
    warn_echo "目标文件已存在，将覆盖：$output_file"
  fi

  : > "$output_file"
  local chunk
  for chunk in "${chunks[@]}"; do
    cat "$chunk" >> "$output_file" || {
      error_echo "合并过程中出错，文件：$chunk"
      rm -f "$output_file"
      return 1
    }
  done

  success_echo "已完成合并：$output_file"
  printf '%s\n' "$output_file"
}
# 执行已经拆分完成的独立业务步骤。
run_jobs_noninteractive_merge() {
  local volume_dir="$1"
  local output_dir="$2"

  if [[ ! -d "$volume_dir" ]]; then
    error_echo "非交互合并失败：子卷目录不存在：$volume_dir"
    return 1
  fi

  if [[ -z "$output_dir" ]]; then
    error_echo "非交互合并失败：输出目录为空。"
    return 1
  fi

  merge_one_dir_to_output_dir "$volume_dir" "$output_dir" >/dev/null
}
# 展示脚本用途和影响范围，并在执行前等待用户确认。
print_intro() {
  bold_echo "======== 子卷合并脚本（${SCRIPT_BASENAME}）========" | jobs_intro_style title
  note_echo "功能概要：" | jobs_intro_style title
  echo "  1. 支持拖入包含子卷目录的目标目录，也支持直接拖入子卷目录本身；" | jobs_intro_style body
  echo "  2. 识别包含类似 原文件@001of004 的子卷目录；" | jobs_intro_style body
  echo "  3. 使用 fzf 选择需要合并的子卷目录（或对全部目录执行）；" | jobs_intro_style body
  echo "  4. 按顺序合并子卷为一个完整文件；" | jobs_intro_style body
  echo "  5. 合并成功后，询问是否删除对应的子卷目录。" | jobs_intro_style body
  echo "" | jobs_intro_style body
  note_echo "按 [Enter] 继续，或 Ctrl+C 退出..." | jobs_intro_style body
  IFS= read -r _
}
# 执行已经拆分完成的独立业务步骤。
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
# 封装 normalize_input_path 对应的独立处理逻辑。
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
# 收集并校验用户输入，决定后续执行路径。
choose_target_directory() {
  echo ""
  note_echo "请拖入要处理的【目标目录】或【子卷目录】，然后回车。"
  echo "👉 直接按 [Enter]：使用脚本所在目录：$SCRIPT_DIR"
  local input="${1:-}"

  if [[ -z "$input" ]]; then
    IFS= read -r input
  fi

  if [[ -z "$input" ]]; then
    TARGET_DIR="$SCRIPT_DIR"
  else
    input="$(normalize_input_path "$input")"

    if [[ ! -d "$input" ]]; then
      error_echo "指定路径不是有效目录：$input"
      exit 1
    fi
    TARGET_DIR="$(cd "$input" && pwd)"
  fi

  info_echo "本次操作的目标目录为：$TARGET_DIR"
}
# 解析并返回后续流程需要的目标信息。
find_volume_dirs() {
  VOLUME_DIRS=()
  TARGET_IS_VOLUME_DIR=0
  local dir

  if [[ -n "$(collect_volume_chunks "$TARGET_DIR" | head -n 1)" ]]; then
    VOLUME_DIRS+=("$TARGET_DIR")
    TARGET_IS_VOLUME_DIR=1
  fi

  for dir in "$TARGET_DIR"/* "$TARGET_DIR"/.[!.]* "$TARGET_DIR"/..?*; do
    [[ -d "$dir" ]] || continue
    if [[ -n "$(collect_volume_chunks "$dir" | head -n 1)" ]]; then
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
# 收集并校验用户输入，决定后续执行路径。
select_volume_dirs() {
  local options=()
  local dir
  for dir in "${VOLUME_DIRS[@]}"; do
    local name
    name=$(basename "$dir")
    options+=("$name :: $dir")
  done

  local selection=""
  if [[ ${#VOLUME_DIRS[@]} -eq 1 ]]; then
    selection="${options[1]}"
    info_echo "仅检测到 1 个子卷目录，将直接处理：${selection%% :: *}"
  else
    options=("【全部子卷目录】 :: __ALL__" "${options[@]}")

    note_echo "在 fzf 中选择要合并的子卷目录："
    selection=$(printf '%s\n' "${options[@]}" | fzf --prompt="请选择要合并的子卷目录：" --height=15 --border) || {
      warn_echo "未选择任何目录，任务取消。"
      exit 1
    }
  fi

  local selected_token="${selection#*:: }"

  if [[ "$selected_token" == "__ALL__" ]]; then
    SELECTED_DIRS=("${VOLUME_DIRS[@]}")
    info_echo "将对所有 ${#SELECTED_DIRS[@]} 个子卷目录执行合并。"
  else
    SELECTED_DIRS=("$selected_token")
    info_echo "已选择子卷目录：$(basename "$selected_token")"
  fi
}
# 封装 merge_one_dir 对应的独立处理逻辑。
merge_one_dir() {
  local dir="$1"
  local name
  name=$(basename "$dir")
  local original_name
  original_name="$(infer_original_name_from_dir "$dir")" || {
    warn_echo "无法推断目录 $name 的原文件名，跳过。"
    return 1
  }

  local output_dir="$TARGET_DIR"
  if [[ "$TARGET_IS_VOLUME_DIR" == "1" && "$dir" == "$TARGET_DIR" ]]; then
    output_dir="$(dirname "$TARGET_DIR")"
  fi

  local output_file="$output_dir/$original_name"
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

  merge_one_dir_to_output_dir "$dir" "$output_dir" >/dev/null || return 1

  echo ""
  warn_echo "是否删除子卷目录？（高危操作）"
  gray_echo "必须输入 YES 后回车才会删除；其它输入一律保留。"
  local confirm_rm
  IFS= read -r confirm_rm
  if [[ "$confirm_rm" == "YES" ]]; then
    if rm -rf -- "$dir"; then
      success_echo "已删除子卷目录：$name"
    else
      error_echo "删除子卷目录失败：$name"
    fi
  else
    note_echo "已保留子卷目录：$name"
  fi
}
# 封装 merge_selected_dirs 对应的独立处理逻辑。
merge_selected_dirs() {
  local dir
  for dir in "${SELECTED_DIRS[@]}"; do
    merge_one_dir "$dir"
    echo ""
  done

  success_echo "所有选定的子卷目录合并流程已结束。"
}
# 打印脚本内置自述，并按运行入口决定是否等待用户确认。
show_script_intro_and_wait() {
  printf '%s\n' '============================== 脚本内置自述 ==============================' | jobs_intro_style title
  printf '%s\n' '脚本名称：【MacOS】🧩子卷➤合而为一源文件.command' | jobs_intro_style title
  printf '%s\n' '核心用途：执行“🧩子卷➤合而为一源文件”对应的自动化任务。' | jobs_intro_style body
  printf '%s\n' '影响范围：可能修改当前项目、用户环境或脚本指定的目标。' | jobs_intro_style body
  printf '%s\n' '取消方式：确认前按 Ctrl+C 终止，不会继续执行后续业务。' | jobs_intro_style body
  printf '%s\n' '============================================================================' | jobs_intro_style title
  if [[ ! -t 0 ]]; then
    printf '%s\n' '当前没有可交互输入，请在终端中重新运行。' >&2
    exit 1
  fi
  IFS= read -r '?👉 已了解脚本用途与影响，按回车继续；按 Ctrl+C 取消：' _ || exit 1
}
# 编排脚本的高层业务流程。
# 初始化脚本运行环境，并集中承载原有的顶层执行逻辑。
# 将 Homebrew shellenv 写入用户配置并在当前终端生效。
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
# 初始化脚本运行环境和后续流程所需状态。
initialize_script_runtime() {
  setopt NO_NOMATCH TYPESET_SILENT
  set -euo pipefail
  : > "$LOG_FILE"
  if [[ "${1:-}" == "--jobs-noninteractive" ]]; then
    if [[ $# -lt 3 ]]; then
      error_echo "用法：$0 --jobs-noninteractive 子卷目录 输出目录"
      exit 1
    fi
    run_jobs_noninteractive_merge "$2" "$3"
    exit $?
  fi
}
# 编排脚本的高层业务流程。
main() {
  show_script_intro_and_wait # 展示脚本内置自述，并按运行入口完成防误触确认。
  initialize_script_runtime # 初始化 Shell 选项、日志、依赖和入口运行状态。
  print_intro # 执行 print_intro 对应的独立业务步骤。
  run_self_check_interactive # 检查当前环境与执行条件是否满足脚本要求。
  choose_target_directory "${1:-}" # 执行 choose_target_directory 对应的独立业务步骤。
  find_volume_dirs # 解析当前任务所需的路径、参数或运行上下文。
  select_volume_dirs # 执行 select_volume_dirs 对应的独立业务步骤。
  merge_selected_dirs # 执行 merge_selected_dirs 对应的独立业务步骤。
}

main "$@"
