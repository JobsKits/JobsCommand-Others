#!/bin/bash

# ✅ 打印绿色信息
print_green() {
    echo -e "\033[0;32m$1\033[0m"
}

# ✅ 显示脚本功能说明
print_green "🛠️ 脚本功能："
print_green "👉 向目标文件写入指定字符串（仅当该字符串未被非注释形式写入时）"
print_green "👉 忽略已存在的注释行（以 # 开头）"
print_green "👉 自动创建目标文件（若不存在）"
print_green "📌 注意：路径必须使用 \$HOME，不支持 ~ 符号自动展开"

echo ""
read -p "✅ 按下回车键继续执行，或按 Ctrl+C 取消..."

# ✅ 定义函数：向目标文件写入唯一字符串（排除注释行）
add_string_if_unique() {
    local FILE_PATH="$1"
    local STRING="$2"
    local UNIQUE=true

    # 文件不存在则创建
    if [ ! -f "$FILE_PATH" ]; then
        touch "$FILE_PATH"
    fi

    # 逐行检查是否已包含指定字符串（排除注释行）
    while IFS= read -r line; do
        if [[ "$line" =~ $STRING ]]; then
            if ! [[ "$line" =~ ^[[:space:]]*# ]]; then
                UNIQUE=false
                break
            fi
        fi
    done < "$FILE_PATH"

    # 写入字符串（若唯一）
    if $UNIQUE; then
        echo "$STRING" >> "$FILE_PATH"
        print_green "✅ 字符串 '$STRING' 已添加到文件 $FILE_PATH"
    else
        echo "⚠️ 文件 $FILE_PATH 已包含字符串 '$STRING'（非注释行）"
    fi
}

# ✅ 示例调用（请根据需要修改路径和字符串）
add_string_if_unique "$HOME/.bash_profile" "export PATH=\$PATH:/usr/local/bin"
