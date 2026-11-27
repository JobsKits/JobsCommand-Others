//
//  TaskStoreTests.swift
//  JobsSchedulerTests
//
//  Created by Jobs on 2026年7月28日，星期二.
//

import Testing
@testable import JobsScheduler

struct TaskStoreTests {
    @Test @MainActor func staleRunningStateBecomesInterruptedWhenNoLockIsHeld() {
        var task = SchedulerTask()
        task.lastExitCode = nil
        task.lastMessage = "正在执行…"

        let reconciledTask = TaskStore.reconcilingInterruptedExecution(task) { _ in false }

        #expect(reconciledTask.lastExitCode == -2)
        #expect(reconciledTask.lastMessage == "上次执行进程已结束，但未能记录退出结果")
    }

    @Test @MainActor func runningStateRemainsWhileLockIsHeld() {
        var task = SchedulerTask()
        task.lastExitCode = nil
        task.lastMessage = "正在执行…"

        let reconciledTask = TaskStore.reconcilingInterruptedExecution(task) { _ in true }

        #expect(reconciledTask == task)
    }
}
