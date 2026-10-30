# <span id="前言">Windows 文件工具隔离测试</span>

![Jobs出品，必属精品](https://picsum.photos/1500/400)

<!-- jobs-toc:start -->
<!-- jobs-toc:source {"v":2,"token":"[toc]"} -->
<details>
<summary>📚 目录（点击展开 / 收起）</summary>

- [一、运行方式](#jobs-toc-heading-1)
- [二、隔离边界](#jobs-toc-heading-2)

</details>
<!-- jobs-toc:end -->

---

## <span id="jobs-toc-heading-1" data-jobs-toc="v2">一、运行方式 <a href="#前言" style="font-size:17px; color:green;"><b>🔼</b></a> <a href="#🔚" style="font-size:17px; color:green;"><b>🔽</b></a></span><!-- jobs-toc:heading-end -->

在此目录使用 [**PowerShell**](https://learn.microsoft.com/powershell/) 运行：

```powershell
& ./Regression.ps1
```

公共模块从 `../Common/JobsTools.ps1` 加载；入口检查递归发现各功能目录内的 `【WindowsOS】*.ps1`。`-SkipEntrypoints` 只运行模块夹具。macOS 完整检查为 59 项断言，Windows 为 57 项，覆盖精确 `YES`、BOM、严格 UTF-8、重复整行、并发修改保留、祖先链接拒绝、替换单文件 / 目录的字面量与 BOM 保留、替换入口链接拒绝及确认期间目录变为链接时停止、路径内 `%TEMP%` 字面保留、显式环境变量根与缺变量停止、递归排除、原始与 gzip 分卷往返、损坏卷与覆盖保护、原生命令退出码，以及全部 17 个入口的 `-Check`。

跨平台原始分卷专项运行 [`FileVolumes.Tests.ps1`](./FileVolumes.Tests.ps1)：

```powershell
& ./FileVolumes.Tests.ps1
```

专项使用真实临时二进制文件验证跨块拆分、乱序合并、指定输出目录、源件保留和无覆盖，mock 选择器验证 `←` / Esc / 空值 / 错误及默认原始卷与 `-LegacyManifest` 分流；旧 `JobsSplit-1` 的直接分卷与 gzip 往返继续验证。fzf 交互分支的 mock 不等同于 Windows 桌面真实按键验收。

## <span id="jobs-toc-heading-2" data-jobs-toc="v2">二、隔离边界 <a href="#前言" style="font-size:17px; color:green;"><b>🔼</b></a> <a href="#🔚" style="font-size:17px; color:green;"><b>🔽</b></a></span><!-- jobs-toc:heading-end -->

只写唯一临时目录，结束清理；不安装软件、不修改用户配置、不运行服务或访问业务远端。基础祖先符号链接夹具在 macOS 运行；文本替换的链接边界在 macOS 使用符号链接、Windows 使用临时目录联接，不要求开发者模式或管理员权限；2026-10-26 在 Windows 11 ARM64 / Windows PowerShell 5.1.26100.9711 原生通过 41 项；根 CMD 回归另验证该仓 MD5 入口在无继承进程执行策略时的真实 `-Check`。真实桌面双击和外部工具业务仍需单独验收。

<a id="🔚" href="#前言" style="font-size:17px; color:green; font-weight:bold;">我是有底线的➤点我回到首页</a>
