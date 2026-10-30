# 【WindowsOS】源文件压缩分卷

![Jobs出品，必属精品](https://picsum.photos/1500/400)

<!-- jobs-toc:start -->
<!-- jobs-toc:source {"v":2,"token":"[toc]"} -->
<details>
<summary>📚 目录（点击展开 / 收起）</summary>

- [🔥 前言](#%E5%89%8D%E8%A8%80)
- [一、功能与边界](#jobs-toc-heading-2)
- [二、运行方式](#jobs-toc-heading-3)
- [三、文件依赖与验证](#jobs-toc-heading-4)
- [四、共享工具与测试样本](#jobs-toc-heading-5)

</details>
<!-- jobs-toc:end -->

---

## 🔥 <span id="前言">前言</span>

本目录集中存放该功能的双击入口、[**PowerShell**](https://learn.microsoft.com/powershell/) 脚本和功能专属文件。返回[WindowsOS 总览](../README.md)。

## <span id="jobs-toc-heading-2" data-jobs-toc="v2">一、功能与边界 <a href="#前言" style="font-size:17px; color:green;"><b>🔼</b></a> <a href="#🔚" style="font-size:17px; color:green;"><b>🔽</b></a></span><!-- jobs-toc:heading-end -->

> **目的：** 与 macOS 互通的原始分卷；保留旧清单压缩模式。

- 默认接受单文件或目录；目录只列当前层超过上限的普通文件，通过 fzf 单选一个。上限为 50 / 100 / 1900 MiB 或自定义正数 MiB（可小数，换算向下取整到字节，至少一个字节）。文件必须超过上限；按 `N=ceil(大小/上限)` 均衡分卷，卷名为 `完整原文件名@序号of总数`，输出到源文件旁 `完整文件名.chunks`。这一步只切分字节，没有压缩。
- 固定 1 MiB 内存缓冲区，输入读共享锁、SHA-256 / 大小及源状态复核后发布；同名结果拒绝覆盖。源文件始终保留；失败保留候选目录并显示位置，不修改源文件，也不删除旧卷。
- `-LegacyManifest` 使用原有 `JobsSplit-1` 模式：选择源文件、新输出目录及每卷 MiB，可选 gzip 后分卷，生成每卷及原文件 SHA-256 清单；输出目录必须不存在，原件保留。

## <span id="jobs-toc-heading-3" data-jobs-toc="v2">二、运行方式 <a href="#前言" style="font-size:17px; color:green;"><b>🔼</b></a> <a href="#🔚" style="font-size:17px; color:green;"><b>🔽</b></a></span><!-- jobs-toc:heading-end -->

最低支持系统：目标为 [**Windows**](https://www.microsoft.com/windows) 10 x64，最低 build 与完整兼容性仍待验证；需要 Windows PowerShell 5.1 或更新版本。外部工具及桌面功能按上节依赖准备。

双击 [【WindowsOS】源文件压缩分卷.cmd](<./【WindowsOS】源文件压缩分卷.cmd>)，或在本目录运行 [【WindowsOS】源文件压缩分卷.ps1](<./【WindowsOS】源文件压缩分卷.ps1>)：

```powershell
& '.\【WindowsOS】源文件压缩分卷.ps1'
```

直接指定源文件与上限（仍显示自述并要求执行确认）：

```powershell
& '.\【WindowsOS】源文件压缩分卷.ps1' `
    -Path 'D:\镜像\示例.iso' `
    -LimitMiB 100
```

保留的 gzip / 清单入口：

```powershell
& '.\【WindowsOS】源文件压缩分卷.ps1' -LegacyManifest
```

只读加载和本地依赖检查：

```powershell
& '.\【WindowsOS】源文件压缩分卷.ps1' -Check
```

正常运行先显示用途并等待回车，写操作按提示精确输入 `YES`；取消使用 Ctrl+C，输入重定向或 EOF 时停止。`.cmd` 为本次 PowerShell 进程指定执行策略，不持久修改本机策略；企业组策略仍优先。

原始分卷模式需要本机可用的 [**fzf**](https://github.com/junegunn/fzf)。回车选择、Esc 取消；目录文件列表支持 `←` 返回上限选择，自定义输入回车返回标准上限。指定 `-LimitMiB` 后没有上限选择层，文件列表用 Esc 取消。空选、取消及选择器失败均不执行业务。缺依赖只提示并停止，不自动安装。`-LegacyManifest` 使用旧交互，不与 `-Path` / `-LimitMiB` 混用。

## <span id="jobs-toc-heading-4" data-jobs-toc="v2">三、文件依赖与验证 <a href="#前言" style="font-size:17px; color:green;"><b>🔼</b></a> <a href="#🔚" style="font-size:17px; color:green;"><b>🔽</b></a></span><!-- jobs-toc:heading-end -->

入口按脚本位置加载 [公共模块](../Common/README.md) 的 `JobsTools.ps1`、`FileVolumes.ps1` 和 `FileVolumeWorkflow.ps1`。复制使用时保留本功能目录与 `Common/` 的相邻关系。原始卷输出与失败候选位于源文件旁，旧清单模式输出到所选新目录；本功能不生成 LocalAppData 备份。运行日志位于系统临时目录，确认自述后显示实际位置。

隔离回归与验证范围见 [Tests 说明](../Tests/README.md)；外部软件安装、服务和桌面操作须按各自环境验收。

## <span id="jobs-toc-heading-5" data-jobs-toc="v2">四、共享工具与测试样本 <a href="#前言" style="font-size:17px; color:green;"><b>🔼</b></a> <a href="#🔚" style="font-size:17px; color:green;"><b>🔽</b></a></span><!-- jobs-toc:heading-end -->

共享资源统一位于仓库根目录的 `Release/`，详见 [Release 说明](../../Release/README.md)。

- [libiPhone-lib 测试分卷](../../Release/libiPhone-lib/) 保留 `libiPhone-lib.a@001of004` 至 `libiPhone-lib.a@004of004` 四个原始二进制分卷，可交给 [Windows 子卷合并入口](<../【WindowsOS】子卷合并/README.md>) 的默认原始卷模式；没有 `JobsSplit-1` 的 `manifest.json`，不使用 `-LegacyManifest`。
- [MacOS MD5 工具说明](<../../Release/【MacOS】🧬MD5.command/README.md>) 对应的 `.command` 入口仅供 [**macOS**](https://www.apple.com/macos/) 使用；Windows 校验文件 MD5 请使用 [【WindowsOS】MD5.cmd](<../【WindowsOS】MD5/【WindowsOS】MD5.cmd>)。

验证跨平台流程时，用普通源文件生成 `.chunks`，再将其目录交给 Windows 或 macOS 合并入口；复制内容的 SHA-256 应一致。旧清单流程则两端 Windows 入口均使用 `-LegacyManifest`。需要对照 MD5 时，分别校验源文件与重建文件。原生 Windows PowerShell 5.1、真实 CMD 双击与 fzf 交互仍需目标机验收。

<a id="🔚" href="#前言" style="font-size:17px; color:green; font-weight:bold;">我是有底线的➤点我回到首页</a>
