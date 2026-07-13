//
//  SchedulerTask.swift
//  JobsScheduler
//
//  Created by Jobs on 2026年7月13日，星期一.
//

import Foundation

enum TaskAction: String, Codable, CaseIterable, Identifiable {
    case open = "打开文件、资料、文件夹或 App"
    case url = "打开 URL"
    case shell = "执行 Shell / command 脚本"
    case command = "执行自定义命令"
    case shortcut = "运行快捷指令"

    var id: String { rawValue }
}

enum ScheduleKind: String, Codable, CaseIterable, Identifiable {
    case once = "仅执行一次"
    case daily = "每天"
    case weekly = "每周"
    case interval = "按间隔"
    case login = "登录后"

    var id: String { rawValue }
}

enum MissedRunPolicy: String, Codable, CaseIterable, Identifiable {
    case runOnWake = "唤醒后补执行"
    case skip = "错过后跳过"

    var id: String { rawValue }
}

enum OverlapPolicy: String, Codable, CaseIterable, Identifiable {
    case skip = "上次未结束则跳过"
    case parallel = "允许并行"
    case terminatePrevious = "终止旧任务后执行"

    var id: String { rawValue }
}

struct SchedulerTask: Codable, Identifiable, Hashable {
    var id = UUID()
    var name = "新计划任务"
    var action: TaskAction = .open
    var target = ""
    var arguments = ""
    var workingDirectory = ""
    var schedule: ScheduleKind = .daily
    var fireDate = Date().addingTimeInterval(3600)
    var weekday = 2
    var intervalMinutes = 60
    var enabled = true
    var missedRunPolicy: MissedRunPolicy = .runOnWake
    var overlapPolicy: OverlapPolicy = .skip
    var timeoutMinutes = 60
    var notifyOnSuccess = false
    var notifyOnFailure = true
    var createdAt = Date()
    var updatedAt = Date()
    var lastRunAt: Date?
    var lastExitCode: Int32?
    var lastMessage = "尚未执行"
    var deletedAt: Date?

    var label: String { "com.jobs.scheduler.task.\(id.uuidString.lowercased())" }
    var isDeleted: Bool { deletedAt != nil }
}

struct SchedulerPreferences: Codable {
    var recycleRetentionDays = 30
    var closeBehavior = "ask"
    var notifyOnFailure = true
}

struct SchedulerExport: Codable {
    var version = 2
    var exportedAt = Date()
    var tasks: [SchedulerTask]
    var preferences: SchedulerPreferences
}
