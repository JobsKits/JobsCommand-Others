# WindowsOS 公共模块

![Jobs出品，必属精品](https://picsum.photos/1500/400)

<!-- jobs-toc:start -->
<!-- jobs-toc:source {"v":2,"token":"[toc]"} -->
<details>
<summary>📚 目录（点击展开 / 收起）</summary>

- [🔥 前言](#%E5%89%8D%E8%A8%80)
- [一、职责与依赖](#jobs-toc-heading-2)
- [二、维护与验证](#jobs-toc-heading-3)

</details>
<!-- jobs-toc:end -->

---

## 🔥 <span id="前言">前言</span>

本目录保存各功能共用的 [`JobsTools.ps1`](./JobsTools.ps1)，由相邻功能目录中的入口按脚本位置加载。返回 [WindowsOS 总览](../README.md)。

## <span id="jobs-toc-heading-2" data-jobs-toc="v2">一、职责与依赖 <a href="#前言" style="font-size:17px; color:green;"><b>🔼</b></a> <a href="#🔚" style="font-size:17px; color:green;"><b>🔽</b></a></span><!-- jobs-toc:heading-end -->

公共模块定义输入确认、日志、文件与备份、依赖检查以及各工具的业务函数；加载时只定义函数，不自行启动工具。文本替换接受普通文件或目录，输入时检查完整祖先链，确认后每个写入目标再次拒绝链接祖先，路径被替换时停止。路径内部的 `%TEMP%` 等文本按合法文件名保留；输入明确以 `%变量名%\` 或 `%变量名%/` 开头、且原文路径不存在时只展开首段，未设置变量时停止。需要 [**PowerShell**](https://learn.microsoft.com/powershell/) 5.1 或更新版本。用户从各功能目录中的同名 `.cmd` 或 `.ps1` 运行工具。

分卷工具额外加载 [`FileVolumes.ps1`](./FileVolumes.ps1) 和 [`FileVolumeWorkflow.ps1`](./FileVolumeWorkflow.ps1)：前者以固定 1 MiB 缓冲区流式拆分 / 合并，校验大小与 SHA-256，并用独占创建及无覆盖移动发布；后者承接文件 / 目录输入、fzf 单选、50 / 100 / 1900 MiB / 自定义上限、返回 / 取消与精确 `YES` 确认。分卷命名与 macOS 的 `原文件名@卷号of总数` 互通。Windows 原件始终保留，不提供删除动作；失败候选保留并显示路径。合并摘要确认复制一致性，没有可信源摘要时不能证明分卷来源可信。

旧 `JobsSplit-1` 清单和 gzip 功能仍由 `JobsTools.ps1` 的原函数实现，公开分卷入口通过 `-LegacyManifest` 选择，未改变其它工具的运行路径。复制分卷入口时，保留本目录三份 `.ps1` 文件；不能只复制 CMD 或公开脚本。

功能专属实现分别位于 [Mock 服务](<../【WindowsOS】Mock服务/README.md>) 的 `MockServer.ps1` 和 [键盘记录器](<../【WindowsOS】JobsKeyboardRecorder/README.md>) 的 `KeyboardRecorder.cs`。其它功能无需复制这两份专属资源，但必须保留本目录与功能目录的相邻关系。

## <span id="jobs-toc-heading-3" data-jobs-toc="v2">二、维护与验证 <a href="#前言" style="font-size:17px; color:green;"><b>🔼</b></a> <a href="#🔚" style="font-size:17px; color:green;"><b>🔽</b></a></span><!-- jobs-toc:heading-end -->

配套 [隔离回归](../Tests/README.md) 检查公共文件操作和全部入口的 `-Check`。修改模块或移动专属文件后，同步核对入口加载路径、内部资源路径与实际功能说明。加载与只读检查不代表真实外部工具或桌面业务已验收。

<a id="🔚" href="#前言" style="font-size:17px; color:green; font-weight:bold;">我是有底线的➤点我回到首页</a>
