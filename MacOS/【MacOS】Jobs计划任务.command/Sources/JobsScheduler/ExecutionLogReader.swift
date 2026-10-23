//
//  ExecutionLogReader.swift
//  JobsScheduler
//
//  Created by Jobs on 2026年7月19日，星期日.
//

import Foundation

actor ExecutionLogReader {
    nonisolated static let tailLineLimit = 2_000
    nonisolated static let tailByteLimit = 1_048_576

    struct Snapshot: Sendable {
        let text: String
        let isTruncated: Bool
        let fileSize: Int
    }

    enum ReadResult: Sendable {
        case unchanged
        case loaded(Snapshot)
        case missing
        case failed(String)
    }

    private struct FileSignature: Equatable, Sendable {
        let size: Int
        let modificationDate: Date?
    }

    private struct LoadedState: Sendable {
        let signature: FileSignature
        let snapshot: Snapshot
        let loadsFullLog: Bool
    }

    private var loadedStates: [UUID: LoadedState] = [:]

    func taskIDsWithLogs(_ logFiles: [UUID: URL]) -> Set<UUID> {
        guard !Task.isCancelled else { return [] };return Set<UUID>(logFiles.compactMap { taskID, url in
            guard !Task.isCancelled else { return nil }
            let attributes = try? FileManager.default.attributesOfItem(atPath: url.path)
            let fileSize = (attributes?[.size] as? NSNumber)?.intValue ?? 0
            return fileSize > 0 ? taskID : nil
        })
    }

    func read(taskID: UUID, from url: URL, force: Bool, loadAll: Bool = false) -> ReadResult {
        guard !Task.isCancelled else { return .unchanged }
        guard FileManager.default.fileExists(atPath: url.path) else {
            loadedStates.removeValue(forKey: taskID)
            return .missing
        }
        do {
            let signature = try fileSignature(for: url)
            guard signature.size > 0 else {
                loadedStates.removeValue(forKey: taskID)
                return .missing
            }
            if let state = loadedStates[taskID], state.loadsFullLog == loadAll {
                if state.signature == signature {
                    return force ? .loaded(state.snapshot) : .unchanged
                }
                if let updatedState = try incrementallyUpdatedState(from: state, signature: signature, url: url) {
                    loadedStates[taskID] = updatedState
                    return .loaded(updatedState.snapshot)
                }
            }
            guard !Task.isCancelled else { return .unchanged }
            let state = try loadState(signature: signature, from: url, loadAll: loadAll)
            guard !Task.isCancelled else { return .unchanged }
            loadedStates[taskID] = state
            return .loaded(state.snapshot)
        } catch {
            return .failed(error.localizedDescription)
        }
    }

    func reset() {
        loadedStates.removeAll()
    }

    private func fileSignature(for url: URL) throws -> FileSignature {
        let attributes = try FileManager.default.attributesOfItem(atPath: url.path)
        let size = (attributes[.size] as? NSNumber)?.intValue ?? 0
        let modificationDate = attributes[.modificationDate] as? Date
        return FileSignature(size: size, modificationDate: modificationDate)
    }

    private func incrementallyUpdatedState(from state: LoadedState, signature: FileSignature, url: URL) throws -> LoadedState? {
        guard signature.size > state.signature.size else { return nil }
        let appendedByteCount = signature.size - state.signature.size
        guard state.loadsFullLog || appendedByteCount <= Self.tailByteLimit else { return nil }
        guard state.loadsFullLog || state.snapshot.text.utf8.count + appendedByteCount <= Self.tailByteLimit else { return nil }
        let appendedText = try readText(from: url, offset: state.signature.size)
        guard !Task.isCancelled else { return nil }
        let sanitizedText = ANSITextSanitizer.clean(state.snapshot.text + appendedText)
        let limited = state.loadsFullLog ? (sanitizedText, false) : limitTailLines(in: sanitizedText)
        let snapshot = Snapshot(
            text: limited.0,
            isTruncated: state.snapshot.isTruncated || limited.1,
            fileSize: signature.size
        )
        return LoadedState(signature: signature, snapshot: snapshot, loadsFullLog: state.loadsFullLog)
    }

    private func loadState(signature: FileSignature, from url: URL, loadAll: Bool) throws -> LoadedState {
        let offset = loadAll ? 0 : max(signature.size - Self.tailByteLimit, 0)
        var text = try readText(from: url, offset: offset)
        var truncated = offset > 0
        if offset > 0, let firstLineBreak = text.firstIndex(of: "\n") {
            text.removeSubrange(...firstLineBreak)
        }
        text = ANSITextSanitizer.clean(text)
        if !loadAll {
            let limited = limitTailLines(in: text)
            text = limited.0
            truncated = truncated || limited.1
        }
        let snapshot = Snapshot(text: text, isTruncated: truncated, fileSize: signature.size)
        return LoadedState(signature: signature, snapshot: snapshot, loadsFullLog: loadAll)
    }

    private func readText(from url: URL, offset: Int) throws -> String {
        let handle = try FileHandle(forReadingFrom: url)
        defer { try? handle.close() }
        try handle.seek(toOffset: UInt64(max(offset, 0)))
        let data = try handle.readToEnd() ?? Data()
        return String(decoding: data, as: UTF8.self)
    }

    private func limitTailLines(in text: String) -> (String, Bool) {
        var index = text.endIndex
        var lineBreakCount = 0
        while index > text.startIndex {
            index = text.index(before: index)
            guard text[index] == "\n" else { continue }
            lineBreakCount += 1
            if lineBreakCount > Self.tailLineLimit {
                return (String(text[text.index(after: index)...]), true)
            }
        };return (text, false)
    }
}
