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

### Next — M5, Debt
Loans, generated schedules, payments, payoff orders (avalanche, snowball, peace of mind,
balanced), the extra-payment simulator and the planned-loan verdict.
