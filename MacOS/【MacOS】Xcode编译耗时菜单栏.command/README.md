# `Xcode 编译耗时菜单栏`

![Jobs出品，必属精品](https://picsum.photos/1500/400)

<!-- jobs-toc:start -->
<!-- jobs-toc:source {"v":2,"token":"[toc]"} -->
<details>
<summary>📚 目录（点击展开 / 收起）</summary>

- [🔥 前言](#%E5%89%8D%E8%A8%80)
- [一、功能覆盖](#jobs-toc-heading-2)
- [二、运行与结果](#jobs-toc-heading-3)
- [三、作用范围与验证](#jobs-toc-heading-4)

</details>
<!-- jobs-toc:end -->

---

## 🔥 <span id="前言">前言</span>

生成并启动本机菜单栏计时工具，展示当前编译耗时、最近构建记录和悬浮看板。入口使用系统 [**zsh**](https://www.zsh.org/)，在本机编译内嵌 Swift 程序。

## <span id="jobs-toc-heading-2" data-jobs-toc="v2">一、功能覆盖 <a href="#前言" style="font-size:17px; color:green;"><b>🔼</b></a> <a href="#🔚" style="font-size:17px; color:green;"><b>🔽</b></a></span><!-- jobs-toc:heading-end -->

- 使用 Scheme Pre/Post Action 的 Hook 精确记录构建开始和结束；未配置 Hook 时读取 DerivedData 的 `.xcactivitylog`，同时根据构建进程提供推断状态。
- 菜单栏与可拖拽悬浮窗显示实时耗时、工程、Scheme、配置、SDK 与设备；查看最近构建、慢任务及 Swift 编译信息。
- 在当前用户 `.xcode-build-timer` 工作目录生成 Swift、App Bundle、Hook、状态与历史记录；按当前 arm64 或 x86_64 编译，部署目标 [**macOS**](https://www.apple.com/macos/) 13.0。

## <span id="jobs-toc-heading-3" data-jobs-toc="v2">二、运行与结果 <a href="#前言" style="font-size:17px; color:green;"><b>🔼</b></a> <a href="#🔚" style="font-size:17px; color:green;"><b>🔽</b></a></span><!-- jobs-toc:heading-end -->

在本目录运行：

```shell
zsh './【MacOS】Xcode编译耗时菜单栏.command'
```

依赖 [**Xcode**](https://developer.apple.com/xcode)/Command Line Tools、`xcrun swiftc` 与 Cocoa 图形会话。先阅读自述并回车确认；入口停止已有 XcodeBuildTimer、重建自己的 App 后启动。只有配置 Scheme Hook 才能获得明确的起止状态，推断值会带提示。

## <span id="jobs-toc-heading-4" data-jobs-toc="v2">三、作用范围与验证 <a href="#前言" style="font-size:17px; color:green;"><b>🔼</b></a> <a href="#🔚" style="font-size:17px; color:green;"><b>🔽</b></a></span><!-- jobs-toc:heading-end -->

主入口生成工具文件，不自动修改所有项目 Scheme。若通过界面配置工程 Hook，应先核对所选 Scheme；对应状态日志留在工作目录，启动日志位于系统临时目录并回显。退出工具停止监听，保留生成文件供再次运行。

运行后先核对菜单栏与看板能显示当前工程；有 Hook 时核对起止状态，无 Hook 时应把推断值与真实 Xcode 构建日志对照。源码生成、编译或启动失败时检查终端回显和工作目录日志。

<a id="🔚" href="#前言" style="font-size:17px; color:green; font-weight:bold;">我是有底线的➤点我回到首页</a>
