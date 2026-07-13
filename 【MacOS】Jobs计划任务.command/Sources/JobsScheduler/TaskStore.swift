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

    private init() {
        load()
        purgeExpiredRecycleBin()
    }

    func load() {
        do {
            try AppPaths.prepare()
            if let data = try? Data(contentsOf: AppPaths.tasks) {
                tasks = try JSONDecoder.jobs.decode([SchedulerTask].self, from: data)
            }
            if let data = try? Data(contentsOf: AppPaths.preferences) {
                preferences = try JSONDecoder.jobs.decode(SchedulerPreferences.self, from: data)
            }
        } catch {
            lastError = error.localizedDescription
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
        } catch {
            lastError = error.localizedDescription
        }
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
