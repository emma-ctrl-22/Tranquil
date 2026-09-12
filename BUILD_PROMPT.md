# Build Prompt — "Tranquil" (personal finance Mac app)

> Paste this whole file as your opening message in Claude Code. Fill in the `FILL IN` blocks first.
> Then say: *"Read CLAUDE.md, then start Milestone 0. Stop at the end of each milestone and show me what you built."*

---

## 0. Fill these in before you start

```
CURRENCY_CODE:        FILL IN (e.g. USD, GHS, EUR) — single currency, no FX conversion anywhere
WEEK_STARTS:          Monday
FINANCIAL_DAY_STARTS: 04:00  (a 01:00 taxi ride belongs to the previous day)

BIRTH_YEAR:           2002   (age 24 — derived, never stored as a fixed number)
INCOME_TYPE:          FILL IN — salaried | freelance | mixed
DEPENDENTS:           FILL IN
TAX_RESERVE_RATE:     FILL IN % — confirm with a local professional
HIGH_INTEREST_APR:    FILL IN % — the line above which debt gets cleared before investing
MY ACCOUNTS:          FILL IN — name, type, current balance
                      types: cash | bank | mobile money | savings | investment | credit | receivable
TYPICAL MICRO-SPENDS: FILL IN — the 8 things you pay for most (bus fare, water, lunch, data, …)
ESSENTIAL CATEGORIES: FILL IN — rent, food, transport, utilities, data… (used to size the buffer)
MY LOANS:             FILL IN — lender, amount, rate, type, repayment, who it's owed to
LOANS I MIGHT TAKE:   FILL IN
THINGS I WANT:        FILL IN — item, price, how badly (1–5)
```

---

## 1. What I'm building

A **local-first macOS app** that I will open ten times a day. Its job is not to make me rich — it is to make me **stable**: never surprised by a bill, never late on a loan, never wondering where the money went, and always knowing how far away the next thing I want is.

It lives in the **menu bar**. Logging a bus fare must take under three seconds or I will stop using it, and the whole thing dies.

Success looks like: after 60 days I can open it and answer, in one glance —
*Am I okay? What's coming? What do I owe? What's next to clear? When do I get the thing I want?*

---

## 2. Non-negotiable constraints

1. **Native macOS 14+, SwiftUI, SwiftData.** No Electron, no web view.
2. **Runs as a menu bar agent** (`LSUIElement = true`) with an optional main window, and **launches at login** — otherwise scheduled notifications won't fire reliably.
3. **100% offline.** No network calls. No accounts, no sync service, no telemetry, no bank APIs. If a feature needs the internet, don't build it.
4. **Money is never a `Double`.** Integer minor units only (see CLAUDE.md).
5. **Balances are derived**, never stored as editable state.
6. **Nothing is ever hard-deleted** — soft-delete with an undo window.
7. Entry speed budget: **quick capture ≤ 3 seconds**, full transaction form ≤ 15 seconds.
8. Dark mode and keyboard navigation from day one, not retrofitted.

---

## 3. Domain model

Use SwiftData. Every model gets a `UUID id`, `createdAt`, `updatedAt`, `deletedAt: Date?`.

### Account
```
name, type (cash|bank|mobileMoney|savings|investment|credit|receivable)
openingBalance: Int (minor units)
colorHex, icon, sortOrder
includeInNetWorth: Bool
isLiquid: Bool            // can I spend from this today?
lowBalanceFloor: Int?     // alert below this
isArchived: Bool
```
Derived: `balance`, `earmarkedTotal`, `available = balance - earmarkedTotal`.

### Transaction
```
date, amount: Int (always positive — direction comes from kind)
kind: .income | .expense | .transfer
account            // source for expense/transfer, destination for income
counterAccount?    // destination, transfers only
category?, subcategory?
note?, tags: [String]
isEstimate: Bool          // logged from memory, flag for later correction
recurringRuleID?, loanID?, goalID?, sinkingFundID?
attachmentPath?           // local receipt photo
```
A transfer is **one** record, not two. Never let a transfer touch income or expense totals.

### Category
```
name, group, icon, colorHex
isEssential: Bool         // feeds the buffer/runway math
isMicro: Bool             // bus fare, water — shown as quick-capture chips
defaultAccount?
```

### Budget
```
category?                 // nil = the catch-all Miscellaneous envelope
period: .weekly | .monthly
amount: Int
rollover: Bool, rolloverCapMultiple: Double (default 2.0)
```

### RecurringRule
```
label, kind, amount, category?, account, counterAccount?
cadence: .weekly | .biweekly | .monthly(day) | .yearly(month,day) | .custom(days)
nextDueDate, endDate?
mode: .autoPost | .remindOnly     // default .remindOnly
isVariableAmount: Bool            // utilities — remind, don't assume
```

### Loan
```
name, lender, direction: .iOwe | .owedToMe
principal: Int, currentBalance derived from payments
interestModel: .amortizing(apr) | .flatRate(rate, years) | .interestFree | .revolving(apr)
startDate, termMonths, paymentFrequency, scheduledPayment: Int
status: .planned | .active | .paid | .defaulted
socialWeight: 0...5       // 5 = borrowed from family, costs me sleep
lateFee?, notes
```

### LoanPayment
```
loan, date, amount, principalPortion, interestPortion, feePortion, isLate: Bool, transactionID?
```

### Goal  *(this covers wishlist items too)*
```
name, targetAmount: Int, targetDate?
priorityRank: Int         // manual, drag to reorder
holdingAccount            // where the money physically sits while saving
monthlyCap: Int?          // don't throw everything at one goal
desireLevel: 1...5
status: .saving | .funded | .purchased | .abandoned
actualPricePaid: Int?     // for overspend variance
```
A goal's saved amount is an **Earmark** against `holdingAccount`, not a separate balance.

### Earmark
```
ownerType: .goal | .sinkingFund | .emergencyFund
ownerID, account, amount: Int
```
Invariant: `sum(earmarks on account) <= account.balance`. If violated, the account is **over-committed** — raise a visible warning, do not silently allow it.

### SinkingFund
```
name (Gifts, Emergency, Rent, Repairs, Social obligations, Annual insurance…)
targetAmount, targetDate?, cadence
requiredPerPeriod derived
holdingAccount
isEmergencyFund: Bool
```

### ScheduledEvent
```
label, expectedDate, expectedAmount, sinkingFund?, confidence: .certain|.likely|.maybe
```
Birthdays, weddings, funerals, school fees, annual renewals. Feeds the cash-flow calendar.

### Supporting
```
DailyLog       — date, entryCount, wasReconciled   (powers the heatmap)
LadderState    — stage, enteredAt, evidence snapshot
BalanceSnapshot— date, accountID, balance          (nightly, for fast charts)
```

---

## 4. Features

### F1 — Quick capture (build this early, obsess over it)
- Menu bar icon → popover. Global hotkey **⌥⌘E** opens it from anywhere.
- **Chips**: the six most-used micro categories, each one tap + amount. Tapping "Trotro" prefills category, account, and last amount.
- **One-line parser**: `trotro 5`, `15 lunch momo`, `-40 data`, `5000 salary`. Parse amount, category keyword, account keyword, note. Show a live preview of what will be saved; Enter commits; Esc cancels.
- **Batch mode**: an empty row appears after each save so five spends take one pass.
- "I spent something, not sure what" → logs to Miscellaneous with `isEstimate = true` and adds it to a **Needs review** queue.
- Every save shows a 5-second undo toast.

### F2 — Accounts, transfers, reconciliation
- Account list with balance, available (balance − earmarks), and a warning badge if over-committed.
- Transfers between any two accounts, including cash → mobile money → bank chains. Common pairs get a saved shortcut.
- **Reconcile**: enter the real-world balance, app shows the gap, and offers to post a single balancing "Unaccounted" adjustment. Records `wasReconciled` for that day.
- Nag if no account has been reconciled in 14 days.

### F3 — Budgets, weekly first
- Weekly budgets are the primary unit; monthly budgets display a weekly pace of `monthly × 7 / daysInMonth`.
- **Miscellaneous is a real, first-class envelope**, not a leftover. It gets its own weekly number and its own burn meter, because that's where discipline actually breaks.
- Burn meter per envelope:
  ```
  burn     = spentThisWeek / budgetThisWeek
  expected = elapsedDaysInWeek / 7
  alert when burn - expected > 0.25
  ```
- Rollover (optional per envelope), capped at 2× so unspent weeks don't become a licence to splurge.
- **Free to spend this week** — the number I actually look at:
  ```
  freeToSpend = expectedIncomeThisWeek
              - proratedCommittedOutflows   (loans + investments + sinking funds + recurring bills)
              - goalAllocationsThisWeek
              - alreadySpentThisWeek
  ```

### F4 — Income
- Regular income as recurring rules; irregular income logged ad hoc.
- If income is lumpy, compute `expectedWeeklyIncome` as the **trailing 8-week median**, not the mean — one good month shouldn't inflate every projection.
- Flag when expected income hasn't arrived by T+2 days.

### F5 — Investments (the monthly deduction)
- A recurring rule with `kind = .transfer` into an investment account, marked as a **committed outflow** so it comes off the top, before free-to-spend.
- Track contribution streak: months contributed out of last 12.
- Show contribution rate as % of net income. Do **not** project market returns — that's fiction; show contributed principal only, and let me enter a current value manually if I want.

### F6 — Loans I owe
- Schedule generation:
  - Amortizing: `payment = P·r / (1 − (1+r)^−n)`, `r = apr/12`
  - Flat rate: `total = P·(1 + rate·years)`, `payment = total / n`
  - Interest-free: `payment = P / n`
- Per loan: remaining balance, payments made vs scheduled, total interest remaining, projected payoff date, late count.
- **Extra payment simulator**: "if I add X per month → payoff moves from A to B, saves Y in interest."
- Payoff order presets, each showing the resulting total interest and total months:
  - **Avalanche** — highest APR first (cheapest)
  - **Snowball** — smallest balance first (fastest wins)
  - **Peace of mind** — `socialWeight` first (the loans from family that make me avoid phone calls)
  - **Balanced** — scored: `w₁·normAPR + w₂·(socialWeight/5) + w₃·smallBalanceBonus + w₄·dueUrgency`, weights editable
- Show me the cost of choosing peace over maths, plainly, and let me choose anyway.

### F7 — Loans I'm about to take
- Create a `.planned` loan and get a verdict **before** signing:
  - New monthly debt service, and debt-service ratio `= monthlyDebtPayments / medianMonthlyNetIncome`
  - New weekly free-to-spend
  - Every goal ETA that slips, and by how long
  - Which Ladder stage this knocks me down to
  - Total interest paid over the life
  - Verdict: **Comfortable** (DSR < 15%) / **Tight** (15–30%) / **Don't** (>30% or it breaks the buffer)
- "Compare against: not borrowing and saving for N months instead" — show both side by side.

### F8 — The Tranquility Ladder
The hierarchy of what to clear, in order. The app computes which stage I'm on and shows **one next action** — never a list of twelve.

| # | Stage | Cleared when |
|---|---|---|
| 0 | **Visibility** | ≥21 of last 28 days logged, and an account reconciled within 7 days |
| 1 | **Two-week buffer** | liquid available ≥ 2 weeks of essential spend |
| 2 | **No obligation is late** | zero overdue loan payments for 60 days; next 30 days of recurring bills fully covered by projected balance |
| 3 | **Toxic debt gone** | every loan with APR > 25% **or** socialWeight ≥ 4 is at zero |
| 4 | **Emergency fund** | ≥ 3 months essential spend, earmarked, in a designated account, untouched for 90 days |
| 5 | **Sinking funds current** | every sinking fund at or above its required-to-date balance |
| 6 | **Debt is small and cheap** | debt-service ratio ≤ 20%, no remaining loan above 15% APR |
| 7 | **Tranquil** | stages 0–6 held simultaneously for 6 consecutive months, and investment contributed in ≥5 of last 6 months |

Rules:
- Stages are checked continuously. Falling back is shown honestly, without shame language — "buffer dipped below two weeks" not "you failed."
- `essentialMonthlySpend` = trailing 3-month **median** of categories where `isEssential`.
- `runwayMonths = liquidAvailable / essentialMonthlySpend` — display prominently.
- **Stability Score 0–100**, weighted and always broken down into its parts so it's never a mystery number:
  `runway 30 · debt-service 20 · on-time payment history 15 · logging consistency 10 · sinking funds coverage 10 · budget adherence 10 · investment consistency 5`

### F9 — Goals, wishlist, and the iPhone question
For any goal, answer all four parts:
1. **How long?** ETA date, from the allocation engine below.
2. **Which account should it go into?** → `holdingAccount`, chosen when the goal is created; suggest the highest-yield liquid account that isn't the daily spending account.
3. **Where is it sitting now?** → current earmark balance, and which account physically holds it.
4. **What does it cost me?** → which other goals slip, and by how long.

**Allocation engine** — each period, projected surplus flows down a waterfall:
```
1. Current Ladder stage requirement   (buffer top-up, toxic debt payment…)
2. Sinking funds due this period
3. Goals in priorityRank order, each capped at monthlyCap
4. Remainder → investment / next stage
```
```
ETA = first period where cumulative allocation ≥ (targetAmount − currentEarmark)
```
Always render the lever alongside it: *"₮ 250/week → 14 Mar. At ₮ 400/week → 2 Feb."* And a slider to feel that tradeoff live.

**Wishlist extras**
- Price watch is manual (no internet): I enter the price and the date I checked.
- When purchased, record `actualPricePaid` and show the variance vs planned. Accumulate an **overspend ledger**: "wishlist items came in ₮ X over plan this year."
- A **cool-off timer** on any goal above a threshold I set — created goals above it stay `.saving` for 7 days before they can be marked purchased without a confirmation prompt.

### F10 — Sinking funds: gifts, emergencies, the predictable surprises
- A sinking fund is a target + a date + a holding account. `requiredPerPeriod = (target − saved) / periodsRemaining`.
- Prebuilt: Emergency, Gifts, Social obligations, Rent, Repairs & replacements, Health, Annual renewals.
- `ScheduledEvent` entries (birthdays, weddings, funerals, school fees) auto-size the Gifts and Social funds twelve months ahead.
- **Emergency fund is special**: it's a Ladder requirement, it can't be auto-raided by the allocation engine, and spending from it requires an explicit confirm and logs a reason.

### F11 — Cash-flow calendar (the "will I be short on the 24th" view)
- 60-day forward projection: today's liquid balance, plus recurring income, minus recurring bills, loan payments, scheduled events, committed contributions.
- Line chart plus a day grid. **Any day projected below zero, or below an account's floor, is flagged in red with the reason and a suggested fix** ("move the ₮ X transfer three days later" / "this week's misc envelope is ₮ Y over pace").

### F12 — Notifications
All **local** notifications (`UNUserNotificationCenter`). Declarative rules in one file. Global quiet hours and a **hard cap of 4 per day** — over-notifying is how apps get muted, and a muted app is a dead app.

| Trigger | Timing |
|---|---|
| Nothing logged today | 20:30 |
| Nothing logged and streak ≥ 5 | 22:00, stronger wording |
| Envelope burn > expected + 25% | once per envelope per week |
| Misc envelope past 60% before Wednesday | once per week |
| Loan payment due | T−3 and morning of T |
| Recurring bill due | T−2 |
| Expected income not received | T+2 |
| Single expense > 1.5× category median | immediately, "confirm this?" |
| Account below `lowBalanceFloor` | on breach |
| Projected negative day inside 14 days | on detection, once |
| Goal hits 25 / 50 / 75 / 100% | on crossing |
| Weekly review | Sunday 18:00 |
| Monthly review | last day of month, 19:00 |
| Nothing reconciled in 14 days | 10:00 |
| Ladder stage gained or lost | on change |

Every notification has an inline action that does the obvious thing: *Log now*, *Mark paid*, *Snooze*, *Open review*.

### F13 — Charts
- **GitHub-style contribution heatmap**, 53×7, three toggleable modes:
  1. *Logged* — intensity = entries that day (this is the discipline habit)
  2. *Spend* — intensity relative to my own trailing median day
  3. *Green day* — binary: stayed inside pace
  Plus current streak, longest streak, and percentage of days logged.
- Net worth line (from `BalanceSnapshot`).
- Debt burn-down, stacked area per loan, with the projected payoff date marked.
- Weekly envelope burn gauges.
- Category breakdown for the month, with month-over-month deltas — and a **micro-spend rollup** that answers "how much did bus fares actually cost me this year?", because that's the number that hides.
- Income vs expense bars, 12 months.
- Goal progress bars with ETA.
- Cash-flow calendar (F11).

### F14 — Reviews
- **Weekly (Sunday)**: spent vs budget per envelope, biggest three expenses, streak, goals moved, anything needing review, and a single suggestion for the coming week.
- **Monthly**: net worth change, savings rate, debt reduced, ladder movement, stability score with its breakdown, overspend ledger, sinking fund health.
- Both are screens with a "copy as text" button, not emails.

### F15 — Data, security, trust
- Local SQLite via SwiftData in the app container.
- Manual **backup to a chosen folder**, plus an automatic weekly backup, keeping the last 12.
- Export CSV and JSON; import CSV with a column mapper for whatever I've already got in a spreadsheet.
- Optional **Touch ID / password lock** on launch and on wake.
- A visible, honest statement in Settings: no network access, ever.

### F16 — Income events: raises, project payments, windfalls
Full rules in `ADVISOR_RULES.md` §4. Build to that document.

```
IncomeEvent
  kind: .projectPayment | .salaryRise | .bonus | .gift | .refund | .assetSale
  grossAmount, taxReserved, directCosts, netUsable
  hoursWorked?          // project payments → effective hourly rate
  clientOrSource?
  allocations: [IncomeAllocation]   // slice → destination, must sum to netUsable
  status: .unallocated | .allocated
```

- **Interception.** Any inflow above `1.5 × medianWeeklyIncome` lands `.unallocated` and is **excluded from spendable balance** until the allocation sheet is completed. This is the highest-value behaviour in the whole app — build it properly.
- Allocation sheet: prefilled with the default splits, every slice draggable, must total 100%, shows the resulting Ladder movement and every goal ETA that improves.
- **Tax reserve account** — `isTaxReserve = true`. Cannot be spent from, cannot hold goal earmarks, excluded from runway and free-to-spend. It is not your money.
- **Salary rise ratchet:** detect the increase, allocate the *delta* per the defaults, and hold every envelope at its current amount. Raising an envelope is a manual action requiring a typed reason, logged.
- **Lifestyle creep chart:** essential spend ÷ net income, monthly, 24 months. Flag two consecutive rising quarters and name the categories responsible.
- **Effective hourly rate** per project and rolled up per client, trailing 12 months.
- **Income concentration:** if one source > 60% of trailing 12-month income, raise the emergency fund target from 3 months to 6 and surface it in the monthly review.
- **Refunds are not income.** They reverse the original expense. Never count toward income, savings rate, or a good month.

### F17 — The Advisor
A **deterministic rule engine**, not a language model — the app has no network, so this is plain Swift over `ADVISOR_RULES.md`. Implement as `Engines/AdvisorEngine` with the rules as declarative data, same pattern as `NotificationRules`.

- **Verdicts** on every significant decision: Approved · Approved with conditions · Not advised · Blocked. Always with the arithmetic visible.
- **Hard rules R1–R11** block in the UI. Override requires a typed reason and writes an `OverrideLog` entry. **R2 (no borrowing to invest) has no override path.**
- **Order of Operations** (§2) rendered as a ladder with a marker on your actual step. The Tranquility Ladder is *where you are*; the Order of Operations is *what the next unit of money does*. Show them side by side.
- **Cost-in-time preview** on any expense above a threshold: "₮1,200 = 3 weeks of the iPhone goal."
- **Protected earning-power budget line** — skills, tools, courses. Treated as investment, not discretionary. The advisor defends it when you cut.
- **Monthly letter** (§6), generated from templates plus real numbers. No exclamation marks, no emoji, no encouragement filler.
- **Override log** totalled in the monthly review: how many times you overrode, and what it cost. Present the number, add no commentary.
- Voice: never "you can't afford that." Always "here is what it costs, your call."

---

## 5. Screens

| Screen | Contains |
|---|---|
| Menu bar popover | Quick capture, today's total, free-to-spend, streak dot |
| **Dashboard** | Free to spend this week · runway · stability score · next ladder action · upcoming 7 days · today's log |
| Ledger | Transaction list, filters, search, bulk edit, needs-review queue |
| Accounts | Balances, available vs earmarked, reconcile, transfers |
| Plan | Envelopes and burn meters · recurring rules · cash-flow calendar |
| Debt | Loans owed, payoff order, simulator, planned-loan verdict |
| **Income** | Windfall inbox, allocation sheet, effective hourly, creep chart, tax reserve |
| **Advisor** | Order of Operations ladder, active rules, override log, monthly letter |
| Goals | Wishlist, ETA, holding accounts, allocation waterfall, sliders |
| Insights | Heatmap, net worth, category rollups, micro-spend rollup |
| Ladder | The seven stages, where I am, evidence, history |
| Settings | Currency, week start, day boundary, notifications, quiet hours, backup, lock |

---

## 6. Build order

Stop after each milestone. Show me a working build and a short note on what changed.

- **M0 — Foundations.** Project, `Money` type, full SwiftData schema, seed data, formula unit tests. No UI beyond a debug list.
- **M1 — Ledger.** Accounts, transactions, transfers, reconciliation, main window.
- **M2 — Quick capture.** Menu bar agent, hotkey, chips, parser, batch mode, undo, launch at login, plus the one daily "nothing logged" notification.
- **M3 — Budgets.** Weekly envelopes, Miscellaneous envelope, burn meters, free-to-spend, rollover.
- **M4 — Forward view.** Recurring rules, committed outflows, scheduled events, sinking funds, cash-flow calendar.
- **M5 — Debt.** Loans, schedules, payments, payoff orders, extra-payment simulator, planned-loan verdict.
- **M6 — Goals.** Earmarks, allocation waterfall, ETA engine, wishlist, overspend ledger, cool-off.
- **M7 — Ladder.** Stage engine, stability score, weekly and monthly reviews.
- **M7.5 — Income events & Advisor.** Windfall interception, allocation sheet, tax reserve account, salary-rise ratchet, creep chart, AdvisorEngine with R1–R11, verdicts, override log, monthly letter. Build to `ADVISOR_RULES.md`.
- **M8 — Polish.** Heatmap and all charts, full notification engine, backup, export/import, app lock, keyboard shortcuts, empty states.

**Definition of done for every milestone:** compiles with no warnings · unit tests pass for any money or date logic · works with an empty database · works with 5,000 transactions without lag · dark mode correct · keyboard-navigable.

---

## 7. Ask me, don't assume

Stop and ask if you hit any of these:
- My income is irregular in a way the 8-week median handles badly
- A loan's terms don't fit any of the three interest models
- A Ladder threshold feels wrong for my actual numbers
- Any feature that would require network access
- Any place where rounding could lose or create money

- A hard rule in `ADVISOR_RULES.md` would block something I clearly need to do
- A default allocation split feels wrong against my real numbers

**Never invent financial logic silently.** If a calculation isn't specified here, write the function, add a `// ASSUMPTION:` comment stating what you chose and why, and tell me in your summary.
