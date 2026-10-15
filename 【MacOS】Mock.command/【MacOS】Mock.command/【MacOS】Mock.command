#!/bin/zsh
# 脚本自述：
# - 脚本名称：【MacOS】Mock.command
# - 核心用途：执行“Mock”对应的自动化任务。
# - 影响范围：可能修改当前项目、用户环境或脚本指定的目标。
# - 运行提示：运行后会先打印内置自述；终端模式按回车确认后继续，按 Ctrl+C 可取消。

# ================================== 基础信息 ==================================

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
# >>> Jobs embedded Python runtime >>>
# 输出诊断，不污染函数返回的解释器路径。
_jobs_python_note() {
  print -u2 -r -- "$*"
}
# 标识当前 zsh 进程及其子 shell，避免继承环境绕过确认。
_jobs_python_process_token() {
  print -r -- "$$:${ZSH_SUBSHELL:-0}"
}
# 只有当前可交互进程内形成的确认才允许环境写操作。
_jobs_python_has_authorization() {
  [[ -t 0 && -t 2 && "${IS_SOURCETREE_RUNTIME:-0}" != 1 && "${DRY_RUN:-0}" != 1 ]] || return 1
  [[ "${parameters[_JOBS_PYTHON_CONFIRMED_PROCESS]:-}" != *export* &&
     "${_JOBS_PYTHON_CONFIRMED_PROCESS:-}" == "$(_jobs_python_process_token)" ]]
}
# 记录调用方已完成的终端确认；非交互入口只允许后续只读检查。
jobs_python_mark_confirmed() {
  emulate -L zsh
  if [[ -t 0 && -t 2 && "${IS_SOURCETREE_RUNTIME:-0}" != 1 && "${DRY_RUN:-0}" != 1 ]]; then
    typeset -g +x _JOBS_PYTHON_CONFIRMED_PROCESS="$(_jobs_python_process_token)"
  fi
  return 0
}
# 在业务自述之后确认本次 Homebrew 更新及 Python 环境准备。
jobs_python_confirm_prepare() {
  emulate -L zsh
  local answer=""
  _jobs_python_has_authorization && return 0
  _jobs_python_note "${1:-Python 环境预检：更新 Homebrew；Python 不满足业务版本时经确认安装或修复。}"
  if [[ ! -t 0 || ! -t 2 || "${IS_SOURCETREE_RUNTIME:-0}" == 1 || "${DRY_RUN:-0}" == 1 ]]; then
    _jobs_python_note "✖ 环境准备需要终端确认；当前未更新或安装任何环境。"
    return 1
  fi
  print -u2 -n -r -- '➤ 按回车准备环境；任意非空输入（含空格）取消：'
  if ! IFS= read -r answer || [[ -n "$answer" ]]; then
    _jobs_python_note '✖ 已取消环境准备。'
    return 1
  fi
  jobs_python_mark_confirmed
}
# 对缺失依赖和已有虚拟环境修复使用统一的必需动作确认。
_jobs_python_confirm_required() {
  emulate -L zsh
  local answer=""
  if ! _jobs_python_has_authorization; then
    _jobs_python_note "✖ $1；需要在终端确认后重试，未执行安装或修复。"
    return 1
  fi
  print -u2 -n -r -- "➤ $1；直接回车执行，任意非空输入（含空格）取消："
  if ! IFS= read -r answer || [[ -n "$answer" ]]; then
    _jobs_python_note '✖ 已取消，停止当前流程。'
    return 1
  fi
}
# 校验版本参数，避免把调用参数作为公式或命令选项解释。
_jobs_python_validate_arguments() {
  emulate -L zsh
  local minimum="$1" formula="$2" maximum="${3:-}"
  if [[ ! "$minimum" =~ '^[0-9]+\.[0-9]+(\.[0-9]+)?$' ||
        ( -n "$maximum" && ! "$maximum" =~ '^[0-9]+\.[0-9]+(\.[0-9]+)?$' ) ||
        ! "$formula" =~ '^python(@[0-9]+\.[0-9]+)?$' ]]; then
    _jobs_python_note "✖ Python 版本或 Homebrew 公式参数无效：$minimum / $formula / $maximum"
    return 1
  fi
  if [[ -n "$maximum" ]] && ! _jobs_python_version_less "$minimum" "$maximum"; then
    _jobs_python_note '✖ Python 最低版本必须小于排他上限。'
    return 1
  fi
}
# 以数值逐段比较版本，不依赖任何 Python 运行时。
_jobs_python_version_less() {
  emulate -L zsh
  local -a left right
  local component left_value right_value
  left=("${(@s:.:)1}")
  right=("${(@s:.:)2}")
  for component in 1 2 3; do
    left_value=$((10#${left[$component]:-0}))
    right_value=$((10#${right[$component]:-0}))
    (( left_value < right_value )) && return 0
    (( left_value > right_value )) && return 1
  done
  return 1
}
# 验证本脚本内封装的 Homebrew 接口，不读取外部函数库。
_jobs_python_load_brew_helpers() {
  emulate -L zsh
  local helper
  for helper in jobs_brew_find jobs_brew_choose_installation jobs_brew_install_system jobs_brew_install_user jobs_brew_activate; do
    (( $+functions[$helper] )) || { _jobs_python_note "✖ 脚本内置 Homebrew 接口缺失：$helper"; return 1; }
  done
}
# 验证解释器版本、标准库与归属，返回可机器判断的状态码。
_jobs_python_probe() {
  emulate -L zsh
  local candidate="$1" minimum="$2" maximum="$3" tree="$4" mode="$5"
  [[ -x "$candidate" ]] || return 1
  PYTHONDONTWRITEBYTECODE=1 "$candidate" -c '
import sys
def version(value):
    return tuple((list(map(int, value.split("."))) + [0, 0, 0])[:3])
actual = tuple(sys.version_info[:3])
if actual < version(sys.argv[1]):
    sys.exit(2)
if sys.argv[2] and actual >= version(sys.argv[2]):
    sys.exit(5)
try:
    import venv
    from pathlib import Path
    if actual >= (3, 11, 0):
        import tomllib
except Exception as error:
    print("Python standard library unavailable: " + str(error), file=sys.stderr)
    sys.exit(3)
try:
    target = Path(sys.argv[3]).resolve()
    executable = Path(sys.executable).resolve()
    if sys.argv[4] == "venv":
        if Path(sys.prefix).resolve() != target or sys.prefix == sys.base_prefix:
            sys.exit(4)
    else:
        executable.relative_to(target)
except (ValueError, OSError):
    sys.exit(4)
print("JOBS_PYTHON_OK|" + ".".join(map(str, actual)) + "|" + str(executable))
' "$minimum" "$maximum" "$tree" "$mode"
}
# 验证公式路径属于当前 Homebrew Cellar，再寻找该公式内的健康解释器。
_jobs_python_find_formula_python() {
  emulate -L zsh
  local minimum="$1" formula="$2" maximum="${3:-}"
  local cellar_root formula_cellar formula_prefix candidate probe_result probe_code=1 version_suffix actual_formula python3_command link_target
  local -a candidates runtime_bins
  cellar_root="$(HOMEBREW_NO_AUTO_UPDATE=1 "$JOBS_HOMEBREW_BIN" --cellar 2>/dev/null)" || return 1
  formula_cellar="$(HOMEBREW_NO_AUTO_UPDATE=1 "$JOBS_HOMEBREW_BIN" --cellar "$formula" 2>/dev/null)" || return 1
  actual_formula="${formula_cellar:t}"
  [[ "$cellar_root" == /* && "$cellar_root" != / && "$formula_cellar" == /* &&
     "${formula_cellar:A}" == "${cellar_root:A}/$actual_formula" &&
     ( "$actual_formula" == "$formula" ||
       ( "$formula" == python && "$actual_formula" =~ '^python@[0-9]+\.[0-9]+$' ) ) ]] || {
    _jobs_python_note "✖ Homebrew 公式 Cellar 路径异常：$formula_cellar"
    return 4
  }
  formula_prefix="$(HOMEBREW_NO_AUTO_UPDATE=1 "$JOBS_HOMEBREW_BIN" --prefix "$formula" 2>/dev/null)" || return 1
  if [[ "$formula_prefix" == /* && ! -e "$formula_prefix" && ! -L "$formula_prefix" ]]; then
    return 1
  fi
  if [[ -L "$formula_prefix" && ! -e "$formula_prefix" ]]; then
    link_target="$(/usr/bin/readlink "$formula_prefix")" || return 4
    [[ "$link_target" == /* ]] || link_target="${formula_prefix:h}/$link_target"
    if [[ "${link_target:a}" == "${formula_cellar:A}/"* ]]; then
      return 1
    fi
    _jobs_python_note "✖ 损坏的公式链接指向外部路径：$formula_prefix"
    return 4
  fi
  [[ "$formula_prefix" == /* && "${formula_prefix:A}" == "${formula_cellar:A}/"* && -d "$formula_prefix" ]] || {
    _jobs_python_note "✖ Homebrew 公式前缀不属于指定公式：$formula_prefix"
    return 4
  }
  version_suffix="${actual_formula#python@}"
  [[ "$actual_formula" != python ]] || version_suffix=3
  candidates=("$formula_prefix/libexec/bin/python3" "$formula_prefix/bin/python$version_suffix" "$formula_prefix/bin/python3")
  runtime_bins=()
  for candidate in "$formula_prefix/libexec/bin" "$formula_prefix/bin"; do
    if [[ -d "$candidate" && "${candidate:A}" == "${formula_prefix:A}/"* ]]; then
      runtime_bins+=("$candidate")
    fi
  done
  for candidate in "${candidates[@]}"; do
    [[ -x "$candidate" ]] || continue
    probe_code=0
    probe_result="$(_jobs_python_probe "$candidate" "$minimum" "$maximum" "${formula_cellar:A}" runtime 2>&1)" || probe_code=$?
    if (( probe_code == 0 )) && [[ "$probe_result" == JOBS_PYTHON_OK\|* ]]; then
      python3_command=""
      local runtime_bin
      for runtime_bin in "${runtime_bins[@]}"; do
        if [[ -x "$runtime_bin/python3" ]]; then
          python3_command="$runtime_bin/python3"
          break
        fi
      done
      if [[ -z "$python3_command" ]] ||
         ! _jobs_python_probe "$python3_command" "$minimum" "$maximum" "${formula_cellar:A}" runtime >/dev/null 2>&1; then
        _jobs_python_note "✖ 公式缺少健康的 python3 命令入口：$formula_prefix"
        return 3
      fi
      typeset -gx JOBS_PYTHON_BIN="$candidate"
      typeset -g +x _JOBS_PYTHON_SELECTED_PROCESS="$(_jobs_python_process_token)"
      typeset -g +x _JOBS_PYTHON_SELECTED_BIN="$candidate"
      typeset -g +x _JOBS_PYTHON_SELECTED_TREE="${formula_cellar:A}"
      export PATH="${(j.:.)runtime_bins}:$PATH"
      rehash
      _jobs_python_note "✔ 复用 Homebrew Python：$candidate（${${probe_result#*|}%%|*}）"
      return 0
    fi
    (( probe_code != 0 )) || probe_code=1
    [[ "$probe_code" != 2 && "$probe_code" != 5 ]] || break
  done
  return "$probe_code"
}
# 在当前进程一次更新 Homebrew；失败不进入 Python 安装或业务。
_jobs_python_update_brew_once() {
  emulate -L zsh
  local brew_key="${JOBS_HOMEBREW_BIN:A}" token="$(_jobs_python_process_token)"
  _jobs_python_has_authorization || return 1
  if [[ "${parameters[_JOBS_PYTHON_UPDATED_BREWS]:-}" != association* ||
        "${parameters[_JOBS_PYTHON_UPDATED_BREWS]:-}" == *export* ]]; then
    unset _JOBS_PYTHON_UPDATED_BREWS
    typeset -gA +x _JOBS_PYTHON_UPDATED_BREWS
  fi
  [[ "${_JOBS_PYTHON_UPDATED_BREWS[$brew_key]:-}" != "$token" ]] || return 0
  _jobs_python_note "ℹ 更新 Homebrew 本体及公式索引：$JOBS_HOMEBREW_BIN update"
  if ! HOMEBREW_NO_AUTO_UPDATE=1 "$JOBS_HOMEBREW_BIN" update; then
    _jobs_python_note '✖ Homebrew 更新失败，停止 Python 准备；未升级其它公式。'
    return 1
  fi
  jobs_brew_activate || { _jobs_python_note '✖ Homebrew 更新后激活或健康复检失败。'; return 1; }
  _JOBS_PYTHON_UPDATED_BREWS[$brew_key]="$token"
}
# 全新 Mac 缺少 CLT 时只请求系统安装一次，完成对话框后由用户重新运行。
_jobs_python_require_clt_for_install() {
  emulate -L zsh
  local developer_directory git_command token="$(_jobs_python_process_token)"
  [[ "$(/usr/bin/uname -s)" == Darwin ]] || return 0
  developer_directory="$(/usr/bin/xcode-select -p 2>/dev/null)" || developer_directory=""
  git_command="$(command -v git 2>/dev/null)"
  if [[ -n "$developer_directory" && -d "$developer_directory" && -n "$git_command" ]] &&
     "$git_command" --version >/dev/null 2>&1; then
    return 0
  fi
  if [[ "${parameters[_JOBS_PYTHON_CLT_REQUESTED_PROCESS]:-}" != *export* &&
        "${_JOBS_PYTHON_CLT_REQUESTED_PROCESS:-}" == "$token" ]]; then
    _jobs_python_note '✖ 已请求 Command Line Tools 安装；请完成系统对话框后重新运行脚本。'
    return 1
  fi
  _jobs_python_confirm_required '缺少可用 Git / Command Line Tools，将打开 Apple 系统安装对话框' || return 1
  typeset -g +x _JOBS_PYTHON_CLT_REQUESTED_PROCESS="$token"
  if ! /usr/bin/xcode-select --install; then
    _jobs_python_note '✖ 无法发起 Command Line Tools 安装；请先在系统中安装或修复开发者工具。'
    return 1
  fi
  _jobs_python_note 'ℹ 已请求系统安装；请完成 Command Line Tools 对话框后重新运行，本次不继续安装 Homebrew。'
  return 1
}
# 准备必经的 Homebrew 通道，缺失时复用内置安装路径选择。
_jobs_python_prepare_brew() {
  emulate -L zsh
  local installed=""
  _jobs_python_load_brew_helpers || return 1
  if ! JOBS_HOMEBREW_BIN="$(jobs_brew_find)"; then
    if ! _jobs_python_has_authorization; then
      _jobs_python_note '✖ 缺少健康 Homebrew；请在终端确认环境准备，未执行安装。'
      return 1
    fi
    _jobs_python_require_clt_for_install || return 1
    jobs_brew_choose_installation || return 1
    case "${JOBS_HOMEBREW_INSTALL_MODE:-}" in
      system) jobs_brew_install_system || return 1 ;;
      user) jobs_brew_install_user || return 1 ;;
      *) _jobs_python_note '✖ Homebrew 安装路径选择无效，停止。'; return 1 ;;
    esac
    installed=installed
  fi
  jobs_brew_activate "$installed" || { _jobs_python_note '✖ Homebrew 激活或健康检查失败。'; return 1; }
  if _jobs_python_has_authorization; then
    _jobs_python_update_brew_once || return 1
  else
    _jobs_python_note 'ℹ 当前未获得终端确认，仅只读检查已有 Homebrew / Python，不更新或安装。'
  fi
}
# 更新 Homebrew 后只处理业务指定的 Python 公式，并立即复检。
jobs_python_ensure() {
  emulate -L zsh
  local minimum="${1:-}" formula="${2:-python@3.13}" maximum="${3:-}"
  local probe_code=0 action=install installed_versions=""
  unset JOBS_PYTHON_BIN
  _jobs_python_validate_arguments "$minimum" "$formula" "$maximum" || return 1
  _jobs_python_prepare_brew || return 1
  _jobs_python_find_formula_python "$minimum" "$formula" "$maximum" || probe_code=$?
  (( probe_code != 0 )) || return 0
  if ! _jobs_python_has_authorization; then
    _jobs_python_note "✖ $formula 不满足 Python $minimum${maximum:+ 至小于 $maximum}；无交互确认，停止。"
    return 1
  fi
  if (( probe_code == 4 )); then
    _jobs_python_note '✖ Python 或公式路径归属异常，停止；不覆盖外部解释器。'
    return 1
  fi
  if (( probe_code == 5 )); then
    _jobs_python_note "✖ $formula 的 Python 版本高于业务允许范围（须小于 $maximum）；停止，不尝试无效升级。"
    return 1
  fi
  installed_versions="$(HOMEBREW_NO_AUTO_UPDATE=1 "$JOBS_HOMEBREW_BIN" list --versions "$formula" 2>/dev/null)" || installed_versions=""
  if [[ -n "$installed_versions" ]]; then
    action=reinstall
    (( probe_code != 2 )) || action=upgrade
  fi
  _jobs_python_confirm_required "必需的 $formula 未就绪，执行 brew $action $formula" || return 1
  if ! HOMEBREW_NO_AUTO_UPDATE=1 "$JOBS_HOMEBREW_BIN" "$action" "$formula"; then
    _jobs_python_note "✖ brew $action $formula 失败；停止，不重复安装。"
    return 1
  fi
  jobs_brew_activate || return 1
  if ! _jobs_python_find_formula_python "$minimum" "$formula" "$maximum"; then
    _jobs_python_note "✖ $formula 安装或修复后仍不满足要求；停止下游业务。"
    return 1
  fi
}
# 拒绝空目录、根目录及符号链接路径，防止虚拟环境修复涉及其它目录。
_jobs_python_validate_venv_path() {
  emulate -L zsh
  local supplied="${1:-}" absolute
  [[ -n "$supplied" ]] || { _jobs_python_note '✖ 虚拟环境路径不能为空。'; return 1; }
  absolute="${supplied:a}"
  if [[ "$absolute" == / || "$absolute" == "${HOME:a}" || "$absolute" != "${absolute:A}" ||
        -L "$absolute" || ( -e "$absolute" && ! -d "$absolute" ) ]]; then
    _jobs_python_note "✖ 虚拟环境须为独立真实目录，拒绝危险路径：$supplied"
    return 1
  fi
  if [[ -d "$absolute" && ! -f "$absolute/pyvenv.cfg" && ! -e "$absolute/bin/python" &&
        ! -L "$absolute/bin/python" && "${absolute:t}" != .venv && "${absolute:t}" != venv ]]; then
    _jobs_python_note "✖ 目录不是可识别的虚拟环境，不移动源码或用户目录：$absolute"
    return 1
  fi
  print -r -- "$absolute"
}
# 复用健康虚拟环境；旧坏环境完整改名备份后重建，不删除原目录。
jobs_python_prepare_venv() {
  emulate -L zsh
  local supplied="${1:-}" minimum="${2:-}" maximum="${3:-}" environment candidate probe_result backup suffix=0
  _jobs_python_validate_arguments "$minimum" python "${maximum:-}" || return 1
  environment="$(_jobs_python_validate_venv_path "$supplied")" || return 1
  candidate="$environment/bin/python"
  if [[ -d "$environment" ]] &&
     probe_result="$(_jobs_python_probe "$candidate" "$minimum" "$maximum" "$environment" venv 2>&1)" &&
     [[ "$probe_result" == JOBS_PYTHON_OK\|* ]]; then
    _jobs_python_note "✔ 复用虚拟环境：$environment"
    return 0
  fi
  if ! _jobs_python_has_authorization; then
    _jobs_python_note "✖ 虚拟环境缺失或不健康，需要终端确认后准备：$environment"
    return 1
  fi
  if [[ -z "${JOBS_PYTHON_BIN:-}" || ! -x "$JOBS_PYTHON_BIN" ||
        "${parameters[_JOBS_PYTHON_SELECTED_PROCESS]:-}" == *export* ||
        "${parameters[_JOBS_PYTHON_SELECTED_BIN]:-}" == *export* ||
        "${parameters[_JOBS_PYTHON_SELECTED_TREE]:-}" == *export* ||
        "${_JOBS_PYTHON_SELECTED_PROCESS:-}" != "$(_jobs_python_process_token)" ||
        "${_JOBS_PYTHON_SELECTED_BIN:-}" != "$JOBS_PYTHON_BIN" ]]; then
    _jobs_python_note '✖ 尚未选定健康 Homebrew Python，请先调用 jobs_python_ensure。'
    return 1
  fi
  if ! _jobs_python_probe "$JOBS_PYTHON_BIN" "$minimum" "$maximum" "$_JOBS_PYTHON_SELECTED_TREE" runtime >/dev/null 2>&1; then
    _jobs_python_note '✖ 已选择的 Homebrew Python 不满足虚拟环境版本要求，停止。'
    return 1
  fi
  if [[ -d "$environment" ]]; then
    _jobs_python_confirm_required "修复旧或损坏的虚拟环境 $environment（完整改名备份）" || return 1
    backup="$environment.backup.$(/bin/date '+%Y%m%d-%H%M%S').$$"
    while [[ -e "$backup" || -L "$backup" ]]; do
      (( suffix += 1 ))
      backup="$environment.backup.$(/bin/date '+%Y%m%d-%H%M%S').$$.$suffix"
    done
    if ! mv -- "$environment" "$backup"; then
      _jobs_python_note "✖ 原虚拟环境备份失败，停止：$environment"
      return 1
    fi
    _jobs_python_note "ℹ 原虚拟环境已完整保留：$backup"
  fi
  if ! PYTHONDONTWRITEBYTECODE=1 "$JOBS_PYTHON_BIN" -m venv "$environment"; then
    _jobs_python_note "✖ 虚拟环境创建失败，停止；备份保持原状：${backup:-无旧环境}"
    return 1
  fi
  if ! probe_result="$(_jobs_python_probe "$candidate" "$minimum" "$maximum" "$environment" venv 2>&1)" ||
     [[ "$probe_result" != JOBS_PYTHON_OK\|* ]]; then
    _jobs_python_note "✖ 虚拟环境创建后复检失败，停止：$environment"
    return 1
  fi
  _jobs_python_note "✔ 虚拟环境已就绪：$environment"
}
# <<< Jobs embedded Python runtime <<<

# 编排本文件内嵌的环境自检，保留当前入口的确认和版本要求。
jobs_mock_python_preflight() {
  case "${1:-interactive}" in
    confirmed) jobs_python_mark_confirmed ;;
    readonly) ;;
    *)
      if [[ -t 0 && -t 2 && "${IS_SOURCETREE_RUNTIME:-0}" != 1 ]]; then
        jobs_python_confirm_prepare || return 1
      fi
      ;;
  esac
  jobs_python_ensure 3.11 python@3.13
}

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
SCRIPT_PATH="${0:A}"
SCRIPT_BASENAME="$(basename "$0" | sed 's/\.[^.]*$//')"
SCRIPT_DIR="$(cd "$(dirname "$SCRIPT_PATH")" && pwd)"
LOG_FILE="/tmp/${SCRIPT_BASENAME}.log"
HTTP_LOG_FILE="/tmp/${SCRIPT_BASENAME}_http_server.log"
PID_FILE="/tmp/${SCRIPT_BASENAME}_http_server.pid"
PORT="8080"
HOST="127.0.0.1"
JSON_DIR_NAME="jsons"
# ================================== 日志与彩色输出 ==================================
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
note_echo()      { log "\033[1;35m➤ $1\033[0m"; }
# 按当前输出级别记录终端信息，并同步写入脚本日志。
error_echo()     { log "\033[1;31m✖ $1\033[0m"; }
# 按当前输出级别记录终端信息，并同步写入脚本日志。
highlight_echo() { log "\033[1;36m🔹 $1\033[0m"; }
# 按当前输出级别记录终端信息，并同步写入脚本日志。
gray_echo()      { log "\033[0;90m$1\033[0m"; }
# 按当前输出级别记录终端信息，并同步写入脚本日志。
bold_echo()      { log "\033[1m$1\033[0m"; }
# 封装 print_divider 对应的独立处理逻辑。
print_divider() {
  gray_echo "=================================================="
}
# 封装 pause_enter 对应的独立处理逻辑。
pause_enter() {
  echo -n $'\n'"按回车继续..."$'\n' | tee -a "$LOG_FILE"
  IFS= read -r _
}
# 收集并校验用户输入，决定后续执行路径。
prompt_optional_upgrade() {
  local name="$1"
  local choice=""
  echo -n $'\n' | tee -a "$LOG_FILE"
  read -r "?检测到已安装 ${name}，输入任意字符升级，直接回车跳过： " choice
  [[ -n "$choice" ]]
}
# ================================== 通用工具 ==================================
# 封装 require_macos 对应的独立处理逻辑。
require_macos() {
  if [[ "$(uname -s)" != "Darwin" ]]; then
    error_echo "该脚本当前仅针对 macOS 设计，检测到系统不是 macOS"
    exit 1
  fi
}
# 封装 require_basic_commands 对应的独立处理逻辑。
require_basic_commands() {
  local missing=()
  local cmd

  for cmd in basename sed tee uname find sort grep cat ps kill sleep mkdir touch; do
    command -v "$cmd" >/dev/null 2>&1 || missing+=("$cmd")
  done

  if [[ ${#missing[@]} -gt 0 ]]; then
    error_echo "缺少基础命令：${missing[*]}"
    exit 1
  fi
}
# 封装 command_exists 对应的独立处理逻辑。
command_exists() {
  command -v "$1" >/dev/null 2>&1
}
# 解析并返回后续流程需要的目标信息。
get_cpu_arch() {
  [[ "$(uname -m)" == "arm64" ]] && echo "arm64" || echo "x86_64"
}
# 解析并返回后续流程需要的目标信息。
get_shell_name() {
  echo "${SHELL##*/}"
}
# 解析并返回后续流程需要的目标信息。
get_shell_profile_file() {
  local shell_name
  shell_name="$(get_shell_name)"

  case "$shell_name" in
    zsh)  echo "$HOME/.zprofile" ;;
    bash) echo "$HOME/.bash_profile" ;;
    *)    echo "$HOME/.profile" ;;
  esac
}
# 检查当前运行条件是否满足后续流程要求。
ensure_file_exists() {
  local file="$1"
  mkdir -p "$(dirname "$file")"
  touch "$file" 2>/dev/null || {
    error_echo "无法创建或写入配置文件：$file"
    return 1
  }
}
# ================================== 幂等环境注入 ==================================
# 封装 append_block_if_missing 对应的独立处理逻辑。
append_block_if_missing() {
  local file="$1"
  local block_id="$2"
  local content="$3"

  local begin_marker="# >>> ${block_id} >>>"
  local end_marker="# <<< ${block_id} <<<"

  ensure_file_exists "$file" || return 1

  if grep -Fq "$begin_marker" "$file" 2>/dev/null; then
    info_echo "配置块已存在：$block_id -> $file"
    return 0
  fi

  {
    echo ""
    echo "$begin_marker"
    printf "%s\n" "$content"
    echo "$end_marker"
  } >> "$file"

  success_echo "已写入配置块：$block_id -> $file"
}
# 封装 apply_shellenv_now 对应的独立处理逻辑。
apply_shellenv_now() {
  local shellenv_cmd="$1"
  eval "$shellenv_cmd"
  success_echo "环境已在当前终端生效"
}
# ================================== Homebrew 环境处理 ==================================
# 封装 brew_bin_candidates 对应的独立处理逻辑。
brew_bin_candidates() {
  cat <<'BREWEOF'
/opt/homebrew/bin/brew
/usr/local/bin/brew
BREWEOF
}
# 解析并返回后续流程需要的目标信息。
detect_brew_bin() {
  local candidate

  if command_exists brew; then
    command -v brew
    return 0
  fi

  while IFS= read -r candidate; do
    if [[ -x "$candidate" ]]; then
      echo "$candidate"
      return 0
    fi
  done < <(brew_bin_candidates)

  return 1
}
# 检查当前运行条件是否满足后续流程要求。
ensure_brew_env() {
  local brew_bin=""

  if brew_bin="$(detect_brew_bin)"; then
    eval "\$(${brew_bin} shellenv)"
    return 0
  fi

  return 1
}
# 封装 inject_brew_shellenv_if_needed 对应的独立处理逻辑。
inject_brew_shellenv_if_needed() {
  local brew_bin="$1"
  local profile_file shellenv_cmd

  profile_file="$(get_shell_profile_file)"
  shellenv_cmd="eval \"\$(${brew_bin} shellenv)\""

  append_block_if_missing "$profile_file" "homebrew-shellenv" "$shellenv_cmd"
  apply_shellenv_now "$shellenv_cmd"
}
# ================================== Homebrew 检查/安装/升级 ==================================
# 执行对应的环境配置或同步处理。
install_homebrew() {
  local arch brew_bin

  arch="$(get_cpu_arch)"
  warn_echo "未检测到 Homebrew，开始安装...（架构：$arch）"

  if ! command_exists curl; then
    error_echo "安装 Homebrew 依赖 curl，但当前系统未检测到 curl"
    exit 1
  fi

  jobs_brew_install_or_exit

  if [[ "$arch" == "arm64" ]]; then
    brew_bin="${JOBS_HOMEBREW_BIN:-$(jobs_brew_find 2>/dev/null || true)}"
  else
    brew_bin="${JOBS_HOMEBREW_BIN:-$(jobs_brew_find 2>/dev/null || true)}"
  fi

  [[ -x "$brew_bin" ]] || {
    error_echo "Homebrew 安装后仍未找到 brew，可执行文件不存在：$brew_bin"
    exit 1
  }

  inject_brew_shellenv_if_needed "$brew_bin"

  if ! command_exists brew; then
    error_echo "Homebrew 安装后 brew 仍不可用"
    exit 1
  fi

  success_echo "Homebrew 安装完成：$(command -v brew)"
}
# 执行对应的环境配置或同步处理。
upgrade_brew_if_needed() {
  if prompt_optional_upgrade "brew"; then
    note_echo "开始执行 brew update"
    brew update
    note_echo "开始执行 brew upgrade"
    brew upgrade
    note_echo "开始执行 brew cleanup"
    brew cleanup || true
    note_echo "开始执行 brew doctor"
    brew doctor || warn_echo "brew doctor 有告警，请按提示自行处理"
    success_echo "brew 升级完成"
  else
    gray_echo "已跳过 brew 升级"
  fi
}
# 检查当前运行条件是否满足后续流程要求。
ensure_brew() {
  print_divider
  bold_echo "第 1 步：检查 Homebrew"

  if ! ensure_brew_env; then
    install_homebrew
  else
    success_echo "已检测到 Homebrew：$(command -v brew)"
    inject_brew_shellenv_if_needed "$(detect_brew_bin)"
    upgrade_brew_if_needed
  fi

  ensure_brew_env || {
    error_echo "Homebrew 环境初始化失败"
    exit 1
  }
}
# ================================== 通用 brew 包检查/安装/升级 ==================================
# 封装 brew_install_or_upgrade_pkg 对应的独立处理逻辑。
brew_install_or_upgrade_pkg() {
  local command_name="$1"
  local brew_pkg_name="$2"
  local display_name="$3"

  print_divider
  bold_echo "检查 ${display_name}"

  if ! command_exists "$command_name"; then
    warn_echo "未检测到 ${display_name}，开始安装..."
    brew install "$brew_pkg_name"

    if ! command_exists "$command_name"; then
      error_echo "${display_name} 安装后仍不可用"
      exit 1
    fi

    success_echo "${display_name} 安装完成"
  else
    success_echo "已检测到 ${display_name}：$(command -v "$command_name")"
  fi

  case "$command_name" in
    python3) gray_echo "当前版本：$("$JOBS_PYTHON_BIN" --version 2>/dev/null || true)" ;;
    fzf)     gray_echo "当前版本：$(fzf --version 2>/dev/null || true)" ;;
  esac

  if prompt_optional_upgrade "$display_name"; then
    note_echo "开始升级 ${display_name} ..."
    brew upgrade "$brew_pkg_name" || true
    success_echo "${display_name} 升级流程已执行完毕"
  else
    gray_echo "已跳过 ${display_name} 升级"
  fi
}
# 检查当前运行条件是否满足后续流程要求。
ensure_python3() {
  jobs_mock_python_preflight readonly || return 1
}
# 检查当前运行条件是否满足后续流程要求。
ensure_fzf() {
  brew_install_or_upgrade_pkg "fzf" "fzf" "fzf"
}
# ================================== 目录与服务 ==================================
# 封装 cd_to_script_dir 对应的独立处理逻辑。
cd_to_script_dir() {
  cd "$SCRIPT_DIR"
  success_echo "已切换到脚本所在目录：$SCRIPT_DIR"
}
# 解析并返回后续流程需要的目标信息。
find_port_owner() {
  if command_exists lsof; then
    lsof -nP -iTCP:"$PORT" -sTCP:LISTEN 2>/dev/null || true
  fi
}
# 解析并返回后续流程需要的目标信息。
get_pid_from_file() {
  [[ -f "$PID_FILE" ]] || return 1
  local pid
  pid="$(cat "$PID_FILE" 2>/dev/null || true)"
  [[ -n "$pid" ]] || return 1
  printf "%s" "$pid"
}
# 检查当前运行条件是否满足后续流程要求。
is_pid_running() {
  local pid="$1"
  ps -p "$pid" >/dev/null 2>&1
}
# 检查当前运行条件是否满足后续流程要求。
is_server_running() {
  local pid=""

  if pid="$(get_pid_from_file)"; then
    if is_pid_running "$pid"; then
      return 0
    fi
    rm -f "$PID_FILE"
  fi

  return 1
}
# 检查当前运行条件是否满足后续流程要求。
check_port_available_for_new_server() {
  if command_exists lsof && lsof -nP -iTCP:"$PORT" -sTCP:LISTEN >/dev/null 2>&1; then
    if is_server_running; then
      warn_echo "后台服务已在运行，无需重复启动"
      return 1
    fi

    error_echo "端口 ${PORT} 已被其他进程占用，请先释放后再运行脚本"
    gray_echo "占用信息如下："
    find_port_owner | tee -a "$LOG_FILE" || true
    exit 1
  fi

  return 0
}
# 封装 wait_for_http_server_ready 对应的独立处理逻辑。
wait_for_http_server_ready() {
  local url="http://${HOST}:${PORT}/"
  local i

  for i in {1..30}; do
    if curl -fsS "$url" >/dev/null 2>&1; then
      return 0
    fi
    sleep 0.3
  done

  return 1
}
# 封装 start_local_http_server_detached 对应的独立处理逻辑。
start_local_http_server_detached() {
  local pid=""

  print_divider
  bold_echo "启动本地 HTTP 服务（后台模式）"

  if is_server_running; then
    pid="$(get_pid_from_file)"
    success_echo "后台服务已在运行：http://${HOST}:${PORT}（PID: ${pid}）"
    return 0
  fi

  check_port_available_for_new_server || return 0

  : > "$HTTP_LOG_FILE"
  note_echo "执行：nohup "$JOBS_PYTHON_BIN" -m http.server ${PORT} --bind ${HOST}"
  nohup "$JOBS_PYTHON_BIN" -m http.server "$PORT" --bind "$HOST" >"$HTTP_LOG_FILE" 2>&1 < /dev/null &
  pid=$!
  disown "$pid" 2>/dev/null || true
  echo "$pid" > "$PID_FILE"

  if ! wait_for_http_server_ready; then
    error_echo "本地 HTTP 服务启动失败"
    gray_echo "日志如下："
    cat "$HTTP_LOG_FILE" || true
    rm -f "$PID_FILE"
    exit 1
  fi

  success_echo "本地 HTTP 服务已后台启动：http://${HOST}:${PORT}（PID: ${pid}）"
  gray_echo "现在可以直接关闭这个终端，服务不会跟着退出"
}
# 封装 stop_local_http_server 对应的独立处理逻辑。
stop_local_http_server() {
  local pid=""

  print_divider
  bold_echo "停止本地 HTTP 服务"

  if ! pid="$(get_pid_from_file)"; then
    warn_echo "未找到 PID 文件，可能服务并不是由本脚本启动"
    return 0
  fi

  if ! is_pid_running "$pid"; then
    warn_echo "PID 文件存在，但进程已不在运行，现已清理 PID 文件"
    rm -f "$PID_FILE"
    return 0
  fi

  kill "$pid" >/dev/null 2>&1 || true
  sleep 0.5

  if is_pid_running "$pid"; then
    warn_echo "普通停止失败，尝试强制结束 PID: ${pid}"
    kill -9 "$pid" >/dev/null 2>&1 || true
  fi

  rm -f "$PID_FILE"
  success_echo "本地 HTTP 服务已停止"
}
# 封装 show_status 对应的独立处理逻辑。
show_status() {
  print_divider
  bold_echo "服务状态"

  if is_server_running; then
    local pid
    pid="$(get_pid_from_file)"
    success_echo "运行中：http://${HOST}:${PORT}（PID: ${pid}）"
    gray_echo "脚本目录：$SCRIPT_DIR"
    gray_echo "日志文件：$LOG_FILE"
    gray_echo "HTTP 日志：$HTTP_LOG_FILE"
  else
    warn_echo "当前未运行"
  fi
}
# ================================== JSON 选择与 URL 处理 ==================================
# 解析并返回后续流程需要的目标信息。
get_json_search_root() {
  if [[ -d "$SCRIPT_DIR/$JSON_DIR_NAME" ]]; then
    printf "%s" "$SCRIPT_DIR/$JSON_DIR_NAME"
  else
    printf "%s" "$SCRIPT_DIR"
  fi
}
# 解析并返回后续流程需要的目标信息。
find_json_files() {
  local search_root relative_prefix

  search_root="$(get_json_search_root)"

  if [[ "$search_root" == "$SCRIPT_DIR/$JSON_DIR_NAME" ]]; then
    relative_prefix="$JSON_DIR_NAME/"
  else
    relative_prefix=""
  fi

  find "$search_root" -type f -name '*.json' ! -path '*/.git/*' | while IFS= read -r file; do
    file="${file#"$search_root"/}"
    printf "%s%s\n" "$relative_prefix" "$file"
  done | sort
}
# 检查当前运行条件是否满足后续流程要求。
ensure_json_files_exist() {
  if [[ -z "$(find_json_files)" ]]; then
    warn_echo "未找到任何 JSON 文件"

    if [[ -d "$SCRIPT_DIR/$JSON_DIR_NAME" ]]; then
      gray_echo "已检测到目录：$SCRIPT_DIR/$JSON_DIR_NAME，但里面没有 .json 文件"
    else
      gray_echo "未检测到目录：$SCRIPT_DIR/$JSON_DIR_NAME，已回退为扫描脚本所在目录"
    fi

    exit 0
  fi
}
# 封装 pick_json_file 对应的独立处理逻辑。
pick_json_file() {
  local selected_json

  ensure_json_files_exist

  selected_json="$(find_json_files | fzf --prompt='请选择一个 JSON 文件: ' --height=40% --reverse)"

  if [[ -z "$selected_json" ]]; then
    warn_echo "未选择任何 JSON 文件，脚本结束"
    exit 0
  fi

  printf "%s" "$selected_json"
}
# 封装 url_encode_with_python 对应的独立处理逻辑。
url_encode_with_python() {
  local raw="$1"
  "$JOBS_PYTHON_BIN" - <<'PY' "$raw"
import sys
import urllib.parse
print(urllib.parse.quote(sys.argv[1]))
PY
}
# 封装 open_url 对应的独立处理逻辑。
open_url() {
  local url="$1"

  if command_exists open; then
    open "$url"
  else
    error_echo "未检测到 open 命令，无法自动打开浏览器"
    return 1
  fi
}
# 封装 open_json_in_browser 对应的独立处理逻辑。
open_json_in_browser() {
  local json_file="$1"
  local encoded_path url

  encoded_path="$(url_encode_with_python "$json_file")"
  url="http://${HOST}:${PORT}/${encoded_path}"

  print_divider
  highlight_echo "你选择的是：$json_file"
  note_echo "浏览器即将打开：$url"

  open_url "$url"
  success_echo "浏览器已打开"
}
# ================================== 自述说明 ==================================
# 展示脚本用途和影响范围，并在执行前等待用户确认。
show_intro() {
  print_divider
  bold_echo "本脚本将执行以下流程：" | jobs_intro_style title
  log "1. 自述说明，并等待你回车" | jobs_intro_style body
  log "2. 内嵌预检 Homebrew：缺失时选路径安装，已有时更新本体与公式索引" | jobs_intro_style body
  log "3. 内嵌预检 Python：复用健康版本，不满足要求才安装或修复" | jobs_intro_style body
  log "4. 检查 fzf：没有就安装，有就可选升级" | jobs_intro_style body
  log "5. 切换到脚本所在目录" | jobs_intro_style body
  log "6. 后台启动本地服务：http://${HOST}:${PORT}" | jobs_intro_style body
  log "7. 优先从 jsons 文件夹里用 fzf 选择一个 json 文件；若 jsons 不存在则回退扫描脚本目录" | jobs_intro_style body
  log "8. 浏览器自动打开对应地址（已处理空格/中文等 URL 编码）" | jobs_intro_style body
  log "9. 脚本退出后服务仍保持运行，可直接关闭终端" | jobs_intro_style body
  log "10. 以后可用 start / stop / status / restart 管理服务" | jobs_intro_style body
  print_divider
  pause_enter
}
# 封装 show_runtime_summary 对应的独立处理逻辑。
show_runtime_summary() {
  print_divider
  success_echo "当前流程已完成，服务仍在后台运行"
  gray_echo "脚本目录：$SCRIPT_DIR"
  gray_echo "日志文件：$LOG_FILE"
  gray_echo "HTTP 日志：$HTTP_LOG_FILE"
  gray_echo "JSON 目录：$(get_json_search_root)"
  gray_echo "PID 文件：$PID_FILE"
  gray_echo "关闭终端是安全的；下次停止服务可运行：$(basename "$0") stop"
}
# 封装 show_usage 对应的独立处理逻辑。
show_usage() {
  print_divider
  bold_echo "用法"
  log "直接双击 / 直接运行：交互式启动并打开 JSON"
  log "$(basename "$0") start   -> 启动后台服务并交互选择 JSON"
  log "$(basename "$0") stop    -> 停止后台服务"
  log "$(basename "$0") status  -> 查看后台服务状态"
  log "$(basename "$0") restart -> 重启后台服务并交互选择 JSON"
}
# ================================== 主流程 ==================================
# 封装 main_start_flow 对应的独立处理逻辑。
main_start_flow() {
  show_intro
  ensure_brew
  ensure_python3
  ensure_fzf
  cd_to_script_dir
  start_local_http_server_detached

  local selected_json
  selected_json="$(pick_json_file)"
  open_json_in_browser "$selected_json"

  show_runtime_summary
}
# 打印脚本内置自述，并按运行入口决定是否等待用户确认。
show_script_intro_and_wait() {
  print -r -- '============================== 脚本内置自述 ==============================' | jobs_intro_style title
  print -r -- "Python 环境：确认后更新 Homebrew；缺失时选择安装路径，Python 不满足要求才修复。" | jobs_intro_style body
  print -r -- '脚本名称：【MacOS】Mock.command' | jobs_intro_style title
  print -r -- '核心用途：执行“Mock”对应的自动化任务。' | jobs_intro_style body
  print -r -- '影响范围：可能修改当前项目、用户环境或脚本指定的目标。' | jobs_intro_style body
  print -r -- '取消方式：确认前按 Ctrl+C 终止，不会继续执行后续业务。' | jobs_intro_style body
  print -r -- '============================================================================' | jobs_intro_style title
  if [[ ! -t 0 ]]; then
    print -u2 -r -- '当前没有可交互输入，请在终端中重新运行。'
    exit 1
  fi
  read -r "?👉 已了解脚本用途与影响，按回车继续；按 Ctrl+C 取消：" _ || exit 1
}
# 执行入口下沉后的完整业务流程和控制逻辑。
run_main_business_flow() {
  # 检查当前步骤所需的环境、路径或输入条件。
  require_macos
  # 检查当前步骤所需的环境、路径或输入条件。
  require_basic_commands

  # 执行当前流程中的独立业务步骤：处理当前语句。
  : > "$LOG_FILE"

  # 初始化当前流程后续步骤需要使用的变量。
  local action="${1:-start}"

  # 根据当前条件选择对应的执行分支。
  case "$action" in
    # 执行当前流程中的独立业务步骤：start。
    start)
      # 执行当前流程中的独立业务步骤：main_start_flow。
      main_start_flow
      ;;
    # 执行当前流程中的独立业务步骤：stop。
    stop)
      # 执行当前流程中的独立业务步骤：stop_local_http_server。
      stop_local_http_server
      ;;
    # 执行当前流程中的独立业务步骤：status。
    status)
      # 执行当前流程中的独立业务步骤：show_status。
      show_status
      ;;
    # 执行当前流程中的独立业务步骤：restart。
    restart)
      # 执行当前流程中的独立业务步骤：stop_local_http_server。
      stop_local_http_server || true
      # 执行当前流程中的独立业务步骤：main_start_flow。
      main_start_flow
      ;;
    # 执行当前流程中的独立业务步骤：help。
    help|-h|--help)
      # 执行当前流程中的独立业务步骤：show_usage。
      show_usage
      ;;
    # 执行当前流程中的独立业务步骤：处理当前语句。
    *)
      # 执行当前流程中的独立业务步骤：error_echo。
      error_echo "不支持的参数：$action"
      # 执行当前流程中的独立业务步骤：show_usage。
      show_usage
      # 执行当前流程中的独立业务步骤：exit。
      exit 1
      ;;
  esac
}
# 编排脚本的高层业务流程。
# 初始化脚本运行环境，并集中承载原有的顶层执行逻辑。
initialize_script_runtime() {
  set -euo pipefail
}
# 编排脚本的高层业务流程。
# 入口失败在阶段内终止；source 业务继续使用可返回的预检函数。
jobs_mock_python_prepare_runtime() {
  jobs_mock_python_preflight confirmed || exit 1
}


main() {
  show_script_intro_and_wait # 展示脚本内置自述，并按运行入口完成防误触确认。
  jobs_mock_python_prepare_runtime # 业务确认后使用内嵌函数准备 Homebrew Python。
  initialize_script_runtime # 初始化 Shell 选项、日志、依赖和入口运行状态。
  run_main_business_flow "$@" # 执行入口下沉后的完整业务流程。
}

main "$@"
