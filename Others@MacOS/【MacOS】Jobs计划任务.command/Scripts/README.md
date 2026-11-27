# `JobsScheduler / Scripts`

![Jobs出品，必属精品](https://picsum.photos/1500/400)

<!-- jobs-toc:start -->
<!-- jobs-toc:source {"v":2,"token":"[toc]"} -->
<details>
<summary>📚 目录（点击展开 / 收起）</summary>

- [🔥 前言](#%E5%89%8D%E8%A8%80)
- [一、图标生成能力](#jobs-toc-heading-2)
- [二、依赖与结果核对](#jobs-toc-heading-3)

</details>
<!-- jobs-toc:end -->

---

## 🔥 <span id="前言">前言</span>

本目录保存 Jobs 计划任务的图标生成辅助脚本；任务创建、调度、运行、诊断与卸载使用[上层应用入口](../README.md)。

## <span id="jobs-toc-heading-2" data-jobs-toc="v2">一、图标生成能力 <a href="#前言" style="font-size:17px; color:green;"><b>🔼</b></a> <a href="#🔚" style="font-size:17px; color:green;"><b>🔽</b></a></span><!-- jobs-toc:heading-end -->

[GenerateAppIcon.swift](./GenerateAppIcon.swift) 使用 [**Swift**](https://www.swift.org/) 和 [**AppKit**](https://developer.apple.com/documentation/appkit) 绘制 1024 × 1024 PNG：红色圆角渐变底、半透明圆形与系统 `alarm.fill` 符号。

第一个位置参数为输出 PNG；省略时写入调用时当前目录的 `AppIcon.png`。本目录中可运行：

```shell
xcrun swift ./GenerateAppIcon.swift ./AppIcon.png
```

## <span id="jobs-toc-heading-3" data-jobs-toc="v2">二、依赖与结果核对 <a href="#前言" style="font-size:17px; color:green;"><b>🔼</b></a> <a href="#🔚" style="font-size:17px; color:green;"><b>🔽</b></a></span><!-- jobs-toc:heading-end -->

需要 macOS 图形 API 和已有 Xcode/Command Line Tools 的 Swift 运行环境。输出以原子方式写入，已有同名文件会被替换；使用新的输出名保留旧图片。

此脚本仅生成一张 PNG，不自动创建 `.iconset` / `.icns`，不安装 App，也不注册计划任务。运行后核对输出文件尺寸、图像主体和命令退出状态；失败时查看标准错误。

<a id="🔚" href="#前言" style="font-size:17px; color:green; font-weight:bold;">我是有底线的➤点我回到首页</a>
