import SwiftUI
import SwiftData

/// Window-level UI state: what is selected, what panel is open, what sheet is up.
/// No money logic lives here — that is the engines' job.
@Observable
final class AppModel {
    enum Screen: String, CaseIterable, Identifiable, Hashable {
        case dashboard, ledger, accounts, plan, debt, income, advisor, goals, insights, ladder
        case review
        case help

        var id: String { rawValue }

        var title: String {
            switch self {
            case .dashboard: "Dashboard"
            case .ledger: "Ledger"
            case .accounts: "Accounts"
            case .plan: "Plan"
            case .debt: "Debt"
            case .income: "Income"
            case .advisor: "Advisor"
            case .goals: "Goals"
            case .insights: "Insights"
            case .ladder: "Ladder"
            case .review: "Review"
            case .help: "How to use this"
            }
        }

        var icon: String {
            switch self {
            case .dashboard: "square.grid.2x2"
            case .ledger: "list.bullet"
            case .accounts: "wallet.pass"
            case .plan: "calendar"
            case .debt: "creditcard"
            case .income: "tray.and.arrow.down"
            case .advisor: "text.book.closed"
            case .goals: "target"
            case .insights: "chart.bar"
            case .ladder: "stairs"
            case .review: "doc.text"
            case .help: "questionmark.circle"
            }
        }

        /// Screens that arrive in later milestones are shown but marked.
        var isAvailable: Bool {
            switch self {
            case .dashboard, .ledger, .accounts, .plan, .debt, .goals, .ladder, .review,
             .income, .advisor, .insights, .help: true
            default: false
            }
        }
    }

    var screen: Screen = .dashboard
    var selectedAccountID: UUID?
    var selectedTransactionID: UUID?
    var isInspectorShown = true
    var isQuickAddShown = false
    var isTransferShown = false
    var reconcilingAccountID: UUID?
    var editingAccountID: UUID?
    var isAccountEditorShown = false
    var searchText = ""
    var heatmapMode: InsightsEngine.HeatmapMode = .logged

    /// The five-second undo window after a save.
    var lastSaved: (id: UUID, label: String)?

    func open(_ screen: Screen) {
        guard screen.isAvailable else { return }
        self.screen = screen
    }
}
