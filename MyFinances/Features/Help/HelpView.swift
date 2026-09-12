import SwiftUI

/// How to use the app. Written for someone opening it for the first time.
struct HelpView: View {
    @Binding var model: AppModel
    let formatter: MoneyFormatter

    @State private var section: Section = .start

    enum Section: String, CaseIterable, Identifiable {
        case start, daily, recording, money, debt, goals, screens, ladder, advisor,
             words, keys, privacy
        var id: String { rawValue }
        var title: String {
            switch self {
            case .start: "Start here"
            case .daily: "Using it daily"
            case .recording: "Where things go"
            case .money: "Income & windfalls"
            case .debt: "Loans"
            case .goals: "Goals & funds"
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
        case .recording: recordingSection
        case .money: moneySection
        case .debt: debtSection
        case .goals: goalsSection
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

            step(5, "Check your pay each month", "Income → This month's pay",
                 "At the end of the month the app compares what actually arrived against "
                 + "the figure you entered. If they differ it asks you to confirm which is "
                 + "right. A baseline that has quietly drifted makes free-to-spend, every "
                 + "goal date and every loan verdict wrong in the same direction.")

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

    // MARK: - Where things go

    private var recordingSection: some View {
        VStack(alignment: .leading, spacing: Theme.Space.md) {
            heading("Where does this go?",
                    "Every kind of money movement, and what to do with it.")

            card {
                VStack(alignment: .leading, spacing: Theme.Space.sm) {
                    define("Rent, bills, a bus fare",
                           "All the same thing: a spend. Log it with ⌥⌘E. If it repeats, set "
                           + "it up once under Plan → Scheduled and then just press Paid when "
                           + "it is due.")
                    define("A repeating bill that is due",
                           "Plan → Scheduled → Paid. That writes the entry and rolls the rule "
                           + "on to next month. If the amount varies, change it there and it "
                           + "remembers.")
                    define("Money from a project",
                           "Income → Record income. It works out the tax to set aside, and "
                           + "anything unusually large is held out of your spendable balance "
                           + "until you say where it goes.")
                    define("A gift",
                           "Income → Record income → Gift. It waits seven days before it can "
                           + "be allocated. No decisions in the first week.")
                    define("A refund",
                           "Income → Record income → Refund. It reverses the original spend "
                           + "and never counts as income or as a good month.")
                    define("Paying off a loan",
                           "Debt → right-click the loan → Record a payment. Use “Clear it” to "
                           + "fill in the full settlement figure.")
                    define("Moving money between your own accounts",
                           "⌘T. One record, and it never counts as spending or income.")
                    define("Putting money into a fund",
                           "That is a transfer too — ⌘T into the investment account.")
                }
            }

            infoCard("Paying a loan off with project money",
                     "Record the income first, allocate it, then record the loan payment from "
                     + "the account it landed in. Two entries, because two things happened: "
                     + "money came in, and money went out to the lender. The loan is marked "
                     + "paid and drops out of the payoff order, and every payment stays in "
                     + "your records — nothing is deleted.")

            card {
                VStack(alignment: .leading, spacing: Theme.Space.sm) {
                    SectionLabel(text: "Investments and funds")
                    Text("""
                         Add an account of type Investment — your MFund, a T-bill ladder,                          whatever you hold. Money you put in is a transfer (⌘T), so the app                          always knows what you contributed.

                         What it is worth is a different question, and one the app cannot                          answer: it has no internet. So every month or so it asks you. Open                          Investments and press Enter its value, put in the figure from your                          statement, and it keeps the history and charts it against what you                          put in.

                         It will never forecast what the holding might become. That is fiction,                          and this app does not deal in it.
                         """)
                        .font(.system(size: 12.5))
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }

    // MARK: - Income and windfalls

    private var moneySection: some View {
        VStack(alignment: .leading, spacing: Theme.Space.md) {
            heading("Money coming in",
                    "Regular pay, project work, gifts and refunds are each handled "
                    + "differently, on purpose.")

            card {
                VStack(alignment: .leading, spacing: Theme.Space.sm) {
                    SectionLabel(text: "Your salary")
                    Text("""
                         Set it once in Settings → Money & time: what lands each month and                          which day. Everything forward-looking reads that number — free to                          spend, goal dates, whether a loan fits.

                         At the end of each month the Income screen compares what actually                          arrived against what you entered. If they differ by more than 1% it                          asks which is right. Say the word and it updates; decline and nothing                          changes.
                         """)
                        .font(.system(size: 12.5))
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            card {
                VStack(alignment: .leading, spacing: Theme.Space.sm) {
                    SectionLabel(text: "Windfalls")
                    Text("""
                         Anything arriving above one and a half times your usual week is                          intercepted. It is recorded, but deliberately **not** counted as                          spendable until you have said where it goes.

                         This happens whether you log it from quick capture or record it on                          the Income screen. It is the single most useful behaviour in the app:                          money that never becomes "just balance" does not quietly disappear.

                         The allocation sheet is prefilled 40% to whatever step you are on,                          25% goals, 20% investing, 15% free. Drag the sliders; it must total                          100%. The goal and investing slices really do move money — an earmark                          and a transfer. The 15% free slice is yours and is not tracked                          against anything.
                         """)
                        .font(.system(size: 12.5))
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            infoCard("Tax reserve",
                     "For untaxed income, a share comes off the top and transfers to a tax "
                     + "reserve account straight away. It cannot be spent from and does not "
                     + "count in net worth, runway or free-to-spend. It was never your money. "
                     + "Set the rate in Settings → Thresholds, and confirm it with a local "
                     + "professional once a year.")

            infoCard("A refund is not income",
                     "It reverses the original spend. It never counts towards income, your "
                     + "savings rate, or a good month. Getting that wrong would make every "
                     + "other number lie.")

            infoCard("A gift waits a week",
                     "Gifts cannot be allocated for seven days. No decisions in the first "
                     + "week — large sums invite bad ones.")
        }
    }

    // MARK: - Loans

    private var debtSection: some View {
        VStack(alignment: .leading, spacing: Theme.Space.md) {
            heading("Loans", "Recording them, paying them, and clearing them.")

            card {
                VStack(alignment: .leading, spacing: Theme.Space.sm) {
                    define("Add a loan", "Debt → New loan. Say who it is owed to and how "
                           + "much it weighs on you: 0 is a faceless lender, 5 is family.")
                    define("Record a payment", "Right-click the loan → Record a payment. "
                           + "Enter any amount — it does not have to be the scheduled one.")
                    define("Clear it", "The payment sheet has a Clear it button that fills in "
                           + "the full settlement figure. Paying it marks the loan paid.")
                    define("Money lent out", "Add it with direction Owed to me. It is recorded "
                           + "at zero expected return, kept out of net worth, and never appears "
                           + "in what to clear.")
                }
            }

            infoCard("Nothing is ever deleted",
                     "A cleared loan drops out of the payoff order and stops counting against "
                     + "you, but the loan and every payment stay in your records permanently.")

            card {
                VStack(alignment: .leading, spacing: Theme.Space.sm) {
                    SectionLabel(text: "Which to clear first")
                    define("Avalanche", "Highest rate first. Costs the least.")
                    define("Snowball", "Smallest balance first. Clears one soonest.")
                    define("Peace of mind", "What you owe people first, whatever it costs.")
                    define("Balanced", "Rate, who it is owed to, size and urgency, weighted.")
                    Text("Switching between them tells you what the choice costs in interest. "
                         + "It shows you the price of choosing peace over arithmetic and then "
                         + "lets you choose.")
                        .font(Theme.Font.caption).foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            infoCard("Before you borrow",
                     "Debt → Thinking about a loan. Type an amount, rate and term and it tells "
                     + "you the monthly payment, the debt-service ratio and the total interest "
                     + "before you sign — plus what saving the same amount instead would take.")
        }
    }

    // MARK: - Goals and funds

    private var goalsSection: some View {
        VStack(alignment: .leading, spacing: Theme.Space.md) {
            heading("Goals, funds and investments",
                    "Three different jobs, often confused.")

            card {
                VStack(alignment: .leading, spacing: Theme.Space.sm) {
                    define("A goal", "Something you want to buy. It has a price and a date "
                           + "the app works out for you.")
                    define("A sinking fund", "Something you know is coming but not exactly "
                           + "when or how much: gifts, repairs, an annual renewal.")
                    define("An investment", "Money you are not going to touch. Tracked "
                           + "separately, never projected.")
                }
            }

            card {
                VStack(alignment: .leading, spacing: Theme.Space.sm) {
                    SectionLabel(text: "How a goal gets funded")
                    Text("""
                         Money is not moved into a separate pot. It is earmarked inside the                          account you nominated: it still shows in that account, it just stops                          counting as available to spend.

                         Each goal card shows how much is in it, which account holds it, and                          when it arrives — with a slider. Drag it and watch the date move.                          That is the honest answer to "should I put more in": you can see                          exactly what it buys you.

                         Goals are funded in your priority order, so a goal's date accounts                          for everything ahead of it in the queue.
                         """)
                        .font(.system(size: 12.5))
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            card {
                VStack(alignment: .leading, spacing: Theme.Space.sm) {
                    SectionLabel(text: "Investments and funds")
                    Text("""
                         Add an account of type Investment — your MFund, a T-bill ladder,                          whatever you hold. Putting money in is a transfer (⌘T), so the app                          always knows exactly what you contributed.

                         What it is worth is a different question, and one the app cannot                          answer: it has no internet. So roughly monthly it asks. Open                          Investments, press Enter its value, and put in the figure from your                          statement. It keeps the history and charts it against what you put in.

                         It will never forecast what a holding might become, and a holding you                          have not valued shows no gain rather than pretending it is flat.
                         """)
                        .font(.system(size: 12.5))
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            infoCard("The emergency fund is protected",
                     "The allocation engine only ever adds to it, never takes from it, and "
                     + "spending out of it asks you to confirm and say why. Set how many "
                     + "months it should hold in Settings → Thresholds.")
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
                           + "your work actually pays per hour, the monthly pay check, and "
                           + "the creep chart.")
                    define("Investments", "What you put in, what you last said it is worth, "
                           + "how many months you have contributed, and the emergency fund.")
                    define("Ladder", "Which of the seven stages you are on, with the evidence.")
                    define("Advisor", "What the next money you get should do, the rules, and "
                           + "the monthly letter.")
                    define("Review", "Your week and your month, with a copy button.")
                    define("Settings", "Currency, your pay, and every threshold the app "
                           + "uses. Nothing is hardcoded.")
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
            infoCard("Two kinds of button in the toolbar",
                     "Buttons on the right with words — Log a spend, Transfer — work on every "
                     + "screen. A button on the left is that screen's own: New loan, New goal, "
                     + "Record income.")

            card {
                VStack(alignment: .leading, spacing: Theme.Space.sm) {
                    shortcut("⌥⌘E", "Quick capture, from any app")
                    shortcut("⌘,", "Settings")
                    shortcut("⌘N", "Log a spend")
                    shortcut("⌘T", "Transfer between accounts")
                    shortcut("⌥⌘I", "Show or hide the details panel")
                    shortcut("⌘1 … ⌘9", "Jump to a screen")
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
            card {
                VStack(alignment: .leading, spacing: Theme.Space.sm) {
                    SectionLabel(text: "Backups")
                    Text("""
                         Settings → Data & backup → choose a folder, then Back up now, or                          leave weekly backups on. It keeps the last twelve.

                         It copies the database and its write-ahead log together — without                          that second file a backup can be missing your most recent entries.

                         You can also export everything as CSV or JSON at any time, and import                          a CSV from a spreadsheet or bank export. Nothing is locked in.
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
