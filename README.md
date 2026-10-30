# `JobsCommand@Others`

![Jobs出品，必属精品](https://picsum.photos/1500/400)

<!-- jobs-toc:start -->
<!-- jobs-toc:source {"v":2,"token":"[toc]"} -->
<details>
<summary>📚 目录（点击展开 / 收起）</summary>

- [🔥 前言](#jobs-toc-heading-1)
- [双平台入口](#jobs-toc-heading-2)
- [一、📦 包结构](#jobs-toc-heading-3)
- [二、📚 脚本清单](#jobs-toc-heading-4)
- [三、目录结构](#repository-layout)
- [四、脚本执行流程](#script-workflows)
  - [【MacOS】Caddy本地域名映射.command](#jobs-toc-heading-7)
  - [JobsKeyboardRecorder.command](#jobs-toc-heading-8)
  - [【MacOS】Jobs计划任务.command](#jobs-toc-heading-9)
  - [【MacOS】Mock.command](#jobs-toc-heading-10)
  - [【MacOS】StirlingPDF.command](#jobs-toc-heading-11)
  - [【MacOS】Xcode编译耗时菜单栏.command](#jobs-toc-heading-12)
  - [【MacOS】⏬下载Mock数据.command](#jobs-toc-heading-13)
  - [【MacOS】⚙️『 已损坏，无法打开： 来自身份不明的开发者』等问题修复工具.command](#jobs-toc-heading-14)
  - [【MacOS】⚙️双击写入文件：不带#的字符串.command](#jobs-toc-heading-15)
  - [【MacOS】⚙️双击安装（升级）Homebrew.command](#jobs-toc-heading-16)
  - [【MacOS】⚙️给文件添加和删除执行权限.command](#jobs-toc-heading-17)
  - [【MacOS】⚙️运行授权.command](#jobs-toc-heading-18)
  - [【MacOS】全文件搜索文字替换.command](#jobs-toc-heading-19)
  - [【MacOS】去乱码.command](#jobs-toc-heading-20)
  - [【MacOS】✂️源文件压缩拆分➤子卷.command](#jobs-toc-heading-21)
  - [【MacOS】🧩子卷➤合而为一源文件.command](#jobs-toc-heading-22)
  - [【MacOS】🧬MD5.command](#jobs-toc-heading-23)
  - [【MacOS】时间戳转换工具.command](#jobs-toc-heading-24)
  - [【MacOS】静态网页截全图.command](#jobs-toc-heading-25)
  - [【MacOS】🎈双击打开当前路径终端.command](#jobs-toc-heading-26)
  - [【MacOS】📦Fastfile.command](#jobs-toc-heading-27)
  - [【MacOS】🧮双击文件数统计.command](#jobs-toc-heading-28)

</details>
<!-- jobs-toc:end -->

## <span id="jobs-toc-heading-1" data-jobs-toc="v2">🔥 <font id=前言>前言</font></span><!-- jobs-toc:heading-end -->

本仓提供本地服务、文件处理、权限与开发辅助工具。macOS 与 Windows 各有对应入口，先按任务选择具体功能，再核对该脚本的输入、产物和作用范围。

## <span id="jobs-toc-heading-2" data-jobs-toc="v2">双平台入口 <a href="#前言" style="font-size:17px; color:green;"><b>🔼</b></a> <a href="#🔚" style="font-size:17px; color:green;"><b>🔽</b></a></span><!-- jobs-toc:heading-end -->

原脚本包和资源位于[MacOS](./MacOS/README.md)；MD5 工具包与共享分卷测试样本位于 [Release](./Release/README.md)。Windows对照实现位于[WindowsOS](./WindowsOS/README.md)，使用PowerShell 5.1+与可双击CMD。Apple模拟器、Xcode与macOS专属权限工具保留在MacOS。Windows安装、服务和配置变更均先说明目标并按提示确认，实际平台验收状态见Windows说明。

## <span id="jobs-toc-heading-3" data-jobs-toc="v2">一、📦 包结构 <a href="#前言" style="font-size:17px; color:green;"><b>🔼</b></a> <a href="#🔚" style="font-size:17px; color:green;"><b>🔽</b></a></span><!-- jobs-toc:heading-end -->

每个目录包含：

```text
脚本名.command/
├── 脚本名.command
└── README.md
```

## <span id="jobs-toc-heading-4" data-jobs-toc="v2">二、📚 脚本清单 <a href="#前言" style="font-size:17px; color:green;"><b>🔼</b></a> <a href="#🔚" style="font-size:17px; color:green;"><b>🔽</b></a></span><!-- jobs-toc:heading-end -->

- `【MacOS】⚙️双击安装（升级）Homebrew.command`
- `【MacOS】⏬下载Mock数据.command`
- `【MacOS】📦Fastfile.command`
- `【MacOS】去乱码.command`
- `【MacOS】⚙️给文件添加和删除执行权限.command`
- `【MacOS】⚙️双击写入文件：不带#的字符串.command`
- `【MacOS】时间戳转换工具.command`
- `【MacOS】全文件搜索文字替换.command`
- `【MacOS】⚙️『 已损坏，无法打开： 来自身份不明的开发者』等问题修复工具.command`
- `【MacOS】🎈双击打开当前路径终端.command`
- `【MacOS】🧮双击文件数统计.command`
- `【MacOS】⚙️运行授权.command`
- `【MacOS】静态网页截全图.command`

## 三、<span id="repository-layout">目录结构</span> <a href="#前言" style="font-size:17px; color:green;"><b>🔼</b></a> <a href="#🔚" style="font-size:17px; color:green;"><b>🔽</b></a>

下面按平台目录与 Release 资源列出真实文件与目录；包内主脚本由下方完整名称直接进入。

Windows 每项功能独占同名目录，目录内放成对的 `.cmd`、`.ps1` 和 `README.md`；公共函数集中在 `WindowsOS/Common/`，功能专属资源随对应目录保存。例如 [MD5 功能目录](<./WindowsOS/【WindowsOS】MD5/README.md>)，完整清单见 [WindowsOS 总览](./WindowsOS/README.md)。

```text
JobsCommand@Others/
├── MacOS/  # 原脚本包、资源与分类链接
├── WindowsOS/  # PowerShell 5.1+ 与双击 CMD
├── Release/  # MD5 工具包与共享分卷测试样本
│   ├── README.md
│   ├── 【MacOS】🧬MD5.command/  # 1 个 macOS 入口及其 README
│   └── libiPhone-lib/  # 4 个二进制分卷
└── README.md

MacOS/
├── icon.png
├── 【MacOS】Caddy本地域名映射.command/  # 1 个入口
├── 【MacOS】JobsKeyboardRecorder.command/  # 1 个入口
├── 【MacOS】Jobs计划任务.command/  # 1 个入口
├── 【MacOS】Mock.command/  # 1 个入口
├── 【MacOS】StirlingPDF.command/  # 1 个入口
├── 【MacOS】Xcode编译耗时菜单栏.command/  # 1 个入口
├── 【MacOS】⏬下载Mock数据.command/  # 1 个入口
├── 【MacOS】⚙️『 已损坏，无法打开： 来自身份不明的开发者』等问题修复工具.command/  # 1 个入口
├── 【MacOS】⚙️双击写入文件：不带#的字符串.command/  # 1 个入口
├── 【MacOS】⚙️双击安装（升级）Homebrew.command/  # 1 个入口
├── 【MacOS】⚙️给文件添加和删除执行权限.command/  # 1 个入口
├── 【MacOS】⚙️运行授权.command/  # 1 个入口
├── 【MacOS】全文件搜索文字替换.command/  # 1 个入口
├── 【MacOS】去乱码.command/  # 1 个入口
├── 【MacOS】文件分拆（合并）测试. command/  # 2 个入口
├── 【MacOS】时间戳转换工具.command/  # 1 个入口
├── 【MacOS】静态网页截全图.command/  # 1 个入口
├── 【MacOS】🎈双击打开当前路径终端.command/  # 1 个入口
├── 【MacOS】📦Fastfile.command/  # 1 个入口
└── 【MacOS】🧮双击文件数统计.command/  # 1 个入口
```

## 四、<span id="script-workflows">脚本执行流程</span> <a href="#前言" style="font-size:17px; color:green;"><b>🔼</b></a> <a href="#🔚" style="font-size:17px; color:green;"><b>🔽</b></a>

MacOS 目录共有 21 个用户入口，Release 目录另有 1 个 MD5 入口（按主 `.command` 文本脚本计数，不含公共模块、测试及资源；依据当前目录，2026-10-26）。这里只列本仓维护的主入口；独立子 Git、测试、函数库及打包资源模板不作为用户运行入口。步骤来自静态源码与配套说明，未执行安装、清理、构建或 Git 写操作。

当前入口使用脚本内置自述，README 用于运行前静态阅读；具体处理范围与交互以各入口的源码和下方流程为准。

### <span id="jobs-toc-heading-7" data-jobs-toc="v2">[【MacOS】Caddy本地域名映射.command](<./MacOS/【MacOS】Caddy本地域名映射.command/【MacOS】Caddy本地域名映射.command>)</span><!-- jobs-toc:heading-end -->

> **目的：** 为本机服务建立 [**Caddy**](https://caddyserver.com/) 域名反向代理。

- 输入本地服务地址和映射域名，检查现有服务。
- 检查 Caddy、端口与配置冲突，按提示准备 hosts / 证书与 Caddyfile。
- 启动代理并自检 HTTPS，打开映射地址；会影响本机解析与代理配置。

### <span id="jobs-toc-heading-8" data-jobs-toc="v2">[JobsKeyboardRecorder.command](<./MacOS/【MacOS】JobsKeyboardRecorder.command/JobsKeyboardRecorder.command>)</span><!-- jobs-toc:heading-end -->

> **目的：** 在明确授权下记录本机键盘事件到指定文件。

- 检查系统权限与编译工具，准备本机原生记录器。
- 确认输出位置与开始记录，处理输入监控授权。
- 启动记录器并提供 stop 入口，结束后核对记录文件；记录内容可能包含敏感输入。

### <span id="jobs-toc-heading-9" data-jobs-toc="v2">[【MacOS】Jobs计划任务.command](<./MacOS/【MacOS】Jobs计划任务.command/【MacOS】Jobs计划任务.command>)</span><!-- jobs-toc:heading-end -->

> **目的：** 安装或管理 Jobs 计划任务原生应用。

- 确认管理范围，检查 Swift、签名和系统调度工具。
- 在菜单中选择构建安装、打开或其它管理动作。
- 执行所选动作并输出应用或调度状态。

### <span id="jobs-toc-heading-10" data-jobs-toc="v2">[【MacOS】Mock.command](<./MacOS/【MacOS】Mock.command/【MacOS】Mock.command/【MacOS】Mock.command>)</span><!-- jobs-toc:heading-end -->

> **目的：** 启动或管理可读取本地 JSON 的 Mock 服务。

- 准备 [**Python**](https://www.python.org/) 与服务目录，检查数据文件和端口。
- 按 start / status / stop 等所选动作管理本入口的后台进程。
- 服务就绪后显示并可打开地址，日志保留请求或启动失败信息。

### <span id="jobs-toc-heading-11" data-jobs-toc="v2">[【MacOS】StirlingPDF.command](<./MacOS/【MacOS】StirlingPDF.command/【MacOS】StirlingPDF.command>)</span><!-- jobs-toc:heading-end -->

> **目的：** 准备并运行本地 [**Stirling PDF**](https://www.stirlingpdf.com/) 服务及可选访问配置。

- 检查 Java、服务文件和端口，读取启动参数。
- 按选择下载或复用服务，准备后台运行与访问配置。
- 启动并检查 HTTP 可用性，显示访问地址。
  - 如果使用 --status 或 --stop，改为查看状态或停止本入口管理的服务。

### <span id="jobs-toc-heading-12" data-jobs-toc="v2">[【MacOS】Xcode编译耗时菜单栏.command](<./MacOS/【MacOS】Xcode编译耗时菜单栏.command/【MacOS】Xcode编译耗时菜单栏.command>)</span><!-- jobs-toc:heading-end -->

> **目的：** 安装或刷新显示 [**Xcode**](https://developer.apple.com/xcode/) 编译耗时的菜单栏工具。

- 检查 Swift 编译环境并选择工程 / 安装动作。
- 准备构建记录与 Hook，编译菜单栏 App。
- 安装或刷新工具并启动，后续从构建记录显示耗时。

### <span id="jobs-toc-heading-13" data-jobs-toc="v2">[【MacOS】⏬下载Mock数据.command](<./MacOS/【MacOS】⏬下载Mock数据.command/【MacOS】⏬下载Mock数据.command>)</span><!-- jobs-toc:heading-end -->

> **目的：** 将预设 Mock 数据仓库克隆或更新到本机。

- 检查 [**Git**](https://git-scm.com/) 与源码中配置的目标位置。
- 目标不存在时克隆，已存在时按交互决定更新。
- 输出结果并显示本地数据目录。

### <span id="jobs-toc-heading-14" data-jobs-toc="v2">[【MacOS】⚙️『 已损坏，无法打开： 来自身份不明的开发者』等问题修复工具.command](<./MacOS/【MacOS】⚙️『 已损坏，无法打开： 来自身份不明的开发者』等问题修复工具.command/【MacOS】⚙️『 已损坏，无法打开： 来自身份不明的开发者』等问题修复工具.command>)</span><!-- jobs-toc:heading-end -->

> **目的：** 处理指定应用的隔离属性或启动校验问题。

- 拖入或确认目标 .app，检查应用目录。
- 查看将修改的安全属性，输入源码要求的 YES 确认。
- 执行针对该 App 的修复并给出结果，随后人工尝试启动。

### <span id="jobs-toc-heading-15" data-jobs-toc="v2">[【MacOS】⚙️双击写入文件：不带#的字符串.command](<./MacOS/【MacOS】⚙️双击写入文件：不带%23的字符串.command/【MacOS】⚙️双击写入文件：不带%23的字符串.command>)</span><!-- jobs-toc:heading-end -->

> **目的：** 向选定文件追加去掉注释标记的配置字符串。

- 输入目标文件，或使用源码声明的默认文件。
- 输入需要写入的字符串并处理前导注释标记。
- 检查重复项后按脚本规则追加，显示文件结果。

### <span id="jobs-toc-heading-16" data-jobs-toc="v2">[【MacOS】⚙️双击安装（升级）Homebrew.command](<./MacOS/【MacOS】⚙️双击安装（升级）Homebrew.command/【MacOS】⚙️双击安装（升级）Homebrew.command>)</span><!-- jobs-toc:heading-end -->

> **目的：** 准备 [**Homebrew**](https://brew.sh/) 并按选择安装开发工具。

- 检查已有 Homebrew；缺失时按提示选择安装位置。
- 配置当前 Shell 的 Homebrew 环境，已有安装按提示选择是否升级。
- 依次处理源码列出的工具安装项并输出结果。

### <span id="jobs-toc-heading-17" data-jobs-toc="v2">[【MacOS】⚙️给文件添加和删除执行权限.command](<./MacOS/【MacOS】⚙️给文件添加和删除执行权限.command/【MacOS】⚙️给文件添加和删除执行权限.command>)</span><!-- jobs-toc:heading-end -->

> **目的：** 切换指定文件或目录的执行权限。

- 选择添加或删除执行权限。
- 拖入目标路径并核对匹配范围。
- 执行 chmod +x 或 -x，逐项报告结果。

### <span id="jobs-toc-heading-18" data-jobs-toc="v2">[【MacOS】⚙️运行授权.command](<./MacOS/【MacOS】⚙️运行授权.command/【MacOS】⚙️运行授权.command>)</span><!-- jobs-toc:heading-end -->

> **目的：** 为指定脚本或目录中的入口补执行权限。

- 阅读影响范围，输入或拖入待授权目标。
- 选择单项或递归扫描范围并执行 chmod。
  - 如果选择递归，会处理该目标下匹配的脚本；先确认目录范围。
- 输出成功与失败结果，按提示继续或退出。

### <span id="jobs-toc-heading-19" data-jobs-toc="v2">[【MacOS】全文件搜索文字替换.command](<./MacOS/【MacOS】全文件搜索文字替换.command/【MacOS】全文件搜索文字替换.command>)</span><!-- jobs-toc:heading-end -->

> **目的：** 批量替换目标文件树中的指定文本。

- 输入待查文字、替换文字和文件 / 目录路径。
- 扫描符合范围的文件，按配置备份原文件。
- 写入替换并汇总匹配结果，运行前确认替换范围。

### <span id="jobs-toc-heading-20" data-jobs-toc="v2">[【MacOS】去乱码.command](<./MacOS/【MacOS】去乱码.command/【MacOS】去乱码.command>)</span><!-- jobs-toc:heading-end -->

> **目的：** 交互解码 URL 编码字符串。

- 检查 Python 或 [**Ruby**](https://www.ruby-lang.org/) 解码能力。
- 输入编码字符串并执行解码。
- 显示可读文本，继续输入或用退出指令结束。

### <span id="jobs-toc-heading-21" data-jobs-toc="v2">[【MacOS】✂️源文件压缩拆分➤子卷.command](<./MacOS/【MacOS】文件分拆（合并）测试. command/【MacOS】✂️源文件压缩拆分➤子卷.command/【MacOS】✂️源文件压缩拆分➤子卷.command>)</span><!-- jobs-toc:heading-end -->

> **目的：** 将指定源文件按上限拆成可传输的原始子卷。

- 拖入单文件或目录，也可传一个位置参数；目录模式使用 fzf 明确勾选。
- 选择 50 / 100 / 1900 MiB 或自定义上限，均衡切分，生成 `完整原文件名@序号of总数`；文件名中的“压缩”是兼容名称，实际不压缩字节。
- 大小、SHA-256 及源状态校验后原子无覆盖发布；默认保留源文件，仅精确输入 `YES` 才删除。

### <span id="jobs-toc-heading-22" data-jobs-toc="v2">[【MacOS】🧩子卷➤合而为一源文件.command](<./MacOS/【MacOS】文件分拆（合并）测试. command/【MacOS】🧩子卷➤合而为一源文件.command/【MacOS】🧩子卷➤合而为一源文件.command>)</span><!-- jobs-toc:heading-end -->

> **目的：** 按子卷顺序重建源文件。

- 输入分卷目录或父目录，识别当前层与一级子目录，使用 fzf 勾选分卷组。
- 核对完整原名、总数、缺号、重复及非空条件，按数字卷号合并；拒绝覆盖已有目标。
- 大小、SHA-256 与输入状态校验通过才发布；分卷默认保留，仅精确输入 `YES` 后删除本组精确清单。

两项与 `WindowsOS_11` 对应 macOS 脚本保持同版本、同内容；[Windows 原生分卷](<./WindowsOS/【WindowsOS】源文件压缩分卷/README.md>)和[Windows 原生合并](<./WindowsOS/【WindowsOS】子卷合并/README.md>)默认使用相同原始卷格式，保留 `-LegacyManifest` 的旧清单 / gzip 模式。

### <span id="jobs-toc-heading-23" data-jobs-toc="v2">[【MacOS】🧬MD5.command](<./Release/【MacOS】🧬MD5.command/【MacOS】🧬MD5.command>)</span><!-- jobs-toc:heading-end -->

> **目的：** 计算指定文件的 MD5 校验值。

- 检查系统可用的 MD5 工具。
- 拖入文件或输入路径，校验文件是否可读。
- 计算并显示摘要，继续下一轮或退出。

### <span id="jobs-toc-heading-24" data-jobs-toc="v2">[【MacOS】时间戳转换工具.command](<./MacOS/【MacOS】时间戳转换工具.command/【MacOS】时间戳转换工具.command>)</span><!-- jobs-toc:heading-end -->

> **目的：** 把 Unix 秒、毫秒或微秒时间戳转换为日期。

- 输入时间戳并检查格式与位数。
- 识别时间单位，调用系统日期工具转换。
- 显示转换结果，继续输入或退出。

### <span id="jobs-toc-heading-25" data-jobs-toc="v2">[【MacOS】静态网页截全图.command](<./MacOS/【MacOS】静态网页截全图.command/【MacOS】静态网页截全图.command>)</span><!-- jobs-toc:heading-end -->

> **目的：** 将本地 HTML 整页或指定元素截图为图片。

- 检查 [**Node.js**](https://nodejs.org/)、[**npm**](https://www.npmjs.com/) 与 [**Puppeteer**](https://pptr.dev/)，选择本地 HTML。
- 输入 CSS 选择器；留空时使用整页模式。
- 启动无头浏览器完成截图，并在 [**Finder**](https://support.apple.com/guide/mac-help/mchlp2605/mac) 定位结果。

### <span id="jobs-toc-heading-26" data-jobs-toc="v2">[【MacOS】🎈双击打开当前路径终端.command](<./MacOS/【MacOS】🎈双击打开当前路径终端.command/【MacOS】🎈双击打开当前路径终端.command>)</span><!-- jobs-toc:heading-end -->

> **目的：** 在脚本对应目录打开系统终端。

- 读取脚本目录并核对需要进入的位置。
- 通过 AppleScript 打开 [**Terminal**](https://support.apple.com/guide/terminal/welcome/mac) 并执行 cd。
- 在新终端继续操作；以脚本中实际窗口处理逻辑为准。

### <span id="jobs-toc-heading-27" data-jobs-toc="v2">[【MacOS】📦Fastfile.command](<./MacOS/【MacOS】📦Fastfile.command/【MacOS】📦Fastfile.command>)</span><!-- jobs-toc:heading-end -->

> **目的：** 为检测到的工程准备或打开 [**fastlane**](https://fastlane.tools/) 的 Fastfile。

- 识别工程类型，检查菜单工具与 fastlane。
- 查找现有 Fastfile，缺失时按脚本模板创建。
- 选择编辑器或 Finder 打开目标文件，后续打包使用其中配置。

### <span id="jobs-toc-heading-28" data-jobs-toc="v2">[【MacOS】🧮双击文件数统计.command](<./MacOS/【MacOS】🧮双击文件数统计.command/【MacOS】🧮双击文件数统计.command>)</span><!-- jobs-toc:heading-end -->

> **目的：** 统计目标目录中的文件数量。

- 选择待统计目录并检查路径。
- 递归遍历目录，计算各级文件数量。
- 输出统计结果，按提示继续或退出。

<a id="🔚" href="#前言" style="font-size:17px; color:green; font-weight:bold;">我是有底线的➤点我回到首页</a>
