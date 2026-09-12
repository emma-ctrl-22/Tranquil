import SwiftUI
import SwiftData
import AppKit

extension Notification.Name {
    static let quickAdd = Notification.Name("tranquil.quickAdd")
    static let openSettings = Notification.Name("tranquil.openSettings")
}

/// The store, created once and shared by the SwiftUI scenes and the status item.
enum AppEnvironment {
    static let container: ModelContainer = {
        do {
            return try TranquilSchema.container()
        } catch {
            // A store that will not open is not something the user can act on, but the
            // app must still start so they can export and reinstall.
            return try! TranquilSchema.container(inMemory: true)
        }
    }()
}

@main
struct TranquilApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate

    var body: some Scene {
        Window("Tranquil", id: "main") {
            RootView()
                .modelContainer(AppEnvironment.container)
        }
        .defaultSize(width: 1180, height: 740)
        .commands {
            CommandGroup(after: .newItem) {
                Button("Log a Spend") {
                    NotificationCenter.default.post(name: .quickAdd, object: nil)
                }
                .keyboardShortcut("n", modifiers: .command)
            }
        }

        Settings {
            SettingsView()
                .modelContainer(AppEnvironment.container)
        }
    }
}

/// Runs Tranquil as a menu bar agent: a status item with a popover, a global hotkey,
/// and the one daily nudge.
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusItem: NSStatusItem?
    private var popover: NSPopover?

    /// True when the app is only hosting a test bundle. A status item, a system-wide
    /// hotkey and a notification prompt are all process-global: several parallel test
    /// hosts competing for them kills the workers.
    private var isHostingTests: Bool {
        ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil
            || NSClassFromString("XCTestCase") != nil
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        guard !isHostingTests else {
            NSApp.setActivationPolicy(.prohibited)
            return
        }

        // A normal app by default: a Dock icon you can keep, and — the reason this
        // matters — a real menu bar. An accessory app has no menu bar, so with the
        // system set to auto-hide it, moving the pointer to the top of the screen
        // reveals nothing at all while this app is frontmost.
        UserDefaults.standard.register(defaults: ["tranquil.showInDock": true])
        let wantsDockIcon = UserDefaults.standard.bool(forKey: "tranquil.showInDock")
        NSApp.setActivationPolicy(wantsDockIcon ? .regular : .accessory)

        installStatusItem()

        // ⌥⌘E from anywhere. Carbon's hotkey API needs no Accessibility permission.
        // If something else already owns the combination, the app carries on without it.
        HotkeyService.shared.register { [weak self] in
            self?.togglePopover(nil)
        }

        // The widget must be fed on launch, not only when the main window opens — this
        // app usually runs all day without a window in sight. It deliberately does not
        // sit behind the notification prompt: a permission dialog the user has not
        // answered would otherwise leave the widget blank indefinitely.
        refreshWidgetSnapshot()

        Task { @MainActor in
            _ = await NotificationService.shared.requestAuthorizationIfNeeded()
            scheduleDailyNudge()
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        HotkeyService.shared.unregister()
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows: Bool) -> Bool {
        if !hasVisibleWindows { openMainWindow() }
        return true
    }

    // MARK: - Status item

    private func installStatusItem() {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        item.button?.image = NSImage(
            systemSymbolName: "leaf", accessibilityDescription: "Tranquil"
        )
        item.button?.target = self
        item.button?.action = #selector(togglePopover(_:))
        item.button?.sendAction(on: [.leftMouseUp, .rightMouseUp])
        statusItem = item

        let popover = NSPopover()
        popover.behavior = .transient
        popover.animates = false
        popover.contentViewController = NSHostingController(
            rootView: MenuBarPopover().modelContainer(AppEnvironment.container)
        )
        self.popover = popover
    }

    @objc private func togglePopover(_ sender: Any?) {
        guard let popover, let button = statusItem?.button else { return }
        if popover.isShown {
            popover.performClose(nil)
            return
        }
        // Right-click gives the utility menu; left-click and the hotkey capture.
        if let event = NSApp.currentEvent, event.type == .rightMouseUp {
            showMenu(from: button)
            return
        }
        NSApp.activate(ignoringOtherApps: true)
        popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
        popover.contentViewController?.view.window?.makeKey()
    }

    private func showMenu(from button: NSStatusBarButton) {
        let menu = NSMenu()
        menu.addItem(withTitle: "Open Tranquil", action: #selector(openMainWindow), keyEquivalent: "")
            .target = self
        menu.addItem(.separator())
        menu.addItem(withTitle: "Settings…", action: #selector(openSettings), keyEquivalent: ",")
            .target = self
        menu.addItem(.separator())
        menu.addItem(withTitle: "Quit Tranquil", action: #selector(NSApplication.terminate(_:)),
                     keyEquivalent: "q")
        statusItem?.menu = menu
        button.performClick(nil)
        statusItem?.menu = nil
    }

    @objc private func openMainWindow() {
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
        if let existing = NSApp.windows.first(where: { $0.identifier?.rawValue.contains("main") == true }) {
            existing.makeKeyAndOrderFront(nil)
        } else {
            NSWorkspace.shared.open(URL(string: "tranquil://main")!)
        }
    }

    /// An accessory app has no menu bar, so `showSettingsWindow:` has nothing to hang
    /// off. Settings is a screen inside the main window instead.
    @objc private func openSettings() {
        openMainWindow()
        NotificationCenter.default.post(name: .openSettings, object: nil)
    }

    // MARK: - Daily nudge

    /// Feeds the widget on launch. This app usually runs all day without a window in
    /// sight, so it cannot wait for one to appear.
    @MainActor
    private func refreshWidgetSnapshot() {
        WidgetSnapshotWriter.refresh(container: AppEnvironment.container)
    }

    @MainActor
    private func scheduleDailyNudge() {
        let context = ModelContext(AppEnvironment.container)
        guard let settings = try? context.fetch(FetchDescriptor<AppSettings>()).first
        else { return }
        let calendar = settings.calendar
        let today = calendar.today()
        let logs = (try? context.fetch(FetchDescriptor<DailyLog>())) ?? []
        let hasLoggedToday = logs.contains { $0.date == today && $0.entryCount > 0 }
        NotificationService.shared.scheduleDailyNudgeIfNeeded(
            hasLoggedToday: hasLoggedToday, settings: settings, calendar: calendar
        )
    }
}
