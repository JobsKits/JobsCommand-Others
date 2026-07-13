//
//  JobsSchedulerApp.swift
//  JobsScheduler
//
//  Created by Jobs on 2026年7月13日，星期一.
//

import AppKit
import SwiftUI
import UserNotifications

@main
struct JobsSchedulerApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @StateObject private var store = TaskStore.shared

    var body: some Scene {
        WindowGroup("Jobs 计划任务") {
            ContentView()
                .environmentObject(store)
                .frame(minWidth: 980, minHeight: 620)
        }
        .commands {
            CommandGroup(replacing: .newItem) {
                Button("新建计划任务") {
                    NotificationCenter.default.post(name: .newSchedulerTask, object: nil)
                }
                .keyboardShortcut("n")
            }
        }
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, NSWindowDelegate {
    private var statusItem: NSStatusItem?
    private var isQuitting = false

    func applicationDidFinishLaunching(_ notification: Notification) {
        if let index = CommandLine.arguments.firstIndex(of: "--run-task"), CommandLine.arguments.indices.contains(index + 1), let id = UUID(uuidString: CommandLine.arguments[index + 1]) {
            NSApp.setActivationPolicy(.prohibited)
            Task {
                await TaskRunner.run(taskID: id)
                NSApp.terminate(nil)
            };return
        }
        NSApp.setActivationPolicy(.accessory)
        configureStatusItem()
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { _, _ in }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) {
            NSApp.windows.forEach { $0.delegate = self }
        }
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { false }

    func windowShouldClose(_ sender: NSWindow) -> Bool {
        if isQuitting { return true }
        let behavior = TaskStore.shared.preferences.closeBehavior
        if behavior == "hide" {
            sender.orderOut(nil)
            return false
        }
        if behavior == "quit" {
            isQuitting = true
            NSApp.terminate(nil)
            return true
        }
        let alert = NSAlert()
        alert.messageText = "关闭 Jobs 计划任务？"
        alert.informativeText = "关闭窗口后可以继续驻留菜单栏，也可以退出 UI。已经注册的计划任务仍由 launchd 执行。"
        alert.addButton(withTitle: "最小化到菜单栏")
        alert.addButton(withTitle: "退出 UI")
        alert.addButton(withTitle: "取消")
        switch alert.runModal() {
        case .alertFirstButtonReturn:
            sender.orderOut(nil)
            return false
        case .alertSecondButtonReturn:
            isQuitting = true
            NSApp.terminate(nil)
            return true
        default:
            return false
        }
    }

    private func configureStatusItem() {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        item.button?.image = NSImage(systemSymbolName: "calendar.badge.clock", accessibilityDescription: "Jobs 计划任务")
        let menu = NSMenu()
        let openItem = menu.addItem(withTitle: "打开任务中心", action: #selector(openMainWindow), keyEquivalent: "")
        openItem.target = self
        let createItem = menu.addItem(withTitle: "新建计划任务", action: #selector(createTask), keyEquivalent: "")
        createItem.target = self
        menu.addItem(.separator())
        let logsItem = menu.addItem(withTitle: "查看日志目录", action: #selector(openLogs), keyEquivalent: "")
        logsItem.target = self
        let preferencesItem = menu.addItem(withTitle: "用户偏好", action: #selector(openPreferences), keyEquivalent: ",")
        preferencesItem.target = self
        menu.addItem(.separator())
        let quitItem = menu.addItem(withTitle: "退出 UI", action: #selector(quit), keyEquivalent: "q")
        quitItem.target = self
        item.menu = menu
        statusItem = item
    }

    @objc private func openMainWindow() {
        NSApp.activate(ignoringOtherApps: true)
        if let window = NSApp.windows.first {
            window.delegate = self
            window.makeKeyAndOrderFront(nil)
        }
    }

    @objc private func createTask() {
        openMainWindow()
        NotificationCenter.default.post(name: .newSchedulerTask, object: nil)
    }

    @objc private func openPreferences() {
        openMainWindow()
        NotificationCenter.default.post(name: .showSchedulerPreferences, object: nil)
    }

    @objc private func openLogs() {
        try? AppPaths.prepare()
        NSWorkspace.shared.open(AppPaths.logs)
    }

    @objc private func quit() {
        isQuitting = true
        NSApp.terminate(nil)
    }
}

extension Notification.Name {
    static let newSchedulerTask = Notification.Name("JobsScheduler.newTask")
    static let showSchedulerPreferences = Notification.Name("JobsScheduler.showPreferences")
}
