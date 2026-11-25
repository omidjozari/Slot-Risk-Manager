# Slot Risk Manager for MetaTrader 5

**Fixed risk per trade, a hard daily loss limit, and the right lot size in one click.**

Slot Risk Manager is a free, open-source panel (Expert Advisor) for MetaTrader 5. You set an entry and a stop-loss, and it
calculates the lot size that loses exactly your chosen risk if the stop is hit. Your daily loss limit is divided into equal
**slots**: one trade uses one slot. The panel always shows how many slots are left today.

By default it is **only a calculator**. Order buttons, trailing, partial close and cancelling orders exist, but each stays
locked until you turn it on yourself. Even then, every order is confirmed twice and always carries a stop-loss.

*[فارسی (Persian guide)](README.fa.md)*: the panel itself can also be switched to Persian, laid out right to left.

---

## Why "slots"?

Many traders risk a fixed amount per trade (for example 10 USD) and stop for the day after a fixed loss (for example 50 USD).
That gives **5 slots** a day. Slot Risk Manager keeps that discipline for you:

- the risk per trade never grows by itself, not after losses and not after wins;
- "% of capital" uses a **fixed reference capital** (e.g. 5,000) that does not grow with profits, unless you choose "% of equity";
- one trade can be split into **two or three entries** (e.g. 50/50 or 70/30) that together use exactly one slot;
- closed losses **and** the open risk of your positions (distance to their stops) count against today's limit.

## Features

**Sizing**
- Lot size from entry, stop-loss and risk, **always rounded down** to the broker's lot step
- Risk modes: % of a fixed reference capital, % of equity, or a fixed amount
- Commission (read from your own deals) and market-order slippage are counted in the risk; the spread is shown as a share of it
- Daily loss limit with slots (the day starts at the broker's server midnight); one, two or three entries per trade
- **REJECTED** with a clear reason when even the smallest lot would risk more than your budget, plus the widest stop that fits
- Any symbol: indices, forex (pips), gold, crypto. Dow Jones, gold, Bitcoin, Ethereum, EUR/USD and GBP/USD are found under
  your broker's own names (`US30.cash`, `XAUUSD.r`, `BTCUSD_l`, …)

**On the chart**
- **Quick place** (button in the title bar, also when the panel is minimised; key `Q`): entry at the market, stop at
  1.5 × ATR(14) on M15, the take-profits and the risk box appear at once for your risk. Drag the lines, then send the order
- **Risk box**: red from the entry to the stop, green to the take-profit, with R and money on each level
- Draggable entry, stop and take-profit lines; in quick place, dragging the stop above or below the entry switches SELL / BUY

**Panel**
- Four tabs: **Trade**, **Positions**, **Rules**, **Settings**; status pills in the header (trading on, news, v2, session, trailing…)
- Minimised: one compact bar with the lot and the risk, BUY / SELL, and the confirmation itself
- **Dark / light theme** (☀ / ☾ in the header; *auto* follows the chart's background), 5 accent colours or your own `#RRGGBB`,
  BUY / SELL in green / red or blue / orange
- Fonts: Segoe UI, Tahoma, Arial, B Nazanin; high-contrast text; size 90–130 %; narrow / normal / wide
- **Persian**: every text, tooltip, dialog and phone message, with the whole panel mirrored right to left
- Settings live in the panel (one choice for every chart) with **4 presets**; hotkeys `B` `S` `Enter` `Esc` `T` `Q`

**Discipline (optional)**
- **v2 rules** (off by default): risk cap per idea and number of legs, open-risk cap, trading window (Asia / London /
  New York, your own times), day over after N losing trades or a % loss, pause after a loss, trades per day, minimum TP,
  minimum stop distance in spreads (per market)
- **News lock**: important news from MT5's own economic calendar (USD and the symbol's currencies) locks the order button
  from N minutes before to M minutes after
- **Checklist**: up to 5 items of your own; the order button opens only when every item is ticked

**Managing trades (each off by default)**
- **Positions** tab: every open position with its live result in money and R, where its stop is in R, and the next trailing step
- **Trailing**: at 2R the stop goes to the entry (plus the commission) and the take-profit to 4R; every further 1R both move
  1R on, until the stop is hit. Models: R steps, ATR, or the last swing. Panel positions only, or all positions; on / off per position
- **Partial close**: at 2R close 50 % of a position, once (both numbers adjustable). It never closes a whole position
- **Cancel pending orders** from the panel, each after a Windows dialog

**Records**
- Today's card: closed trades, wins / losses, result in money and R, losing trades in a row
- Journal file `MQL5/Files/SlotRiskManager_journal.csv`: one row per closed position (first stop, R multiple, exit reason, exits)
- Notifications to the MetaTrader app on your phone: trailing moves, closed positions, daily limit used up, session open

All numbers come from your own terminal: tick value, contract size, minimum lot, lot step and currency conversion are read
from MetaTrader for each symbol (`OrderCalcProfit` / `OrderCalcMargin`).

## Installation

1. Download this repository (**Code → Download ZIP**) and unzip it.
2. In MetaTrader 5: **File → Open Data Folder**. Copy the `MQL5` folder from the zip into the data folder, merging it with
   the existing `MQL5` folder. This adds:
   - `MQL5/Experts/SlotRiskManager/` (the panel: 8 files)
   - `MQL5/Scripts/SlotRiskManager/RM_Tests.mq5` (optional self-test)
3. Open MetaEditor (F4), open `MQL5/Experts/SlotRiskManager/SlotRiskManager.mq5` and press **Compile** (F7).
4. Back in MetaTrader, in the **Navigator**, right-click **Expert Advisors → Refresh**, then drag **SlotRiskManager**
   onto a chart.

Algo Trading does not need to be on for the calculator. It is only needed for orders, trailing, partial close and cancelling.

Optional self-test: compile `RM_Tests.mq5` the same way and drag it onto any chart. The **Experts** tab should show
`RM tests: 42 passed, 0 failed`.

## Quick place

1. Press **Place** in the title bar (or `Q`). Entry, stop, take-profits and the risk box appear for your risk.
2. Drag the **stop**: the lot is recalculated, the risk stays the same. Below the entry = BUY, above = SELL.
3. Drag the **entry** for a pending order (limit or stop), or the **TP** line for your own target.
4. Press **Order** (also in the compact bar) → **Confirm** → the Windows dialog. The lines go once the order is sent;
   pressing **Place** again removes them.

The starting stop distance (× ATR) and its timeframe are in **Settings → Quick place**. Quick place itself never sends anything.

## Order buttons (optional, off by default)

> **Test on a demo account first.** With these buttons the tool sends real orders to your broker.

To use them, turn on all three:

1. EA inputs: **Allow order buttons = true** (default false; with false no order is possible at all).
2. MetaTrader's **Algo Trading** button, and "Allow Algo Trading" in the EA's Common tab.
3. The **Trading OFF → ON** switch in the panel. It is OFF again every time the EA starts.

Sending an order:

1. Choose the take-profit: none, 1R, 2R, 3R or **Line** (the TP line you dragged).
2. Press the order button. **Confirmation 1 of 2**: the panel (or the compact bar) lists each order and the risk.
   It expires after 30 seconds, and any change in the panel cancels it.
3. Press **Confirm**. **Confirmation 2 of 2**: a Windows dialog, `Send REAL order(s)?`, where the default button is **No**.
   If anything changed between the two steps (lot, SL, TP or pending price), nothing is sent.

**Safety locks.** No order is sent when there is no stop-loss or the lot was rejected; the trade is larger than the loss left
today or no slot is left; a position on the same symbol and side is in loss (no averaging down); there is not enough free
margin; the quote is not fresh or the spread is too wide (market orders); or, when you turned them on, a v2 rule, the news
lock or an unticked checklist item blocks it.

## Trailing, partial close and cancelling (optional, off by default)

Each needs its own EA input **and** a switch in the panel that asks once with a Windows dialog (default answer **No**):

| Feature | EA input | Panel |
|---|---|---|
| Trailing | **Allow trailing** | Positions → TRAILING switch |
| Partial close | **Allow partial close and cancelling pending orders** | Positions → PARTIAL CLOSE switch |
| Cancel a pending order | same input | **×** next to the order, a dialog every time |

They work while MetaTrader and the EA are running; the last stop and take-profit stay on the server otherwise. If the EA runs
on several charts, only one of them does this work for the account.

## Where the code that touches the market lives

| File | The only thing it may do |
|---|---|
| `RM_Trade.mqh` | send **new** orders (`TRADE_ACTION_DEAL` / `TRADE_ACTION_PENDING`), always with a stop-loss |
| `RM_Trail.mqh` | move the stop-loss **forward** and the take-profit **further** (`TRADE_ACTION_SLTP`); never back, never removed |
| `RM_Manage.mqh` | close **part** of a position (it always leaves part of it open) and remove **pending** orders |

Everything else is calculation and drawing. `tests/test_slot_risk_manager.py` checks these rules in the source
(`python tests/test_slot_risk_manager.py`), and `RM_Tests.mq5` checks the arithmetic inside MetaTrader.

## Inputs

Most settings are in the panel (**Settings** and **Rules** tabs) and are kept for every chart; the EA inputs only give their
values at the first start and after **Reset all**. The safety switches stay in the inputs:

| Input | Default | Meaning |
|---|---|---|
| Allow order buttons | false | Order buttons off / on |
| Allow trailing | false | Trailing off / on |
| Allow partial close and cancelling pending orders | false | Partial close and cancelling off / on |
| Risk mode / Risk % / Reference capital / Fixed risk | % of capital / 0.5 / 5000 / 10 | Risk per trade |
| Maximum loss per day | 50 | Daily limit (account currency) |
| v2 rules on | false | The optional discipline rules |
| Magic number | 30030 | For the tool's orders |
| Maximum slippage | 20 | Market orders, broker points |

## Files the panel writes (MQL5/Files)

`SlotRiskManager_presets.txt` (presets), `SlotRiskManager_checklist.txt` (your checklist), `SlotRiskManager_journal.csv`
(closed positions), `SlotRiskManager_<symbol>.png` (a picture of the chart at each start, for support).

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

## Translations

The Persian text is generated from the table in `tools/make_lang.py`: edit it and run `python tools/make_lang.py` to rebuild
`RM_Lang.mqh`, then compile again.

## Limitations

- Every number is an estimate: slippage, gaps, commissions and swaps can make the real loss larger.
- Market orders can fill with slippage, up to your maximum slippage.
- Trailing, partial close and notifications only work while MetaTrader and the EA are running.
- News times come from MT5's calendar in server time; check them once against a known release.
- The daily limit counts trades from the broker's server midnight.

## Disclaimer

This software is provided "as is", without warranty of any kind (see [LICENSE](LICENSE)). Trading leveraged products
carries a high risk of loss. The tool helps you size positions and keep your own rules; it does not give trading advice.
You are responsible for every order you confirm. Test it on a demo account before using it on a live account.

## Version history

- **2.90**: Quick place (entry, stop at k × ATR, TPs and the risk box in one click; key Q). Dark / light / auto theme with a
  sun-moon button, accent colours and your own colour, BUY / SELL colour pairs, font choice, high-contrast text.
- **2.80**: Persian: every text, tooltip, dialog and phone message, the panel mirrored right to left.
- **2.70**: Tabs, status pills, compact bar, panel size and width; settings in the panel with 4 presets; hotkeys; news lock;
  checklist; today's card and the journal file; partial close and cancelling pending orders; ATR and swing trailing.
- **2.60**: Risk box on the chart, draggable TP line, Positions section, next trailing step on the chart, phone notifications.
- **2.50 / 2.51**: Trailing (off by default, two switches). v2 rules off by default.
- **2.40 / 2.41**: Markets found under the broker's own names, commission and slippage in the risk, scrolling panel;
  minimum stop distance in spreads per market.
- **2.30**: Sessions chosen in the panel; new look drawn on one canvas.
- **2.20**: v2 discipline rules (idea and open-risk caps, trading window, day stop, pause, trades a day); up to 3 entries.
- **2.10**: Renamed from "US30 Risk Manager". Narrower and shorter panel with foldable sections.
- **2.00**: Optional order buttons with two-step confirmation and safety locks.
- **1.10**: Movable and minimisable panel, large lot read-out, reason when a trade is rejected; forex in pips, crypto support.
- **1.00**: Calculator only.

## Licence

MIT © 2026 OmidBibak. See [LICENSE](LICENSE).
