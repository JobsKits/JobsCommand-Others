//
//  ContentView.swift
//  JobsScheduler
//
//  Created by Jobs on 2026年7月13日，星期一.
//

import AppKit
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
                ExecutionLogsView()
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
        .alert("操作失败", isPresented: Binding(get: { store.lastError != nil }, set: { if !$0 { store.lastError = nil } })) {
            Button("知道了") { store.lastError = nil }
        } message: {
            Text(store.lastError ?? "未知错误")
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
                TaskRow(task: task, edit: { edit(task) })
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
}

struct TaskRow: View {
    @EnvironmentObject private var store: TaskStore
    let task: SchedulerTask
    let edit: () -> Void

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
                Text(task.lastMessage).font(.caption).foregroundStyle(.secondary).lineLimit(1)
            }
            Spacer()
            Toggle("", isOn: Binding(get: { task.enabled }, set: { store.setEnabled(task, enabled: $0) }))
                .labelsHidden()
            Button("立即运行") { LaunchdManager.runNow(task) }
            Button("编辑", action: edit)
            Menu {
                Button("在 Finder 中显示目标") {
                    NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: task.target)])
                }
                Button("查看日志") { NSWorkspace.shared.open(AppPaths.log(for: task)) }
                Divider()
                Button("移入回收站", role: .destructive) { store.moveToRecycleBin(task) }
            } label: {
                Image(systemName: "ellipsis.circle")
            }
            .menuStyle(.borderlessButton)
            .frame(width: 28)
        }
        .padding(.vertical, 6)
    }
}
