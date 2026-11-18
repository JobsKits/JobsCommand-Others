# 【WindowsOS】子卷合并

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

> **目的：** 分卷重建。

- 默认输入分卷目录或其父目录；扫描当前层与一级子目录，以完整原文件名分组，在 fzf 中单选一组。卷名为 `完整原文件名@序号of总数`，兼容补零及名称里的 `@`；逐组检查总数、缺号、重复和空卷，按数字顺序合并，不混组。
- 直接输入分卷目录时输出到其父目录；输入父目录并选择其中子组时输出到所输入目录。固定内存流式写入独占候选，大小与 SHA-256 校验通过后无覆盖发布。始终保留原分卷，失败候选保留；没有可信原文件摘要时，复制校验不能证明镜像来源可信。
- `-LegacyManifest` 保留 Windows `JobsSplit-1` 清单重建：核对卷名 / 每卷 SHA-256，支持 gzip 解压，并核对原文件 SHA-256。清单模式和原始卷模式不能混用。

## <span id="jobs-toc-heading-3" data-jobs-toc="v2">二、运行方式 <a href="#前言" style="font-size:17px; color:green;"><b>🔼</b></a> <a href="#🔚" style="font-size:17px; color:green;"><b>🔽</b></a></span><!-- jobs-toc:heading-end -->

最低支持系统：目标为 [**Windows**](https://www.microsoft.com/windows) 10 x64，最低 build 与完整兼容性仍待验证；需要 Windows PowerShell 5.1 或更新版本。外部工具及桌面功能按上节依赖准备。

双击 [【WindowsOS】子卷合并.cmd](<./【WindowsOS】子卷合并.cmd>)，或在本目录运行 [【WindowsOS】子卷合并.ps1](<./【WindowsOS】子卷合并.ps1>)：

```powershell
& '.\【WindowsOS】子卷合并.ps1'
```

直接指定目录（仍展示自述并要求执行确认）：

```powershell
& '.\【WindowsOS】子卷合并.ps1' `
    -Path 'D:\镜像\示例.iso.chunks'
```

原始卷选择需要 [**fzf**](https://github.com/junegunn/fzf)，回车选择、Esc 取消；取消、空选和选择器错误不执行合并。缺依赖提示后停止，不自动安装。

旧清单 / gzip 用法（沿用旧交互，不与 `-Path` 混用）：

```powershell
& '.\【WindowsOS】子卷合并.ps1' -LegacyManifest
```

只读加载和本地依赖检查：

```powershell
& '.\【WindowsOS】子卷合并.ps1' -Check
```

正常运行先显示用途并等待回车，写操作按提示精确输入 `YES`；取消使用 Ctrl+C，输入重定向或 EOF 时停止。`.cmd` 为本次 PowerShell 进程指定执行策略，不持久修改本机策略；企业组策略仍优先。

## <span id="jobs-toc-heading-4" data-jobs-toc="v2">三、文件依赖与验证 <a href="#前言" style="font-size:17px; color:green;"><b>🔼</b></a> <a href="#🔚" style="font-size:17px; color:green;"><b>🔽</b></a></span><!-- jobs-toc:heading-end -->

入口按脚本位置加载 [公共模块](../Common/README.md) 的 `JobsTools.ps1`、`FileVolumes.ps1` 和 `FileVolumeWorkflow.ps1`。复制使用时保留本功能目录与 `Common/` 的相邻关系。原始卷结果与候选位于分卷目录或其父目录，旧清单模式使用所选新目标；本功能不生成 LocalAppData 备份。运行日志位于系统临时目录，确认自述后显示实际位置。

隔离回归与验证范围见 [Tests 说明](../Tests/README.md)；外部软件安装、服务和桌面操作须按各自环境验收。

默认原始卷模式可读取共享测试样本 `Release/libiPhone-lib`。macOS / Windows 的拆分目录命名可不同，只要完整分卷文件名格式相同即可互通。Windows PowerShell 5.1、真实 CMD 双击与 fzf 交互尚需目标机验收。

<a id="🔚" href="#前言" style="font-size:17px; color:green; font-weight:bold;">我是有底线的➤点我回到首页</a>
