#!/bin/zsh
# shell: zsh
# 脚本自述：
# - 脚本名称：【MacOS】连接时间胶囊.command
# - 核心用途：回车确认后连接 Data，显示局域网 IPv4 与实际 SMB 会话；存在迁移配置时装载缓存工作卷。
# - 影响范围：写私有临时日志，更新受管 Data 链接，留存残留空挂载标记并装载既有镜像，不迁移数据。
# - 运行提示：直接按回车开始连接；认证仍由系统窗口处理，等待期间可 Ctrl+C 取消。

SERVER_HOST='AirPort.local'
SERVER_URL="smb://${SERVER_HOST}/Data"
SCRIPT_PATH=''
SCRIPT_DIR=''
SCRIPT_BASENAME=''
LOG_FILE=''
SUPPORT_DIR=''
CONFIG_FILE=''
CACHE_VOLUME=''
DATA_LINK=''
RUNTIME_DIR=''
RUNTIME_READY=0
RUNTIME_FINISHED=0
COMMAND_OUT=''
COMMAND_ERR=''
COMMAND_PID=''
TEMP_DATA_LINK=''
CONFIG_ACTIVE=0
STORAGE_TOKEN=''
CACHE_UUID=''
CACHE_IMAGE_NAME='JobsCache.dmg'
SHARE_ROOT=''

# 判断当前输出是否支持终端颜色。
supports_color() {
    [[ -t 1 && -n "${TERM:-}" && "${TERM:-}" != dumb && -z "${NO_COLOR+x}" ]]
}
# 先展示用途，再等待交互终端确认。
show_script_intro_and_wait() {
    local answer=''
    if supports_color; then
        printf '\033[1;31m连接时间胶囊\033[0m\n'
        printf '\033[0;34m回车后连接；有迁移配置时验证共享和缓存工作卷。\033[0m\n'
        printf '\033[0;34m连接成功后，终端和日志显示设备局域网 IPv4 与完整 SMB 会话详情。\033[0m\n'
        printf '\033[0;34m查找共享最多等待120秒，可按 Ctrl+C 取消；不会强制推出或绕过锁定。\033[0m\n'
        printf '\033[0;34m日志位于系统临时目录，脚本不读取或保存密码。\033[0m\n'
        printf '\033[0;34m仅有系统空挂载标记时先留存再重建挂载点；其它本地内容保留并停止。\033[0m\n'
        printf '目标：\033[32;4m%s\033[0m\n' "$SERVER_URL"
    else
        printf '%s\n' '连接时间胶囊' '回车后连接；有迁移配置时验证共享和缓存工作卷。' \
            '连接成功后，终端和日志显示设备局域网 IPv4 与完整 SMB 会话详情。' \
            '查找共享最多等待120秒，可按 Ctrl+C 取消；不会强制推出或绕过锁定。' \
            '日志位于系统临时目录，脚本不读取或保存密码。' \
            '仅有系统空挂载标记时先留存再重建挂载点；其它本地内容保留并停止。' "目标：$SERVER_URL"
    fi
    if [[ ! -t 0 ]]; then
        printf '%s\n' '请在交互终端运行并按回车确认。' >&2
        return 2
    fi
    if supports_color; then
        printf '\033[1;36m开始连接时间胶囊\033[0m？[\033[1;32m直接回车连接\033[0m / \033[1;31m输入任意内容后回车取消\033[0m]：'
    else
        printf '%s' '开始连接时间胶囊？[直接回车连接 / 输入任意内容后回车取消]：'
    fi
    if ! IFS= read -r answer || [[ -n "$answer" ]]; then
        printf '%s\n' '已取消连接。'
        return 130
    fi
}
# 从实际脚本位置初始化路径，并建立本次私有日志。
initialize_runtime() {
    setopt NO_NOMATCH
    umask 077
    SCRIPT_PATH="${${(%):-%x}:A}"
    SCRIPT_DIR="${SCRIPT_PATH:h}"
    SCRIPT_BASENAME="${SCRIPT_PATH:t:r}"
    LOG_FILE="$(/usr/bin/mktemp "${TMPDIR:-/tmp}/${SCRIPT_BASENAME}.XXXXXXXX")" || {
        printf '%s\n' '错误：无法创建私有日志。' >&2
        exit 1
    }
    RUNTIME_DIR="$(/usr/bin/mktemp -d "${TMPDIR:-/tmp}/JobsTimeCapsule.connect.XXXXXXXX")" || fail 1 '无法创建私有运行目录。'
    COMMAND_OUT="${RUNTIME_DIR}/command.out"
    COMMAND_ERR="${RUNTIME_DIR}/command.err"
    SUPPORT_DIR="${HOME}/Library/Application Support/JobsTimeCapsule"
    CONFIG_FILE="${SUPPORT_DIR}/migration.json"
    DATA_LINK="${SUPPORT_DIR}/Data"
    CACHE_VOLUME="${SUPPORT_DIR}/CacheVolume"
    RUNTIME_READY=1
    trap 'fail 130 "已取消；未报告工作卷就绪，请按系统实际状态确认连接。"' INT
    trap 'fail 143 "连接流程已终止。"' TERM HUP
    log_message "日志：$LOG_FILE" || exit 1
}
# 同步输出状态与纯文本日志，不记录认证信息。
log_message() {
    local message="$1" green_suffix="${2:-}"
    if [[ -n "$green_suffix" ]] && supports_color; then
        printf '%s\033[32m%s\033[0m\n' "$message" "$green_suffix" || return 1
    elif supports_color && [[ "$message" == *"$SERVER_URL"* ]]; then
        printf '%s\033[32;4m%s\033[0m%s\n' "${message%%"$SERVER_URL"*}" "$SERVER_URL" "${message#*"$SERVER_URL"}" || return 1
    else
        printf '%s%s\n' "$message" "$green_suffix" || return 1
    fi
    printf '%s%s\n' "$message" "$green_suffix" >> "$LOG_FILE"
}
# 明确显示失败并保留调用方的真实非零退出码。
fail() {
    local result_code="$1"
    shift
    (( result_code > 0 && result_code < 256 )) || result_code=1
    if [[ -n "$LOG_FILE" ]]; then
        log_message "错误：$*；退出码：$result_code；日志：$LOG_FILE" || true
    else
        printf '错误：%s；退出码：%s\n' "$*" "$result_code" >&2
    fi
    exit "$result_code"
}
# 清理仅本轮创建的临时对象，保留日志和原退出码。
finish_runtime() {
    local result_code="$1"
    if [[ -n "$COMMAND_PID" ]]; then
        kill -TERM "$COMMAND_PID" 2>/dev/null || true
    fi
    if [[ -n "$TEMP_DATA_LINK" && -L "$TEMP_DATA_LINK" ]]; then
        /bin/rm -f "$TEMP_DATA_LINK" 2>/dev/null || true
    fi
    if [[ -n "$RUNTIME_DIR" && -d "$RUNTIME_DIR" ]]; then
        /bin/rm -f "${RUNTIME_DIR}/command.out" "${RUNTIME_DIR}/command.err" "${RUNTIME_DIR}/cache-info.plist" 2>/dev/null || true
        /bin/rmdir "$RUNTIME_DIR" 2>/dev/null || true
    fi
    log_message "流程结束，退出码：$result_code；日志：$LOG_FILE" || true
    return "$result_code"
}
# 仅在整个主Shell退出时清理一次，函数返回及命令替换不触发清理。
TRAPEXIT() {
    local result_code=$?
    (( ZSH_SUBSHELL == 0 )) || return "$result_code"
    if (( RUNTIME_READY == 1 && RUNTIME_FINISHED == 0 )); then
        RUNTIME_FINISHED=1
        finish_runtime "$result_code"
    fi
    return "$result_code"
}
# 有界执行原生命令，输出只进入本轮私有临时文件。
run_bounded() {
    local timeout_seconds="$1"
    shift
    local deadline=$(( SECONDS + timeout_seconds )) result_code=0
    "$@" > "$COMMAND_OUT" 2> "$COMMAND_ERR" </dev/null &
    COMMAND_PID=$!
    while kill -0 "$COMMAND_PID" 2>/dev/null; do
        if (( SECONDS >= deadline )); then
            kill -TERM "$COMMAND_PID" 2>/dev/null || true
            /bin/sleep 0.2
            kill -KILL "$COMMAND_PID" 2>/dev/null || true
            COMMAND_PID=''
            return 124
        fi
        /bin/sleep 0.2
    done
    wait "$COMMAND_PID"
    result_code=$?
    COMMAND_PID=''
    return "$result_code"
}
# 仅把已声明原生命令的错误输出附入日志，不转储配置或挂载表。
append_command_error() {
    if [[ -s "$COMMAND_ERR" ]]; then
        /bin/cat "$COMMAND_ERR" >> "$LOG_FILE" || fail 1 '无法写入命令错误日志。'
    fi
}
# 确认原生入口存在，不安装额外依赖。
check_environment() {
    local command_path=''
    [[ -x /usr/bin/open ]] || fail 69 '系统open命令不可用。'
    if [[ ! -e "$CONFIG_FILE" && ! -L "$CONFIG_FILE" ]]; then
        return 0
    fi
    for command_path in /usr/bin/open /usr/bin/plutil /usr/sbin/diskutil /sbin/mount /usr/bin/head /usr/bin/stat /usr/bin/mktemp /bin/rmdir /bin/ln /bin/mv; do
        [[ -x "$command_path" ]] || fail 69 "系统命令不可用：$command_path"
    done
}
# 读取既有身份字段及白名单镜像名；缺配置时保持原连接方式。
load_configuration() {
    if [[ ! -e "$CONFIG_FILE" && ! -L "$CONFIG_FILE" ]]; then
        return 0
    fi
    [[ -d "$SUPPORT_DIR" && ! -L "$SUPPORT_DIR" ]] || fail 65 '支持目录必须是本机真实目录。'
    [[ -f "$CONFIG_FILE" && ! -L "$CONFIG_FILE" ]] || fail 65 '迁移配置必须是普通文件。'
    local result_code=0 config_owner='' image_name_type=''
    config_owner="$(/usr/bin/stat -f '%u' "$CONFIG_FILE" 2>> "$LOG_FILE")" || fail $? '无法读取迁移配置归属。'
    [[ "$config_owner" == "$EUID" ]] || fail 65 '迁移配置不属于当前用户。'
    STORAGE_TOKEN="$(/usr/bin/plutil -extract storage_token raw -expect string -o - "$CONFIG_FILE" 2>> "$LOG_FILE")"
    result_code=$?
    (( result_code == 0 )) || fail "$result_code" '无法读取 storage_token。'
    CACHE_UUID="$(/usr/bin/plutil -extract cache_volume_uuid raw -expect string -o - "$CONFIG_FILE" 2>> "$LOG_FILE")"
    result_code=$?
    (( result_code == 0 )) || fail "$result_code" '无法读取 cache_volume_uuid。'
    if image_name_type="$(/usr/bin/plutil -type cache_image_name "$CONFIG_FILE" 2>/dev/null)"; then
        [[ "$image_name_type" == string ]] || fail 65 'cache_image_name必须是字符串。'
        CACHE_IMAGE_NAME="$(/usr/bin/plutil -extract cache_image_name raw -expect string -o - "$CONFIG_FILE" 2>> "$LOG_FILE")" || fail $? '无法读取 cache_image_name。'
    fi
    case "$CACHE_IMAGE_NAME" in
        JobsCache.dmg|JobsCache.asif) ;;
        *) fail 65 '缓存镜像名不在允许清单中，拒绝其它文件名或路径。' ;;
    esac
    [[ "$STORAGE_TOKEN" =~ '^[A-Za-z0-9._-]+$' ]] || fail 65 '共享身份标记格式无效。'
    (( ${#STORAGE_TOKEN} >= 8 && ${#STORAGE_TOKEN} <= 256 )) || fail 65 '共享身份标记长度无效。'
    [[ "$CACHE_UUID" =~ '^[[:xdigit:]]{8}(-[[:xdigit:]]{4}){3}-[[:xdigit:]]{12}$' ]] || fail 65 '缓存卷 UUID 格式无效。'
    CACHE_UUID="${CACHE_UUID:u}"
    CONFIG_ACTIVE=1
    log_message '已读取既有迁移配置；身份标记不会写入日志。' || fail 1 '日志写入失败。'
}
# 交给访达处理认证，但不把请求提交当作挂载成功。
open_shared_disk() {
    log_message "连接目标：$SERVER_URL" || fail 1 '日志写入失败。'
    run_bounded 10 /usr/bin/open "$SERVER_URL"
    local result_code=$?
    if (( result_code != 0 )); then
        append_command_error
        fail "$result_code" '连接请求未能提交。'
    fi
    log_message '连接请求已交给访达，尚未据此认定已挂载；可在系统认证窗口取消。' || fail 1 '日志写入失败。'
}
# 查询设备主机名对应的局域网 IPv4，忽略自动分配的链路本地地址。
log_lan_ipv4() {
    local ipv4_addresses=''
    if run_bounded 3 /usr/bin/dscacheutil -q host -a name "$SERVER_HOST"; then
        ipv4_addresses="$(/usr/bin/awk '$1 == "ip_address:" && $2 !~ /^(127[.]|169[.]254[.])/ && !seen[$2]++ { print $2 }' "$COMMAND_OUT")"
    fi
    if [[ -n "$ipv4_addresses" ]]; then
        log_message "设备局域网 IPv4（$SERVER_HOST 解析）：" "${ipv4_addresses//$'\n'/、}" || fail 1 '日志写入失败。'
    else
        log_message "警告：暂未解析到 $SERVER_HOST 的局域网 IPv4。" || fail 1 '日志写入失败。'
    fi
}
# 在真实挂载点查询 SMB 会话，诊断失败时仍可继续连接流程。
log_smb_statistics() {
    local result_code=0
    log_message "SMB 会话详情：smbutil statshares -m ${(q)SHARE_ROOT}" || fail 1 '日志写入失败。'
    run_bounded 5 /usr/bin/smbutil statshares -m "$SHARE_ROOT"
    result_code=$?
    if (( result_code == 0 )) && [[ -s "$COMMAND_OUT" ]]; then
        log_message "$(< "$COMMAND_OUT")" || fail 1 '日志写入失败。'
    else
        log_message "警告：未取得 SMB 会话详情，挂载点：$SHARE_ROOT，查询退出码：$result_code。" || fail 1 '日志写入失败。'
        append_command_error
    fi
}
# 从真实 smbfs 挂载查找目标，迁移模式还要求共享身份标记匹配。
find_matching_share() {
    local deadline="$1" remaining=0 result_code=0 mount_snapshot='' mount_line='' candidate='' marker=''
    local mount_source='' target="${SERVER_URL#smb://}"
    local -a matches=() candidates=("${SUPPORT_DIR}/DataMount" /Volumes/*(N))
    remaining=$(( deadline - SECONDS ))
    (( remaining > 0 )) || return 124
    run_bounded "$(( remaining < 3 ? remaining : 3 ))" /sbin/mount -t smbfs
    result_code=$?
    if (( result_code != 0 )); then
        append_command_error
        if (( CONFIG_ACTIVE == 0 )); then
            log_message "警告：无法查询实际 SMB 挂载，查询退出码：$result_code。" || fail 1 '日志写入失败。'
            return 74
        fi
        fail "$result_code" '无法查询真实SMB挂载状态。'
    fi
    mount_snapshot="$(< "$COMMAND_OUT")"
    for candidate in "${candidates[@]}"; do
        [[ ! -L "$candidate" ]] || continue
        mount_source=''
        for mount_line in "${(@f)mount_snapshot}"; do
            if [[ "$mount_line" == *" on ${candidate} (smbfs"* ]]; then
                mount_source="${mount_line%" on ${candidate} (smbfs"*}"
                break
            fi
        done
        [[ -n "$mount_source" ]] || continue
        if (( CONFIG_ACTIVE == 0 )); then
            mount_source="${mount_source#//}"
            mount_source="${mount_source##*@}"
            [[ "${mount_source:l}" == "${target:l}" ]] && matches+=("$candidate")
            continue
        fi
        [[ ! -L "${candidate}/JobsMacStorage" && ! -L "${candidate}/JobsMacStorage/.jobs-storage-token" ]] || continue
        remaining=$(( deadline - SECONDS ))
        (( remaining > 0 )) || return 124
        if run_bounded "$(( remaining < 3 ? remaining : 3 ))" /usr/bin/head -c 513 "${candidate}/JobsMacStorage/.jobs-storage-token"; then
            marker="$(< "$COMMAND_OUT")"
            [[ "$marker" == "$STORAGE_TOKEN" ]] && matches+=("$candidate")
        fi
    done
    (( ${#matches} < 2 )) || return 73
    (( ${#matches} == 1 )) || return 1
    SHARE_ROOT="${matches[1]}"
    return 0
}
# 在最多120秒内等待目标共享，显示进度并允许取消。
wait_for_share() {
    local started=$SECONDS deadline=$(( SECONDS + 120 )) result_code=0 last_notice=-10
    while (( SECONDS < deadline )); do
        find_matching_share "$deadline"
        result_code=$?
        if (( result_code == 0 )); then
            log_message "已找到唯一匹配的 SMB 挂载：$SHARE_ROOT" || fail 1 '日志写入失败。'
            return 0
        fi
        (( result_code != 74 )) || return 1
        if (( CONFIG_ACTIVE == 0 && result_code == 73 )); then
            log_message '警告：同一共享有多个挂载点，本次跳过 SMB 会话统计。' || fail 1 '日志写入失败。'
            return 1
        fi
        (( result_code != 73 )) || fail 73 '存在多个身份标记相同的共享，保留现状并停止。'
        if (( SECONDS - started - last_notice >= 5 )); then
            log_message "等待目标共享（$(( SECONDS - started ))/120秒，可按 Ctrl+C 取消）……" || fail 1 '日志写入失败。'
            last_notice=$(( SECONDS - started ))
        fi
        (( SECONDS < deadline )) && /bin/sleep 0.2
    done
    if (( CONFIG_ACTIVE == 0 )); then
        log_message '警告：120秒内未看到目标共享挂载，暂无法打印 SMB 会话详情，请检查访达连接。' || fail 1 '日志写入失败。'
        return 1
    fi
    fail 124 '120秒内未发现身份标记匹配的真实 SMB 共享；请检查系统认证和网络。'
}
# 原子更新本脚本受管的 Data 符号链接，保留同名真实对象。
update_data_link() {
    if [[ -e "$DATA_LINK" && ! -L "$DATA_LINK" ]]; then
        fail 73 'Data入口已有同名非符号链接对象，已保留。'
    fi
    TEMP_DATA_LINK="${SUPPORT_DIR}/.Data.connect.$$.$RANDOM"
    [[ ! -e "$TEMP_DATA_LINK" && ! -L "$TEMP_DATA_LINK" ]] || fail 73 '临时Data入口发生名称冲突。'
    /bin/ln -s "$SHARE_ROOT" "$TEMP_DATA_LINK" || fail $? '无法建立受管Data入口。'
    if [[ -e "$DATA_LINK" && ! -L "$DATA_LINK" ]]; then
        fail 73 'Data入口已被其它操作改变，原对象保留。'
    fi
    /bin/mv -f -h "$TEMP_DATA_LINK" "$DATA_LINK" || fail $? '无法原子更新Data入口。'
    TEMP_DATA_LINK=''
    log_message "受管Data入口已指向核实后的共享：$SHARE_ROOT" || fail 1 '日志写入失败。'
}
# 检查指定路径是否是实际挂载点，不依赖本地目录是否存在。
is_mount_point() {
    local target="$1" result_code=0 mount_line='' snapshot=''
    run_bounded 5 /sbin/mount
    result_code=$?
    if (( result_code != 0 )); then
        append_command_error
        fail "$result_code" '无法查询实际挂载点。'
    fi
    snapshot="$(< "$COMMAND_OUT")"
    for mount_line in "${(@f)snapshot}"; do
        [[ "$mount_line" == *" on ${target} ("* ]] && return 0
    done
    return 1
}
# 核对实际挂载点、卷UUID与卷内标记，绝不凭目录存在报告成功。
verify_cache_identity() {
    local result_code=0 actual_uuid='' actual_mount='' marker=''
    run_bounded 15 /usr/sbin/diskutil info -plist "$CACHE_VOLUME"
    result_code=$?
    if (( result_code != 0 )); then
        append_command_error
        fail "$result_code" '无法读取缓存卷身份。'
    fi
    /bin/cp "$COMMAND_OUT" "${RUNTIME_DIR}/cache-info.plist" || fail $? '无法保存本轮卷身份结果。'
    actual_mount="$(/usr/bin/plutil -extract MountPoint raw -expect string -o - "${RUNTIME_DIR}/cache-info.plist" 2>> "$LOG_FILE")" || fail $? '缓存挂载点信息缺失。'
    actual_uuid="$(/usr/bin/plutil -extract VolumeUUID raw -expect string -o - "${RUNTIME_DIR}/cache-info.plist" 2>> "$LOG_FILE")" || fail $? '缓存卷UUID缺失。'
    [[ "$actual_mount" == "$CACHE_VOLUME" ]] || fail 73 'CacheVolume不是预期的实际挂载点，已保留现状。'
    [[ "${actual_uuid:u}" == "$CACHE_UUID" ]] || fail 73 'CacheVolume已挂载其它UUID的卷，已保留且不强制推出。'
    [[ ! -L "${CACHE_VOLUME}/.jobs-cache-token" ]] || fail 73 '缓存卷身份标记不能是符号链接。'
    run_bounded 10 /usr/bin/head -c 513 "${CACHE_VOLUME}/.jobs-cache-token" || fail $? '缓存卷身份标记不可读取。'
    marker="$(< "$COMMAND_OUT")"
    [[ "$marker" == "$STORAGE_TOKEN" ]] || fail 73 '缓存卷身份标记不匹配，已保留现状。'
}
# 仅留存未挂载目录中的系统空标记；用rmdir确保其它内容不会被移走或删除。
preserve_stale_mount_marker() {
    local marker_path="${CACHE_VOLUME}/.autodiskmounted" backup_dir=''
    local directory_identity='' marker_identity='' current_identity='' support_device=''
    local -a existing_entries=("$CACHE_VOLUME"/*(DN))
    (( ${#existing_entries} == 1 )) && [[ "${existing_entries[1]}" == "$marker_path" ]] || \
        fail 73 "CacheVolume是非空本地目录，已保留且不会覆盖：$CACHE_VOLUME"
    [[ -f "$marker_path" && ! -L "$marker_path" && ! -s "$marker_path" && -O "$marker_path" && -O "$CACHE_VOLUME" ]] || \
        fail 73 'CacheVolume中的挂载标记不是当前用户的普通空文件，已保留。'
    support_device="$(/usr/bin/stat -f '%d' "$SUPPORT_DIR" 2>> "$LOG_FILE")" || fail $? '无法核对支持目录设备。'
    directory_identity="$(/usr/bin/stat -f '%d:%i' "$CACHE_VOLUME" 2>> "$LOG_FILE")" || fail $? '无法核对旧挂载目录。'
    [[ "${directory_identity%%:*}" == "$support_device" ]] || fail 73 'CacheVolume不在支持目录所在设备，已保留。'
    marker_identity="$(/usr/bin/stat -f '%d:%i:%u:%z:%l:%m:%c' "$marker_path" 2>> "$LOG_FILE")" || fail $? '无法核对空挂载标记。'
    backup_dir="$(/usr/bin/mktemp -d "${SUPPORT_DIR}/CacheMountBackup.XXXXXXXX")" || fail $? '无法创建挂载标记留存目录。'
    log_message "检测到残留空挂载标记；留存位置：$backup_dir" || fail 1 '日志写入失败。'
    is_mount_point "$CACHE_VOLUME" && fail 73 'CacheVolume已被其它操作挂载，停止标记处理。'
    [[ -d "$CACHE_VOLUME" && ! -L "$CACHE_VOLUME" ]] || fail 73 'CacheVolume类型已改变，保留现状并停止。'
    current_identity="$(/usr/bin/stat -f '%d:%i' "$CACHE_VOLUME" 2>> "$LOG_FILE")" || fail $? '无法复核旧挂载目录。'
    [[ "$current_identity" == "$directory_identity" ]] || fail 73 'CacheVolume目录已被替换，保留现状并停止。'
    existing_entries=("$CACHE_VOLUME"/*(DN))
    (( ${#existing_entries} == 1 )) && [[ "${existing_entries[1]}" == "$marker_path" ]] || \
        fail 73 'CacheVolume内容已改变，保留现状并停止。'
    [[ -f "$marker_path" && ! -L "$marker_path" && ! -s "$marker_path" ]] || fail 73 '空挂载标记类型或内容已改变，已保留。'
    current_identity="$(/usr/bin/stat -f '%d:%i:%u:%z:%l:%m:%c' "$marker_path" 2>> "$LOG_FILE")" || fail $? '无法复核空挂载标记。'
    [[ "$current_identity" == "$marker_identity" ]] || fail 73 '空挂载标记已被替换或修改，已保留。'
    /bin/mv -n -h "$marker_path" "${backup_dir}/.autodiskmounted" || fail $? "无法留存空挂载标记；留存位置：$backup_dir"
    [[ ! -e "$marker_path" && ! -L "$marker_path" && -f "${backup_dir}/.autodiskmounted" ]] || \
        fail 73 "空挂载标记留存结果异常；保留现状：$backup_dir"
    /bin/rmdir "$CACHE_VOLUME" 2>> "$LOG_FILE" || fail 73 "旧挂载目录未能移除，可能出现新内容或已挂载；已保留，标记位于：$backup_dir"
    log_message '残留空挂载标记已留存，空挂载目录已移除；继续由系统建立挂载点。' || fail 1 '日志写入失败。'
}
# 复用身份正确的卷，或只装载既有缓存镜像；不覆盖本地数据。
ensure_cache_volume() {
    local result_code=0 image_path="${SHARE_ROOT}/JobsMacStorage/${CACHE_IMAGE_NAME}"
    local -a existing_entries=()
    [[ ! -L "$CACHE_VOLUME" ]] || fail 73 'CacheVolume不能是符号链接，现有对象已保留。'
    is_mount_point "$CACHE_VOLUME"
    result_code=$?
    if (( result_code == 0 )); then
        verify_cache_identity
        return 0
    fi
    [[ -f "$image_path" && ! -L "$image_path" ]] || fail 66 '既有缓存镜像缺失或不是普通文件，不会编造或创建。'
    if [[ -e "$CACHE_VOLUME" ]]; then
        [[ -d "$CACHE_VOLUME" ]] || fail 73 'CacheVolume已有同名非目录对象，已保留。'
        existing_entries=("$CACHE_VOLUME"/*(DN))
        if (( ${#existing_entries} != 0 )); then
            preserve_stale_mount_marker
        fi
    fi
    log_message '正在装载既有缓存工作卷；不强制推出、不绕过锁定，可按 Ctrl+C 取消。' || fail 1 '日志写入失败。'
    run_bounded 120 /usr/sbin/diskutil image attach --mountPoint "$CACHE_VOLUME" --mountOptions owners,nosuid,nodev "$image_path"
    result_code=$?
    if (( result_code != 0 )); then
        append_command_error
        if (( result_code == 124 )); then
            log_message '装载命令等待超时；正在复核系统是否已经完成挂载。' || fail 1 '日志写入失败。'
            if is_mount_point "$CACHE_VOLUME"; then
                verify_cache_identity
                return 0
            fi
            fail 124 '120秒内未确认缓存镜像装载；系统请求可能仍在处理，稍后再次运行核验。'
        fi
        fail "$result_code" '缓存镜像装载失败，请按系统提示处理；现有对象已保留。'
    fi
    verify_cache_identity
}
# 按有无既有迁移配置连接，工作卷全部身份核验后才报告就绪。
connect_storage() {
    if (( CONFIG_ACTIVE == 0 )); then
        open_shared_disk
        if wait_for_share; then
            log_lan_ipv4
            log_smb_statistics
        fi
        return 0
    fi
    local lookup_result=0
    find_matching_share "$(( SECONDS + 5 ))"
    lookup_result=$?
    case "$lookup_result" in
        0) log_message "复用已核实的现有共享：$SHARE_ROOT" || fail 1 '日志写入失败。' ;;
        1)
            open_shared_disk
            wait_for_share
            ;;
        73) fail 73 '存在多个身份标记相同的共享，保留现状并停止。' ;;
        *) fail "$lookup_result" '无法在短时检查内核实已有共享，保留现状并停止。' ;;
    esac
    update_data_link
    ensure_cache_volume
    log_message '共享与缓存卷身份均已核实，工作卷已就绪；尚未代替程序使用验收。' || fail 1 '日志写入失败。'
    run_bounded 10 /usr/bin/open "$SHARE_ROOT"
    local result_code=$?
    if (( result_code != 0 )); then
        append_command_error
        fail "$result_code" '工作卷身份验证通过，但无法打开共享文件夹。'
    fi
    log_lan_ipv4
    log_smb_statistics
}
# 取得本次确认后初始化并连接。
main() {
    show_script_intro_and_wait || return $?
    initialize_runtime # 建立本轮私有日志并注册取消与退出处理。
    check_environment # 仅检查原生系统入口，不安装任何依赖。
    load_configuration # 缺少迁移配置时保留原连接行为。
    connect_storage # 连接并按既有配置核对共享和缓存卷身份。
}

main "$@"
