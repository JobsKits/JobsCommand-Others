//
//  TaskRunner.swift
//  JobsScheduler
//
//  Created by Jobs on 2026年7月13日，星期一.
//

import AppKit
import Foundation
import UserNotifications

enum TaskRunner {
    static func run(taskID: UUID, ignoreMissed: Bool = false) async {
        let store = await TaskStore.shared
        guard let task = await store.tasks.first(where: { $0.id == taskID && $0.enabled && !$0.isDeleted }) else { return }
        if !ignoreMissed && shouldSkipMissedRun(task) {
            await store.updateExecution(id: task.id, exitCode: 76, message: "计划时间已错过超过 10 分钟，按任务策略跳过")
            return
        }
        let lock = TaskLock(task: task)
        guard task.overlapPolicy == .parallel || lock.acquire(terminatePrevious: task.overlapPolicy == .terminatePrevious) else {
            await store.updateExecution(id: task.id, exitCode: 75, message: "上次任务尚未结束，本次已跳过")
            return
        }
        defer { lock.release() }
        await store.markExecutionStarted(id: task.id)
        appendLog(task: task, message: "开始执行：\(task.target)")
        let result = execute(task)
        sanitizeLog(task: task)
        appendLog(task: task, message: result.message)
        await store.updateExecution(id: task.id, exitCode: result.code, message: result.message)
        if (result.code == 0 && task.notifyOnSuccess) || (result.code != 0 && task.notifyOnFailure) {
            notify(task: task, result: result)
        }
    }

    private static func execute(_ task: SchedulerTask) -> (code: Int32, message: String) {
        let process = Process()
        process.environment = commandEnvironment()
        switch task.action {
        case .open:
            process.executableURL = URL(fileURLWithPath: "/usr/bin/open")
            process.arguments = [task.target]
        case .url:
            process.executableURL = URL(fileURLWithPath: "/usr/bin/open")
            process.arguments = [task.target]
        case .shell:
            process.executableURL = URL(fileURLWithPath: "/bin/zsh")
            process.arguments = [task.target] + split(task.arguments)
        case .command:
            process.executableURL = URL(fileURLWithPath: "/bin/zsh")
            process.arguments = ["-lc", task.target]
        case .shortcut:
            process.executableURL = URL(fileURLWithPath: "/usr/bin/shortcuts")
            process.arguments = ["run", task.target]
        }
        if !task.workingDirectory.isEmpty {
            process.currentDirectoryURL = URL(fileURLWithPath: task.workingDirectory, isDirectory: true)
        }
        do {
            try AppPaths.prepare()
            let logURL = AppPaths.log(for: task)
            if !AppPaths.fileManager.fileExists(atPath: logURL.path) {
                try Data().write(to: logURL)
            }
            let outputHandle = try FileHandle(forWritingTo: logURL)
            try outputHandle.seekToEnd()
            process.standardOutput = outputHandle
            process.standardError = outputHandle
            defer { try? outputHandle.close() }
            try process.run()
            let deadline = Date().addingTimeInterval(TimeInterval(max(task.timeoutMinutes, 1) * 60))
            while process.isRunning && Date() < deadline {
                Thread.sleep(forTimeInterval: 0.2)
            }
            if process.isRunning {
                process.terminate()
                return (124, "任务超过 \(task.timeoutMinutes) 分钟，已终止")
            }
            try outputHandle.synchronize()
            return (process.terminationStatus, process.terminationStatus == 0 ? "执行成功" : "执行失败，退出码：\(process.terminationStatus)")
        } catch {
            return (-1, error.localizedDescription)
        }
    }

    private static func commandEnvironment() -> [String: String] {
        var environment = ProcessInfo.processInfo.environment
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        let preferredPaths = [
            "\(home)/.local/bin",
            "/opt/homebrew/bin",
            "/opt/homebrew/sbin",
            "/usr/local/bin",
            "/usr/local/sbin",
            "/usr/bin",
            "/bin",
            "/usr/sbin",
            "/sbin"
        ]
        let inheritedPaths = environment["PATH", default: ""]
            .split(separator: ":")
            .map(String.init)
        var paths: [String] = []
        for path in preferredPaths + inheritedPaths where !paths.contains(path) {
            paths.append(path)
        }
        environment["PATH"] = paths.joined(separator: ":")
        return environment
    }

    private static func split(_ text: String) -> [String] {
        text.split(whereSeparator: \.isWhitespace).map(String.init)
    }

    private static func appendLog(task: SchedulerTask, message: String) {
        try? AppPaths.prepare()
        let line = "[\(ISO8601DateFormatter().string(from: Date()))] \(message)\n"
        let url = AppPaths.log(for: task)
        if !AppPaths.fileManager.fileExists(atPath: url.path) {
            try? Data().write(to: url)
        }
        guard let handle = try? FileHandle(forWritingTo: url) else { return }
        defer { try? handle.close() }
        _ = try? handle.seekToEnd()
        try? handle.write(contentsOf: Data(line.utf8))
    }

    private static func sanitizeLog(task: SchedulerTask) {
        let url = AppPaths.log(for: task)
        guard let text = try? String(contentsOf: url, encoding: .utf8) else { return }
        let cleaned = ANSITextSanitizer.clean(text)
        guard cleaned != text else { return }
        try? cleaned.write(to: url, atomically: true, encoding: .utf8)
    }

    private static func shouldSkipMissedRun(_ task: SchedulerTask) -> Bool {
        guard task.missedRunPolicy == .skip else { return false }
        let calendar = Calendar.current
        let now = Date()
        let scheduled: Date?
        switch task.schedule {
        case .once:
            scheduled = task.fireDate
        case .daily:
            let time = calendar.dateComponents([.hour, .minute], from: task.fireDate)
            scheduled = calendar.date(bySettingHour: time.hour ?? 0, minute: time.minute ?? 0, second: 0, of: now)
        case .weekly:
            let time = calendar.dateComponents([.hour, .minute], from: task.fireDate)
            scheduled = calendar.nextDate(
                after: calendar.date(byAdding: .day, value: -7, to: now) ?? now,
                matching: DateComponents(hour: time.hour, minute: time.minute, weekday: task.weekday),
                matchingPolicy: .nextTime
            )
        case .interval, .login:
            scheduled = nil
        }
        guard let scheduled else { return false };return now.timeIntervalSince(scheduled) > 600
    }

    private static func notify(task: SchedulerTask, result: (code: Int32, message: String)) {
        let content = UNMutableNotificationContent()
        content.title = result.code == 0 ? "计划任务执行成功" : "计划任务执行失败"
        content.body = "\(task.name)：\(result.message.prefix(180))"
        UNUserNotificationCenter.current().add(UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: nil))
    }
}

final class TaskLock {
    private let url: URL
    private var descriptor: Int32 = -1

    init(task: SchedulerTask) {
        url = AppPaths.locks.appendingPathComponent("\(task.id.uuidString).lock")
    }

    func acquire(terminatePrevious: Bool) -> Bool {
        try? AppPaths.prepare()
        if terminatePrevious, let pid = try? String(contentsOf: url, encoding: .utf8), let value = Int32(pid) {
            kill(value, SIGTERM)
            try? AppPaths.fileManager.removeItem(at: url)
        }
        descriptor = open(url.path, O_CREAT | O_EXCL | O_WRONLY, S_IRUSR | S_IWUSR)
        guard descriptor >= 0 else { return false }
        let pid = "\(getpid())"
        _ = pid.withCString { write(descriptor, $0, strlen($0)) };return true
    }

    func release() {
        if descriptor >= 0 { close(descriptor) }
        try? AppPaths.fileManager.removeItem(at: url)
    }
}
