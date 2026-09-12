import SwiftUI
import SwiftData

/// Create or edit an account. Opening balance is the only balance figure anyone ever
/// types — everything after it is derived from the ledger.
struct AccountEditor: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context
    @Environment(\.colorScheme) private var scheme
    let editingID: UUID?
    let formatter: MoneyFormatter

    @Query(filter: #Predicate<Account> { $0.deletedAt == nil }, sort: \Account.sortOrder)
    private var accounts: [Account]

    @State private var name = ""
    @State private var type: AccountType = .cash
    @State private var openingText = ""
    @State private var floorText = ""
    @State private var isLiquid = true
    @State private var includeInNetWorth = true
    @State private var isTaxReserve = false
    @State private var isEmergencyFundAccount = false
    @State private var colorHex = "#4F8A7B"

    private var existing: Account? {
        guard let editingID else { return nil }
        return accounts.first { $0.id == editingID }
    }

    private var isValid: Bool {
        !name.trimmingCharacters(in: .whitespaces).isEmpty
            && (openingText.isEmpty || formatter.parse(openingText) != nil)
    }

    private let palette = ["#4F8A7B", "#4E8FA8", "#C9B24E", "#B05C4F", "#7B6FC9", "#7AA84E", "#8A8A8A"]

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text(existing == nil ? "New account" : "Edit account").font(Theme.Font.title)
                Spacer()
            }
            .padding(Theme.Space.lg)
            Divider().opacity(0.5)

            ScrollView {
                VStack(alignment: .leading, spacing: Theme.Space.md) {
                    labelled("Name") {
                        TextField("MTN MoMo", text: $name).textFieldStyle(.roundedBorder)
                    }

                    labelled("Type") {
                        Picker("", selection: $type) {
                            ForEach(AccountType.allCases, id: \.self) { option in
                                Label(option.label, systemImage: option.systemImage).tag(option)
                            }
                        }
                        .labelsHidden()
                        .onChange(of: type) { _, newValue in
                            isLiquid = newValue.isLiquidByDefault
                            includeInNetWorth = newValue.countsInNetWorthByDefault
                        }
                    }

                    labelled("Opening balance") {
                        TextField("0.00", text: $openingText)
                            .textFieldStyle(.roundedBorder)
                            .disabled(existing != nil)
                    }
                    if existing != nil {
                        Text("Opening balance is fixed once an account exists. To correct a "
                             + "balance, reconcile instead — it records why it changed.")
                            .font(Theme.Font.caption).foregroundStyle(.secondary)
                    }

                    labelled("Low balance floor") {
                        TextField("Optional", text: $floorText).textFieldStyle(.roundedBorder)
                    }

                    labelled("Colour") {
                        HStack(spacing: Theme.Space.sm) {
                            ForEach(palette, id: \.self) { hex in
                                Circle()
                                    .fill(Color(hex: hex))
                                    .frame(width: 18, height: 18)
                                    .overlay(
                                        Circle().stroke(Color.primary.opacity(
                                            colorHex == hex ? 0.6 : 0), lineWidth: 2)
                                    )
                                    .onTapGesture { colorHex = hex }
                                    .accessibilityLabel("Colour \(hex)")
                            }
                            Spacer()
                        }
                    }

                    Divider().opacity(0.4)

                    Toggle("I can spend from this today", isOn: $isLiquid)
                    Toggle("Count towards net worth", isOn: $includeInNetWorth)
                    Toggle("This is my emergency fund", isOn: $isEmergencyFundAccount)
                    Toggle("This is a tax reserve", isOn: $isTaxReserve)
                    if isTaxReserve {
                        NoticeRow(
                            tone: .caution, icon: "lock",
                            title: "Not your money",
                            detail: "A tax reserve cannot be spent from, holds no goal earmarks, "
                                  + "and is excluded from net worth, runway and free-to-spend."
                        )
                    }
                }
                .padding(Theme.Space.lg)
            }

            Divider().opacity(0.5)
            HStack {
                Spacer()
                Button("Cancel") { dismiss() }.keyboardShortcut(.cancelAction)
                Button("Save") { save() }
                    .keyboardShortcut(.defaultAction)
                    .buttonStyle(.borderedProminent)
                    .disabled(!isValid)
            }
            .padding(Theme.Space.md)
        }
        .frame(width: 440, height: 580)
        .background(Theme.Palette.surface(scheme))
        .onAppear(perform: load)
    }

    private func labelled<Content: View>(_ title: String,
                                         @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: Theme.Space.xs) {
            SectionLabel(text: title)
            content()
        }
    }

    private func load() {
        guard let existing else { return }
        name = existing.name
        type = existing.type
        openingText = formatter.string(existing.openingBalance, style: .bare)
        floorText = existing.lowBalanceFloor.map { formatter.string($0, style: .bare) } ?? ""
        isLiquid = existing.isLiquid
        includeInNetWorth = existing.includeInNetWorth
        isTaxReserve = existing.isTaxReserve
        isEmergencyFundAccount = existing.isEmergencyFundAccount
        colorHex = existing.colorHex
    }

    private func save() {
        let floor = floorText.isEmpty ? nil : formatter.parse(floorText)
        if let existing {
            existing.name = name
            existing.type = type
            existing.lowBalanceFloor = floor
            existing.isLiquid = isLiquid
            existing.includeInNetWorth = includeInNetWorth
            existing.isTaxReserve = isTaxReserve
            existing.isEmergencyFundAccount = isEmergencyFundAccount
            existing.colorHex = colorHex
            existing.updatedAt = Date()
        } else {
            let account = Account(
                name: name,
                type: type,
                openingBalance: formatter.parse(openingText) ?? .zero,
                colorHex: colorHex,
                sortOrder: (accounts.map(\.sortOrder).max() ?? -1) + 1,
                includeInNetWorth: includeInNetWorth,
                isLiquid: isLiquid,
                lowBalanceFloor: floor,
                isTaxReserve: isTaxReserve,
                isEmergencyFundAccount: isEmergencyFundAccount
            )
            context.insert(account)
        }
        try? context.save()
        dismiss()
    }
}
