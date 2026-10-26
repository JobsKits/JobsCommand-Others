//
//  ContentView.swift
//  JobsScheduler
//
//  Created by Jobs on 2026年7月13日，星期一.
//

import AppKit
import Combine
import SwiftUI
import UniformTypeIdentifiers

struct ContentView: View {
    enum Section: String, CaseIterable, Identifiable {
        case tasks = "计划任务"
        case recycle = "回收站"
        case logs = "执行记录"
        case settings = "用户偏好"

        var id: String { rawValue }
        var icon: String {
            switch self {
            case .tasks: "calendar.badge.clock"
            case .recycle: "trash"
            case .logs: "doc.text.magnifyingglass"
            case .settings: "gearshape"
            }
        }
    }

    @EnvironmentObject private var store: TaskStore
    @State private var selection: Section? = .tasks
    @State private var editingTask: SchedulerTask?
    @State private var showingEditor = false
    @State private var search = ""
    @State private var requestedLogTaskID: UUID?
    private let taskRefreshTimer = Timer.publish(every: 1, on: .main, in: .common).autoconnect()

    var body: some View {
        NavigationSplitView {
            List(Section.allCases, selection: $selection) { item in
                Label(item.rawValue, systemImage: item.icon).tag(item)
            }
            .navigationTitle("Jobs 计划任务")
        } detail: {
            switch selection ?? .tasks {
            case .tasks:
                taskList
            case .recycle:
                RecycleBinView()
            case .logs:
                ExecutionLogsView(requestedTaskID: $requestedLogTaskID)
            case .settings:
                PreferencesView()
            }
        }
        .sheet(isPresented: $showingEditor) {
            TaskEditorView(task: editingTask ?? SchedulerTask()) { value in
                store.save(value)
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .newSchedulerTask)) { _ in newTask() }
        .onReceive(NotificationCenter.default.publisher(for: .showSchedulerPreferences)) { _ in selection = .settings }
        .onReceive(taskRefreshTimer) { _ in store.reloadIfChanged() }
        .alert("操作失败", isPresented: Binding(get: { store.lastError != nil }, set: { if !$0 { store.lastError = nil } })) {
            Button("知道了") { store.lastError = nil }
        } message: {
            Text(store.lastError ?? "未知错误")
        }
        .preferredColorScheme(preferredColorScheme)
    }

    private var preferredColorScheme: ColorScheme? {
        switch store.preferences.appearance ?? .system {
        case .system: nil
        case .light: .light
        case .dark: .dark
        }
    }

    private var taskList: some View {
        VStack(spacing: 0) {
            HStack {
                TextField("搜索任务", text: $search)
                    .textFieldStyle(.roundedBorder)
                    .frame(maxWidth: 320)
                Spacer()
                Button("新建任务", systemImage: "plus") { newTask() }
                    .buttonStyle(.borderedProminent)
            }
            .padding()
            List(filteredTasks) { task in
                TaskRow(
                    task: task,
                    edit: { edit(task) },
                    showDetails: { showDetails(for: task) }
                )
            }
            .overlay {
                if filteredTasks.isEmpty {
                    ContentUnavailableView("暂无计划任务", systemImage: "calendar.badge.plus", description: Text("点击“新建任务”，或把文件拖入任务编辑器。"))
                }
            }
        }
        .navigationTitle("计划任务")
    }

    private var filteredTasks: [SchedulerTask] {
        guard !search.isEmpty else { return store.activeTasks.sorted { $0.updatedAt > $1.updatedAt } };return store.activeTasks.filter { $0.name.localizedCaseInsensitiveContains(search) || $0.target.localizedCaseInsensitiveContains(search) }
    }

    private func newTask() {
        editingTask = SchedulerTask()
        showingEditor = true
    }

    private func edit(_ task: SchedulerTask) {
        editingTask = task
        showingEditor = true
    }

    private func showDetails(for task: SchedulerTask) {
        requestedLogTaskID = task.id
        selection = .logs
    }
}

struct TaskRow: View {
    @EnvironmentObject private var store: TaskStore
    let task: SchedulerTask
    let edit: () -> Void
    let showDetails: () -> Void

    var body: some View {
        HStack(spacing: 14) {
            Image(systemName: task.lastExitCode == 0 ? "checkmark.circle.fill" : "calendar.badge.clock")
                .font(.title2)
                .foregroundStyle(task.enabled ? Color.accentColor : Color.secondary)
            VStack(alignment: .leading, spacing: 5) {
                Text(task.name).font(.headline)
                Text("\(task.schedule.rawValue) · \(task.target)")
                    .lineLimit(1)
                    .foregroundStyle(.secondary)
                Text("配置时间：\(configuredScheduleText)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                TimelineView(.periodic(from: .now, by: 1)) { context in
                    Text(nextRunText(at: context.date))
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(task.enabled ? Color.accentColor : Color.secondary)
                }
                Text(lastExecutionText).font(.caption).foregroundStyle(.secondary).lineLimit(1)
            }
            Spacer()
            Toggle("", isOn: Binding(get: { task.enabled }, set: { store.setEnabled(task, enabled: $0) }))
                .labelsHidden()
            Button("立即运行") { LaunchdManager.runNow(task) }
            Button("显示详情", action: showDetails)
            Button(action: edit) {
                Image(systemName: "gearshape")
            }
            .accessibilityLabel("编辑任务")
            .help("编辑任务")
        }
        .padding(.vertical, 6)
        .contentShape(Rectangle())
        .contextMenu {
            Button("在 Finder 中显示目标") {
                NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: task.target)])
            }
            Button("查看日志", action: showDetails)
            Divider()
            Button("移入回收站", role: .destructive) { store.moveToRecycleBin(task) }
        }
    }

    private var configuredScheduleText: String {
        let time = task.fireDate.formatted(date: .omitted, time: .shortened)
        switch task.schedule {
        case .once:
            return task.fireDate.formatted(date: .numeric, time: .shortened)
        case .daily:
            return "每天 \(time)"
        case .weekly:
            let weekdays = ["星期日", "星期一", "星期二", "星期三", "星期四", "星期五", "星期六"]
            let index = min(max(task.weekday - 1, 0), weekdays.count - 1)
            return "\(weekdays[index]) \(time)"
        case .interval:
            return "每 \(task.intervalMinutes) 分钟"
        case .login:
            return "用户登录后"
        }
    }

    private var lastExecutionText: String {
        guard task.lastExitCode == 0, let lastRunAt = task.lastRunAt else { return task.lastMessage }
        let completionTime = lastRunAt.formatted(date: .abbreviated, time: .standard)
        return "\(task.lastMessage) · 完成时间：\(completionTime)"
    }

    private func nextRunText(at now: Date) -> String {
        guard task.enabled else { return "下次执行：任务已停用" }
        guard task.schedule != .login else { return "下次执行：用户下次登录时" }
        guard let nextRun = task.nextRunDate(after: now) else {
            return task.schedule == .once ? "下次执行：一次性计划时间已过" : "下次执行：待系统计算"
        }
        let remaining = max(Int(nextRun.timeIntervalSince(now)), 0)
        let hours = remaining / 3_600
        let minutes = remaining % 3_600 / 60
        let seconds = remaining % 60
        let countdown = String(format: "%02d:%02d:%02d", hours, minutes, seconds)
        let nextRunDescription = nextRun.formatted(date: .abbreviated, time: .standard)
        return "下次执行：\(nextRunDescription) · 倒计时：\(countdown)"
    }
}
