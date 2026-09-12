import SwiftUI

/// How to use the app. Written for someone opening it for the first time.
struct HelpView: View {
    @Binding var model: AppModel
    let formatter: MoneyFormatter

    @State private var section: Section = .start

    enum Section: String, CaseIterable, Identifiable {
        case start, daily, words, screens, ladder, advisor, keys, privacy
        var id: String { rawValue }
        var title: String {
            switch self {
            case .start: "Start here"
            case .daily: "Using it daily"
            case .words: "What the words mean"
            case .screens: "The screens"
            case .ladder: "The Ladder"
            case .advisor: "The Advisor"
            case .keys: "Keyboard"
            case .privacy: "Your data"
            }
        }
    }

    var body: some View {
        HStack(spacing: 0) {
            List(Section.allCases, selection: $section) { item in
                Text(item.title).tag(item)
            }
            .listStyle(.sidebar)
            .frame(width: 180)

            Divider().opacity(0.5)

            ScrollView {
                VStack(alignment: .leading, spacing: Theme.Space.md) {
                    content
                }
                .padding(Theme.Space.lg)
                .frame(maxWidth: 720, alignment: .leading)
            }
        }
    }

    @ViewBuilder
    private var content: some View {
        switch section {
        case .start: startSection
        case .daily: dailySection
        case .words: wordsSection
        case .screens: screensSection
        case .ladder: ladderSection
        case .advisor: advisorSection
        case .keys: keysSection
        case .privacy: privacySection
        }
    }

    // MARK: - Start

    private var startSection: some View {
        VStack(alignment: .leading, spacing: Theme.Space.md) {
            heading("Set it up in four steps",
                    "Each one takes a couple of minutes. Do them in order — later steps read "
                    + "what earlier ones set up.")

            step(1, "Add your accounts", "Accounts → New account",
                 "Add every place money actually sits: cash in your pocket, mobile money, "
                 + "your bank, savings. Put in what is in each one right now as the opening "
                 + "balance. That is the only balance you ever type — after this the app "
                 + "works balances out from what you log.")

            step(2, "Tell it what you earn", "Settings → Money & time",
                 "Your net pay each month and the day it lands. Everything forward-looking "
                 + "reads this: what is free to spend, when goals arrive, whether a loan fits.")

            step(3, "Add what repeats", "Plan → Scheduled → +",
                 "Rent, salary, data bundle, any loan payment. These are what make the "
                 + "60-day forecast able to warn you. Without them it has nothing to predict "
                 + "from.")

            step(4, "Set two or three envelopes", "Plan → Envelopes → New envelope",
                 "Pick the two or three things you actually lose money on, and give "
                 + "Miscellaneous a real number too — that is where discipline usually breaks. "
                 + "Weekly amounts, not monthly; the week is the unit you can still do "
                 + "something about.")

            infoCard("Then just log things",
                     "That is the whole job. Press ⌥⌘E from anywhere, type what you spent, "
                     + "press Return. Everything else in the app is built out of those entries.")
        }
    }

    // MARK: - Daily

    private var dailySection: some View {
        VStack(alignment: .leading, spacing: Theme.Space.md) {
            heading("Logging takes three seconds",
                    "Press ⌥⌘E anywhere, or click the leaf in the menu bar. Type one line "
                    + "and press Return.")

            card {
                VStack(alignment: .leading, spacing: Theme.Space.sm) {
                    SectionLabel(text: "What you can type")
                    example("trotro 5", "₵5.00 out, category Trotro")
                    example("15 lunch momo", "₵15.00 out, Lunch, from MTN MoMo")
                    example("-40 data", "₵40.00 out, Data")
                    example("5000 salary", "₵5,000.00 in — the word salary makes it income")
                    example("30", "₵30.00 out, Miscellaneous, flagged for review")
                    Text("Order does not matter and capitals do not matter. It shows you "
                         + "exactly what it will save before you press Return, so nothing is "
                         + "a surprise.")
                        .font(Theme.Font.caption).foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            card {
                VStack(alignment: .leading, spacing: Theme.Space.sm) {
                    SectionLabel(text: "If you are not sure what it was")
                    Text("Type just the amount. It goes to Miscellaneous marked as an "
                         + "estimate and waits in Ledger → Needs review. A rough number logged "
                         + "now is worth far more than an exact one you never enter.")
                        .font(.system(size: 12.5))
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            card {
                VStack(alignment: .leading, spacing: Theme.Space.sm) {
                    SectionLabel(text: "Once a fortnight: reconcile")
                    Text("Accounts → right-click an account → Reconcile. Count what is really "
                         + "there and type it in. The app shows the gap and posts one visible "
                         + "\u{201C}Unaccounted\u{201D} entry to close it. This is what keeps "
                         + "the numbers honest, and the dashboard will nag you after 14 days.")
                        .font(.system(size: 12.5))
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }

    // MARK: - Words

    private var wordsSection: some View {
        VStack(alignment: .leading, spacing: Theme.Space.md) {
            heading("The words the app uses",
                    "A few of these mean something specific here.")
            card {
                VStack(alignment: .leading, spacing: Theme.Space.sm) {
                    define("Envelope", "A budget for one kind of spending over a week.")
                    define("Miscellaneous", "The catch-all envelope. It gets its own real "
                           + "number — it is not a leftover.")
                    define("Micro-spend", "Small, frequent things: bus fare, water, lunch. "
                           + "They get chips in quick capture and their own yearly total.")
                    define("Earmark", "Money reserved for a goal inside an account. It stays "
                           + "in the account; it just stops counting as available.")
                    define("Available", "Balance minus earmarks. What you can actually spend.")
                    define("Committed outflow", "Rent, a loan payment, an investment. It comes "
                           + "off the top before anything is called free.")
                    define("Free to spend", "What is left this week after commitments and what "
                           + "you have already spent.")
                    define("Runway", "How many months of essential spending your liquid money "
                           + "covers.")
                    define("Sinking fund", "Saving toward something you know is coming — gifts, "
                           + "repairs, an annual renewal.")
                    define("Windfall", "Any inflow well above your usual week. It is held out "
                           + "of your spendable balance until you decide where it goes.")
                    define("Tax reserve", "Money set aside from untaxed income. Not spendable, "
                           + "not counted as yours.")
                }
            }
        }
    }

    // MARK: - Screens

    private var screensSection: some View {
        VStack(alignment: .leading, spacing: Theme.Space.md) {
            heading("What each screen is for", "")
            card {
                VStack(alignment: .leading, spacing: Theme.Space.sm) {
                    define("Dashboard", "Answers one question: am I okay? One recommended "
                           + "action at the top, one figure per area below it.")
                    define("Ledger", "Everything you have logged, grouped by day. Filters, "
                           + "search, and the needs-review queue.")
                    define("Accounts", "Balances, what is earmarked, reconcile, transfers.")
                    define("Plan", "Envelopes and their burn meters, everything scheduled, and "
                           + "the 60-day cash-flow view that says whether you will be short.")
                    define("Debt", "What you owe, in the order worth clearing it, and what "
                           + "each order costs. Also the verdict on a loan before you sign.")
                    define("Goals", "What you are saving for, when it arrives, and what "
                           + "changing the weekly amount does to that date.")
                    define("Income", "Windfalls waiting to be allocated, the tax reserve, what "
                           + "your work actually pays per hour, and the creep chart.")
                    define("Ladder", "Which of the seven stages you are on, with the evidence.")
                    define("Advisor", "What the next money you get should do, the rules, and "
                           + "the monthly letter.")
                    define("Review", "Your week and your month, with a copy button.")
                    define("Insights", "The logging heatmap, net worth, and where it all went.")
                }
            }
        }
    }

    // MARK: - Ladder

    private var ladderSection: some View {
        VStack(alignment: .leading, spacing: Theme.Space.md) {
            heading("The Tranquility Ladder",
                    "Seven stages, in order. The app works out which one you are on and shows "
                    + "a single next action — never a list of twelve things.")
            card {
                VStack(alignment: .leading, spacing: Theme.Space.sm) {
                    ForEach(LadderStage.allCases, id: \.rawValue) { stage in
                        HStack(alignment: .top, spacing: Theme.Space.sm) {
                            Text("\(stage.rawValue)")
                                .font(Theme.Font.amount).foregroundStyle(.tertiary)
                                .frame(width: 16, alignment: .trailing)
                            Text(stage.title).font(.system(size: 12.5))
                            Spacer(minLength: 0)
                        }
                    }
                }
            }
            infoCard("Going backwards is fine",
                     "Stages are checked continuously, so you can slip back down one. The app "
                     + "says so plainly and moves on to what to do about it. There is no "
                     + "shaming here and no streak to lose.")
            infoCard("Stage 7 takes six months",
                     "Tranquility is stages 0–6 holding together for six consecutive months. "
                     + "It is deliberately slow, and the app will not claim it early.")
        }
    }

    // MARK: - Advisor

    private var advisorSection: some View {
        VStack(alignment: .leading, spacing: Theme.Space.md) {
            heading("The Advisor",
                    "A fixed set of rules, not a chatbot. Same numbers in, same answer out, "
                    + "every time — and every answer points at the rule it came from.")
            card {
                VStack(alignment: .leading, spacing: Theme.Space.sm) {
                    define("What it does", "Tells you what the next money you get should do, "
                           + "and what a decision costs before you make it.")
                    define("What it will not do", "Pick investments, name products, predict "
                           + "markets, or compare you to anyone.")
                    define("Verdicts", "Approved · Approved with conditions · Not advised · "
                           + "Blocked. Always with the arithmetic shown.")
                    define("Overrides", "You can override any rule except R2 by typing a "
                           + "reason. It is kept and totalled each month, without comment.")
                }
            }
            infoCard("It never says you cannot afford something",
                     "It says what the thing costs — in money, in weeks of a goal, in Ladder "
                     + "stages — and then it is your call.")
        }
    }

    // MARK: - Keyboard

    private var keysSection: some View {
        VStack(alignment: .leading, spacing: Theme.Space.md) {
            heading("Keyboard", "")
            card {
                VStack(alignment: .leading, spacing: Theme.Space.sm) {
                    shortcut("⌥⌘E", "Quick capture, from any app")
                    shortcut("⌘N", "Log a spend")
                    shortcut("⌘T", "Transfer between accounts")
                    shortcut("⌥⌘I", "Show or hide the details panel")
                    shortcut("⌘1 … ⌘9", "Jump to a screen")
                    shortcut("⌘,", "Settings")
                    shortcut("Return", "Save, in any sheet")
                    shortcut("Esc", "Cancel, in any sheet")
                }
            }
        }
    }

    // MARK: - Privacy

    private var privacySection: some View {
        VStack(alignment: .leading, spacing: Theme.Space.md) {
            heading("Your data stays here", "")
            card {
                VStack(alignment: .leading, spacing: Theme.Space.sm) {
                    Text("""
                         This app makes no network calls of any kind. No accounts, no sync, no \
                         telemetry, no analytics, no crash reporting, no bank connections. \
                         There is nowhere for your data to go.

                         Everything lives in one file on this Mac. That means nobody else can \
                         see it — and also that if the Mac dies, so does it.
                         """)
                        .font(.system(size: 12.5))
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            infoCard("So set up backups",
                     "Settings → Data → choose a folder. It keeps the last 12 and can do it "
                     + "weekly on its own. You can also export everything as CSV or JSON at "
                     + "any time, and nothing is locked in.")
        }
    }

    // MARK: - Pieces

    private func heading(_ title: String, _ subtitle: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title).font(.system(size: 20, weight: .medium))
            if !subtitle.isEmpty {
                Text(subtitle)
                    .font(Theme.Font.caption).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private func card<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        Card { content() }
    }

    private func step(_ number: Int, _ title: String, _ where_: String,
                      _ detail: String) -> some View {
        Card {
            HStack(alignment: .top, spacing: Theme.Space.md) {
                Text("\(number)")
                    .font(.system(size: 16, weight: .medium, design: .rounded))
                    .foregroundStyle(Theme.Palette.accent)
                    .frame(width: 22)
                VStack(alignment: .leading, spacing: 3) {
                    Text(title).font(.system(size: 14, weight: .medium))
                    Text(where_).font(Theme.Font.caption)
                        .foregroundStyle(Theme.Palette.accent)
                    Text(detail).font(.system(size: 12.5)).foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }

    private func infoCard(_ title: String, _ detail: String) -> some View {
        NoticeRow(tone: .positive, icon: "lightbulb", title: title, detail: detail)
    }

    private func example(_ typed: String, _ result: String) -> some View {
        HStack(alignment: .top, spacing: Theme.Space.sm) {
            Text(typed)
                .font(.system(size: 12, design: .monospaced))
                .padding(.horizontal, 6).padding(.vertical, 2)
                .background(Theme.Palette.accentSoft)
                .clipShape(RoundedRectangle(cornerRadius: 4))
                .frame(width: 130, alignment: .leading)
            Text(result).font(Theme.Font.caption).foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
    }

    private func define(_ term: String, _ meaning: String) -> some View {
        HStack(alignment: .top, spacing: Theme.Space.sm) {
            Text(term).font(.system(size: 12.5, weight: .medium))
                .frame(width: 132, alignment: .leading)
            Text(meaning).font(Theme.Font.caption).foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
    }

    private func shortcut(_ keys: String, _ what: String) -> some View {
        HStack(spacing: Theme.Space.sm) {
            Text(keys)
                .font(.system(size: 12, design: .monospaced))
                .padding(.horizontal, 6).padding(.vertical, 2)
                .background(Theme.Palette.raised(.light).opacity(0.6))
                .clipShape(RoundedRectangle(cornerRadius: 4))
                .frame(width: 88, alignment: .leading)
            Text(what).font(Theme.Font.caption).foregroundStyle(.secondary)
            Spacer(minLength: 0)
        }
    }
}
