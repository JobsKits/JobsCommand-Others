//
//  SupportingViews.swift
//  JobsScheduler
//
//  Created by Jobs on 2026年7月13日，星期一.
//

import AppKit
import Combine
import SwiftUI
import UniformTypeIdentifiers

struct RecycleBinView: View {
    @EnvironmentObject private var store: TaskStore
    @State private var showingEmptyConfirmation = false

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("删除的任务默认保留 \(store.preferences.recycleRetentionDays) 天").foregroundStyle(.secondary)
                Spacer()
                Button("清空回收站", role: .destructive) { showingEmptyConfirmation = true }
                    .disabled(store.recycledTasks.isEmpty)
            }
            .padding()
            List(store.recycledTasks) { task in
                HStack {
                    VStack(alignment: .leading) {
                        Text(task.name).font(.headline)
                        Text(task.target).foregroundStyle(.secondary).lineLimit(1)
                    }
                    Spacer()
                    Button("恢复") { store.restore(task) }
                    Button("彻底删除", role: .destructive) { store.permanentlyDelete(task) }
                }
                .padding(.vertical, 5)
            }
            .overlay {
                if store.recycledTasks.isEmpty {
                    ContentUnavailableView("回收站为空", systemImage: "trash", description: Text("删除的任务会先停用并保留在这里。"))
                }
            }
        }
        .navigationTitle("回收站")
        .alert("确认清空回收站？", isPresented: $showingEmptyConfirmation) {
            Button("取消", role: .cancel) {}
            Button("永久删除", role: .destructive) { store.emptyRecycleBin() }
        } message: {
            Text("这会永久删除回收站中的 \(store.recycledTasks.count) 个任务及其日志，删除后无法恢复。")
        }
    }
}

struct ExecutionLogsView: View {
    @EnvironmentObject private var store: TaskStore
    @Binding var requestedTaskID: UUID?
    @State private var selection: UUID?
    @State private var logText = "请选择一个任务查看日志。"
    @State private var logTextRevision = UUID()
    @State private var scrollToEndRequestID = UUID()
    @State private var logIsTruncated = false
    @State private var logFileSize = 0
    @State private var loadsFullLog = false
    @State private var showingClearLogsConfirmation = false
    @State private var loggedTaskIDs: Set<UUID> = []
    @State private var followsLatestOutput = true
    @State private var logReader = ExecutionLogReader()
    @State private var loggedTasksRefreshTask: Task<Void, Never>?
    @State private var selectedLogRefreshTask: Task<Void, Never>?
    @State private var loggedTasksRefreshRequestID: UUID?
    @State private var selectedLogRefreshRequestID: UUID?
    private let logRefreshTimer = Timer.publish(every: 1, on: .main, in: .common).autoconnect()

    var body: some View {
        HSplitView {
            List(loggedTasks, selection: $selection) { task in
                VStack(alignment: .leading, spacing: 3) {
                    Text(task.name)
                    Text(task.lastRunAt?.formatted() ?? "尚未执行").font(.caption).foregroundStyle(.secondary)
                    Text(task.lastMessage).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                }
                .tag(task.id)
            }
            .frame(minWidth: 240)
            .contextMenu { clearLogsMenu }
            .overlay {
                if loggedTasks.isEmpty {
                    ContentUnavailableView("暂无执行记录", systemImage: "doc.text.magnifyingglass", description: Text("任务执行后会在这里显示日志。"))
                }
            }
            VStack(spacing: 0) {
                if logIsTruncated && !loadsFullLog {
                    HStack(spacing: 12) {
                        Text("为保持流畅，仅显示最近 \(ExecutionLogReader.tailLineLimit) 行（日志大小：\(formattedLogFileSize)）")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Spacer()
                        Button("加载完整日志", action: loadCompleteLog)
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    Divider()
                }
                LogTextView(
                    text: logText,
                    contentRevision: logTextRevision,
                    scrollToEndRequestID: scrollToEndRequestID,
                    followsLatestOutput: followsLatestOutput
                )
            }
            .contextMenu { clearLogsMenu }
        }
        .navigationTitle("执行记录")
        .toolbar {
            Toggle("跟随最新", isOn: $followsLatestOutput)
            if loadsFullLog {
                Button("只看最近 \(ExecutionLogReader.tailLineLimit) 行", action: loadRecentLog)
            }
            Button("打开日志目录") {
                try? AppPaths.prepare()
                NSWorkspace.shared.open(AppPaths.logs)
            }
        }
        .onChange(of: selection) { _, value in
            guard value != nil else { return }
            loadsFullLog = false
            logIsTruncated = false
            scrollToEndRequestID = UUID()
            updateLogText("正在加载日志…")
            refreshSelectedLog(force: true)
        }
        .onChange(of: store.tasks) { _, _ in reloadLoggedTasks() }
        .onChange(of: requestedTaskID) { _, _ in applyRequestedSelection() }
        .onReceive(logRefreshTimer) { _ in
            reloadLoggedTasks()
            refreshSelectedLog()
        }
        .onAppear {
            reloadLoggedTasks()
            applyRequestedSelection()
        }
        .onDisappear {
            loggedTasksRefreshTask?.cancel()
            selectedLogRefreshTask?.cancel()
            loggedTasksRefreshTask = nil
            selectedLogRefreshTask = nil
            loggedTasksRefreshRequestID = nil
            selectedLogRefreshRequestID = nil
        }
        .alert("清除全部日志？", isPresented: $showingClearLogsConfirmation) {
            Button("取消", role: .cancel) {}
            Button("清除", role: .destructive) { clearAllLogs() }
        } message: {
            Text("这会清空所有任务的执行日志，任务配置和调度不受影响。")
        }
    }

    @ViewBuilder private var clearLogsMenu: some View {
        Button("清除全部日志", role: .destructive) {
            showingClearLogsConfirmation = true
        }
    }

    private var loggedTasks: [SchedulerTask] {
        store.tasks
            .filter { loggedTaskIDs.contains($0.id) }
            .sorted { ($0.lastRunAt ?? .distantPast) > ($1.lastRunAt ?? .distantPast) }
    }

    private var formattedLogFileSize: String {
        ByteCountFormatter.string(fromByteCount: Int64(logFileSize), countStyle: .file)
    }

    private func reloadLoggedTasks() {
        guard loggedTasksRefreshTask == nil else { return }
        let logFiles = Dictionary(uniqueKeysWithValues: store.tasks.map { ($0.id, AppPaths.log(for: $0)) })
        let requestedTaskID = requestedTaskID
        let selectedTaskID = selection
        let reader = logReader
        let requestID = UUID()
        loggedTasksRefreshRequestID = requestID
        loggedTasksRefreshTask = Task { @MainActor in
            var taskIDs = await reader.taskIDsWithLogs(logFiles)
            guard loggedTasksRefreshRequestID == requestID else { return }
            loggedTasksRefreshTask = nil
            loggedTasksRefreshRequestID = nil
            guard !Task.isCancelled else { return }
            if let requestedTaskID {
                taskIDs.insert(requestedTaskID)
            }
            if let selectedTaskID {
                taskIDs.insert(selectedTaskID)
            }
            loggedTaskIDs = taskIDs
        }
    }

    private func applyRequestedSelection() {
        guard let requestedTaskID, store.tasks.contains(where: { $0.id == requestedTaskID }) else { return }
        loggedTaskIDs.insert(requestedTaskID)
        let shouldRefresh = selection == requestedTaskID
        selection = requestedTaskID
        self.requestedTaskID = nil
        if shouldRefresh {
            loadsFullLog = false
            logIsTruncated = false
            scrollToEndRequestID = UUID()
            updateLogText("正在加载日志…")
            refreshSelectedLog(force: true)
        }
    }

    private func refreshSelectedLog(force: Bool = false) {
        guard let selectedTaskID = selection,
              let task = store.tasks.first(where: { $0.id == selectedTaskID }) else { return }
        if !force, selectedLogRefreshTask != nil { return }
        let logURL = AppPaths.log(for: task)
        let reader = logReader
        let loadAll = loadsFullLog
        selectedLogRefreshTask?.cancel()
        let requestID = UUID()
        selectedLogRefreshRequestID = requestID
        selectedLogRefreshTask = Task { @MainActor in
            let result = await reader.read(taskID: selectedTaskID, from: logURL, force: force, loadAll: loadAll)
            guard selectedLogRefreshRequestID == requestID else { return }
            selectedLogRefreshTask = nil
            selectedLogRefreshRequestID = nil
            guard !Task.isCancelled, selection == selectedTaskID else { return }
            switch result {
            case .unchanged:
                break
            case let .loaded(snapshot):
                logIsTruncated = snapshot.isTruncated
                logFileSize = snapshot.fileSize
                updateLogText(snapshot.text)
            case .missing:
                logIsTruncated = false
                logFileSize = 0
                updateLogText("该任务暂无日志。")
            case let .failed(message):
                logIsTruncated = false
                updateLogText("读取日志失败：\(message)")
            }
        }
    }

    private func loadCompleteLog() {
        loadsFullLog = true
        logIsTruncated = false
        scrollToEndRequestID = UUID()
        updateLogText("正在加载完整日志…")
        refreshSelectedLog(force: true)
    }

    private func loadRecentLog() {
        loadsFullLog = false
        scrollToEndRequestID = UUID()
        updateLogText("正在加载最近日志…")
        refreshSelectedLog(force: true)
    }

    private func updateLogText(_ text: String) {
        logText = text
        logTextRevision = UUID()
    }

    private func clearAllLogs() {
        do {
            try AppPaths.prepare()
            let urls = try AppPaths.fileManager.contentsOfDirectory(at: AppPaths.logs, includingPropertiesForKeys: nil)
            for url in urls where url.pathExtension.lowercased() == "log" {
                let handle = try FileHandle(forWritingTo: url)
                try handle.truncate(atOffset: 0)
                try handle.close()
            }
            selection = nil
            loggedTaskIDs.removeAll()
            logIsTruncated = false
            logFileSize = 0
            loadsFullLog = false
            updateLogText("全部日志已清除。")
            Task { await logReader.reset() }
        } catch {
            updateLogText("清除日志失败：\(error.localizedDescription)")
        }
    }
}

struct PreferencesView: View {
    @EnvironmentObject private var store: TaskStore
    @State private var importing = false
    @State private var message = ""
    @State private var wakeTime = Calendar.current.date(bySettingHour: 2, minute: 55, second: 0, of: Date()) ?? Date()

    var body: some View {
        Form {
            Section("外观") {
                Picker("主题", selection: appearanceBinding) {
                    ForEach(AppAppearance.allCases) { appearance in
                        Text(appearance.rawValue).tag(appearance)
                    }
                }
                .pickerStyle(.segmented)
            }
            Section("回收站") {
                Stepper("删除任务保留 \(store.preferences.recycleRetentionDays) 天", value: $store.preferences.recycleRetentionDays, in: 1...365)
                Button("立即清理过期任务") { store.savePreferences() }
            }
            Section("关闭窗口") {
                Picker("默认行为", selection: $store.preferences.closeBehavior) {
                    Text("每次询问").tag("ask")
                    Text("关闭窗口并驻留到顶部菜单栏").tag("hide")
                    Text("退出 UI").tag("quit")
                }
                Text("退出 UI 不会取消已经注册的计划任务。").font(.caption).foregroundStyle(.secondary)
            }
            Section("配置备份") {
                HStack {
                    Button("导出全部任务") { exportTasks() }
                    Button("导入任务") { importing = true }
                    if !message.isEmpty { Text(message).foregroundStyle(.secondary) }
                }
            }
            Section("系统能力") {
                LabeledContent("调度引擎", value: "launchd / LaunchAgent")
                LabeledContent("数据目录", value: AppPaths.support.path)
                Button("打开数据目录") {
                    try? AppPaths.prepare()
                    NSWorkspace.shared.open(AppPaths.support)
                }
                Text("管理员命令不会保存密码。需要 sudo 的脚本必须提前配置最小范围授权。")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Section("定时唤醒") {
                DatePicker("每天唤醒时间", selection: $wakeTime, displayedComponents: [.hourAndMinute])
                HStack {
                    Button("在终端配置每天唤醒") { configureWake() }
                    Button("查看当前唤醒规则") { showWakeSchedule() }
                    Button("在终端取消重复唤醒", role: .destructive) { cancelWake() }
                }
                Text("pmset 的重复唤醒是全局系统规则，只能保留一套；操作会打开终端并由用户亲自输入管理员密码。")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .navigationTitle("用户偏好")
        .onChange(of: store.preferences.appearance) { _, _ in store.savePreferences() }
        .onChange(of: store.preferences.recycleRetentionDays) { _, _ in store.savePreferences() }
        .onChange(of: store.preferences.closeBehavior) { _, _ in store.savePreferences() }
        .fileImporter(isPresented: $importing, allowedContentTypes: [.json]) { result in
            do {
                let url = try result.get()
                try store.importFrom(url)
                message = "导入成功"
            } catch {
                message = "导入失败：\(error.localizedDescription)"
            }
        }
    }

    private var appearanceBinding: Binding<AppAppearance> {
        Binding(
            get: { store.preferences.appearance ?? .system },
            set: { store.preferences.appearance = $0 }
        )
    }

    private func exportTasks() {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.json]
        panel.nameFieldStringValue = "Jobs计划任务备份.json"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            try store.export(to: url)
            message = "导出成功"
        } catch {
            message = "导出失败：\(error.localizedDescription)"
        }
    }

    private func configureWake() {
        let values = Calendar.current.dateComponents([.hour, .minute], from: wakeTime)
        let time = String(format: "%02d:%02d:00", values.hour ?? 2, values.minute ?? 55)
        runInTerminal("sudo pmset repeat wakeorpoweron MTWRFSU \(time); pmset -g sched")
    }

    private func showWakeSchedule() {
        runInTerminal("pmset -g sched")
    }

    private func cancelWake() {
        runInTerminal("sudo pmset repeat cancel; pmset -g sched")
    }

    private func runInTerminal(_ command: String) {
        let escaped = command.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "\"", with: "\\\"")
        let script = "tell application \"Terminal\" to do script \"\(escaped)\"\ntell application \"Terminal\" to activate"
        var error: NSDictionary?
        NSAppleScript(source: script)?.executeAndReturnError(&error)
        if let error { message = "打开终端失败：\(error)" }
    }
}
