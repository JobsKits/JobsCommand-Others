//
//  LaunchdManager.swift
//  JobsScheduler
//
//  Created by Jobs on 2026年7月13日，星期一.
//

import Foundation

enum LaunchdManager {
    static func register(_ task: SchedulerTask) throws {
        guard let executable = Bundle.main.executablePath else {
            throw NSError(domain: "JobsScheduler", code: 1, userInfo: [NSLocalizedDescriptionKey: "找不到 App 可执行文件"])
        }
        try AppPaths.prepare()
        unregister(task)
        var plist: [String: Any] = [
            "Label": task.label,
            "ProgramArguments": [executable, "--run-task", task.id.uuidString],
            "ProcessType": "Background",
            "StandardOutPath": AppPaths.log(for: task).path,
            "StandardErrorPath": AppPaths.log(for: task).path
        ]
        applySchedule(task, to: &plist)
        let data = try PropertyListSerialization.data(fromPropertyList: plist, format: .xml, options: 0)
        try data.write(to: AppPaths.plist(for: task), options: .atomic)
        let result = runLaunchctl(["bootstrap", "gui/\(getuid())", AppPaths.plist(for: task).path])
        if result != 0 {
            throw NSError(domain: "JobsScheduler", code: Int(result), userInfo: [NSLocalizedDescriptionKey: "launchd 注册失败，退出码：\(result)"])
        }
    }

    static func unregister(_ task: SchedulerTask) {
        let url = AppPaths.plist(for: task)
        _ = runLaunchctl(["bootout", "gui/\(getuid())", url.path])
        try? AppPaths.fileManager.removeItem(at: url)
    }

    static func runNow(_ task: SchedulerTask) {
        Task.detached {
            await TaskRunner.run(taskID: task.id, ignoreMissed: true)
        }
    }

    private static func applySchedule(_ task: SchedulerTask, to plist: inout [String: Any]) {
        let components = Calendar.current.dateComponents([.month, .day, .hour, .minute], from: task.fireDate)
        switch task.schedule {
        case .once:
            plist["StartCalendarInterval"] = [
                "Month": components.month ?? 1,
                "Day": components.day ?? 1,
                "Hour": components.hour ?? 0,
                "Minute": components.minute ?? 0
            ]
        case .daily:
            plist["StartCalendarInterval"] = ["Hour": components.hour ?? 0, "Minute": components.minute ?? 0]
        case .weekly:
            plist["StartCalendarInterval"] = [
                "Weekday": task.weekday,
                "Hour": components.hour ?? 0,
                "Minute": components.minute ?? 0
            ]
        case .interval:
            plist["StartInterval"] = max(task.intervalMinutes, 1) * 60
        case .login:
            plist["RunAtLoad"] = true
        }
    }

    @discardableResult
    private static func runLaunchctl(_ arguments: [String]) -> Int32 {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/launchctl")
        process.arguments = arguments
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        do {
            try process.run()
            process.waitUntilExit()
            return process.terminationStatus
        } catch {
            return -1
        }
    }
}
