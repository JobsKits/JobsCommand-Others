//
//  TaskEditorView.swift
//  JobsScheduler
//
//  Created by Jobs on 2026年7月13日，星期一.
//

import SwiftUI
import UniformTypeIdentifiers

struct TaskEditorView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var task: SchedulerTask
    @State private var selectingTarget = false
    @State private var dropTargeted = false
    let save: (SchedulerTask) -> Void

    init(task: SchedulerTask, save: @escaping (SchedulerTask) -> Void) {
        _task = State(initialValue: task)
        self.save = save
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text(task.createdAt == task.updatedAt ? "新建计划任务" : "编辑计划任务").font(.title2).bold()
                Spacer()
                Button("取消") { dismiss() }
                Button("保存") {
                    var value = task
                    if value.action == .command && value.target.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                        value.target = "update -t"
                    }
                    save(value)
                    dismiss()
                }
                .buttonStyle(.borderedProminent)
                .disabled(task.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || (task.action != .command && task.target.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty))
            }
            .padding()
            Divider()
            Form {
                Section("基本信息") {
                    TextField("任务名称", text: $task.name)
                    Picker("动作类型", selection: $task.action) {
                        ForEach(TaskAction.allCases) { Text($0.rawValue).tag($0) }
                    }
                }
                Section("目标") {
                    if task.action == .command {
                        commandEditor
                    } else {
                        HStack {
                            TextField(text: $task.target, prompt: Text(targetPlaceholder)) {
                                EmptyView()
                            }
                            .accessibilityLabel("目标")
                            if [.open, .shell].contains(task.action) {
                                Button("选择…") { selectingTarget = true }
                            }
                        }
                    }
                    if task.action == .shell {
                        TextField("参数，以空格分隔", text: $task.arguments)
                        TextField("工作目录，可留空", text: $task.workingDirectory)
                    }
                    RoundedRectangle(cornerRadius: 10)
                        .strokeBorder(dropTargeted ? Color.accentColor : Color.secondary.opacity(0.4), style: StrokeStyle(lineWidth: 2, dash: [7]))
                        .frame(height: 72)
                        .overlay(Text("把 App、脚本、文件、资料或文件夹拖到这里，自动识别动作类型").foregroundStyle(.secondary))
                        .onDrop(of: [UTType.fileURL], isTargeted: $dropTargeted) { providers in
                            guard let provider = providers.first else { return false }
                            provider.loadDataRepresentation(forTypeIdentifier: UTType.fileURL.identifier) { data, _ in
                                guard let data, let url = URL(dataRepresentation: data, relativeTo: nil) else { return }
                                DispatchQueue.main.async { applyFileTarget(url) }
                            };return true
                        }
                }
                Section("计划时间") {
                    Picker("计划类型", selection: $task.schedule) {
                        ForEach(ScheduleKind.allCases) { Text($0.rawValue).tag($0) }
                    }
                    if task.schedule == .once {
                        DatePicker("执行日期", selection: $task.fireDate, displayedComponents: [.date])
                        WheelTimePicker(title: "执行时刻", selection: $task.fireDate)
                    } else if [.daily, .weekly].contains(task.schedule) {
                        WheelTimePicker(title: "执行时刻", selection: $task.fireDate)
                    }
                    if task.schedule == .weekly {
                        Picker("星期", selection: $task.weekday) {
                            Text("星期日").tag(1); Text("星期一").tag(2); Text("星期二").tag(3); Text("星期三").tag(4)
                            Text("星期四").tag(5); Text("星期五").tag(6); Text("星期六").tag(7)
                        }
                    }
                    if task.schedule == .interval {
                        Stepper("每 \(task.intervalMinutes) 分钟", value: $task.intervalMinutes, in: 1...43_200)
                    }
                    Picker("睡眠错过", selection: $task.missedRunPolicy) {
                        ForEach(MissedRunPolicy.allCases) { Text($0.rawValue).tag($0) }
                    }
                }
                Section("执行策略") {
                    Picker("重复运行", selection: $task.overlapPolicy) {
                        ForEach(OverlapPolicy.allCases) { Text($0.displayName).tag($0) }
                    }
                    Stepper("超时：\(task.timeoutMinutes) 分钟", value: $task.timeoutMinutes, in: 1...1440)
                    Toggle("成功时通知", isOn: $task.notifyOnSuccess)
                    Toggle("失败时通知", isOn: $task.notifyOnFailure)
                    Toggle("立即启用", isOn: $task.enabled)
                }
            }
            .formStyle(.grouped)
        }
        .frame(width: 720, height: 700)
        .fileImporter(isPresented: $selectingTarget, allowedContentTypes: [.item], allowsMultipleSelection: false) { result in
            if case let .success(urls) = result, let url = urls.first { applyFileTarget(url) }
        }
    }

    private var commandEditor: some View {
        ZStack(alignment: .topLeading) {
            RoundedRectangle(cornerRadius: 6)
                .fill(Color(nsColor: .textBackgroundColor))
            if task.target.isEmpty {
                TextEditor(text: .constant(targetPlaceholder))
                    .font(.system(.body, design: .monospaced))
                    .foregroundStyle(.tertiary)
                    .scrollContentBackground(.hidden)
                    .padding(.horizontal, 3)
                    .allowsHitTesting(false)
                    .accessibilityHidden(true)
            }
            TextEditor(text: $task.target)
                .font(.system(.body, design: .monospaced))
                .scrollContentBackground(.hidden)
                .padding(.horizontal, 3)
                .accessibilityLabel("自定义命令")
        }
        .frame(maxWidth: .infinity, minHeight: 48, maxHeight: 72)
        .overlay {
            RoundedRectangle(cornerRadius: 6)
                .stroke(Color.secondary.opacity(0.35))
        }
    }

    private func applyFileTarget(_ url: URL) {
        task.target = url.path
        task.action = ["command", "sh", "zsh"].contains(url.pathExtension.lowercased()) ? .shell : .open
    }

    private var targetPlaceholder: String {
        switch task.action {
        case .open: "文件、资料、文件夹或 App 路径"
        case .url: "https://…"
        case .shell: "Shell 或 .command 脚本路径"
        case .command: "默认：update -t（留空即执行）"
        case .shortcut: "快捷指令名称"
        }
    }
}
