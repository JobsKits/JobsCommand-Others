# `【MacOS】Jobs计划任务`

![Jobs出品，必属精品](https://picsum.photos/1500/400)

[toc]

---

## 🔥 <font id=前言>前言</font>

`Jobs 计划任务` 是一个面向 macOS 的原生菜单栏计划任务管理器。它不重新实现计时守护进程，而是为每个任务生成独立的 `LaunchAgent`，由系统原生 `launchd` 调度。

项目使用 [**Swift**](https://www.swift.org/) 与 AppKit/SwiftUI 构建菜单栏和管理界面，使用 `./Jobs计划任务.command` 作为统一安装、启动、升级、诊断和卸载入口。

## 一、主要能力 <a href="#前言" style="font-size:17px; color:green;"><b>🔼</b></a> <a href="#🔚" style="font-size:17px; color:green;"><b>🔽</b></a>

### 1.1、可执行目标

- 打开 App、文件夹和各种资料文件。
- 打开文本文档、PDF、图片、视频和音频。
- 打开 URL。
- 执行 `.command`、`.sh` 和 `.zsh` 脚本。
- 执行自定义 Shell 命令。
- 通过 `shortcuts run` 运行快捷指令。
- 支持拖拽目标和文件选择器两种录入方式。

### 1.2、计划类型

- 仅执行一次。
- 每天指定时间。
- 每周指定星期和时间。
- 每隔若干分钟执行。
- 用户登录后执行。
- 支持启用、停用、重新定义时间和立即执行。
- 支持在设置页打开终端配置、查看或取消 `pmset` 全局重复唤醒规则。

### 1.3、任务治理

- 设置任务超时时间。
- 选择允许并行、跳过重叠或终止旧任务。
- 保存执行时间、退出码、结果和完整日志。
- 成功或失败时发送系统通知。
- 删除任务先进入软件内部回收站，默认保留 `30` 天。
- 支持恢复、彻底删除和清空回收站。
- 支持全部任务的 JSON 导入和导出。

## 二、目录结构

```text
Jobs计划任务.command/
├── Jobs计划任务.command
├── Package.swift
├── README.md
├── Resources/
│   ├── AppIcon.icns
│   └── Info.plist
└── Sources/
    └── JobsScheduler/
        ├── AppPaths.swift
        ├── ContentView.swift
        ├── JobsSchedulerApp.swift
        ├── LaunchdManager.swift
        ├── SchedulerTask.swift
        ├── SupportingViews.swift
        ├── TaskEditorView.swift
        ├── TaskRunner.swift
        └── TaskStore.swift
```

## 三、安装与启动

### 3.1、双击入口

双击：

```text
./Jobs计划任务.command
```

确认脚本自述后选择：

```text
1. 安装并启动
```

脚本会执行 Release 编译，把 App 安装到当前用户的 `Applications` 目录，然后启动菜单栏 App。整个过程不需要 `sudo`。

### 3.2、菜单栏入口

启动后，Dock 与菜单栏都会显示醒目的红色闹钟入口；App 也会出现在 `Command-Option-Escape` 打开的“强制退出应用程序”列表中。菜单栏提供：

- 打开任务中心；
- 新建计划任务；
- 查看日志目录；
- 用户偏好；
- 退出 UI。

带刘海的 MacBook 会把过多的菜单栏项目挤到刘海后面。本 App 为状态项设置稳定位置标识，并在首次启动时默认放到距屏幕右侧约 `200` 点的位置，避免红色闹钟落入刘海遮挡区。

退出 UI 不会停止已经注册的计划任务，因为实际调度由 `launchd` 承担。

## 四、任务数据与系统文件

### 4.1、用户数据

任务、偏好、锁文件和日志保存在当前用户的 `Library/Application Support/com.jobs.scheduler` 目录中。

### 4.2、LaunchAgent

每个启用的任务都会在当前用户的 `Library/LaunchAgents` 目录生成一个文件：

```text
com.jobs.scheduler.task.<任务UUID>.plist
```

停用、删除或重新定义任务时，App 会同步注销旧任务并更新 plist。

## 五、睡眠、关机与错过执行

- Mac 处于清醒状态时，任务按计划执行。
- Mac 睡眠时，普通 LaunchAgent 不会主动唤醒电脑。
- `StartCalendarInterval` 类型的任务通常会在唤醒后补执行一次。
- 任务选择“错过后跳过”时，延迟超过 `10` 分钟会记录为跳过；手动“立即运行”不受此限制。
- Mac 关机时不能执行任务。
- 必须准点唤醒时，需要额外使用 `pmset`；该能力涉及管理员权限和系统级重复唤醒规则，不由普通任务静默修改。

设置页可以把配置命令送入终端，再由用户亲自输入管理员密码。对应命令示例：

```shell
sudo pmset repeat wakeorpoweron MTWRFSU 02:55:00
```

执行前应先查看现有规则，避免覆盖其他唤醒设置：

```shell
pmset -g sched
```

## 六、管理员权限与无人值守

- App 永远不保存开机密码。
- App 不会把密码写入脚本、plist、日志或钥匙串。
- 需要 `sudo` 的脚本无法依靠模拟回车实现无人值守。
- 确需无人值守时，应在 `/etc/sudoers.d/` 中只授权必要命令和固定参数。
- 不要配置不受限制的 `NOPASSWD: ALL`。
- 需要交互式 `read`、菜单选择或密码输入的脚本，不适合作为后台计划任务。

## 七、执行策略与日志

### 7.1、重叠任务

- `上次未结束则跳过`：适合更新、备份等不可重入任务。
- `允许并行`：适合互不影响的打开类任务。
- `终止旧任务后执行`：适合只需要保留最新实例的任务。

### 7.2、日志

每个任务拥有独立日志。可以在任务列表中查看日志，也可以从菜单栏或“执行记录”页面打开日志目录。

日志包含：

- 开始时间和结束结果；
- 标准输出和标准错误；
- 退出码；
- 超时和重叠跳过信息。

## 八、关闭窗口与退出 UI

默认关闭管理窗口时会询问：

- 关闭管理窗口并驻留到屏幕顶部、日期时间旁边的菜单栏；
- 退出 UI；
- 取消。

用户偏好中可以改成固定行为。选择驻留时会隐藏管理窗口，并在屏幕顶部菜单栏保留醒目的 `⏰ 计划任务` 入口；无论选择驻留还是退出 UI，已注册计划任务都继续由系统执行。

## 九、卸载

再次双击 `./Jobs计划任务.command`，选择：

```text
5. 卸载
```

卸载必须输入 `YES`。脚本会：

- 退出菜单栏 App；
- 注销并删除本软件生成的任务 LaunchAgent；
- 删除已安装 App；
- 再次询问是否删除任务数据和日志。

只有继续输入 `DELETE`，数据和日志才会被彻底删除。

## 十、已知边界

- 当前实现使用用户级 LaunchAgent，不负责无人登录状态下的系统级任务。
- 一次性计划由指定月、日和时间触发，执行成功或失败后自动停用；不应把日期设置到过去。
- Shell 参数按空格拆分，不负责还原复杂引号语法；复杂参数建议写入独立脚本。
- 文件被移动或改名后，原路径任务会失效，需要重新选择目标。
- `pmset` 的重复唤醒规则属于全局系统设置，多个任务不能无冲突地各自占用一套规则。

## 十一、静态诊断

入口菜单的“环境诊断”会检查：

- macOS 与 Swift 版本；
- App 是否已安装；
- 数据目录是否存在；
- 已生成的 LaunchAgent 数量；
- `Info.plist` 是否有效。

开发时还可以执行：

```shell
zsh -n ./Jobs计划任务.command
swift build --package-path .
plutil -lint ./Resources/Info.plist
```

<a id="🔚" href="#前言" style="font-size:17px; color:green; font-weight:bold;">我是有底线的➤点我回到首页</a>
