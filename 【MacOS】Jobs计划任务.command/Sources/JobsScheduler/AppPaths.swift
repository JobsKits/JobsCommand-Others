//
//  AppPaths.swift
//  JobsScheduler
//
//  Created by Jobs on 2026年7月13日，星期一.
//

import Foundation

enum AppPaths {
    static var fileManager: FileManager { FileManager.default }
    static let support = FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent("Library/Application Support/com.jobs.scheduler", isDirectory: true)
    static let tasks = support.appendingPathComponent("tasks.json")
    static let preferences = support.appendingPathComponent("preferences.json")
    static let logs = support.appendingPathComponent("Logs", isDirectory: true)
    static let locks = support.appendingPathComponent("Locks", isDirectory: true)
    static let launchAgents = FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent("Library/LaunchAgents", isDirectory: true)

    static func prepare() throws {
        for url in [support, logs, locks, launchAgents] {
            try fileManager.createDirectory(at: url, withIntermediateDirectories: true)
        }
    }

    static func plist(for task: SchedulerTask) -> URL {
        launchAgents.appendingPathComponent("\(task.label).plist")
    }

    static func log(for task: SchedulerTask) -> URL {
        logs.appendingPathComponent("\(task.id.uuidString).log")
    }
}
