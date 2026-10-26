# 【WindowsOS】静态网页截全图

![Jobs出品，必属精品](https://picsum.photos/1500/400)

<!-- jobs-toc:start -->
<!-- jobs-toc:source {"v":2,"token":"[toc]"} -->
<details>
<summary>📚 目录（点击展开 / 收起）</summary>

- [🔥 前言](#%E5%89%8D%E8%A8%80)
- [一、功能与边界](#jobs-toc-heading-2)
- [二、运行方式](#jobs-toc-heading-3)
- [三、文件依赖与验证](#jobs-toc-heading-4)

</details>
<!-- jobs-toc:end -->

---

## 🔥 <span id="前言">前言</span>

本目录集中存放该功能的双击入口、[**PowerShell**](https://learn.microsoft.com/powershell/) 脚本和功能专属文件。返回[WindowsOS 总览](../README.md)。

## <span id="jobs-toc-heading-2" data-jobs-toc="v2">一、功能与边界 <a href="#前言" style="font-size:17px; color:green;"><b>🔼</b></a> <a href="#🔚" style="font-size:17px; color:green;"><b>🔽</b></a></span><!-- jobs-toc:heading-end -->

> **目的：** 本地HTML完整截图。

- 选择HTML、新PNG及可选CSS选择器。检查[**Node.js**](https://nodejs.org/)/[**npm**](https://www.npmjs.com/)，缺失Puppeteer时经YES在用户数据目录私有安装并下载Chromium；确认后无头浏览器打开本地HTML，生成整页或元素截图，拒绝覆盖。页面脚本可能访问网络。

## <span id="jobs-toc-heading-3" data-jobs-toc="v2">二、运行方式 <a href="#前言" style="font-size:17px; color:green;"><b>🔼</b></a> <a href="#🔚" style="font-size:17px; color:green;"><b>🔽</b></a></span><!-- jobs-toc:heading-end -->

最低支持系统：目标为 [**Windows**](https://www.microsoft.com/windows) 10 x64，最低 build 与完整兼容性仍待验证；需要 Windows PowerShell 5.1 或更新版本。外部工具及桌面功能按上节依赖准备。

双击 [【WindowsOS】静态网页截全图.cmd](<./【WindowsOS】静态网页截全图.cmd>)，或在本目录运行 [【WindowsOS】静态网页截全图.ps1](<./【WindowsOS】静态网页截全图.ps1>)：

```powershell
& '.\【WindowsOS】静态网页截全图.ps1'
```

只读加载和本地依赖检查：

```powershell
& '.\【WindowsOS】静态网页截全图.ps1' -Check
```

正常运行先显示用途并等待回车，写操作按提示精确输入 `YES`；取消使用 Ctrl+C，输入重定向或 EOF 时停止。`.cmd` 为本次 PowerShell 进程指定执行策略，不持久修改本机策略；企业组策略仍优先。

## <span id="jobs-toc-heading-4" data-jobs-toc="v2">三、文件依赖与验证 <a href="#前言" style="font-size:17px; color:green;"><b>🔼</b></a> <a href="#🔚" style="font-size:17px; color:green;"><b>🔽</b></a></span><!-- jobs-toc:heading-end -->

入口按脚本位置加载 [公共模块](../Common/README.md) 中的 `../Common/JobsTools.ps1`。复制使用时保留本功能目录与 `Common/` 的相邻关系。业务状态与备份位于当前用户本地应用数据目录；运行日志位于系统临时目录，确认自述后显示实际位置。

隔离回归与验证范围见 [Tests 说明](../Tests/README.md)；外部软件安装、服务和桌面操作须按各自环境验收。

<a id="🔚" href="#前言" style="font-size:17px; color:green; font-weight:bold;">我是有底线的➤点我回到首页</a>
