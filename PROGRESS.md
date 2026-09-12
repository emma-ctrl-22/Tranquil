# PROGRESS

## M0 — Foundations ✅

### What shipped

**Core/Money**
- `Money` — `Int` minor units, `Sendable`, `Comparable`. No `Double` or `Float` exists anywhere in the codebase.
- Banker's rounding, applied once at the final step (`Money.roundBankers`, `scaled(by:)`).
- `split(into:)` — remainder pesewas across the first N parts, asserts the sum.
- `allocate(by:)` — largest-remainder proportional split, deterministic, asserts the sum.
- `Currency` (GHS default) and `MoneyFormatter`, the only place a currency string is made or parsed.

**Core/Time**
- `FinancialCalendar` — injected everywhere; nothing else calls `Date()` or `Calendar.current`.
- A financial day is represented by **the instant it starts** (midnight + boundary hour), which makes `financialDay(for:)` idempotent. Midnight-based day values were not, and broke week and month arithmetic.
- 04:00 boundary, Monday weeks, month-end clamping, DST-safe day construction.

**Models** — all 18 `@Model` types registered in `TranquilSchema`. Enums with associated values (`Loan.InterestModel`, `RecurringRule.Cadence`) are decomposed into stored columns with a computed façade, because SwiftData cannot store them directly. Rates are stored as basis-point `Int` and exposed as `Decimal`.

**Services** — `SeedData`: deterministic Ghana demo dataset, the 5,000-transaction stress generator, and `wipe`.

**Features/Debug** — `DebugDataView`, M0's only UI.

**Tests** — ~90 tests, every expected value hand-checked.

### What is stubbed
- No engines yet. `BalanceEngine` and the rest arrive with M1 onward; the debug view shows opening balances only, not derived ones.
- No menu bar agent, no `LSUIElement`, no launch-at-login — that is M2.
- No migration tests: there is only one schema version so far.

### Assumptions made (CLAUDE.md requires these be stated, not invented quietly)
1. **`ScheduledEvent.projectionWeight`** — a `.maybe` event counts at 50% in cash-flow projections; `.certain` and `.likely` at 100%. Zero would let "maybe" surprises hit unfunded; 100% would over-reserve.
2. **`expectedWeeklyIncomeFromSalary`** — a monthly salary is regular but lumpy. F4's trailing 8-week median of *weekly* income reads ₵0 in the three weeks a salary does not land, which would collapse free-to-spend. The salaried component is spread as `monthly x 12 / 52`; the 8-week median still governs genuinely irregular income. `IncomeEngine` combines the two in M4.
3. **Thresholds**, all editable settings rather than constants: tax reserve 25%, high-interest 25% APR, DSR cap 30%, speculation cap 5%, emergency fund 6 months, windfall trigger 1.5x.
4. **`Money.allocate(by:)` tie-breaking** — equal remainders resolve by original order, so allocation output is reproducible across runs.

### Owner profile as configured
GHS · Monday weeks · 04:00 day boundary · born 2002 · income type mixed ·
net salary ₵3,500/month on the 28th (editable; a raise is handled by the §4b ratchet, not by moving the baseline).

---

## M1 — Ledger ✅

### What shipped

**`Engines/BalanceEngine`** — the only thing that computes a balance. Pure functions over
value types; `DataBridge` is the single place SwiftData models and engine records meet.
- `balance = opening + movement`, `available = balance − earmarks`, `asOf:` for history.
- A transfer debits the source and credits the destination from **one** record, and is
  excluded from spend and income totals by construction.
- Tax reserve excluded from net worth, liquid available and runway. Receivables excluded
  from net worth (R11). Archived accounts excluded from every total.
- Over-commitment is reported with its real negative `available`, never clamped away.
- `reconcile(derived:actual:)` plus the 14-day nag.

**UI shell** — one window: sidebar, content, inspector panel, sheets.
`Core/Design/Theme.swift` holds every colour, radius, spacing and type token.
- **Dashboard** — available to spend, net worth, earmarked, spent this week, warning
  banners (over-committed, below floor, reconcile overdue), today's log, account tiles.
- **Ledger** — grouped by financial day with sticky headers and day subtotals, filters
  including a Needs-review queue, search, soft delete with a five-second undo toast.
- **Accounts** — tiles with balance, available and status pills; create, edit, reconcile.
- **Inspector** (⌥⌘I) — account or transaction detail, with a running summary as fallback.
- **Quick add** (⌘N) — one line in, live preview of exactly what will be saved, micro
  chips that prefill the last amount, batch mode, undo.
- **Transfer** (⌘T) — one record, blocked out of the tax reserve.
- **Reconcile** — shows the gap and posts a single visible "Unaccounted" entry.

**`Services/DailyLogService`** — one row per financial day; entry counts, reconciliation
flags, and the streak. Today not yet being logged does not break a streak.

### What is stubbed
- Plan, Debt, Income, Advisor, Goals, Insights and Ladder are listed in the sidebar and
  say which milestone they arrive in.
- No menu bar agent, hotkey, launch-at-login or notifications yet — that is M2.
- The quick-add parser handles amount, keyword category and note. Account keywords and
  the full grammar (`-40 data`, `5000 salary`) land with M2.
- `BalanceSnapshot` is not yet written nightly; balances derive from the ledger each time,
  which is well inside budget at 5,000 transactions.

### Assumption added
5. **Reconciliation adjustments** are posted as `isEstimate = true` against Miscellaneous,
   so they surface in the Needs-review queue rather than quietly becoming truth.

---

## M2 — Quick capture ✅

### What shipped

**`Core/Parsing/QuickParser`** — pure, vocabulary-driven, 27 tests. Handles every example
in the spec: `trotro 5`, `15 lunch momo`, `-40 data`, `5000 salary`.
- Word order does not matter; matching is case-insensitive and supports aliases
  ("momo", "bus", "gcb") and multi-word names, longest match first.
- An explicit `+`/`-` always beats an income keyword, so `-500 refund` stays an expense.
- A term is consumed once, so one word cannot be both category and account.
- Anything it cannot place stays in the note; `matched` reports what it recognised so
  the preview can show its work. It never guesses silently.

**Menu bar agent** — `LSUIElement`, an `NSStatusItem` with a transient popover.
Left-click or ⌥⌘E captures; right-click gives Open / Settings / Quit.
The popover shows capture, today's spend, available, and the streak.

**`Services/HotkeyService`** — ⌥⌘E via Carbon `RegisterEventHotKey`, which is system-wide
**without** Accessibility permission. If the combination is taken, the app carries on.

**`Services/LaunchAtLoginService`** — `SMAppService`, revocable in System Settings.

**`Engines/NotificationRules`** — all fifteen notifications as declarative data: trigger,
wording, timing, cooldown, inline action. One `shouldDeliver` gate enforces the daily cap
and quiet hours centrally. Tests assert every trigger has exactly one rule, every
time-based rule has a cooldown, no wording contains an exclamation mark or emoji, and
quiet hours are absolute even for urgent rules.

**`Services/NotificationService`** — local `UNUserNotificationCenter` delivery, plus M2's
one live rule: "nothing logged today" at 20:30.

**Settings** — login item, Dock visibility, notification cap, and a plain statement that
the app makes no network calls of any kind.

### Assumptions added
6. **Income keywords** — `salary, wage, paid, payment, income, bonus, refund,
   reimbursement, gift, sold` flip an unsigned line to income. Deliberately few: a false
   positive files a spend as income and corrupts the savings rate, which is worse than
   making the user type `+`.
7. **Cap bypass** — only `loanPaymentDue`, `recurringBillDue`, `accountBelowFloor` and
   `projectedNegativeDay` may exceed the daily cap. Quiet hours bind them anyway.

### Still open
- Notification **inline action buttons** are wired as categories but the handlers only
  post an in-app event; Log now / Mark paid land with the screens they act on.
- Only the daily nudge is scheduled live. The other fourteen rules are defined and
  tested, and get switched on as their data arrives in M3–M7.

---

## M3 — Budgets ✅

### What shipped

**`Engines/BudgetEngine`** — 24 tests, every expected value hand-checked.
- `weeklyBudget` — a weekly envelope is its own pace; a monthly one shows
  `monthly x 7 / daysInMonth`, so ₵310/month is ₵70 a week in a 31-day month and
  ₵77.50 in February.
- `burn = spent / budget`, `expected = elapsedDays / 7`, alert when the gap exceeds 0.25.
  Exactly 0.25 does **not** alert — the spec says greater than.
- An envelope with no budget has `burn == nil` and is never "ahead of pace", rather than
  dividing by zero.
- Rollover capped at `base x capMultiple` (2x by default). Overspending does not create a
  debt that follows you into next week.
- `weeklyCommitted` prorates by cadence: ₵900/month rent is ₵207.69 a week, a ₵520
  annual renewal is ₵10.
- `freeToSpend = expectedIncome − committed − goalAllocations − alreadySpent`, reported
  honestly when negative.
- `medianWeeklyIncome` — median, never mean, so one good month cannot inflate every
  projection.

**Plan screen** — envelope cards with a burn meter and a pace marker showing where you
*should* be, committed-outflows card, and an envelope editor.

**Dashboard** — the hero becomes **Free to spend this week** once there are commitments
to come off the top, showing its arithmetic underneath. Envelopes ahead of pace surface
as neutral notices; the week card shows the five envelopes furthest ahead of pace.

**Anti-creep ratchet (§4b), early** — raising an envelope requires a typed reason, stored
on the budget with its date. Envelopes never rise on their own.

### Assumption added
8. **Dashboard hero** — shows *available to spend* until committed outflows exist, then
   switches to *free to spend this week*. Before there are commitments the two are the
   same number, and the simpler label is the honest one.

---

## M4 — Forward view ✅

### What shipped

**`Engines/ForecastEngine`** — 17 tests.
- `occurrences(of:from:through:)` expands any cadence over a window. Month-end clamps
  rather than skips: monthly-on-the-31st gives 31 Jan, 28 Feb, 31 Mar, 30 Apr.
- A rule whose due date has fallen behind is **caught up silently**, not replayed — a
  three-month-stale rent rule emits the next occurrence, not three missed ones.
- Every loop carries a guard rail, so a malformed cadence cannot hang the app.
- `project(...)` walks the balance day by day, bucketing movements in one pass.
- Reports `firstNegativeDay` and, earlier and more softly, `firstDayBelowFloor`.
- `suggestion(for:)` names the **largest** outflow on the trouble day and what moving it
  would clear. A fix, never a lecture.

**Plan screen, now three tabs**
- *Envelopes* — as M3.
- *Scheduled* — recurring rules with cadence and next due date, sinking funds with
  progress and required-per-period, and upcoming scheduled events.
- *Cash flow* — a 60-day Swift Charts area/line with zero and floor rule marks and a
  marker on the trouble day, a 60-cell day grid coloured by state, and a detail card
  showing exactly what lands on any day you click.

**Recurring rule editor** — full cadence controls, variable-amount and committed-outflow
flags, and auto-post versus remind-only (remind-only is the default).

**Dashboard** — a projected-negative-day notice with its suggested fix.

**Salary-rise detection, groundwork** — editing an income rule's amount stores the
previous one, so §4b can allocate the *delta* rather than letting a raise become the new
baseline. The allocation sheet itself is M7.5.

### Assumptions added
9. **Projection floor** — the cash-flow floor is the **sum** of every account's
   `lowBalanceFloor`, since the projection tracks one combined liquid balance.
   Per-account projection needs per-account forecasting, which the spec does not ask for.
10. **Stale recurring rules** are advanced to the window without emitting the missed
    occurrences. Replaying them would invent transactions that never happened.

---

## M5 — Debt ✅

### What shipped

**`Engines/LoanEngine`** — 30 tests, the most arithmetic-heavy engine in the app.
- `power(_:_:)` does integer exponentiation in `Decimal`. No `pow`, no `Double`: a
  compounding error at the fourth decimal becomes real money over eighteen months.
- Amortising: `payment = P·r·(1+r)^n / ((1+r)^n − 1)` — the same formula without a
  negative exponent. A zero rate degrades to an even split rather than dividing by zero.
- Flat rate: `total = P(1 + rate·years)`. Interest-free: `P / n`.
- **Every schedule's principal sums exactly to the amount borrowed.** The final
  instalment absorbs the rounding; ₵1,000.01 over 7 payments loses nothing.
- Schedules carry a guard rail: a payment that cannot cover the interest ends the
  schedule instead of looping forever.
- Four payoff orders. Balanced scores
  `w1·normAPR + w2·(social/5) + w3·smallBalanceBonus + w4·urgency`, weights editable,
  ties broken deterministically.
- A **receivable is never in the payoff queue** (R11).
- `simulateExtra` — payoff date moves from A to B, saving Y.
- `verdict(...)` — debt-service ratio with its arithmetic; above the cap it is
  **Not affordable** and blocked (R4), and borrowing while toxic debt is outstanding
  raises R1. Zero income reads as ratio 1, never as "comfortable".

**Debt screen** — totals, a strategy picker that states what each order costs relative to
Avalanche, loan cards with progress and payoff date, a schedule table, the extra-payment
simulator, and a receivables section kept out of net worth.

**Planned-loan sheet** — type an amount, rate and term and get the verdict before signing,
with the alternative the spec insists on: saving the same amount instead, and how long
that takes.

### Bug the tests caught
Early settlement on a **flat-rate** loan was dropping the unpaid interest, making the
simulator claim savings that do not exist. On a flat-rate loan the interest is fixed at
signing — paying early shortens the term and saves nothing. The settling instalment now
carries all interest still owed, and the UI says so plainly.

### Assumptions added
11. **Revolving credit** is projected on the same reducing-balance schedule as an
    amortising loan over its term. Real revolving debt has no fixed schedule; treating it
    as amortising gives an honest payoff estimate if you stop borrowing on it.
12. **Verdict bands** — under 15% comfortable, 15–30% tight, above the configured cap not
    affordable. The 15% line is from BUILD_PROMPT F7; the cap is a setting.

---

## M6 — Goals ✅

### What shipped

**`Engines/GoalEngine`** — 18 tests.
- **Waterfall**: Ladder requirement → sinking funds (emergency fund first) → goals in
  manual priority order, each capped → leftover. Tested to never allocate more than the
  surplus, and to allocate nothing rather than going negative when there is no surplus.
- A goal never receives more than it still needs; funded and abandoned goals are skipped.
- **ETA** runs the waterfall forward period by period, so a goal's date accounts for
  everything ahead of it in the queue. That is what makes *"what does it cost me"*
  answerable rather than a guess.
- A goal that never gets funded reports **no ETA** instead of inventing a date.
- `eta(forGoal:atRate:)` drives the lever: ₵250/week → 35 weeks, ₵400/week → 22.
  An exact division does not round up a spurious extra period.
- `costInTime` — "₵1,200 = 3 weeks of the iPhone".
- Overspend ledger totals variance in both directions.

**Goals screen** — one card per goal answering all four questions: how long (with a live
slider), which account holds it, how much is there now, and the price. Purchased items
roll up into an overspend ledger that states the number and adds no commentary.

**Goal editor** — suggests the best liquid non-daily account as the holding account,
monthly cap, desire level, and the 7-day cool-off on anything above the threshold. The
saved amount is written as an **Earmark** against the holding account, never a separate
balance.

### Dashboard — now covers every module
A new `ModuleStrip` gives each module exactly one figure: net worth, spent this week,
60-day low, owed, and the next goal. Each tile opens its screen.

Held against CLAUDE.md's rule that the dashboard answers one question: the strip is
glanceable figures only, and just three things escalate into a notice — a toxic loan, a
projected negative day, and an envelope past pace.

**Debt was backfilled**: M5 shipped without dashboard presence, which was incomplete.

### Assumption added
13. **Dashboard module tiles appear only when they have data.** An empty Debt tile reading
    ₵0.00 is noise on a dashboard whose job is answering "am I okay".

---

## M7 — Ladder ✅

### What shipped

**`Engines/LadderEngine`** — 24 tests, one per stage boundary plus the score.
- All seven stages evaluated against the spec's exact conditions, including the ones
  easy to fudge: 21 of 28 days **and** reconciled within 7; a late payment 59 days ago
  still fails stage 2; the emergency fund untouched for 90 days, not 89; **every**
  sinking fund on track, not most; stage 7 needs six consecutive months **and**
  investing in five of six.
- `currentStage` is the lowest unmet stage — the one you are working on.
- With no spend history the buffer **cannot be claimed** and runway is `nil`. Unknown,
  not passed: otherwise someone who has logged nothing clears stage 1 for free.
- **Stability score** with the spec's weights (30/20/15/10/10/10/5) and a test asserting
  they sum to 100. It always arrives broken into parts with the arithmetic for each.
- Investing scores **months contributed**, never the amount — consistency beats size.
- **One action at a time**, chosen by stage and by what is actually missing, pointing at
  the screen that fixes it. A test asserts no stage ever returns a list.
- A test scans every stage's evidence and the action for shame language and exclamation
  marks.

**`Engines/ReviewEngine`** — 18 tests. Weekly and monthly, deterministic and templated.
The weekly returns exactly **one** suggestion, chosen by what actually moved: poor logging
first (nothing downstream is trustworthy without it), then the worst envelope, then the
review queue. A clean week says "nothing needs changing" with no praise attached.
The monthly headline figure is chosen by rule: ladder move → debt cleared → savings rate
→ net worth.

**`LadderSnapshotBuilder`** — the seam between the store and the pure engine. Essential
spend is a trailing three-month **median**, so one heavy month does not permanently
raise the bar.

**Ladder screen** — current stage, runway, the one next action, the score broken into
seven bars with their evidence, and all seven stages with what each needs.

**Review screen** — weekly and monthly, with "copy as text".

### Dashboard
The **one next action** now sits at the top of the dashboard, above everything else, with
a button that goes to the right screen. Two tiles joined the strip: **Stability** (score
plus current stage) and **Runway** (months of essentials covered).

### Assumptions added
14. **Stability score curves** — runway scores full marks at 6 months; debt service scores
    full at 0% and zero at 40%+. The spec fixes the weights but not the curves.
15. **`monthsAllStagesHeld` is 0 until history exists.** Stage 7 needs six months of
    recorded evaluations; the app has none yet, so Tranquil is correctly unreachable
    rather than falsely claimable. `LadderState` snapshots will feed it.

---

## M7.5 — Income events and the Advisor ✅

### What shipped

**`Engines/IncomeEngine`** — 24 tests.
- **Interception**: anything above `1.5 x medianWeeklyIncome` lands `.unallocated` and is
  excluded from spendable balance. With **no** income history nothing is intercepted —
  otherwise the first entry ever made would be held hostage.
- R3 tax reserve on untaxed kinds only; salary, gifts and refunds reserve nothing.
- §4a split 40/25/20/15 and §4b split 40/30/20/10, both asserted against the spec, and
  `allocate` proven to lose nothing on an awkward total.
- Effective hourly rate, and client roll-ups sorted by what the work actually pays.
- Concentration: one source **over** 60% raises the emergency target to 6 months.
  Exactly 60% does not.
- Salary rise returns the **delta** only; a cut or a flat month is not a rise.
- Creep needs **three** quarters, each higher than the last. One bad quarter does not
  trip it, and a month with no income has no ratio rather than breaking the chart.

**`Engines/AdvisorEngine`** — 27 tests.
- All eleven rules as declarative data. A test asserts **only R2** has no override path.
- Order of Operations as an eleven-step ladder; the advisor never recommends a step while
  an earlier one is unmet. Tested at each precedence boundary — tax reserve outranks
  everything, the employer match outranks clearing 30% debt.
- `assess(...)` returns a verdict with every finding's rule ID and **the arithmetic**.
- Tests assert the output never contains "cannot afford", never an exclamation mark, and
  is byte-identical across runs.
- `monthlyLetter` — §6 structure, at most two things to change, and the creep check.

**Income screen** — windfall inbox, the tax-reserve card, effective hourly per client,
and the 24-month lifestyle-creep chart.

**Allocation sheet** — the §4a arithmetic, draggable slices, and a hard requirement that
they total 100% before it commits.

**Advisor screen** — Order of Operations with a marker on your actual step, the rule book,
the monthly letter with copy, and the override log totalled without commentary.

### Dashboard
Two tiles added — **Waiting to allocate** and **Next money goes to** (the Order of
Operations step) — plus notices for held windfalls and for creep.

### Assumptions added
16. **No interception without history.** With a zero median, nothing is a windfall.
17. **Creep needs three quarters** of data and two consecutive rises. Two quarters would
    fire on any single noisy month.
18. **`taxReserveOwed`** is the tax held against still-unallocated events. Once allocated
    it has reached the reserve account and is no longer outstanding.

---

## M8 — Polish ✅

### What shipped

**`Engines/InsightsEngine`** — 17 tests. The 53x7 heatmap in three modes (logged, spend,
green days), with intensity always relative to **your own** trailing median, never an
external benchmark. Current and longest streaks, the logging rate, category rollups with
month-over-month deltas, the micro-spend rollup, and the debt burn-down.

**Insights screen** — heatmap with mode toggle and streak figures, income against expense
for 12 months, net worth, stacked debt burn-down, the micro-spend card, and the category
breakdown with deltas.

**`Services/ExportService`** — 17 tests. RFC 4180 CSV writing and parsing, a column
mapper that guesses from common header names, and seven date shapes. Rows that cannot be
read are **skipped and listed**, never guessed at.

**`Services/BackupService`** — 4 tests. Copies the store plus its `-wal` and `-shm`
sidecars (without the write-ahead log a backup can be missing the newest transactions),
keeps the last 12, and leaves unrelated files in the folder alone.

**`Services/AppLockService`** — Touch ID or password on launch and wake, always with a
password fallback so the lock can never make the app unopenable.

**`Services/NotificationScheduler`** — evaluates all fifteen rules against live data.
Every one still passes through the single `shouldDeliver` gate.

**Settings** — Data tab (backup folder, back up now, weekly backup, CSV and JSON export,
CSV import) and Security tab.

**Keyboard** — ⌘1–⌘9 for screens, ⌘N log, ⌘T transfer, ⌥⌘I inspector, ⌥⌘E global capture.

**Dashboard** — a Logging streak tile, carrying the month's micro-spend total.

### Bugs the tests caught
- **CRLF line endings.** Swift treats `\r\n` as a *single* `Character`, so the parser
  matched neither `\n` nor `\r` and folded the line break into a field — every
  Windows-exported CSV would have imported as one giant row. All three line endings are
  now matched explicitly.
- **The app installed a status item, a global hotkey and a notification prompt while
  hosting tests.** Parallel test hosts competed for process-global resources. The
  delegate now no-ops under a test host.

### On running the tests
Use `-parallel-testing-enabled NO`. In parallel, one crashed worker reports every test it
had not yet run as "failed", which hides the real failure. Serial output gives a clean
`✔`/`✘` per test.

### Assumptions added
19. **Heatmap intensity** — four entries is a full-intensity logged day; twice your median
    day is a full-intensity spend day. The spec fixes the modes, not the ramps.
20. **Imported rows land as estimates**, so they surface in the needs-review queue rather
    than silently becoming truth.
21. **Net worth history is reconstructed from the ledger** rather than read from
    `BalanceSnapshot`. The snapshot is only ever a cache, and if the two disagreed the
    ledger would win.

---

---

## M9 — Settings, backups and Help (added after M8, on request)

### What shipped

**Settings, fully editable** — five tabs. Everything that was a hardcoded constant is now
a stored setting with a control:
- *General* — login item, Dock visibility.
- *Money & time* — currency, week start, financial day boundary, birth year, income type,
  dependents, net monthly pay and pay day.
- *Thresholds* — tax reserve, high-interest line, debt-service cap, emergency fund months,
  speculation cap, income-concentration line, envelope alert margin, "maybe" event weight,
  windfall trigger, cool-off threshold and days, cost-in-time threshold, Ladder stage 6
  thresholds, and both stability-score curves. With a reset button.
- *Data* — backup folder, back up now, weekly backups, CSV and JSON export, CSV import.
- *Security* / *Privacy* — app lock, and the plain no-network statement.

**Constants moved into settings and wired through the engines**: the envelope burn margin,
the `.maybe` projection weight, Ladder stage 6's two thresholds, the runway and
debt-service scoring curves, and the concentration line. Five new tests prove each one
actually changes the outcome, and that a zero curve falls back rather than dividing by
zero.

**Help screen** — eight sections in the sidebar: a four-step setup, daily use with worked
quick-capture examples, the vocabulary, what each screen is for, the Ladder, the Advisor,
keyboard shortcuts, and where the data lives.

**Settings is a screen, not a window.** The app runs as a menu bar agent, which has no
menu bar for ⌘, to hang off — the `Settings` scene was effectively unreachable. It now
lives in the sidebar under Setup, with ⌘, and a toolbar button, and the status item's
Settings command opens the main window there.

**Monthly salary check** — 7 tests. Compares what actually arrived against the figure in
Settings, with a 1% tolerance so ordinary pay wobble is not a monthly prompt. More than
expected is treated as a rise and records an `IncomeEvent` for the §4b ratchet; less is
flagged but never ratchets. Before pay day a shortfall reads "not due yet", not a problem.
Surfaced on the Income screen with confirm/decline, and as a dashboard notice.

---

## M10 — The gaps you found

Things the engines supported but nothing in the UI could actually do.

**Record a loan payment** — Debt → right-click a loan → Record a payment. Writes a
`LoanPayment` (the debt going down, split into principal and interest) **and** a
`Transaction` (the money leaving the account), linked to each other. "Clear it" fills in
the full settlement figure; clearing marks the loan paid and drops it out of the payoff
order. Nothing is deleted — the loan and every payment stay in the records.

**Post a due recurring rule** — Plan → Scheduled → Paid / Received. Writes the entry and
rolls the rule on to its next date, month-end clamped. A variable bill learns its latest
amount. "Skip this one" advances without writing anything, because a bill you were
reminded about but did not pay must not appear as though you had.

**Investments** — a new `Valuation` model and `InvestmentEngine` (8 tests). Contributed
principal comes from the ledger; current value only ever from what you type. An unvalued
holding has **no gain**, not a gain of zero, and the portfolio total falls back to
contributed rather than treating it as worthless. Asks again after 30 days. Contribution
streak counts months, never amounts. The emergency fund sits on the same screen.

**Settings layout** — tabs moved to the top as a segmented control, content left-aligned
in a scroll view instead of floating in the middle of a fixed-size window.

**Help** — a new "Where things go" section covering rent, bills, project income, gifts,
refunds, loan payoffs, transfers and funds, including the worked example of paying a loan
out of a project payment.

### Schema note
`Valuation` is additive, so SwiftData migrates it automatically. No existing data changes.

### Assumption added
22. **Valuations go stale after 30 days.** Funds report monthly; asking more often is
    noise. An account with money in it and no valuation at all is always asked.

---

## M11 — Conflict audit

Asked to check whether anything conflicted. Five real problems, all fixed.

1. **Recorded income never reached the ledger.** An `IncomeEvent` wrote no `Transaction`,
   so ₵1,600 of project money raised no balance, appeared in no ledger, and was invisible
   to the monthly salary check — while quick capture wrote a transaction with no event.
   Two ways in, two different outcomes. `IncomeEventService.post` now writes the income
   entry and moves the tax reserve as its own transfer, from both paths.

2. **Windfall interception never ran.** `isWindfall` was written and tested but nothing
   called it, so the behaviour the spec calls the most valuable in the app did not
   happen. Quick capture and the menu bar popover now intercept automatically against the
   trailing 8-week median.

3. **Allocations moved nothing.** The sheet wrote `IncomeAllocation` rows and stopped.
   Goal and sinking-fund slices now create or increase an earmark; the investment slice
   writes a real transfer. The ladder-gap slice is still left as an instruction, because
   where it lands depends on your step — that is now stated rather than silently skipped.

4. **The emergency fund setting was ignored.** Settings edited `emergencyFundMonths`
   while the Ladder read `recommendedEmergencyFundMonths`, so changing it did nothing.
   The setting is now authoritative and the recommendation is offered with an Apply
   button. Two claimants on the balance itself (an `Account` flag and a `SinkingFund`
   flag) now have a defined precedence.

5. **Loan balances ignored how much was actually paid.** `remainingBalance` came from the
   *count* of payments against the schedule, so overpaying reduced the balance by the
   scheduled instalment only. It now follows principal actually cleared, with the
   schedule as the fallback before any payment exists. Two tests added.

### Also
- **Toolbar** — two bare `+` glyphs were indistinguishable. Global actions are now
  labelled and on the right; a screen's own action is on the left with its own noun.
- **Date pickers** — all six made compact and consistently sized.
- **`DOCUMENTATION.md`** — architecture, the money and time rules, where every kind of
  movement is recorded, a single-source-of-truth table, how to add things, and known gaps.
- **Help** — rewritten to twelve sections, adding Income & windfalls, Loans, and
  Goals & funds.

---

## M12 — Desktop widget

Display only: widgets cannot take typed input, and ⌥⌘E already opens capture from any
app, which is faster than reaching for a widget.

**The database does not move.** A widget runs in its own process and cannot read the
app's store, so rather than relocating the database into an App Group container — a
migration of real data for a read-only feature — the app writes a small pre-formatted
JSON snapshot into the shared container and the widget reads that. The widget never
writes anything and never touches the store.

- `WidgetSnapshot` — the Codable contract, the one file shared by both targets.
- `WidgetSnapshotWriter` — builds it from live data on launch and whenever the ledger
  changes, then reloads the timeline.
- `TranquilWidget` — small, medium and large. Free to spend, spend today and this week,
  runway, stability score, streak, the one next Ladder action, the next scheduled
  outgoing, and one warning.
- `WidgetSource/SETUP.md` — the five Xcode steps, and what to check if it shows sample
  numbers.

Requires a Widget Extension target and the `group.com.MyFinances` App Group on both
targets; both are done in Xcode's UI rather than by editing the project file.

---

## M13 — Icon, Dock and the menu bar

**App icon** — drawn programmatically (`scratchpad/makeicon.swift`, kept with the notes):
a sage squircle matching the app's accent, with a leaf echoing the menu bar glyph. Ten
sizes, 16 through 1024. Veins are omitted below 64pt so it stays legible in the Dock.
The first attempt read as a coffee bean; the points needed sharpening and a tilt.

**The app is a normal app again.** `LSUIElement` is removed and the activation policy now
defaults to `.regular`, with menu-bar-only as the opt-in.

This fixed two reported problems that turned out to be one cause: an accessory app has no
Dock icon **and no menu bar**. With the system menu bar set to auto-hide, moving the
pointer to the top of the screen while Tranquil was frontmost revealed nothing at all —
no battery, no clock — because there was no menu bar to reveal. BUILD_PROMPT §2 asks for
a menu bar agent; the constraint costs the system menu bar while the app is focused, which
is not a trade worth making. The status item and ⌥⌘E are unaffected either way, and
Settings → General still offers the old behaviour with that consequence spelled out.

---

## M14 — Widget showing placeholder data, and the contribution grid

**The placeholder bug had two parts.**

The immediate cause was a **stale incremental build**: the installed binary had the new
`WidgetSnapshot` (so the JSON gained the new keys) but the old `WidgetSnapshotWriter` (so
they were never filled in). A clean Release build fixed it. Worth remembering — after
editing a file the widget also compiles, build clean before installing.

The deeper fault was mine, and it is the one that mattered: the provider read
`WidgetSnapshot.load() ?? .placeholder`, so **any** failure to read the real data
rendered convincing sample figures — ₵248.00, a five-day streak, a runway — that were
not the user's. A widget that cannot reach its data must say so.

`loadResult()` now returns a typed `LoadFailure` and the widget renders it:
- *Can't reach shared data* — the App Group is missing on one of the targets
- *Open Tranquil once* — container fine, no snapshot written yet
- *Update Tranquil* — version mismatch between app and widget
- *Data unreadable* — the file is there but will not decode

Sample data now appears in exactly one place where it is honest: the widget gallery
preview (`context.isPreview`).

**Contribution grid** — the large widget carries a GitHub-style grid of the last 13 weeks,
one square per financial day, four intensity steps, matching the Insights heatmap. It is
computed in the app and shipped in the snapshot, so the widget stays a pure renderer.

---

## M15 — Widget refresh from the menu bar, and the empty states

**Logging from the menu bar did not refresh the widget.** The refresh was wired to the
main window, which is the one place this app usually is not. `WidgetSnapshotWriter.refresh`
is now a single entry point rebuilding from the store, called on launch and from every
save path. `SoftDeletable` was added so that generic fetch can filter deleted rows.

**Empty and unavailable states redesigned.** They now carry the app's leaf on a soft tint
rather than a warning triangle — sage when simply waiting for data, amber when something
needs doing. Nothing here is an emergency, and a finance widget shouting from the desktop
is a widget that gets removed.

`LeafMark` and `LeafRib` are the icon's leaf as SwiftUI shapes. The first attempt read as
a cashew: the leaf was drawn at roughly 0.74 as wide as it was long, where the icon uses
0.54. Rendering it to a PNG before shipping is what caught it.

### Still hardcoded on purpose
Notification times and cooldowns (they live in `NotificationRules` as declarative data),
the payoff-order scoring weights (editable in code via `LoanEngine.Weights`, no UI yet),
and the heatmap intensity ramps.

---

## All milestones complete

357 tests, 0 failures, no warnings. Remaining known gaps are listed under each milestone's
"what is stubbed"; the largest are `monthsAllStagesHeld` (needs recorded history before
Ladder stage 7 can be reached) and notification inline-action handlers.
