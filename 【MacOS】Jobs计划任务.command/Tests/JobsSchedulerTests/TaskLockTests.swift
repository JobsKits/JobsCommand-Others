//
//  TaskLockTests.swift
//  JobsSchedulerTests
//
//  Created by Jobs on 2026年7月22日，星期三.
//

import Darwin
import Foundation
import Testing
@testable import JobsScheduler

struct TaskLockTests {
    @Test func stalePIDFileDoesNotBlockNewOwner() throws {
        let directory = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let lockURL = directory.appendingPathComponent("task.lock")
        try "213\n".write(to: lockURL, atomically: true, encoding: .utf8)

        let lock = TaskLock(url: lockURL)
        #expect(lock.acquire(terminatePrevious: false))
        let owner = try String(contentsOf: lockURL, encoding: .utf8)
        #expect(owner.hasPrefix("\(getpid()) "))
        lock.release()
    }

    @Test func activeOwnerBlocksSecondOwnerUntilRelease() throws {
        let directory = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let lockURL = directory.appendingPathComponent("task.lock")
        let firstLock = TaskLock(url: lockURL)
        let secondLock = TaskLock(url: lockURL)

        #expect(firstLock.acquire(terminatePrevious: false))
        #expect(!secondLock.acquire(terminatePrevious: false))
        firstLock.release()
        #expect(secondLock.acquire(terminatePrevious: false))
        secondLock.release()
    }

    private func temporaryDirectory() throws -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }
}
