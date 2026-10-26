# 分卷测试资源与 MD5 工具

![Jobs出品，必属精品](https://picsum.photos/1500/400)

<!-- jobs-toc:start -->
<!-- jobs-toc:source {"v":2,"token":"[toc]"} -->
<details>
<summary>📚 目录（点击展开 / 收起）</summary>

- [🔥 前言](#%E5%89%8D%E8%A8%80)
- [一、目录与用途](#jobs-toc-heading-2)
- [二、macOS 使用方式](#jobs-toc-heading-3)
- [三、Windows 使用边界](#jobs-toc-heading-4)

</details>
<!-- jobs-toc:end -->

---

## 🔥 <span id="前言">前言</span>

本目录集中保存 MD5 工具包与共享分卷测试样本。返回[仓库总览](../README.md)；拆分、合并工具的完整说明见 [MacOS 文件子卷工具](<../MacOS/【MacOS】文件分拆（合并）测试. command/README.md>)。

## <span id="jobs-toc-heading-2" data-jobs-toc="v2">一、目录与用途 <a href="#前言" style="font-size:17px; color:green;"><b>🔼</b></a> <a href="#🔚" style="font-size:17px; color:green;"><b>🔽</b></a></span><!-- jobs-toc:heading-end -->

| 目录 | 内容与用途 |
|---|---|
| [【MacOS】🧬MD5.command](<./【MacOS】🧬MD5.command/README.md>) | 包含 macOS MD5 主脚本与配套 README，用于人工核对文件摘要。 |
| [libiPhone-lib](./libiPhone-lib/) | 包含 `libiPhone-lib.a@001of004` 至 `libiPhone-lib.a@004of004` 四个二进制分卷，用于测试合并。 |

## <span id="jobs-toc-heading-3" data-jobs-toc="v2">二、macOS 使用方式 <a href="#前言" style="font-size:17px; color:green;"><b>🔼</b></a> <a href="#🔚" style="font-size:17px; color:green;"><b>🔽</b></a></span><!-- jobs-toc:heading-end -->

在本 `README.md` 所在目录运行 MD5 工具，阅读内置自述并按回车后，拖入要校验的文件；使用 `Ctrl+C` 退出：

```shell
./'【MacOS】🧬MD5.command/【MacOS】🧬MD5.command'
```

合并样本时，运行 [MacOS 合并脚本](<../MacOS/【MacOS】文件分拆（合并）测试. command/【MacOS】🧩子卷➤合而为一源文件.command/【MacOS】🧩子卷➤合而为一源文件.command>)，在目标目录提示处选择本 `Release/` 目录，脚本会扫描其一级子目录 `libiPhone-lib/`，输出 `./libiPhone-lib.a`。合并后在删除提示处直接回车，保留测试分卷；同名输出已存在时先检查覆盖提示。

## <span id="jobs-toc-heading-4" data-jobs-toc="v2">三、Windows 使用边界 <a href="#前言" style="font-size:17px; color:green;"><b>🔼</b></a> <a href="#🔚" style="font-size:17px; color:green;"><b>🔽</b></a></span><!-- jobs-toc:heading-end -->

[Windows 源文件压缩分卷](<../WindowsOS/【WindowsOS】源文件压缩分卷/README.md>) 生成 `JobsSplit-1` 的 `manifest.json`，并由 [Windows 子卷合并](<../WindowsOS/【WindowsOS】子卷合并/README.md>) 校验和重建。这里的 `@001of004` 样本没有该清单，不能直接交给 Windows 合并入口。

MD5 `.command` 仅供 [**macOS**](https://www.apple.com/macos/) 使用；Windows 用户使用 [Windows MD5 工具](<../WindowsOS/【WindowsOS】MD5/README.md>)。移动目录不改变分卷内容或格式。

<a id="🔚" href="#前言" style="font-size:17px; color:green; font-weight:bold;">我是有底线的➤点我回到首页</a>
