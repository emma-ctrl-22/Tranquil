# CLAUDE.md

Project context for **Tranquil** — a local-first macOS personal finance app.
Read this before touching anything. `BUILD_PROMPT.md` is the product spec, `ADVISOR_RULES.md` is the rule book for the opinionated layer, and this file is how we build both.

---

## What this app is for

One person's daily money life: micro-spends, weekly envelopes, several accounts, loans owed, things they're saving for, and a staged path to financial stability. The goal is **stability, not wealth optimisation**. Features that add anxiety, comparison, or speculation don't belong here, no matter how standard they are in finance apps.

The single most important quality: **logging a ₮5 bus fare must take under three seconds.** If a change makes capture slower, it's a regression even if it adds a feature.

---

## Stack

- macOS 14+, Swift 5.9+, SwiftUI, SwiftData, Swift Charts
- Menu bar agent (`LSUIElement = true`), main window optional, launches at login
- `UNUserNotificationCenter` for all notifications — **local only**
- No third-party dependencies without asking first. `swift-format` and XCTest are fine.

## Commands

```bash
xcodebuild -scheme Tranquil -destination 'platform=macOS' build
xcodebuild -scheme Tranquil -destination 'platform=macOS' test
swift-format format -i -r Sources/
```

## Layout

```
Sources/
  Core/
    Money/           Money type, formatting, rounding, allocation
    Time/            FinancialCalendar — week/month/day boundaries
    Extensions/
  Models/            SwiftData @Model types only, no business logic
  Engines/           pure, testable, no UI, no SwiftData writes
    BalanceEngine    account balances, earmarks, available
    BudgetEngine     envelopes, burn rate, free-to-spend
    LoanEngine       schedules, amortisation, payoff ordering, simulation
    GoalEngine       allocation waterfall, ETA
    ForecastEngine   60-day cash-flow projection
    LadderEngine     stage evaluation, stability score
    AdvisorEngine    verdicts, hard rules R1-R11, order of operations, monthly letter
    IncomeEngine     windfall interception, allocation splits, creep detection
    NotificationRules declarative rule list, evaluated by a scheduler
  Features/          one folder per screen: View + ViewModel
  Services/          persistence, notifications, backup, import/export, app lock
Tests/
  EngineTests/       golden tests for every engine
  FixtureData/
```

**Engines are pure functions over snapshots.** They take value types in and return value types out. They never read `@Environment`, never touch SwiftData directly, never schedule notifications. This is what makes the money logic testable, and the money logic is the whole app.

---

## Money — the rules that matter most

1. **Never `Double`, never `Float`, anywhere near an amount.** Not in a model, not in a view, not in a temporary variable.
2. All amounts are `Int` in **minor units** (cents/pesewas). `Money` is a struct wrapping that `Int`.
3. Only `Money` formats currency. No view builds a string from a number.
4. **Percentages and rates use `Decimal`.** Convert to `Money` only at the end, with explicit rounding.
5. Rounding is banker's rounding, applied once, at the final step — never intermediate.
6. **Splitting money must not lose or create money.** Use `Money.split(into:)`, which distributes remainder pennies across the first N parts and asserts the sum equals the original. Every allocation, amortisation schedule, and proration goes through it.
7. `Money` is never optional to mean zero. Use `.zero`.
8. Amounts are stored positive; direction comes from `Transaction.kind`. There are no negative amounts in the database.

Any function touching money gets a unit test with a hand-checked expected value. Not a test that asserts the function equals itself — a test with a number a human worked out.

---

## Time

- One `FinancialCalendar`, injected everywhere. Nothing calls `Date()` or `Calendar.current` directly.
- The **financial day starts at the configured hour** (default 04:00). A 01:30 expense belongs to the previous financial day. This affects the heatmap, daily nudges, streaks, and daily totals — get it right once, centrally.
- Weeks start on the configured weekday.
- Store `Date` in UTC, present in the user's timezone.
- Month arithmetic must survive month-end: "monthly on the 31st" in February means the 28th/29th, not a skipped month.

---

## Data rules

- **Balances are derived**, never stored as mutable state. `BalanceSnapshot` rows are a nightly cache, always reconstructable from transactions — if the cache and the ledger ever disagree, the ledger wins and the cache is rebuilt.
- A transfer is **one** `Transaction` with `kind == .transfer` and a `counterAccount`. Transfers never appear in income or expense totals. Assert this in tests; it's the bug every finance app ships.
- **Soft delete only** (`deletedAt`). Every query filters deleted rows. Purge is a manual action in Settings with a confirmation.
- Invariant: `sum(earmarks on an account) <= account.balance`. When violated, surface an **over-committed** warning; never silently rebalance the user's money for them.
- Every schema change ships with a migration and a test that opens a fixture database from the previous version.

---

## Vocabulary — use these exact words in code, UI, and commits

| Term | Meaning |
|---|---|
| **Envelope** | A budget for a category over a period |
| **Miscellaneous** | The catch-all envelope — a first-class budget, not a leftover |
| **Micro-spend** | Small frequent expense (bus fare, water) — `Category.isMicro` |
| **Earmark** | Money inside an account reserved for a goal or fund |
| **Available** | `balance − earmarks` — what's actually spendable |
| **Committed outflow** | Loan payment, investment, sinking fund, recurring bill — comes off the top |
| **Free to spend** | What's left after committed outflows and goal allocations |
| **Runway** | Months of essential spend covered by liquid available funds |
| **Burn rate** | Envelope spend pace vs elapsed time in the period |
| **Sinking fund** | Saving toward a known future expense |
| **Ladder** | The seven-stage path to stability |
| **Tranquility** | Stage 7 — stability held for six months. **Never say "financial freedom."** |
| **Order of Operations** | What the next unit of money does (`ADVISOR_RULES.md` §2) — distinct from the Ladder, which is where you are |
| **Windfall** | Any inflow > 1.5x median weekly income — intercepted, unspendable until allocated |
| **Tax reserve** | Money set aside from untaxed income. Not an asset, not spendable, not part of runway. |
| **Creep** | Essential spend rising as a share of income |
| **Verdict** | Advisor output: Approved / with conditions / Not advised / Blocked |

---

## The Advisor — scope and boundaries

The advisor is a **deterministic rule engine over `ADVISOR_RULES.md`**, implemented in plain Swift. It is not a model, makes no network calls, and produces identical output for identical inputs. Every verdict must be reproducible and explainable by pointing at a rule ID.

It advises on **behaviour only** — how much, in what order, held where, and what a decision costs. It does not and will not select investments, name products, forecast returns, or phrase anything as buy/sell. That boundary is not negotiable and is the reason the "never project returns" rule below survives alongside an opinionated advisor.

Voice, enforced in code review:

- Numbers before opinion. Every verdict shows its arithmetic.
- Never "you can't afford that." Always "this costs X, your call."
- No exclamation marks, no emoji, no encouragement filler, no "you've got this."
- Never moralise. Never raise the same past mistake twice.
- State setbacks in one neutral sentence, then move to the action.
- The user can always override (except R2). Overrides are logged, never argued with.

## UI principles

- **The dashboard answers one question: am I okay?** If a number doesn't help answer it, it belongs on another screen.
- One recommended action at a time. Never a to-do list of financial obligations.
- Neutral language for setbacks. "Buffer dipped below two weeks" — not "you failed," not "uh oh!"
- No confetti, no gamified guilt, no streak-loss shaming. The streak exists to support logging, and it's presented as information.
- Every destructive action is undoable; every irreversible one is confirmed.
- Empty states explain what to do, not just that there's nothing here.
- Full keyboard navigation, VoiceOver labels on every control showing a number, Dynamic Type respected.

---

## Notifications

All rules live in `Engines/NotificationRules.swift` as declarative data — trigger, condition, timing, cooldown, wording, inline action. Adding a notification means adding a rule, never scattering scheduling calls through feature code.

- Hard cap 4 per day, enforced centrally.
- Quiet hours respected absolutely.
- Every rule has a cooldown so it can't fire twice for the same condition.
- Every notification has an inline action that does the obvious thing.
- A muted app is a dead app. When in doubt, don't send it.

---

## Never

- Make a network call. Not for prices, not for rates, not for crash reports, not for fonts.
- Add analytics or telemetry of any kind.
- Project investment returns or forecast markets. Show contributed principal and let the user enter current value manually.
- Give investment advice, or phrase any output as a recommendation to buy or sell anything.
- Force-unwrap in a money or date path.
- `fatalError` on a path a user can reach.
- Auto-spend from the emergency fund or the tax reserve, or auto-reorder the user's goal priorities.
- Let a windfall merge into spendable balance before it has been allocated.
- Count a refund as income, or a loan to a friend as an asset in net worth.
- Raise a budget envelope automatically because income went up.
- Add an override path to R2 (no borrowing to invest).
- Ship a calculation change without updating its golden test.

---

## Working style

- Work milestone by milestone (see `BUILD_PROMPT.md` §6). Stop at the end of each one and summarise.
- Write the engine and its tests before the view.
- When a calculation isn't specified, implement it, mark it `// ASSUMPTION: <what and why>`, and say so in the summary. Don't invent financial logic quietly.
- Ask before: adding a dependency, changing the schema in a way that needs migration, altering a Ladder threshold or an advisor rule, or anything that touches rounding.
- Commits: `area: imperative summary` (e.g. `LoanEngine: handle flat-rate schedules with irregular final payment`).
- Update `PROGRESS.md` at the end of each milestone: what shipped, what's stubbed, what's assumed, what's next.
