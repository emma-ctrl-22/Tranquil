import Foundation
import SwiftData

/// Manual and automatic local backups. A backup is a copy of the store file in a folder
/// the user chose — no service, no account, no upload.
nonisolated enum BackupService {

    static let keepCount = 12

    struct BackupFile: Identifiable, Sendable {
        let url: URL
        let createdAt: Date
        let size: Int

        var id: URL { url }
    }

    /// Where SwiftData put the store.
    static func storeURL() -> URL? {
        let support = FileManager.default.urls(for: .applicationSupportDirectory,
                                               in: .userDomainMask).first
        return support?.appendingPathComponent("default.store")
    }

    static func backupFileName(at date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(identifier: "UTC")
        formatter.dateFormat = "yyyy-MM-dd-HHmmss"
        return "tranquil-\(formatter.string(from: date)).store"
    }

    /// Copies the store, plus SQLite's sidecar files — without the write-ahead log a
    /// copy can be missing the most recent transactions.
    @discardableResult
    static func backup(to folder: URL, now: Date = Date()) throws -> URL {
        guard let store = storeURL() else { throw BackupError.storeNotFound }
        let manager = FileManager.default
        guard manager.fileExists(atPath: store.path) else { throw BackupError.storeNotFound }

        let destination = folder.appendingPathComponent(backupFileName(at: now))
        if manager.fileExists(atPath: destination.path) {
            try manager.removeItem(at: destination)
        }
        try manager.copyItem(at: store, to: destination)

        for suffix in ["-wal", "-shm"] {
            let sidecar = URL(fileURLWithPath: store.path + suffix)
            guard manager.fileExists(atPath: sidecar.path) else { continue }
            let sidecarDestination = URL(fileURLWithPath: destination.path + suffix)
            if manager.fileExists(atPath: sidecarDestination.path) {
                try manager.removeItem(at: sidecarDestination)
            }
            try manager.copyItem(at: sidecar, to: sidecarDestination)
        }

        try prune(in: folder)
        return destination
    }

    static func existingBackups(in folder: URL) throws -> [BackupFile] {
        let manager = FileManager.default
        let contents = try manager.contentsOfDirectory(
            at: folder,
            includingPropertiesForKeys: [.creationDateKey, .fileSizeKey],
            options: [.skipsHiddenFiles]
        )
        return contents
            .filter { $0.lastPathComponent.hasPrefix("tranquil-")
                   && $0.pathExtension == "store" }
            .compactMap { url in
                let values = try? url.resourceValues(forKeys: [.creationDateKey, .fileSizeKey])
                return BackupFile(url: url,
                                  createdAt: values?.creationDate ?? .distantPast,
                                  size: values?.fileSize ?? 0)
            }
            .sorted { $0.createdAt > $1.createdAt }
    }

    /// Keeps the most recent twelve and removes the rest, sidecars included.
    static func prune(in folder: URL) throws {
        let backups = try existingBackups(in: folder)
        guard backups.count > keepCount else { return }
        let manager = FileManager.default
        for backup in backups.dropFirst(keepCount) {
            try? manager.removeItem(at: backup.url)
            for suffix in ["-wal", "-shm"] {
                let sidecar = URL(fileURLWithPath: backup.url.path + suffix)
                try? manager.removeItem(at: sidecar)
            }
        }
    }

    /// True when the last backup is older than a week.
    static func isWeeklyBackupDue(lastBackup: Date?, now: Date,
                                  calendar: FinancialCalendar) -> Bool {
        guard let lastBackup else { return true }
        return calendar.daysBetween(lastBackup, now) >= 7
    }

    enum BackupError: LocalizedError {
        case storeNotFound
        case noFolderChosen

        var errorDescription: String? {
            switch self {
            case .storeNotFound: "The database file could not be found."
            case .noFolderChosen: "Choose a folder to keep backups in first."
            }
        }
    }
}
