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

公共模块定义输入确认、日志、文件与备份、依赖检查以及各工具的业务函数；加载时只定义函数，不自行启动工具。需要 [**PowerShell**](https://learn.microsoft.com/powershell/) 5.1 或更新版本。用户从各功能目录中的同名 `.cmd` 或 `.ps1` 运行工具。

功能专属实现分别位于 [Mock 服务](<../【WindowsOS】Mock服务/README.md>) 的 `MockServer.ps1` 和 [键盘记录器](<../【WindowsOS】JobsKeyboardRecorder/README.md>) 的 `KeyboardRecorder.cs`。其它功能无需复制这两份专属资源，但必须保留本目录与功能目录的相邻关系。

## <span id="jobs-toc-heading-3" data-jobs-toc="v2">二、维护与验证 <a href="#前言" style="font-size:17px; color:green;"><b>🔼</b></a> <a href="#🔚" style="font-size:17px; color:green;"><b>🔽</b></a></span><!-- jobs-toc:heading-end -->

配套 [隔离回归](../Tests/README.md) 检查公共文件操作和全部入口的 `-Check`。修改模块或移动专属文件后，同步核对入口加载路径、内部资源路径与实际功能说明。加载与只读检查不代表真实外部工具或桌面业务已验收。

<a id="🔚" href="#前言" style="font-size:17px; color:green; font-weight:bold;">我是有底线的➤点我回到首页</a>
