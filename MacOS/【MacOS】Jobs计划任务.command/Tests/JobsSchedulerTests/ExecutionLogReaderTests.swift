//
//  ExecutionLogReaderTests.swift
//  JobsSchedulerTests
//
//  Created by Jobs on 2026年7月22日，星期三.
//

import Foundation
import Testing
@testable import JobsScheduler

struct ExecutionLogReaderTests {
    @Test func tailReadLimitsLinesAndAppendsIncrementally() async throws {
        let directory = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let logURL = directory.appendingPathComponent("task.log")
        let originalText = (0..<2_105).map { String(format: "line-%04d", $0) }.joined(separator: "\n") + "\n"
        try originalText.write(to: logURL, atomically: true, encoding: .utf8)

        let reader = ExecutionLogReader()
        let taskID = UUID()
        let firstResult = await reader.read(taskID: taskID, from: logURL, force: true)
        let firstSnapshot = try loadedSnapshot(from: firstResult)
        #expect(firstSnapshot.isTruncated)
        #expect(!firstSnapshot.text.contains("line-0000"))
        #expect(firstSnapshot.text.contains("line-2104"))
        #expect(firstSnapshot.text.split(whereSeparator: \.isNewline).count <= ExecutionLogReader.tailLineLimit)

        let handle = try FileHandle(forWritingTo: logURL)
        try handle.seekToEnd()
        try handle.write(contentsOf: Data("line-2105\n".utf8))
        try handle.close()

        let updatedResult = await reader.read(taskID: taskID, from: logURL, force: false)
        let updatedSnapshot = try loadedSnapshot(from: updatedResult)
        #expect(updatedSnapshot.isTruncated)
        #expect(updatedSnapshot.text.contains("line-2105"))
    }

    @Test func fullReadKeepsBeginningAndEnd() async throws {
        let directory = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let logURL = directory.appendingPathComponent("task.log")
        let text = (0..<2_105).map { String(format: "line-%04d", $0) }.joined(separator: "\n")
        try text.write(to: logURL, atomically: true, encoding: .utf8)

        let reader = ExecutionLogReader()
        let result = await reader.read(taskID: UUID(), from: logURL, force: true, loadAll: true)
        let snapshot = try loadedSnapshot(from: result)
        #expect(!snapshot.isTruncated)
        #expect(snapshot.text.hasPrefix("line-0000"))
        #expect(snapshot.text.hasSuffix("line-2104"))
    }

    @Test func tailReadLimitsInitialBytes() async throws {
        let directory = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let logURL = directory.appendingPathComponent("task.log")
        let oversizedLine = String(repeating: "A", count: ExecutionLogReader.tailByteLimit + 4_096)
        try (oversizedLine + "\nfinal-line\n").write(to: logURL, atomically: true, encoding: .utf8)

        let reader = ExecutionLogReader()
        let result = await reader.read(taskID: UUID(), from: logURL, force: true)
        let snapshot = try loadedSnapshot(from: result)
        #expect(snapshot.isTruncated)
        #expect(snapshot.text.utf8.count <= ExecutionLogReader.tailByteLimit)
        #expect(snapshot.text.contains("final-line"))
    }

    private func temporaryDirectory() throws -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    private func loadedSnapshot(from result: ExecutionLogReader.ReadResult) throws -> ExecutionLogReader.Snapshot {
        switch result {
        case let .loaded(snapshot):
            return snapshot
        case .unchanged:
            throw NSError(domain: "ExecutionLogReaderTests", code: 1, userInfo: [NSLocalizedDescriptionKey: "日志读取结果意外为 unchanged"])
        case .missing:
            throw NSError(domain: "ExecutionLogReaderTests", code: 2, userInfo: [NSLocalizedDescriptionKey: "日志读取结果意外为 missing"])
        case let .failed(message):
            throw NSError(domain: "ExecutionLogReaderTests", code: 3, userInfo: [NSLocalizedDescriptionKey: message])
        }
    }
}
