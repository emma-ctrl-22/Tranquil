import SwiftUI
import SwiftData

struct SettingsView: View {
    @Environment(\.modelContext) private var context
    @Query private var settingsRows: [AppSettings]

    @State private var launchAtLogin = LaunchAtLoginService.isEnabled
    @AppStorage("tranquil.showInDock") private var showInDock = false

    private var settings: AppSettings? { settingsRows.first }

    var body: some View {
        TabView {
            general.tabItem { Label("General", systemImage: "gearshape") }
            notifications.tabItem { Label("Notifications", systemImage: "bell") }
            privacy.tabItem { Label("Privacy", systemImage: "lock") }
        }
        .frame(width: 460, height: 340)
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
