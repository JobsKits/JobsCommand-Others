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



<!-- JOBS_TERMINAL_STYLE_V1:BEGIN -->

> Windows 终端配色保护：支持完整颜色查询的交互控制台会先保存当前会话默认前景、背景与16色色表，再临时使用黑底白字和统一强调色；正常结束、业务失败及可捕获中断后恢复。用户运行中自行改动的颜色保留并提示，不修改用户主题、共享 Profile、注册表或全局策略。快照不包含进入前任意叠加的临时文字样式。非控制台、重定向、`NO_COLOR`、Sourcetree 及无法可靠保存／恢复颜色的环境保持原状态或降级为纯文本。

> 强制结束进程或终端崩溃无法保证自动恢复。恢复失败时保留并提示本轮 `%TEMP%\JobsTerminalStyle-<PID>-*.ps1` 恢复脚本，需在原控制台核对后运行；不要通过重置用户配置恢复。`-ExecutionPolicy Bypass` 如被入口使用，仅作用于本次子进程，不持久修改策略。

> 验证范围：已完成 PowerShell 语法、参数／退出与隔离生命周期核验；Windows 原生控制台的显示、按键与 `Ctrl+C` 实机验证尚未完成。

<!-- JOBS_TERMINAL_STYLE_V1:END -->

<a id="🔚" href="#前言" style="font-size:17px; color:green; font-weight:bold;">我是有底线的➤点我回到首页</a>
