#!/bin/bash

set -u

RED='\033[31m'
GREEN='\033[32m'
YELLOW='\033[33m'
BLUE='\033[34m'
NC='\033[0m'

PROJECT_PATH=''
OUTPUT_DIR=''
PODSPEC_COUNT=0
PODFILE_COUNT=0
TOTAL_COUNT=0

print_intro() {
    printf "${BLUE}============================================================${NC}\n"
    printf "${BLUE} 提取项目中的 CocoaPods 相关文件${NC}\n"
    printf "${BLUE}============================================================${NC}\n"
    printf "\n"
    printf "功能说明：\n"
    printf "1. 从你拖入的 Xcode 工程目录中递归查找并复制所有 .podspec 文件。\n"
    printf "2. 只从你拖入的工程根目录复制 Podfile.deps、Podfile、Podfile.lock。\n"
    printf "3. Podfile.deps、Podfile、Podfile.lock 不会递归查找子目录，避免把 Pods、Example、Demo 里的 Podfile 全复制出来。\n"
    printf "4. 复制结果会放到桌面新建的 PodspecFiles_时间戳 文件夹中。\n"
    printf "5. 如果 Podfile.deps、Podfile、Podfile.lock 不存在，只会用红字提示，不会影响脚本继续执行。\n"
    printf "6. 如果出现同名文件，会自动追加 _1、_2 等序号，避免覆盖。\n"
    printf "\n"
    printf "${YELLOW}按回车开始执行...${NC}"
    read -r _
    printf "\n"
}

normalize_dragged_path() {
    local RAW_PATH="$1"

    # 去掉首尾空白
    RAW_PATH="$(echo "$RAW_PATH" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')"

    # 去掉首尾引号
    RAW_PATH="${RAW_PATH%\"}"
    RAW_PATH="${RAW_PATH#\"}"
    RAW_PATH="${RAW_PATH%\'}"
    RAW_PATH="${RAW_PATH#\'}"

    # 处理 macOS 终端拖入路径时的反斜杠转义，例如 My\ Project
    printf '%s\n' "$RAW_PATH" | sed 's/\\\(.\)/\1/g'
}

read_project_path() {
    local RAW_PATH
    local NORMALIZED_PATH

    while true; do
        echo "请把 Xcode 工程目录拖到这里，然后按回车："
        read -r RAW_PATH

        NORMALIZED_PATH="$(normalize_dragged_path "$RAW_PATH")"

        if [ -d "$NORMALIZED_PATH" ]; then
            PROJECT_PATH="$NORMALIZED_PATH"
            break
        fi

        echo ""
        printf "${RED}错误：路径不存在，或者不是文件夹：${NC}\n"
        echo "$NORMALIZED_PATH"
        echo "请重新输入。"
        echo ""
    done
}

create_output_dir() {
    local DESKTOP_DIR="$HOME/Desktop"
    local TIME_TEXT

    TIME_TEXT="$(date '+%Y%m%d_%H%M%S')"
    OUTPUT_DIR="$DESKTOP_DIR/PodspecFiles_$TIME_TEXT"

    mkdir -p "$OUTPUT_DIR"
}

make_unique_target_file() {
    local SOURCE_FILE="$1"
    local FILE_NAME
    local TARGET_FILE
    local NAME
    local EXT
    local INDEX

    FILE_NAME="$(basename "$SOURCE_FILE")"
    TARGET_FILE="$OUTPUT_DIR/$FILE_NAME"

    if [ ! -e "$TARGET_FILE" ]; then
        echo "$TARGET_FILE"
        return
    fi

    if [[ "$FILE_NAME" == *.* ]]; then
        NAME="${FILE_NAME%.*}"
        EXT=".${FILE_NAME##*.}"
    else
        NAME="$FILE_NAME"
        EXT=""
    fi

    INDEX=1

    while [ -e "$OUTPUT_DIR/${NAME}_${INDEX}${EXT}" ]; do
        INDEX=$((INDEX + 1))
    done

    echo "$OUTPUT_DIR/${NAME}_${INDEX}${EXT}"
}

copy_to_output_dir() {
    local SOURCE_FILE="$1"
    local TARGET_FILE

    TARGET_FILE="$(make_unique_target_file "$SOURCE_FILE")"

    cp -p "$SOURCE_FILE" "$TARGET_FILE"
    echo "已复制：$SOURCE_FILE"

    TOTAL_COUNT=$((TOTAL_COUNT + 1))
}

copy_podspec_files() {
    local PODSPEC_FILE

    while IFS= read -r -d '' PODSPEC_FILE; do
        copy_to_output_dir "$PODSPEC_FILE"
        PODSPEC_COUNT=$((PODSPEC_COUNT + 1))
    done < <(find "$PROJECT_PATH" -type f -iname "*.podspec" -print0)
}

copy_root_podfile_by_name() {
    local PODFILE_NAME="$1"
    local PODFILE_FILE="$PROJECT_PATH/$PODFILE_NAME"

    if [ -f "$PODFILE_FILE" ]; then
        copy_to_output_dir "$PODFILE_FILE"
        PODFILE_COUNT=$((PODFILE_COUNT + 1))
    else
        printf "${RED}未找到：%s${NC}\n" "$PODFILE_NAME"
    fi
}

copy_root_podfiles() {
    copy_root_podfile_by_name "Podfile.deps"
    copy_root_podfile_by_name "Podfile"
    copy_root_podfile_by_name "Podfile.lock"
}

remove_empty_output_dir_if_needed() {
    if [ "$TOTAL_COUNT" -eq 0 ]; then
        rmdir "$OUTPUT_DIR"
        printf "${RED}没有找到任何 .podspec、Podfile.deps、Podfile、Podfile.lock 文件。${NC}\n"
        exit 0
    fi
}

print_result() {
    echo ""
    printf "${GREEN}完成，共复制 %s 个文件。${NC}\n" "$TOTAL_COUNT"
    echo "其中 .podspec 文件：$PODSPEC_COUNT 个。"
    echo "其中 Podfile 相关文件：$PODFILE_COUNT 个。"
    echo "输出目录：$OUTPUT_DIR"
}

open_output_dir() {
    open "$OUTPUT_DIR"
}

main() {
    # 1. 打印脚本自述，并等待用户确认开始。
    print_intro

    # 2. 读取并校验用户拖入的 Xcode 工程目录。
    read_project_path

    # 3. 在桌面创建本次导出的目标文件夹。
    create_output_dir

    # 4. 递归复制项目中的 .podspec 文件。
    copy_podspec_files

    # 5. 只从工程根目录复制 Podfile.deps、Podfile、Podfile.lock。
    copy_root_podfiles

    # 6. 如果什么都没复制到，则删除空目录并正常结束。
    remove_empty_output_dir_if_needed

    # 7. 打印统计结果，并打开输出目录。
    print_result
    open_output_dir
}

main "$@"
