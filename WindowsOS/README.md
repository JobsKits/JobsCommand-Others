# `JobsCommand@Others` WindowsOS 脚本

![Jobs出品，必属精品](https://picsum.photos/1500/400)

<!-- jobs-toc:start -->
<!-- jobs-toc:source {"v":2,"token":"[toc]"} -->
<details>
<summary>📚 目录（点击展开 / 收起）</summary>

- [🔥 前言](#%E5%89%8D%E8%A8%80)
- [一、运行方式](#jobs-toc-heading-2)
- [二、入口与流程](#jobs-toc-heading-3)
  - [【WindowsOS】Caddy本地域名映射.cmd](#jobs-toc-heading-4)
  - [【WindowsOS】Jobs计划任务.cmd](#jobs-toc-heading-5)
  - [【WindowsOS】Mock服务.cmd](#jobs-toc-heading-6)
  - [【WindowsOS】StirlingPDF.cmd](#jobs-toc-heading-7)
  - [【WindowsOS】下载Mock数据.cmd](#jobs-toc-heading-8)
  - [【WindowsOS】唯一字符串写入.cmd](#jobs-toc-heading-9)
  - [【WindowsOS】软件包安装升级.cmd](#jobs-toc-heading-10)
  - [【WindowsOS】全文件搜索文字替换.cmd](#jobs-toc-heading-11)
  - [【WindowsOS】URL去乱码.cmd](#jobs-toc-heading-12)
  - [【WindowsOS】源文件压缩分卷.cmd](#jobs-toc-heading-13)
  - [【WindowsOS】子卷合并.cmd](#jobs-toc-heading-14)
  - [【WindowsOS】MD5.cmd](#jobs-toc-heading-15)
  - [【WindowsOS】时间戳转换工具.cmd](#jobs-toc-heading-16)
  - [【WindowsOS】静态网页截全图.cmd](#jobs-toc-heading-17)
  - [【WindowsOS】打开当前路径终端.cmd](#jobs-toc-heading-18)
  - [【WindowsOS】文件数统计.cmd](#jobs-toc-heading-19)
  - [【WindowsOS】JobsKeyboardRecorder.cmd](#jobs-toc-heading-20)
- [三、平台差异与验证](#jobs-toc-heading-21)

</details>
<!-- jobs-toc:end -->

---

## 🔥 <span id="前言">前言</span>

本目录提供与原脚本功能对应的[**Windows**](https://www.microsoft.com/windows)入口，按当前平台的工具、权限和服务方式执行。

## <span id="jobs-toc-heading-2" data-jobs-toc="v2">一、运行方式 <a href="#前言" style="font-size:17px; color:green;"><b>🔼</b></a> <a href="#🔚" style="font-size:17px; color:green;"><b>🔽</b></a></span><!-- jobs-toc:heading-end -->

[**Windows**](https://www.microsoft.com/windows) 10/11，[**Windows PowerShell**](https://learn.microsoft.com/powershell/) 5.1 或更新版本。双击对应 `.cmd`，或在 PowerShell 使用 `& .\【WindowsOS】脚本名.ps1`；入口全部先显示用途并等待回车，写操作再按提示精确输入 `YES`。可用 `-Check` 只读加载与查询本地依赖，不安装、启动或写业务文件。输入重定向/EOF直接停止；取消用Ctrl+C。`.ps1`以UTF-8 BOM保存，`.cmd`仅为双击转发，不持久修改ExecutionPolicy；被企业策略拦截时遵循本机已批准策略。

`JobsTools.ps1`只定义公共与业务函数；各脚本入口按自身路径加载，不能单独拷贝一个入口后遗漏模块。状态/备份分别保存在当前用户的本地应用数据目录 `JobsCommandOthers` 或 `JobsSh`；每次运行的状态日志保存于系统临时目录中的独立 `Jobs-*.log` 或 `JobsSh-*.log`，自述确认后显示真实位置。下载前显示来源与目标，URL凭据/查询参数脱敏。

递归文件工具默认排除 `.git`、`node_modules`、`Pods`、`.dart_tool`、`build`、`DerivedData`与链接。服务仅绑定回环地址；[**Docker**](https://docs.docker.com/)只操作专属标签容器，不卸载其它软件或清理其它数据。命令失败返回非零，备份保留供检查恢复。

## <span id="jobs-toc-heading-3" data-jobs-toc="v2">二、入口与流程 <a href="#前言" style="font-size:17px; color:green;"><b>🔼</b></a> <a href="#🔚" style="font-size:17px; color:green;"><b>🔽</b></a></span><!-- jobs-toc:heading-end -->

### <span id="jobs-toc-heading-4" data-jobs-toc="v2">[【WindowsOS】Caddy本地域名映射.cmd](<./【WindowsOS】Caddy本地域名映射.cmd>)</span><!-- jobs-toc:heading-end -->

> **目的：** 本地域名反代。

- 检查 caddy.exe，选择 start / status / stop；创建独立 Caddyfile 与管理端口20219，将本地域名8089反代至输入的本地端口。hosts 写入需管理员终端与 YES，先保留备份；restore-hosts 只在未被后续修改时恢复。使用 HTTP，不自动安装根证书或修改代理。
- [PowerShell入口](<./【WindowsOS】Caddy本地域名映射.ps1>)；只读检查：`& .\【WindowsOS】Caddy本地域名映射.ps1 -Check`。

### <span id="jobs-toc-heading-5" data-jobs-toc="v2">[【WindowsOS】Jobs计划任务.cmd](<./【WindowsOS】Jobs计划任务.cmd>)</span><!-- jobs-toc:heading-end -->

> **目的：** 当前用户计划任务。

- 通过 [**Windows ScheduledTasks**](https://learn.microsoft.com/powershell/module/scheduledtasks/) 管理 JobsScheduler- 前缀任务，支持 list / add / run / disable / enable / remove。新增任务每天定时运行明确选择的 .ps1，仅当前用户登录时运行、最低权限，拒绝覆盖同名任务；写操作精确 YES。
- [PowerShell入口](<./【WindowsOS】Jobs计划任务.ps1>)；只读检查：`& .\【WindowsOS】Jobs计划任务.ps1 -Check`。

### <span id="jobs-toc-heading-6" data-jobs-toc="v2">[【WindowsOS】Mock服务.cmd](<./【WindowsOS】Mock服务.cmd>)</span><!-- jobs-toc:heading-end -->

> **目的：** 本地 JSON Mock 服务。

- 选择数据目录、端口及 start / status / stop；使用 .NET TCP 服务仅监听127.0.0.1。GET / 列出第一层 JSON，GET /相对路径.json 返回对应数据；禁止越界、符号链接、目录联接和写入 API。后台进程记录 PID、启动时间与完整启动令牌，停止前复核身份。
- [PowerShell入口](<./【WindowsOS】Mock服务.ps1>)；只读检查：`& .\【WindowsOS】Mock服务.ps1 -Check`。

### <span id="jobs-toc-heading-7" data-jobs-toc="v2">[【WindowsOS】StirlingPDF.cmd](<./【WindowsOS】StirlingPDF.cmd>)</span><!-- jobs-toc:heading-end -->

> **目的：** 本地 PDF 服务。

- 使用已运行的 [**Docker Desktop**](https://docs.docker.com/desktop/) Linux 引擎，支持 start / status / stop / remove。首次下载官方 Stirling PDF 镜像，回环8088映射容器8080，配置、日志与持久文件分别保存专属数据卷；停止或移除保留数据卷。启动等待HTTP就绪，默认账号首次登录按官方文档修改。
- [PowerShell入口](<./【WindowsOS】StirlingPDF.ps1>)；只读检查：`& .\【WindowsOS】StirlingPDF.ps1 -Check`。

### <span id="jobs-toc-heading-8" data-jobs-toc="v2">[【WindowsOS】下载Mock数据.cmd](<./【WindowsOS】下载Mock数据.cmd>)</span><!-- jobs-toc:heading-end -->

> **目的：** 下载 Mock 数据。

- 克隆 https://github.com/JobsKits/JobsMockData.git 至选择父目录；已有目录先核对 origin 与工作区干净，再经 YES 执行 pull --ff-only，拒绝覆盖本地修改。
- [PowerShell入口](<./【WindowsOS】下载Mock数据.ps1>)；只读检查：`& .\【WindowsOS】下载Mock数据.ps1 -Check`。

### <span id="jobs-toc-heading-9" data-jobs-toc="v2">[【WindowsOS】唯一字符串写入.cmd](<./【WindowsOS】唯一字符串写入.cmd>)</span><!-- jobs-toc:heading-end -->

> **目的：** 唯一整行写入。

- 选择严格UTF-8文件，输入一行文本；仅把未注释的完整相同行视为重复。非重复时 YES 确认、备份原文件后追加，保留BOM，内容不写日志；新文件按确认后创建。确认期间目标被其它进程修改或创建时停止，保留并发内容；目标及其上层目录中的链接均拒绝。
- [PowerShell入口](<./【WindowsOS】唯一字符串写入.ps1>)；只读检查：`& .\【WindowsOS】唯一字符串写入.ps1 -Check`。

### <span id="jobs-toc-heading-10" data-jobs-toc="v2">[【WindowsOS】软件包安装升级.cmd](<./【WindowsOS】软件包安装升级.cmd>)</span><!-- jobs-toc:heading-end -->

> **目的：** Windows 软件包安装升级。

- 以 [**winget**](https://learn.microsoft.com/windows/package-manager/winget/) 替代 [**Homebrew**](https://brew.sh/)，输入明确包ID后核对来源，YES确认并选择 install / upgrade；不批量升级其它软件。winget缺失时通过 Windows App Installer 准备，不静默下载执行安装器。
- [PowerShell入口](<./【WindowsOS】软件包安装升级.ps1>)；只读检查：`& .\【WindowsOS】软件包安装升级.ps1 -Check`。

### <span id="jobs-toc-heading-11" data-jobs-toc="v2">[【WindowsOS】全文件搜索文字替换.cmd](<./【WindowsOS】全文件搜索文字替换.cmd>)</span><!-- jobs-toc:heading-end -->

> **目的：** 文件树文本替换。

- 输入文件或目录、查找与替换文字；递归跳过依赖、Git与构建目录及链接。仅严格UTF-8文本，先展示全部命中，YES后逐文件保留独立备份，复核SHA-256未并发改变再字面量替换，保留BOM。
- [PowerShell入口](<./【WindowsOS】全文件搜索文字替换.ps1>)；只读检查：`& .\【WindowsOS】全文件搜索文字替换.ps1 -Check`。

### <span id="jobs-toc-heading-12" data-jobs-toc="v2">[【WindowsOS】URL去乱码.cmd](<./【WindowsOS】URL去乱码.cmd>)</span><!-- jobs-toc:heading-end -->

> **目的：** URL解码与剪贴板。

- 输入百分号编码文本，按选择把 + 解析为空格；使用 .NET 解码并复制到剪贴板。不修改文件，不把解码正文写入状态日志。
- [PowerShell入口](<./【WindowsOS】URL去乱码.ps1>)；只读检查：`& .\【WindowsOS】URL去乱码.ps1 -Check`。

### <span id="jobs-toc-heading-13" data-jobs-toc="v2">[【WindowsOS】源文件压缩分卷.cmd](<./【WindowsOS】源文件压缩分卷.cmd>)</span><!-- jobs-toc:heading-end -->

> **目的：** 原文件压缩分卷。

- 选择源文件、新输出目录及每卷MiB，可选gzip后分卷；确认后用流处理并生成 JobsSplit-1 清单，记录原文件/每卷SHA-256。源文件保留，输出目录必须不存在。
- [PowerShell入口](<./【WindowsOS】源文件压缩分卷.ps1>)；只读检查：`& .\【WindowsOS】源文件压缩分卷.ps1 -Check`。

### <span id="jobs-toc-heading-14" data-jobs-toc="v2">[【WindowsOS】子卷合并.cmd](<./【WindowsOS】子卷合并.cmd>)</span><!-- jobs-toc:heading-end -->

> **目的：** 分卷重建。

- 选择 Windows JobsSplit-1 manifest.json 与新目标文件；先核对卷名和所有SHA-256，再确认重建，支持gzip解压并核对原文件SHA-256。拒绝覆盖已有目标；MacOS旧卷格式需原工具或7-Zip，不能直接混用。
- [PowerShell入口](<./【WindowsOS】子卷合并.ps1>)；只读检查：`& .\【WindowsOS】子卷合并.ps1 -Check`。

### <span id="jobs-toc-heading-15" data-jobs-toc="v2">[【WindowsOS】MD5.cmd](<./【WindowsOS】MD5.cmd>)</span><!-- jobs-toc:heading-end -->

> **目的：** 文件摘要。

- 选择一个普通文件，使用 Get-FileHash 显示MD5；原文件不变。
- [PowerShell入口](<./【WindowsOS】MD5.ps1>)；只读检查：`& .\【WindowsOS】MD5.ps1 -Check`。

### <span id="jobs-toc-heading-16" data-jobs-toc="v2">[【WindowsOS】时间戳转换工具.cmd](<./【WindowsOS】时间戳转换工具.cmd>)</span><!-- jobs-toc:heading-end -->

> **目的：** 时间戳转换。

- 输入Unix秒、毫秒或微秒整数，按位数识别，显示当前系统本地时区与UTC毫秒精度日期。
- [PowerShell入口](<./【WindowsOS】时间戳转换工具.ps1>)；只读检查：`& .\【WindowsOS】时间戳转换工具.ps1 -Check`。

### <span id="jobs-toc-heading-17" data-jobs-toc="v2">[【WindowsOS】静态网页截全图.cmd](<./【WindowsOS】静态网页截全图.cmd>)</span><!-- jobs-toc:heading-end -->

> **目的：** 本地HTML完整截图。

- 选择HTML、新PNG及可选CSS选择器。检查[**Node.js**](https://nodejs.org/)/[**npm**](https://www.npmjs.com/)，缺失Puppeteer时经YES在用户数据目录私有安装并下载Chromium；确认后无头浏览器打开本地HTML，生成整页或元素截图，拒绝覆盖。页面脚本可能访问网络。
- [PowerShell入口](<./【WindowsOS】静态网页截全图.ps1>)；只读检查：`& .\【WindowsOS】静态网页截全图.ps1 -Check`。

### <span id="jobs-toc-heading-18" data-jobs-toc="v2">[【WindowsOS】打开当前路径终端.cmd](<./【WindowsOS】打开当前路径终端.cmd>)</span><!-- jobs-toc:heading-end -->

> **目的：** 指定目录打开终端。

- 选择真实目录，在该工作目录打开cmd.exe；不拼接可执行Shell文字。
- [PowerShell入口](<./【WindowsOS】打开当前路径终端.ps1>)；只读检查：`& .\【WindowsOS】打开当前路径终端.ps1 -Check`。

### <span id="jobs-toc-heading-19" data-jobs-toc="v2">[【WindowsOS】文件数统计.cmd](<./【WindowsOS】文件数统计.cmd>)</span><!-- jobs-toc:heading-end -->

> **目的：** 文件统计。

- 选择目录，递归统计普通文件总数和扩展名分组；跳过Git、依赖、构建目录与链接，不修改业务文件。
- [PowerShell入口](<./【WindowsOS】文件数统计.ps1>)；只读检查：`& .\【WindowsOS】文件数统计.ps1 -Check`。

### <span id="jobs-toc-heading-20" data-jobs-toc="v2">[【WindowsOS】JobsKeyboardRecorder.cmd](<./【WindowsOS】JobsKeyboardRecorder.cmd>)</span><!-- jobs-toc:heading-end -->

> **目的：** 可见键盘记录会话。

- 使用Windows自带[**.NET Framework**](https://learn.microsoft.com/dotnet/framework/)/[**Windows Forms**](https://learn.microsoft.com/dotnet/desktop/winforms/)在当前入口进程中显示始终置顶的记录面板。本人点击开始并再次确认后安装会话键盘钩子，只在内存保存按键名与时间，不转换输入文字或读取剪贴板。停止、锁屏、关闭窗口、关闭启动终端或进程结束后停止监听；不联网、不自启动、无监听子进程。停止后可显式手动保存TSV，关闭不自动保存或重建目录。需要交互桌面和STA（双击CMD已指定）。
- [PowerShell入口](<./【WindowsOS】JobsKeyboardRecorder.ps1>)；只读检查：`& .\【WindowsOS】JobsKeyboardRecorder.ps1 -Check`。

## <span id="jobs-toc-heading-21" data-jobs-toc="v2">三、平台差异与验证 <a href="#前言" style="font-size:17px; color:green;"><b>🔼</b></a> <a href="#🔚" style="font-size:17px; color:green;"><b>🔽</b></a></span><!-- jobs-toc:heading-end -->

MacOS原入口22个，Windows提供17个入口。Xcode编译耗时、iOS Fastfile、Gatekeeper损坏修复、POSIX执行权限切换与运行授权共5项只保留MacOS；Windows无法等价运行其Apple工具或权限语义。Homebrew管理对应winget；计划任务对应当前用户Windows任务计划程序，未提供SwiftUI桌面界面；Stirling使用官方容器运行服务，未复刻源码开发服务器。键盘记录器采用可见WinForms会话并只记按键名/时间，与MacOS可见字符文本格式不同；Windows键盘钩子、锁屏停止和实际桌面交互须实机验收。

`KeyboardRecorder.cs`为同进程可见记录窗口，随入口运行编译到内存；`MockServer.ps1`为后台只读JSON服务内部实现，不直接作为用户双击入口。分卷采用Windows原生JobsSplit-1格式，保留压缩、拆分、校验、重建能力，不能冒充MacOS历史卷集格式相同。

来源：[Caddy CLI](https://caddyserver.com/docs/command-line)、[Stirling Docker安装](https://docs.stirlingpdf.com/Server/Install/Docker/)、[Windows任务注册](https://learn.microsoft.com/en-us/powershell/module/scheduledtasks/register-scheduledtask)。

已进行PowerShell解析/BOM检查、只读入口检查，以及临时文件中的隔离验证；这些结果不代表Windows PowerShell 5.1实机、安装器、WSL2、数据库或服务已实际验收。未运行真实安装、升级、系统配置、服务启动、数据库重置或文件清理。

持续回归入口与范围见 [文件工具隔离测试](./Tests/README.md)。

<a id="🔚" href="#前言" style="font-size:17px; color:green; font-weight:bold;">我是有底线的➤点我回到首页</a>
