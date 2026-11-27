//
//  TaskStore.swift
//  JobsScheduler
//
//  Created by Jobs on 2026年7月13日，星期一.
//

import Combine
import Foundation

@MainActor
final class TaskStore: ObservableObject {
    static let shared = TaskStore()

    @Published private(set) var tasks: [SchedulerTask] = []
    @Published var preferences = SchedulerPreferences()
    @Published var lastError: String?

    var activeTasks: [SchedulerTask] { tasks.filter { !$0.isDeleted } }
    var recycledTasks: [SchedulerTask] { tasks.filter(\.isDeleted) }
    private var tasksModificationDate: Date?

    private init() {
        load()
        purgeExpiredRecycleBin()
    }

    func load() {
        do {
            try AppPaths.prepare()
            if let data = try? Data(contentsOf: AppPaths.tasks) {
                let decodedTasks = try JSONDecoder.jobs.decode([SchedulerTask].self, from: data)
                tasks = decodedTasks
                    .map(migratingLegacyExecutionMessage)
                    .map { Self.reconcilingInterruptedExecution($0, isExecutionActive: TaskLock.isHeld(for:)) }
                if tasks != decodedTasks {
                    try JSONEncoder.jobs.encode(tasks).write(to: AppPaths.tasks, options: .atomic)
                }
            }
            if let data = try? Data(contentsOf: AppPaths.preferences) {
                preferences = try JSONDecoder.jobs.decode(SchedulerPreferences.self, from: data)
            }
            tasksModificationDate = currentTasksModificationDate()
        } catch {
            lastError = error.localizedDescription
        }
    }

    func reloadIfChanged() {
        if currentTasksModificationDate() != tasksModificationDate {
            load()
        } else {
            reconcileInterruptedExecutions()
        }
    }

    func save(_ task: SchedulerTask) {
        var value = task
        value.updatedAt = Date()
        if let index = tasks.firstIndex(where: { $0.id == value.id }) {
            tasks[index] = value
        } else {
            tasks.append(value)
        }
        persist()
        synchronize(value)
    }

    func moveToRecycleBin(_ task: SchedulerTask) {
        guard let index = tasks.firstIndex(where: { $0.id == task.id }) else { return }
        LaunchdManager.unregister(tasks[index])
        tasks[index].enabled = false
        tasks[index].deletedAt = Date()
        persist()
    }

    func restore(_ task: SchedulerTask) {
        guard let index = tasks.firstIndex(where: { $0.id == task.id }) else { return }
        tasks[index].deletedAt = nil
        tasks[index].enabled = true
        persist()
        synchronize(tasks[index])
    }

    func permanentlyDelete(_ task: SchedulerTask) {
        LaunchdManager.unregister(task)
        tasks.removeAll { $0.id == task.id }
        try? AppPaths.fileManager.removeItem(at: AppPaths.log(for: task))
        persist()
    }

    func emptyRecycleBin() {
        recycledTasks.forEach(permanentlyDelete)
    }

    func setEnabled(_ task: SchedulerTask, enabled: Bool) {
        guard let index = tasks.firstIndex(where: { $0.id == task.id }) else { return }
        tasks[index].enabled = enabled
        tasks[index].updatedAt = Date()
        persist()
        synchronize(tasks[index])
    }

    func markExecutionStarted(id: UUID) {
        guard let index = tasks.firstIndex(where: { $0.id == id }) else { return }
        tasks[index].lastRunAt = Date()
        tasks[index].lastExitCode = nil
        tasks[index].lastMessage = "正在执行…"
        persist()
    }

    func updateExecution(id: UUID, exitCode: Int32, message: String) {
        guard let index = tasks.firstIndex(where: { $0.id == id }) else { return }
        tasks[index].lastRunAt = Date()
        tasks[index].lastExitCode = exitCode
        tasks[index].lastMessage = message
        if tasks[index].schedule == .once {
            tasks[index].enabled = false
            LaunchdManager.unregister(tasks[index])
        }
        persist()
    }

    func savePreferences() {
        do {
            try AppPaths.prepare()
            try JSONEncoder.jobs.encode(preferences).write(to: AppPaths.preferences, options: .atomic)
            purgeExpiredRecycleBin()
        } catch {
            lastError = error.localizedDescription
        }
    }

    func export(to url: URL) throws {
        let value = SchedulerExport(tasks: tasks, preferences: preferences)
        try JSONEncoder.jobs.encode(value).write(to: url, options: .atomic)
    }

    func importFrom(_ url: URL) throws {
        let value = try JSONDecoder.jobs.decode(SchedulerExport.self, from: Data(contentsOf: url))
        tasks.forEach(LaunchdManager.unregister)
        tasks = value.tasks
        preferences = value.preferences
        persist()
        savePreferences()
        activeTasks.filter(\.enabled).forEach(synchronize)
    }

    private func synchronize(_ task: SchedulerTask) {
        do {
            if task.enabled && !task.isDeleted {
                try LaunchdManager.register(task)
            } else {
                LaunchdManager.unregister(task)
            }
        } catch {
            lastError = error.localizedDescription
        }
    }

    private func purgeExpiredRecycleBin() {
        let cutoff = Calendar.current.date(byAdding: .day, value: -max(preferences.recycleRetentionDays, 1), to: Date()) ?? Date()
        recycledTasks.filter { ($0.deletedAt ?? Date()) < cutoff }.forEach(permanentlyDelete)
    }

    private func persist() {
        do {
            try AppPaths.prepare()
            try JSONEncoder.jobs.encode(tasks).write(to: AppPaths.tasks, options: .atomic)
            tasksModificationDate = currentTasksModificationDate()
        } catch {
            lastError = error.localizedDescription
        }
    }

    private func currentTasksModificationDate() -> Date? {
        let attributes = try? AppPaths.fileManager.attributesOfItem(atPath: AppPaths.tasks.path)
        return attributes?[.modificationDate] as? Date
    }

    private func reconcileInterruptedExecutions() {
        let reconciledTasks = tasks.map {
            Self.reconcilingInterruptedExecution($0, isExecutionActive: TaskLock.isHeld(for:))
        }
        guard reconciledTasks != tasks else { return }
        tasks = reconciledTasks
        persist()
    }

    static func reconcilingInterruptedExecution(
        _ task: SchedulerTask,
        isExecutionActive: (SchedulerTask) -> Bool
    ) -> SchedulerTask {
        guard task.lastExitCode == nil,
              task.lastMessage == "正在执行…",
              !isExecutionActive(task) else { return task }
        var value = task
        value.lastExitCode = -2
        value.lastMessage = "上次执行进程已结束，但未能记录退出结果"
        return value
    }

    private func migratingLegacyExecutionMessage(_ task: SchedulerTask) -> SchedulerTask {
        guard task.lastExitCode == 75, task.lastMessage == "上次任务尚未结束，本次已跳过" else { return task }
        var value = task
        value.lastMessage = "旧版本曾因锁记录跳过；无法据此确认当时是否仍有实例运行"
        return value
    }
}

extension JSONEncoder {
    static var jobs: JSONEncoder {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        return encoder
    }
}

extension JSONDecoder {
    static var jobs: JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }
}
