#!/bin/zsh
# 脚本自述：
# - 名称：键盘输入记录；Shell 管理流程，内嵌 Objective-C 调用 macOS 原生接口。
# - 用途：经确认后将当前登录会话输入的可见字符保存为纯文本，仅在本程序运行期间生效。
# - 影响：首次写入 ~/Downloads/JobsKeyboardRecorder 单文件；再次记录后转为同名目录并从 0 编号。
# - 写入：仅在启动脚本仍运行的有效会话内补齐记录路径；停止收尾只保存已打开的文件，不重建目录。
# - 控制：缓存原生状态 App，安装 ~/.local/bin/stop；必要时备份并补充 zsh 命令路径。
# - 限制：安全输入期间暂停；不还原输入法最终文字、粘贴、光标移动和删除后的文稿。
# - 开启：双击本脚本，回车准备、再次回车确认开始；记录期间保持启动终端运行。
# - 关闭：Ctrl+C、关闭启动终端、菜单停止或另一个终端输入 stop；脚本退出后不继续记录。
# - 依赖：macOS 10.15+、Apple Command Line Tools；不使用 Swift 或第三方运行时。

# 按终端能力输出自述颜色，重定向时保留纯文本。
intro_line() {
  local role="$1"
  local message="$2"
  local style='0;34'
  [[ "$role" == title ]] && style='1;31'
  if [[ -t 1 && -n "${TERM:-}" && "${TERM:-}" != dumb && -z "${NO_COLOR+x}" ]]; then
    printf '\033[%sm%s\033[0m\n' "$style" "$message"
  else
    print -r -- "$message"
  fi
}
# 首先解释用途和权限，确认前不创建文件或启动监听。
show_script_intro_and_wait() {
  intro_line title '⌨️ macOS 键盘输入记录'
  if [[ "$#" == 1 && "$1" == stop ]]; then
    intro_line body '停止当前记录并保存；此入口不启动新的监听。'
    return
  fi
  [[ "$#" == 0 ]] || { print -u2 -r -- '用法：双击本脚本开启；关闭时打开终端，输入 stop 后按回车。'; exit 1; }
  intro_line body '1、仅用于你有权操作的当前登录会话；记录期间必须保持启动终端运行。'
  intro_line body '2、仅保存按下时产生的文字，不重复保存松开事件；文件正文没有时间、键码或 JSON 字段。'
  intro_line body '3、首次生成“下载/JobsKeyboardRecorder”单文件；再次记录时转成同名文件夹，内放无后缀文件 0、1，后续继续递增。'
  intro_line body '   仅在脚本运行期间补齐缺失路径并追加；脚本退出、关闭终端或停止后，不再创建记录文件或目录。'
  intro_line body '4、首次编译需要 Apple Command Line Tools；不自动安装工具，不依赖 Swift。'
  intro_line body '5、需要手动授予“输入监控”；缺少权限时自动打开授权页面并标红加粗 App 路径；保存记录无需管理员密码。'
  intro_line body '6、保留空格、回车和制表符；忽略快捷键和非文字键，不还原光标移动、删除、输入法最终文字或粘贴内容；安全输入期间暂停。'
  intro_line body '7、记录可能包含私人文字；目录权限 700、文件权限 600，仅当前用户及管理员可读。'
  intro_line body '8、无网络上传、无开机启动；启动脚本持续等待，菜单栏保留记录状态与停止入口，不弹出浮窗。'
  intro_line body '9、开启：双击本脚本，首次回车准备程序，再次回车确认开始；输入任意字符取消，启动前可按 Ctrl+C 退出。'
  intro_line body '10、关闭：在启动终端按 Ctrl+C、关闭该终端，或使用菜单停止；另一个终端输入 stop 也可停止并保存。'
  intro_line body '11、原生 App 缓存在 ~/Library/Caches/JobsKeyboardRecorder；stop 安装到 ~/.local/bin，必要时备份并补充 zsh PATH。'
  if [[ ! -t 0 || ! -t 1 ]]; then
    print -u2 -r -- '✖ 请双击此 .command，或在可交互的终端中运行。'
    exit 1
  fi
  local answer=''
  IFS= read -r 'answer?按回车准备；Ctrl+C 取消：' || exit 1
  [[ -z "$answer" ]] || exit 0
}
# 初始化私有日志和可回收的构建目录。
initialize_runtime() {
  setopt NO_NOMATCH PIPE_FAIL
  umask 077
  SCRIPT_DIR="${${(%):-%x}:A:h}"
  SCRIPT_PATH="${${(%):-%x}:A}"
  SCRIPT_BASENAME="${SCRIPT_PATH:t:r}"
  local runtime_log_directory="${TMPDIR:-/tmp/}"
  /bin/mkdir -p "$runtime_log_directory" || { print -u2 -r -- "✖ 无法创建日志目录：${runtime_log_directory}"; exit 1; }
  LOG_FILE="$(/usr/bin/mktemp "${runtime_log_directory%/}/${SCRIPT_BASENAME}.XXXXXX")" || exit 1
  LOG_FILE="${LOG_FILE:A}"
  CACHE_DIR="${HOME}/Library/Caches/JobsKeyboardRecorder"
  RECORD_PATH="${HOME}/Downloads/JobsKeyboardRecorder"
  APP_PATH="${CACHE_DIR}/JobsKeyboardRecorder.app"
  HELPER="${APP_PATH}/Contents/MacOS/JobsKeyboardRecorder"
  CONTROL_PATH="${CACHE_DIR}/control.sock"
  STOP_COMMAND="${HOME}/.local/bin/stop"
  WORK_DIR=''
  RECORDER_STARTED=0
  RUNTIME_INITIALIZED=1
  trap 'exit 130' INT
  trap 'exit 129' HUP
  trap 'exit 143' TERM
}
# 补齐缺失的日志及父目录，已有文件必须属于当前用户且不能是链接。
ensure_shell_log_file() {
  local log_directory="${LOG_FILE:h}"
  [[ -n "$LOG_FILE" && ! -L "$LOG_FILE" && ! -L "$log_directory" ]] || return 1
  [[ "$log_directory" == "${log_directory:A}" ]] || return 1
  (umask 077; /bin/mkdir -p "$log_directory") || return 1
  local log_directory_owner="$(/usr/bin/stat -f '%u' "$log_directory")"
  [[ "$log_directory_owner" == "$UID" || ( "$log_directory_owner" == 0 && -k "$log_directory" ) ]] || return 1
  if [[ -e "$LOG_FILE" ]]; then
    [[ -f "$LOG_FILE" && "$(/usr/bin/stat -f '%u:%l' "$LOG_FILE")" == "${UID}:1" ]] || return 1
  fi
  (umask 077; : >>"$LOG_FILE") || return 1
  /bin/chmod 600 "$LOG_FILE"
}
# 将运行状态同步写入终端和日志，不将按键正文混入状态日志。
log() {
  if ! ensure_shell_log_file; then
    print -u2 -r -- "✖ 无法创建或写入运行状态日志：${LOG_FILE}"
    exit 1
  fi
  if ! print -r -- "$*" | /usr/bin/tee -a "$LOG_FILE"; then
    print -u2 -r -- "✖ 写入运行状态日志失败：${LOG_FILE}"
    exit 1
  fi
}
# 报告错误并中止后续业务。
fail() {
  log "✖ $*"
  if [[ -t 0 && -t 1 ]]; then
    local answer=''
    print -r -- '本次操作失败，请先处理上面的原因；终端显示“进程已完成”不表示记录启动成功。'
    IFS= read -r 'answer?按回车关闭本次失败提示：' || true
  fi
  exit 1
}
# 先撤销本次会话，再删除构建文件；退出不保留可继续记录的后台会话。
cleanup_runtime() {
  if [[ -n "$WORK_DIR" && -d "$WORK_DIR" && ! -L "$WORK_DIR" ]]; then
    local ticket="${WORK_DIR}/startup-ticket"
    /bin/rm -f "$ticket"
    if [[ "$RECORDER_STARTED" == 1 && -x "$HELPER" ]]; then
      local cleanup_seconds="$SECONDS"
      while (( SECONDS - cleanup_seconds < 3 )) && "$HELPER" --status "$CONTROL_PATH" "$ticket" >/dev/null 2>&1; do
        /bin/sleep 0.1
      done
    fi
    /bin/rm -f "${WORK_DIR}/JobsKeyboardRecorder.h" "${WORK_DIR}/JobsKeyboardRecorder.m" "${WORK_DIR}/JobsKeyboardRecorder" "${WORK_DIR}/stop"
    /bin/rmdir "$WORK_DIR" 2>/dev/null
  fi
}
# 使用全局退出函数，避免 zsh 将函数内部的 EXIT trap 提前消耗在函数返回时。
TRAPEXIT() {
  local script_exit_code="$?"
  if [[ "${RUNTIME_INITIALIZED:-0}" == 1 && "${ZSH_SUBSHELL:-0}" == 0 ]]; then
    cleanup_runtime
  fi
  return "$script_exit_code"
}
# 停止入口直接使用现有控制通道，不编译、不申请权限、不启动记录。
handle_control_command() {
  [[ "${1:-}" == stop ]] || return 0
  if [[ ! -x "$HELPER" ]]; then
    log '■ 当前没有运行中的新版记录器。'
    exit 0
  fi
  "$HELPER" --stop "$CONTROL_PATH"
  exit $?
}
# 校验实际使用的编译器和平台，不触发安装或升级。
check_environment() {
  ensure_shell_log_file || fail '无法准备运行状态日志。'
  [[ "$(/usr/bin/uname -s)" == Darwin ]] || fail '只支持 macOS。'
  (( UID != 0 )) || fail '请用当前登录用户运行。'
  CLANG="$(/usr/bin/xcrun --sdk macosx --find clang 2>>"$LOG_FILE")" || fail '未找到 clang，请先安装 Apple Command Line Tools：xcode-select --install'
  ensure_shell_log_file || fail '无法准备运行状态日志。'
  "$CLANG" --version >>"$LOG_FILE" 2>&1 || fail "编译器不可用：${CLANG}"
  ensure_shell_log_file || fail '无法准备运行状态日志。'
  SDK_ROOT="$(/usr/bin/xcrun --sdk macosx --show-sdk-path 2>>"$LOG_FILE")" || fail 'macOS SDK 不可用，请检查 xcode-select -p。'
  [[ -d "$SDK_ROOT" && -r "${SDK_ROOT}/System/Library/Frameworks/ApplicationServices.framework/Headers/ApplicationServices.h" &&
     -r "${SDK_ROOT}/System/Library/Frameworks/Carbon.framework/Headers/Carbon.h" ]] || fail "macOS SDK 缺少系统 Framework 头文件：${SDK_ROOT}"
  log "ℹ 运行状态日志：${LOG_FILE}"
  log "ℹ macOS SDK：${SDK_ROOT}"
}
# 输出原生程序的系统依赖与菜单栏控制接口。
emit_native_header() {
  /bin/cat <<'JOBS_NATIVE_HEADER'
//
//  JobsKeyboardRecorder.h
//  JobsKeyboardRecorder
//
//  Created by Jobs on 2026年10月15日，星期四.
//

#include <ApplicationServices/ApplicationServices.h>
#include <Carbon/Carbon.h>
#include <dirent.h>
#include <errno.h>
#include <fcntl.h>
#include <limits.h>
#include <libproc.h>
#include <poll.h>
#include <signal.h>
#include <stddef.h>
#include <stdbool.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/stat.h>
#include <sys/file.h>
#include <sys/proc.h>
#include <sys/socket.h>
#include <sys/un.h>
#include <time.h>
#include <unistd.h>
#import <AppKit/AppKit.h>

@interface JobsKeyboardRecorder : NSObject <NSApplicationDelegate>
- (void)stopRecording:(id)sender;
@end
JOBS_NATIVE_HEADER
}
# 输出本脚本维护的原生事件与可见控制界面，不访问外部源码或网络。
emit_native_source() {
  /bin/cat <<'JOBS_NATIVE_C'
//
//  JobsKeyboardRecorder.m
//  JobsKeyboardRecorder
//
//  Created by Jobs on 2026年10月15日，星期四.
//

#import "JobsKeyboardRecorder.h"

static int control_directory_fd = -1;
static int control_lock_fd = -1;
static int control_listener_fd = -1;
static int control_pending_fd = -1;
static char control_socket_name[NAME_MAX + 1];
static struct stat control_bound_socket;
static bool control_has_bound_socket = false;
static bool control_stop_requested = false;
static int64_t control_pending_deadline = 0;
static const char *control_session_ticket = "";

/* 提供总计时限，避免重试或信号中断延长等待。 */
static int64_t control_now_ms(void) {
    struct timespec value;
    if (clock_gettime(CLOCK_MONOTONIC, &value) != 0) {
        return -1;
    }
    return (int64_t)value.tv_sec * 1000 + value.tv_nsec / 1000000;
}

/* 按同一个截止时间等待本地连接可读或可写。 */
static bool control_wait(int fd, short events, int64_t deadline) {
    for (;;) {
        int64_t now = control_now_ms();
        if (now < 0 || now >= deadline) {
            errno = ETIMEDOUT;
            return false;
        }
        struct pollfd item = { .fd = fd, .events = events, .revents = 0 };
        int timeout = (int)(deadline - now);
        int result = poll(&item, 1, timeout);
        if (result < 0 && errno == EINTR) {
            continue;
        }
        if (result == 0) {
            errno = ETIMEDOUT;
            return false;
        }
        if (result < 0) {
            return false;
        }
        if (item.revents & (events | POLLHUP | POLLERR)) {
            return true;
        }
        errno = EBADF;
        return false;
    }
}

/* 设为非阻塞并禁止连接断开触发 SIGPIPE。 */
static bool control_prepare_fd(int fd) {
    int flags = fcntl(fd, F_GETFL);
    int descriptor_flags = fcntl(fd, F_GETFD);
    int enabled = 1;
    return flags >= 0 && descriptor_flags >= 0 &&
           fcntl(fd, F_SETFL, flags | O_NONBLOCK) == 0 &&
           fcntl(fd, F_SETFD, descriptor_flags | FD_CLOEXEC) == 0 &&
           setsockopt(fd, SOL_SOCKET, SO_NOSIGPIPE, &enabled, sizeof(enabled)) == 0;
}

/* 校验控制路径并拆分父目录和末级文件名。 */
static bool control_split_path(const char *path, char *directory, char *name) {
    if (path == NULL || path[0] != '/' || strlen(path) >= sizeof(((struct sockaddr_un *)0)->sun_path)) {
        errno = EINVAL;
        return false;
    }
    const char *slash = strrchr(path, '/');
    size_t directory_length = (size_t)(slash - path);
    size_t name_length = strlen(slash + 1);
    if (directory_length == 0 || name_length == 0 || name_length > NAME_MAX - 5 ||
        strcmp(slash + 1, ".") == 0 || strcmp(slash + 1, "..") == 0) {
        errno = EINVAL;
        return false;
    }
    memcpy(directory, path, directory_length);
    directory[directory_length] = '\0';
    memcpy(name, slash + 1, name_length + 1);
    return true;
}

/* 逐级拒绝符号链接，最终目录必须由当前用户持有且权限为 700。 */
static int control_private_directory(const char *path) {
    char copy[PATH_MAX];
    size_t length = strlen(path);
    if (length >= sizeof(copy) || path[0] != '/') {
        errno = EINVAL;
        return -1;
    }
    memcpy(copy, path, length + 1);
    int fd = open("/", O_RDONLY | O_DIRECTORY | O_CLOEXEC);
    if (fd < 0) {
        return -1;
    }
    char *part = copy + 1;
    while (*part != '\0') {
        char *end = strchr(part, '/');
        if (end != NULL) {
            *end = '\0';
        }
        if (*part == '\0' || strcmp(part, ".") == 0 || strcmp(part, "..") == 0) {
            close(fd);
            errno = EINVAL;
            return -1;
        }
        int next = openat(fd, part, O_RDONLY | O_DIRECTORY | O_NOFOLLOW | O_CLOEXEC);
        if (next < 0) {
            int error = errno;
            close(fd);
            errno = error;
            return -1;
        }
        close(fd);
        fd = next;
        if (end == NULL) {
            break;
        }
        part = end + 1;
    }
    struct stat information;
    if (fstat(fd, &information) != 0) {
        int error = errno;
        close(fd);
        errno = error;
        return -1;
    }
    if (!S_ISDIR(information.st_mode) || information.st_uid != getuid() ||
        (information.st_mode & 07777) != 0700) {
        close(fd);
        errno = EPERM;
        return -1;
    }
    return fd;
}

/* 只允许替换已失去监听者的本用户 socket。 */
static bool control_remove_stale(const char *path, int directory_fd, const char *name) {
    struct stat previous;
    if (fstatat(directory_fd, name, &previous, AT_SYMLINK_NOFOLLOW) != 0) {
        return errno == ENOENT;
    }
    if (!S_ISSOCK(previous.st_mode) || previous.st_uid != getuid()) {
        errno = EPERM;
        return false;
    }
    int probe = socket(AF_UNIX, SOCK_STREAM, 0);
    if (probe < 0) {
        return false;
    }
    if (!control_prepare_fd(probe)) {
        int error = errno;
        close(probe);
        errno = error;
        return false;
    }
    struct sockaddr_un address;
    memset(&address, 0, sizeof(address));
    address.sun_family = AF_UNIX;
    address.sun_len = sizeof(address);
    memcpy(address.sun_path, path, strlen(path) + 1);
    int connected = connect(probe, (struct sockaddr *)&address, sizeof(address));
    int connect_error = errno;
    close(probe);
    if (connected == 0 || connect_error == EINPROGRESS || connect_error == EAGAIN) {
        errno = EADDRINUSE;
        return false;
    }
    if (connect_error != ECONNREFUSED && connect_error != ENOENT) {
        errno = connect_error;
        return false;
    }
    struct stat current;
    if (fstatat(directory_fd, name, &current, AT_SYMLINK_NOFOLLOW) != 0) {
        return errno == ENOENT;
    }
    if (current.st_dev != previous.st_dev || current.st_ino != previous.st_ino) {
        errno = EAGAIN;
        return false;
    }
    return unlinkat(directory_fd, name, 0) == 0;
}

/* 写入少量控制字节，必要时等到共享的截止时间。 */
static bool control_send_until(int fd, const char *bytes, size_t length, int64_t deadline) {
    while (length > 0) {
        ssize_t count = send(fd, bytes, length, 0);
        if (count < 0 && errno == EINTR) {
            continue;
        }
        if (count < 0 && (errno == EAGAIN || errno == EWOULDBLOCK)) {
            if (!control_wait(fd, POLLOUT, deadline)) {
                return false;
            }
            continue;
        }
        if (count <= 0) {
            return false;
        }
        bytes += count;
        length -= (size_t)count;
    }
    return true;
}

/* 由调用方先完成记录文件 fsync 和 close，再回传保存结果。 */
void control_close(bool success) {
    if (control_listener_fd >= 0) {
        close(control_listener_fd);
        control_listener_fd = -1;
    }
    if (control_has_bound_socket && control_directory_fd >= 0) {
        struct stat current;
        if (fstatat(control_directory_fd, control_socket_name, &current, AT_SYMLINK_NOFOLLOW) == 0 &&
            S_ISSOCK(current.st_mode) && current.st_uid == getuid() &&
            current.st_dev == control_bound_socket.st_dev && current.st_ino == control_bound_socket.st_ino) {
            (void)unlinkat(control_directory_fd, control_socket_name, 0);
        }
    }
    control_has_bound_socket = false;
    if (control_pending_fd >= 0) {
        if (control_stop_requested) {
            const char *answer = success ? "OK\n" : "ERROR\n";
            int64_t now = control_now_ms();
            if (now >= 0) {
                (void)control_send_until(control_pending_fd, answer, strlen(answer), now + 1000);
            }
        }
        close(control_pending_fd);
        control_pending_fd = -1;
    }
    if (control_lock_fd >= 0) {
        close(control_lock_fd);
        control_lock_fd = -1;
    }
    if (control_directory_fd >= 0) {
        close(control_directory_fd);
        control_directory_fd = -1;
    }
    control_stop_requested = false;
}

/* 持有私有锁并创建本地控制通道，不接触任何输入监听。 */
bool control_open(const char *path) {
    if (control_directory_fd >= 0) {
        errno = EALREADY;
        return false;
    }
    char directory[PATH_MAX];
    char name[NAME_MAX + 1];
    char lock_name[NAME_MAX + 1];
    if (!control_split_path(path, directory, name)) {
        return false;
    }
    control_directory_fd = control_private_directory(directory);
    if (control_directory_fd < 0) {
        return false;
    }
    (void)snprintf(lock_name, sizeof(lock_name), "%s.lock", name);
    control_lock_fd = openat(control_directory_fd, lock_name,
                             O_RDWR | O_CREAT | O_CLOEXEC | O_NOFOLLOW, 0600);
    if (control_lock_fd < 0) {
        goto failure;
    }
    struct stat lock_information;
    if (fstat(control_lock_fd, &lock_information) != 0) {
        goto failure;
    }
    if (!S_ISREG(lock_information.st_mode) || lock_information.st_uid != getuid() ||
        lock_information.st_nlink != 1 || (lock_information.st_mode & 07777) != 0600) {
        errno = EPERM;
        goto failure;
    }
    if (flock(control_lock_fd, LOCK_EX | LOCK_NB) != 0) {
        goto failure;
    }
    struct stat lock_entry;
    if (fstatat(control_directory_fd, lock_name, &lock_entry, AT_SYMLINK_NOFOLLOW) != 0) {
        goto failure;
    }
    if (lock_entry.st_dev != lock_information.st_dev || lock_entry.st_ino != lock_information.st_ino) {
        errno = EAGAIN;
        goto failure;
    }
    if (!control_remove_stale(path, control_directory_fd, name)) {
        goto failure;
    }
    control_listener_fd = socket(AF_UNIX, SOCK_STREAM, 0);
    if (control_listener_fd < 0 || !control_prepare_fd(control_listener_fd)) {
        goto failure;
    }
    struct sockaddr_un address;
    memset(&address, 0, sizeof(address));
    address.sun_family = AF_UNIX;
    address.sun_len = sizeof(address);
    memcpy(address.sun_path, path, strlen(path) + 1);
    mode_t previous_mask = umask(077);
    int bind_result = bind(control_listener_fd, (struct sockaddr *)&address, sizeof(address));
    int bind_error = errno;
    (void)umask(previous_mask);
    if (bind_result != 0) {
        errno = bind_error;
        goto failure;
    }
    memcpy(control_socket_name, name, strlen(name) + 1);
    if (fstatat(control_directory_fd, name, &control_bound_socket, AT_SYMLINK_NOFOLLOW) != 0) {
        goto failure;
    }
    control_has_bound_socket = true;
    if (!S_ISSOCK(control_bound_socket.st_mode) || control_bound_socket.st_uid != getuid() ||
        fchmodat(control_directory_fd, name, 0600, 0) != 0 || listen(control_listener_fd, 8) != 0) {
        goto failure;
    }
    return true;

failure: {
        int error = errno;
        control_close(false);
        errno = error;
        return false;
    }
}

/* 就绪后在计时器中调用；单次仅做非阻塞操作并识别一个命令字节。 */
bool control_tick(void) {
    if (control_stop_requested) {
        return true;
    }
    if (control_listener_fd < 0) {
        return false;
    }
    for (int attempt = 0; attempt < 8; attempt++) {
        int64_t now = control_now_ms();
        if (now < 0) {
            return false;
        }
        if (control_pending_fd >= 0 && now >= control_pending_deadline) {
            close(control_pending_fd);
            control_pending_fd = -1;
        }
        if (control_pending_fd < 0) {
            control_pending_fd = accept(control_listener_fd, NULL, NULL);
            if (control_pending_fd < 0) {
                return false;
            }
            uid_t peer_uid;
            gid_t peer_gid;
            if (!control_prepare_fd(control_pending_fd) ||
                getpeereid(control_pending_fd, &peer_uid, &peer_gid) != 0 || peer_uid != getuid()) {
                close(control_pending_fd);
                control_pending_fd = -1;
                continue;
            }
            control_pending_deadline = now + 2000;
        }
        unsigned char command = 0;
        ssize_t count = recv(control_pending_fd, &command, 1, 0);
        if (count < 0 && errno == EINTR) {
            continue;
        }
        if (count < 0 && (errno == EAGAIN || errno == EWOULDBLOCK)) {
            return false;
        }
        if (count == 1 && command == 'S') {
            control_stop_requested = true;
            return true;
        }
        if (count == 1 && command == 'Q') {
            char ready[PATH_MAX + 16];
            int length = snprintf(ready, sizeof(ready), "READY %s\n", control_session_ticket);
            if (length > 0 && (size_t)length < sizeof(ready)) {
                (void)send(control_pending_fd, ready, (size_t)length, 0);
            }
        }
        close(control_pending_fd);
        control_pending_fd = -1;
    }
    return false;
}

/* 在没有记录器时将 stop 视为成功，status 则报告未就绪。 */
static int control_absent(bool stop) {
    if (stop) {
        puts("■ 已停止。");
        return 0;
    }
    return 1;
}

/* 只发送本地控制请求，八秒内必须收到完整的明确应答。 */
int control_client(const char *path, bool stop, const char *expected_ticket) {
    char directory[PATH_MAX];
    char name[NAME_MAX + 1];
    if (!control_split_path(path, directory, name)) {
        return 1;
    }
    int directory_fd = control_private_directory(directory);
    if (directory_fd < 0) {
        if (errno == ENOENT) {
            return control_absent(stop);
        }
        if (stop) {
            fputs("✖ 控制目录不安全或不可访问。\n", stderr);
        }
        return 1;
    }
    struct stat information;
    int inspected = fstatat(directory_fd, name, &information, AT_SYMLINK_NOFOLLOW);
    int inspect_error = errno;
    close(directory_fd);
    if (inspected != 0) {
        if (inspect_error == ENOENT) {
            return control_absent(stop);
        }
        return 1;
    }
    if (!S_ISSOCK(information.st_mode) || information.st_uid != getuid() ||
        (information.st_mode & 07777) != 0600) {
        if (stop) {
            fputs("✖ 控制 socket 的类型、归属或权限不正确。\n", stderr);
        }
        return 1;
    }
    int fd = socket(AF_UNIX, SOCK_STREAM, 0);
    if (fd < 0) {
        return 1;
    }
    int result = 1;
    int64_t now = control_now_ms();
    if (now < 0 || !control_prepare_fd(fd)) {
        goto finished;
    }
    int64_t deadline = now + (stop ? 8000 : 750);
    struct sockaddr_un address;
    memset(&address, 0, sizeof(address));
    address.sun_family = AF_UNIX;
    address.sun_len = sizeof(address);
    memcpy(address.sun_path, path, strlen(path) + 1);
    if (connect(fd, (struct sockaddr *)&address, sizeof(address)) != 0) {
        int connection_error = errno;
        if (connection_error == ENOENT || connection_error == ECONNREFUSED) {
            result = control_absent(stop);
            goto finished;
        }
        if (connection_error != EINPROGRESS && connection_error != EAGAIN) {
            goto finished;
        }
        if (!control_wait(fd, POLLOUT, deadline)) {
            goto finished;
        }
        int socket_error = 0;
        socklen_t error_length = sizeof(socket_error);
        if (getsockopt(fd, SOL_SOCKET, SO_ERROR, &socket_error, &error_length) != 0) {
            goto finished;
        }
        if (socket_error == ENOENT || socket_error == ECONNREFUSED) {
            result = control_absent(stop);
            goto finished;
        }
        if (socket_error != 0) {
            goto finished;
        }
    }
    uid_t peer_uid;
    gid_t peer_gid;
    if (getpeereid(fd, &peer_uid, &peer_gid) != 0 || peer_uid != getuid()) {
        goto finished;
    }
    if (!control_send_until(fd, stop ? "S" : "Q", 1, deadline)) {
        goto finished;
    }
    char response[PATH_MAX + 16];
    size_t used = 0;
    while (used < sizeof(response) - 1) {
        if (!control_wait(fd, POLLIN, deadline)) {
            goto finished;
        }
        ssize_t count = recv(fd, response + used, sizeof(response) - 1 - used, 0);
        if (count < 0 && (errno == EINTR || errno == EAGAIN || errno == EWOULDBLOCK)) {
            continue;
        }
        if (count <= 0) {
            goto finished;
        }
        used += (size_t)count;
        response[used] = '\0';
        if (memchr(response, '\n', used) != NULL) {
            char expected[PATH_MAX + 16];
            snprintf(expected, sizeof(expected), "READY %s\n", expected_ticket == NULL ? "" : expected_ticket);
            bool correct = stop ? strcmp(response, "OK\n") == 0 :
                           expected_ticket == NULL ? strncmp(response, "READY ", 6) == 0 :
                           strcmp(response, expected) == 0;
            if (correct) {
                if (stop) {
                    puts("■ 已停止并保存。");
                }
                result = 0;
            }
            goto finished;
        }
    }

finished:
    close(fd);
    if (result != 0 && stop) {
        fputs("✖ 未收到停止并保存成功的确认；请检查状态日志。\n", stderr);
    }
    return result;
}

static const char *version = "1.7.0";
static volatile sig_atomic_t stop_signal = 0;
static CFMachPortRef event_tap = NULL;
static int record_fd = -1;
static int status_fd = -1;
static int storage_lock_fd = -1;
static char record_file_path[PATH_MAX];
static char status_file_path[PATH_MAX];
static bool write_failed = false;
static bool secure_input = false;
static unsigned long long event_count = 0;
static unsigned int timer_ticks = 0;
static const char *stop_reason = "requested";
static NSStatusItem *status_item = nil;
static JobsKeyboardRecorder *application_delegate = nil;
static bool simulated_session = false;
static bool pending_application_quit = false;
static pid_t session_owner_pid = 0;
static struct proc_bsdinfo session_owner;
static bool session_bound = false;
static bool session_closing = false;

// 绑定启动脚本的进程身份，启动时间用于防止 PID 被复用后误续会话。
static bool bind_session_owner(const char *pid_text) {
    char *end = NULL;
    errno = 0;
    long value = strtol(pid_text, &end, 10);
    if (errno != 0 || end == pid_text || *end != '\0' || value <= 1 || value > INT_MAX) {
        return false;
    }
    session_owner_pid = (pid_t)value;
    if (session_owner_pid == getpid() ||
        proc_pidinfo(session_owner_pid, PROC_PIDTBSDINFO, 0, &session_owner, sizeof(session_owner)) != (int)sizeof(session_owner) ||
        session_owner.pbi_uid != getuid() || session_owner.pbi_status == SZOMB) {
        return false;
    }
    session_bound = true;
    return true;
}
// 每次处理事件及补齐路径前确认脚本仍存活；异常退出和遗留票据均不能续录。
static bool recording_session_active(void) {
    if (!session_bound) {
        return true;
    }
    struct proc_bsdinfo current;
    return !session_closing && !stop_signal && access(control_session_ticket, F_OK) == 0 &&
           proc_pidinfo(session_owner_pid, PROC_PIDTBSDINFO, 0, &current, sizeof(current)) == (int)sizeof(current) &&
           current.pbi_uid == getuid() && current.pbi_status != SZOMB &&
           current.pbi_start_tvsec == session_owner.pbi_start_tvsec &&
           current.pbi_start_tvusec == session_owner.pbi_start_tvusec;
}

// 补齐当前用户的输出目录，同时兼容系统带粘滞位的公共临时目录。
static int open_output_directory(const char *path) {
    char directory_path[PATH_MAX];
    if (path == NULL || path[0] != '/' || strlen(path) >= sizeof(directory_path)) {
        errno = EINVAL;
        return -1;
    }
    snprintf(directory_path, sizeof(directory_path), "%s", path);
    int directory_fd = open("/", O_RDONLY | O_DIRECTORY | O_CLOEXEC);
    if (directory_fd < 0) {
        return -1;
    }
    char *part = directory_path + 1;
    while (*part != '\0') {
        char *separator = strchr(part, '/');
        if (separator != NULL) {
            *separator = '\0';
        }
        if (*part == '\0' || strcmp(part, ".") == 0 || strcmp(part, "..") == 0) {
            close(directory_fd);
            errno = EINVAL;
            return -1;
        }
        int next_fd = openat(directory_fd, part, O_RDONLY | O_DIRECTORY | O_NOFOLLOW | O_CLOEXEC);
        if (next_fd < 0 && errno == ENOENT) {
            if (!recording_session_active()) {
                close(directory_fd);
                errno = ECANCELED;
                return -1;
            }
            struct stat parent;
            if (fstat(directory_fd, &parent) != 0 ||
                (parent.st_uid != getuid() && !(parent.st_uid == 0 && (parent.st_mode & S_ISVTX)))) {
                close(directory_fd);
                errno = EPERM;
                return -1;
            }
            if (mkdirat(directory_fd, part, 0700) == 0 || errno == EEXIST) {
                next_fd = openat(directory_fd, part, O_RDONLY | O_DIRECTORY | O_NOFOLLOW | O_CLOEXEC);
            }
        }
        int error = errno;
        close(directory_fd);
        if (next_fd < 0) {
            errno = error;
            return -1;
        }
        directory_fd = next_fd;
        if (separator == NULL) {
            break;
        }
        part = separator + 1;
    }
    struct stat attributes;
    if (fstat(directory_fd, &attributes) != 0) {
        int error = errno;
        close(directory_fd);
        errno = error;
        return -1;
    }
    if (!S_ISDIR(attributes.st_mode) ||
        (attributes.st_uid != getuid() && !(attributes.st_uid == 0 && (attributes.st_mode & S_ISVTX)))) {
        close(directory_fd);
        errno = EPERM;
        return -1;
    }
    return directory_fd;
}
// 每次写入都打开当前路径，无则创建；切换文件前同步旧句柄，避免写入已删除的文件。
static bool ensure_output_file(const char *path, int *file_fd) {
    if (!recording_session_active()) {
        errno = ECANCELED;
        return false;
    }
    if (path == NULL || path[0] != '/' || strlen(path) >= PATH_MAX) {
        errno = EINVAL;
        return false;
    }
    char parent_path[PATH_MAX];
    snprintf(parent_path, sizeof(parent_path), "%s", path);
    char *separator = strrchr(parent_path, '/');
    if (separator == parent_path || separator[1] == '\0' ||
        strcmp(separator + 1, ".") == 0 || strcmp(separator + 1, "..") == 0) {
        errno = EINVAL;
        return false;
    }
    *separator = '\0';
    const char *name = separator + 1;
    int directory_fd = open_output_directory(parent_path);
    if (directory_fd < 0) {
        return false;
    }
    if (!recording_session_active()) {
        close(directory_fd);
        errno = ECANCELED;
        return false;
    }
    int candidate_fd = openat(directory_fd, name,
                              O_WRONLY | O_CREAT | O_APPEND | O_NOFOLLOW | O_NONBLOCK | O_CLOEXEC, 0600);
    int error = errno;
    close(directory_fd);
    if (candidate_fd < 0) {
        errno = error;
        return false;
    }
    struct stat candidate;
    if (fstat(candidate_fd, &candidate) != 0) {
        error = errno;
        close(candidate_fd);
        errno = error;
        return false;
    }
    if (!S_ISREG(candidate.st_mode) || candidate.st_uid != getuid() || candidate.st_nlink != 1) {
        close(candidate_fd);
        errno = EPERM;
        return false;
    }
    if (fchmod(candidate_fd, 0600) != 0) {
        error = errno;
        close(candidate_fd);
        errno = error;
        return false;
    }
    if (*file_fd >= 0) {
        struct stat previous;
        if (fstat(*file_fd, &previous) != 0) {
            error = errno;
            close(candidate_fd);
            errno = error;
            return false;
        }
        if (previous.st_dev == candidate.st_dev && previous.st_ino == candidate.st_ino) {
            close(candidate_fd);
            return true;
        }
        int sync_result = fsync(*file_fd);
        error = errno;
        int close_result = close(*file_fd);
        if (close_result != 0 && sync_result == 0) {
            error = errno;
        }
        *file_fd = -1;
        if (sync_result != 0 || close_result != 0) {
            close(candidate_fd);
            errno = error;
            return false;
        }
    }
    *file_fd = candidate_fd;
    return true;
}
// 菜单栏初始化错误也进入统一的状态日志写入口。
static void status_message(const char *message);

// 在菜单或命令请求停止时唤醒 AppKit，统一执行保存收尾。
static void stop_recording_loop(const char *reason) {
    session_closing = true;
    stop_reason = reason;
    stop_signal = SIGTERM;
    [NSApp stop:nil];
    NSEvent *wake = [NSEvent otherEventWithType:NSEventTypeApplicationDefined
                                      location:NSZeroPoint
                                 modifierFlags:0
                                     timestamp:0
                                  windowNumber:0
                                       context:nil
                                       subtype:0
                                         data1:0
                                         data2:0];
    [NSApp postEvent:wake atStart:YES];
}

@implementation JobsKeyboardRecorder
// 菜单停止入口先保存记录，再结束进程。
- (void)stopRecording:(id)sender {
    (void)sender;
    stop_recording_loop("requested");
}
// 注销或系统退出时仍走统一保存流程。
- (NSApplicationTerminateReply)applicationShouldTerminate:(NSApplication *)sender {
    (void)sender;
    pending_application_quit = true;
    stop_recording_loop("application_quit");
    return NSTerminateLater;
}

@end

// 仅显示菜单栏状态和停止菜单，不创建普通窗口。
static bool prepare_status_indicator(void) {
    [NSApplication sharedApplication];
    if (NSApp.activationPolicy != NSApplicationActivationPolicyAccessory &&
        ![NSApp setActivationPolicy:NSApplicationActivationPolicyAccessory]) {
        status_message("✖ AppKit 无法设置菜单栏应用运行策略。");
        return false;
    }
    application_delegate = [JobsKeyboardRecorder new];
    NSApp.delegate = application_delegate;
    [NSApp finishLaunching];
    status_item = [[NSStatusBar systemStatusBar] statusItemWithLength:NSVariableStatusItemLength];
    if (status_item.button == nil) {
        status_message("✖ AppKit 无法创建菜单栏状态按钮。");
        return false;
    }
    status_item.behavior = NSStatusItemBehaviorTerminationOnRemoval;
    status_item.visible = YES;
    status_item.button.title = simulated_session ? @"键盘记录测试" : @"键盘记录准备中";
    status_item.button.toolTip = @"菜单栏选择“停止并保存”，或在终端输入 stop";
    NSMenu *menu = [[NSMenu alloc] initWithTitle:@"JobsKeyboardRecorder"];
    NSMenuItem *stop_item = [[NSMenuItem alloc] initWithTitle:@"停止并保存"
                                                     action:@selector(stopRecording:)
                                              keyEquivalent:@""];
    stop_item.target = application_delegate;
    [menu addItem:stop_item];
    status_item.menu = menu;
    if (!status_item.visible) {
        status_message("✖ AppKit 无法显示菜单栏记录状态。");
        return false;
    }
    return true;
}

// 生成带本机时区的毫秒时间，便于对应发生时间。
static void timestamp(char *output, size_t capacity) {
    struct timespec now;
    struct tm local_time;
    char date[40];
    char zone[12];
    clock_gettime(CLOCK_REALTIME, &now);
    localtime_r(&now.tv_sec, &local_time);
    strftime(date, sizeof(date), "%Y-%m-%dT%H:%M:%S", &local_time);
    strftime(zone, sizeof(zone), "%z", &local_time);
    snprintf(output, capacity, "%s.%03ld%s", date, now.tv_nsec / 1000000, zone);
}
// 处理短写和信号中断，任何写入失败都会停止监听。
static bool write_all(int fd, const void *bytes, size_t length) {
    const unsigned char *cursor = bytes;
    while (length > 0) {
        ssize_t written = write(fd, cursor, length);
        if (written < 0 && errno == EINTR) {
            continue;
        }
        if (written <= 0) {
            return false;
        }
        cursor += written;
        length -= (size_t)written;
    }
    return true;
}
// 状态提示只包含计数及路径，不输出按键内容。
static void status_message(const char *message) {
    char time_text[64];
    char line[PATH_MAX + 256];
    timestamp(time_text, sizeof(time_text));
    int length = snprintf(line, sizeof(line), "[%s] %s\n", time_text, message);
    if (length > 0 && (size_t)length < sizeof(line)) {
        (void)write_all(STDOUT_FILENO, line, (size_t)length);
        bool active = recording_session_active();
        bool status_ready = status_fd >= 0;
        if (active && status_file_path[0] != '\0') {
            status_ready = ensure_output_file(status_file_path, &status_fd);
        }
        if (status_file_path[0] != '\0' &&
            ((!status_ready && active) || (status_ready && !write_all(status_fd, line, (size_t)length)))) {
            fprintf(stderr, "✖ 写入运行状态日志失败：%s\n", strerror(errno));
            write_failed = true;
            stop_recording_loop("status_write_failed");
        }
    }
}
// 只将有效 UTF-8 文字写入正文，写入失败时保留已有内容并停止。
static void append_text(const unsigned char *text, size_t length) {
    if (!recording_session_active()) {
        stop_recording_loop("launcher_exited");
        return;
    }
    if (!ensure_output_file(record_file_path, &record_fd) || !write_all(record_fd, text, length)) {
        write_failed = true;
        stop_recording_loop("log_write_failed");
    }
}
// 会话状态单独进入运行日志，不混入用户的纯文本记录。
static void lifecycle_event(const char *kind) {
    char line[256];
    snprintf(line, sizeof(line), "会话状态：%s；文字输入事件：%llu", kind, event_count);
    status_message(line);
}
// 将当前安全输入状态转换为明确的暂停和恢复标记。
static void update_secure_input(void) {
    bool current = IsSecureEventInputEnabled();
    if (current != secure_input) {
        secure_input = current;
        lifecycle_event(current ? "secure_input_pause" : "secure_input_resume");
        status_item.button.title = current ? @"⏸ 键盘记录暂停" : @"● 键盘记录中";
        status_message(current ? "⏸ 安全输入已启用，暂停记录。" : "● 安全输入已结束，恢复记录。 ");
    }
}
// 提取可见字符，统一回车为换行；不读取应用文本或剪贴板。
static size_t event_text(CGEventRef event, unsigned char *output, size_t capacity) {
    UniChar characters[64];
    UniChar filtered[64];
    UniCharCount length = 0;
    CFIndex used = 0;
    CFIndex byte_count = 0;
    CGKeyCode keycode = (CGKeyCode)CGEventGetIntegerValueField(event, kCGKeyboardEventKeycode);
    CGEventKeyboardGetUnicodeString(event, 64, &length, characters);
    if (length > 64) {
        length = 64;
    }
    for (UniCharCount index = 0; index < length; index++) {
        UniChar character = characters[index];
        if (character == '\r' || (character == 0x03 && keycode == kVK_ANSI_KeypadEnter)) {
            character = '\n';
        }
        if (character == '\n' || character == '\t' ||
            (character >= 0x20 && !(character >= 0x7F && character <= 0x9F) &&
             !(character >= 0xF700 && character <= 0xF8FF))) {
            filtered[used++] = character;
        }
    }
    CFStringRef string = CFStringCreateWithCharacters(kCFAllocatorDefault, filtered, used);
    if (string != NULL) {
        CFIndex converted = CFStringGetBytes(string, CFRangeMake(0, CFStringGetLength(string)),
                                             kCFStringEncodingUTF8, 0, false, output,
                                             (CFIndex)capacity, &byte_count);
        CFRelease(string);
        if (converted != used) {
            return 0;
        }
    }
    return (size_t)byte_count;
}
// 每次按下只记录一次文字，忽略松开、修饰键及 Command/Control 快捷键。
static void record_event(CGEventType type, CGEventRef event) {
    CGEventFlags flags = CGEventGetFlags(event);
    if (type != kCGEventKeyDown || (flags & (kCGEventFlagMaskCommand | kCGEventFlagMaskControl))) {
        return;
    }
    unsigned char text[512];
    size_t length = event_text(event, text, sizeof(text));
    if (length > 0) {
        append_text(text, length);
        if (!write_failed) {
            event_count++;
        }
    }
}
// 系统回调只被动观察；保护状态和监听中断都显式处理。
static CGEventRef handle_event(CGEventTapProxy proxy, CGEventType type, CGEventRef event, void *context) {
    (void)proxy;
    (void)context;
    if (!recording_session_active()) {
        stop_recording_loop("launcher_exited");
        return event;
    }
    if (type == kCGEventTapDisabledByTimeout) {
        lifecycle_event("gap_tap_timeout");
        status_message("⚠ 监听曾超时，期间可能缺少事件，现尝试恢复。 ");
        CGEventTapEnable(event_tap, true);
        return event;
    }
    if (type == kCGEventTapDisabledByUserInput) {
        stop_recording_loop("tap_disabled");
        return event;
    }
    update_secure_input();
    if (!secure_input && !stop_signal && !write_failed) {
        record_event(type, event);
    }
    return event;
}
// 信号处理器只设置标记，资源收尾由主循环执行。
static void request_stop(int number) {
    stop_signal = number;
}
// 处理控制命令、可见状态、权限撤销及周期性状态提示。
static void timer_callback(CFRunLoopTimerRef timer, void *context) {
    (void)timer;
    (void)context;
    if (control_tick()) {
        stop_recording_loop("stop_command");
        return;
    }
    if (stop_signal) {
        stop_recording_loop(stop_reason);
        return;
    }
    if (!recording_session_active()) {
        stop_recording_loop("launcher_exited");
        return;
    }
    if (!status_item.visible) {
        stop_recording_loop("indicator_closed");
        return;
    }
    if (!simulated_session && !CGPreflightListenEventAccess()) {
        stop_recording_loop("permission_revoked");
        return;
    }
    if (!simulated_session) {
        update_secure_input();
    }
    if (++timer_ticks % 120 == 0) {
        char message[160];
        snprintf(message, sizeof(message), "%s 已记录 %llu 次文字输入；终端输入 stop 或菜单栏选择“停止并保存”。",
                 secure_input ? "⏸ 安全输入暂停中。" : "● 正在记录。", event_count);
        status_message(message);
    }
}
// 识别无后缀编号及旧版编号，越界时避免回绕覆盖旧文件。
static int record_index(const char *name, unsigned long long *index) {
    if (name[0] < '0' || name[0] > '9') {
        return 0;
    }
    char *end = NULL;
    errno = 0;
    unsigned long long value = strtoull(name, &end, 10);
    if (*end != '\0' && strcmp(end, ".jsonl") != 0) {
        return 0;
    }
    if (errno == ERANGE) {
        return -1;
    }
    *index = value;
    return 1;
}
// 仅为旧版编号记录去除后缀，保留文件名中的原始编号。
static bool numbered_suffix_target(const char *name, char *target, size_t capacity) {
    unsigned long long index = 0;
    size_t length = strlen(name);
    if (length <= 6 || strcmp(name + length - 6, ".jsonl") != 0 ||
        record_index(name, &index) != 1 || length - 6 >= capacity) {
        return false;
    }
    memcpy(target, name, length - 6);
    target[length - 6] = '\0';
    return true;
}
// 兼容旧版使用时间戳命名的记录，不读取记录正文。
static bool legacy_record_name(const char *name) {
    size_t length = strlen(name);
    return length > 15 && strncmp(name, "keyboard-", 9) == 0 &&
           strcmp(name + length - 6, ".jsonl") == 0;
}
// 只迁移属于当前用户的普通记录文件，拒绝符号链接和其它对象。
static bool owned_record_file(int directory_fd, const char *name) {
    struct stat attributes;
    if (fstatat(directory_fd, name, &attributes, AT_SYMLINK_NOFOLLOW) != 0 ||
        !S_ISREG(attributes.st_mode) || attributes.st_uid != getuid()) {
        fprintf(stderr, "✖ 记录必须是当前用户拥有的普通文件：%s\n", name);
        return false;
    }
    return true;
}
// 续接最大编号，迁移旧版后缀及时间戳记录，目标冲突时保留全部原文件。
static bool scan_record_directory(const char *path, int directory_fd,
                                  bool *empty, unsigned long long *next_index) {
    struct dirent **entries = NULL;
    int count = scandir(path, &entries, NULL, alphasort);
    if (count < 0) {
        perror("读取记录目录失败");
        return false;
    }
    bool success = false;
    bool numbered = false;
    bool legacy = false;
    unsigned long long legacy_count = 0;
    unsigned long long maximum = 0;
    *empty = true;
    for (int index = 0; index < count; index++) {
        const char *name = entries[index]->d_name;
        if (strcmp(name, ".") == 0 || strcmp(name, "..") == 0) {
            continue;
        }
        *empty = false;
        unsigned long long value = 0;
        int kind = record_index(name, &value);
        if (kind < 0) {
            fprintf(stderr, "✖ 记录编号超出可用范围：%s\n", name);
            goto finished;
        }
        bool old_format = legacy_record_name(name);
        if ((kind == 1 || old_format) && !owned_record_file(directory_fd, name)) {
            goto finished;
        }
        if (kind == 1) {
            if (!numbered || value > maximum) {
                maximum = value;
            }
            numbered = true;
        }
        legacy = legacy || old_format;
        if (old_format) {
            legacy_count++;
        }
    }
    if (!*empty && !numbered && !legacy) {
        fprintf(stderr, "✖ 同名目录包含未识别文件，已保留原内容；请先处理目录冲突。\n");
        goto finished;
    }
    if (numbered && (maximum == ULLONG_MAX || legacy_count > ULLONG_MAX - maximum - 1)) {
        fprintf(stderr, "✖ 记录编号已达到上限，已有记录保持原样。\n");
        goto finished;
    }
    for (int index = 0; index < count; index++) {
        char target[NAME_MAX + 1];
        if (!numbered_suffix_target(entries[index]->d_name, target, sizeof(target))) {
            continue;
        }
        struct stat attributes;
        if (fstatat(directory_fd, target, &attributes, AT_SYMLINK_NOFOLLOW) == 0) {
            fprintf(stderr, "✖ 去除后缀的目标已存在，原文件保持不变：%s\n", target);
            goto finished;
        }
        if (errno != ENOENT) {
            perror("检查无后缀目标失败");
            goto finished;
        }
    }
    if (fchmod(directory_fd, 0700) != 0) {
        perror("设置私有记录目录权限失败");
        goto finished;
    }
    for (int index = 0; index < count; index++) {
        char target[NAME_MAX + 1];
        const char *name = entries[index]->d_name;
        if (!numbered_suffix_target(name, target, sizeof(target))) {
            continue;
        }
        if (renameatx_np(directory_fd, name, directory_fd, target, RENAME_EXCL) != 0) {
            perror("去除旧版记录后缀失败，已有记录未覆盖");
            goto finished;
        }
    }
    for (int index = 0; index < count; index++) {
        const char *name = entries[index]->d_name;
        if (!legacy_record_name(name)) {
            continue;
        }
        if (numbered && maximum == ULLONG_MAX) {
            fprintf(stderr, "✖ 记录编号已达到上限。\n");
            goto finished;
        }
        unsigned long long value = numbered ? maximum + 1 : 0;
        char target[64];
        snprintf(target, sizeof(target), "%llu", value);
        if (renameatx_np(directory_fd, name, directory_fd, target, RENAME_EXCL) != 0) {
            perror("迁移旧版记录失败，已有记录未覆盖");
            goto finished;
        }
        maximum = value;
        numbered = true;
    }
    if (numbered && maximum == ULLONG_MAX) {
        fprintf(stderr, "✖ 记录编号已达到上限。\n");
        goto finished;
    }
    *next_index = numbered ? maximum + 1 : 0;
    success = true;
finished:
    for (int index = 0; index < count; index++) {
        free(entries[index]);
    }
    free(entries);
    return success;
}
// 先保留旧记录的硬链接，再原子交换文件与目录，迁移全程不丢旧记录。
static int promote_first_record(const char *path, int parent_fd, const char *name) {
    if (!recording_session_active()) {
        errno = ECANCELED;
        return -1;
    }
    char staging_path[PATH_MAX];
    int length = snprintf(staging_path, sizeof(staging_path), "%s.migration.XXXXXX", path);
    if (length <= 0 || (size_t)length >= sizeof(staging_path) || mkdtemp(staging_path) == NULL) {
        perror("创建记录迁移目录失败");
        return -1;
    }
    const char *staging_name = strrchr(staging_path, '/') + 1;
    int directory_fd = openat(parent_fd, staging_name, O_RDONLY | O_DIRECTORY | O_NOFOLLOW | O_CLOEXEC);
    if (directory_fd < 0) {
        perror("打开记录迁移目录失败");
        (void)unlinkat(parent_fd, staging_name, AT_REMOVEDIR);
        return -1;
    }
    if (linkat(parent_fd, name, directory_fd, "0", 0) != 0) {
        perror("保留首份记录失败");
        close(directory_fd);
        (void)unlinkat(parent_fd, staging_name, AT_REMOVEDIR);
        return -1;
    }
    if (renameatx_np(parent_fd, name, parent_fd, staging_name, RENAME_SWAP) != 0) {
        perror("将首份记录转入同名目录失败");
        (void)unlinkat(directory_fd, "0", 0);
        close(directory_fd);
        (void)unlinkat(parent_fd, staging_name, AT_REMOVEDIR);
        return -1;
    }
    if (unlinkat(parent_fd, staging_name, 0) != 0) {
        fprintf(stderr, "⚠ 首份记录已安全迁入 0，冗余副本暂留：%s\n", staging_path);
    }
    return directory_fd;
}
// 首次使用单文件，多次使用编号目录；父目录锁防止同时启动时相互覆盖。
static bool open_record(const char *path, char *record_path, size_t capacity) {
    if (!recording_session_active()) {
        errno = ECANCELED;
        return false;
    }
    char parent_path[PATH_MAX];
    const char *separator = strrchr(path, '/');
    if (path[0] != '/' || separator == NULL || strcmp(separator + 1, "JobsKeyboardRecorder") != 0 ||
        (size_t)(separator - path) >= sizeof(parent_path) || separator == path) {
        fprintf(stderr, "✖ 记录位置必须是绝对路径下的 JobsKeyboardRecorder。\n");
        return false;
    }
    size_t parent_length = (size_t)(separator - path);
    memcpy(parent_path, path, parent_length);
    parent_path[parent_length] = '\0';
    const char *name = separator + 1;
    int directory_fd = -1;
    storage_lock_fd = open_output_directory(parent_path);
    struct stat attributes;
    if (storage_lock_fd < 0 || fstat(storage_lock_fd, &attributes) != 0 ||
        attributes.st_uid != getuid()) {
        fprintf(stderr, "✖ 无法创建记录父目录，或目录不属于当前用户。\n");
        goto failed;
    }
    if (flock(storage_lock_fd, LOCK_EX | LOCK_NB) != 0) {
        fprintf(stderr, "✖ 已有记录会话正在使用此位置，请先停止该会话。\n");
        goto failed;
    }
    bool first_record = false;
    unsigned long long next_index = 0;
    if (fstatat(storage_lock_fd, name, &attributes, AT_SYMLINK_NOFOLLOW) != 0) {
        if (errno != ENOENT) {
            perror("检查记录位置失败");
            goto failed;
        }
        first_record = true;
    } else {
        if (attributes.st_uid != getuid() ||
            (!S_ISREG(attributes.st_mode) && !S_ISDIR(attributes.st_mode))) {
            fprintf(stderr, "✖ 同名位置必须是当前用户的普通文件或目录，不能是符号链接。\n");
            goto failed;
        }
        if (S_ISREG(attributes.st_mode)) {
            if ((attributes.st_mode & 0777) != 0600) {
                fprintf(stderr, "✖ 首份记录的文件权限必须为 600，已保留原文件。\n");
                goto failed;
            }
            directory_fd = promote_first_record(path, storage_lock_fd, name);
            next_index = 1;
            if (directory_fd < 0) {
                goto failed;
            }
        } else {
            directory_fd = openat(storage_lock_fd, name, O_RDONLY | O_DIRECTORY | O_NOFOLLOW | O_CLOEXEC);
            if (directory_fd < 0) {
                perror("准备私有记录目录失败");
                goto failed;
            }
            bool empty = false;
            if (!scan_record_directory(path, directory_fd, &empty, &next_index)) {
                goto failed;
            }
            if (empty) {
                close(directory_fd);
                directory_fd = -1;
                if (unlinkat(storage_lock_fd, name, AT_REMOVEDIR) != 0) {
                    perror("移除旧版空记录目录失败");
                    goto failed;
                }
                first_record = true;
            }
        }
    }
    char filename[64];
    if (first_record) {
        snprintf(filename, sizeof(filename), "%s", name);
    } else {
        snprintf(filename, sizeof(filename), "%llu", next_index);
    }
    int length = first_record ? snprintf(record_path, capacity, "%s", path) :
                               snprintf(record_path, capacity, "%s/%s", path, filename);
    if (length <= 0 || (size_t)length >= capacity) {
        fprintf(stderr, "✖ 记录路径过长。\n");
        goto failed;
    }
    if (!recording_session_active()) {
        errno = ECANCELED;
        goto failed;
    }
    record_fd = openat(first_record ? storage_lock_fd : directory_fd, filename,
                       O_WRONLY | O_CREAT | O_EXCL | O_APPEND | O_NOFOLLOW | O_CLOEXEC, 0600);
    if (record_fd < 0) {
        perror("创建记录文件失败，已有记录未覆盖");
        goto failed;
    }
    snprintf(record_file_path, sizeof(record_file_path), "%s", record_path);
    if (directory_fd >= 0) {
        close(directory_fd);
    }
    return true;
failed:
    if (directory_fd >= 0) {
        close(directory_fd);
    }
    if (storage_lock_fd >= 0) {
        close(storage_lock_fd);
        storage_lock_fd = -1;
    }
    return false;
}
// 只写人造事件，供离线验证格式；不创建监听、不申请权限、不发送按键。
static int self_test(const char *path) {
    char record_path[PATH_MAX];
    if (!open_record(path, record_path, sizeof(record_path))) {
        return 1;
    }
    CGEventRef event = CGEventCreateKeyboardEvent(NULL, 0, true);
    if (event == NULL) {
        close(record_fd);
        return 1;
    }
    const UniChar text[] = {'d', 'j', 'i', 'o', 'w', 'i', 'j', 'c'};
    CGEventSetFlags(event, 0);
    lifecycle_event("self_test_start");
    for (size_t index = 0; index < sizeof(text) / sizeof(text[0]); index++) {
        CGEventKeyboardSetUnicodeString(event, 1, &text[index]);
        record_event(kCGEventKeyDown, event);
        record_event(kCGEventKeyUp, event);
        record_event(kCGEventFlagsChanged, event);
    }
    CGEventSetFlags(event, kCGEventFlagMaskCommand);
    record_event(kCGEventKeyDown, event);
    CGEventSetFlags(event, kCGEventFlagMaskControl);
    record_event(kCGEventKeyDown, event);
    lifecycle_event("self_test_end");
    CFRelease(event);
    int result = ensure_output_file(record_file_path, &record_fd) ? fsync(record_fd) : -1;
    close(record_fd);
    puts(record_path);
    return write_failed || result != 0 ? 1 : 0;
}
// 控制命令不初始化界面；实际记录须绑定仍在运行的启动脚本。
static int run_command(int argc, char **argv) {
    if (argc == 2 && strcmp(argv[1], "--version") == 0) {
        puts(version);
        return 0;
    }
    if ((argc == 3 && strcmp(argv[1], "--stop") == 0) ||
        ((argc == 3 || argc == 4) && strcmp(argv[1], "--status") == 0)) {
        return control_client(argv[2], strcmp(argv[1], "--stop") == 0, argc == 4 ? argv[3] : NULL);
    }
    if (argc == 3 && strcmp(argv[1], "--self-test") == 0) {
        return self_test(argv[2]);
    }
    if (argc != 7 || (strcmp(argv[1], "--record") != 0 && strcmp(argv[1], "--self-test-session") != 0) || getuid() == 0) {
        fprintf(stderr, "✖ 请通过 .command 入口启动，或使用 stop 停止。\n");
        return 1;
    }
    simulated_session = strcmp(argv[1], "--self-test-session") == 0;
    control_session_ticket = argv[5];
    if (!bind_session_owner(argv[6]) || !recording_session_active()) {
        fprintf(stderr, "✖ 启动脚本已退出或会话已取消，未开始记录。\n");
        return 1;
    }
    if (strlen(argv[3]) >= sizeof(status_file_path)) {
        fprintf(stderr, "✖ 运行状态日志路径过长。\n");
        return 1;
    }
    snprintf(status_file_path, sizeof(status_file_path), "%s", argv[3]);
    if (!ensure_output_file(status_file_path, &status_fd)) {
        perror("打开运行状态日志失败");
        return 1;
    }
    if (!control_open(argv[4])) {
        status_message("✖ 启动失败：已有会话，或私有控制通道不可用。");
        close(status_fd);
        return 1;
    }
    if (!prepare_status_indicator()) {
        status_message("✖ 启动失败：无法显示菜单栏记录状态，未启动监听。");
        control_close(false);
        close(status_fd);
        return 1;
    }
    if (!simulated_session && !CGPreflightListenEventAccess() && !CGRequestListenEventAccess()) {
        status_message("✖ 启动失败：请在系统设置 → 隐私与安全性 → 输入监控中允许 JobsKeyboardRecorder，再重新运行脚本。");
        control_close(false);
        close(status_fd);
        return 77;
    }
    if (!recording_session_active()) {
        status_message("✖ 启动已取消，未开始记录。");
        control_close(false);
        close(status_fd);
        return 1;
    }
    CGEventMask mask = CGEventMaskBit(kCGEventKeyDown) | CGEventMaskBit(kCGEventKeyUp) |
                       CGEventMaskBit(kCGEventFlagsChanged);
    if (!simulated_session) {
        event_tap = CGEventTapCreate(kCGSessionEventTap, kCGHeadInsertEventTap, kCGEventTapOptionListenOnly,
                                    mask, handle_event, NULL);
    }
    if (!simulated_session && event_tap == NULL) {
        status_message("✖ 启动失败：创建监听失败，请检查输入监控权限。 ");
        control_close(false);
        close(status_fd);
        return 1;
    }
    char record_path[PATH_MAX];
    if (!open_record(argv[2], record_path, sizeof(record_path))) {
        if (event_tap != NULL) {
            CFMachPortInvalidate(event_tap);
            CFRelease(event_tap);
        }
        status_message("✖ 启动失败：无法准备记录文件，已有文件保持原样。");
        control_close(false);
        close(status_fd);
        return 1;
    }
    struct sigaction action;
    memset(&action, 0, sizeof(action));
    action.sa_handler = request_stop;
    sigemptyset(&action.sa_mask);
    sigaction(SIGINT, &action, NULL);
    sigaction(SIGTERM, &action, NULL);
    sigaction(SIGHUP, &action, NULL);
    signal(SIGPIPE, SIG_IGN);
    CFRunLoopSourceRef source = event_tap == NULL ? NULL : CFMachPortCreateRunLoopSource(kCFAllocatorDefault, event_tap, 0);
    CFRunLoopTimerRef timer = CFRunLoopTimerCreate(kCFAllocatorDefault, CFAbsoluteTimeGetCurrent(),
                                                  0.25, 0, 0, timer_callback, NULL);
    if ((!simulated_session && source == NULL) || timer == NULL) {
        status_message("✖ 启动失败：无法创建事件循环。");
        close(record_fd);
        close(status_fd);
        if (source != NULL) {
            CFRelease(source);
        }
        if (timer != NULL) {
            CFRelease(timer);
        }
        if (event_tap != NULL) {
            CFMachPortInvalidate(event_tap);
            CFRelease(event_tap);
        }
        control_close(false);
        return 1;
    }
    lifecycle_event(simulated_session ? "self_test_session_start" : "session_start");
    status_message(record_path);
    if (!simulated_session) {
        status_item.button.title = @"● 键盘记录中";
        update_secure_input();
        CFRunLoopAddSource(CFRunLoopGetCurrent(), source, kCFRunLoopCommonModes);
        CGEventTapEnable(event_tap, true);
    }
    CFRunLoopAddTimer(CFRunLoopGetCurrent(), timer, kCFRunLoopCommonModes);
    if (!write_failed) {
        status_message(simulated_session ? "● 模拟会话已启动，不监听实际按键。" : "● 正在记录；请保持启动终端运行，Ctrl+C、关闭终端、stop 或菜单均可停止。");
        [NSApp run];
    }
    session_closing = true;
    if (event_tap != NULL) {
        CGEventTapEnable(event_tap, false);
        CFMachPortInvalidate(event_tap);
    }
    CFRunLoopTimerInvalidate(timer);
    lifecycle_event(stop_reason);
    int sync_result = fsync(record_fd);
    int close_result = close(record_fd);
    if (sync_result != 0 || close_result != 0) {
        write_failed = true;
    }
    status_message(write_failed ? "✖ 写入失败，记录已停止；请检查磁盘空间与文件权限。" : "■ 记录已停止，已有内容已保存。 ");
    CFRelease(timer);
    if (source != NULL) {
        CFRelease(source);
    }
    if (event_tap != NULL) {
        CFRelease(event_tap);
    }
    [[NSStatusBar systemStatusBar] removeStatusItem:status_item];
    control_close(!write_failed);
    close(status_fd);
    if (strcmp(strrchr(control_session_ticket, '/') == NULL ? "" : strrchr(control_session_ticket, '/') + 1, "startup-ticket") == 0) {
        (void)unlink(control_session_ticket);
        char ticket_directory[PATH_MAX];
        snprintf(ticket_directory, sizeof(ticket_directory), "%s", control_session_ticket);
        *strrchr(ticket_directory, '/') = '\0';
        (void)rmdir(ticket_directory);
    }
    if (pending_application_quit) {
        [NSApp replyToApplicationShouldTerminate:YES];
    }
    return write_failed || strcmp(stop_reason, "permission_revoked") == 0 ||
           strcmp(stop_reason, "tap_disabled") == 0 ? 1 : 0;
}
// 所有 Objective-C 临时对象在命令完成后集中释放。
int main(int argc, char **argv) {
    @autoreleasepool {
        return run_command(argc, argv);
    }
}
JOBS_NATIVE_C
}
# 只在源码变化或缓存失效时重新编译，保持辅助程序路径稳定。
prepare_native_helper() {
  ensure_shell_log_file || fail '无法准备运行状态日志。'
  [[ ! -L "$CACHE_DIR" ]] || fail "缓存目录不能是符号链接：${CACHE_DIR}"
  /bin/mkdir -p "$CACHE_DIR" || fail "无法创建缓存：${CACHE_DIR}"
  [[ "$(/usr/bin/stat -f '%u' "$CACHE_DIR")" == "$UID" ]] || fail '缓存目录不属于当前用户。'
  /bin/chmod 700 "$CACHE_DIR" || fail '无法设置缓存目录权限。'
  local cache_path=''
  for cache_path in "$APP_PATH" "${APP_PATH}/Contents" "${APP_PATH}/Contents/MacOS" "$HELPER" "${APP_PATH}/Contents/Info.plist" "${CACHE_DIR}/JobsKeyboardRecorder.h" "${CACHE_DIR}/JobsKeyboardRecorder.m"; do
    [[ ! -L "$cache_path" ]] || fail "缓存位置不能是符号链接：${cache_path}"
  done
  if [[ -x "$HELPER" ]] && "$HELPER" --status "$CONTROL_PATH" >/dev/null 2>&1; then
    fail '已有会话正在运行，请先在终端输入 stop，再重新运行。'
  fi
  WORK_DIR="$(/usr/bin/mktemp -d "${CACHE_DIR}/build.XXXXXX")" || fail '无法创建构建目录。'
  emit_native_header >"${WORK_DIR}/JobsKeyboardRecorder.h" || fail '无法准备原生头文件。'
  emit_native_source >"${WORK_DIR}/JobsKeyboardRecorder.m" || fail '无法准备内嵌源码。'
  if [[ -x "$HELPER" ]] && /usr/bin/cmp -s "${WORK_DIR}/JobsKeyboardRecorder.m" "${CACHE_DIR}/JobsKeyboardRecorder.m" &&
     /usr/bin/cmp -s "${WORK_DIR}/JobsKeyboardRecorder.h" "${CACHE_DIR}/JobsKeyboardRecorder.h" &&
     /usr/bin/plutil -lint "${APP_PATH}/Contents/Info.plist" >/dev/null 2>&1 &&
     [[ "$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "${APP_PATH}/Contents/Info.plist" 2>/dev/null)" == com.jobs.keyboard-recorder ]] &&
     [[ "$(/usr/libexec/PlistBuddy -c 'Print :CFBundleExecutable' "${APP_PATH}/Contents/Info.plist" 2>/dev/null)" == JobsKeyboardRecorder ]] &&
     /usr/bin/codesign --verify --strict "$APP_PATH" >>"$LOG_FILE" 2>&1 &&
     [[ "$("$HELPER" --version 2>>"$LOG_FILE")" == '1.7.0' ]]; then
    log '✔ 复用已编译的原生监听程序。'
    return
  fi
  log 'ℹ 正在编译内嵌原生程序……'
  if ! "$CLANG" -std=gnu11 -fobjc-arc -O2 -Wall -Wextra -Werror -isysroot "$SDK_ROOT" -mmacosx-version-min=10.15 \
      "${WORK_DIR}/JobsKeyboardRecorder.m" -framework AppKit -framework ApplicationServices -framework Carbon \
      -o "${WORK_DIR}/JobsKeyboardRecorder" 2>&1 | /usr/bin/tee -a "$LOG_FILE"; then
    fail '原生程序编译失败，未启动监听；详情见运行状态日志。'
  fi
  /bin/mkdir -p "${APP_PATH}/Contents/MacOS" || fail '无法创建原生 App 目录。'
  /bin/cat >"${APP_PATH}/Contents/Info.plist" <<'JOBS_APP_PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
  <key>CFBundleIdentifier</key><string>com.jobs.keyboard-recorder</string>
  <key>CFBundleName</key><string>JobsKeyboardRecorder</string>
  <key>CFBundleDisplayName</key><string>Jobs 键盘记录</string>
  <key>CFBundleExecutable</key><string>JobsKeyboardRecorder</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>CFBundleShortVersionString</key><string>1.7.0</string>
  <key>CFBundleVersion</key><string>170</string>
  <key>LSMinimumSystemVersion</key><string>10.15</string>
  <key>LSUIElement</key><true/>
  <key>NSHighResolutionCapable</key><true/>
</dict></plist>
JOBS_APP_PLIST
  [[ "$?" == 0 ]] || fail '无法生成 App 信息文件。'
  /bin/mv "${WORK_DIR}/JobsKeyboardRecorder" "$HELPER" || fail '无法保存监听程序。'
  ensure_shell_log_file || fail '无法准备运行状态日志。'
  /usr/bin/codesign --force --sign - "$APP_PATH" >>"$LOG_FILE" 2>&1 || fail '原生 App 本地签名失败。'
  /bin/mv "${WORK_DIR}/JobsKeyboardRecorder.h" "${CACHE_DIR}/JobsKeyboardRecorder.h" || fail '无法保存头文件缓存。'
  /bin/mv "${WORK_DIR}/JobsKeyboardRecorder.m" "${CACHE_DIR}/JobsKeyboardRecorder.m" || fail '无法保存源码缓存。'
  [[ "$("$HELPER" --version)" == '1.7.0' ]] || fail '编译后健康检查失败。'
  log 'ℹ 原生程序已更新；原先已授权的旧版本需要在输入监控中移除，再重新添加当前 App。'
}
# 开始前再次等待回车确认，输入任意字符则取消。
confirm_recording() {
  log '⚠ 即将记录当前会话其它应用中的键盘事件，请确认这是你有权记录的会话。'
  log '⚠ 安全输入之外的私人文字也可能被记录，请自行妥善保管日志。'
  local answer=''
  IFS= read -r 'answer?按回车确认开始；输入任意字符取消；Ctrl+C 终止：' || exit 0
  [[ -z "$answer" ]] || exit 0
}
# 校验记录位置，单文件及编号目录由原生程序在开始记录时统一分配。
prepare_record_location() {
  local downloads_dir="${RECORD_PATH:h}"
  [[ ! -L "$RECORD_PATH" ]] || fail '记录位置不能是符号链接。'
  [[ ! -L "$downloads_dir" ]] || fail '记录父目录不能是符号链接。'
  /bin/mkdir -p "$downloads_dir" || fail "无法创建记录父目录：${downloads_dir}"
  [[ -d "$downloads_dir" && -w "$downloads_dir" && "$(/usr/bin/stat -f '%u' "$downloads_dir")" == "$UID" ]] || fail "下载目录不存在、不属于当前用户或不可写：${downloads_dir}"
  if [[ -e "$RECORD_PATH" ]]; then
    [[ ( -f "$RECORD_PATH" || -d "$RECORD_PATH" ) && "$(/usr/bin/stat -f '%u' "$RECORD_PATH")" == "$UID" ]] || fail "同名记录位置的类型或所有权异常：${RECORD_PATH}"
  fi
  log "✔ 按键记录位置：${RECORD_PATH}（首次为单文件，多次为编号目录）"
}
# 安装当前用户的 stop 命令，只替换本脚本自己生成的入口。
install_stop_command() {
  local bin_dir="${STOP_COMMAND:h}"
  local existing_command=''
  existing_command="$(whence -p stop 2>/dev/null)"
  [[ -z "$existing_command" || "$existing_command" == "$STOP_COMMAND" ]] || fail "已有同名 stop 命令，未覆盖：${existing_command}"
  [[ ! -L "$bin_dir" && ! -L "$STOP_COMMAND" ]] || fail 'stop 目录或入口不能是符号链接。'
  /bin/mkdir -p "$bin_dir" || fail '无法创建当前用户命令目录。'
  [[ "$(/usr/bin/stat -f '%u' "$bin_dir")" == "$UID" ]] || fail 'stop 命令目录不属于当前用户。'
  if [[ -e "$STOP_COMMAND" ]]; then
    [[ -f "$STOP_COMMAND" && "$(/usr/bin/stat -f '%u' "$STOP_COMMAND")" == "$UID" ]] &&
      /usr/bin/grep -Fqx '# JobsKeyboardRecorder stop command' "$STOP_COMMAND" || fail '已有其它 stop 文件，未覆盖。'
  fi
  /bin/cat >"${WORK_DIR}/stop" <<'JOBS_STOP_COMMAND'
#!/bin/zsh
# JobsKeyboardRecorder stop command
# 停止当前用户的键盘记录，等待保存完成；不启动新的监听。
# 将停止请求交给原生控制通道，保留保存确认和退出码。
stop_current_session() {
  local recorder_helper="${HOME}/Library/Caches/JobsKeyboardRecorder/JobsKeyboardRecorder.app/Contents/MacOS/JobsKeyboardRecorder"
  if [[ ! -x "$recorder_helper" ]]; then
    print -r -- '■ 当前没有运行中的新版记录器。'
    return 0
  fi
  "$recorder_helper" --stop "${HOME}/Library/Caches/JobsKeyboardRecorder/control.sock"
}
# 单一入口只负责停止，不启动记录或请求权限。
main() {
  stop_current_session # 请求停止并等待原生程序保存完成。
}
main "$@"
JOBS_STOP_COMMAND
  [[ "$?" == 0 ]] || fail '无法生成 stop 命令。'
  /bin/chmod 700 "${WORK_DIR}/stop" || fail '无法设置 stop 执行权限。'
  /bin/mv "${WORK_DIR}/stop" "$STOP_COMMAND" || fail '无法安装 stop 命令。'
  if [[ ":${PATH}:" != *":${bin_dir}:"* ]]; then
    local rc_file="${ZDOTDIR:-$HOME}/.zshrc"
    [[ ! -L "$rc_file" && ( ! -e "$rc_file" || -f "$rc_file" ) ]] || fail 'zsh 配置类型异常，请用脚本的 stop 参数停止。'
    if ! /usr/bin/grep -Fqx '# >>> JobsKeyboardRecorder stop PATH >>>' "$rc_file" 2>/dev/null; then
      if [[ -e "$rc_file" ]]; then
        /bin/cp -p "$rc_file" "${rc_file}.keyboard-recorder.$(/bin/date +%Y%m%d%H%M%S).bak" || fail '无法备份 zsh 配置。'
      fi
      /bin/cat >>"$rc_file" <<'JOBS_STOP_PATH'

# >>> JobsKeyboardRecorder stop PATH >>>
export PATH="$HOME/.local/bin:$PATH"
# <<< JobsKeyboardRecorder stop PATH <<<
JOBS_STOP_PATH
      [[ "$?" == 0 ]] || fail '无法配置新终端的 stop 命令路径。'
    fi
  fi
  log "✔ 停止命令已就绪：${STOP_COMMAND}；打开终端，输入 stop 后按回车即可关闭并保存。"
}
# 突出显示授权对象并打开输入监控页面，授权由用户在系统设置中完成。
show_input_monitoring_help() {
  local app_message="ℹ 需要授权的 App：${APP_PATH}"
  log "$app_message" >/dev/null
  intro_line title "$app_message"
  if /usr/bin/open 'x-apple.systempreferences:com.apple.preference.security?Privacy_ListenEvent' >>"$LOG_FILE" 2>&1; then
    log 'ℹ 已请求打开系统设置 → 隐私与安全性 → 输入监控，请手动添加上面的 App 并开启。'
  else
    log '⚠ 无法自动打开授权页面，请手动前往系统设置 → 隐私与安全性 → 输入监控。'
  fi
  log 'ℹ 如果已有开关仍未生效，请在输入监控列表中移除旧项，再添加上面的 App 并开启；随后重新运行脚本。'
  log 'ℹ 当前尚未开始记录。看到“记录器已成功启动”后，仍需保持启动终端运行。'
}
# 持续等待本次会话，终端或脚本退出时由清理钩子撤销记录资格。
wait_for_recorder() {
  local ticket="${WORK_DIR}/startup-ticket"
  while "$HELPER" --status "$CONTROL_PATH" "$ticket" >/dev/null 2>&1; do
    /bin/sleep 0.25
  done
  print -r -- '■ 记录会话已结束，启动脚本即将退出。'
}
# 由 LaunchServices 打开授权对象，启动脚本保持运行并拥有本次会话。
run_recorder() {
  local ticket="${WORK_DIR}/startup-ticket"
  : >"$ticket" || fail '无法准备启动确认。'
  /usr/bin/open -g -n "$APP_PATH" --args --record "$RECORD_PATH" "$LOG_FILE" "$CONTROL_PATH" "$ticket" "$$" || fail '无法打开原生记录器。'
  local start_seconds="$SECONDS"
  while (( SECONDS - start_seconds < 15 )); do
    if "$HELPER" --status "$CONTROL_PATH" "$ticket" >/dev/null 2>&1; then
      RECORDER_STARTED=1
      log '✔ 记录器已成功启动，请保持此终端运行。'
      log "ℹ 实际保存位置：${RECORD_PATH}（下载目录，不在文稿目录）"
      log 'ℹ 菜单栏显示记录状态；启动脚本退出后，不再创建或重建记录路径。'
      log '■ 关闭方法：Ctrl+C、关闭此终端、菜单栏“停止并保存”，或另一个终端输入 stop。'
      log 'ℹ 注销或重启后不会自动启动。'
      wait_for_recorder
      return 0
    fi
    if /usr/bin/grep -Fq '✖ 启动失败：' "$LOG_FILE"; then
      /usr/bin/tail -n 4 "$LOG_FILE"
      if /usr/bin/grep -Fq '输入监控中允许 JobsKeyboardRecorder' "$LOG_FILE"; then
        show_input_monitoring_help
      fi
      fail '启动失败；若系统要求输入监控授权，请授权 JobsKeyboardRecorder 后重新运行。'
    fi
    /bin/sleep 0.2
  done
  /bin/rm -f "$ticket"
  fail '启动未在预期时间内确认，已取消启动；请检查运行状态日志。'
}
# 编排说明、停止分流、原生 App 准备与前台会话管理。
main() {
  show_script_intro_and_wait "$@" # 启动先确认；停止参数只显示停止说明。
  initialize_runtime # 确认后初始化私有日志和清理钩子。
  handle_control_command "$@" # 停止命令直接收尾，不进入编译和记录流程。
  check_environment # 检查 macOS、编译器与 SDK 的真实可用性。
  prepare_native_helper # 编译或复用内嵌源码与原生状态 App。
  confirm_recording # 明确确认允许记录当前会话的键盘事件。
  prepare_record_location # 检查下载位置，保持首次单文件和多次编号目录的规则。
  install_stop_command # 提供可从新终端直接执行的 stop 命令。
  run_recorder # 由 App 自查权限并绑定启动脚本，持续等待会话结束。
}

main "$@"
