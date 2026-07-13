//
//  StatusMenuView.swift
//  JobsScheduler
//
//  Created by Jobs on 2026年7月13日，星期一.
//

import AppKit
import SwiftUI

struct StatusMenuView: View {
    @EnvironmentObject private var store: TaskStore

    var body: some View {
        Button("打开任务中心") { openMainWindow() }
        Button("新建计划任务") {
            openMainWindow()
            NotificationCenter.default.post(name: .newSchedulerTask, object: nil)
        }
        Divider()
        Button("查看日志目录") {
            try? AppPaths.prepare()
            NSWorkspace.shared.open(AppPaths.logs)
        }
        Button("用户偏好") {
            openMainWindow()
            NotificationCenter.default.post(name: .showSchedulerPreferences, object: nil)
        }
        Divider()
        Button("退出 UI") { NSApp.terminate(nil) }
    }

    private func openMainWindow() {
        NSApp.activate(ignoringOtherApps: true)
        if let window = NSApp.windows.first(where: { $0.canBecomeMain && $0.title.contains("Jobs") }) ?? NSApp.windows.first(where: \.canBecomeMain) {
            window.makeKeyAndOrderFront(nil)
        }
    }
}
