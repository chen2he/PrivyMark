//
//  SharedInbox.swift
//  PrivyMark
//
//  App Group inbox for the Share Extension handoff (PRD §7.7):
//  the extension writes the shared image here; the main app picks it up
//  on launch/foreground and deletes it immediately.
//

import Foundation

nonisolated enum SharedInbox {
    static let appGroupID = "group.jiamin.chen.PrivyMark"
    static let urlScheme = "privymark"

    static var inboxDirectory: URL? {
        FileManager.default
            .containerURL(forSecurityApplicationGroupIdentifier: appGroupID)?
            .appendingPathComponent("Inbox", isDirectory: true)
    }

    /// Writes image data into the inbox (called from the Share Extension).
    @discardableResult
    static func deposit(_ data: Data, fileExtension: String) -> Bool {
        guard let dir = inboxDirectory else { return false }
        do {
            try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
            let url = dir.appendingPathComponent(UUID().uuidString)
                .appendingPathExtension(fileExtension)
            try data.write(to: url, options: .atomic)
            return true
        } catch {
            return false
        }
    }

    /// Returns the newest deposited image and clears the inbox.
    /// PRD §8.1: no copies are retained — files are deleted as soon as read.
    static func takeLatest() -> Data? {
        guard let dir = inboxDirectory,
              let files = try? FileManager.default.contentsOfDirectory(
                at: dir, includingPropertiesForKeys: [.contentModificationDateKey])
        else { return nil }

        let sorted = files.sorted { lhs, rhs in
            let l = (try? lhs.resourceValues(forKeys: [.contentModificationDateKey]))?
                .contentModificationDate ?? .distantPast
            let r = (try? rhs.resourceValues(forKeys: [.contentModificationDateKey]))?
                .contentModificationDate ?? .distantPast
            return l > r
        }
        let data = sorted.first.flatMap { try? Data(contentsOf: $0) }
        for file in files { try? FileManager.default.removeItem(at: file) }
        return data
    }
}
