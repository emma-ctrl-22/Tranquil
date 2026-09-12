# ADVISOR_RULES.md — The Accountant

The opinionated layer of Tranquil. Everything else in the app records what happened; this decides what to say about it.

> **Voice:** thirty years of watching people make the same eight mistakes. Blunt, numbers first, no flattery, no shame. It has seen a promising 24-year-old with good income end up broke at 31, and it has seen a boring one end up fine — and it knows the difference was never income.
>
> This is a rule engine for one person's own money, not licensed financial advice. It handles **behaviour** — how much, in what order, held where. It never picks investments, never forecasts markets, never tells you what to buy.

---

## 1. Owner profile

```
age: 24                    (store birth year; age is derived, not a fixed number)
incomeType: salaried | freelance | mixed        ← FILL IN
dependents: 0                                   ← FILL IN
primaryIncomeSource: single employer | single client | multiple clients
taxReserveRate: FILL IN %   ← check your own bracket, or ask a local accountant.
                              Default to something conservative; over-reserving is
                              an inconvenience, under-reserving is a crisis.
```

### Why 24 changes the rules

The advisor's whole posture is set by this. At 24:

1. **Your earning power is worth more than your portfolio, by an enormous margin.** A ₮2,000 course that raises your rate by 15% beats ₮2,000 invested, every time, for the next decade. Spending on skills, tools, and reputation is **not discretionary** in this app — it's a protected, budgeted line item. The advisor defends it during cutbacks.
2. **Lifestyle creep is the single biggest financial risk of the next five years** — far bigger than picking the wrong fund. Income will rise faster now than it ever will again. The gap between what you earn and what you spend is the entire game, and creep closes it silently. Most of the hard rules below exist to guard this one thing.
3. **Consistency beats size.** ₮200 every month for ten years beats ₮2,000 whenever you remember. So the app weights *contribution streak* above *contribution amount* in the stability score.
4. **Long consumer financing is expensive optionality.** A phone on 24-month instalments converts a one-time choice into two years of reduced flexibility, right when flexibility is your main asset.
5. **Illiquidity is a trap before the emergency fund exists.** Locked money that you have to break early costs more than it earned.
6. **You have no dependents** (update if that changes): health and disability cover matter, life insurance largely doesn't. The advisor should not nag about the latter.

---

## 2. The Order of Operations

Every spare unit of money goes down this list. The advisor never recommends a step while an earlier one is unmet, and says which step you're on at all times.

| # | Step | Why it's here |
|---|---|---|
| 1 | **Tax reserve** | It was never your money. See §4. |
| 2 | **Minimum payments on everything** | Missed payments cost more than any return |
| 3 | **Starter buffer — 2 weeks of essentials** | Stops small shocks becoming debt |
| 4 | **Employer match, if any** | A guaranteed 100% return. Nothing else comes close. |
| 5 | **Debt above the high-interest threshold** | Clearing 28% debt is a guaranteed 28% return |
| 6 | **Emergency fund — 3 months essentials** | Higher if freelance or single-client: use 6 |
| 7 | **Sinking funds funded to date** | Turns surprises into scheduled events |
| 8 | **Long-term investing, automatic and boring** | Time is the asset you have most of |
| 9 | **Medium-interest debt** | Below the threshold, no rush |
| 10 | **Goals and wants** | Deliberate, funded, guilt-free |
| 11 | **Speculation — capped, see R9** | Only from here down |

Display as a ladder with a marker showing where you actually are. Skipping a step requires an override (§5).

---

## 3. Hard rules

Hard rules **block the action in the UI**. They can be overridden, but only by typing a reason, which is logged permanently and shown in the monthly review.

| ID | Rule | Rationale |
|---|---|---|
| **R1** | No new debt for a depreciating asset while any loan sits above the high-interest threshold | Borrowing at 30% to buy something losing value is two losses stacked |
| **R2** | No borrowing to invest. Ever. No exceptions, no override. | The one rule with no override. Leverage turns a bad year into a permanent one. |
| **R3** | Freelance or project income is not yours until the tax reserve is deducted | The most common way self-employed people at your stage get destroyed |
| **R4** | A planned loan taking debt service above 30% of median income is marked **Not affordable**, not "tight" | Above 30% you have no room to absorb a bad month |
| **R5** | Don't invest new money while carrying debt above the high-interest threshold | Paying 28% debt is a certain 28%; no investment offers certainty |
| **R6** | Emergency fund cannot drop below 1 month without a logged reason | It only works if it's there when you need it |
| **R7** | No purchase that drops runway below the current Ladder stage requirement | Buying a thing shouldn't cost you a stage |
| **R8** | Consumer instalment plans over 6 months require an explicit override | Convert it to a savings goal first and see if you still want it |
| **R9** | Speculative holdings capped at 5% of net worth, and only from Ladder stage 4 | Fine as entertainment, ruinous as a plan |
| **R10** | Illiquid or locked products blocked before the emergency fund exists | Breaking them early costs more than they pay |
| **R11** | Lending money to friends or family is logged as a **receivable at zero expected return**, never as an asset in net worth | Be generous if you want to be — just don't count it as wealth |

**Thresholds are settings, not constants.** Interest rates differ enormously by country and product. Set `highInterestThresholdAPR` on first run; default it conservatively.

---

## 4. Income events — the module that matters most for you

Any inflow above `1.5 × medianWeeklyIncome` is intercepted. **It does not merge into your spendable balance.** It lands in a holding state and the app will not let you spend it until it's allocated. This one behaviour is worth more than every chart in the app.

### 4a. Project / freelance payment

```
Gross received          ₮ ______
− Tax reserve (R3)      ₮ ______   → tax reserve account, locked
− Direct project costs  ₮ ______
= Net usable            ₮ ______
```

Default allocation of net usable:

| Slice | Share | Goes to |
|---|---|---|
| Ladder gap | 40% | Whatever step in §2 you're currently on |
| Goals | 25% | Top-ranked goals, respecting caps |
| Investment | 20% | Committed, automatic |
| **Free** | 15% | Yours. No questions, no tracking against budget. |

That free slice is deliberate. A system with zero enjoyment gets abandoned in four months, and an abandoned system returns nothing. Fifteen percent of a windfall spent freely is the maintenance cost of a habit that lasts a decade.

**Effective hourly rate:** log hours worked against the project. Show `net usable ÷ hours`. Over a year this tells you which kinds of work to take more of and which to stop taking — at 24 this is the highest-leverage number in the entire app.

**Income concentration flag:** if one client or employer produced more than 60% of trailing 12-month income, raise it in the monthly review and push the emergency fund target from 3 months to 6. Concentration is a risk you can see coming.

### 4b. Salary rise — the anti-creep ratchet

Detected when a recurring income rule's amount increases, or the trailing median steps up and holds for two periods.

**The rule: your baseline spending does not automatically rise with your income.** Ever. It rises only when you explicitly decide it should, and the app makes you decide it in writing.

Default handling of the *increase* — not the whole salary, just the delta:

| Slice | Share |
|---|---|
| Investment rate increase | 40% |
| Ladder gap / debt | 30% |
| Lifestyle — explicit, logged | 20% |
| Goals | 10% |

Then: envelopes stay where they are until you raise one on purpose, with a reason attached.

**Lifestyle creep tracker.** Plot essential spend as a percentage of net income over time. If essentials grow faster than income for two consecutive quarters, the advisor raises it directly and names the categories that moved. This is the chart that would have saved most of the people the advisor has watched fail.

### 4c. Bonus, gift, refund, asset sale

- **Bonus** — treat as 4a, but tax may already be withheld; ask.
- **Gift / inheritance** — full stop for 7 days before any allocation. No decisions in the first week; large sums invite bad ones.
- **Refund or reimbursement** — **not income.** It's a return of capital. It reverses the original expense and never counts toward income, savings rate, or a good month. Getting this wrong makes your numbers lie to you.
- **Asset sale** — treat as 4a; flag if you're selling something you'll need to re-buy.

---

## 5. Verdicts and overrides

Every significant decision — a planned loan, a goal purchase, a large expense, an allocation — gets a verdict with the arithmetic shown:

- **Approved** — meets every rule
- **Approved with conditions** — fine if you do X (e.g. "fine, if the tax reserve goes in first")
- **Not advised** — allowed, but here is precisely what it costs
- **Blocked** — hard rule; requires a typed override

**The advisor never says "you can't afford that."** It says what the thing costs in the currency that actually persuades: *"₮4,800 now. That's your emergency fund down to 1.4 months, and the laptop moves from March to July. Your call."*

**Cost-in-time preview** on any expense above a threshold: show it in weeks of your top goal, not just money. `₮1,200 = 3 weeks of the iPhone.`

**The override log** is permanent. The monthly review shows how many times you overrode the advisor and what those overrides cost, totalled. No commentary needed — the number does the work.

---

## 6. The monthly letter

One screen a month, generated from templates and your real numbers. Deterministic, offline, no model calls. Structure:

1. **The number that matters this month** — one figure, chosen by rule (savings rate, or debt cleared, or runway, whichever moved most)
2. **What went right** — specific and earned, never generic praise
3. **What I'd change** — at most two things, the two largest by impact
4. **The creep check** — essentials as a share of income, trend
5. **One instruction for next month** — a single concrete action

Tone rules: no exclamation marks, no emoji, no "you've got this." State the facts and the consequence. If the month was bad, say so in one sentence and move to what to do. Never moralise, never bring up a past failure more than once.

---

## 7. What the advisor will not do

- Recommend a specific stock, fund, coin, platform, or product
- Forecast returns, inflation, or prices
- Frame any output as "buy" or "sell"
- Compare you to anyone, any average, or any benchmark population
- Use urgency, scarcity, or fear to drive an action
- Nag more than once about the same thing in the same month
- Pretend certainty about tax. Tax rules are jurisdictional and change — the app reserves a percentage you set and tells you to confirm the rate with a local professional once a year.
