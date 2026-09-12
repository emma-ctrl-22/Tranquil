# Tranquil — project documentation

A local-first macOS personal finance app. This document describes how it is built, how
the pieces fit together, and the rules that must not be broken when changing it.

`BUILD_PROMPT.md` is the product spec · `ADVISOR_RULES.md` is the rule book for the
opinionated layer · `CLAUDE.md` is the working agreement · `PROGRESS.md` is the
milestone-by-milestone record.

---

## 1. What the app is for

One person's daily money life: micro-spends, weekly envelopes, several accounts, loans
owed, things they are saving for, and a staged path to stability. The goal is
**stability, not wealth optimisation**.

The single most important quality: **logging a ₵5 bus fare takes under three seconds.**
Anything that makes capture slower is a regression, whatever it adds.

---

## 2. Architecture

```
MyFinances/
  Core/
    Money/      Money, Currency, MoneyFormatter
    Time/       FinancialCalendar
    Parsing/    QuickParser
    Design/     Theme — every colour, radius, spacing and type token
  Models/       SwiftData @Model types only. No business logic.
  Engines/      Pure functions over value types. No SwiftData, no UI, no writes.
  Features/     One folder per screen.
  Services/     Persistence-adjacent work: notifications, backup, export, lock, seeds.
```

### The rule that holds it together

**Engines are pure.** They take value types in and return value types out. They never
read `@Environment`, never touch SwiftData, never schedule a notification, never write
anything. That is what makes the money logic testable, and the money logic is the app.

`Features/Shell/DataBridge.swift` is the **only** place SwiftData models and engine
value types meet. If you find yourself passing an `@Model` into an engine, the bridge is
where that conversion belongs.

### The engines

| Engine | Answers |
|---|---|
| `BalanceEngine` | What is every balance, what is available, what was spent, does the ledger match reality |
| `BudgetEngine` | Envelope budgets, burn rate against pace, free-to-spend, expected income |
| `ForecastEngine` | Where the balance goes over the next 60 days, and which day breaks |
| `LoanEngine` | Schedules, payoff order, extra-payment simulation, the verdict before you sign |
| `GoalEngine` | The allocation waterfall, goal ETAs, cost-in-time, the overspend ledger |
| `LadderEngine` | Which of the seven stages you are on, the stability score, the one next action |
| `IncomeEngine` | Windfall interception, allocation splits, salary checks and rises, lifestyle creep |
| `InvestmentEngine` | Contributed principal against entered value, contribution consistency |
| `AdvisorEngine` | Order of Operations, hard rules R1–R11, verdicts, the monthly letter |
| `ReviewEngine` | The weekly and monthly reviews |
| `InsightsEngine` | Heatmap, streaks, category rollups, debt burn-down |
| `NotificationRules` | Every notification as declarative data, and the single delivery gate |

---

## 3. Money

These rules are absolute.

1. **Never `Double` or `Float` anywhere near an amount.** Not in a model, a view, or a
   temporary. The only exception is handing a value to Swift Charts for pixels, which is
   marked as such at every site and never feeds a total back.
2. All amounts are `Int` **minor units** (pesewas). `Money` wraps that `Int`.
3. Only `MoneyFormatter` turns an amount into a string or a string into an amount.
4. **Rates and percentages are `Decimal`**, stored as basis-point `Int`s.
5. Rounding is **banker's**, applied once, at the final step — never intermediate.
6. **Splitting money must not lose or create it.** `Money.split(into:)` distributes the
   remainder across the first parts; `Money.allocate(by:)` uses largest-remainder. Both
   assert the total. Every schedule, proration and allocation goes through them.
7. `Money` is never optional to mean zero. Use `.zero`.
8. **Amounts are stored positive.** Direction comes from `Transaction.kind`. There are no
   negative amounts in the database.

---

## 4. Time

`FinancialCalendar` is injected everywhere. **Nothing else calls `Date()` or
`Calendar.current`.**

A **financial day is represented by the instant it starts** — midnight plus the boundary
hour (04:00 by default), not midnight. This makes `financialDay(for:)` idempotent, which
every piece of day arithmetic depends on.

Two things this gets right that are easy to get wrong:

- A 01:30 spend belongs to the **previous** financial day.
- The day boundary is built by **setting the wall-clock hour**, not by adding an interval.
  On a daylight-saving morning, midnight plus four hours is 05:00 — which would silently
  corrupt one day's streak, heatmap cell and weekly total every year.

Month arithmetic **clamps**: "monthly on the 31st" is 28 or 29 February, never a skipped
month.

---

## 5. Data rules

- **Balances are derived**, never stored as mutable state. `BalanceSnapshot` is only ever
  a cache; if it and the ledger disagreed, the ledger wins.
- A transfer is **one** `Transaction` with a `counterAccount`. Transfers never appear in
  income or expense totals.
- **Soft delete only** (`deletedAt`). Every query filters deleted rows.
- Invariant: `sum(earmarks on an account) <= account.balance`. When violated, the account
  is **over-committed** — surfaced as a warning, never silently rebalanced.
- A **receivable** (money lent out) is never an asset in net worth (R11).
- A **tax reserve** account is not spendable, holds no goal earmarks, and is excluded from
  net worth, runway and free-to-spend.

### Where each kind of money movement is recorded

| What happened | What gets written |
|---|---|
| A spend | one `Transaction` (`.expense`) |
| Money between your own accounts | one `Transaction` (`.transfer`) with `counterAccount` |
| A repeating bill posted | one `Transaction`, and the `RecurringRule` rolls to its next date |
| Income recorded | one `Transaction` (`.income`), plus a transfer to the tax reserve if any, plus an `IncomeEvent` |
| A windfall allocated | `IncomeAllocation` rows, plus earmarks and transfers that carry them out |
| A loan payment | a `LoanPayment` (debt down, split principal/interest) **and** a `Transaction` (money out), linked by id |
| An investment valuation | a `Valuation` row. It moves no money and changes no balance. |
| Reconciling | one visible "Unaccounted" `Transaction`, flagged as an estimate |

---

## 6. Single sources of truth

Places where two things could disagree, and which one wins.

| Question | Authority |
|---|---|
| An account's balance | The ledger, always. Derived by `BalanceEngine`. |
| A loan's outstanding balance | Principal actually paid off (`LoanPayment` rows). The schedule is only the fallback before any payment exists. |
| The emergency fund balance | The earmark against the emergency `SinkingFund`. The `Account.isEmergencyFundAccount` flag is a fallback used only when no such fund exists. |
| Emergency fund target | `AppSettings.emergencyFundMonths`. `recommendedEmergencyFundMonths` is advice shown in Settings, never applied behind your back. |
| Expected income | `AppSettings.expectedMonthlyNetIncome`, spread as `x 12 / 52`. The 8-week median governs irregular income only. |
| What an investment is worth | Only a `Valuation` you entered. The app never guesses, and an unvalued holding has **no** gain rather than a gain of zero. |
| Whether a rule may notify | `NotificationRules.shouldDeliver`, the single gate. |

---

## 7. The Advisor

A **deterministic rule engine**, not a model. No network, identical output for identical
input, and every verdict traceable to a rule ID.

It advises on **behaviour only** — how much, in what order, held where, what a decision
costs. It never selects investments, names products, forecasts returns, or phrases
anything as buy or sell.

**R2 (no borrowing to invest) is the one rule with no override path.** Every other rule
can be overridden with a typed reason, which is logged permanently and totalled in the
monthly review without commentary.

Voice, enforced by tests:
- Numbers before opinion; every verdict shows its arithmetic.
- Never "you can't afford that". Always "this costs X, your call."
- No exclamation marks, no emoji, no encouragement filler.
- Setbacks stated in one neutral sentence, then the action.

---

## 8. Notifications

Every rule lives in `Engines/NotificationRules.swift` as declarative data — trigger,
wording, timing, cooldown, inline action. **Adding a notification means adding a rule**,
never a scheduling call in feature code.

- Hard cap of 4 a day, enforced centrally.
- Quiet hours are **absolute**, even for urgent rules.
- Every rule has a cooldown so it cannot fire twice for one condition.
- Only four rules may exceed the daily cap: loan due, bill due, account below floor,
  projected negative day. Money about to go wrong.

A muted app is a dead app. When in doubt, it does not send.

---

## 9. Privacy

The app makes **no network calls of any kind**. No accounts, no sync, no telemetry, no
analytics, no crash reporting, no bank connections. Notifications are scheduled on-device
by macOS. The whole database is one local file.

This is why prices, exchange rates and fund values are entered by hand: there is nowhere
to fetch them from, by design.

---

## 10. Building and testing

```bash
xcodebuild -scheme MyFinances -destination 'platform=macOS' build
xcodebuild -scheme MyFinances -destination 'platform=macOS' \
           -parallel-testing-enabled NO -only-testing:MyFinancesTests test
```

**Always run tests serially.** In parallel, a crashed worker reports every test it had not
yet reached as "failed", which buries the real failure. Serial output gives a clean
`✔`/`✘` per test.

Current state: **357 tests, 0 failures, no warnings.**

### Testing rules
- Any function touching money gets a test with a **hand-checked** expected value — not a
  test asserting the function equals itself.
- Boundaries get their own tests: exactly-on-the-line cases, empty databases, zero
  denominators, and the day a clock changes.
- Changing a calculation means updating its golden test in the same commit.

---

## 11. Adding things

**A new engine:** pure functions, value types in and out, tests before the view.

**A new screen:** add a case to `AppModel.Screen`, add it to the sidebar group, add it to
`RootView.content`, and — required — **give it representation on the Dashboard**. One
glanceable figure in the module strip; escalate to a notice only when something is
actually wrong.

**A new model:** add it to `TranquilSchema.models` (a test asserts the count) and update
the schema count test. Additive properties migrate automatically.

**A new threshold:** it goes on `AppSettings` as basis points with a computed `Decimal`
accessor, gets a control in Settings → Thresholds, and gets a test proving it changes
behaviour. Nothing that shapes a financial judgement stays hardcoded.

---

## 12. Known gaps

- `monthsAllStagesHeld` is always 0, so **Ladder stage 7 is unreachable** until recorded
  history exists. Honest, but untested against real data.
- Notification **inline actions** are wired as categories; their handlers post an in-app
  event rather than performing the action.
- `BalanceSnapshot` is never written; net worth history is reconstructed from the ledger
  each time. Correct, and fast enough at 5,000 transactions.
- The **ladder-gap slice** of a windfall allocation is recorded but not automatically
  carried out — where it should land depends on your current step, so the app names the
  step rather than guessing.
- Payoff-order scoring weights are editable in code, not in the UI.
