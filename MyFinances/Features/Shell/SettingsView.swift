import SwiftUI
import SwiftData
import AppKit
import UniformTypeIdentifiers

struct SettingsView: View {
    @Environment(\.modelContext) private var context
    @Query private var settingsRows: [AppSettings]

    @State private var launchAtLogin = LaunchAtLoginService.isEnabled
    @State private var status: String?
    @AppStorage("tranquil.showInDock") private var showInDock = false

    private var settings: AppSettings? { settingsRows.first }

    var body: some View {
        TabView {
            general.tabItem { Label("General", systemImage: "gearshape") }
            notifications.tabItem { Label("Notifications", systemImage: "bell") }
            data.tabItem { Label("Data", systemImage: "externaldrive") }
            security.tabItem { Label("Security", systemImage: "touchid") }
            privacy.tabItem { Label("Privacy", systemImage: "lock") }
        }
        .frame(width: 500, height: 420)
    }

    private var general: some View {
        Form {
            Toggle("Open at login", isOn: $launchAtLogin)
                .onChange(of: launchAtLogin) { _, newValue in
                    LaunchAtLoginService.setEnabled(newValue)
                    launchAtLogin = LaunchAtLoginService.isEnabled
                }
            Text(LaunchAtLoginService.statusDescription)
                .font(Theme.Font.caption).foregroundStyle(.secondary)

            Toggle("Show in the Dock", isOn: $showInDock)
                .onChange(of: showInDock) { _, newValue in
                    NSApp.setActivationPolicy(newValue ? .regular : .accessory)
                }
            Text("Tranquil normally lives only in the menu bar. Press ⌥⌘E to capture from "
                 + "anywhere.")
                .font(Theme.Font.caption).foregroundStyle(.secondary)

            if let settings {
                Divider()
                LabeledContent("Currency", value: settings.currencyCode)
                LabeledContent("Week starts", value: settings.weekStartsOn == 2 ? "Monday" : "Sunday")
                LabeledContent("Day starts at", value: "\(settings.financialDayStartsAtHour):00")
                Text("A late-night spend before this hour counts towards the previous day.")
                    .font(Theme.Font.caption).foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
    }

    @ViewBuilder
    private var notifications: some View {
        if let settings {
            Form {
                Toggle("Send reminders", isOn: Binding(
                    get: { settings.notificationsEnabled },
                    set: { settings.notificationsEnabled = $0; try? context.save() }
                ))
                Stepper(
                    "At most \(settings.maxNotificationsPerDay) a day",
                    value: Binding(
                        get: { settings.maxNotificationsPerDay },
                        set: { settings.maxNotificationsPerDay = $0; try? context.save() }
                    ),
                    in: 1...8
                )
                Text("A muted app is a dead app. The cap is enforced centrally, and quiet "
                     + "hours are absolute.")
                    .font(Theme.Font.caption).foregroundStyle(.secondary)

                Divider()
                LabeledContent("Quiet hours",
                               value: "\(settings.quietHoursStartHour):00 – "
                                    + "\(settings.quietHoursEndHour):00")
            }
            .formStyle(.grouped)
        }
    }

    // MARK: - Data

    @ViewBuilder
    private var data: some View {
        Form {
            Section("Backup") {
                LabeledContent("Folder", value: backupFolderName)
                Button("Choose a backup folder…", action: chooseBackupFolder)
                Button("Back up now", action: backupNow)
                    .disabled(backupFolder == nil)
                if let settings {
                    Toggle("Back up automatically each week", isOn: Binding(
                        get: { settings.automaticWeeklyBackup },
                        set: { settings.automaticWeeklyBackup = $0; try? context.save() }
                    ))
                }
                Text("The last \(BackupService.keepCount) backups are kept. A backup is a copy "
                     + "of the database in a folder you chose — there is no service involved.")
                    .font(Theme.Font.caption).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Section("Export") {
                Button("Export transactions as CSV…") { export(.csv) }
                Button("Export everything as JSON…") { export(.json) }
            }

            Section("Import") {
                Button("Import a CSV…", action: importCSV)
                Text("You choose which column is which. Rows that cannot be read are skipped "
                     + "and listed, never guessed at.")
                    .font(Theme.Font.caption).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            if let status { Text(status).font(Theme.Font.caption).foregroundStyle(.secondary) }
        }
        .formStyle(.grouped)
    }

    // MARK: - Security

    @ViewBuilder
    private var security: some View {
        Form {
            if let settings {
                if AppLockService.shared.isAvailable {
                    Toggle("Lock on launch", isOn: Binding(
                        get: { settings.requireUnlockOnLaunch },
                        set: { settings.requireUnlockOnLaunch = $0; try? context.save() }
                    ))
                    Toggle("Lock when the Mac wakes", isOn: Binding(
                        get: { settings.requireUnlockOnWake },
                        set: { settings.requireUnlockOnWake = $0; try? context.save() }
                    ))
                    Text("Unlocks with \(AppLockService.shared.biometryDescription). "
                         + "Authentication is handled by macOS — the app never sees your "
                         + "password or fingerprint.")
                        .font(Theme.Font.caption).foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                } else {
                    Text("This Mac cannot authenticate, so the lock is unavailable.")
                        .font(Theme.Font.caption).foregroundStyle(.secondary)
                }
            }
        }
        .formStyle(.grouped)
    }

    // MARK: - Actions

    private var backupFolder: URL? {
        guard let data = settings?.backupFolderBookmark else { return nil }
        var isStale = false
        return try? URL(resolvingBookmarkData: data, options: [.withSecurityScope],
                        relativeTo: nil, bookmarkDataIsStale: &isStale)
    }

    private var backupFolderName: String {
        backupFolder?.lastPathComponent ?? "Not chosen"
    }

    private func chooseBackupFolder() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.prompt = "Choose"
        guard panel.runModal() == .OK, let url = panel.url, let settings else { return }
        settings.backupFolderBookmark = try? url.bookmarkData(
            options: [.withSecurityScope], includingResourceValuesForKeys: nil, relativeTo: nil
        )
        try? context.save()
        status = "Backups will be kept in \(url.lastPathComponent)."
    }

    private func backupNow() {
        guard let folder = backupFolder else {
            status = BackupService.BackupError.noFolderChosen.localizedDescription
            return
        }
        let accessed = folder.startAccessingSecurityScopedResource()
        defer { if accessed { folder.stopAccessingSecurityScopedResource() } }
        do {
            let url = try BackupService.backup(to: folder)
            status = "Backed up to \(url.lastPathComponent)."
        } catch {
            status = error.localizedDescription
        }
    }

    private enum ExportFormat { case csv, json }

    private func export(_ format: ExportFormat) {
        guard let settings else { return }
        let panel = NSSavePanel()
        panel.nameFieldStringValue = format == .csv ? "tranquil-transactions.csv"
                                                    : "tranquil-export.json"
        panel.allowedContentTypes = [format == .csv ? UTType.commaSeparatedText : UTType.json]
        guard panel.runModal() == .OK, let url = panel.url else { return }

        do {
            let transactions = try context.fetch(
                FetchDescriptor<Transaction>(predicate: #Predicate { $0.deletedAt == nil })
            )
            switch format {
            case .csv:
                let text = ExportService.exportTransactions(
                    transactions, formatter: settings.formatter, calendar: settings.calendar
                )
                try text.write(to: url, atomically: true, encoding: .utf8)
                status = "Exported \(transactions.count) transactions."
            case .json:
                let data = try ExportService.exportJSON(
                    accounts: try context.fetch(FetchDescriptor<Account>()),
                    transactions: transactions,
                    categories: try context.fetch(FetchDescriptor<MyFinances.Category>()),
                    loans: try context.fetch(FetchDescriptor<Loan>()),
                    goals: try context.fetch(FetchDescriptor<Goal>()),
                    calendar: settings.calendar
                )
                try data.write(to: url)
                status = "Exported everything as JSON."
            }
        } catch {
            status = error.localizedDescription
        }
    }

    private func importCSV() {
        guard let settings else { return }
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.commaSeparatedText, .text]
        panel.canChooseDirectories = false
        guard panel.runModal() == .OK, let url = panel.url,
              let text = try? String(contentsOf: url, encoding: .utf8) else { return }

        let rows = ExportService.parseCSV(text)
        guard let headers = rows.first else {
            status = "That file is empty."
            return
        }
        let mapping = ExportService.suggestMapping(headers: headers)
        let result = ExportService.parseRows(rows, mapping: mapping, hasHeader: true,
                                             formatter: settings.formatter,
                                             calendar: settings.calendar)
        guard !result.rows.isEmpty else {
            status = result.skipped.first ?? "Nothing in that file could be read."
            return
        }

        let accounts = (try? context.fetch(FetchDescriptor<Account>())) ?? []
        let categories = (try? context.fetch(FetchDescriptor<MyFinances.Category>())) ?? []
        for row in result.rows {
            let account = row.accountName.flatMap { name in
                accounts.first { $0.name.caseInsensitiveCompare(name) == .orderedSame }
            } ?? accounts.first
            let category = row.categoryName.flatMap { name in
                categories.first { $0.name.caseInsensitiveCompare(name) == .orderedSame }
            }
            context.insert(Transaction(
                date: row.date, amount: row.amount, kind: row.kind,
                account: account, category: category, note: row.note,
                // Imported rows are estimates until reviewed.
                isEstimate: true
            ))
        }
        try? context.save()
        status = "Imported \(result.rows.count) rows"
            + (result.skipped.isEmpty ? "." : ", skipped \(result.skipped.count).")
    }

    private var privacy: some View {
        Form {
            VStack(alignment: .leading, spacing: Theme.Space.sm) {
                Label("No network access, ever", systemImage: "wifi.slash")
                    .font(Theme.Font.title)
                Text("""
                     Tranquil makes no network calls of any kind. There are no accounts, no \
                     sync, no telemetry, no analytics, no crash reporting, and no bank \
                     connections. Your data is a single local database on this Mac, and \
                     notifications are scheduled by macOS on-device.

                     Nothing here is ever sent anywhere.
                     """)
                    .font(Theme.Font.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(.vertical, Theme.Space.xs)
        }
        .formStyle(.grouped)
    }
}
