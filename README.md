# Slot Risk Manager for MetaTrader 5

**Fixed risk per trade, a hard daily loss limit, and the right lot size in one click.**

Slot Risk Manager is a free, open-source panel (Expert Advisor) for MetaTrader 5. You set an entry and a stop-loss, and it
calculates the lot size that loses exactly your chosen risk if the stop is hit. Your daily loss limit is divided into equal
**slots**: one trade uses one slot. The panel always shows how many slots are left today.

By default it is **only a calculator**. Order buttons exist, but they stay locked until you turn them on yourself. Even then,
every order has to be confirmed twice and always carries a stop-loss.

*[فارسی (Persian guide)](README.fa.md)*

---

## Why "slots"?

Many traders risk a fixed amount per trade (for example 10 USD) and stop for the day after a fixed loss (for example 50 USD).
That gives **5 slots** a day. Slot Risk Manager keeps that discipline for you:

- the risk per trade never grows by itself, not after losses and not after wins;
- "% of capital" uses a **fixed reference capital** (e.g. 5,000) that does not grow with profits, unless you choose "% of equity";
- one trade can be split into **two entries** (e.g. 50/50 or 70/30) that together use exactly one slot;
- closed losses **and** the open risk of your positions (distance to their stops) count against today's limit.

## Features

- Lot size from entry, stop-loss and risk, **always rounded down** to the broker's lot step
- Risk modes: % of a fixed reference capital, % of equity, or a fixed amount
- Daily loss limit with slots (the day starts at the broker's server midnight)
- One or two entries per trade
- Entry at the market price or at your price; stop typed in or dragged as a line on the chart
- Targets at 1R / 2R / 3R, with the expected profit and the win rate needed to break even
- **REJECTED** with a clear reason when even the smallest lot would risk more than your budget, plus the widest stop that fits
- Works on any symbol: indices, forex (distances in pips), gold, crypto (spread limit as % of price)
- Warnings: market closed, wide spread, positions without a stop, not enough margin, quote-only symbols
- Movable, minimisable panel with foldable sections; it always stays inside the chart
- Optional order buttons (market or pending orders), off by default, with two-step confirmation

All numbers come from your own terminal: tick value, contract size, minimum lot, lot step and currency conversion are read
from MetaTrader for the chart's symbol (`OrderCalcProfit` / `OrderCalcMargin`).

## Installation

1. Download this repository (**Code → Download ZIP**) and unzip it.
2. In MetaTrader 5: **File → Open Data Folder**. Copy the `MQL5` folder from the zip into the data folder, merging it with
   the existing `MQL5` folder. This adds:
   - `MQL5/Experts/SlotRiskManager/` (the panel)
   - `MQL5/Scripts/SlotRiskManager/RM_Tests.mq5` (optional self-test)
3. Open MetaEditor (F4), open `MQL5/Experts/SlotRiskManager/SlotRiskManager.mq5` and press **Compile** (F7).
4. Back in MetaTrader, in the **Navigator**, right-click **Expert Advisors → Refresh**, then drag **SlotRiskManager**
   onto a chart.

Algo Trading does not need to be on for the calculator. It is only needed if you use the order buttons.

Optional self-test: compile `RM_Tests.mq5` the same way and drag it onto any chart. The **Experts** tab should show
`RM tests: … passed, 0 failed`.

## The panel

| Part | What it does |
|---|---|
| **Title bar** | Drag to move. `–` minimises to one line with the lot and risk. The badge shows `CALC ONLY` or `TRADING ON`. |
| **BUY / SELL** | Trade direction. |
| **Entry** | `Market` = live price (Ask for buy, Bid for sell). `Price` = the price you type, or drag the green line. |
| **Price / SL** | Entry price and stop-loss price. You can also drag the red SL line on the chart. |
| **2nd / 1st %** | Only with two entries: the second entry price and the share of the risk on the first entry. |
| **RISK** (foldable) | Risk mode, risk %, fixed amount, reference capital, one or two entries, daily limit, stop buffer, Reset. |
| **Result** | The lot size in large type, the risk in money, % of the budget used, entry → stop distance and margin. |
| **TARGETS** (foldable) | 1R / 2R / 3R prices, profit and break-even win rate. |
| **ORDER** | Only when order buttons are allowed (see below). |
| **TODAY** (foldable) | Loss left today, slots left and the spread; unfolded also bid, closed loss, open risk and slot size. |

Folded sections show a one-line summary. If the chart gets shorter (for example when the Toolbox window is opened), the panel
folds extra sections and moves up, so nothing stays hidden below the chart.

Settings are saved per symbol. **The daily limit is shared by all symbols** (it reads the whole account's history and positions).

## Order buttons (optional, off by default)

> **Test on a demo account first.** With these buttons the tool sends real orders to your broker.

To use them, turn on all three:

1. EA inputs: **Allow order buttons = true** (default false; with false no order is possible at all).
2. MetaTrader's **Algo Trading** button, and "Allow Algo Trading" in the EA's Common tab.
3. The **Trading OFF → ON** switch in the panel. It is OFF again every time the EA starts.

Sending an order:

1. Choose the take-profit: none, 1R, 2R or 3R.
2. Press the order button, for example `SELL order · 0.20 lot · risk 8.00`. **Confirmation 1 of 2**: the panel lists each
   order (type, lot, price, SL, TP) and the risk. It expires after 30 seconds, and any change in the panel cancels it.
3. Press **Confirm**. **Confirmation 2 of 2**: a Windows dialog, `Send REAL order(s)?`, where the default button is **No**.
   If anything changed between the two steps (lot, SL, TP or pending price), nothing is sent.

Order types: `Market` entry sends a market order. A `Price` entry sends a pending order: a limit when the price is better
than the market, a stop when it is worse. With two entries, two separate orders share one stop. The order comment looks like
`RM S2 P1` (today's slot 2, part 1). The magic number is set in the inputs (default 30030).

**Safety locks.** No order is sent when:

- there is no stop-loss, or the lot was rejected for this risk;
- the trade is larger than the loss left today, or no slot is left;
- a position on the same symbol and side is in loss (no averaging down);
- there is not enough free margin, or the symbol cannot be traded;
- for market orders, the quote is not fresh or the spread is above your limit.

The tool **never modifies, closes or deletes** existing orders or positions, and it never raises your risk. All order code is
in one file, `RM_Trade.mqh`, which only builds **new** orders (`TRADE_ACTION_DEAL` or `TRADE_ACTION_PENDING`) with a stop-loss.

## Inputs

| Input | Default | Meaning |
|---|---|---|
| Risk mode | % of capital | % of a fixed reference capital, % of equity, or a fixed amount |
| Risk % | 0.5 | Used by the two % modes |
| Reference capital | 5000 | Fixed base for "% of capital" (does not grow with profits) |
| Fixed risk per trade | 10 | Used by the fixed mode (account currency) |
| Maximum loss per day | 50 | Daily limit (account currency) |
| What uses the daily limit | losses only | `losses only`: wins do not give back room; `net`: the day's net result |
| Entries per trade | 1 | 1 or 2 |
| Share of the first entry % | 50 | 50 = 5+5, 70 = 7+3 |
| Buffer beyond the level | 5 | Stop distance beyond a card level (points; pips on forex) |
| Warn when the spread is above | 5 / 2.0 / 0.10 % | Index points / forex pips / crypto % of price |
| Cards folder | US30Analyzer | Optional, see below |
| Panel X / Y | 12 / 30 | Position at the first start (then drag it) |
| Allow order buttons | false | Order buttons off/on |
| Magic number | 30030 | For the tool's orders |
| Maximum slippage | 20 | Market orders, broker points |
| Confirmation expires after | 30 s | Step 1 of 2 |

## Optional: levels from your own analysis tool

The panel can take the entry and stop from a "card" written by another program, such as your own analysis engine or
script. If the file `<Terminal>/Common/Files/<Cards folder>/cards.csv` exists, a **Card #** field appears. Type a card
number and the zone, refine, BOS-leg and liquidity levels become extra Entry and Stop choices. They are also drawn on the chart.

Format: `;`-separated, with this header line:

```
card_no;direction;zone_tf;stage;zone_low;zone_high;refined_low;refined_high;bos_level;bos_origin;liquidity;invalidation;created_utc;price
```

`direction` is `buy` or `sell`, prices use a `.` decimal point, and empty or 0 means "no level". Without this file the
card controls are hidden, and the panel works as a plain calculator.

## Limitations

- Every number is an estimate: slippage, gaps, commissions and swaps can make the real loss larger.
- Market orders can fill with slippage, up to your maximum slippage.
- Pending orders stay until you cancel them (GTC); the tool does not manage them after sending.
- The daily limit counts trades from the broker's server midnight.
- The panel follows the Windows display scale (125 %, 150 %, …).

## Disclaimer

This software is provided "as is", without warranty of any kind (see [LICENSE](LICENSE)). Trading leveraged products
carries a high risk of loss. The tool helps you size positions and keep your own rules; it does not give trading advice.
You are responsible for every order you confirm. Test it on a demo account before using it on a live account.

## Version history

- **2.10**: Renamed from "US30 Risk Manager". Narrower and shorter panel with foldable sections, always kept inside the chart.
  Card controls appear only when a cards file exists.
- **2.00**: Optional order buttons with two-step confirmation and safety locks.
- **1.10**: Movable and minimisable panel, large lot read-out, reason when a trade is rejected; forex in pips, crypto support.
- **1.00**: Calculator only.

## Licence

MIT © 2026 OmidBibak. See [LICENSE](LICENSE).
