//
//  TaskLock.swift
//  JobsScheduler
//
//  Created by Jobs on 2026年7月22日，星期三.
//

import Darwin
import Foundation

final class TaskLock {
    private struct Owner {
        let runnerPID: Int32
        let childPID: Int32?
    }

    private let url: URL
    private var descriptor: Int32 = -1

    convenience init(task: SchedulerTask) {
        self.init(url: AppPaths.locks.appendingPathComponent("\(task.id.uuidString).lock"))
    }

    init(url: URL) {
        self.url = url
    }

    func acquire(terminatePrevious: Bool) -> Bool {
        try? AppPaths.prepare()
        descriptor = open(url.path, O_CREAT | O_RDWR, S_IRUSR | S_IWUSR)
        guard descriptor >= 0 else { return false }
        if flock(descriptor, LOCK_EX | LOCK_NB) == 0 {
            writeOwner(childPID: nil)
            return true
        }
        guard terminatePrevious else {
            closeDescriptor()
            return false
        };return terminateRunningChildAndRetry()
    }

    func recordChildProcess(_ pid: Int32) {
        guard descriptor >= 0 else { return }
        writeOwner(childPID: pid)
    }

    func release() {
        guard descriptor >= 0 else { return }
        _ = flock(descriptor, LOCK_UN)
        closeDescriptor()
    }

    private func terminateRunningChildAndRetry() -> Bool {
        let deadline = Date().addingTimeInterval(5)
        var signaledPID: Int32?
        while Date() < deadline {
            if flock(descriptor, LOCK_EX | LOCK_NB) == 0 {
                writeOwner(childPID: nil)
                return true
            }
            if let childPID = readOwner()?.childPID, childPID > 0, childPID != signaledPID {
                _ = kill(childPID, SIGTERM)
                signaledPID = childPID
            }
            usleep(100_000)
        }
        closeDescriptor()
        return false
    }

    private func writeOwner(childPID: Int32?) {
        let value = "\(getpid()) \(childPID ?? 0)\n"
        _ = ftruncate(descriptor, 0)
        _ = lseek(descriptor, 0, SEEK_SET)
        _ = value.withCString { write(descriptor, $0, strlen($0)) }
        _ = fsync(descriptor)
    }

    private func readOwner() -> Owner? {
        guard let value = try? String(contentsOf: url, encoding: .utf8) else { return nil }
        let components = value.split(whereSeparator: \.isWhitespace)
        guard let first = components.first, let runnerPID = Int32(first) else { return nil }
        let childPID = components.count > 1 ? Int32(components[1]) : nil
        return Owner(runnerPID: runnerPID, childPID: childPID == 0 ? nil : childPID)
    }

    private func closeDescriptor() {
        guard descriptor >= 0 else { return }
        _ = close(descriptor)
        descriptor = -1
    }
}
