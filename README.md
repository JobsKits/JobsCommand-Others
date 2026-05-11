# `MacOS脚本升级优化版` <a href="#前言" style="font-size:17px; color:green;"><b>🔼</b></a> <a href="#🔚" style="font-size:17px; color:green;"><b>🔽</b></a>

![Jobs倾情奉献](https://picsum.photos/1500/400 "Jobs出品，必属精品")

[toc]

## 🔥 <font id=前言>前言</font>

本压缩包由原始 `.command` 脚本升级整理而来。每个脚本都被放入同名文件夹，文件夹名称保留脚本完整文件名和 `.command` 后缀。

## 一、📦 包结构 <a href="#前言" style="font-size:17px; color:green;"><b>🔼</b></a> <a href="#🔚" style="font-size:17px; color:green;"><b>🔽</b></a>

每个目录包含：

```text
脚本名.command/
├── 脚本名.command
└── README.md
```

## 二、✅ 统一升级点 <a href="#前言" style="font-size:17px; color:green;"><b>🔼</b></a> <a href="#🔚" style="font-size:17px; color:green;"><b>🔽</b></a>

* 统一使用 `#!/bin/zsh`。
* 统一使用彩色日志函数和 `/tmp/脚本名.log`。
* 统一使用 `SCRIPT_DIR` / `SCRIPT_PATH` 定位脚本路径。
* 统一在 `main "$@"` 收口执行。
* 双击脚本时先打印同目录 README，并等待回车继续。
* 涉及升级的流程统一改成：直接回车跳过；输入任意字符后回车执行升级。
* 每个脚本配套一份按固定格式重写的 README。

## 三、📚 脚本清单 <a href="#前言" style="font-size:17px; color:green;"><b>🔼</b></a> <a href="#🔚" style="font-size:17px; color:green;"><b>🔽</b></a>

* `【MacOS】⚙️双击安装（升级）Homebrew.command`
* `【MacOS】⏬下载Mock数据.command`
* `【MacOS】📦Fastfile.command`
* `【MacOS】去乱码.command`
* `【MacOS】⚙️给文件添加和删除执行权限.command`
* `【MacOS】⚙️双击写入文件：不带#的字符串.command`
* `【MacOS】时间戳转换工具.command`
* `【MacOS】全文件搜索文字替换.command`
* `【MacOS】⚙️『 已损坏，无法打开: 来自身份不明的开发者』等问题修复工具.command`
* `【MacOS】🎈双击打开当前路径终端.command`
* `【MacOS】🧮双击文件数统计.command`
* `【MacOS】⚙️运行授权.command`
* `【MacOS】静态网页截全图.command`

## 八、🍺 Homebrew 自检统一标准 <a href="#前言" style="font-size:17px; color:green;"><b>🔼</b></a> <a href="#🔚" style="font-size:17px; color:green;"><b>🔽</b></a>

本包里凡是涉及 Homebrew 的脚本，已统一成同一套交互规范：**回车跳过更新，输入任意字符后回车执行更新流程**。更新流程固定包含 `brew update`、`brew upgrade`、`brew cleanup`、`brew doctor`、`brew -v`。

<a id="🔚" href="#前言" style="font-size:17px; color:green; font-weight:bold;">我是有底线的➤点我回到首页</a>
