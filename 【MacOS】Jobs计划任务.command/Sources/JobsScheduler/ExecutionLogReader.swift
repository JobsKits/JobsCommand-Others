//
//  ExecutionLogReader.swift
//  JobsScheduler
//
//  Created by Jobs on 2026年7月19日，星期日.
//

import Foundation

actor ExecutionLogReader {
    enum ReadResult: Sendable {
        case unchanged
        case loaded(String)
        case missing
        case failed(String)
    }

    private struct FileSignature: Equatable, Sendable {
        let size: Int
        let modificationDate: Date?
    }

    private var loadedSignatures: [UUID: FileSignature] = [:]

    func taskIDsWithLogs(_ logFiles: [UUID: URL]) -> Set<UUID> {
        guard !Task.isCancelled else { return [] };return Set<UUID>(logFiles.compactMap { taskID, url in
            guard !Task.isCancelled else { return nil }
            let values = try? url.resourceValues(forKeys: [.fileSizeKey])
            return (values?.fileSize ?? 0) > 0 ? taskID : nil
        })
    }

    func read(taskID: UUID, from url: URL, force: Bool) -> ReadResult {
        guard !Task.isCancelled else { return .unchanged }
        guard FileManager.default.fileExists(atPath: url.path) else {
            loadedSignatures.removeValue(forKey: taskID)
            return .missing
        }
        do {
            let values = try url.resourceValues(forKeys: [.contentModificationDateKey, .fileSizeKey])
            let signature = FileSignature(
                size: values.fileSize ?? 0,
                modificationDate: values.contentModificationDate
            )
            guard signature.size > 0 else {
                loadedSignatures.removeValue(forKey: taskID)
                return .missing
            }
            guard force || loadedSignatures[taskID] != signature else { return .unchanged }
            guard !Task.isCancelled else { return .unchanged }
            let text = try String(contentsOf: url, encoding: .utf8)
            guard !Task.isCancelled else { return .unchanged }
            let sanitizedText = ANSITextSanitizer.clean(text)
            guard !Task.isCancelled else { return .unchanged }
            loadedSignatures[taskID] = signature
            return .loaded(sanitizedText)
        } catch {
            return .failed(error.localizedDescription)
        }
    }
}
