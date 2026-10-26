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

`-SkipEntrypoints` 只运行模块夹具。macOS 完整检查为 43 项断言，Windows 为 41 项，覆盖精确 `YES`、BOM、严格 UTF-8、重复整行、并发修改保留、祖先链接拒绝、递归排除、原始与 gzip 分卷往返、损坏卷与覆盖保护、原生命令退出码，以及全部 17 个入口的 `-Check`。

## <span id="jobs-toc-heading-2" data-jobs-toc="v2">二、隔离边界 <a href="#前言" style="font-size:17px; color:green;"><b>🔼</b></a> <a href="#🔚" style="font-size:17px; color:green;"><b>🔽</b></a></span><!-- jobs-toc:heading-end -->

只写唯一临时目录，结束清理；不安装软件、不修改用户配置、不运行服务或访问业务远端。祖先链接夹具在 macOS 运行，Windows 上跳过需要额外权限的链接创建；2026-10-26 在 Windows 11 ARM64 / Windows PowerShell 5.1.26100.9711 原生通过 41 项；根 CMD 回归另验证该仓 MD5 入口在无继承进程执行策略时的真实 `-Check`。真实桌面双击和外部工具业务仍需单独验收。

<a id="🔚" href="#前言" style="font-size:17px; color:green; font-weight:bold;">我是有底线的➤点我回到首页</a>
