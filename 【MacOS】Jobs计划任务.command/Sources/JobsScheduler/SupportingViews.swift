//
//  SupportingViews.swift
//  JobsScheduler
//
//  Created by Jobs on 2026年7月13日，星期一.
//

import AppKit
import SwiftUI
import UniformTypeIdentifiers

struct RecycleBinView: View {
    @EnvironmentObject private var store: TaskStore

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("删除的任务默认保留 \(store.preferences.recycleRetentionDays) 天").foregroundStyle(.secondary)
                Spacer()
                Button("清空回收站", role: .destructive) { store.emptyRecycleBin() }
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
    }
}

struct ExecutionLogsView: View {
    @EnvironmentObject private var store: TaskStore
    @State private var selection: UUID?
    @State private var logText = "请选择一个任务查看日志。"

    var body: some View {
        HSplitView {
            List(store.tasks, selection: $selection) { task in
                VStack(alignment: .leading, spacing: 3) {
                    Text(task.name)
                    Text(task.lastRunAt?.formatted() ?? "尚未执行").font(.caption).foregroundStyle(.secondary)
                }
                .tag(task.id)
            }
            .frame(minWidth: 240)
            ScrollView {
                Text(logText)
                    .font(.system(.body, design: .monospaced))
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .topLeading)
                    .padding()
            }
        }
        .navigationTitle("执行记录")
        .toolbar {
            Button("打开日志目录") {
                try? AppPaths.prepare()
                NSWorkspace.shared.open(AppPaths.logs)
            }
        }
        .onChange(of: selection) { _, value in
            guard let value, let task = store.tasks.first(where: { $0.id == value }) else { return }
            logText = (try? String(contentsOf: AppPaths.log(for: task), encoding: .utf8)) ?? "该任务暂无日志。"
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
