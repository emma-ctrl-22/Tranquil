import SwiftUI
import SwiftData
import AppKit
import UniformTypeIdentifiers

struct SettingsView: View {
    @Environment(\.modelContext) private var context
    @Query private var settingsRows: [AppSettings]

    @State private var launchAtLogin = LaunchAtLoginService.isEnabled
    @State private var status: String?
    @AppStorage("tranquil.showInDock") private var showInDock = true

    private var settings: AppSettings? { settingsRows.first }

    @State private var tab: Tab = .money

    enum Tab: String, CaseIterable, Identifiable {
        case money, thresholds, notifications, data, security, general
        var id: String { rawValue }
        var title: String {
            switch self {
            case .money: "Money & time"
            case .thresholds: "Thresholds"
            case .notifications: "Notifications"
            case .data: "Data & backup"
            case .security: "Security"
            case .general: "General"
            }
        }
        var icon: String {
            switch self {
            case .money: "banknote"
            case .thresholds: "slider.horizontal.3"
            case .notifications: "bell"
            case .data: "externaldrive"
            case .security: "lock"
            case .general: "gearshape"
            }
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            Picker("", selection: $tab) {
                ForEach(Tab.allCases) { option in
                    Label(option.title, systemImage: option.icon).tag(option)
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .padding(.horizontal, Theme.Space.lg)
            .padding(.vertical, Theme.Space.sm)

            Divider().opacity(0.5)

            ScrollView {
                content
                    .frame(maxWidth: 620, alignment: .leading)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, Theme.Space.lg)
                    .padding(.vertical, Theme.Space.md)
            }
        }
    }

    @ViewBuilder
    private var content: some View {
        switch tab {
        case .money: money
        case .thresholds: thresholds
        case .notifications: notifications
        case .data: data
        case .security: security
        case .general:
            VStack(alignment: .leading, spacing: Theme.Space.md) {
                general
                privacy
            }
        }
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
                    if newValue { NSApp.activate(ignoringOtherApps: true) }
                }
            Text(showInDock
                 ? "Tranquil behaves like a normal app: a Dock icon you can keep, and a "
                   + "menu bar that reveals when you move the pointer to the top of the "
                   + "screen. The leaf stays in the menu bar either way, and ⌥⌘E still "
                   + "captures from anywhere."
                 : "Tranquil lives only in the menu bar. Note that while it is frontmost it "
                   + "has no menu bar of its own, so if you have the system menu bar set to "
                   + "auto-hide, moving the pointer to the top will reveal nothing.")
                .font(Theme.Font.caption).foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

        }
        .formStyle(.grouped).scrollDisabled(true).frame(minHeight: 240)
    }

    // MARK: - Money and time

    @ViewBuilder
    private var money: some View {
        if let settings {
            Form {
                Section("Currency and calendar") {
                    Picker("Currency", selection: Binding(
                        get: { settings.currencyCode },
                        set: { code in
                            if let currency = Currency.named(code) {
                                settings.applyCurrency(currency)
                                try? context.save()
                            }
                        }
                    )) {
                        ForEach(Currency.known, id: \.code) { currency in
                            Text("\(currency.symbol)  \(currency.code)").tag(currency.code)
                        }
                    }

                    Picker("Week starts on", selection: binding(\.weekStartsOn)) {
                        Text("Monday").tag(2)
                        Text("Sunday").tag(1)
                    }

                    Stepper("Day starts at \(settings.financialDayStartsAtHour):00",
                            value: binding(\.financialDayStartsAtHour), in: 0...12)
                    Text("A spend logged before this hour counts towards the previous day, so a "
                         + "01:00 taxi belongs to the night out, not the morning after.")
                        .font(Theme.Font.caption).foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Section("You") {
                    Stepper("Born \(settings.birthYear) — age \(settings.age)",
                            value: binding(\.birthYear), in: 1930...2020)
                    Picker("Income", selection: Binding(
                        get: { settings.incomeType },
                        set: { settings.incomeType = $0; try? context.save() }
                    )) {
                        Text("Salaried").tag(AppSettings.IncomeType.salaried)
                        Text("Freelance").tag(AppSettings.IncomeType.freelance)
                        Text("Mixed").tag(AppSettings.IncomeType.mixed)
                    }
                    Text("Freelance or mixed income targets a six-month emergency fund instead "
                         + "of three, and applies the tax reserve to untaxed inflows.")
                        .font(Theme.Font.caption).foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)

                    Stepper("Dependents: \(settings.dependents)",
                            value: binding(\.dependents), in: 0...12)
                }

                Section("Regular income") {
                    moneyField("Net pay each month", \.expectedMonthlyNetIncomeMinorUnits)
                    Stepper("Paid on the \(settings.salaryDayOfMonth)",
                            value: binding(\.salaryDayOfMonth), in: 1...31)
                    Text("Spread across the year as "
                         + formatter.string(settings.expectedWeeklyIncomeFromSalary)
                         + " a week, because a monthly salary would otherwise read as zero "
                         + "in three weeks out of four.")
                        .font(Theme.Font.caption).foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .formStyle(.grouped).scrollDisabled(true).frame(minHeight: 240)
        }
    }

    // MARK: - Thresholds

    @ViewBuilder
    private var thresholds: some View {
        if let settings {
            Form {
                Section("Tax and debt") {
                    percentField("Tax reserve on untaxed income", \.taxReserveRateBasisPoints)
                    percentField("High-interest line (APR)",
                                 \.highInterestThresholdAPRBasisPoints)
                    percentField("Debt service cap", \.maxDebtServiceRatioBasisPoints)
                    Text("Above the cap a planned loan reads Not affordable and is blocked. "
                         + "Confirm the tax rate with a local professional once a year.")
                        .font(Theme.Font.caption).foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Section("Safety net") {
                    Stepper("Emergency fund: \(settings.emergencyFundMonths) months",
                            value: binding(\.emergencyFundMonths), in: 1...24)
                    if !settings.emergencyFundMonthsMatchesRecommendation {
                        HStack {
                            Text("\(settings.incomeType == .salaried ? "Salaried" : "Irregular") "
                                 + "income suggests \(settings.recommendedEmergencyFundMonths) "
                                 + "months.")
                                .font(Theme.Font.caption).foregroundStyle(.secondary)
                            Spacer()
                            Button("Use \(settings.recommendedEmergencyFundMonths)") {
                                settings.emergencyFundMonths = settings.recommendedEmergencyFundMonths
                                try? context.save()
                            }
                            .controlSize(.small)
                        }
                    }
                    percentField("Speculation cap of net worth",
                                 \.speculationCapOfNetWorthBasisPoints)
                    percentField("One income source counts as concentrated above",
                                 \.concentrationThresholdBasisPoints)
                }

                Section("Pace and pauses") {
                    percentField("Envelope alert margin", \.burnAlertMarginBasisPoints)
                    percentField("Weight given to a \u{201C}maybe\u{201D} event",
                                 \.maybeEventWeightBasisPoints)
                    percentField("Windfall trigger (x median week)",
                                 \.windfallMultipleBasisPoints)
                    moneyField("Cool-off applies to goals above", \.coolOffThresholdMinorUnits)
                    Stepper("Cool-off: \(settings.goalCoolOffDays) days",
                            value: binding(\.goalCoolOffDays), in: 0...30)
                    moneyField("Show cost-in-time above", \.costInTimeThresholdMinorUnits)
                }

                Section("Ladder stage 6 and scoring") {
                    percentField("Debt service at or under", \.stage6MaxDebtServiceBasisPoints)
                    percentField("No loan above", \.stage6MaxAPRBasisPoints)
                    Stepper("Runway scores full marks at \(settings.runwayFullMarksMonths) months",
                            value: binding(\.runwayFullMarksMonths), in: 1...24)
                    percentField("Debt service scores zero at",
                                 \.debtServiceZeroScoreBasisPoints)
                }

                Button("Reset thresholds to defaults", action: resetThresholds)
            }
            .formStyle(.grouped).scrollDisabled(true).frame(minHeight: 240)
        }
    }

    // MARK: - Field helpers

    private var formatter: MoneyFormatter {
        settings?.formatter ?? MoneyFormatter(currency: .ghs)
    }

    private func binding<Value>(_ keyPath: ReferenceWritableKeyPath<AppSettings, Value>)
    -> Binding<Value> {
        Binding(
            get: { settings?[keyPath: keyPath] ?? placeholder[keyPath: keyPath] },
            set: { settings?[keyPath: keyPath] = $0; try? context.save() }
        )
    }

    /// A stand-in so the bindings have something to read before setup has run.
    private var placeholder: AppSettings { AppSettings() }

    /// Basis points edited as a plain percentage.
    private func percentField(
        _ label: String, _ keyPath: ReferenceWritableKeyPath<AppSettings, Int>
    ) -> some View {
        let value = Binding<Double>(
            get: { Double(settings?[keyPath: keyPath] ?? 0) / 100 },
            set: {
                settings?[keyPath: keyPath] = Int(($0 * 100).rounded())
                try? context.save()
            }
        )
        return HStack {
            Text(label)
            Spacer()
            TextField("", value: value, format: .number.precision(.fractionLength(0...2)))
                .textFieldStyle(.roundedBorder)
                .multilineTextAlignment(.trailing)
                .frame(width: 72)
            Text("%").foregroundStyle(.secondary)
        }
    }

    private func moneyField(
        _ label: String, _ keyPath: ReferenceWritableKeyPath<AppSettings, Int>
    ) -> some View {
        let text = Binding<String>(
            get: {
                formatter.string(Money(minorUnits: settings?[keyPath: keyPath] ?? 0),
                                 style: .bare)
            },
            set: {
                if let parsed = formatter.parse($0) {
                    settings?[keyPath: keyPath] = parsed.minorUnits
                    try? context.save()
                }
            }
        )
        return HStack {
            Text(label)
            Spacer()
            Text(formatter.currency.symbol).foregroundStyle(.secondary)
            TextField("", text: text)
                .textFieldStyle(.roundedBorder)
                .multilineTextAlignment(.trailing)
                .frame(width: 96)
        }
    }

    private func resetThresholds() {
        guard let settings else { return }
        let defaults = AppSettings()
        settings.taxReserveRateBasisPoints = defaults.taxReserveRateBasisPoints
        settings.highInterestThresholdAPRBasisPoints = defaults.highInterestThresholdAPRBasisPoints
        settings.maxDebtServiceRatioBasisPoints = defaults.maxDebtServiceRatioBasisPoints
        settings.speculationCapOfNetWorthBasisPoints = defaults.speculationCapOfNetWorthBasisPoints
        settings.concentrationThresholdBasisPoints = defaults.concentrationThresholdBasisPoints
        settings.burnAlertMarginBasisPoints = defaults.burnAlertMarginBasisPoints
        settings.maybeEventWeightBasisPoints = defaults.maybeEventWeightBasisPoints
        settings.windfallMultipleBasisPoints = defaults.windfallMultipleBasisPoints
        settings.coolOffThresholdMinorUnits = defaults.coolOffThresholdMinorUnits
        settings.goalCoolOffDays = defaults.goalCoolOffDays
        settings.costInTimeThresholdMinorUnits = defaults.costInTimeThresholdMinorUnits
        settings.stage6MaxDebtServiceBasisPoints = defaults.stage6MaxDebtServiceBasisPoints
        settings.stage6MaxAPRBasisPoints = defaults.stage6MaxAPRBasisPoints
        settings.runwayFullMarksMonths = defaults.runwayFullMarksMonths
        settings.debtServiceZeroScoreBasisPoints = defaults.debtServiceZeroScoreBasisPoints
        settings.emergencyFundMonths = defaults.emergencyFundMonths
        try? context.save()
        status = "Thresholds reset."
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
            .formStyle(.grouped).scrollDisabled(true).frame(minHeight: 240)
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
        .formStyle(.grouped).scrollDisabled(true).frame(minHeight: 240)
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
        .formStyle(.grouped).scrollDisabled(true).frame(minHeight: 240)
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
        .formStyle(.grouped).scrollDisabled(true).frame(minHeight: 240)
    }
}
