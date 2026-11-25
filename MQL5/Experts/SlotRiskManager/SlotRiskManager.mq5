//+------------------------------------------------------------------+
//| SlotRiskManager.mq5 - Slot Risk Manager                           |
//| Copyright 2026, OmidBibak. MIT licence (see LICENSE).             |
//| https://github.com/omidjozari/Slot-Risk-Manager                   |
//|                                                                   |
//| Position-size and daily-loss tool for discretionary traders:      |
//| lot size from entry, stop-loss and a FIXED risk per trade; the    |
//| daily loss limit is split into equal "slots" (one trade = one     |
//| slot, optionally split into two entries). Any symbol: indices,    |
//| forex (pips), gold, crypto. Calculation only unless you turn the  |
//| order buttons on (EA input + panel switch); then every order is   |
//| confirmed twice and always carries a stop-loss. Order code lives  |
//| only in RM_Trade.mqh.                                             |
//|                                                                   |
//| Optional: a companion analysis engine may write the levels of     |
//| its recent setups to Common\Files\<folder>\cards.csv; when that   |
//| file exists, a card number fills entry / stop from those levels.  |
//| Without it the card controls are hidden.                          |
//|                                                                   |
//| History                                                           |
//| 1.00 calculator only (no trading code).                           |
//| 1.10 movable and minimisable panel, large lot read-out, entry at  |
//|      the zone / refine edge, reason when a trade is rejected.     |
//| 2.00 order buttons (off by default, two confirmations).           |
//| 2.10 renamed Slot Risk Manager (was US30 Risk Manager); narrower, |
//|      shorter panel with foldable sections (risk settings,         |
//|      targets, the day), always kept inside the chart; card        |
//|      controls only when the cards file exists.                    |
//| 2.20 v2 discipline rules: idea cap                                |
//|      (1% of balance, max 3 legs), open-risk cap (2%), trading     |
//|      window 16:30-21:00, day over after 2 losing ideas in a row   |
//|      or a 2% loss, 30 min pause after a loss, 4 trades a day,     |
//|      TP >= 2R, stop >= 8 x spread, symbol list; up to 3 entries.  |
//|      Locks apply to the order button; the panel shows them all.   |
//| 2.30 sessions chosen in the panel: Asia / London / New York, each |
//|      on or off with its own times, and a switch for the window    |
//|      rule; new look drawn on one canvas (RM_UI.mqh): rounded cards,|
//|      soft shadow, segmented controls, switches, rule tiles, bars. |
//| 2.40 MARKETS: Dow Jones, gold, Bitcoin, Ethereum, EURUSD, GBPUSD  |
//|      found under the broker's own names (YM_l, US30.cash, XAUUSD.r,|
//|      ...), each ticked for orders (replaces the YM-only list), one|
//|      click opens it; commission and market-order slippage counted in|
//|      the risk, the spread shown; the panel scrolls (wheel or bar).|
//| 2.41 'stop at least N x spread' set per market in MARKETS (field  |
//|      x in each row; Dow 8, gold 8, Bitcoin 5, Ethereum 5, forex 8;|
//|      0 = off) instead of one number for every market.             |
//| 2.50 TRAILING (off unless you turn it on: EA input + panel        |
//|      switch): at 2R the stop goes to the entry (plus the          |
//|      commission) and the take-profit to 4R; every further 1R the  |
//|      stop and the take-profit move 1R on, until the stop is hit.  |
//|      Panel positions or all positions. Only RM_Trail.mqh changes  |
//|      a position, and only forward.                                |
//| 2.51 the trailing switch stays on after "Yes" (the second report  |
//|      of the same click came after the dialog and switched it off);|
//|      v2 rules off by default (EA input).                          |
//| 2.60 risk box on the chart (red to the stop, green to the target, |
//|      R and money on each level), take-profit line you can drag    |
//|      (TP "Line"); POSITIONS section: live result in money and R,  |
//|      trailing on/off per position; next trailing step drawn on    |
//|      the chart; notifications to the MetaTrader app on the phone. |
//| 2.70 tabs (Trade / Positions / Rules / Settings), status pills in |
//|      the header, compact bar when minimised (BUY / SELL), panel   |
//|      size and width, Persian titles (test); settings in the panel |
//|      with 4 presets; hotkeys B S Enter Esc T; news lock (MT5      |
//|      calendar); checklist before an order; today's card and the  |
//|      journal file (CSV); partial close and cancelling pending     |
//|      orders (RM_Manage.mqh, off unless you turn them on); ATR and |
//|      swing trailing.                                              |
//| 2.80 Persian: every text of the panel, tooltips, dialogs and phone|
//|      messages (RM_Lang.mqh), the panel laid out right to left.    |
//| 2.90 themes: auto (the chart's background) / dark / light, sun-   |
//|      moon button in the header; button colours (5 accents or     |
//|      #RRGGBB, BUY / SELL green-red or blue-orange); fonts (Segoe, |
//|      Tahoma, Arial, B Nazanin), high-contrast text, 8 pt at least;|
//|      quick place: one button (header, also minimised; key Q) puts |
//|      entry, stop (k x ATR) and TPs on the chart for your risk;    |
//|      drag them, then Order (same two confirmations).              |
//+------------------------------------------------------------------+
#property copyright "Copyright 2026, OmidBibak (MIT licence)"
#property link      "https://github.com/omidjozari/Slot-Risk-Manager"
#property version   "2.90"
#property description "Risk calculator: lot size from entry, stop-loss and a fixed risk; daily loss slots."
#property description "Orders only when you allow them (EA input + panel switch) and confirm twice; otherwise calculation only."
#property description "v2 rules: idea and open-risk caps, trading window, day stop, pause after a loss, trades per day."

#include "RM_Math.mqh"
#include "RM_Cards.mqh"
#include "RM_Trade.mqh"
#include "RM_Trail.mqh"
#include "RM_Manage.mqh"
#include "RM_Lang.mqh"
#include "RM_UI.mqh"

enum RM_RISK_MODE
  {
   RISK_REF_PERCENT = 0,   // % of a fixed reference capital
   RISK_EQUITY_PERCENT = 1,// % of current equity
   RISK_FIXED = 2          // fixed amount per trade
  };

enum RM_DAY_COUNT
  {
   DAY_LOSSES_ONLY = 0,    // only losing trades use the daily limit (wins do not add room)
   DAY_NET = 1             // net result of the day
  };

enum RM_TRAIL_MODE
  {
   TRAIL_R_STEPS = 0,      // R steps: stop and take-profit move every step
   TRAIL_ATR = 1,          // ATR: from the first step, price - k x ATR (at least the entry)
   TRAIL_SWING = 2         // swing: from the first step, beyond the last swing (at least the entry)
  };

input group "Risk per trade (one slot)"
input RM_RISK_MODE InpRiskMode   = RISK_REF_PERCENT; // Risk mode
input double InpRiskPercent      = 0.5;      // Risk % (reference capital or equity)
input double InpRefCapital       = 5000.0;   // Reference capital (does not grow with profits)
input double InpFixedRisk        = 10.0;     // Fixed risk per trade (deposit currency)
input group "Daily limit"
input double InpDailyLimit       = 50.0;     // Maximum loss per day (deposit currency)
input RM_DAY_COUNT InpDayCount   = DAY_LOSSES_ONLY; // What uses the daily limit
input group "v2 discipline rules"
input bool   InpV2On             = false;    // v2 rules on (they lock the order button; the panel always shows them)
input double InpIdeaRiskPct      = 1.0;      // Idea = this symbol + side: max risk of all its legs, % of balance (0 = off)
input int    InpIdeaMaxLegs      = 3;        // Idea: max legs, open positions + pending orders + the new order (0 = off)
input double InpOpenRiskPct      = 2.0;      // All positions + pending orders: max risk to their stops, % of balance (0 = off)
input bool   InpWindowOn         = true;     // Trading window rule on (also a switch in the panel)
input string InpWindowStart      = "16:30";  // New York session start (server time; ticked at the first start)
input string InpWindowEnd        = "21:00";  // New York session end (server time)
input string InpLondonStart      = "10:00";  // London session start (server time)
input string InpLondonEnd        = "18:30";  // London session end (server time)
input string InpAsiaStart        = "02:00";  // Asia session start (server time)
input string InpAsiaEnd          = "11:00";  // Asia session end (server time)
input bool   InpPendingExpire    = true;     // Pending orders expire at the end of the window (when the broker allows it)
input int    InpMaxTradesDay     = 4;        // Max trades a day: positions opened + pending orders placed today (0 = off)
input int    InpMaxLossStreak    = 2;        // Day over after this many losing trades in a row (0 = off)
input double InpDayLossPct       = 2.0;      // Day over after a net loss of this % of the balance (0 = off)
input int    InpPauseMin         = 30;       // Pause after every losing trade, minutes (0 = off)
input double InpMinTpR           = 2.0;      // Order take-profit at least this many R (0 = off)
input string InpStopSpreads      = "US30=8,XAUUSD=8,BTCUSD=5,ETHUSD=5,EURUSD=8,GBPUSD=8,OTHER=8"; // Stop at least N x spread, per market (first start; then MARKETS; 0 = off)
input string InpMarkets          = "US30,XAUUSD,BTCUSD,ETHUSD,EURUSD,GBPUSD,OTHER"; // Markets ticked for orders at the first start (then: MARKETS)
input group "Split of one trade"
input int    InpParts            = 1;        // Entries per trade (1, 2 or 3)
input double InpShare1           = 50.0;     // Share of the first entry in % (50 = 5+5, 70 = 7+3)
input double InpShare2           = 30.0;     // With 3 entries: share of the second entry in % (the third gets the rest)
input group "Stop-loss"
input double InpSLBuffer         = 5.0;      // Buffer beyond the level (points on indices, pips on forex)
input double InpMaxSpread        = 5.0;      // Warn when the spread is above (index points; indices, gold, CFDs)
input double InpMaxSpreadPips    = 2.0;      // Warn when the spread is above (pips; forex pairs)
input double InpMaxSpreadCryptoPct = 0.10;   // Warn when the spread is above (% of price; Bitcoin, Ethereum...)
input group "Costs in the risk"
input double InpCommission       = -1;       // Commission per 1.00 lot, both ways (deposit currency; -1 = from your deals)
input bool   InpSlipInRisk       = true;     // Market orders: count the maximum slippage in the risk
input group "Engine cards"
input string InpCardsFolder      = "US30Analyzer"; // Optional: Common\Files folder of an analysis engine (cards.csv)
input group "Panel"
input int    InpX                = 12;       // Panel X at the first start (pixels; then drag the title bar)
input int    InpY                = 30;       // Panel Y at the first start (pixels)
input group "Orders (off unless you turn them on)"
input bool   InpTradingEnabled   = false;    // Allow order buttons (then switch Trading ON in the panel; it starts OFF)
input long   InpMagic            = 30030;    // Magic number of the tool's orders
input int    InpDeviation        = 20;       // Market orders: maximum slippage (broker points)
input int    InpConfirmSeconds   = 30;       // Step 1 confirmation expires after (seconds)
input group "Trailing (off unless you turn it on)"
input bool   InpTrailAllowed     = false;    // Allow trailing (then switch Trailing ON in the panel; it starts OFF)
input double InpTrailStartR      = 2.0;      // First step: the price this many R in profit
input double InpTrailStepR       = 1.0;      // Next steps: every this many R
input double InpTrailLagR        = 2.0;      // Stop this many R behind the step reached (2: at 2R the stop goes to the entry)
input double InpTrailTpLeadR     = 2.0;      // Take-profit this many R ahead of the step (0 = not moved); new orders get start + this
input bool   InpTrailCoverCosts  = true;     // A stop at or beyond the entry also covers the commission (truly free of risk)
input RM_TRAIL_MODE InpTrailMode = TRAIL_R_STEPS; // Trailing model (first start; then the Settings tab)
input double InpTrailAtrK        = 2.0;      // ATR model: stop this many ATR behind the price
input int    InpTrailAtrN        = 14;       // ATR model: ATR period
input int    InpTrailSwing       = 5;        // Swing model: lowest low / highest high of this many closed bars
input group "Partial close and pending orders (off unless you turn it on)"
input bool   InpManageAllowed    = false;    // Allow partial close and cancelling pending orders (then switch it ON in the panel)
input double InpPartialR         = 2.0;      // Partial close at this many R (first start; then the Settings tab)
input double InpPartialPct       = 50.0;     // Share of the position closed, % (first start; then the Settings tab)
input group "News lock (MT5 economic calendar)"
input bool   InpNewsLock         = false;    // Lock the order button around important news (first start; then the Rules tab)
input int    InpNewsBefore       = 15;       // Minutes before the news
input int    InpNewsAfter        = 15;       // Minutes after the news
input bool   InpNewsMedium       = false;    // Medium-impact news too (else high-impact only)
input group "Phone notifications (MetaTrader app; MetaQuotes ID in Tools > Options > Notifications)"
input bool   InpPush             = true;     // Send notifications to the MetaTrader app on your phone
input bool   InpPushTrail        = true;     // ... when the trailing moves a stop
input bool   InpPushClose        = true;     // ... when a position closes (stop, take-profit or by hand)
input bool   InpPushDay          = true;     // ... when the daily loss limit is used up
input bool   InpPushSession      = true;     // ... when a session of your trading window opens (v2 rules on)
input group "Chart"
input bool   InpRiskBox          = true;     // Risk box on the chart: red to the stop, green to the take-profit
input bool   InpHotkeys          = true;     // Hotkeys on the chart: B, S, Enter, Esc, T (first start; then the Settings tab)

#define PH "RM_PH_"   // panel header (always shown)
#define PB "RM_PB_"   // panel body (hidden when minimised)
#define PC "RM_C_"    // chart objects (lines, zone boxes)
#define RM_TITLE "Slot Risk Manager"
#define PW 332        // panel width (pixels at 100% Windows scale)
#define HH 96         // header: title row, status pills, tabs (2.70)
#define HT 40         // title row: drag the panel by it; the minimised panel is this row and the compact bar

// palette (2.30): graphite surfaces, one blue accent, green / red / amber only for meaning. 2.90: set by ApplyTheme()
// (dark / light, the accent and BUY / SELL colours chosen in Settings)
color C_BG    = C'17,20,26';    // panel
color C_HEAD  = C'22,26,33';    // header band
color C_CARD  = C'25,29,37';    // cards and fields
color C_CTRL  = C'33,38,48';    // controls at rest
color C_HOVER = C'44,50,62';    // controls under the mouse
color C_EDGE  = C'44,50,62';    // borders
color C_LINE  = C'34,39,49';    // dividers
color C_TXT   = C'231,234,240';
color C_DIM   = C'140,148,163';
color C_FAINT = C'96,104,120';
color C_ON    = C'59,130,246';  // accent
color C_OFF   = C'33,38,48';
color C_GREEN = C'34,197,94';
color C_BUYON = C'22,163,74';
color C_SELON = C'220,38,38';
color C_RED   = C'239,68,68';
color C_AMBER = C'245,158,11';

// ---------------- state (saved per symbol in terminal global variables)
bool   g_buy = true;
int    g_entry_src = 0;          // 0 market, 1 zone edge, 2 refine edge, 3 price
double g_entry_px = 0, g_entry2 = 0, g_entry3 = 0;
int    g_sl_src = 4;             // 0 refine, 1 BOS leg, 2 zone, 3 liquidity, 4 manual
double g_sl_manual = 0;
double g_buffer = 5;
int    g_mode = 0;
double g_percent = 0.5, g_ref = 5000, g_fixed = 10, g_daily = 50;
int    g_parts = 1;
double g_share1 = 50, g_share2 = 30;
int    g_card_no = 0;
RmCard g_card;
string g_card_msg = "";
int    g_px = 12, g_py = 30;
bool   g_min = false;
double g_s = 1.0;                // screen scale (DPI / 96)
bool   g_drag = false, g_was_down = false;
int    g_dx = 0, g_dy = 0;
uint   g_last_move = 0;
long   g_scroll_orig = 1, g_mouse_orig = 0;
string g_seen[];
// folding sections: 1 risk settings, 2 targets, 3 the day, 4 v2 rules, 5 sessions, 6 markets. Saved; the auto_ flags fold extra sections only while the
// panel is taller than the chart (never saved). The section opened last stays open.
bool   g_f_risk = true, g_f_tgt = false, g_f_day = true, g_f_v2 = false, g_f_ses = false, g_f_mk = true;
bool   g_a_risk = false, g_a_tgt = false, g_a_day = false, g_a_v2 = false, g_a_ses = false;
int    g_last_open = 0;
bool   g_dry = false;            // measuring pass: compute the height, draw nothing
int    g_draw_y = 30;            // where the panel is drawn (kept inside the chart)
bool   g_cards = false;          // the engine's cards file exists on this computer

// ---------------- sessions (2.30): your trading window, chosen in the panel (saved per symbol)
bool   g_win_rule = true;        // the window rule on / off
bool   g_ses_on[3];              // Asia, London, New York ticked
int    g_ses_a[3], g_ses_b[3];   // start / end, minutes after server midnight
int    v_ses_now = -1, v_ses_next = -1;   // session open now / opening next (-1 = none)
string SES_NAME[3] = {"Asia", "London", "New York"};

// ---------------- panel canvas (2.30)
string g_hover = "";             // zone under the mouse
bool   g_over = false;           // the mouse is over the panel (the chart does not scroll then)
int    g_panel_h = 0;            // height of the panel drawn last
int    g_res_h = 0, g_cf_h = 0;  // heights measured in the dry pass: result card, confirmation card
uint   g_click_at = 0;
int    g_click_x = -1, g_click_y = -1;
bool   g_shot = true;            // save a picture of the chart once after the start
bool   g_raise = false;          // make the panel again so it is drawn above the chart's other objects
uint   g_raise_at = 0;           // a drawing was made on the chart: raise the panel when the drawing stops (debounce)
long   g_create_orig = 0;        // the chart's 'object created' events setting before the tool

// ---------------- markets (2.40): found by name in the broker's symbol list; ticked = orders allowed (all charts)
string g_mk_sym[RM_FAMILIES];    // the broker's symbol of each market ("" = not offered)
bool   g_mk_allow[RM_FAMILIES + 1];   // the six markets and "other symbols"
double g_mk_x[RM_FAMILIES + 1];       // stop at least this many spreads from every entry, per market (0 = rule off)
int    g_fam = -1;               // market of this chart's symbol (-1 = other)

// ---------------- costs (2.40)
double g_comm_lot = 0;           // commission per 1.00 lot, both ways (deposit currency)
double v_slip_lot = 0;           // market orders: loss of 1.00 lot over the maximum slippage
double v_cost_spread = 0, v_cost_comm = 0, v_cost_slip = 0;   // for the lots of this trade

// ---------------- scrolling (2.40)
int    g_scroll = 0;             // pixels of content scrolled up under the header
int    g_body_h = 0, g_view_h = 0;    // content height below the header, visible part of it
bool   g_sdrag = false;          // dragging the scroll bar
int    g_sdrag_y0 = 0, g_sdrag_s0 = 0;
long   g_wheel_orig = 0;

// ---------------- orders (version 2)
bool    g_trade_on = false;      // panel switch: OFF at every start, never saved
int     g_tp_r = 0;              // take-profit sent with the order: 0 none, 1..3 = R, 4 = the TP line (dragged on the chart)
double  g_tp_px = 0;             // price of the TP line (g_tp_r 4)

// ---------------- 2.70: panel settings (one choice for every chart; the EA inputs only at the first start)
bool    g_v2on = false;
double  g_tr_start = 2, g_tr_step = 1, g_tr_lag = 2, g_tr_lead = 2;
bool    g_tr_cost = true;
int     g_tr_mode = 0;           // 0 R steps, 1 ATR, 2 swing
double  g_tr_atr_k = 2.0;
int     g_tr_atr_n = 14, g_tr_swing = 5, g_tr_tf = 1;   // timeframe: 0 M5, 1 M15, 2 H1
bool    g_push = true, g_push_tr = true, g_push_cl = true, g_push_day = true, g_push_ses = true;
bool    g_box = true, g_hot = true;
int     g_zoom_i = 1, g_width_i = 1, g_lang = 0;
double  g_zoom = 1.0;
int     g_pw = PW;               // panel width (pixels at 100%)
bool    g_news_on = false;
int     g_news_before = 15, g_news_after = 15, g_news_imp = 0;   // importance: 0 high only, 1 medium and high
bool    g_chk_on = false;
double  g_pc_r = 2.0, g_pc_pct = 50.0;
// 2.90 look and quick place
int     g_theme = 0;             // 0 auto (the chart's background), 1 dark, 2 light
bool    g_dark = true;           // the theme in use
int     g_acc_i = 0;             // accent: 0-4 the colours below, 5 your colour
color   g_acc_custom = C'59,130,246';
color   g_accs[5] = {C'59,130,246', C'20,184,166', C'139,92,246', C'249,115,22', C'202,138,4'};
int     g_bs_i = 0;              // BUY / SELL: 0 green / red, 1 blue / orange
int     g_font_i = 0;            // 0 auto, 1 Segoe UI, 2 Tahoma, 3 Arial, 4 B Nazanin
bool    g_contrast = true;       // brighter grey text
double  g_shadow = 0.42;
bool    g_qp = false;            // quick place: the entry, stop and TP lines are on the chart (never saved)
double  g_qp_k = 1.5;            // stop distance at the start: k x ATR(14)
int     g_qp_tf = 1;             // ATR timeframe: 0 M5, 1 M15, 2 H1
int     g_qp_atr = INVALID_HANDLE;
ENUM_TIMEFRAMES g_qp_atr_tf = PERIOD_M15;
uint    g_msg_at = 0;            // when the last order message was set (the compact bar shows it for 8 s)
int     g_tab = 0;               // 0 Trade, 1 Positions, 2 Rules, 3 Settings (per symbol)
bool    g_editing = false;       // typing in a field: no hotkeys
long    g_qnav_orig = 1;
// partial close / pending orders / news / today
bool    g_pc_on = false, g_pc_ok = false, g_pd_ok = false;
string  g_pc_msg = "", g_pd_msg = "";
string  v_news_name = "", v_news_cur = "", v_news_err = "";
datetime v_news_t = 0;
bool    v_news_lock = false;     // inside the window of an important event (locks only with the news lock on)
int     v_news_min = 0;          // minutes to the event (negative: after it)
int     v_sc_n = 0, v_sc_win = 0, v_sc_loss = 0, v_sc_rn = 0, v_jr_n = 0;
double  v_sc_net = 0, v_sc_r = 0;
bool    g_confirm = false;       // step 1 shown, waiting for "Confirm"
uint    g_confirm_at = 0;
RmOrder g_plan[3];
int     g_plan_n = 0;
string  g_order_msg = "";
bool    g_order_ok = false;

// ---------------- trailing (2.50): one choice for every chart (terminal global variables RM_TRAIL_ON / RM_TRAIL_SCOPE);
// one chart runs it at a time (RM_TRAIL_OWNER), the others show it
bool    g_trail_on = false;      // panel switch (works only with the EA input InpTrailAllowed)
int     g_trail_scope = 0;       // 0 = positions of this tool's panel (magic number), 1 = all positions of the account
bool    g_f_tr = true;           // section folded
string  g_trail_msg = "";
bool    g_trail_ok = false;
string  v_tr_state = "";         // off / run here / run by another chart / Algo Trading off
int     v_tr_n = 0;              // positions trailed now
string  v_tr_line[];             // one line per position (panel)
color   v_tr_col[];
ulong   g_tr_tk[];               // last request per position (one every 3 s at most)
uint    g_tr_at[];
uint    g_tr_clean = 0;

// ---------------- open positions (2.60): every position of the account, for the POSITIONS section and the chart
struct RmPos
  {
   ulong  tk;
   string sym;
   bool   buy;
   double vol, op, sl, tp;
   double r;          // entry to the first stop (price; 0 = unknown)
   double gain;       // price now, in R from the entry
   double ksl;        // stop now, in R from the entry
   double pl;         // result now (profit + swap, deposit currency)
   bool   in_scope;   // the trailing would handle it (Panel / All)
   bool   excluded;   // trailing switched off for this position
   double next_px;    // next trailing step (price; 0 = none)
   string next_txt;   // what happens there
  };
RmPos   v_pos[];
int     v_pos_n = 0;
bool    g_f_pos = false;         // section folded

// ---------------- phone notifications (2.60): sent by one chart only (RM_NOTE_OWNER)
ulong   g_nt_tk[];               // positions open at the last look
bool    g_nt_init = false;
int     g_nt_slots = -1;         // slots left at the last look (-1 = not known yet)
bool    g_nt_win = false;
bool    g_nt_win_known = false;
uint    g_push_at[];             // times of the last notifications (at most 10 a minute)

// ---------------- the day
struct RmDay
  {
   double used;      // part of the daily limit used by closed trades
   double net;       // net closed result today
   double open_risk; // loss if every open position hits its stop
   int    no_sl;     // open positions without a stop (risk unknown)
  };

// ---------------- results of the last calculation (shown by Draw)
double v_bid, v_ask, v_spread, v_budget, v_e1, v_e2, v_e3, v_sl, v_b1, v_b2, v_b3, v_total, v_lots, v_margin, v_left;
long   v_age;
string v_base, v_err;
bool   v_ready;                  // entry and stop known and on the right sides
RmSize v_s1, v_s2, v_s3;
double v_tp[3], v_rw[3];
RmDay  v_day;
int    v_slots_left, v_slots_all;
string v_warn[];
double v_raw1, v_minrisk1, v_maxstop1;

// ---------------- v2 discipline rules (2.20)
struct RmBook                    // what is open now: positions and pending orders, whatever placed them
  {
   double open_risk;             // all symbols: loss if every one of them hits its stop
   int    no_sl;                 // of those, without a stop (risk unknown)
   double idea_risk;             // the idea on this chart: this symbol, the side chosen in the panel
   int    idea_legs;
   int    idea_no_sl;
   double idea_sl;               // stop of the idea's newest leg (0 = none)
   int    pending_today;         // pending orders placed today (all symbols)
  };
struct RmHist                    // today's closed trades, from the deal history (any platform)
  {
   int      trades;              // positions opened today
   int      streak;              // losing trades (ideas) in a row today
   datetime last_loss;           // close of the last losing position
  };
RmBook   v_book;
RmHist   v_hist;
bool     g_hist_dirty = true;    // a trade happened (OnTrade): read the history again
uint     g_hist_at = 0;
datetime g_hist_day = 0;
double   v_bal, v_idea_cap, v_open_cap, v_day_cap, v_size_budget, v_min_stop;
string   v_cap_by;
bool     v_win_on, v_win_in;
int      v_win_min, v_pause_left;
string   v_v2_why, v_v2_short;   // first v2 rule that blocks a new order ("" = none)

// ---------------- small helpers
uint RtlFlags() { return g_lang == 1 ? 0x00180000 : 0; }   // MB_RIGHT | MB_RTLREADING: Persian dialogs read right to left
int    Z(const int v) { return (int)MathRound(v * g_s); }
string Gv(const string k) { return "RM_" + _Symbol + "_" + k; }
void   SaveNum(const string k, const double v) { GlobalVariableSet(Gv(k), v); }
double LoadNum(const string k, const double d) { return GlobalVariableCheck(Gv(k)) ? GlobalVariableGet(Gv(k)) : d; }
string Cur() { return AccountInfoString(ACCOUNT_CURRENCY); }

string Fmt(const double v, const int d)
  {
   string s = DoubleToString(MathAbs(v), d);
   int dot = StringFind(s, ".");
   string ip = dot >= 0 ? StringSubstr(s, 0, dot) : s;
   string fp = dot >= 0 ? StringSubstr(s, dot) : "";
   string out = "";
   int n = StringLen(ip);
   for(int i = 0; i < n; i++)
     {
      out += StringSubstr(ip, i, 1);
      int rest = n - 1 - i;
      if(rest > 0 && rest % 3 == 0)
         out += ",";
     }
   bool neg = v < 0 && StringToDouble(s) != 0.0;
   return (neg ? "-" : "") + out + fp;
  }

string Px(const double p) { return p > 0 ? Fmt(p, _Digits) : "-"; }
string Lot(const double v) { return DoubleToString(v, RmStepDigits(SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_STEP))); }

// distance unit of the chart's symbol: pips on forex pairs (EURUSD 0.0001, USDJPY 0.01), whole price points elsewhere
// (an index such as US30: 1.0 = one point). Prices, lots and money do not depend on it; only distances, the buffer and the spread limit.
// crypto (e.g. BTCUSD / ETHUSD in a "Crypto" folder; some brokers set up quote-only crypto like forex): distances in
// price points (1 pt = a 1.00 move of the price), spread limit in % of the price
bool IsCrypto()
  {
   string path = SymbolInfoString(_Symbol, SYMBOL_PATH);
   StringToUpper(path);
   if(StringFind(path, "CRYPTO") >= 0)
      return true;
   string base = SymbolInfoString(_Symbol, SYMBOL_CURRENCY_BASE);
   StringToUpper(base);
   string coins[] = {"BTC", "ETH", "XBT", "LTC", "XRP", "SOL", "BCH", "ADA", "DOGE", "DOT", "BNB"};
   for(int i = 0; i < ArraySize(coins); i++)
      if(base == coins[i] || StringFind(_Symbol, coins[i]) == 0)
         return true;
   return false;
  }
bool IsFx()
  {
   if(IsCrypto())
      return false;
   long m = SymbolInfoInteger(_Symbol, SYMBOL_TRADE_CALC_MODE);
   return m == SYMBOL_CALC_MODE_FOREX || m == SYMBOL_CALC_MODE_FOREX_NO_LEVERAGE;
  }
double Unit()      { return !IsFx() ? 1.0 : ((_Digits == 3 || _Digits == 5) ? 10 * _Point : _Point); }
string UnitName()  { return IsFx() ? "pips" : "pts"; }
string Dist(const double d) { return Fmt(d / Unit(), 1) + " " + UnitName(); }
double MaxSpread() { return IsFx() ? InpMaxSpreadPips : InpMaxSpread; }
// spread limit in price units, and its text
double SpreadLimit(const double price)
  {
   if(IsCrypto())
      return price > 0 ? price * InpMaxSpreadCryptoPct / 100.0 : 0;
   return MaxSpread() * Unit();
  }
string SpreadLimitText()
  {
   return IsCrypto() ? DoubleToString(InpMaxSpreadCryptoPct, 2) + "% of the price" : DoubleToString(MaxSpread(), 1) + " " + UnitName();
  }

string Ago(const long sec)
  {
   if(sec < 90) return IntegerToString(sec) + " s";
   if(sec < 5400) return IntegerToString(sec / 60) + " min";
   if(sec < 172800) return DoubleToString(sec / 3600.0, 1) + " h";
   return DoubleToString(sec / 86400.0, 1) + " days";
  }

string Trunc(const string s, const int n) { return StringLen(s) <= n ? s : StringSubstr(s, 0, n - 1) + "…"; }

void Warn(const string w)
  {
   int n = ArraySize(v_warn);
   ArrayResize(v_warn, n + 1);
   v_warn[n] = w;
  }

void Seen(const string n)
  {
   int k = ArraySize(g_seen);
   ArrayResize(g_seen, k + 1);
   g_seen[k] = n;
  }

// ---------------- text size (pixels) for placing and shortening labels
int TextW(const string t, const string font, const int size)
  {
   uint w = 0, h = 0;
   TextSetFont(UiFontName(font), -(int)MathRound(MathMax(size, 8) * 10 * UiZoom), UiFontFlags(font));   // like the labels (2.90 font)
   TextGetSize(LangTr(t), w, h);                // 2.80: measured as drawn (Persian when chosen)
   return (int)w;
  }

string FitText(const string t0, const string font, const int size, const int maxw)
  {
   string t = LangTrPlain(t0);                  // 2.80: fit the Persian text, not the English one
   if(maxw <= 0 || TextW(t, font, size) <= maxw)
      return t;
   string s = t;
   while(StringLen(s) > 1)
     {
      s = StringSubstr(s, 0, StringLen(s) - 1);
      if(TextW(s + "…", font, size) <= maxw)
         return s + "…";
     }
   return s;
  }

// word wrap into at most max_lines lines; the last line is shortened with "…" when the text is longer
int Wrap(const string t, const string font, const int size, const int maxw, const int max_lines, string &out[])
  {
   ArrayResize(out, 0);
   string w[];
   int n = StringSplit(LangTrPlain(t), ' ', w);   // 2.80: wrap the Persian words
   string cur = "";
   for(int i = 0; i < n; i++)
     {
      if(w[i] == "")
         continue;
      string cand = cur == "" ? w[i] : cur + " " + w[i];
      if(cur == "" || TextW(cand, font, size) <= maxw)
        {
         cur = cand;
         continue;
        }
      int k = ArraySize(out);
      if(k >= max_lines - 1)
        {
         for(int j = i; j < n; j++)
            if(w[j] != "")
               cur += " " + w[j];
         break;
        }
      ArrayResize(out, k + 1);
      out[k] = cur;
      cur = w[i];
     }
   if(cur != "")
     {
      int k = ArraySize(out);
      ArrayResize(out, k + 1);
      out[k] = FitText(cur, font, size, maxw);
     }
   return ArraySize(out);
  }

// ---------------- panel drawing (2.30: one canvas, RM_UI.mqh). Chart coordinates. In the measuring pass (g_dry)
// nothing is drawn: the calls only move the layout on, so the height is known before the canvas is painted.
// rounded rectangle with an optional 1 px border (edge = bg: none)
void Rect(const string n, const int x, const int y, const int w, const int h, const color bg, const color edge, const int r = -1)
  {
   if(g_dry)
      return;
   UiCard(x, y, w, h, r < 0 ? Z(6) : r, bg, edge);
  }

void Text(const string n, const int x, const int y, const string t, const color c, const int size = 9,
          const string font = "Segoe UI", const bool right = false)
  {
   if(g_dry)
      return;
   UiText(x, y, t, c, size, font, right ? (TA_RIGHT | TA_TOP) : (TA_LEFT | TA_TOP));
  }

// text centred vertically on y (labels next to controls)
void TextV(const int x, const int y, const string t, const color c, const int size = 9, const string font = "Segoe UI",
           const bool right = false)
  {
   if(g_dry)
      return;
   UiText(x, y, t, c, size, font, (right ? TA_RIGHT : TA_LEFT) | TA_VCENTER);
  }

// button: rounded, filled with on_color when on, quiet when off, lighter under the mouse. A click comes back as `n`.
void Btn(const string n, const int x, const int y, const int w, const int h, const string t, const bool on,
         const color on_color = C'59,130,246', const int size = 8, const string tip = "")
  {
   if(g_dry)
      return;
   bool hov = g_hover == n;
   color oc = on_color == C'59,130,246' ? C_ON : on_color;     // 2.90: the accent chosen in Settings
   color bg = on ? (hov ? UiMix(oc, clrWhite, 0.12) : oc) : (hov ? C_HOVER : C_CTRL);
   UiRound(x, y, w, h, MathMin(Z(8), h / 2), bg);
   string f = on ? "Segoe UI Semibold" : "Segoe UI";
   UiText(x + w / 2, y + h / 2, FitText(t, f, size, w - Z(10)), on ? clrWhite : (hov ? C_TXT : C_DIM), size, f, TA_CENTER | TA_VCENTER);
   UiZone(n, x, y, w, h, tip);
  }

// segmented control: n options in one rounded box, the chosen one filled. Option i comes back as base + val[i].
void Seg(const string base, const int x, const int y, const int w, const int h, const string &lab[], const int &val[],
         const int n, const int sel, const string &tip[], const color acc = C'59,130,246')
  {
   if(g_dry || n <= 0)
      return;
   UiCard(x, y, w, h, Z(8), C_CARD, C_EDGE);
   int p = Z(3);
   int sw = (w - 2 * p) / n;
   for(int i = 0; i < n; i++)
     {
      int sx = x + p + i * sw;
      int ww = (i == n - 1) ? (x + w - p - sx) : sw;
      string id = base + IntegerToString(val[i]);
      bool on = val[i] == sel, hov = g_hover == id;
      if(on)
         UiRound(sx, y + p, ww, h - 2 * p, Z(6), hov ? UiMix(acc == C'59,130,246' ? C_ON : acc, clrWhite, 0.12) : (acc == C'59,130,246' ? C_ON : acc));
      else if(hov)
         UiRound(sx, y + p, ww, h - 2 * p, Z(6), C_HOVER);
      string f = on ? "Segoe UI Semibold" : "Segoe UI";
      UiText(sx + ww / 2, y + h / 2, FitText(lab[i], f, 8, ww - Z(4)), on ? clrWhite : (hov ? C_TXT : C_DIM), 8, f,
             TA_CENTER | TA_VCENTER);
      UiZone(id, sx, y, ww, h, tip[i]);
     }
  }

// switch: track and knob, the track filled with acc when on. A click comes back as `n`.
void Toggle(const string n, const int x, const int y, const bool on, const color acc, const string tip)
  {
   if(g_dry)
      return;
   int w = Z(34), h = Z(18);
   bool hov = g_hover == n;
   color tr = on ? (hov ? UiMix(acc, clrWhite, 0.12) : acc) : (hov ? C_HOVER : C_CTRL);
   UiCard(x, y, w, h, h / 2, tr, on ? tr : C_EDGE);
   UiCircle(on ? x + w - h / 2 : x + h / 2, y + h / 2, h / 2 - Z(3), on ? clrWhite : C_DIM);
   UiZone(n, x, y, w, h, tip);
  }

// thin progress bar: `frac` of the track filled (0..1)
void Bar(const int x, const int y, const int w, const double frac, const color c)
  {
   if(g_dry || w <= 0)
      return;
   int h = Z(4);
   UiRound(x, y, w, h, h / 2, C_CTRL);
   int fw = (int)MathRound(w * MathMax(0.0, MathMin(1.0, frac)));
   if(fw > 0)
      UiRound(x, y, MathMax(h, fw), h, h / 2, c);
  }

void Dot(const int cx, const int cy, const color c)
  {
   if(!g_dry)
      UiCircle(cx, cy, Z(3), c);
  }

// small rounded tag on a background `under`; returns its width (also in the measuring pass)
int Pill(const int x, const int y, const string t, const color c, const color under, const int size = 7)
  {
   int w = TextW(t, "Segoe UI Semibold", size) + Z(14);
   if(!g_dry)
     {
      int h = Z(16);
      UiRound(x, y, w, h, h / 2, UiMix(under, c, 0.20));
      UiText(x + w / 2, y + h / 2, t, c, size, "Segoe UI Semibold", TA_CENTER | TA_VCENTER);
     }
   return w;
  }

// square icon button ("–" / "+")
void IconBtn(const string n, const int x, const int y, const int sz, const bool plus, const string tip)
  {
   if(g_dry)
      return;
   bool hov = g_hover == n;
   if(hov)
      UiRound(x, y, sz, sz, Z(7), C_HOVER);
   UiPlusMinus(x + sz / 2, y + sz / 2, Z(5), plus, hov ? C_TXT : C_DIM);
   UiZone(n, x, y, sz, sz, tip);
  }

// input field: rounded box on the canvas with a small caption on the left, the OBJ_EDIT (no frame of its own) inside it.
// The text is set only when the field is created (or by SetEd): the timer never overwrites what you type.
void Ed(const string n, const int x, const int y, const int w, const int h, const string t, const string tip = "",
        const string cap = "", const bool left = false)
  {
   if(g_dry)
      return;
   if(!UiInClipY(y, y + h))
      return;                             // scrolled out of view: no field (Sweep removes it)
   UiCard(x, y, w, h, Z(7), C_CARD, C_EDGE);
   int ex = x + Z(6), ew = w - Z(12);
   if(cap != "")
     {
      UiText(x + Z(9), y + h / 2, cap, C_FAINT, 8, "Segoe UI", TA_LEFT | TA_VCENTER);
      int cwid = TextW(cap, "Segoe UI", 8) + Z(14);
      ex = x + cwid;
      ew = w - cwid - Z(7);
     }
   if(ObjectFind(0, n) < 0)
     {
      ObjectCreate(0, n, OBJ_EDIT, 0, 0, 0);
      ObjectSetString(0, n, OBJPROP_TEXT, t);
     }
   ObjectSetInteger(0, n, OBJPROP_CORNER, CORNER_LEFT_UPPER);
   ObjectSetInteger(0, n, OBJPROP_XDISTANCE, UiFx(ex, MathMax(Z(18), ew)));   // 2.80: mirrored right to left
   ObjectSetInteger(0, n, OBJPROP_YDISTANCE, y + Z(3));
   ObjectSetInteger(0, n, OBJPROP_XSIZE, MathMax(Z(18), ew));
   ObjectSetInteger(0, n, OBJPROP_YSIZE, h - Z(6));
   ObjectSetString(0, n, OBJPROP_FONT, UiFontName("Segoe UI Semibold"));
   ObjectSetInteger(0, n, OBJPROP_FONTSIZE, (int)MathRound(9 * UiZoom));
   ObjectSetInteger(0, n, OBJPROP_COLOR, C_TXT);
   ObjectSetInteger(0, n, OBJPROP_BGCOLOR, C_CARD);
   ObjectSetInteger(0, n, OBJPROP_BORDER_COLOR, C_CARD);
   ObjectSetInteger(0, n, OBJPROP_ALIGN, (left != UiMirror) ? ALIGN_LEFT : ALIGN_RIGHT);
   ObjectSetInteger(0, n, OBJPROP_SELECTABLE, false);
   ObjectSetInteger(0, n, OBJPROP_HIDDEN, true);
   ObjectSetString(0, n, OBJPROP_TOOLTIP, tip == "" ? "\n" : tip);
   Seen(n);
  }

void SetEd(const string key, const string t) { ObjectSetString(0, PB + "ED_" + key, OBJPROP_TEXT, t); }

bool EdNum(const string key, double &v)
  {
   string n = PB + "ED_" + key;
   if(ObjectFind(0, n) < 0)
      return false;                       // hidden (minimised / not shown): keep the saved value
   v = StringToDouble(ObjectGetString(0, n, OBJPROP_TEXT));
   return true;
  }

// a time field "HH:MM"; a time that cannot be read keeps the old value (written back into the field)
bool EdTime(const string key, int &m)
  {
   string n = PB + "ED_" + key;
   if(ObjectFind(0, n) < 0)
      return false;
   int v = RmHhmm(ObjectGetString(0, n, OBJPROP_TEXT));
   if(v >= 0 && v <= 1440)
      m = v;
   ObjectSetString(0, n, OBJPROP_TEXT, RmHhmmText(m));
   return true;
  }

// ---------------- chart objects (true when a new object was made: it is drawn above older objects, see RaisePanel)
bool HLine(const string n, const double p, const color c, const ENUM_LINE_STYLE st, const int width, const bool drag, const string tip)
  {
   string name = PC + n;
   if(p <= 0)
     {
      ObjectDelete(0, name);
      return false;
     }
   bool made = false;
   if(ObjectFind(0, name) < 0)
      made = ObjectCreate(0, name, OBJ_HLINE, 0, 0, p);
   if(!(drag && ObjectGetInteger(0, name, OBJPROP_SELECTED)))
      ObjectSetDouble(0, name, OBJPROP_PRICE, p);
   ObjectSetInteger(0, name, OBJPROP_COLOR, c);
   ObjectSetInteger(0, name, OBJPROP_STYLE, st);
   ObjectSetInteger(0, name, OBJPROP_WIDTH, width);
   ObjectSetInteger(0, name, OBJPROP_SELECTABLE, drag);
   ObjectSetInteger(0, name, OBJPROP_BACK, false);
   ObjectSetString(0, name, OBJPROP_TOOLTIP, tip);
   ObjectSetString(0, name, OBJPROP_TEXT, tip);
   return made;
  }

bool Box(const string n, const double lo, const double hi, const color c, const bool fill, const datetime t1)
  {
   string name = PC + n;
   if(lo <= 0 || hi <= 0)
     {
      ObjectDelete(0, name);
      return false;
     }
   datetime t2 = TimeCurrent() + PeriodSeconds() * 20;
   bool made = false;
   if(ObjectFind(0, name) < 0)
      made = ObjectCreate(0, name, OBJ_RECTANGLE, 0, t1, hi, t2, lo);
   ObjectSetInteger(0, name, OBJPROP_TIME, 0, t1);
   ObjectSetDouble(0, name, OBJPROP_PRICE, 0, hi);
   ObjectSetInteger(0, name, OBJPROP_TIME, 1, t2);
   ObjectSetDouble(0, name, OBJPROP_PRICE, 1, lo);
   ObjectSetInteger(0, name, OBJPROP_COLOR, c);
   ObjectSetInteger(0, name, OBJPROP_FILL, fill);       // only the zone is filled: overlapping fills mix colours
   ObjectSetInteger(0, name, OBJPROP_WIDTH, fill ? 1 : 2);
   ObjectSetInteger(0, name, OBJPROP_BACK, true);
   ObjectSetInteger(0, name, OBJPROP_SELECTABLE, false);
   return made;
  }

datetime CardTime()
  {
   string s = g_card.created;
   StringReplace(s, "-", ".");
   StringReplace(s, "T", " ");
   datetime utc = StringToTime(s);
   if(utc <= 0)
      return iTime(_Symbol, PERIOD_CURRENT, 80);
   long off = (long)(TimeTradeServer() - TimeGMT());   // server minus UTC
   datetime t = (datetime)(utc + off - PeriodSeconds() * 10);
   return t;
  }

// ---------------- day ledger: today's closed result and the open risk to the stops (all symbols)
RmDay DayLedger()
  {
   RmDay d;
   d.used = 0; d.net = 0; d.open_risk = 0; d.no_sl = 0;
   datetime now = TimeTradeServer();
   datetime day0 = now - (now % 86400);              // broker server midnight
   double losses = 0;
   if(HistorySelect(day0, now + 60))
     {
      int n = HistoryDealsTotal();
      for(int i = 0; i < n; i++)
        {
         ulong t = HistoryDealGetTicket(i);
         if(t == 0)
            continue;
         long typ = HistoryDealGetInteger(t, DEAL_TYPE);
         if(typ != DEAL_TYPE_BUY && typ != DEAL_TYPE_SELL)
            continue;                                    // balance, credit, dividends...
         double v = HistoryDealGetDouble(t, DEAL_PROFIT) + HistoryDealGetDouble(t, DEAL_COMMISSION)
                    + HistoryDealGetDouble(t, DEAL_SWAP) + HistoryDealGetDouble(t, DEAL_FEE);
         d.net += v;
         losses += MathMin(0.0, v);                      // a losing close, or the commission of an entry
        }
     }
   d.used = MathMax(0.0, (InpDayCount == DAY_NET) ? -d.net : -losses);
   for(int i = PositionsTotal() - 1; i >= 0; i--)
     {
      ulong tk = PositionGetTicket(i);
      if(tk == 0)
         continue;
      string sym = PositionGetString(POSITION_SYMBOL);
      double vol = PositionGetDouble(POSITION_VOLUME);
      double op = PositionGetDouble(POSITION_PRICE_OPEN);
      double sl = PositionGetDouble(POSITION_SL);
      long pt = PositionGetInteger(POSITION_TYPE);
      if(sl <= 0)
        {
         d.no_sl++;
         continue;
        }
      double pr = 0;
      ENUM_ORDER_TYPE ot = (pt == POSITION_TYPE_BUY) ? ORDER_TYPE_BUY : ORDER_TYPE_SELL;
      if(OrderCalcProfit(ot, sym, vol, op, sl, pr) && pr < 0)
         d.open_risk += -pr;
     }
   return d;
  }

// ---------------- v2 rules: what is open and what happened today
// loss of `vol` lots from `price` to `sl` (0 without a stop, or when the stop is at or beyond break-even)
double LossTo(const string sym, const bool buy, const double vol, const double price, const double sl)
  {
   double pr = 0;
   if(sl <= 0 || vol <= 0 || price <= 0)
      return 0;
   if(OrderCalcProfit(buy ? ORDER_TYPE_BUY : ORDER_TYPE_SELL, sym, vol, price, sl, pr) && pr < 0)
      return -pr;
   return 0;
  }

RmBook Book(const datetime day0)
  {
   RmBook b;
   b.open_risk = 0; b.no_sl = 0; b.idea_risk = 0; b.idea_legs = 0; b.idea_no_sl = 0; b.idea_sl = 0; b.pending_today = 0;
   datetime newest = 0;
   for(int i = PositionsTotal() - 1; i >= 0; i--)
     {
      if(PositionGetTicket(i) == 0)
         continue;
      string sym = PositionGetString(POSITION_SYMBOL);
      bool buy = PositionGetInteger(POSITION_TYPE) == POSITION_TYPE_BUY;
      double sl = PositionGetDouble(POSITION_SL);
      double r = LossTo(sym, buy, PositionGetDouble(POSITION_VOLUME), PositionGetDouble(POSITION_PRICE_OPEN), sl);
      b.open_risk += r;
      if(sl <= 0)
         b.no_sl++;
      if(sym != _Symbol || buy != g_buy)
         continue;
      b.idea_legs++;
      b.idea_risk += r;
      if(sl <= 0)
         b.idea_no_sl++;
      datetime t = (datetime)PositionGetInteger(POSITION_TIME);
      if(sl > 0 && t >= newest) { newest = t; b.idea_sl = sl; }
     }
   for(int i = OrdersTotal() - 1; i >= 0; i--)
     {
      if(OrderGetTicket(i) == 0)
         continue;
      long ty = OrderGetInteger(ORDER_TYPE);
      bool buy = ty == ORDER_TYPE_BUY_LIMIT || ty == ORDER_TYPE_BUY_STOP || ty == ORDER_TYPE_BUY_STOP_LIMIT;
      bool sell = ty == ORDER_TYPE_SELL_LIMIT || ty == ORDER_TYPE_SELL_STOP || ty == ORDER_TYPE_SELL_STOP_LIMIT;
      if(!buy && !sell)
         continue;                                       // a market order being filled
      string sym = OrderGetString(ORDER_SYMBOL);
      double sl = OrderGetDouble(ORDER_SL);
      double px = OrderGetDouble(ORDER_PRICE_OPEN);
      if((ty == ORDER_TYPE_BUY_STOP_LIMIT || ty == ORDER_TYPE_SELL_STOP_LIMIT) && OrderGetDouble(ORDER_PRICE_STOPLIMIT) > 0)
         px = OrderGetDouble(ORDER_PRICE_STOPLIMIT);
      double r = LossTo(sym, buy, OrderGetDouble(ORDER_VOLUME_CURRENT), px, sl);
      datetime t = (datetime)OrderGetInteger(ORDER_TIME_SETUP);
      b.open_risk += r;
      if(sl <= 0)
         b.no_sl++;
      if(t >= day0)
         b.pending_today++;
      if(sym != _Symbol || buy != g_buy)
         continue;
      b.idea_legs++;
      b.idea_risk += r;
      if(sl <= 0)
         b.idea_no_sl++;
      if(sl > 0 && t >= newest) { newest = t; b.idea_sl = sl; }
     }
   return b;
  }

// deal history of the last 14 days (to know when today's closed positions were opened): positions opened today,
// losing ideas in a row today (legs of one ladder count once) and the close of the last losing position
RmHist V2History(const datetime day0, const datetime now)
  {
   RmHist h;
   h.trades = 0; h.streak = 0; h.last_loss = 0;
   if(!HistorySelect(day0 - 14 * 86400, now + 60))
      return h;
   ulong pid[];
   string sym[];
   bool buy[];
   long tin[], tout[];
   double net[];
   int np = 0;
   int n = HistoryDealsTotal();
   for(int i = 0; i < n; i++)
     {
      ulong t = HistoryDealGetTicket(i);
      if(t == 0)
         continue;
      long typ = HistoryDealGetInteger(t, DEAL_TYPE);
      if(typ != DEAL_TYPE_BUY && typ != DEAL_TYPE_SELL)
         continue;                                       // balance, credit, dividends...
      long en = HistoryDealGetInteger(t, DEAL_ENTRY);
      ulong p = (ulong)HistoryDealGetInteger(t, DEAL_POSITION_ID);
      long tm = HistoryDealGetInteger(t, DEAL_TIME);
      double v = HistoryDealGetDouble(t, DEAL_PROFIT) + HistoryDealGetDouble(t, DEAL_COMMISSION)
                 + HistoryDealGetDouble(t, DEAL_SWAP) + HistoryDealGetDouble(t, DEAL_FEE);
      int k = -1;
      for(int j = np - 1; j >= 0; j--)
         if(pid[j] == p) { k = j; break; }
      if(k < 0)
        {
         k = np++;
         ArrayResize(pid, np, 64); ArrayResize(sym, np, 64); ArrayResize(buy, np, 64);
         ArrayResize(tin, np, 64); ArrayResize(tout, np, 64); ArrayResize(net, np, 64);
         pid[k] = p;
         sym[k] = HistoryDealGetString(t, DEAL_SYMBOL);
         buy[k] = (en == DEAL_ENTRY_IN) ? (typ == DEAL_TYPE_BUY) : (typ == DEAL_TYPE_SELL);   // an exit deal is opposite to its position
         tin[k] = tm;
         tout[k] = 0;
         net[k] = 0;
        }
      net[k] += v;
      if(en == DEAL_ENTRY_IN)
        {
         tin[k] = tm;
         if(tm >= (long)day0)
            h.trades++;
        }
      else if(tm > tout[k])
         tout[k] = tm;
     }
   string cs[];
   bool cb[];
   long ci[], co[];
   double cn[];
   int nc = 0;
   for(int k = 0; k < np; k++)
     {
      if(tout[k] == 0 || PositionSelectByTicket(pid[k]))
         continue;                                       // still open (or only partly closed)
      if(net[k] < 0 && tout[k] > (long)h.last_loss)
         h.last_loss = (datetime)tout[k];
      if(tout[k] < (long)day0)
         continue;
      nc++;
      ArrayResize(cs, nc, 16); ArrayResize(cb, nc, 16); ArrayResize(ci, nc, 16); ArrayResize(co, nc, 16); ArrayResize(cn, nc, 16);
      cs[nc - 1] = sym[k];
      cb[nc - 1] = buy[k];
      ci[nc - 1] = tin[k];
      co[nc - 1] = tout[k];
      cn[nc - 1] = net[k];
     }
   h.streak = RmIdeaLossStreak(cs, cb, ci, co, cn);
   return h;
  }

// "1%" / "0.5%"
string Pc(const double p)
  {
   string t = DoubleToString(p, 2);
   while(StringLen(t) > 1 && StringSubstr(t, StringLen(t) - 1) == "0")
      t = StringSubstr(t, 0, StringLen(t) - 1);
   if(StringSubstr(t, StringLen(t) - 1) == ".")
      t = StringSubstr(t, 0, StringLen(t) - 1);
   return t + "%";
  }

string Mins(const int m)
  {
   if(m < 60)
      return IntegerToString(m) + " min";
   if(m >= 1440)
      return IntegerToString(m / 1440) + " d " + IntegerToString((m % 1440) / 60) + " h " + IntegerToString(m % 60) + " min";
   return IntegerToString(m / 60) + " h " + IntegerToString(m % 60) + " min";
  }

// what is open, today's history (read again after a trade, at a new day, or every 10 s), the caps, and the budget of a
// new order: the slot budget, but never more than the room left under the idea cap and the open-risk cap
void V2Pre()
  {
   datetime now = TimeTradeServer();
   datetime day0 = now - (now % 86400);
   v_book = Book(day0);
   if(g_hist_dirty || day0 != g_hist_day || GetTickCount() - g_hist_at > 10000)
     {
      v_hist = V2History(day0, now);
      g_hist_dirty = false;
      g_hist_day = day0;
      g_hist_at = GetTickCount();
     }
   v_bal = AccountInfoDouble(ACCOUNT_BALANCE);
   v_idea_cap = v_bal * MathMax(0.0, InpIdeaRiskPct) / 100.0;
   v_open_cap = v_bal * MathMax(0.0, InpOpenRiskPct) / 100.0;
   v_day_cap = MathMax(0.0, v_bal - v_day.net) * MathMax(0.0, InpDayLossPct) / 100.0;   // of the balance at the start of the day
   double idea_room = (g_v2on && InpIdeaRiskPct > 0) ? MathMax(0.0, v_idea_cap - v_book.idea_risk) : -1.0;
   double open_room = (g_v2on && InpOpenRiskPct > 0) ? MathMax(0.0, v_open_cap - v_book.open_risk) : -1.0;
   v_size_budget = RmCapBudget(v_budget, idea_room, open_room);
   v_cap_by = "";
   if(v_size_budget < v_budget - 1e-9)
      v_cap_by = (open_room >= 0 && open_room <= v_size_budget + 1e-9) ? "open risk " + Pc(InpOpenRiskPct) : "idea " + Pc(InpIdeaRiskPct);
  }

// the broker's trade sessions of this symbol: does it trade at minute `m` of weekday `dow` (0 = Sunday)?
// A symbol without any session data counts as always trading.
bool TradesAt(const int dow, const int m)
  {
   datetime from = 0, to = 0;
   bool any = false;
   for(int d = 0; d < 7 && !any; d++)
      any = SymbolInfoSessionTrade(_Symbol, (ENUM_DAY_OF_WEEK)d, 0, from, to);
   if(!any)
      return true;
   for(int k = 0; k < 16; k++)
     {
      if(!SymbolInfoSessionTrade(_Symbol, (ENUM_DAY_OF_WEEK)dow, k, from, to))
         break;
      int a = (int)((long)from / 60), b = (int)((long)to / 60);
      if(a == b || (a < b ? (m >= a && m < b) : (m >= a || m < b)))
         return true;
     }
   return false;
  }

// the ticked sessions: "London + New York", with their times when `times`
string SessionsText(const bool times)
  {
   string out = "";
   for(int s = 0; s < 3; s++)
      if(g_ses_on[s])
         out += (out == "" ? "" : (times ? ", " : " + ")) + SES_NAME[s] +
                (times ? " " + RmHhmmText(g_ses_a[s]) + "-" + RmHhmmText(g_ses_b[s]) : "");
   return out == "" ? "none" : out;
  }

string WindowText()
  {
   if(!g_win_rule)
      return "window off: orders at any time";
   if(!v_win_on)
      return "no session ticked";
   if(v_win_in)
      return "open now" + (v_ses_now >= 0 ? " (" + SES_NAME[v_ses_now] + ")" : "") + ", closes in " + Mins(v_win_min);
   return "closed, opens in " + Mins(v_win_min) + (v_ses_next >= 0 ? " (" + SES_NAME[v_ses_next] + ")" : "");
  }

// markets ticked: saved choices (shared by all charts), or the input list when there are none / on Reset all
void MarketDefaults(const bool reset)
  {
   string raw = InpMarkets;
   StringToUpper(raw);
   StringReplace(raw, " ", "");
   string list = "," + raw + ",";
   for(int f = 0; f <= RM_FAMILIES; f++)
     {
      string key = f < RM_FAMILIES ? RM_FAM_KEY[f] : "OTHER";
      string gv = "RM_MK_" + key;
      bool def = StringFind(list, "," + key + ",") >= 0;
      g_mk_allow[f] = (!reset && GlobalVariableCheck(gv)) ? GlobalVariableGet(gv) != 0 : def;
      string gx = "RM_MKX_" + key;
      double dx = MathMax(0.0, RmListValue(InpStopSpreads, key, 8.0));
      g_mk_x[f] = (!reset && GlobalVariableCheck(gx)) ? GlobalVariableGet(gx) : dx;
     }
  }

// "8" / "5.5"
string XText(const double x) { return DoubleToString(x, MathAbs(x - MathRound(x)) < 1e-9 ? 0 : 1); }

// the stop / spread multiplier of this chart's market
double StopSpreads() { return g_mk_x[g_fam < 0 ? RM_FAMILIES : g_fam]; }

// session defaults from the inputs (Asia, London, New York)
void SesDefaults(int &a[], int &b[])
  {
   string sa[3] = {InpAsiaStart, InpLondonStart, InpWindowStart}, sb[3] = {InpAsiaEnd, InpLondonEnd, InpWindowEnd};
   int da[3] = {120, 600, 990}, db[3] = {660, 1110, 1260};
   for(int s = 0; s < 3; s++)
     {
      a[s] = RmHhmm(sa[s]) >= 0 ? RmHhmm(sa[s]) : da[s];
      b[s] = RmHhmm(sb[s]) >= 0 ? RmHhmm(sb[s]) : db[s];
     }
  }

void V2Block(const string why, const string tag)
  {
   if(v_v2_why != "")
      return;
   v_v2_why = why;
   v_v2_short = tag;
  }

// every v2 rule for a NEW order on this chart; the first one that fails locks the order button (BuildPlan)
void V2Check()
  {
   v_v2_why = "";
   v_v2_short = "";
   datetime now = TimeTradeServer();
   int m = (int)((now % 86400) / 60);
   MqlDateTime dt;
   TimeToStruct(now, dt);
   // trading window = the sessions ticked in the panel, and only while the market is open
   int sa[3], sb[3];
   bool son[3];
   int nses = 0;
   for(int s = 0; s < 3; s++)
     {
      sa[s] = g_ses_a[s];
      sb[s] = g_ses_b[s];
      son[s] = g_ses_on[s] && sa[s] >= 0 && sb[s] >= 0 && sa[s] != sb[s];
      if(son[s])
         nses++;
     }
   v_win_on = g_win_rule && nses > 0;
   v_win_in = (!v_win_on || RmInSessions(m, sa, sb, son)) && TradesAt(dt.day_of_week, m);   // your hours AND the market open
   v_win_min = 0;
   v_ses_now = -1;
   v_ses_next = -1;
   for(int s = 0; s < 3 && v_win_in; s++)
      if(son[s] && RmInWindow(m, sa[s], sb[s]))
        {
         v_ses_now = s;
         break;
        }
   if(v_win_on && v_win_in)
      v_win_min = RmMinutesToClose(m, sa, sb, son);
   else if(v_win_on)
      for(int s = 0; s < 3; s++)
        {
         if(!son[s])
            continue;
         bool open_at[7];                                                  // the symbol trades at this session's start that day
         for(int d = 0; d < 7; d++)
            open_at[d] = TradesAt(d, sa[s]);
         int mins = RmMinutesToOpen(m, dt.day_of_week, sa[s], open_at);   // weekend: counts to Monday, not to Sunday
         if(v_ses_next < 0 || mins < v_win_min)
           {
            v_win_min = mins;
            v_ses_next = s;
           }
        }
   v_pause_left = 0;
   if(InpPauseMin > 0 && v_hist.last_loss > 0)
     {
      long left = (long)v_hist.last_loss + (long)InpPauseMin * 60 - (long)now;
      if(left > 0)
         v_pause_left = (int)((left + 59) / 60);
     }
   v_min_stop = (StopSpreads() > 0 && v_spread > 0) ? StopSpreads() * v_spread : 0;   // per market (MARKETS)
   if(!g_v2on)
      return;
   int legs = g_parts;
   int today = v_hist.trades + v_book.pending_today;
   // the day
   if(InpDayLossPct > 0 && v_day.net < 0 && -v_day.net >= v_day_cap - 1e-9)
      V2Block("day over: today's loss " + Fmt(-v_day.net, 2) + " reached " + Pc(InpDayLossPct) + " of the balance", "day over");
   if(InpMaxLossStreak > 0 && v_hist.streak >= InpMaxLossStreak)
      V2Block(StringFormat("day over: %d losing trades in a row", v_hist.streak), "day over");
   if(v_pause_left > 0)
      V2Block("pause after a loss: " + Mins(v_pause_left) + " left", "pause " + Mins(v_pause_left));
   if(InpMaxTradesDay > 0 && today + legs > InpMaxTradesDay)
      V2Block(StringFormat("%d trade(s) today + %d new is over %d a day", today, legs, InpMaxTradesDay), "trades full");
   if(g_win_rule && nses == 0)
      V2Block("trading window on, but no session ticked: tick one, or switch the window off", "no session");
   if(v_win_on && !v_win_in)
      V2Block("outside your sessions (" + SessionsText(true) + "): opens in " + Mins(v_win_min), "window closed");
   if(!g_mk_allow[g_fam < 0 ? RM_FAMILIES : g_fam])
      V2Block(_Symbol + " (" + MarketName(g_fam) + ") is not ticked in MARKETS", "market not ticked");
   // the idea and the account
   if(v_book.no_sl > 0)
      V2Block(IntegerToString(v_book.no_sl) + " open position / order without a stop: open risk unknown", "leg without SL");
   if(InpIdeaMaxLegs > 0 && v_book.idea_legs + legs > InpIdeaMaxLegs)
      V2Block(StringFormat("idea legs: %d open + %d new is over %d", v_book.idea_legs, legs, InpIdeaMaxLegs), "idea legs full");
   if(InpIdeaRiskPct > 0 && v_book.idea_risk >= v_idea_cap - 1e-9)
      V2Block("idea risk " + Fmt(v_book.idea_risk, 2) + " is at its cap " + Fmt(v_idea_cap, 2) + " (" + Pc(InpIdeaRiskPct) + ")",
              "idea risk full");
   if(InpOpenRiskPct > 0 && v_book.open_risk >= v_open_cap - 1e-9)
      V2Block("open risk " + Fmt(v_book.open_risk, 2) + " is at its cap " + Fmt(v_open_cap, 2) + " (" + Pc(InpOpenRiskPct) + ")",
              "open risk full");
   // this order
   if(v_ready && v_min_stop > 0)
     {
      double d = MathAbs(v_e1 - v_sl);
      if(g_parts >= 2)
         d = MathMin(d, MathAbs(v_e2 - v_sl));
      if(g_parts == 3)
         d = MathMin(d, MathAbs(v_e3 - v_sl));
      if(d < v_min_stop - 1e-9)
         V2Block("stop " + Dist(d) + " is under " + XText(StopSpreads()) + " x spread (" + Dist(v_min_stop) + ")",
                 "stop too close");
     }
   if(InpTradingEnabled && InpMinTpR > 0 && OrderTpR() < InpMinTpR - 1e-9)
      V2Block("choose a take-profit of at least " + DoubleToString(InpMinTpR, 0) + "R", "TP under " + DoubleToString(InpMinTpR, 0) + "R");
   if(v_ready && v_book.idea_sl > 0 && MathAbs(v_sl - v_book.idea_sl) > SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_SIZE) / 2)
      Warn("v2: this idea's open leg has its stop at " + Px(v_book.idea_sl) + " - one shared stop for all legs");
  }

// end of the trading window for a pending order placed now (0 = good till cancelled)
datetime PendingExpiry()
  {
   if(!g_v2on || !InpPendingExpire || !v_win_on || !v_win_in || v_win_min <= 0)
      return 0;
   datetime now = TimeTradeServer();
   return (datetime)(now - now % 60 + v_win_min * 60);
  }

// ---------------- trailing (2.50)
bool TrailValid() { return g_tr_start > 0 && g_tr_step > 0 && g_tr_lag > 0 && g_tr_lead >= 0; }
bool TrailActive() { return InpTrailAllowed && g_trail_on && TrailValid(); }
// trailing moves the take-profit: new orders get it at the first step + lead (4R), so the first step can be reached
bool TrailTp() { return TrailActive() && g_tr_lead > 0; }
double OrderTpR()
  {
   if(TrailTp())
      return g_tr_start + g_tr_lead;
   if(g_tp_r == 4)
     {
      double d = MathAbs(v_e1 - v_sl);
      if(d <= 0 || g_tp_px <= 0)
         return 0;
      return MathMax(0.0, (g_buy ? g_tp_px - v_e1 : v_e1 - g_tp_px) / d);
     }
   return g_tp_r;
  }

// take-profit of a new order: none, 1-3R, the TP line, or the trailing's first target (4R)
double SelTp()
  {
   if(!v_ready || v_sl <= 0)
      return 0;
   double d = MathAbs(v_e1 - v_sl);
   if(TrailTp())
      return g_buy ? v_e1 + OrderTpR() * d : v_e1 - OrderTpR() * d;
   if(g_tp_r == 4)
      return g_tp_px;
   return g_tp_r > 0 ? v_tp[g_tp_r - 1] : 0;
  }

string TrailRule()
  {
   if(g_tr_mode > 0)
     {
      string m = g_tr_mode == 1 ? XText(g_tr_atr_k) + " x ATR(" + IntegerToString(g_tr_atr_n) + ", " + TfName() + ")"
                 : "the last swing of " + IntegerToString(g_tr_swing) + " bars (" + TfName() + ")";
      return "from " + XText(g_tr_start) + "R: stop at least the entry, then " + m +
             (g_tr_lead > 0 ? "  ·  TP " + XText(g_tr_start + g_tr_lead) + "R, +" + XText(g_tr_step) + "R each step" : "");
     }
   string tp = g_tr_lead > 0 ? ", TP " + XText(g_tr_start + g_tr_lead) + "R" : "";
   double k = g_tr_start - g_tr_lag;
   string st = MathAbs(k) < 1e-9 ? "entry" : (k > 0 ? "+" : "") + XText(k) + "R";
   return "at " + XText(g_tr_start) + "R: stop " + st + tp + "  ·  then every " + XText(g_tr_step) + "R: stop" +
          (g_tr_lead > 0 ? " and TP" : "") + " +" + XText(g_tr_step) + "R";
  }

// one chart does a job for the whole account (trailing, notifications): the owner writes a heartbeat every second;
// another chart takes over 5 s after it stops
bool Owner(const string job)
  {
   string ko = "RM_" + job + "_OWNER", kb = "RM_" + job + "_BEAT";
   double me = (double)(ChartID() % 1000000007);
   double now = (double)GetTickCount64();
   bool has = GlobalVariableCheck(ko);
   double own = has ? GlobalVariableGet(ko) : -1;
   double beat = GlobalVariableCheck(kb) ? GlobalVariableGet(kb) : 0;
   if(has && own != me && now - beat < 5000 && now >= beat)
      return false;
   GlobalVariableSet(ko, me);
   GlobalVariableSet(kb, now);
   return true;
  }

void Release(const string job)
  {
   string ko = "RM_" + job + "_OWNER", kb = "RM_" + job + "_BEAT";
   if(GlobalVariableCheck(ko) && GlobalVariableGet(ko) == (double)(ChartID() % 1000000007))
     {
      GlobalVariableDel(ko);
      GlobalVariableDel(kb);
     }
  }

bool TrailOwner() { return Owner("TRAIL"); }
void TrailRelease() { Release("TRAIL"); }

// trailing switched off for one position (POSITIONS section)
string TrailXKey(const ulong tk) { return "RM_TR_X_" + IntegerToString((long)tk); }
bool TrailExcluded(const ulong tk) { return GlobalVariableCheck(TrailXKey(tk)); }

// R of a position = entry to its FIRST stop, remembered (terminal global variable) because the stop moves later.
// First time: the stop of the order that opened it, else its stop now (when that is still on the losing side).
// `cost` = commission of the position both ways as a price distance (0 when g_tr_cost is off).
double TrailR(const ulong tk, const string sym, const bool buy, const double op, const double sl, double &cost)
  {
   string kr = "RM_TR_R_" + IntegerToString((long)tk), kc = "RM_TR_C_" + IntegerToString((long)tk);
   cost = 0;
   if(GlobalVariableCheck(kr))
     {
      cost = g_tr_cost && GlobalVariableCheck(kc) ? GlobalVariableGet(kc) : 0;
      return GlobalVariableGet(kr);
     }
   double first = 0, comm = 0, vin = 0;
   long pid = PositionGetInteger(POSITION_IDENTIFIER);
   if(HistorySelectByPosition(pid))
     {
      if(HistoryOrdersTotal() > 0)
        {
         ulong ot = HistoryOrderGetTicket(0);
         if(ot > 0)
            first = HistoryOrderGetDouble(ot, ORDER_SL);
        }
      for(int i = 0; i < HistoryDealsTotal(); i++)
        {
         ulong dt = HistoryDealGetTicket(i);
         if(dt > 0 && HistoryDealGetInteger(dt, DEAL_ENTRY) == DEAL_ENTRY_IN)
           {
            comm += HistoryDealGetDouble(dt, DEAL_COMMISSION) + HistoryDealGetDouble(dt, DEAL_FEE);
            vin += HistoryDealGetDouble(dt, DEAL_VOLUME);
           }
        }
     }
   if(first <= 0 || (buy ? first >= op : first <= op))
      first = sl;
   if(first <= 0 || (buy ? first >= op : first <= op))
      return 0;                                         // the stop is already at or beyond the entry: R unknown
   double r = MathAbs(op - first);
   double c = 0, v = 0;
   double ts = SymbolInfoDouble(sym, SYMBOL_TRADE_TICK_SIZE);
   if(comm < 0 && vin > 0 && ts > 0 && OrderCalcProfit(ORDER_TYPE_BUY, sym, 1.0, op, op + ts, v) && v > 0)
      c = -comm / vin * 2.0 / v * ts;                    // entry commission per lot, both ways, as a price distance
   GlobalVariableSet(kr, r);
   GlobalVariableSet(kc, c);
   cost = g_tr_cost ? c : 0;
   return r;
  }

// the last request for this position was less than 3 s ago
bool TrailBusy(const ulong tk)
  {
   for(int i = ArraySize(g_tr_tk) - 1; i >= 0; i--)
      if(g_tr_tk[i] == tk)
        {
         if(GetTickCount() - g_tr_at[i] < 3000)
            return true;
         g_tr_at[i] = GetTickCount();
         return false;
        }
   int n = ArraySize(g_tr_tk);
   if(n >= 200) { ArrayResize(g_tr_tk, 0); ArrayResize(g_tr_at, 0); n = 0; }
   ArrayResize(g_tr_tk, n + 1);
   ArrayResize(g_tr_at, n + 1);
   g_tr_tk[n] = tk;
   g_tr_at[n] = GetTickCount();
   return false;
  }

void TrailLine(const string t, const color c)
  {
   int n = ArraySize(v_tr_line);
   ArrayResize(v_tr_line, n + 1);
   ArrayResize(v_tr_col, n + 1);
   v_tr_line[n] = t;
   v_tr_col[n] = c;
  }

// remembered R of positions that are closed: removed once a minute
void TrailClean()
  {
   if(GetTickCount() - g_tr_clean < 60000 && g_tr_clean != 0)
      return;
   g_tr_clean = GetTickCount();
   for(int i = GlobalVariablesTotal() - 1; i >= 0; i--)
     {
      string n = GlobalVariableName(i);
      if(StringFind(n, "RM_TR_R_") != 0 && StringFind(n, "RM_TR_C_") != 0 && StringFind(n, "RM_TR_X_") != 0 && StringFind(n, "RM_PC_D_") != 0)
         continue;
      ulong tk = (ulong)StringToInteger(StringSubstr(n, 8));
      if(!PositionSelectByTicket(tk))
         GlobalVariableDel(n);
     }
  }

// every tick and every second: the stop and the take-profit of each trailed position, moved forward when a step is reached
void TrailRun()
  {
   v_tr_n = 0;
   ArrayResize(v_tr_line, 0);
   ArrayResize(v_tr_col, 0);
   g_trail_on = GlobalVariableCheck("RM_TRAIL_ON") && GlobalVariableGet("RM_TRAIL_ON") != 0;
   g_trail_scope = GlobalVariableCheck("RM_TRAIL_SCOPE") && GlobalVariableGet("RM_TRAIL_SCOPE") != 0 ? 1 : 0;
   if(!InpTrailAllowed || !TrailValid() || !g_trail_on)
     {
      v_tr_state = !InpTrailAllowed ? "off in the EA inputs" : (!TrailValid() ? "Settings tab: start, step and lag must be above 0" : "OFF");
      TrailRelease();
      return;
     }
   if(!TrailOwner())
     {
      v_tr_state = "ON  ·  run by the Slot Risk Manager on another chart";
      return;
     }
   TrailClean();
   bool algo = TerminalInfoInteger(TERMINAL_TRADE_ALLOWED) && MQLInfoInteger(MQL_TRADE_ALLOWED);
   v_tr_state = algo ? "ON  ·  " + (g_trail_scope == 0 ? "panel positions" : "all positions")
                : "ON, but Algo Trading is off: stops are not moved";
   for(int i = PositionsTotal() - 1; i >= 0; i--)
     {
      ulong tk = PositionGetTicket(i);
      if(tk == 0)
         continue;
      if(g_trail_scope == 0 && PositionGetInteger(POSITION_MAGIC) != InpMagic)
         continue;
      string sym = PositionGetString(POSITION_SYMBOL);
      bool buy = PositionGetInteger(POSITION_TYPE) == POSITION_TYPE_BUY;
      double op = PositionGetDouble(POSITION_PRICE_OPEN), sl = PositionGetDouble(POSITION_SL), tp = PositionGetDouble(POSITION_TP);
      int dg = (int)SymbolInfoInteger(sym, SYMBOL_DIGITS);
      string head = sym + " " + (buy ? "BUY" : "SELL") + " " + DoubleToString(PositionGetDouble(POSITION_VOLUME), 2);
      if(TrailExcluded(tk))
        {
         TrailLine(head + "  ·  trailing off for this position", C_FAINT);
         continue;
        }
      if(sl <= 0)
        {
         TrailLine(head + "  ·  no stop: not trailed", C_AMBER);
         continue;
        }
      double cost = 0;
      double r = TrailR(tk, sym, buy, op, sl, cost);
      if(r <= 0)
        {
         TrailLine(head + "  ·  stop at the entry when first seen: R unknown, not trailed", C_FAINT);
         continue;
        }
      v_tr_n++;
      double px = buy ? SymbolInfoDouble(sym, SYMBOL_BID) : SymbolInfoDouble(sym, SYMBOL_ASK);
      if(px <= 0)
        {
         TrailLine(head + "  ·  no quote", C_FAINT);
         continue;
        }
      double gain = (buy ? px - op : op - px) / r;
      double n = RmTrailStep(gain, g_tr_start, g_tr_step);
      double tsl = 0, ttp = 0;
      RmTrailTargets(buy, op, r, n < 0 ? g_tr_start : n, g_tr_lag, g_tr_lead, cost, tsl, ttp);
      double tick = SymbolInfoDouble(sym, SYMBOL_TRADE_TICK_SIZE);
      if(tick <= 0)
         tick = SymbolInfoDouble(sym, SYMBOL_POINT);
      tsl = RmTickRound(sym, tsl);
      ttp = ttp > 0 ? RmTickRound(sym, ttp) : 0;
      if(g_tr_mode > 0 && n >= 0)                     // 2.70 ATR / swing: from the first step at least the entry, then the model
        {
         double lvl = TrailModelStop(sym, buy, px);
         double be = buy ? op + cost : op - cost;
         tsl = RmTickRound(sym, buy ? MathMax(be, lvl) : (lvl > 0 ? MathMin(be, lvl) : be));
        }
      bool msl = n >= 0 && RmStopForward(buy, sl, tsl, tick);
      bool mtp = RmTpFurther(buy, tp, ttp, tick);
      double ksl = (buy ? sl - op : op - sl) / r;     // where the stop is now, in R from the entry
      TrailLine(head + StringFormat("  ·  %+.1fR", gain) + (n >= 0 ? "  ·  step " + XText(n) + "R" : "") + "  ·  SL " +
                (MathAbs(ksl) < 0.05 ? "entry" : StringFormat("%+.1fR", ksl)) + (tp > 0 ? "  ·  TP " + DoubleToString(tp, dg) : "  ·  no TP"),
                ksl >= -1e-9 ? C_GREEN : C_TXT);
      if((!msl && !mtp) || !algo || TrailBusy(tk))
         continue;
      string m = "";
      bool ok = RmModifyStops(tk, msl ? tsl : sl, mtp ? ttp : tp, m);
      if(ok || StringFind(m, "RM_WAIT") != 0)
        {
         g_trail_ok = ok;
         g_trail_msg = (ok ? "Moved " : "Not moved: ") + m;
         Print(RM_TITLE, " trailing: ", ok ? "moved " : "not moved ", m, ok ? StringFormat("  (price %+.2fR, step %sR)", gain, XText(n)) : "");
         if(ok && g_push_tr)
            Push("Trailing: " + m + StringFormat(" (price %+.1fR)", gain));
        }
     }
  }

// take-profit button at the start: the v2 minimum when orders are on
int DefaultTp()
  {
   if(g_v2on && InpTradingEnabled && InpMinTpR > 0)
      return (int)MathMin(3.0, MathCeil(InpMinTpR));
   return 0;
  }

// ---------------- entry and stop from the selected sources
double EntryPrice(string &why)
  {
   why = "";
   if(g_entry_src == 0)
      return g_buy ? v_ask : v_bid;
   if(g_entry_src == 3)
     {
      if(g_entry_px <= 0) why = "type the entry price";
      return g_entry_px;
     }
   if(!g_card.found)
     {
      why = "load an engine card for this entry (or choose Market / Price)";
      return 0;
     }
   double p = 0;
   if(g_entry_src == 1)
      p = g_buy ? g_card.zone_high : g_card.zone_low;    // near edge of the zone
   else
      p = g_buy ? g_card.ref_high : g_card.ref_low;      // near edge of the M15 refine
   if(p <= 0)
      why = "this card has no refine zone";
   return p;
  }

double StopPrice(string &why)
  {
   why = "";
   if(g_sl_src == 4)
     {
      if(g_sl_manual <= 0) why = "type the stop-loss price, or drag the red line";
      return g_sl_manual;
     }
   if(!g_card.found)
     {
      why = "load an engine card for this stop (or choose Manual)";
      return 0;
     }
   double lvl = 0;
   if(g_sl_src == 0)
      lvl = g_buy ? g_card.ref_low : g_card.ref_high;
   else if(g_sl_src == 1)
      lvl = g_card.bos_origin;
   else if(g_sl_src == 2)
      lvl = g_buy ? g_card.zone_low : g_card.zone_high;
   else if(g_sl_src == 3)
      lvl = g_card.liquidity;
   if(lvl <= 0)
     {
      string nm[4] = {"refine", "BOS leg (no BOS yet)", "zone", "liquidity"};
      why = "this card has no " + nm[g_sl_src] + " level";
      return 0;
     }
   return g_buy ? lvl - g_buffer * Unit() : lvl + g_buffer * Unit();
  }

bool CardsFile()
  {
   return InpCardsFolder != "" && FileIsExist(InpCardsFolder + "\\cards.csv", FILE_COMMON);
  }

// ---------------- calculation (no drawing)
void Calc()
  {
   CalcCore();
   V2Check();
  }

void CalcCore()
  {
   ArrayResize(v_warn, 0);
   // without the engine's cards file (other computers, other traders) the card row and the card sources are hidden:
   // entry = Market or Price, stop = the price you type or drag
   g_cards = CardsFile();
   if(!g_cards && !g_card.found)
     {
      if(g_entry_src == 1 || g_entry_src == 2)
         g_entry_src = g_entry_px > 0 ? 3 : 0;
      if(g_sl_src < 4)
         g_sl_src = 4;
     }
   v_bid = SymbolInfoDouble(_Symbol, SYMBOL_BID);
   v_ask = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
   double vmin = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MIN);
   double vmax = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MAX);
   double vstep = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_STEP);
   v_age = (long)(TimeTradeServer() - (datetime)SymbolInfoInteger(_Symbol, SYMBOL_TIME));
   v_spread = (v_bid > 0 && v_ask > 0) ? v_ask - v_bid : 0;
   if(v_bid <= 0 || v_ask <= 0 || v_age > 120)
      Warn("Market closed or offline: last quote " + Ago(v_age) + " ago");
   else if(SpreadLimit(v_bid) > 0 && v_spread > SpreadLimit(v_bid) + 1e-12)
      Warn("Spread " + Dist(v_spread) + " is above " + SpreadLimitText());
   if(SymbolInfoInteger(_Symbol, SYMBOL_TRADE_MODE) == SYMBOL_TRADE_MODE_DISABLED)
      Warn("Quotes only: this symbol cannot be traded on this account");

   double equity = AccountInfoDouble(ACCOUNT_EQUITY);
   v_budget = RmBudget(g_mode, g_percent, g_ref, equity, g_fixed);
   v_base = g_mode == 2 ? "fixed" : (g_mode == 1 ? StringFormat("%.2f%% of equity %s", g_percent, Fmt(equity, 0))
            : StringFormat("%.2f%% of %s", g_percent, Fmt(g_ref, 0)));

   v_day = DayLedger();
   v_left = MathMax(0.0, g_daily - v_day.used - v_day.open_risk);
   v_slots_all = v_budget > 0 ? (int)MathFloor(g_daily / v_budget + 1e-9) : 0;
   v_slots_left = v_budget > 0 ? (int)MathFloor(v_left / v_budget + 1e-9) : 0;
   if(v_day.no_sl > 0)
      Warn(IntegerToString(v_day.no_sl) + " open position(s) without a stop: risk unknown");
   if(v_budget > g_daily)
      Warn("One trade risks more than the whole daily limit");
   V2Pre();

   string w1 = "", w2 = "";
   v_e1 = EntryPrice(w1);
   v_e2 = (g_parts >= 2 && g_entry2 > 0) ? g_entry2 : v_e1;
   v_e3 = (g_parts == 3 && g_entry3 > 0) ? g_entry3 : v_e1;
   v_sl = StopPrice(w2);
   v_ready = false;
   v_err = "";
   v_s1.ok = false; v_s1.lot = 0; v_s1.risk = 0; v_s1.loss_per_lot = 0; v_s1.why = "";
   v_s2 = v_s1;
   v_s3 = v_s1;
   v_total = 0; v_lots = 0; v_margin = 0; v_raw1 = 0; v_minrisk1 = 0; v_maxstop1 = 0;
   for(int r = 0; r < 3; r++) { v_tp[r] = 0; v_rw[r] = 0; }
   if(v_e1 <= 0) { v_err = "Entry: " + w1; return; }
   if(v_sl <= 0) { v_err = "Stop: " + w2; return; }
   if((g_buy && (v_sl >= v_e1 || v_sl >= v_e2 || v_sl >= v_e3)) || (!g_buy && (v_sl <= v_e1 || v_sl <= v_e2 || v_sl <= v_e3)))
     {
      v_err = g_buy ? "The stop must be BELOW the entry for a BUY" : "The stop must be ABOVE the entry for a SELL";
      return;
     }
   if(g_parts == 3 && g_share1 + g_share2 >= 100.0 - 1e-9)
     {
      v_err = "1st % + 2nd % leave nothing for the 3rd entry";
      return;
     }
   v_ready = true;
   ENUM_ORDER_TYPE ot = g_buy ? ORDER_TYPE_BUY : ORDER_TYPE_SELL;
   double bud = v_size_budget;                      // the slot budget, capped by the v2 idea / open-risk room
   v_b1 = (g_parts >= 2) ? bud * g_share1 / 100.0 : bud;
   v_b2 = (g_parts == 2) ? bud - v_b1 : ((g_parts == 3) ? bud * g_share2 / 100.0 : 0);
   v_b3 = (g_parts == 3) ? bud - v_b1 - v_b2 : 0;
   double l1 = 0, l2 = 0, l3 = 0, pr = 0;
   if(OrderCalcProfit(ot, _Symbol, 1.0, v_e1, v_sl, pr)) l1 = -pr;
   if(g_parts >= 2 && OrderCalcProfit(ot, _Symbol, 1.0, v_e2, v_sl, pr)) l2 = -pr;
   if(g_parts == 3 && OrderCalcProfit(ot, _Symbol, 1.0, v_e3, v_sl, pr)) l3 = -pr;
   // costs of 1.00 lot on top of the move to the stop: the commission (both ways) and, for a market order, the largest
   // slippage it accepts. The spread needs nothing extra: a buy fills at Ask and its stop is hit at Bid (a sell the other
   // way round), so the loss to the stop already contains it.
   bool mk1 = g_entry_src == 0, mk2 = mk1 && g_entry2 <= 0, mk3 = mk1 && g_entry3 <= 0;
   v_slip_lot = 0;
   if(InpSlipInRisk && InpDeviation > 0 && OrderCalcProfit(ot, _Symbol, 1.0, v_e1, g_buy ? v_e1 - InpDeviation * _Point : v_e1 + InpDeviation * _Point, pr))
      v_slip_lot = MathMax(0.0, -pr);
   if(l1 > 0) l1 += g_comm_lot + (mk1 ? v_slip_lot : 0);
   if(l2 > 0) l2 += g_comm_lot + (mk2 ? v_slip_lot : 0);
   if(l3 > 0) l3 += g_comm_lot + (mk3 ? v_slip_lot : 0);
   v_s1 = RmSizeFor(v_b1, l1, vmin, vmax, vstep);
   if(g_parts >= 2)
      v_s2 = RmSizeFor(v_b2, l2, vmin, vmax, vstep);
   if(g_parts == 3)
      v_s3 = RmSizeFor(v_b3, l3, vmin, vmax, vstep);
   double dist = MathAbs(v_e1 - v_sl);
   if(l1 > 0)
     {
      v_raw1 = v_b1 / l1;                              // exact volume before the broker step
      v_minrisk1 = vmin * l1;                          // what the smallest volume would risk
      v_maxstop1 = dist > 0 ? v_b1 / (vmin * l1 / dist) : 0;   // widest stop the budget allows at the smallest volume
     }
   v_total = (v_s1.ok ? v_s1.risk : 0) + (v_s2.ok ? v_s2.risk : 0) + (v_s3.ok ? v_s3.risk : 0);
   v_lots = (v_s1.ok ? v_s1.lot : 0) + (v_s2.ok ? v_s2.lot : 0) + (v_s3.ok ? v_s3.lot : 0);
   v_cost_comm = g_comm_lot * v_lots;
   v_cost_slip = v_slip_lot * ((mk1 && v_s1.ok ? v_s1.lot : 0) + (mk2 && v_s2.ok ? v_s2.lot : 0) + (mk3 && v_s3.ok ? v_s3.lot : 0));
   v_cost_spread = 0;
   if(v_lots > 0 && v_spread > 0 && OrderCalcProfit(ORDER_TYPE_BUY, _Symbol, v_lots, v_ask, v_ask - v_spread, pr))
      v_cost_spread = MathMax(0.0, -pr);
   if(v_lots > 0 && !OrderCalcMargin(ot, _Symbol, v_lots, v_e1, v_margin))
      v_margin = 0;
   if(v_total > v_left + 1e-6)
      Warn("More than today's remaining loss (" + Fmt(v_left, 2) + " " + Cur() + ")");
   if(v_margin > AccountInfoDouble(ACCOUNT_MARGIN_FREE))
      Warn("Not enough free margin");
   for(int r = 1; r <= 3; r++)
     {
      double tp = g_buy ? v_e1 + r * dist : v_e1 - r * dist;
      double p1 = 0, p2 = 0, p3 = 0, rw = 0;
      if(v_s1.ok && OrderCalcProfit(ot, _Symbol, v_s1.lot, v_e1, tp, p1)) rw += p1;
      if(v_s2.ok && OrderCalcProfit(ot, _Symbol, v_s2.lot, v_e2, tp, p2)) rw += p2;
      if(v_s3.ok && OrderCalcProfit(ot, _Symbol, v_s3.lot, v_e3, tp, p3)) rw += p3;
      rw -= v_cost_comm;                  // net of the commission
      v_tp[r - 1] = tp;
      v_rw[r - 1] = rw;
     }
  }

// ---------------- drawing
bool Folded(const int k)
  {
   if(k == 1) return g_f_risk || g_a_risk;
   if(k == 2) return g_f_tgt || g_a_tgt;
   if(k == 4) return g_f_v2 || g_a_v2;
   if(k == 5) return g_f_ses || g_a_ses;
   if(k == 6) return g_f_mk;
   if(k == 7) return g_f_tr;
   if(k == 8) return g_f_pos;
   return g_f_day || g_a_day;
  }

// fold an open section for this draw only (panel taller than the chart); false when it is folded already or opened last
bool AutoFold(const int k)
  {
   if(Folded(k) || k == g_last_open)
      return false;
   if(k == 1) g_a_risk = true;
   else if(k == 2) g_a_tgt = true;
   else if(k == 4) g_a_v2 = true;
   else if(k == 5) g_a_ses = true;
   else g_a_day = true;
   return true;
  }

void ToggleFold(const int k)
  {
   bool opening = Folded(k);
   if(k == 1) { g_f_risk = !opening; g_a_risk = false; }
   else if(k == 2) { g_f_tgt = !opening; g_a_tgt = false; }
   else if(k == 4) { g_f_v2 = !opening; g_a_v2 = false; }
   else if(k == 5) { g_f_ses = !opening; g_a_ses = false; }
   else if(k == 6) { g_f_mk = !opening; }
   else if(k == 7) { g_f_tr = !opening; }
   else if(k == 8) { g_f_pos = !opening; }
   else { g_f_day = !opening; g_a_day = false; }
   if(opening)
      g_last_open = k;
   else if(g_last_open == k)
      g_last_open = 0;
  }

// section title: small label, a hairline (or the one-line summary when folded) and a chevron; the whole row folds it
void Section(const string n, const int L, const int R, const int y, const string t, const string key = "",
             const bool folded = false, const string summary = "", const color sc = C'140,148,163')
  {
   string tt = L_(t);
   int ts = g_lang == 1 ? 8 : 7;
   Text(n, L, y - (g_lang == 1 ? Z(2) : 0), tt, C_DIM, ts, "Segoe UI Semibold");
   int tx = L + TextW(tt, "Segoe UI Semibold", ts) + Z(10);
   int r = key == "" ? R : R - Z(26);
   if(folded && summary != "")
      Text(n + "_sum", tx, y - Z(2), FitText(summary, "Segoe UI", 8, r - tx), sc == C'140,148,163' ? C_DIM : sc, 8);
   else if(!g_dry)
      UiLineH(tx, y + Z(6), MathMax(1, r - tx), C_LINE);
   if(key != "" && !g_dry)
     {
      string id = PB + "BTN_F" + key;
      bool hov = g_hover == id;
      if(hov)
         UiRound(R - Z(22), y - Z(4), Z(22), Z(20), Z(6), C_HOVER);
      UiChevron(R - Z(11), y + Z(6), Z(3), !folded, hov ? C_TXT : C_DIM);
      UiZone(id, L, y - Z(6), R - L, Z(22), folded ? "Show" : "Hide");
     }
  }

void KV(const string n, const int x, const int r, const int y, const string k, const string v, const color vc)
  {
   Text(n + "_k", x, y, k, C_DIM, 9);
   int kw = TextW(k, "Segoe UI", 9) + Z(10);
   Text(n + "_v", r, y, FitText(v, "Segoe UI", 9, r - x - kw), vc, 9, "Segoe UI", true);
  }

string Summary()
  {
   if(!v_ready)
      return "-";
   if(!v_s1.ok)
      return "rejected";
   return Lot(v_lots) + " lot · " + Fmt(v_total, 2) + " " + Cur();
  }

// measure the content, place the panel (it stays where you put it and reaches at most to the chart's bottom; taller
// content scrolls with the mouse wheel or the bar on the right), then paint: card, scrolled content, header band on top
void Draw()
  {
   int ch = (int)ChartGetInteger(0, CHART_HEIGHT_IN_PIXELS);
   if(ch <= 0)
      ch = 100000;
   int W = Z(g_pw), hh = Z(HH);
   g_dry = true;
   int full = Panel(g_px, 0, 0);                  // whole height, nothing scrolled
   g_dry = false;
   ArrayResize(g_seen, 0);
   int vmin = MathMin(full, hh + Z(180));         // at least this much of the panel stays visible
   g_draw_y = MathMax(0, MathMin(g_py, ch - vmin - Z(4)));
   int h = MathMin(full, MathMax(vmin, ch - g_draw_y - Z(4)));
   g_body_h = full - hh;
   g_view_h = h - hh;
   g_scroll = MathMax(0, MathMin(g_scroll, g_body_h - g_view_h));
   g_panel_h = h;
   // the chart lines first: a line made just now (or a drawing made after the panel) would lie over the panel
   if(DrawChart() || g_raise)
      RaisePanel();
   g_raise = false;
   if(UiBegin(g_px, g_draw_y, W, h, Z(16)))
     {
      UiShadow(g_px, g_draw_y, W, h, Z(12), Z(14), Z(4), g_shadow);
      UiCard(g_px, g_draw_y, W, h, Z(12), g_min ? C_HEAD : C_BG, C_EDGE);
      if(!g_min)
        {
         UiClip(g_px + 1, g_draw_y + hh + 1, g_px + W - 2, g_draw_y + h - 2);
         Panel(g_px, g_draw_y, g_scroll);
         UiNoClip();
         UiRound(g_px + 1, g_draw_y + 1, W - 2, hh, Z(11), C_HEAD);      // the header covers what scrolled under it
         UiFill(g_px + 1, g_draw_y + hh - Z(12), W - 2, Z(12), C_HEAD);
         UiLineH(g_px + 1, g_draw_y + hh, W - 2, C_LINE);
         ScrollBar();
        }
      Head(g_px, g_draw_y);
      UiEnd();
     }
   Sweep();
   ChartRedraw();
  }

// scroll bar: track (x, y, height) and thumb (y, height); false when everything fits
bool SbGeo(int &tx, int &ty, int &th, int &my, int &mh)
  {
   tx = 0; ty = 0; th = 0; my = 0; mh = 0;
   if(g_min || g_view_h <= 0 || g_body_h <= g_view_h)
      return false;
   tx = g_px + Z(g_pw) - Z(8);
   ty = g_draw_y + Z(HH) + Z(6);
   th = g_view_h - Z(12);
   mh = MathMax(Z(28), (int)((double)th * g_view_h / g_body_h));
   if(th <= mh)
      return false;
   my = ty + (int)((double)(th - mh) * g_scroll / (g_body_h - g_view_h));
   return true;
  }

void ScrollBar()
  {
   int tx, ty, th, my, mh;
   if(!SbGeo(tx, ty, th, my, mh))
      return;
   UiRound(tx, ty, Z(4), th, Z(2), C_LINE);
   UiRound(tx, my, Z(4), mh, Z(2), g_sdrag ? C_DIM : C_HOVER);
  }

// scroll to `px` pixels (kept within the content)
void ScrollTo(const int px)
  {
   g_scroll = MathMax(0, MathMin(g_body_h - g_view_h, px));
  }

// header: title, status tag, (minimised) summary, minimise button; drag it to move the panel
void Head(const int x, const int y)
  {
   int W = Z(g_pw);
   int L = x + Z(14), R = x + W - Z(14);
   int ht = Z(HT);
   bool live = InpTradingEnabled && g_trade_on;
   int bsz = Z(26), mx0 = R - bsz, tx0 = mx0 - Z(4) - bsz, qw = Z(66), qx0 = tx0 - Z(6) - qw;
   TextV(L, y + ht / 2, FitText(RM_TITLE, "Segoe UI Semibold", 10, qx0 - L - Z(6)), C_TXT, 10, "Segoe UI Semibold");
   Btn(PH + "BTN_QP", qx0, y + ht / 2 - Z(12), qw, Z(24), g_qp ? "Placing" : "Place", g_qp, C_ON, 8,
       g_qp ? "Click to remove the lines (Q)" : "Entry, stop and TPs on the chart for your risk: drag them, then Order (Q)");
   string thm = PH + "BTN_THM";
   bool thv = g_hover == thm;
   if(thv)
      UiRound(tx0, y + ht / 2 - Z(13), bsz, bsz, Z(7), C_HOVER);
   UiSunMoon(tx0 + bsz / 2, y + ht / 2, Z(7), g_dark, thv ? C_TXT : C_DIM, thv ? C_HOVER : C_HEAD);
   UiZone(thm, tx0, y + ht / 2 - Z(13), bsz, bsz, g_dark ? "Light theme" : "Dark theme");
   IconBtn(PH + "BTN_MIN", mx0, y + ht / 2 - Z(13), bsz, g_min, g_min ? "Open the panel" : "Minimise");
   if(g_min)
     {
      Compact(x, y + ht);
      return;
     }
   // status pills: what is on, what locks the order button
   int sy = y + ht - Z(4), sx = L, sr = R;
   sx = SPill(sx, sy, sr, live ? "TRADING ON" : "CALC ONLY", live ? C_RED : C_AMBER);
   if(g_news_on && v_news_lock)
      sx = SPill(sx, sy, sr, "NEWS LOCK", C_RED);
   else if(v_news_t > 0 && v_news_min >= 0 && v_news_min <= 60)
      sx = SPill(sx, sy, sr, "NEWS " + IntegerToString(v_news_min) + "m", C_AMBER);
   if(g_chk_on && !ChecklistOk())
      sx = SPill(sx, sy, sr, "CHECKLIST", C_AMBER);
   if(g_v2on)
      sx = SPill(sx, sy, sr, v_v2_why == "" ? "V2 OK" : "V2: " + v_v2_short, v_v2_why == "" ? C_GREEN : C_RED);
   if(g_v2on && v_win_on)
      sx = SPill(sx, sy, sr, (v_win_in && v_ses_now >= 0) ? SES_NAME[v_ses_now] + " OPEN" : "WINDOW CLOSED", v_win_in ? C_GREEN : C_AMBER);
   if(InpTrailAllowed)
      sx = SPill(sx, sy, sr, g_trail_on ? "TRAIL ON" : "TRAIL OFF", g_trail_on ? C_GREEN : C_FAINT);
   if(PartialOn())
      sx = SPill(sx, sy, sr, "PARTIAL " + XText(g_pc_r) + "R", C_GREEN);
   string tl[4];
   tl[0] = L_("Trade"); tl[1] = L_("Positions"); tl[2] = L_("Rules"); tl[3] = L_("Settings");
   int tv[4] = {0, 1, 2, 3};
   string tt[4] = {"Side, entry, stop, the lot size and the order", "Open positions, pending orders, trailing, partial close, today",
                   "v2 rules, news lock, checklist, sessions, markets", "Presets, display, hotkeys, trailing, phone"};
   Seg(PH + "BTN_TAB", L, y + Z(60), R - L, Z(28), tl, tv, 4, g_tab, tt);
  }

// the panel's content below the header (the open tab), `scroll` pixels scrolled up; returns the bottom of the content as
// if nothing were scrolled. Minimised: the title row and the compact bar.
int Panel(const int x, const int y, const int scroll)
  {
   if(g_min)
      return y + Z(HT) + Z(38);
   if(g_tab == 0)
      return TabTrade(x, y, scroll);
   int W = Z(g_pw);
   int L = x + Z(14), R = x + W - Z(14);
   int cy = y + Z(HH) - scroll + Z(14);
   if(g_tab == 1)
      cy = TabPositions(L, R, cy);
   else if(g_tab == 2)
      cy = TabRules(L, R, cy);
   else
      cy = TabSettings(L, R, cy);
   return cy + Z(10) + scroll;
  }

// the Trade tab: side, entry and stop, risk, the result, targets, checklist and the order; `scroll` pixels scrolled up
int TabTrade(const int x, const int y, const int scroll)
  {
   int W = Z(g_pw);
   int L = x + Z(14), R = x + W - Z(14);
   int hh = Z(HH);

   int top = y + hh - scroll;
   int cy = top + Z(14);
   int lw = Z(46);                       // label column
   int cx = L + lw;                      // controls start
   int cw = R - cx;                      // controls width
   int rh = Z(26), st = Z(32);           // control height, row step

   // ---- side
   int hw = (R - L - Z(8)) / 2;
   Btn(PB + "BTN_BUY", L, cy, hw, Z(36), "BUY", g_buy, C_BUYON, 10, "Buy side");
   Btn(PB + "BTN_SELL", L + hw + Z(8), cy, R - L - hw - Z(8), Z(36), "SELL", !g_buy, C_SELON, 10, "Sell side");
   cy += Z(46);

   // ---- engine card: only when the engine's cards file is on this computer
   bool cards = g_cards || g_card.found;
   if(cards)
     {
      TextV(L, cy + rh / 2, "Card", C_DIM, 9);
      Ed(PB + "ED_CARD", cx, cy, Z(100), rh, g_card_no > 0 ? IntegerToString(g_card_no) : "", "Engine card number, then Enter or Load", "#A");
      Btn(PB + "BTN_LOAD", cx + Z(106), cy, Z(60), rh, "Load", true, C_ON, 8, "Take the levels of this engine card");
      Btn(PB + "BTN_CLR", cx + Z(172), cy, Z(30), rh, "×", false, C_ON, 9, "Clear the card");
      cy += st;
      if(g_card_msg != "")
        {
         Text(PB + "cmsg", L, cy - Z(2), FitText(g_card_msg, "Segoe UI", 8, R - L), g_card.found ? C_GREEN : C_AMBER, 8);
         cy += Z(18);
        }
     }

   // ---- entry and stop
   TextV(L, cy + rh / 2, "Entry", C_DIM, 9);
   if(cards)
     {
      string es[4] = {"Market", "Zone", "Refine", "Price"};
      int ev[4] = {0, 1, 2, 3};
      string et[4] = {"Market order at the live price", "Near edge of the card's zone", "Near edge of the card's M15 refine",
                      "Your price: type it, or drag the green line"};
      Seg(PB + "BTN_EN", cx, cy, cw, rh, es, ev, 4, g_entry_src, et);
     }
   else
     {
      string es[2] = {"Market", "Price"};
      int ev[2] = {0, 3};
      string et[2] = {"Market order at the live price", "Your price: type it, or drag the green line"};
      Seg(PB + "BTN_EN", cx, cy, cw, rh, es, ev, 2, g_entry_src, et);
     }
   cy += st;
   if(cards)
     {
      string ss[5] = {"Refine", "BOS leg", "Zone", "Liq.", "Manual"};
      int sv[5] = {0, 1, 2, 3, 4};
      string sst[5] = {"Beyond the far edge of the refine", "Beyond the origin of the BOS leg", "Beyond the far edge of the zone",
                       "Beyond the liquidity level", "Your stop: type it, or drag the red line"};
      TextV(L, cy + rh / 2, "Stop", C_DIM, 9);
      Seg(PB + "BTN_SL", cx, cy, cw, rh, ss, sv, 5, g_sl_src, sst);
      cy += st;
     }
   int fw = (R - L - Z(8)) / 2, fx2 = L + fw + Z(8);
   Ed(PB + "ED_ENTRY", L, cy, fw, rh, g_entry_px > 0 ? DoubleToString(g_entry_px, _Digits) : "", "Entry price (Entry switches to Price)", "Price");
   Ed(PB + "ED_SL", fx2, cy, R - fx2, rh, g_sl_manual > 0 ? DoubleToString(g_sl_manual, _Digits) : "",
      "Stop-loss price" + (cards ? " (Stop switches to Manual)" : ""), "SL");
   cy += st;
   if(g_parts >= 2)
     {
      Ed(PB + "ED_E2", L, cy, fw, rh, g_entry2 > 0 ? DoubleToString(g_entry2, _Digits) : "", "Second entry price (empty = same as the first)", "2nd");
      Ed(PB + "ED_SH", fx2, cy, R - fx2, rh, DoubleToString(g_share1, 0), "Share of the risk on the first entry (50 = 5+5, 70 = 7+3)", "1st %");
      cy += st;
     }
   if(g_parts == 3)
     {
      Ed(PB + "ED_E3", L, cy, fw, rh, g_entry3 > 0 ? DoubleToString(g_entry3, _Digits) : "", "Third entry price (empty = same as the first)", "3rd");
      Ed(PB + "ED_SH2", fx2, cy, R - fx2, rh, DoubleToString(g_share2, 0), "Share of the risk on the second entry; the third gets the rest", "2nd %");
      cy += st;
     }
   cy += Z(6);

   // ---- risk settings (folded: one line)
   string rs = g_mode == 2 ? "Fixed " + Fmt(g_fixed, 2) + " " + Cur()
               : StringFormat("%.2f%% of ", g_percent) + (g_mode == 1 ? "equity" : Fmt(g_ref, 0));
   string ps = g_parts == 3 ? StringFormat("3 entries %.0f/%.0f/%.0f", g_share1, g_share2, 100 - g_share1 - g_share2)
               : (g_parts == 2 ? StringFormat("2 entries %.0f/%.0f", g_share1, 100 - g_share1) : "1 entry");
   rs += "  ·  " + ps + "  ·  day max " + Fmt(g_daily, 0);
   bool fr = Folded(1);
   Section(PB + "s_risk", L, R, cy, "RISK", "RISK", fr, rs, C_TXT);
   cy += Z(24);
   if(!fr)
     {
      string ms[3] = {"% of capital", "% of equity", "Fixed " + Cur()};
      int mv[3] = {0, 1, 2};
      string mt[3] = {"Risk % of the fixed reference capital (does not grow with profits)", "Risk % of the current equity",
                      "Fixed amount per trade"};
      Seg(PB + "BTN_RK", L, cy, R - L, rh, ms, mv, 3, g_mode, mt);
      cy += st;
      int w3 = (R - L - Z(16)) / 3, x2 = L + w3 + Z(8), x3 = L + 2 * (w3 + Z(8));
      Ed(PB + "ED_PCT", L, cy, w3, rh, DoubleToString(g_percent, 2), "Risk % of the reference capital or of the equity", "Risk %");
      Ed(PB + "ED_FIX", x2, cy, w3, rh, DoubleToString(g_fixed, 2), "Fixed risk per trade (" + Cur() + ")", "Fixed");
      Ed(PB + "ED_REF", x3, cy, R - x3, rh, DoubleToString(g_ref, 0), "Reference capital for '% of capital' (does not grow with profits)", "Capital");
      cy += st;
      int w2 = (R - L - Z(8)) / 2;
      Ed(PB + "ED_DAY", L, cy, w2, rh, DoubleToString(g_daily, 0), "Maximum loss per day (" + Cur() + "); the day runs from server midnight to midnight",
         "Day max");
      Ed(PB + "ED_BUF", L + w2 + Z(8), cy, R - L - w2 - Z(8), rh, DoubleToString(g_buffer, 1), "Stop distance beyond a card level (" + UnitName() + ")",
         "Buffer");
      cy += st;
      TextV(L, cy + rh / 2, "Entries", C_DIM, 9);
      string pl[3] = {"1", "2", "3"};
      int pv[3] = {1, 2, 3};
      string pt[3] = {"One entry per trade", "Two entries per trade: one slot, one stop", "Three entries per trade: one slot, one stop"};
      Seg(PB + "BTN_P", L + Z(52), cy, Z(108), rh, pl, pv, 3, g_parts, pt);
      Btn(PB + "BTN_RESET", R - Z(86), cy, Z(86), rh, "Reset all", false, C_ON, 8, "Back to the EA inputs; Trading switches OFF");
      cy += st + Z(2);
     }
   cy += Z(2);

   // ---- result card (its height comes from the measuring pass)
   int rt = cy;
   int rhc = MathMax(Z(40), g_res_h);
   color acc = !v_ready ? C_EDGE : (v_s1.ok ? C_GREEN : C_RED);
   if(!g_dry)
     {
      UiCard(L, rt, R - L, rhc, Z(10), C_CARD, C_EDGE);
      UiRound(L + 1, rt + Z(12), Z(3), MathMax(Z(6), rhc - Z(24)), Z(2), acc);
     }
   int ix = L + Z(16), ir = R - Z(14);
   int ry = rt + Z(14);
   if(!v_ready)
     {
      Text(PB + "r_big", ix, ry - Z(4), "—", C_DIM, 18, "Segoe UI Semibold");
      string ln[];
      int n = Wrap(v_err, "Segoe UI", 9, ir - ix - Z(34), 2, ln);
      for(int i = 0; i < n; i++)
         Text(PB + "r_" + IntegerToString(i + 1), ix + Z(34), ry + Z(1) + i * Z(17), ln[i], C_AMBER, 9);
      ry += Z(42);
     }
   else if(!v_s1.ok)
     {
      int tw = ir - ix;
      Text(PB + "r_big", ix, ry - Z(3), "REJECTED", C_RED, 15, "Segoe UI Semibold");
      Text(PB + "r_rk", ir, ry + Z(2), "budget " + Fmt(v_b1, 2) + " " + Cur(), C_TXT, 9, "Segoe UI Semibold", true);
      ry += Z(32);
      Text(PB + "r_1", ix, ry, FitText(StringFormat("Needed %s lot  ·  %s lot would risk %s %s", DoubleToString(v_raw1, 3),
           Lot(SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MIN)), Fmt(v_minrisk1, 2), Cur()), "Segoe UI", 8, tw), C_TXT, 8);
      ry += Z(17);
      Text(PB + "r_2", ix, ry, FitText(StringFormat("Stop %s  ·  widest for this risk %s", Dist(MathAbs(v_e1 - v_sl)),
           Dist(v_maxstop1)), "Segoe UI", 8, tw), C_TXT, 8);
      ry += Z(17);
      Text(PB + "r_3", ix, ry, cards ? "Closer entry (Zone / Refine) or a nearer stop" : "A nearer stop or a closer entry", C_DIM, 8);
      ry += Z(24);
     }
   else
     {
      string lt = Lot(v_lots);
      Text(PB + "r_big", ix, ry - Z(5), lt, C_TXT, 20, "Segoe UI Semibold");
      Text(PB + "r_unit", ix + TextW(lt, "Segoe UI Semibold", 20) + Z(6), ry + Z(12), "lot", C_DIM, 9);
      Text(PB + "r_rk", ir, ry - Z(1), "risk " + Fmt(v_total, 2) + " " + Cur(), C_GREEN, 10, "Segoe UI Semibold", true);
      bool capped = v_size_budget < v_budget - 1e-9;
      string rp = capped ? "capped by v2 " + v_cap_by + ": " + Fmt(v_size_budget, 2)
                  : StringFormat("%.0f%% of the %s budget", v_budget > 0 ? 100 * v_total / v_budget : 0, Fmt(v_budget, 2));
      Text(PB + "r_rp", ir, ry + Z(18), rp, capped ? C_AMBER : C_DIM, 8, "Segoe UI", true);
      ry += Z(42);
      Bar(ix, ry, ir - ix, v_size_budget > 0 ? v_total / v_size_budget : 0, capped ? C_AMBER : C_GREEN);
      ry += Z(14);
      if(g_parts >= 2)
        {
         KV(PB + "r_p1", ix, ir, ry, "1st", v_s1.ok ? Lot(v_s1.lot) + " lot @ " + Px(v_e1) + "  ·  " + Fmt(v_s1.risk, 2) : v_s1.why,
            v_s1.ok ? C_TXT : C_RED);
         ry += Z(18);
         KV(PB + "r_p2", ix, ir, ry, "2nd", v_s2.ok ? Lot(v_s2.lot) + " lot @ " + Px(v_e2) + "  ·  " + Fmt(v_s2.risk, 2) : v_s2.why,
            v_s2.ok ? C_TXT : C_RED);
         ry += Z(18);
        }
      if(g_parts == 3)
        {
         KV(PB + "r_p3", ix, ir, ry, "3rd", v_s3.ok ? Lot(v_s3.lot) + " lot @ " + Px(v_e3) + "  ·  " + Fmt(v_s3.risk, 2) : v_s3.why,
            v_s3.ok ? C_TXT : C_RED);
         ry += Z(18);
        }
      KV(PB + "r_es", ix, ir, ry, "Entry → SL", Px(v_e1) + "  →  " + Px(v_sl) + "  (" + Dist(MathAbs(v_e1 - v_sl)) + ")", C_TXT);
      ry += Z(18);
      double sp_pct = v_total > 0 ? 100.0 * v_cost_spread / v_total : 0;
      KV(PB + "r_sp", ix, ir, ry, "Spread now", Dist(v_spread) + " = " + Fmt(v_cost_spread, 2) + StringFormat("  (%.0f%% of the risk)", sp_pct),
         sp_pct > 25 ? C_AMBER : C_TXT);
      ry += Z(18);
      KV(PB + "r_cs", ix, ir, ry, "In the risk", "commission " + Fmt(v_cost_comm, 2) + (v_cost_slip > 0 ? "  ·  slippage ≤ " + Fmt(v_cost_slip, 2) : ""), C_DIM);
      ry += Z(18);
      KV(PB + "r_mg", ix, ir, ry, "Margin", Fmt(v_margin, 2) + " " + Cur(), C_TXT);
      ry += Z(22);
     }
   if(g_dry)
      g_res_h = ry - rt;
   cy = rt + MathMax(Z(40), g_res_h) + Z(14);

   // ---- targets (folded: one line)
   if(v_ready && v_s1.ok)
     {
      bool ft = Folded(2);
      string ts = "1R +" + Fmt(v_rw[0], 2) + "  ·  2R +" + Fmt(v_rw[1], 2) + "  ·  3R +" + Fmt(v_rw[2], 2);
      Section(PB + "s_tp", L, R, cy, "TARGETS", "TGT", ft, ts, C_GREEN);
      cy += Z(24);
      if(!ft)
        {
         for(int r = 0; r < 3; r++)
           {
            string k = PB + "tp" + IntegerToString(r);
            Pill(L, cy, IntegerToString(r + 1) + "R", C_GREEN, C_BG);
            TextV(L + Z(40), cy + Z(8), Px(v_tp[r]), C_TXT, 9);
            TextV(R - Z(100), cy + Z(8), "+" + Fmt(v_rw[r], 2), C_GREEN, 9, "Segoe UI Semibold", true);
            TextV(R, cy + Z(8), StringFormat("needs %.0f%% wins", RmBreakEvenWinRate(r + 1)), C_FAINT, 8, "Segoe UI", true);
            cy += Z(22);
           }
         cy += Z(6);
        }
     }

   // ---- checklist (2.70), then the order: only with the EA input on; panel switch starts OFF; two confirmations
   cy = DrawChecklist(L, R, cy);
   cy = DrawOrders(L, R, cy);

   int nw = MathMin(3, ArraySize(v_warn));
   for(int i = 0; i < nw; i++)
     {
      Dot(L + Z(4), cy + Z(8), C_AMBER);
      Text(PB + "w" + IntegerToString(i), L + Z(14), cy, FitText(v_warn[i], "Segoe UI", 8, R - L - Z(14)), C_AMBER, 8);
      cy += Z(17);
     }
   cy += Z(10);
   return cy + scroll;
  }

// ---------------- v2 rules section: a status banner and one tile per rule for a new order on this chart
// tile: name, value and a bar of how much is used (frac < 0: none). st 0 ok, 1 close to the limit, 2 blocks a new order
void Tile(const int x, const int y, const int w, const string name, const string val, const double frac, const int st)
  {
   if(g_dry)
      return;
   color c = st == 2 ? C_RED : (st == 1 ? C_AMBER : C_GREEN);
   int h = Z(50);
   UiCard(x, y, w, h, Z(9), st == 2 ? UiMix(C_CARD, C_RED, 0.10) : C_CARD, st == 2 ? UiMix(C_BG, C_RED, 0.45) : C_EDGE);
   UiCircle(x + Z(12), y + Z(13), Z(3), c);
   UiText(x + Z(21), y + Z(13), FitText(name, "Segoe UI", 8, w - Z(28)), C_DIM, 8, "Segoe UI", TA_LEFT | TA_VCENTER);
   UiText(x + Z(10), y + Z(30), FitText(val, "Segoe UI Semibold", 10, w - Z(18)), st == 2 ? UiMix(C_RED, clrWhite, 0.2) : C_TXT, 10,
          "Segoe UI Semibold", TA_LEFT | TA_VCENTER);
   if(frac >= 0)
      Bar(x + Z(10), y + h - Z(9), w - Z(20), frac, c);
  }

int DrawV2(const int L, const int R, int cy)
  {
   if(!g_v2on)
      return cy;                                       // the switch is at the top of the Rules tab
   bool blk = v_v2_why != "";
   int today = v_hist.trades + v_book.pending_today;
   string tmax = InpMaxTradesDay > 0 ? " / " + IntegerToString(InpMaxTradesDay) : "";
   string sum = (blk ? v_v2_short : "OK") + "  ·  trades " + IntegerToString(today) + tmax + "  ·  open risk " + Fmt(v_book.open_risk, 2);
   bool f = Folded(4);
   Section(PB + "s_v2", L, R, cy, "V2 RULES", "V2", f, sum, blk ? C_RED : C_GREEN);
   cy += Z(24);
   if(f)
      return cy;
   // status banner
   string ln[];
   int n = Wrap(blk ? "Blocked: " + v_v2_why : "All v2 rules OK for a new order", "Segoe UI Semibold", 9, R - L - Z(40), 2, ln);
   int bh = Z(14) + n * Z(17);
   color tint = blk ? C_RED : C_GREEN;
   if(!g_dry)
     {
      UiCard(L, cy, R - L, bh, Z(9), UiMix(C_BG, tint, 0.13), UiMix(C_BG, tint, 0.40));
      UiCircle(L + Z(15), cy + Z(15), Z(4), tint);
     }
   for(int i = 0; i < n; i++)
      Text(PB + "v2_st" + IntegerToString(i), L + Z(28), cy + Z(7) + i * Z(17), ln[i], UiMix(tint, clrWhite, 0.25), 9, "Segoe UI Semibold");
   cy += bh + Z(10);
   // tiles, two per row
   int tw = (R - L - Z(8)) / 2, tx2 = L + tw + Z(8), tw2 = R - tx2;
   int st_t = (InpMaxTradesDay > 0 && today + g_parts > InpMaxTradesDay) ? 2 : ((InpMaxTradesDay > 0 && today + g_parts == InpMaxTradesDay) ? 1 : 0);
   Tile(L, cy, tw, "Trades today", IntegerToString(today) + tmax, InpMaxTradesDay > 0 ? (double)today / InpMaxTradesDay : -1, st_t);
   int st_s = (InpMaxLossStreak > 0 && v_hist.streak >= InpMaxLossStreak) ? 2 : (v_hist.streak > 0 ? 1 : 0);
   Tile(tx2, cy, tw2, "Losses in a row", IntegerToString(v_hist.streak) + (InpMaxLossStreak > 0 ? " / " + IntegerToString(InpMaxLossStreak) : ""),
        InpMaxLossStreak > 0 ? (double)v_hist.streak / InpMaxLossStreak : -1, st_s);
   cy += Z(58);
   bool dayx = InpDayLossPct > 0 && v_day.net < 0 && -v_day.net >= v_day_cap - 1e-9;
   double dfr = (InpDayLossPct > 0 && v_day_cap > 0) ? MathMax(0.0, -v_day.net) / v_day_cap : -1;
   Tile(L, cy, tw, "Day P/L  ·  stop " + Pc(InpDayLossPct), Fmt(v_day.net, 2) + (InpDayLossPct > 0 ? " / -" + Fmt(v_day_cap, 2) : ""), dfr,
        dayx ? 2 : (dfr >= 0.5 ? 1 : 0));
   Tile(tx2, cy, tw2, "Pause after a loss", v_pause_left > 0 ? Mins(v_pause_left) + " left" : (InpPauseMin > 0 ? "ready" : "off"),
        (v_pause_left > 0 && InpPauseMin > 0) ? (double)v_pause_left / InpPauseMin : -1, v_pause_left > 0 ? 2 : 0);
   cy += Z(58);
   bool ifull = InpIdeaRiskPct > 0 && v_book.idea_risk >= v_idea_cap - 1e-9;
   bool lfull = InpIdeaMaxLegs > 0 && v_book.idea_legs + g_parts > InpIdeaMaxLegs;
   double ifr = (InpIdeaRiskPct > 0 && v_idea_cap > 0) ? v_book.idea_risk / v_idea_cap : -1;
   Tile(L, cy, tw, "Idea " + (g_buy ? "BUY" : "SELL") + "  ·  legs " + IntegerToString(v_book.idea_legs) +
        (InpIdeaMaxLegs > 0 ? "/" + IntegerToString(InpIdeaMaxLegs) : ""), Fmt(v_book.idea_risk, 2) + " / " + Fmt(v_idea_cap, 2), ifr,
        (ifull || lfull || v_book.idea_no_sl > 0) ? 2 : (ifr >= 0.7 ? 1 : 0));
   bool ofull = InpOpenRiskPct > 0 && v_book.open_risk >= v_open_cap - 1e-9;
   double ofr = (InpOpenRiskPct > 0 && v_open_cap > 0) ? v_book.open_risk / v_open_cap : -1;
   Tile(tx2, cy, tw2, "Open risk  ·  " + Pc(InpOpenRiskPct), Fmt(v_book.open_risk, 2) + " / " + Fmt(v_open_cap, 2), ofr,
        (ofull || v_book.no_sl > 0) ? 2 : (ofr >= 0.7 ? 1 : 0));
   cy += Z(58);
   bool mk_ok = g_mk_allow[g_fam < 0 ? RM_FAMILIES : g_fam];
   string ord = (InpMinTpR > 0 ? "TP >= " + DoubleToString(InpMinTpR, 0) + "R" : "any TP") +
                (v_min_stop > 0 ? "  ·  stop >= " + Dist(v_min_stop) + " (" + XText(StopSpreads()) + " x spread)" : "") +
                "  ·  " + MarketName(g_fam) + (mk_ok ? " ticked" : " not ticked");
   Text(PB + "v2_x", L, cy, FitText("Order: " + ord, "Segoe UI", 8, R - L), mk_ok ? C_FAINT : C_RED, 8);
   cy += Z(24);
   return cy;
  }

// ---------------- sessions section: the window rule switch, and Asia / London / New York each on or off with its times
// one session: a chip (click = tick / untick) and its start and end fields (server time)
int SessionRow(const int s, const int L, const int R, int y)
  {
   int rh = Z(26);
   string id = PB + "BTN_SES" + IntegerToString(s);
   bool on = g_ses_on[s], now = v_ses_now == s, hov = g_hover == id;
   int chw = Z(108);
   if(!g_dry)
     {
      color bg = on ? UiMix(C_BG, C_ON, hov ? 0.34 : 0.24) : (hov ? C_HOVER : C_CTRL);
      UiCard(L, y, chw, rh, Z(8), bg, on ? UiMix(C_BG, C_ON, 0.60) : bg);
      int bx = L + Z(9), by = y + rh / 2 - Z(6);
      if(on)
        {
         UiRound(bx, by, Z(12), Z(12), Z(3), C_ON);
         UiCheck(bx + Z(6), by + Z(6), Z(3), clrWhite);
        }
      else
         UiCard(bx, by, Z(12), Z(12), Z(3), C_CARD, C_FAINT);
      UiText(L + Z(28), y + rh / 2, SES_NAME[s], on ? C_TXT : C_DIM, 9, on ? "Segoe UI Semibold" : "Segoe UI", TA_LEFT | TA_VCENTER);
      if(now)
         UiCircle(L + chw - Z(11), y + rh / 2, Z(3), C_GREEN);
      UiZone(id, L, y, chw, rh, (on ? "Ticked: click to untick " : "Not ticked: click to tick ") + SES_NAME[s] + (now ? " (open now)" : ""));
     }
   int fx = L + chw + Z(8);
   int fw = (R - fx - Z(14)) / 2;
   Ed(PB + "ED_S" + IntegerToString(s) + "A", fx, y, fw, rh, RmHhmmText(g_ses_a[s]), SES_NAME[s] + " start, server time (HH:MM)", "from");
   TextV(fx + fw + Z(4), y + rh / 2, "–", C_FAINT, 9);
   Ed(PB + "ED_S" + IntegerToString(s) + "B", fx + fw + Z(14), y, R - (fx + fw + Z(14)), rh, RmHhmmText(g_ses_b[s]),
      SES_NAME[s] + " end, server time (HH:MM)", "to");
   return y + Z(32);
  }

int DrawSessions(const int L, const int R, int cy)
  {
   if(!g_v2on)
      return cy;
   bool f = Folded(5);
   string sum = !g_win_rule ? "off: orders at any time"
                : (!v_win_on ? "no session ticked" : SessionsText(false) + "  ·  " + (v_win_in ? Mins(v_win_min) + " left" : "opens in " + Mins(v_win_min)));
   color sc = !g_win_rule ? C_DIM : ((v_win_on && v_win_in) ? C_GREEN : C_AMBER);
   Section(PB + "s_ses", L, R, cy, "SESSIONS", "SES", f, sum, sc);
   cy += Z(24);
   if(f)
      return cy;
   TextV(L, cy + Z(9), g_win_rule ? "Trade only in the ticked sessions" : "Window off: orders at any time", g_win_rule ? C_TXT : C_DIM, 9,
         "Segoe UI Semibold");
   Toggle(PB + "BTN_WIN", R - Z(34), cy, g_win_rule, C_ON,
          g_win_rule ? "Window rule ON: click to switch it off" : "Window rule OFF: click to switch it on");
   cy += Z(28);
   if(g_win_rule)
     {
      for(int s = 0; s < 3; s++)
         cy = SessionRow(s, L, R, cy);
      Text(PB + "ses_st", L, cy - Z(1), FitText(WindowText() + "  ·  server " + TimeToString(TimeTradeServer(), TIME_MINUTES), "Segoe UI", 8, R - L),
           (v_win_on && v_win_in) ? C_GREEN : C_AMBER, 8);
      cy += Z(20);
     }
   return cy + Z(6);
  }

// ---------------- markets: the broker's symbols of the six markets, found by name in its whole symbol list
string MarketName(const int f) { return f >= 0 && f < RM_FAMILIES ? RM_FAM_NAME[f] : "other symbol"; }

void FindMarkets()
  {
   int best[RM_FAMILIES];
   for(int f = 0; f < RM_FAMILIES; f++)
     {
      best[f] = -1000000;
      g_mk_sym[f] = "";
     }
   string path = SymbolInfoString(_Symbol, SYMBOL_PATH);
   int sl = StringFind(path, "\\");
   string root = sl > 0 ? StringSubstr(path, 0, sl + 1) : "";   // e.g. "Cent\" on a cent account
   int n = SymbolsTotal(false);
   for(int i = 0; i < n; i++)
     {
      string s = SymbolName(i, false);
      int f = RmFamily(s, SymbolInfoString(s, SYMBOL_DESCRIPTION));
      if(f < 0)
         continue;
      long tm = SymbolInfoInteger(s, SYMBOL_TRADE_MODE);
      int sc = (tm == SYMBOL_TRADE_MODE_FULL ? 1000 : (tm != SYMBOL_TRADE_MODE_DISABLED ? 500 : 0))   // tradable first
               + (root != "" && StringFind(SymbolInfoString(s, SYMBOL_PATH), root) == 0 ? 200 : 0)     // same account group
               + (SymbolInfoInteger(s, SYMBOL_VISIBLE) != 0 ? 100 : 0)                                // in Market Watch
               + (s == _Symbol ? 5000 : 0) - StringLen(s);
      if(sc > best[f])
        {
         best[f] = sc;
         g_mk_sym[f] = s;
        }
     }
   g_fam = RmFamily(_Symbol, SymbolInfoString(_Symbol, SYMBOL_DESCRIPTION));
  }

// spread of a symbol in its own units (pips on forex pairs, price points elsewhere); "" without a quote
string SpreadOf(const string s)
  {
   double b = SymbolInfoDouble(s, SYMBOL_BID), a = SymbolInfoDouble(s, SYMBOL_ASK);
   if(s == "" || b <= 0 || a <= 0)
      return "";
   long cm = SymbolInfoInteger(s, SYMBOL_TRADE_CALC_MODE);
   int dg = (int)SymbolInfoInteger(s, SYMBOL_DIGITS);
   bool fx = (cm == SYMBOL_CALC_MODE_FOREX || cm == SYMBOL_CALC_MODE_FOREX_NO_LEVERAGE) && RmFamily(s, "") != 2 && RmFamily(s, "") != 3;
   double u = fx ? ((dg == 3 || dg == 5) ? 10 * SymbolInfoDouble(s, SYMBOL_POINT) : SymbolInfoDouble(s, SYMBOL_POINT)) : 1.0;
   double v = (a - b) / u;
   return Fmt(v, v < 10 ? 2 : 1) + (fx ? " pips" : " pts");
  }

// commission per 1.00 lot both ways: the input, or the average of your deals on this symbol in the last 180 days
void FindCommission()
  {
   g_comm_lot = 0;
   if(InpCommission >= 0)
     {
      g_comm_lot = InpCommission;
      return;
     }
   datetime now = TimeCurrent();
   if(!HistorySelect(now - 180 * 86400, now + 60))
      return;
   double c = 0, v = 0;
   int n = HistoryDealsTotal();
   for(int i = 0; i < n; i++)
     {
      ulong t = HistoryDealGetTicket(i);
      if(t == 0 || HistoryDealGetString(t, DEAL_SYMBOL) != _Symbol)
         continue;
      long typ = HistoryDealGetInteger(t, DEAL_TYPE);
      if(typ != DEAL_TYPE_BUY && typ != DEAL_TYPE_SELL)
         continue;
      c += HistoryDealGetDouble(t, DEAL_COMMISSION) + HistoryDealGetDouble(t, DEAL_FEE);
      v += HistoryDealGetDouble(t, DEAL_VOLUME);
     }
   if(v > 0)
      g_comm_lot = MathMax(0.0, -c / v * 2.0);    // per side, entry and exit
  }

// one market: tick box (orders allowed), name and the broker's symbol (click: open it on this chart), spread
int MarketRow(const int f, const int L, const int R, int y)
  {
   int rh = Z(26);
   bool other = f >= RM_FAMILIES;
   string sym = other ? _Symbol : g_mk_sym[f];
   bool on = g_mk_allow[f], cur = other ? true : (f == g_fam);
   string aid = PB + "BTN_MKA" + IntegerToString(f), oid = PB + "BTN_MKO" + IntegerToString(f);
   if(!g_dry)
     {
      bool ha = g_hover == aid, ho = g_hover == oid;
      if(cur)
         UiRound(L, y, R - L, rh, Z(8), UiMix(C_BG, C_ON, 0.16));
      else if(ho)
         UiRound(L, y, R - L, rh, Z(8), C_CTRL);
      int bx = L + Z(8), by = y + rh / 2 - Z(6);
      if(on)
        {
         UiRound(bx, by, Z(12), Z(12), Z(3), ha ? UiMix(C_ON, clrWhite, 0.15) : C_ON);
         UiCheck(bx + Z(6), by + Z(6), Z(3), clrWhite);
        }
      else
         UiCard(bx, by, Z(12), Z(12), Z(3), ha ? C_HOVER : C_CARD, C_FAINT);
      UiZone(aid, L, y, Z(28), rh, on ? "Orders allowed on " + MarketName(f) + ": click to block them" : "Orders blocked: click to allow them");
      UiText(L + Z(30), y + rh / 2, other ? "Other" : RM_FAM_NAME[f], cur || on ? C_TXT : C_DIM, 9, cur ? "Segoe UI Semibold" : "Segoe UI",
             TA_LEFT | TA_VCENTER);
      UiText(L + Z(112), y + rh / 2, sym == "" ? "not offered" : FitText(sym, "Segoe UI", 8, Z(70)), sym == "" ? C_FAINT : C_DIM, 8, "Segoe UI",
             TA_LEFT | TA_VCENTER);
      string sp = sym == "" ? "" : SpreadOf(sym);
      UiText(R - Z(64), y + rh / 2, sp == "" ? (sym == "" ? "" : "no quote") : sp, C_FAINT, 8, "Segoe UI", TA_RIGHT | TA_VCENTER);
      if(!cur && sym != "")
         UiZone(oid, L + Z(28), y, R - L - Z(90), rh, "Open " + sym + " on this chart");
     }
   Ed(PB + "ED_MKX" + IntegerToString(f), R - Z(56), y, Z(56), rh, XText(g_mk_x[f]),
      "Stop at least this many spreads from every entry on " + (other ? "other symbols" : RM_FAM_NAME[f]) + " (0 = rule off)", "×");
   return y + Z(29);
  }

int DrawMarkets(const int L, const int R, int cy)
  {
   bool f = Folded(6);
   int fi = g_fam < 0 ? RM_FAMILIES : g_fam;
   int non = 0;
   for(int k = 0; k <= RM_FAMILIES; k++)
      if(g_mk_allow[k])
         non++;
   string sum = MarketName(g_fam) + " (" + _Symbol + ")  ·  " + (g_mk_allow[fi] ? "orders allowed" : "orders blocked") + "  ·  " +
                IntegerToString(non) + " ticked  ·  stop >= " + XText(StopSpreads()) + "x spread";
   Section(PB + "s_mk", L, R, cy, "MARKETS", "MKT", f, sum, g_mk_allow[fi] ? C_TXT : C_RED);
   cy += Z(24);
   if(f)
      return cy;
   for(int k = 0; k < RM_FAMILIES; k++)
      cy = MarketRow(k, L, R, cy);
   if(g_fam < 0)
      cy = MarketRow(RM_FAMILIES, L, R, cy);
   Text(PB + "mk_n", L, cy + Z(1), FitText("Tick = orders allowed  ·  name = open it here  ·  × = stop at least that many spreads (0 = off)", "Segoe UI", 8, R - L), C_FAINT, 8);
   return cy + Z(24);
  }

// delete panel objects that were not drawn this time (fields that are not shown any more)
void Sweep()
  {
   for(int i = ObjectsTotal(0, -1, -1) - 1; i >= 0; i--)
     {
      string n = ObjectName(0, i, -1, -1);
      if(StringFind(n, PB) != 0 && StringFind(n, PH) != 0)
         continue;
      bool keep = false;
      for(int k = ArraySize(g_seen) - 1; k >= 0; k--)
         if(g_seen[k] == n) { keep = true; break; }
      if(!keep)
         ObjectDelete(0, n);
     }
  }

// the tool's lines and zone boxes; true when one was made just now (then it lies over the panel until RaisePanel)
bool DrawChart()
  {
   bool show = v_ready, made = false;
   made = HLine("SL", show ? v_sl : 0, C_RED, STYLE_SOLID, 2, true, "SL  -" + Fmt(v_total, 2)) || made;
   made = HLine("EN", show ? v_e1 : 0, C_GREEN, STYLE_SOLID, 1, true, "Entry") || made;
   made = HLine("E2", (show && g_parts >= 2) ? v_e2 : 0, C_GREEN, STYLE_DASH, 1, true, "2nd entry") || made;
   made = HLine("E3", (show && g_parts == 3) ? v_e3 : 0, C_GREEN, STYLE_DASH, 1, true, "3rd entry") || made;
   for(int r = 0; r < 3; r++)
      made = HLine("TP" + IntegerToString(r + 1), (show && v_s1.ok && (g_tp_r != r + 1 || TrailTp())) ? v_tp[r] : 0, C_GREEN, STYLE_DOT, 1,
                   false, StringFormat("TP %dR  +%.2f", r + 1, v_rw[r])) || made;
   double tp = (show && v_s1.ok) ? SelTp() : 0;
   bool tp_ok = tp > 0 && (g_buy ? tp > v_e1 : tp < v_e1);
   made = HLine("TPL", tp, C_GREEN, STYLE_SOLID, 2, !TrailTp(),
                TrailTp() ? "TP of the trailing (moved on later)" : "Take-profit: drag it (TP switches to Line)") || made;
   made = RiskBox(show && v_s1.ok && g_box, tp_ok ? tp : 0) || made;
   made = NextSteps() || made;
   made = HLine("INV", g_card.found ? g_card.invalidation : 0, C_AMBER, STYLE_DASHDOT, 1, false,
                "Zone invalid on a " + g_card.tf + " body close beyond") || made;
   if(g_card.found)
     {
      datetime t1 = CardTime();
      made = Box("ZONE", g_card.zone_low, g_card.zone_high, g_card.buy ? C'28,52,88' : C'88,48,30', true, t1) || made;
      made = Box("REF", g_card.ref_low, g_card.ref_high, g_card.buy ? C'70,140,230' : C'235,140,60', false, t1) || made;
     }
   else
     {
      ObjectDelete(0, PC + "ZONE");
      ObjectDelete(0, PC + "REF");
     }
   return made;
  }

// MT5 draws chart objects in the order they were made, the newest on top. When a line or a drawing was made after the
// panel, the panel is made again (canvas first, then its fields) so that it is drawn above everything on the chart.
void RaisePanel()
  {
   UiDestroy();
   ObjectsDeleteAll(0, PB);
   ObjectsDeleteAll(0, PH);
  }

// ---------------- orders (version 2): every lock is in BuildPlan; sending only in DoConfirm after the Windows dialog
string OrderLine(const RmOrder &o)
  {
   return StringFormat("%s %s @ %s  SL %s%s", RmTypeName(o.type), Lot(o.lot), o.market ? "market" : Px(o.price), Px(o.sl),
                       o.tp > 0 ? "  TP " + Px(o.tp) : "") + (o.expire > 0 ? "  until " + TimeToString(o.expire, TIME_MINUTES) : "");
  }

// an open position on this symbol and side that is in loss: a new order would average down
bool LosingSameSide()
  {
   for(int i = PositionsTotal() - 1; i >= 0; i--)
     {
      ulong tk = PositionGetTicket(i);
      if(tk == 0 || PositionGetString(POSITION_SYMBOL) != _Symbol)
         continue;
      bool pbuy = PositionGetInteger(POSITION_TYPE) == POSITION_TYPE_BUY;
      if(pbuy == g_buy && PositionGetDouble(POSITION_PROFIT) < 0)
         return true;
     }
   return false;
  }

bool BuildPlan(string &why)
  {
   why = "";
   g_plan_n = 0;
   if(!InpTradingEnabled) { why = "order buttons are off in the EA inputs"; return false; }
   if(!g_trade_on) { why = "switch Trading ON first"; return false; }
   if(!v_ready) { why = v_err; return false; }
   if(!v_s1.ok || (g_parts >= 2 && !v_s2.ok) || (g_parts == 3 && !v_s3.ok)) { why = "volume rejected for this risk"; return false; }
   if(v_sl <= 0) { why = "no stop-loss"; return false; }
   if(v_slots_left < 1 || v_total > v_left + 1e-6) { why = "daily loss limit: no room for this trade today"; return false; }
   if(v_margin > AccountInfoDouble(ACCOUNT_MARGIN_FREE)) { why = "not enough free margin"; return false; }
   if(SymbolInfoInteger(_Symbol, SYMBOL_TRADE_MODE) == SYMBOL_TRADE_MODE_DISABLED) { why = "this symbol cannot be traded"; return false; }
   bool market = g_entry_src == 0;
   if(market && (v_bid <= 0 || v_age > 10)) { why = "no fresh quote for a market order"; return false; }
   if(market && SpreadLimit(v_bid) > 0 && v_spread > SpreadLimit(v_bid) + 1e-12) { why = "spread too wide for a market order"; return false; }
   if(LosingSameSide()) { why = "a position on this side is in loss: no averaging down"; return false; }
   if(g_v2on && v_v2_why != "") { why = "v2 rule: " + v_v2_why; return false; }
   if(g_news_on && v_news_lock) { why = "news lock: " + v_news_cur + " " + v_news_name; return false; }
   if(!ChecklistOk()) { why = "checklist: tick every item first"; return false; }
   double tp = SelTp();                     // trailing on: the first step + lead (4R), moved on later
   datetime exp = PendingExpiry();
   g_plan[0] = RmBuildOrder(_Symbol, g_buy, market, v_e1, v_sl, tp, v_s1.lot, exp);
   g_plan_n = 1;
   if(g_parts >= 2)
     {
      g_plan[1] = RmBuildOrder(_Symbol, g_buy, market && g_entry2 <= 0, v_e2, v_sl, tp, v_s2.lot, exp);
      g_plan_n = 2;
     }
   if(g_parts == 3)
     {
      g_plan[2] = RmBuildOrder(_Symbol, g_buy, market && g_entry3 <= 0, v_e3, v_sl, tp, v_s3.lot, exp);
      g_plan_n = 3;
     }
   for(int i = 0; i < g_plan_n; i++)
      if(!g_plan[i].ok)
        {
         why = (g_plan_n >= 2 ? "entry " + IntegerToString(i + 1) + ": " : "") + g_plan[i].why;
         return false;
        }
   return true;
  }

// step 1: the order button shows what would be sent
void StartConfirm()
  {
   string why = "";
   Calc();
   g_order_ok = false;
   g_msg_at = GetTickCount();
   if(!BuildPlan(why))
     {
      g_confirm = false;
      g_order_msg = "Not ready: " + why;
      return;
     }
   g_confirm = true;
   g_confirm_at = GetTickCount();
   g_order_msg = "";
  }

// step 2: same plan as in step 1, then the Windows dialog (default button = No), then the orders
void DoConfirm()
  {
   if(!g_confirm)
      return;
   g_confirm = false;
   g_order_ok = false;
   if(GetTickCount() - g_confirm_at > (uint)MathMax(5, InpConfirmSeconds) * 1000)
     {
      g_order_msg = "Confirmation expired: nothing sent";
      return;
     }
   RmOrder before[3];
   int nb = g_plan_n;
   for(int i = 0; i < nb; i++)
      before[i] = g_plan[i];
   string why = "";
   Calc();
   if(!BuildPlan(why))
     {
      g_order_msg = "Not sent: " + why;
      return;
     }
   bool changed = nb != g_plan_n;
   for(int i = 0; i < g_plan_n && !changed; i++)
      changed = before[i].type != g_plan[i].type || MathAbs(before[i].lot - g_plan[i].lot) > 1e-9 ||
                MathAbs(before[i].sl - g_plan[i].sl) > 1e-9 || MathAbs(before[i].tp - g_plan[i].tp) > 1e-9 ||
                (!g_plan[i].market && MathAbs(before[i].price - g_plan[i].price) > 1e-9);
   if(changed)
     {
      g_order_msg = "Levels changed since step 1: nothing sent, check and press again";
      return;
     }
   string lines = "";
   for(int i = 0; i < g_plan_n; i++)
      lines += OrderLine(g_plan[i]) + "\n";
   string txt = StringFormat("Send %d REAL order(s) on %s?\n\n%s\nRisk %s %s  (left today %s)\n\n"
                             "This is not a test: the order goes to the broker.", g_plan_n, _Symbol, lines, Fmt(v_total, 2), Cur(),
                             Fmt(v_left, 2));
   if(g_lang == 1)
      txt = StringFormat("ارسال %d سفارش واقعی روی %s؟\n\n%s\nریسک %s %s  (مانده‌ی امروز %s)\n\nاین آزمایش نیست: سفارش به بروکر فرستاده می‌شود.",
                         g_plan_n, _Symbol, lines, Fmt(v_total, 2), Cur(), Fmt(v_left, 2));
   int ans = MessageBox(txt, g_lang == 1 ? "مدیر ریسک اسلات - تأیید ۲ از ۲" : RM_TITLE + " - confirm 2 of 2",
                        MB_YESNO | MB_ICONWARNING | MB_DEFBUTTON2 | RtlFlags());
   if(ans != IDYES)
     {
      g_order_msg = "Cancelled: nothing sent";
      return;
     }
   if(!TerminalInfoInteger(TERMINAL_TRADE_ALLOWED) || !MQLInfoInteger(MQL_TRADE_ALLOWED))
     {
      g_order_msg = "Not sent: MT5 Algo Trading is off (toolbar button, and 'Allow Algo Trading' in the EA settings)";
      return;
     }
   string cmt = "RM" + (g_card.found ? " A" + IntegerToString(g_card.no) : "") + StringFormat(" S%d", v_slots_all - v_slots_left + 1);
   string out = "";
   bool all = true;
   for(int i = 0; i < g_plan_n; i++)
     {
      string m = "";
      bool ok = RmSendOrder(_Symbol, g_plan[i], InpMagic, cmt + (g_plan_n >= 2 ? StringFormat(" P%d", i + 1) : ""),
                            (ulong)MathMax(0, InpDeviation), m);
      all = all && ok;
      out += (i > 0 ? "  |  " : "") + (ok ? "Sent " : "FAILED ") + m;
      Print(RM_TITLE, ": ", ok ? "sent " : "failed ", m);
     }
   g_order_ok = all;
   g_order_msg = out;
   if(all)
      for(int i = 0; i < 5; i++)
         g_ck[i] = false;                    // the checklist is ticked again for the next order
   g_msg_at = GetTickCount();
   if(all && g_qp)
      QpOff();                                 // 2.90: the lines go once the order is sent
  }

int DrawOrders(const int L, const int R, int cy)
  {
   if(!InpTradingEnabled)
     {
      Text(PB + "o_off", L, cy, FitText("Orders off (EA input 'Allow order buttons'): calculation only", "Segoe UI", 8, R - L), C_FAINT, 8);
      return cy + Z(22);
     }
   Section(PB + "s_ord", L, R, cy, "ORDER");
   cy += Z(24);
   int rh = Z(26);
   Toggle(PB + "BTN_TRADE", L, cy + Z(4), g_trade_on, C_SELON,
          g_trade_on ? "Click to lock the order button" : "Click to allow orders (each order still needs two confirmations)");
   TextV(L + Z(42), cy + rh / 2, g_trade_on ? "Trading ON" : "Trading OFF", g_trade_on ? C_RED : C_DIM, 9, "Segoe UI Semibold");
   TextV(L + Z(130), cy + rh / 2, "TP", C_DIM, 9);
   string tps[5] = {"none", "1R", "2R", "3R", "Line"};
   int tv[5] = {0, 1, 2, 3, 4};
   string tt[5] = {"Order without a take-profit", "Take-profit at 1R", "Take-profit at 2R", "Take-profit at 3R",
                   "Take-profit at the TP line: drag it on the chart"};
   int tx0 = L + Z(150);
   if(TrailTp())
      TextV(tx0, cy + rh / 2, FitText(XText(OrderTpR()) + "R, then moved by the trailing", "Segoe UI", 8, R - tx0), C_GREEN, 8);
   else
      Seg(PB + "BTN_TP", tx0, cy, R - tx0, rh, tps, tv, 5, g_tp_r, tt);
   cy += Z(34);
   if(!g_confirm)
     {
      bool v2ok = !g_v2on || v_v2_why == "";
      bool nwok = !(g_news_on && v_news_lock), ckok = ChecklistOk();
      bool can = g_trade_on && v_ready && v_s1.ok && v2ok && nwok && ckok;
      string side = g_buy ? "BUY" : "SELL";
      string act = side + (g_entry_src == 0 ? " now" : " order") + "  ·  " + Lot(v_lots) + " lot  ·  risk " + Fmt(v_total, 2);
      string t = can ? act : (!g_trade_on ? "Order button locked (Trading OFF)"
                 : ((!v_ready || !v_s1.ok) ? "Order: set entry and stop first" : (!v2ok ? "Locked by v2: " + v_v2_short
                 : (!nwok ? "Locked: news " + v_news_cur + " " + v_news_name : "Tick the checklist first"))));
      Btn(PB + "BTN_ORDER", L, cy, R - L, Z(38), t, can, g_buy ? C_BUYON : C_SELON, 10, "Step 1 of 2: shows the order to confirm");
      cy += Z(46);
     }
   else
     {
      int secs = MathMax(0, InpConfirmSeconds - (int)((GetTickCount() - g_confirm_at) / 1000));
      int tw2 = R - L - Z(24);
      int y0 = cy;
      int chh = MathMax(Z(60), g_cf_h);
      if(!g_dry)
         UiCard(L, cy, R - L, chh, Z(10), UiMix(C_BG, C_AMBER, 0.08), UiMix(C_BG, C_AMBER, 0.55));
      Text(PB + "cf_t", L + Z(12), cy + Z(10), StringFormat("Confirm 1 of 2  ·  %d s left", secs), C_AMBER, 9, "Segoe UI Semibold");
      int yy = cy + Z(32);
      for(int i = 0; i < g_plan_n; i++)
        {
         string head = (g_plan_n >= 2 ? IntegerToString(i + 1) + ")  " : "") + RmTypeName(g_plan[i].type) + "  " + Lot(g_plan[i].lot) +
                       " lot  @ " + (g_plan[i].market ? "market" : Px(g_plan[i].price));
         string stops = "SL " + Px(g_plan[i].sl) + (g_plan[i].tp > 0 ? "  ·  TP " + Px(g_plan[i].tp) : "  ·  no TP") +
                        (g_plan[i].expire > 0 ? "  ·  until " + TimeToString(g_plan[i].expire, TIME_MINUTES) : "");
         Text(PB + "cf_l" + IntegerToString(i), L + Z(12), yy, FitText(head, "Segoe UI Semibold", 9, tw2), C_TXT, 9, "Segoe UI Semibold");
         yy += Z(16);
         Text(PB + "cf_s" + IntegerToString(i), L + Z(12), yy, FitText(stops, "Segoe UI", 8, tw2), C_DIM, 8);
         yy += Z(19);
        }
      Text(PB + "cf_r", L + Z(12), yy, FitText("Risk " + Fmt(v_total, 2) + " " + Cur() + "  ·  left today " + Fmt(v_left, 2),
           "Segoe UI", 8, tw2), C_DIM, 8);
      yy += Z(20);
      int bw2 = (R - L - Z(32)) / 2;
      Btn(PB + "BTN_CONFIRM", L + Z(12), yy, bw2, Z(30), "Confirm", true, g_buy ? C_BUYON : C_SELON, 9,
          "Step 2 of 2 opens a Windows dialog (default answer: No)");
      Btn(PB + "BTN_CANCEL", L + Z(20) + bw2, yy, R - L - Z(32) - bw2, Z(30), "Cancel", false, C_ON, 9, "Nothing is sent");
      yy += Z(42);
      if(g_dry)
         g_cf_h = yy - y0;
      cy = y0 + MathMax(Z(60), g_cf_h) + Z(8);
     }
   if(g_order_msg != "")
     {
      string ln[];
      int n = Wrap(g_order_msg, "Segoe UI", 8, R - L, 2, ln);
      for(int i = 0; i < n; i++)
        {
         Text(PB + "o_msg" + IntegerToString(i), L, cy, ln[i], g_order_ok ? C_GREEN : C_AMBER, 8);
         cy += Z(15);
        }
      cy += Z(4);
     }
   return cy + Z(4);
  }

// ================= 2.70: settings in the panel, presets, tabs, hotkeys, news lock, checklist, today's card and the
// journal file, partial close, cancelling pending orders, ATR / swing trailing, Persian labels (test)

// ---------------- panel settings: one choice for every chart (terminal global variables RM_S_<key>); the EA inputs
// give the values at the first start (and after "Reset all")
double SGet(const string k, const double d) { string n = "RM_S_" + k; return GlobalVariableCheck(n) ? GlobalVariableGet(n) : d; }
void   SSet(const string k, const double v) { GlobalVariableSet("RM_S_" + k, v); }

void LoadSettings()
  {
   g_v2on = SGet("v2", InpV2On) != 0;
   g_tr_start = SGet("trst", InpTrailStartR); g_tr_step = SGet("trsp", InpTrailStepR);
   g_tr_lag = SGet("trlg", InpTrailLagR); g_tr_lead = SGet("trld", InpTrailTpLeadR);
   g_tr_cost = SGet("trcc", InpTrailCoverCosts) != 0;
   g_tr_mode = (int)SGet("trm", (double)InpTrailMode);
   g_tr_atr_k = SGet("atrk", InpTrailAtrK); g_tr_atr_n = (int)SGet("atrn", InpTrailAtrN);
   g_tr_swing = (int)SGet("swb", InpTrailSwing); g_tr_tf = (int)SGet("trtf", 1);
   g_push = SGet("push", InpPush) != 0; g_push_tr = SGet("psht", InpPushTrail) != 0; g_push_cl = SGet("pshc", InpPushClose) != 0;
   g_push_day = SGet("pshd", InpPushDay) != 0; g_push_ses = SGet("pshs", InpPushSession) != 0;
   g_box = SGet("box", InpRiskBox) != 0; g_hot = SGet("hot", InpHotkeys) != 0;
   g_zoom_i = (int)SGet("zoom", 1); g_width_i = (int)SGet("width", 1); g_lang = (int)SGet("lang", 0);
   g_news_on = SGet("nwon", InpNewsLock) != 0; g_news_before = (int)SGet("nwb", InpNewsBefore);
   g_news_after = (int)SGet("nwa", InpNewsAfter); g_news_imp = (int)SGet("nwi", InpNewsMedium ? 1 : 0);
   g_chk_on = SGet("ckon", 0) != 0;
   g_pc_r = SGet("pcr", InpPartialR); g_pc_pct = SGet("pcp", InpPartialPct);
   g_theme = (int)SGet("theme", 0); g_acc_i = (int)SGet("acc", 0); g_acc_custom = (color)(int)SGet("accc", (double)(int)C'59,130,246');
   g_bs_i = (int)SGet("bsc", 0); g_font_i = (int)SGet("font", 0); g_contrast = SGet("hcon", 1) != 0;
   g_qp_k = SGet("qpk", 1.5); g_qp_tf = (int)SGet("qptf", 1);
   if(g_theme < 0 || g_theme > 2) g_theme = 0;
   if(g_acc_i < 0 || g_acc_i > 5) g_acc_i = 0;
   if(g_bs_i < 0 || g_bs_i > 1) g_bs_i = 0;
   if(g_font_i < 0 || g_font_i > 4) g_font_i = 0;
   if(g_qp_tf < 0 || g_qp_tf > 2) g_qp_tf = 1;
   if(g_qp_k <= 0) g_qp_k = 1.5;
   if(g_tr_mode < 0 || g_tr_mode > 2) g_tr_mode = 0;
   if(g_tr_tf < 0 || g_tr_tf > 2) g_tr_tf = 1;
   if(g_zoom_i < 0 || g_zoom_i > 3) g_zoom_i = 1;
   if(g_width_i < 0 || g_width_i > 2) g_width_i = 1;
   if(g_lang < 0 || g_lang > 1) g_lang = 0;
   if(g_news_imp < 0 || g_news_imp > 1) g_news_imp = 0;
   if(g_tr_atr_n < 2) g_tr_atr_n = 14;
   if(g_tr_swing < 2) g_tr_swing = 5;
  }

void SaveSettings()
  {
   SSet("v2", g_v2on); SSet("trst", g_tr_start); SSet("trsp", g_tr_step); SSet("trlg", g_tr_lag); SSet("trld", g_tr_lead);
   SSet("trcc", g_tr_cost); SSet("trm", g_tr_mode); SSet("atrk", g_tr_atr_k); SSet("atrn", g_tr_atr_n); SSet("swb", g_tr_swing);
   SSet("trtf", g_tr_tf); SSet("push", g_push); SSet("psht", g_push_tr); SSet("pshc", g_push_cl); SSet("pshd", g_push_day);
   SSet("pshs", g_push_ses); SSet("box", g_box); SSet("hot", g_hot); SSet("zoom", g_zoom_i); SSet("width", g_width_i);
   SSet("lang", g_lang); SSet("nwon", g_news_on); SSet("nwb", g_news_before); SSet("nwa", g_news_after); SSet("nwi", g_news_imp);
   SSet("ckon", g_chk_on); SSet("pcr", g_pc_r); SSet("pcp", g_pc_pct);
   SSet("theme", g_theme); SSet("acc", g_acc_i); SSet("accc", (double)(int)g_acc_custom); SSet("bsc", g_bs_i); SSet("font", g_font_i);
   SSet("hcon", g_contrast); SSet("qpk", g_qp_k); SSet("qptf", g_qp_tf);
  }

// panel size: zoom (fonts and spacing) and width
void ApplySize()
  {
   double zs[4] = {0.9, 1.0, 1.15, 1.3};
   int ws[3] = {300, 332, 380};
   g_zoom = zs[g_zoom_i];
   UiZoom = g_zoom;
   g_s = MathMax(1.0, MathMin(3.0, TerminalInfoInteger(TERMINAL_SCREEN_DPI) / 96.0)) * g_zoom;
   g_pw = ws[g_width_i];
   bool fa = g_lang == 1;
   if(fa != LgOn)
      LgClear();
   LgOn = fa;                                   // 2.80: Persian text
   UiMirror = fa;                               // and the panel right to left
   ApplyFont();                                 // 2.90
   ApplyTheme();
  }

// Persian labels (test): tabs and section titles only; MT5 may draw Persian letters unjoined on the canvas
string L_(const string s) { return g_lang == 1 ? LangTrPlain(s) : s; }

// a switch row: label on the left, switch on the right (click = BTN_<id>)
int ToggleRow(const string id, const int L, const int R, const int y, const string label, const bool on, const string tip,
              const color acc = C'59,130,246')
  {
   int rh = Z(26);
   TextV(L, y + rh / 2, FitText(label, "Segoe UI", 9, R - L - Z(44)), on ? C_TXT : C_DIM, 9);
   Toggle(PB + "BTN_" + id, R - Z(34), y + Z(4), on, acc == C'59,130,246' ? C_ON : acc, tip);
   return y + Z(28);
  }

bool EdText(const string key, string &t)
  {
   string n = PB + "ED_" + key;
   if(ObjectFind(0, n) < 0)
      return false;
   t = ObjectGetString(0, n, OBJPROP_TEXT);
   StringTrimLeft(t);
   StringTrimRight(t);
   return true;
  }

// ---------------- header: status pills and tabs; minimised: one compact row
int SPill(const int x, const int y, const int r, const string t, const color c)
  {
   int w = TextW(t, "Segoe UI Semibold", 7) + Z(14);
   if(x + w > r)
      return x;                                         // no room left in the row
   Pill(x, y, t, c, C_HEAD);
   return x + w + Z(5);
  }

void Compact(const int x, const int y)
  {
   int W = Z(g_pw);
   int L = x + Z(14), R = x + W - Z(14);
   int bw = Z(64), bh = Z(28), by = y + Z(4);
   bool v2stop = g_v2on && v_v2_why != "";
   bool nw = g_news_on && v_news_lock;
   if(g_confirm)                                       // 2.90: step 1 shown in the bar; Confirm opens the Windows dialog
     {
      int secs = MathMax(0, InpConfirmSeconds - (int)((GetTickCount() - g_confirm_at) / 1000));
      string cs = (g_buy ? "BUY " : "SELL ") + Lot(v_lots) + " lot  ·  " + Fmt(v_total, 2) + "  ·  " + IntegerToString(secs) + " s";
      TextV(L, by + bh / 2, FitText(cs, "Segoe UI Semibold", 9, R - L - 2 * bw - Z(16)), C_AMBER, 9, "Segoe UI Semibold");
      Btn(PH + "BTN_CONFIRM", R - 2 * bw - Z(6), by, bw, bh, "Confirm", true, g_buy ? C_BUYON : C_SELON, 9,
          "Step 2 of 2 opens a Windows dialog (default answer: No)");
      Btn(PH + "BTN_CANCEL", R - bw, by, bw, bh, "Cancel", false, C_ON, 9, "Nothing is sent");
      return;
     }
   bool fresh = g_order_msg != "" && GetTickCount() - g_msg_at < 8000;
   string s = fresh ? g_order_msg : (nw ? "news lock" : (v2stop ? "v2: " + v_v2_short : Summary()));
   color sc = fresh ? (g_order_ok ? C_GREEN : C_AMBER) : ((nw || v2stop) ? C_RED : ((v_ready && v_s1.ok) ? C_GREEN : C_DIM));
   if(g_qp)                                            // quick place: one Order button, the side follows the stop
     {
      int ow = Z(118);
      TextV(L, by + bh / 2, FitText(s, "Segoe UI Semibold", 9, R - L - ow - Z(10)), sc, 9, "Segoe UI Semibold");
      Btn(PH + "BTN_ORDER", R - ow, by, ow, bh, "Order  " + (g_buy ? "BUY" : "SELL"), v_ready && v_s1.ok, g_buy ? C_BUYON : C_SELON, 9,
          "Step 1 of 2: shows the order to confirm");
      return;
     }
   TextV(L, by + bh / 2, FitText(s, "Segoe UI Semibold", 9, R - L - 2 * bw - Z(16)), sc, 9, "Segoe UI Semibold");
   Btn(PH + "BTN_CBUY", R - 2 * bw - Z(6), by, bw, bh, "BUY", g_buy, C_BUYON, 9, "Buy: opens the panel with the order to confirm (step 1 of 2)");
   Btn(PH + "BTN_CSELL", R - bw, by, bw, bh, "SELL", !g_buy, C_SELON, 9, "Sell: opens the panel with the order to confirm (step 1 of 2)");
  }

// ---------------- the tabs
int TabPositions(const int L, const int R, int cy)
  {
   cy = DrawPositions(L, R, cy);
   cy = DrawPending(L, R, cy);
   cy = DrawTrail(L, R, cy);
   cy = DrawPartial(L, R, cy);
   cy = DrawToday(L, R, cy);
   return cy;
  }

int TabRules(const int L, const int R, int cy)
  {
   cy = ToggleRow("V2ON", L, R, cy, g_v2on ? "v2 rules ON: they lock the order button" : "v2 rules OFF", g_v2on,
                  g_v2on ? "Click to switch the v2 rules off" :
                  "Click to switch the v2 rules on: idea and open-risk caps, trading window, day stop, pause, trades a day, TP, stop", C_GREEN);
   cy += Z(4);
   cy = DrawV2(L, R, cy);
   cy = DrawNews(L, R, cy);
   cy = DrawChecklistEdit(L, R, cy);
   cy = DrawSessions(L, R, cy);
   cy = DrawMarkets(L, R, cy);
   return cy;
  }

int TabSettings(const int L, const int R, int cy)
  {
   cy = DrawPresets(L, R, cy);
   cy = DrawLook(L, R, cy);
   cy = DrawDisplay(L, R, cy);
   cy = DrawQpSet(L, R, cy);
   cy = DrawTrailSet(L, R, cy);
   cy = DrawPhone(L, R, cy);
   return cy;
  }

// ---------------- presets: up to 4 sets of settings, kept in MQL5\Files\SlotRiskManager_presets.txt (every chart)
#define RM_PRESETS "SlotRiskManager_presets.txt"
#define RM_PS_N 4
#define RM_PS_F 14
string g_ps_name[RM_PS_N];
bool   g_ps_has[RM_PS_N];
double g_ps_v[RM_PS_N][RM_PS_F];   // mode, %, fixed, capital, day max, entries, share 1, share 2, buffer, TP, trailing, scope, v2, partial
string g_ps_msg = "";

void PresetsLoad()
  {
   for(int k = 0; k < RM_PS_N; k++)
     {
      g_ps_has[k] = false;
      g_ps_name[k] = "Preset " + IntegerToString(k + 1);
     }
   int h = FileOpen(RM_PRESETS, FILE_READ | FILE_TXT | FILE_UNICODE);
   if(h == INVALID_HANDLE)
      return;
   while(!FileIsEnding(h))
     {
      string ln = FileReadString(h);
      string p[];
      int n = StringSplit(ln, '|', p);
      if(n < 2 + RM_PS_F)
         continue;
      int k = (int)StringToInteger(p[0]);
      if(k < 0 || k >= RM_PS_N)
         continue;
      g_ps_name[k] = p[1];
      g_ps_has[k] = true;
      for(int f = 0; f < RM_PS_F; f++)
         g_ps_v[k][f] = StringToDouble(p[2 + f]);
     }
   FileClose(h);
  }

void PresetsSave()
  {
   int h = FileOpen(RM_PRESETS, FILE_WRITE | FILE_TXT | FILE_UNICODE);
   if(h == INVALID_HANDLE)
     {
      g_ps_msg = "Presets file not written (error " + IntegerToString(GetLastError()) + ")";
      return;
     }
   for(int k = 0; k < RM_PS_N; k++)
     {
      if(!g_ps_has[k])
         continue;
      string nm = g_ps_name[k];
      StringReplace(nm, "|", "/");
      string ln = IntegerToString(k) + "|" + nm;
      for(int f = 0; f < RM_PS_F; f++)
         ln += "|" + DoubleToString(g_ps_v[k][f], 4);
      FileWriteString(h, ln + "\r\n");
     }
   FileClose(h);
  }

string PresetText(const int k)
  {
   if(!g_ps_has[k])
      return "Empty: press Save to keep the current settings here";
   int mode = (int)g_ps_v[k][0], parts = (int)g_ps_v[k][5], tp = (int)g_ps_v[k][9];
   string r = mode == 2 ? "fixed " + Fmt(g_ps_v[k][2], 2) : Fmt(g_ps_v[k][1], 2) + "% of " + (mode == 1 ? "equity" : Fmt(g_ps_v[k][3], 0));
   string e = parts == 1 ? "1 entry" : IntegerToString(parts) + " entries";
   string t = tp == 0 ? "no TP" : (tp == 4 ? "TP line" : "TP " + IntegerToString(tp) + "R");
   return r + " · " + e + " · " + t + " · day max " + Fmt(g_ps_v[k][4], 0) + (g_ps_v[k][10] != 0 ? " · trailing" : "") +
          (g_ps_v[k][13] != 0 ? " · partial" : "") + (g_ps_v[k][12] != 0 ? " · v2" : "");
  }

void PresetStore(const int k)
  {
   if(k < 0 || k >= RM_PS_N)
      return;
   string t = "";
   if(EdText("PSN" + IntegerToString(k), t) && t != "")
      g_ps_name[k] = t;
   g_ps_v[k][0] = g_mode; g_ps_v[k][1] = g_percent; g_ps_v[k][2] = g_fixed; g_ps_v[k][3] = g_ref; g_ps_v[k][4] = g_daily;
   g_ps_v[k][5] = g_parts; g_ps_v[k][6] = g_share1; g_ps_v[k][7] = g_share2; g_ps_v[k][8] = g_buffer; g_ps_v[k][9] = g_tp_r;
   g_ps_v[k][10] = g_trail_on; g_ps_v[k][11] = g_trail_scope; g_ps_v[k][12] = g_v2on; g_ps_v[k][13] = g_pc_on;
   g_ps_has[k] = true;
   PresetsSave();
   g_ps_msg = "Saved \"" + g_ps_name[k] + "\": " + PresetText(k);
  }

void PresetApply(const int k)
  {
   if(k < 0 || k >= RM_PS_N || !g_ps_has[k])
     {
      g_ps_msg = "This preset is empty: Save first";
      return;
     }
   g_mode = (int)g_ps_v[k][0]; g_percent = g_ps_v[k][1]; g_fixed = g_ps_v[k][2]; g_ref = g_ps_v[k][3]; g_daily = g_ps_v[k][4];
   g_parts = (int)g_ps_v[k][5]; g_share1 = g_ps_v[k][6]; g_share2 = g_ps_v[k][7]; g_buffer = g_ps_v[k][8];
   g_tp_r = (int)g_ps_v[k][9];
   if(g_mode < 0 || g_mode > 2) g_mode = 0;
   if(g_parts < 1 || g_parts > 3) g_parts = 1;
   if(g_tp_r < 0 || g_tp_r > 4) g_tp_r = 0;
   g_trail_scope = g_ps_v[k][11] != 0 ? 1 : 0;
   GlobalVariableSet("RM_TRAIL_SCOPE", g_trail_scope);
   g_v2on = g_ps_v[k][12] != 0;
   SetEd("PCT", DoubleToString(g_percent, 2)); SetEd("FIX", DoubleToString(g_fixed, 2)); SetEd("REF", DoubleToString(g_ref, 0));
   SetEd("DAY", DoubleToString(g_daily, 0)); SetEd("BUF", DoubleToString(g_buffer, 1)); SetEd("SH", DoubleToString(g_share1, 0));
   SetEd("SH2", DoubleToString(g_share2, 0));
   bool want_tr = g_ps_v[k][10] != 0, want_pc = g_ps_v[k][13] != 0;
   if(InpTrailAllowed && want_tr != g_trail_on)
      TrailSwitch();                                    // switching on asks first (Windows dialog)
   if(InpManageAllowed && want_pc != g_pc_on)
      PartialSwitch();                                  // switching on asks first (Windows dialog)
   g_ps_msg = "Loaded \"" + g_ps_name[k] + "\": " + PresetText(k);
  }

int DrawPresets(const int L, const int R, int cy)
  {
   Section(PB + "s_ps", L, R, cy, "PRESETS", "", false, "", C_DIM);
   cy += Z(24);
   int rh = Z(26), bw = Z(52);
   for(int k = 0; k < RM_PS_N; k++)
     {
      string ks = IntegerToString(k);
      Ed(PB + "ED_PSN" + ks, L, cy, R - L - 2 * bw - Z(12), rh, g_ps_name[k], "Name of preset " + IntegerToString(k + 1) + ": " + PresetText(k),
         IntegerToString(k + 1), true);
      Btn(PB + "BTN_PSL" + ks, R - 2 * bw - Z(6), cy, bw, rh, "Load", g_ps_has[k], C_ON, 8, PresetText(k));
      Btn(PB + "BTN_PSS" + ks, R - bw, cy, bw, rh, "Save", false, C_ON, 8,
          "Keep the current settings here: risk, day max, entries, buffer, TP, trailing, partial close, v2");
      cy += Z(30);
     }
   if(g_ps_msg != "")
     {
      string ln[];
      int n = Wrap(g_ps_msg, "Segoe UI", 8, R - L, 2, ln);
      for(int i = 0; i < n; i++)
        {
         Text(PB + "ps_m" + IntegerToString(i), L, cy, ln[i], C_GREEN, 8);
         cy += Z(15);
        }
     }
   return cy + Z(8);
  }

// ---------------- display: size, width, language, hotkeys, risk box
int DrawDisplay(const int L, const int R, int cy)
  {
   Section(PB + "s_dp", L, R, cy, "DISPLAY", "", false, "", C_DIM);
   cy += Z(24);
   int rh = Z(26), lx = L + Z(70);
   TextV(L, cy + rh / 2, "Size", C_DIM, 9);
   string zl[4] = {"90%", "100%", "115%", "130%"};
   int zv[4] = {0, 1, 2, 3};
   string zt[4] = {"Smaller text and panel", "Normal size", "Larger text and panel", "Largest text and panel"};
   Seg(PB + "BTN_ZM", lx, cy, R - lx, rh, zl, zv, 4, g_zoom_i, zt);
   cy += Z(32);
   TextV(L, cy + rh / 2, "Width", C_DIM, 9);
   string wl[3] = {"Narrow", "Normal", "Wide"};
   int wv[3] = {0, 1, 2};
   string wt[3] = {"Panel 300 px", "Panel 332 px", "Panel 380 px"};
   Seg(PB + "BTN_WD", lx, cy, R - lx, rh, wl, wv, 3, g_width_i, wt);
   cy += Z(32);
   TextV(L, cy + rh / 2, "Language", C_DIM, 9);
   string ll[2] = {"English", "فارسی"};
   int lv[2] = {0, 1};
   string lt[2] = {"English labels", "Persian, right to left"};
   Seg(PB + "BTN_LG", lx, cy, R - lx, rh, ll, lv, 2, g_lang, lt);
   cy += Z(34);
   cy = ToggleRow("HOT", L, R, cy, "Hotkeys: B · S · Enter · Esc · T", g_hot,
                  "On the chart: B buy side, S sell side, Enter shows the order to confirm (step 1), Esc cancels it, T trailing on / off");
   cy = ToggleRow("BOX", L, R, cy, "Risk box on the chart", g_box, "Red to the stop, green to the take-profit, with R and money");
   return cy + Z(8);
  }

// ---------------- trailing and partial-close settings
string TfName() { return g_tr_tf == 0 ? "M5" : (g_tr_tf == 2 ? "H1" : "M15"); }
ENUM_TIMEFRAMES TrailTf() { return g_tr_tf == 0 ? PERIOD_M5 : (g_tr_tf == 2 ? PERIOD_H1 : PERIOD_M15); }

int DrawTrailSet(const int L, const int R, int cy)
  {
   Section(PB + "s_ts", L, R, cy, "TRAILING SETTINGS", "", false, "", C_DIM);
   cy += Z(24);
   int rh = Z(26), lx = L + Z(70);
   TextV(L, cy + rh / 2, "Mode", C_DIM, 9);
   string ml[3] = {"R steps", "ATR", "Swing"};
   int mv[3] = {0, 1, 2};
   string mt[3] = {"Every step: stop and TP move 1 step on", "From the first step: stop at least at the entry, then price - k x ATR",
                   "From the first step: stop at least at the entry, then beyond the last swing low / high"};
   Seg(PB + "BTN_TRM", lx, cy, R - lx, rh, ml, mv, 3, g_tr_mode, mt);
   cy += Z(32);
   int w4 = (R - L - Z(24)) / 4;
   Ed(PB + "ED_TRST", L, cy, w4, rh, XText(g_tr_start), "First step: the price this many R in profit", "start");
   Ed(PB + "ED_TRSP", L + w4 + Z(8), cy, w4, rh, XText(g_tr_step), "Next steps every this many R", "step");
   Ed(PB + "ED_TRLG", L + 2 * (w4 + Z(8)), cy, w4, rh, XText(g_tr_lag),
      "R steps: stop this many R behind the step reached (2: at 2R the stop goes to the entry)", "lag");
   Ed(PB + "ED_TRLD", L + 3 * (w4 + Z(8)), cy, R - (L + 3 * (w4 + Z(8))), rh, XText(g_tr_lead),
      "Take-profit this many R ahead of the step reached (0 = the take-profit is not moved)", "TP+");
   cy += Z(32);
   if(g_tr_mode > 0)
     {
      int w3 = (R - L - Z(16)) / 3, x2 = L + w3 + Z(8), x3 = L + 2 * (w3 + Z(8));
      if(g_tr_mode == 1)
        {
         Ed(PB + "ED_ATRK", L, cy, w3, rh, XText(g_tr_atr_k), "Stop this many ATR behind the price", "ATR x");
         Ed(PB + "ED_ATRN", x2, cy, w3, rh, IntegerToString(g_tr_atr_n), "ATR period (bars)", "period");
        }
      else
         Ed(PB + "ED_SWB", L, cy, w3 * 2 + Z(8), rh, IntegerToString(g_tr_swing), "Swing: the lowest low (buy) / highest high (sell) of this many closed bars", "bars");
      string fl[3] = {"M5", "M15", "H1"};
      int fv[3] = {0, 1, 2};
      string ft[3] = {"Timeframe M5", "Timeframe M15", "Timeframe H1"};
      Seg(PB + "BTN_TRF", x3, cy, R - x3, rh, fl, fv, 3, g_tr_tf, ft);
      cy += Z(32);
     }
   cy = ToggleRow("TRCC", L, R, cy, "Risk-free stop also covers the commission", g_tr_cost,
                  "A stop at or beyond the entry is moved on by the commission of the position, so a stop-out there is not a loss");
   Text(PB + "ts_r", L, cy, FitText(TrailRule(), "Segoe UI", 8, R - L), C_FAINT, 8);
   cy += Z(22);
   Section(PB + "s_pcs", L, R, cy, "PARTIAL CLOSE", "", false, "", C_DIM);
   cy += Z(24);
   int w2 = (R - L - Z(8)) / 2;
   Ed(PB + "ED_PCR", L, cy, w2, rh, XText(g_pc_r), "Close part of a position when it reaches this many R", "at R");
   Ed(PB + "ED_PCP", L + w2 + Z(8), cy, R - L - w2 - Z(8), rh, XText(g_pc_pct), "Share of the position closed, % (1-99; once per position)", "close %");
   cy += Z(32);
   return cy + Z(4);
  }

// ---------------- phone notifications settings
int DrawPhone(const int L, const int R, int cy)
  {
   Section(PB + "s_ph", L, R, cy, "PHONE", "", false, "", C_DIM);
   cy += Z(24);
   cy = ToggleRow("PUSH", L, R, cy, "Notifications to the MetaTrader app", g_push, "Messages to the MetaTrader app on your phone", C_GREEN);
   if(g_push)
     {
      cy = ToggleRow("PSHT", L, R, cy, "· trailing moves a stop, partial close", g_push_tr, "", C_GREEN);
      cy = ToggleRow("PSHC", L, R, cy, "· a position closes (stop, TP, hand)", g_push_cl, "", C_GREEN);
      cy = ToggleRow("PSHD", L, R, cy, "· the daily loss limit is used up", g_push_day, "", C_GREEN);
      cy = ToggleRow("PSHS", L, R, cy, "· a session of your window opens (v2)", g_push_ses, "", C_GREEN);
     }
   bool ph = TerminalInfoInteger(TERMINAL_NOTIFICATIONS_ENABLED) != 0;
   int bw = Z(86);
   Text(PB + "ph_s", L, cy + Z(5), FitText(ph ? "MetaQuotes ID set: messages go to your phone" : "Set your MetaQuotes ID: Tools > Options > Notifications",
        "Segoe UI", 8, R - L - bw - Z(8)), ph ? C_FAINT : C_AMBER, 8);
   Btn(PB + "BTN_PTEST", R - bw, cy, bw, Z(24), "Send a test", false, C_ON, 8, "Sends one test message to your phone");
   cy += Z(30);
   return cy + Z(4);
  }

// ---------------- hotkeys (on the chart, not while typing in a field)
bool OnEditField(const int mx, const int my)
  {
   for(int i = ObjectsTotal(0, 0, OBJ_EDIT) - 1; i >= 0; i--)
     {
      string n = ObjectName(0, i, 0, OBJ_EDIT);
      if(StringFind(n, PB + "ED_") != 0)
         continue;
      int x = (int)ObjectGetInteger(0, n, OBJPROP_XDISTANCE), y = (int)ObjectGetInteger(0, n, OBJPROP_YDISTANCE);
      int w = (int)ObjectGetInteger(0, n, OBJPROP_XSIZE), h = (int)ObjectGetInteger(0, n, OBJPROP_YSIZE);
      if(mx >= x && mx < x + w && my >= y && my < y + h)
         return true;
     }
   return false;
  }

void HotKey(const int k)
  {
   if(!g_hot || g_editing)
      return;
   if(k == 'B' || k == 'S')
     {
      bool b = k == 'B';
      if(g_buy != b && g_confirm)
        {
         g_confirm = false;
         g_order_ok = false;
         g_order_msg = "Confirmation cancelled (side changed)";
        }
      g_buy = b;
      Refresh();
     }
   else if(k == 13)                                     // Enter: step 1 only; step 2 is a click on Confirm and the Windows dialog
     {
      if(g_confirm)
         return;
      g_min = false;
      g_tab = 0;
      g_scroll = 0;
      StartConfirm();
      Draw();
     }
   else if(k == 27)                                     // Esc
     {
      if(g_confirm)
        {
         g_confirm = false;
         g_order_ok = false;
         g_order_msg = "Cancelled: nothing sent";
         Draw();
        }
     }
   else if(k == 'T')
     {
      TrailSwitch();                                    // switching on asks first (Windows dialog)
      Refresh();
     }
   else if(k == 'Q')                                    // 2.90 quick place on / off
     {
      QpToggle();
      Refresh();
     }
  }

// ---------------- news lock: the MT5 economic calendar (server time), USD and this symbol's currencies
string   g_nw_curs[];
datetime g_nw_t[];
string   g_nw_name[], g_nw_cur[];
uint     g_news_at = 0;

void NewsAddCur(const string c)
  {
   if(StringLen(c) != 3)
      return;
   for(int i = 0; i < ArraySize(g_nw_curs); i++)
      if(g_nw_curs[i] == c)
         return;
   int n = ArraySize(g_nw_curs);
   ArrayResize(g_nw_curs, n + 1);
   g_nw_curs[n] = c;
  }

string NewsCurrencies()
  {
   string s = "";
   for(int i = 0; i < ArraySize(g_nw_curs); i++)
      s += (i > 0 ? ", " : "") + g_nw_curs[i];
   return s;
  }

// events of the next 2 days (and the last 6 hours), read every 5 minutes
void NewsLoad()
  {
   if(g_news_at != 0 && GetTickCount() - g_news_at < 300000)
      return;
   g_news_at = GetTickCount();
   ArrayResize(g_nw_t, 0);
   ArrayResize(g_nw_name, 0);
   ArrayResize(g_nw_cur, 0);
   ArrayResize(g_nw_curs, 0);
   NewsAddCur("USD");
   NewsAddCur(SymbolInfoString(_Symbol, SYMBOL_CURRENCY_BASE));
   NewsAddCur(SymbolInfoString(_Symbol, SYMBOL_CURRENCY_PROFIT));
   v_news_err = "";
   datetime now = TimeTradeServer();
   for(int c = 0; c < ArraySize(g_nw_curs); c++)
     {
      MqlCalendarValue vals[];
      ResetLastError();
      int n = CalendarValueHistory(vals, now - 6 * 3600, now + 2 * 86400, NULL, g_nw_curs[c]);
      if(n < 0)
        {
         v_news_err = "economic calendar not available (error " + IntegerToString(GetLastError()) + ")";
         continue;
        }
      for(int i = 0; i < n; i++)
        {
         MqlCalendarEvent ev;
         if(!CalendarEventById(vals[i].event_id, ev))
            continue;
         bool imp = ev.importance == CALENDAR_IMPORTANCE_HIGH || (g_news_imp == 1 && ev.importance == CALENDAR_IMPORTANCE_MODERATE);
         if(!imp)
            continue;
         int k = ArraySize(g_nw_t);
         ArrayResize(g_nw_t, k + 1);
         ArrayResize(g_nw_name, k + 1);
         ArrayResize(g_nw_cur, k + 1);
         g_nw_t[k] = vals[i].time;
         g_nw_name[k] = ev.name;
         g_nw_cur[k] = g_nw_curs[c];
        }
     }
  }

// the event that locks now (inside its window), else the next one
void NewsCheck()
  {
   NewsLoad();
   v_news_lock = false;
   v_news_t = 0;
   v_news_name = "";
   v_news_cur = "";
   v_news_min = 0;
   datetime now = TimeTradeServer();
   int bi = -1;
   for(int i = 0; i < ArraySize(g_nw_t); i++)
      if(now >= g_nw_t[i] - g_news_before * 60 && now <= g_nw_t[i] + g_news_after * 60)
        {
         bi = i;
         v_news_lock = true;
         break;
        }
   if(bi < 0)
      for(int i = 0; i < ArraySize(g_nw_t); i++)
         if(g_nw_t[i] > now && (bi < 0 || g_nw_t[i] < g_nw_t[bi]))
            bi = i;
   if(bi < 0)
      return;
   v_news_t = g_nw_t[bi];
   v_news_name = g_nw_name[bi];
   v_news_cur = g_nw_cur[bi];
   v_news_min = (int)(((long)v_news_t - (long)now) / 60);
  }

int DrawNews(const int L, const int R, int cy)
  {
   Section(PB + "s_nw", L, R, cy, "NEWS", "", false, "", C_DIM);
   cy += Z(24);
   cy = ToggleRow("NWON", L, R, cy, g_news_on ? StringFormat("News lock ON: %d min before, %d after", g_news_before, g_news_after) : "News lock OFF",
                  g_news_on, g_news_on ? "Click to stop locking the order button around the news" :
                  "Click to lock the order button around important news (MT5 economic calendar)", C_AMBER);
   int rh = Z(26), w3 = (R - L - Z(16)) / 3, x2 = L + w3 + Z(8), x3 = L + 2 * (w3 + Z(8));
   Ed(PB + "ED_NWB", L, cy, w3, rh, IntegerToString(g_news_before), "Minutes before the news: the order button is locked", "before");
   Ed(PB + "ED_NWA", x2, cy, w3, rh, IntegerToString(g_news_after), "Minutes after the news: the order button is locked", "after");
   string il[2] = {"High", "Med+"};
   int iv[2] = {0, 1};
   string it[2] = {"Only high-impact news", "Medium and high-impact news"};
   Seg(PB + "BTN_NWI", x3, cy, R - x3, rh, il, iv, 2, g_news_imp, it);
   cy += Z(32);
   string nx = v_news_t > 0 ? v_news_cur + " " + v_news_name + "  ·  " + TimeToString(v_news_t, TIME_DATE | TIME_MINUTES) +
               (v_news_min >= 0 ? "  (in " + Mins(v_news_min) + ")" : "  (" + Mins(-v_news_min) + " ago)")
               : (v_news_err != "" ? v_news_err : "no important news in the next 2 days");
   bool lk = g_news_on && v_news_lock;
   color c = lk ? C_RED : ((v_news_t > 0 && v_news_min >= 0 && v_news_min <= 60) ? C_AMBER : C_DIM);
   string ln[];
   int n = Wrap((lk ? "Locked: " : (v_news_lock ? "Now: " : "Next: ")) + nx, "Segoe UI", 8, R - L, 2, ln);
   for(int i = 0; i < n; i++)
     {
      Text(PB + "nw_t" + IntegerToString(i), L, cy, ln[i], c, 8);
      cy += Z(15);
     }
   Text(PB + "nw_c", L, cy, FitText("Currencies " + NewsCurrencies() + "  ·  times are server time", "Segoe UI", 8, R - L), C_FAINT, 8);
   return cy + Z(24);
  }

// ---------------- checklist: up to 5 items of your own (MQL5\Files\SlotRiskManager_checklist.txt); with the checklist on,
// the order button opens only when every item is ticked; the ticks are cleared after each order
#define RM_CHECKLIST "SlotRiskManager_checklist.txt"
string g_ck_txt[5];
bool   g_ck[5];
bool   g_ck_dirty = false;

void ChecklistLoad()
  {
   g_ck_txt[0] = "My setup, from my plan";
   g_ck_txt[1] = "Stop beyond a real level";
   g_ck_txt[2] = "Entry at my level, not chasing";
   g_ck_txt[3] = "No important news soon";
   g_ck_txt[4] = "Calm: not a revenge trade";
   for(int i = 0; i < 5; i++)
      g_ck[i] = false;
   int h = FileOpen(RM_CHECKLIST, FILE_READ | FILE_TXT | FILE_UNICODE);
   if(h == INVALID_HANDLE)
      return;
   for(int i = 0; i < 5; i++)
      g_ck_txt[i] = FileIsEnding(h) ? "" : FileReadString(h);
   FileClose(h);
  }

void ChecklistSave()
  {
   g_ck_dirty = false;
   int h = FileOpen(RM_CHECKLIST, FILE_WRITE | FILE_TXT | FILE_UNICODE);
   if(h == INVALID_HANDLE)
      return;
   for(int i = 0; i < 5; i++)
      FileWriteString(h, g_ck_txt[i] + "\r\n");
   FileClose(h);
  }

bool ChecklistOk()
  {
   if(!g_chk_on)
      return true;
   for(int i = 0; i < 5; i++)
      if(g_ck_txt[i] != "" && !g_ck[i])
         return false;
   return true;
  }

int DrawChecklist(const int L, const int R, int cy)
  {
   if(!g_chk_on)
      return cy;
   int n = 0;
   for(int i = 0; i < 5; i++)
      if(g_ck_txt[i] != "")
         n++;
   if(n == 0)
      return cy;
   Section(PB + "s_ckt", L, R, cy, "CHECKLIST", "", false, "", C_DIM);
   cy += Z(22);
   int rh = Z(24);
   for(int i = 0; i < 5; i++)
     {
      if(g_ck_txt[i] == "")
         continue;
      string id = PB + "BTN_CHK" + IntegerToString(i);
      if(!g_dry)
        {
         bool hov = g_hover == id;
         int bx = L + Z(2), by = cy + rh / 2 - Z(7);
         if(g_ck[i])
           {
            UiRound(bx, by, Z(14), Z(14), Z(3), C_GREEN);
            UiCheck(bx + Z(7), by + Z(7), Z(4), clrWhite);
           }
         else
            UiCard(bx, by, Z(14), Z(14), Z(3), hov ? C_HOVER : C_CARD, C_FAINT);
         UiText(L + Z(24), cy + rh / 2, FitText(g_ck_txt[i], "Segoe UI", 9, R - L - Z(26)), g_ck[i] ? C_TXT : C_DIM, 9, "Segoe UI",
                TA_LEFT | TA_VCENTER);
         UiZone(id, L, cy, R - L, rh, g_ck[i] ? "Ticked: click to untick" : "Click to tick");
        }
      cy += Z(26);
     }
   return cy + Z(4);
  }

int DrawChecklistEdit(const int L, const int R, int cy)
  {
   Section(PB + "s_ck", L, R, cy, "CHECKLIST", "", false, "", C_DIM);
   cy += Z(24);
   cy = ToggleRow("CKON", L, R, cy, g_chk_on ? "Checklist ON: tick every item before an order" : "Checklist OFF", g_chk_on,
                  g_chk_on ? "Click to switch the checklist off" : "Click to show the checklist above the order button (Trade tab)", C_GREEN);
   if(!g_chk_on)
      return cy + Z(6);
   for(int i = 0; i < 5; i++)
     {
      Ed(PB + "ED_CKT" + IntegerToString(i), L, cy, R - L, Z(26), g_ck_txt[i], "Checklist item " + IntegerToString(i + 1) + " (empty = not used)",
         IntegerToString(i + 1), true);
      cy += Z(30);
     }
   return cy + Z(6);
  }

// ---------------- today's card and the journal file (MQL5\Files\SlotRiskManager_journal.csv: one row per closed position)
#define RM_JOURNAL "SlotRiskManager_journal.csv"
struct RmClosed
  {
   ulong  pid, ord;
   string sym, cmt;
   bool   buy;
   double vin, pin, vout, pout, net;
   long   tin, tout, reason, magic;
   int    exits;
  };
string g_jr_ids[];
bool   g_jr_loaded = false;
bool   g_sc_dirty = true;
uint   g_sc_at = 0;

void JournalLoad()
  {
   g_jr_loaded = true;
   ArrayResize(g_jr_ids, 0);
   if(!FileIsExist(RM_JOURNAL))
      return;
   int h = FileOpen(RM_JOURNAL, FILE_READ | FILE_CSV | FILE_ANSI, ',');
   if(h == INVALID_HANDLE)
      return;
   while(!FileIsEnding(h))
     {
      string id = FileReadString(h);
      while(!FileIsLineEnding(h) && !FileIsEnding(h))
         FileReadString(h);
      if(id == "" || id == "position_id")
         continue;
      int n = ArraySize(g_jr_ids);
      ArrayResize(g_jr_ids, n + 1, 256);
      g_jr_ids[n] = id;
     }
   FileClose(h);
  }

bool JournalHas(const string id)
  {
   for(int i = ArraySize(g_jr_ids) - 1; i >= 0; i--)
      if(g_jr_ids[i] == id)
         return true;
   return false;
  }

string ReasonText(const long r)
  {
   if(r == DEAL_REASON_SL) return "SL";
   if(r == DEAL_REASON_TP) return "TP";
   if(r == DEAL_REASON_SO) return "StopOut";
   if(r == DEAL_REASON_EXPERT) return "EA";
   return "Hand";
  }

void JournalAdd(const RmClosed &c, const double op, const double cp, const double sl0, const double rm)
  {
   bool fresh = !FileIsExist(RM_JOURNAL);
   int h = FileOpen(RM_JOURNAL, FILE_READ | FILE_WRITE | FILE_CSV | FILE_ANSI, ',');
   if(h == INVALID_HANDLE)
      return;
   FileSeek(h, 0, SEEK_END);
   if(fresh || FileTell(h) == 0)
      FileWrite(h, "position_id", "symbol", "side", "volume", "open_time", "open_price", "first_sl", "close_time", "close_price",
                "exits", "close_reason", "net", "r_multiple", "magic", "comment");
   int dg = (int)SymbolInfoInteger(c.sym, SYMBOL_DIGITS);
   if(dg <= 0)
      dg = 5;
   string cm = c.cmt;
   StringReplace(cm, ",", " ");
   string id = IntegerToString((long)c.pid);
   FileWrite(h, id, c.sym, c.buy ? "Buy" : "Sell", DoubleToString(c.vin, 2), TimeToString((datetime)c.tin, TIME_DATE | TIME_SECONDS),
             DoubleToString(op, dg), sl0 > 0 ? DoubleToString(sl0, dg) : "", TimeToString((datetime)c.tout, TIME_DATE | TIME_SECONDS),
             DoubleToString(cp, dg), IntegerToString(c.exits), ReasonText(c.reason), DoubleToString(c.net, 2),
             sl0 > 0 ? DoubleToString(rm, 2) : "", IntegerToString(c.magic), cm);
   FileClose(h);
   int n = ArraySize(g_jr_ids);
   ArrayResize(g_jr_ids, n + 1, 256);
   g_jr_ids[n] = id;
  }

// closed positions of the last 14 days: today's card, and new rows for the journal file (one chart writes it)
void ScoreRun()
  {
   if(!g_sc_dirty && GetTickCount() - g_sc_at < 15000)
      return;
   g_sc_dirty = false;
   g_sc_at = GetTickCount();
   datetime now = TimeTradeServer();
   datetime day0 = now - now % 86400;
   if(!HistorySelect(day0 - 14 * 86400, now + 60))
      return;
   RmClosed cs[];
   int nc = 0;
   for(int i = 0; i < HistoryDealsTotal(); i++)
     {
      ulong d = HistoryDealGetTicket(i);
      if(d == 0)
         continue;
      long typ = HistoryDealGetInteger(d, DEAL_TYPE);
      if(typ != DEAL_TYPE_BUY && typ != DEAL_TYPE_SELL)
         continue;
      ulong pid = (ulong)HistoryDealGetInteger(d, DEAL_POSITION_ID);
      int k = -1;
      for(int j = nc - 1; j >= 0; j--)
         if(cs[j].pid == pid) { k = j; break; }
      if(k < 0)
        {
         k = nc++;
         ArrayResize(cs, nc, 64);
         cs[k].pid = pid; cs[k].ord = 0; cs[k].sym = HistoryDealGetString(d, DEAL_SYMBOL); cs[k].cmt = ""; cs[k].buy = true;
         cs[k].vin = 0; cs[k].pin = 0; cs[k].vout = 0; cs[k].pout = 0; cs[k].net = 0; cs[k].tin = 0; cs[k].tout = 0;
         cs[k].reason = -1; cs[k].magic = 0; cs[k].exits = 0;
        }
      double vol = HistoryDealGetDouble(d, DEAL_VOLUME), px = HistoryDealGetDouble(d, DEAL_PRICE);
      long tm = HistoryDealGetInteger(d, DEAL_TIME);
      cs[k].net += HistoryDealGetDouble(d, DEAL_PROFIT) + HistoryDealGetDouble(d, DEAL_COMMISSION) + HistoryDealGetDouble(d, DEAL_SWAP) +
                   HistoryDealGetDouble(d, DEAL_FEE);
      if(HistoryDealGetInteger(d, DEAL_ENTRY) == DEAL_ENTRY_IN)
        {
         if(cs[k].vin == 0)
           {
            cs[k].tin = tm;
            cs[k].buy = typ == DEAL_TYPE_BUY;
            cs[k].ord = (ulong)HistoryDealGetInteger(d, DEAL_ORDER);
            cs[k].magic = HistoryDealGetInteger(d, DEAL_MAGIC);
            cs[k].cmt = HistoryDealGetString(d, DEAL_COMMENT);
           }
         cs[k].vin += vol;
         cs[k].pin += px * vol;
        }
      else
        {
         cs[k].vout += vol;
         cs[k].pout += px * vol;
         cs[k].exits++;
         if(tm >= cs[k].tout)
           {
            cs[k].tout = tm;
            cs[k].reason = HistoryDealGetInteger(d, DEAL_REASON);
           }
        }
     }
   v_sc_n = 0; v_sc_win = 0; v_sc_loss = 0; v_sc_rn = 0; v_sc_net = 0; v_sc_r = 0;
   bool jr = Owner("JOURNAL");
   if(jr && !g_jr_loaded)
      JournalLoad();
   for(int k = 0; k < nc; k++)
     {
      if(cs[k].tout == 0 || cs[k].vin <= 0 || cs[k].vout < cs[k].vin - 1e-9 || PositionSelectByTicket(cs[k].pid))
         continue;                                      // still open (or only partly closed)
      double op = cs[k].pin / cs[k].vin, cp = cs[k].vout > 0 ? cs[k].pout / cs[k].vout : 0;
      double sl0 = cs[k].ord > 0 ? HistoryOrderGetDouble(cs[k].ord, ORDER_SL) : 0;   // the stop of the order that opened it
      if(sl0 <= 0 || (cs[k].buy ? sl0 >= op : sl0 <= op))
        {
         string kr = "RM_TR_R_" + IntegerToString((long)cs[k].pid);
         double r0 = GlobalVariableCheck(kr) ? GlobalVariableGet(kr) : 0;
         sl0 = r0 > 0 ? (cs[k].buy ? op - r0 : op + r0) : 0;
        }
      double r = sl0 > 0 ? MathAbs(op - sl0) : 0;
      double rm = r > 0 && cp > 0 ? (cs[k].buy ? cp - op : op - cp) / r : 0;
      if(cs[k].tout >= (long)day0)
        {
         v_sc_n++;
         if(cs[k].net > 0) v_sc_win++;
         else if(cs[k].net < 0) v_sc_loss++;
         v_sc_net += cs[k].net;
         if(r > 0) { v_sc_r += rm; v_sc_rn++; }
        }
      if(jr && !JournalHas(IntegerToString((long)cs[k].pid)))
         JournalAdd(cs[k], op, cp, sl0, rm);
     }
   v_jr_n = ArraySize(g_jr_ids);
  }

// ---------------- pending orders (POSITIONS tab): each one with a cancel button (asks first)
int DrawPending(const int L, const int R, int cy)
  {
   int n = 0, shown = 0;
   for(int i = OrdersTotal() - 1; i >= 0; i--)
     {
      ulong tk = OrderGetTicket(i);
      if(tk == 0)
         continue;
      long ty = OrderGetInteger(ORDER_TYPE);
      if(ty < ORDER_TYPE_BUY_LIMIT || ty > ORDER_TYPE_SELL_STOP_LIMIT)
         continue;
      if(n == 0)
        {
         Section(PB + "s_pd", L, R, cy, "PENDING ORDERS", "", false, "", C_DIM);
         cy += Z(24);
        }
      n++;
      if(shown >= 6)
         continue;
      string sym = OrderGetString(ORDER_SYMBOL);
      int dg = (int)SymbolInfoInteger(sym, SYMBOL_DIGITS);
      double sl = OrderGetDouble(ORDER_SL);
      string t = sym + "  " + RmTypeName((ENUM_ORDER_TYPE)ty) + "  " + DoubleToString(OrderGetDouble(ORDER_VOLUME_CURRENT), 2) + " @ " +
                 DoubleToString(OrderGetDouble(ORDER_PRICE_OPEN), dg) + (sl > 0 ? "  ·  SL " + DoubleToString(sl, dg) : "  ·  no SL");
      bool can = InpManageAllowed;
      Text(PB + "pd_" + IntegerToString(shown), L, cy + Z(4), FitText(t, "Segoe UI", 8, R - L - (can ? Z(36) : 0)), C_TXT, 8);
      if(can)
         Btn(PB + "BTN_CXL" + IntegerToString((long)tk), R - Z(28), cy, Z(28), Z(22), "×", false, C_RED, 9, "Cancel this pending order (asks first)");
      cy += Z(26);
      shown++;
     }
   if(n == 0)
      return cy;
   if(n > shown)
     {
      Text(PB + "pd_more", L, cy, "+" + IntegerToString(n - shown) + " more", C_FAINT, 8);
      cy += Z(16);
     }
   if(!InpManageAllowed)
     {
      Text(PB + "pd_off", L, cy, FitText("Cancel from here: EA input 'Allow partial close and cancelling'", "Segoe UI", 8, R - L), C_FAINT, 8);
      cy += Z(16);
     }
   if(g_pd_msg != "")
     {
      Text(PB + "pd_m", L, cy, FitText(g_pd_msg, "Segoe UI", 8, R - L), g_pd_ok ? C_GREEN : C_AMBER, 8);
      cy += Z(16);
     }
   return cy + Z(6);
  }

void CancelPending(const ulong tk)
  {
   if(!InpManageAllowed)
      return;
   if(!OrderSelect(tk))
     {
      g_pd_ok = false;
      g_pd_msg = "Order not found (filled or removed already?)";
      return;
     }
   string sym = OrderGetString(ORDER_SYMBOL);
   int dg = (int)SymbolInfoInteger(sym, SYMBOL_DIGITS);
   string txt = StringFormat("Cancel this pending order?\n\n%s  %s  %s lot @ %s\n\nOnly this order is removed. Positions are not touched.", sym,
                             RmTypeName((ENUM_ORDER_TYPE)OrderGetInteger(ORDER_TYPE)), DoubleToString(OrderGetDouble(ORDER_VOLUME_CURRENT), 2),
                             DoubleToString(OrderGetDouble(ORDER_PRICE_OPEN), dg));
   if(g_lang == 1)
     {
      StringReplace(txt, "Cancel this pending order?", "این سفارش در انتظار لغو شود؟");
      StringReplace(txt, "Only this order is removed. Positions are not touched.", "فقط همین سفارش حذف می‌شود. به پوزیشن‌ها دست نمی‌خورد.");
      StringReplace(txt, " lot @ ", " لات @ ");
     }
   if(MessageBox(txt, g_lang == 1 ? "مدیر ریسک اسلات - لغو سفارش" : RM_TITLE + " - cancel order",
                 MB_YESNO | MB_ICONQUESTION | MB_DEFBUTTON2 | RtlFlags()) != IDYES)
     {
      g_pd_ok = false;
      g_pd_msg = "Not cancelled";
      return;
     }
   if(!TerminalInfoInteger(TERMINAL_TRADE_ALLOWED) || !MQLInfoInteger(MQL_TRADE_ALLOWED))
     {
      g_pd_ok = false;
      g_pd_msg = "Not cancelled: Algo Trading is off";
      return;
     }
   string m = "";
   bool ok = RmCancelPending(tk, m);
   g_pd_ok = ok;
   g_pd_msg = (ok ? "Cancelled " : "Not cancelled: ") + m;
   Print(RM_TITLE, ": ", g_pd_msg);
  }

// ---------------- partial close: once per position, at g_pc_r R close g_pc_pct % (one chart runs it: RM_MANAGE_OWNER)
bool PartialOn() { return InpManageAllowed && g_pc_on; }

void PartialRun()
  {
   g_pc_on = GlobalVariableCheck("RM_PC_ON") && GlobalVariableGet("RM_PC_ON") != 0;
   if(!InpManageAllowed || !g_pc_on || g_pc_r <= 0 || g_pc_pct <= 0 || g_pc_pct >= 100)
     {
      Release("MANAGE");
      return;
     }
   if(!Owner("MANAGE"))
      return;
   if(!TerminalInfoInteger(TERMINAL_TRADE_ALLOWED) || !MQLInfoInteger(MQL_TRADE_ALLOWED))
      return;
   for(int i = PositionsTotal() - 1; i >= 0; i--)
     {
      ulong tk = PositionGetTicket(i);
      if(tk == 0)
         continue;
      if(g_trail_scope == 0 && PositionGetInteger(POSITION_MAGIC) != InpMagic)
         continue;
      string dk = "RM_PC_D_" + IntegerToString((long)tk);
      if(TrailExcluded(tk) || GlobalVariableCheck(dk))
         continue;
      string sym = PositionGetString(POSITION_SYMBOL);
      bool buy = PositionGetInteger(POSITION_TYPE) == POSITION_TYPE_BUY;
      double op = PositionGetDouble(POSITION_PRICE_OPEN), sl = PositionGetDouble(POSITION_SL), vol = PositionGetDouble(POSITION_VOLUME);
      if(sl <= 0)
         continue;
      double cost = 0;
      double r = TrailR(tk, sym, buy, op, sl, cost);
      if(r <= 0 || !PositionSelectByTicket(tk))
         continue;
      double px = buy ? SymbolInfoDouble(sym, SYMBOL_BID) : SymbolInfoDouble(sym, SYMBOL_ASK);
      if(px <= 0 || (buy ? px - op : op - px) / r < g_pc_r - 1e-9)
         continue;
      if(TrailBusy(tk))
         continue;
      string m = "";
      bool ok = RmPartialClose(tk, vol * g_pc_pct / 100.0, (ulong)MathMax(0, InpDeviation), "RM partial " + XText(g_pc_r) + "R", m);
      if(ok || StringFind(m, "RM_TOO_SMALL") == 0 || StringFind(m, "RM_FULL_CLOSE") == 0)
         GlobalVariableSet(dk, 1);                      // once per position
      g_pc_ok = ok;
      g_pc_msg = (ok ? "Closed part: " : "Not closed: ") + m;
      Print(RM_TITLE, " partial close: ", ok ? "done " : "not done ", m);
      if(ok && g_push_tr)
         Push("Partial close: " + m);
     }
  }

// switch the partial close on (after one Windows dialog, default answer No) or off; one choice for every chart
void PartialSwitch()
  {
   if(!InpManageAllowed)
      return;
   if(g_pc_on)
     {
      g_pc_on = false;
      GlobalVariableSet("RM_PC_ON", 0);
      g_pc_ok = false;
      g_pc_msg = "Partial close OFF";
      return;
     }
   if(g_pc_r <= 0 || g_pc_pct <= 0 || g_pc_pct >= 100)
     {
      g_pc_ok = false;
      g_pc_msg = "Settings tab: R above 0 and a share between 1 and 99 %";
      return;
     }
   int n = 0;
   for(int i = PositionsTotal() - 1; i >= 0; i--)
      if(PositionGetTicket(i) > 0 && (g_trail_scope == 1 || PositionGetInteger(POSITION_MAGIC) == InpMagic))
         n++;
   string txt = StringFormat("Start the partial close on %s?\n\nWhen a position reaches %sR, %s%% of it is closed at the market, once.\n"
                             "It never closes a whole position and never opens one. %d open position(s) now, and later ones.\n"
                             "It works while MetaTrader and this EA are running.", g_trail_scope == 0 ? "the panel's positions" : "ALL positions",
                             XText(g_pc_r), XText(g_pc_pct), n);
   if(g_lang == 1)
      txt = StringFormat("سیو سود پله‌ای روی %s شروع شود؟\n\nوقتی پوزیشن به %sR برسد، %s٪ آن یک بار به قیمت بازار بسته می‌شود.\n"
                         "هرگز کل پوزیشن را نمی‌بندد و هرگز پوزیشن باز نمی‌کند. الان %d پوزیشن باز، و پوزیشن‌های بعدی.\n"
                         "تا وقتی متاتریدر و این EA روشن‌اند کار می‌کند.", g_trail_scope == 0 ? "پوزیشن‌های پنل" : "همه‌ی پوزیشن‌ها",
                         XText(g_pc_r), XText(g_pc_pct), n);
   if(MessageBox(txt, g_lang == 1 ? "مدیر ریسک اسلات - سیو سود" : RM_TITLE + " - partial close",
                 MB_YESNO | MB_ICONQUESTION | MB_DEFBUTTON2 | RtlFlags()) != IDYES)
     {
      g_pc_ok = false;
      g_pc_msg = "Partial close stays OFF";
      return;
     }
   g_pc_on = true;
   GlobalVariableSet("RM_PC_ON", 1);
   g_pc_ok = true;
   g_pc_msg = "Partial close ON";
  }

int DrawPartial(const int L, const int R, int cy)
  {
   if(!InpManageAllowed)
     {
      Text(PB + "pc_off", L, cy, FitText("Partial close off (EA input 'Allow partial close and cancelling')", "Segoe UI", 8, R - L), C_FAINT, 8);
      return cy + Z(22);
     }
   Section(PB + "s_pc", L, R, cy, "PARTIAL CLOSE", "", false, "", C_DIM);
   cy += Z(24);
   cy = ToggleRow("PCON", L, R, cy, g_pc_on ? "ON: at " + XText(g_pc_r) + "R close " + XText(g_pc_pct) + "% (once)" : "Partial close OFF", g_pc_on,
                  g_pc_on ? "Click to stop the partial close" : "Click to start the partial close (asks once)", C_GREEN);
   if(!InpTrailAllowed)                                 // the Panel / All choice is in TRAILING; without it, here
     {
      int rh = Z(26), sx = L + Z(150);
      TextV(L, cy + rh / 2, "Positions", C_DIM, 9);
      string sl[2] = {"Panel", "All"};
      int sv[2] = {0, 1};
      string st[2] = {"Only positions opened by this panel (magic " + IntegerToString(InpMagic) + ")", "Every open position of the account"};
      Seg(PB + "BTN_TRS", sx, cy, R - sx, rh, sl, sv, 2, g_trail_scope, st);
      cy += Z(32);
     }
   Text(PB + "pc_sc", L, cy, FitText((g_trail_scope == 0 ? "Panel positions" : "All positions") + string("  ·  share and R: Settings tab"),
        "Segoe UI", 8, R - L), C_FAINT, 8);
   cy += Z(16);
   if(g_pc_msg != "")
     {
      string ln[];
      int k = Wrap(g_pc_msg, "Segoe UI", 8, R - L, 2, ln);
      for(int i = 0; i < k; i++)
        {
         Text(PB + "pc_m" + IntegerToString(i), L, cy, ln[i], g_pc_ok ? C_GREEN : C_AMBER, 8);
         cy += Z(15);
        }
     }
   return cy + Z(8);
  }

// ---------------- ATR / swing trailing: the model's stop for a position (0 = none)
string g_atr_key[];
int    g_atr_h[];

int AtrHandle(const string sym, const ENUM_TIMEFRAMES tf)
  {
   string key = sym + "|" + IntegerToString((int)tf) + "|" + IntegerToString(g_tr_atr_n);
   for(int i = 0; i < ArraySize(g_atr_key); i++)
      if(g_atr_key[i] == key)
         return g_atr_h[i];
   int h = iATR(sym, tf, g_tr_atr_n);
   if(h == INVALID_HANDLE)
      return h;
   int n = ArraySize(g_atr_key);
   ArrayResize(g_atr_key, n + 1);
   ArrayResize(g_atr_h, n + 1);
   g_atr_key[n] = key;
   g_atr_h[n] = h;
   return h;
  }

void AtrFree()
  {
   for(int i = 0; i < ArraySize(g_atr_h); i++)
      IndicatorRelease(g_atr_h[i]);
   ArrayResize(g_atr_h, 0);
   ArrayResize(g_atr_key, 0);
  }

double TrailModelStop(const string sym, const bool buy, const double px)
  {
   ENUM_TIMEFRAMES tf = TrailTf();
   if(g_tr_mode == 1)
     {
      int h = AtrHandle(sym, tf);
      double b[];
      if(h == INVALID_HANDLE || CopyBuffer(h, 0, 1, 1, b) != 1 || b[0] <= 0)
         return 0;
      return buy ? px - g_tr_atr_k * b[0] : px + g_tr_atr_k * b[0];
     }
   if(g_tr_mode == 2)
     {
      int k = buy ? iLowest(sym, tf, MODE_LOW, g_tr_swing, 1) : iHighest(sym, tf, MODE_HIGH, g_tr_swing, 1);
      if(k < 0)
         return 0;
      double sp = SymbolInfoDouble(sym, SYMBOL_ASK) - SymbolInfoDouble(sym, SYMBOL_BID);
      return buy ? iLow(sym, tf, k) - sp : iHigh(sym, tf, k) + sp;
     }
   return 0;
  }

// ---------------- today (POSITIONS tab): the daily limit, slots, and today's closed trades
int DrawToday(const int L, const int R, int cy)
  {
   // ---- the day (folded: one line)
   bool wide = SpreadLimit(v_bid) > 0 && v_spread > SpreadLimit(v_bid) + 1e-12;
   bool fd = Folded(3);
   string ds = "left " + Fmt(v_left, 2) + " / " + Fmt(g_daily, 0) + "  ·  slots " + IntegerToString(v_slots_left) + "/" +
               IntegerToString(v_slots_all) + "  ·  spread " + Dist(v_spread);
   color dc = v_slots_left < 1 ? C_RED : ((v_left < v_budget || wide) ? C_AMBER : C_TXT);
   Section(PB + "s_day", L, R, cy, "TODAY", "DAY", fd, ds, dc);
   cy += Z(24);
   if(!fd)
     {
      KV(PB + "k_mkt", L, R, cy, _Symbol, "Bid " + Px(v_bid) + "  ·  spread " + Dist(v_spread), wide ? C_AMBER : C_TXT);
      cy += Z(20);
      KV(PB + "k_day", L, R, cy, "Daily limit", "lost " + Fmt(v_day.used, 2) + "  ·  open " + Fmt(v_day.open_risk, 2) + "  ·  left " +
         Fmt(v_left, 2), v_left < v_budget ? C_AMBER : C_TXT);
      cy += Z(20);
      Bar(L, cy, R - L, g_daily > 0 ? (v_day.used + v_day.open_risk) / g_daily : 0, v_left < v_budget ? C_AMBER : C_ON);
      cy += Z(12);
      string sl = IntegerToString(v_slots_left) + " of " + IntegerToString(v_slots_all) + "  ·  " + Fmt(v_budget, 2) + " each";
      TextV(L, cy + Z(9), "Slots", C_DIM, 9);
      TextV(R, cy + Z(9), sl, v_slots_left > 0 ? C_TXT : C_RED, 9, "Segoe UI", true);
      int px0 = L + Z(44), pw = Z(14), room = R - TextW(sl, "Segoe UI", 9) - Z(10) - px0;
      int np = MathMin(v_slots_all, MathMax(0, room / (pw + Z(4))));
      if(!g_dry)
         for(int i = 0; i < np; i++)
            UiRound(px0 + i * (pw + Z(4)), cy + Z(5), pw, Z(8), Z(3), i < v_slots_left ? C_GREEN : C_CTRL);
      cy += Z(26);
     }
   // today's closed trades and the journal file (2.70)
   string sc = v_sc_n == 0 ? "No closed trade today" :
               StringFormat("Closed %d  ·  %d W / %d L (%d%%)  ·  %s%s %s", v_sc_n, v_sc_win, v_sc_loss, (int)MathRound(100.0 * v_sc_win / v_sc_n),
                            v_sc_net >= 0 ? "+" : "", Fmt(v_sc_net, 2), Cur()) + (v_sc_rn > 0 ? StringFormat("  ·  %+.1fR", v_sc_r) : "");
   Text(PB + "sc_1", L, cy, FitText(sc, "Segoe UI Semibold", 9, R - L), v_sc_n == 0 ? C_DIM : (v_sc_net >= 0 ? C_GREEN : C_RED), 9,
        "Segoe UI Semibold");
   cy += Z(18);
   Text(PB + "sc_2", L, cy, FitText(StringFormat("Losing trades in a row: %d  ·  journal file: %d trades", v_hist.streak, v_jr_n), "Segoe UI", 8,
        R - L), C_DIM, 8);
   cy += Z(16);
   Text(PB + "sc_3", L, cy, FitText("MQL5\\Files\\" + RM_JOURNAL, "Segoe UI", 8, R - L), C_FAINT, 8);
   cy += Z(22);
   return cy;
  }

// ================= 2.90: themes (auto / dark / light, sun-moon button), button colours, fonts, quick place

// ---------------- theme and colours
// colour as #RRGGBB (MT5 colours keep red in the low byte)
string ColorHex(const color c)
  {
   uint u = (uint)c;
   return StringFormat("#%02X%02X%02X", u & 0xFF, (u >> 8) & 0xFF, (u >> 16) & 0xFF);
  }

int HexVal(const ushort ch)
  {
   if(ch >= '0' && ch <= '9') return ch - '0';
   if(ch >= 'a' && ch <= 'f') return ch - 'a' + 10;
   if(ch >= 'A' && ch <= 'F') return ch - 'A' + 10;
   return -1;
  }

bool HexColor(const string t0, color &c)
  {
   string t = t0;
   StringReplace(t, "#", "");
   StringTrimLeft(t);
   StringTrimRight(t);
   if(StringLen(t) != 6)
      return false;
   int v[3] = {0, 0, 0};
   for(int i = 0; i < 3; i++)
     {
      int hi = HexVal(StringGetCharacter(t, 2 * i)), lo = HexVal(StringGetCharacter(t, 2 * i + 1));
      if(hi < 0 || lo < 0)
         return false;
      v[i] = hi * 16 + lo;
     }
   c = (color)(v[0] | (v[1] << 8) | (v[2] << 16));
   return true;
  }

// the panel's colours: dark or light (auto = the chart's background), the accent, BUY / SELL, the contrast of grey text
void ApplyTheme()
  {
   uint u = (uint)ChartGetInteger(0, CHART_COLOR_BACKGROUND);
   double lum = 0.299 * (u & 0xFF) + 0.587 * ((u >> 8) & 0xFF) + 0.114 * ((u >> 16) & 0xFF);
   g_dark = g_theme == 1 || (g_theme == 0 && lum < 128);
   if(g_dark)
     {
      C_BG = C'17,20,26'; C_HEAD = C'22,26,33'; C_CARD = C'25,29,37'; C_CTRL = C'33,38,48'; C_HOVER = C'44,50,62';
      C_EDGE = C'44,50,62'; C_LINE = C'34,39,49'; C_TXT = C'231,234,240'; C_DIM = C'140,148,163'; C_FAINT = C'96,104,120';
      C_GREEN = C'34,197,94'; C_RED = C'239,68,68'; C_AMBER = C'245,158,11';
      g_shadow = 0.42;
      if(g_contrast) { C_TXT = C'246,247,250'; C_DIM = C'190,197,209'; C_FAINT = C'150,158,173'; }
     }
   else
     {
      C_BG = C'249,250,252'; C_HEAD = C'240,242,246'; C_CARD = C'255,255,255'; C_CTRL = C'231,234,239'; C_HOVER = C'218,223,230';
      C_EDGE = C'213,218,226'; C_LINE = C'226,230,236'; C_TXT = C'17,24,39'; C_DIM = C'75,85,99'; C_FAINT = C'120,128,141';
      C_GREEN = C'21,128,61'; C_RED = C'200,30,30'; C_AMBER = C'180,110,0';
      g_shadow = 0.16;
      if(g_contrast) { C_TXT = C'8,12,20'; C_DIM = C'45,55,70'; C_FAINT = C'85,94,108'; }
     }
   C_ON = (g_acc_i >= 0 && g_acc_i < 5) ? g_accs[g_acc_i] : g_acc_custom;
   C_OFF = C_CTRL;
   if(g_bs_i == 1) { C_BUYON = C'37,99,235'; C_SELON = C'234,88,12'; }   // blue / orange (easier when green and red look alike)
   else { C_BUYON = C'22,163,74'; C_SELON = C'220,38,38'; }
  }

// fonts: auto = Tahoma for Persian, Segoe UI for English
void ApplyFont()
  {
   string fr[5] = {"", "Segoe UI", "Tahoma", "Arial", "B Nazanin"};
   int fi = g_font_i == 0 ? (g_lang == 1 ? 2 : 1) : g_font_i;
   if(fi < 1 || fi > 4)
      fi = 1;
   UiFR = fr[fi];
   UiFB = fi == 1 ? "Segoe UI Semibold" : fr[fi];
   UiFBf = fi == 1 ? 0 : FW_BOLD;
  }

int DrawLook(const int L, const int R, int cy)
  {
   Section(PB + "s_lk", L, R, cy, "APPEARANCE", "", false, "", C_DIM);
   cy += Z(24);
   int rh = Z(26), lx = L + Z(70);
   TextV(L, cy + rh / 2, "Theme", C_DIM, 9);
   string tl[3] = {"Auto", "Dark", "Light"};
   int tv[3] = {0, 1, 2};
   string tt[3] = {"Follow the chart background", "Always dark", "Always light"};
   Seg(PB + "BTN_THS", lx, cy, R - lx, rh, tl, tv, 3, g_theme, tt);
   cy += Z(32);
   TextV(L, cy + rh / 2, "Colour", C_DIM, 9);
   string at[6] = {"Blue accent", "Teal accent", "Purple accent", "Orange accent", "Amber accent", "Your colour (field on the right)"};
   int sw = Z(18), gap = Z(6), sx = lx;
   for(int i = 0; i < 6; i++)
     {
      string id = PB + "BTN_ACC" + IntegerToString(i);
      if(!g_dry)
        {
         color c = i < 5 ? g_accs[i] : g_acc_custom;
         bool sel = g_acc_i == i, hov = g_hover == id;
         if(sel || hov)
            UiCircle(sx + sw / 2, cy + rh / 2, sw / 2 + Z(2), sel ? C_TXT : C_HOVER);
         UiCircle(sx + sw / 2, cy + rh / 2, sw / 2 - (sel ? Z(1) : 0), c);
         if(i == 5)
            UiPlusMinus(sx + sw / 2, cy + rh / 2, Z(4), true, clrWhite);
         UiZone(id, sx, cy, sw, rh, at[i]);
        }
      sx += sw + gap;
     }
   Ed(PB + "ED_ACCX", sx, cy, R - sx, rh, ColorHex(g_acc_custom), "Custom colour: #RRGGBB", "#", true);
   cy += Z(32);
   TextV(L, cy + rh / 2, "BUY / SELL", C_DIM, 9);
   string bl[2] = {"Green / Red", "Blue / Orange"};
   int bv[2] = {0, 1};
   string bt[2] = {"BUY green, SELL red", "BUY blue, SELL orange (easier when green and red look alike)"};
   Seg(PB + "BTN_BSC", lx, cy, R - lx, rh, bl, bv, 2, g_bs_i, bt);
   cy += Z(32);
   TextV(L, cy + rh / 2, "Font", C_DIM, 9);
   string fl[5] = {"Auto", "Segoe", "Tahoma", "Arial", "Nazanin"};
   int fv[5] = {0, 1, 2, 3, 4};
   string ft[5] = {"Auto: Tahoma for Persian, Segoe UI for English", "Segoe UI", "Tahoma: clear at small sizes, Persian and English", "Arial",
                   "B Nazanin (when installed)"};
   Seg(PB + "BTN_UFN", lx, cy, R - lx, rh, fl, fv, 5, g_font_i, ft);
   cy += Z(34);
   cy = ToggleRow("HCON", L, R, cy, "High contrast text", g_contrast, "Brighter grey text for easier reading");
   return cy + Z(6);
  }

// ---------------- quick place: entry at the market and the stop k x ATR away, for the risk chosen; drag the lines, then Order
ENUM_TIMEFRAMES QpTf() { return g_qp_tf == 0 ? PERIOD_M5 : (g_qp_tf == 2 ? PERIOD_H1 : PERIOD_M15); }

double QpDistance()
  {
   ENUM_TIMEFRAMES tf = QpTf();
   if(g_qp_atr == INVALID_HANDLE || g_qp_atr_tf != tf)
     {
      if(g_qp_atr != INVALID_HANDLE)
         IndicatorRelease(g_qp_atr);
      g_qp_atr = iATR(_Symbol, tf, 14);
      g_qp_atr_tf = tf;
     }
   double b[];
   double d = 0;
   if(g_qp_atr != INVALID_HANDLE && CopyBuffer(g_qp_atr, 0, 1, 1, b) == 1 && b[0] > 0)
      d = g_qp_k * b[0];
   double bid = SymbolInfoDouble(_Symbol, SYMBOL_BID), ask = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
   double sp = MathMax(0.0, ask - bid);
   if(d <= 0)
      d = MathMax(10 * sp, bid * 0.002);               // no ATR yet: 10 spreads or 0.2% of the price
   return MathMax(d, 3 * sp);
  }

void QpOn()
  {
   double bid = SymbolInfoDouble(_Symbol, SYMBOL_BID), ask = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
   if(bid <= 0 || ask <= 0)
     {
      g_order_ok = false;
      g_order_msg = "Quick place: no quote";
      g_msg_at = GetTickCount();
      return;
     }
   double d = QpDistance();
   double e = g_buy ? ask : bid;
   g_entry_src = 0;                                    // at the market; drag the entry line for a pending order
   g_entry_px = 0;
   g_sl_src = 4;
   g_sl_manual = NormalizeDouble(g_buy ? e - d : e + d, _Digits);
   SetEd("SL", DoubleToString(g_sl_manual, _Digits));
   SetEd("ENTRY", "");
   g_qp = true;
   g_confirm = false;
   g_order_ok = true;
   g_order_msg = "Quick place: drag the entry, stop and TP lines, then Order";
   g_msg_at = GetTickCount();
  }

void QpOff()
  {
   g_qp = false;
   g_sl_manual = 0;
   g_entry_src = 0;
   g_entry_px = 0;
   SetEd("SL", "");
   SetEd("ENTRY", "");
  }

void QpToggle()
  {
   if(g_qp)
      QpOff();
   else
      QpOn();
  }

// the side follows the stop: below the entry = BUY, above it = SELL
void QpSide()
  {
   if(!g_qp || g_sl_src != 4 || g_sl_manual <= 0)
      return;
   double ref = (g_entry_src == 3 && g_entry_px > 0) ? g_entry_px
                : (SymbolInfoDouble(_Symbol, SYMBOL_BID) + SymbolInfoDouble(_Symbol, SYMBOL_ASK)) / 2;
   if(ref > 0)
      g_buy = g_sl_manual < ref;
  }

int DrawQpSet(const int L, const int R, int cy)
  {
   Section(PB + "s_qp", L, R, cy, "QUICK PLACE", "", false, "", C_DIM);
   cy += Z(24);
   int rh = Z(26), w2 = (R - L - Z(8)) / 2, x2 = L + w2 + Z(8);
   Ed(PB + "ED_QPK", L, cy, w2, rh, XText(g_qp_k), "Stop distance at the start: this many ATR (14)", "ATR x");
   string fl[3] = {"M5", "M15", "H1"};
   int fv[3] = {0, 1, 2};
   string ft[3] = {"Timeframe M5", "Timeframe M15", "Timeframe H1"};
   Seg(PB + "BTN_QPT", x2, cy, R - x2, rh, fl, fv, 3, g_qp_tf, ft);
   cy += Z(32);
   Text(PB + "qp_n", L, cy, FitText("Place button (or Q): entry, stop and TPs on the chart for your risk", "Segoe UI", 8, R - L), C_FAINT, 8);
   return cy + Z(24);
  }

// ---------------- chart (2.60): risk box, labels, next trailing steps
// money of all legs if the price reaches `px` (deposit currency, net of the commission)
double MoneyAt(const double px)
  {
   ENUM_ORDER_TYPE ot = g_buy ? ORDER_TYPE_BUY : ORDER_TYPE_SELL;
   double sum = 0, p = 0;
   if(v_s1.ok && OrderCalcProfit(ot, _Symbol, v_s1.lot, v_e1, px, p)) sum += p;
   if(g_parts >= 2 && v_s2.ok && OrderCalcProfit(ot, _Symbol, v_s2.lot, v_e2, px, p)) sum += p;
   if(g_parts == 3 && v_s3.ok && OrderCalcProfit(ot, _Symbol, v_s3.lot, v_e3, px, p)) sum += p;
   return sum - v_cost_comm;
  }

bool ChartRect(const string n, const double a, const double b, const datetime t1, const datetime t2, const color c)
  {
   string name = PC + n;
   if(a <= 0 || b <= 0)
     {
      ObjectDelete(0, name);
      return false;
     }
   bool made = false;
   if(ObjectFind(0, name) < 0)
      made = ObjectCreate(0, name, OBJ_RECTANGLE, 0, t1, a, t2, b);
   ObjectSetInteger(0, name, OBJPROP_TIME, 0, t1);
   ObjectSetDouble(0, name, OBJPROP_PRICE, 0, a);
   ObjectSetInteger(0, name, OBJPROP_TIME, 1, t2);
   ObjectSetDouble(0, name, OBJPROP_PRICE, 1, b);
   ObjectSetInteger(0, name, OBJPROP_COLOR, c);
   ObjectSetInteger(0, name, OBJPROP_FILL, true);
   ObjectSetInteger(0, name, OBJPROP_BACK, true);
   ObjectSetInteger(0, name, OBJPROP_SELECTABLE, false);
   ObjectSetInteger(0, name, OBJPROP_HIDDEN, true);
   return made;
  }

bool ChartLabel(const string n, const datetime t, const double p, const string text, const color c)
  {
   string name = PC + n;
   if(p <= 0 || text == "")
     {
      ObjectDelete(0, name);
      return false;
     }
   bool made = false;
   if(ObjectFind(0, name) < 0)
      made = ObjectCreate(0, name, OBJ_TEXT, 0, t, p);
   ObjectSetInteger(0, name, OBJPROP_TIME, 0, t);
   ObjectSetDouble(0, name, OBJPROP_PRICE, 0, p);
   ObjectSetString(0, name, OBJPROP_TEXT, LangTrPlain(text));
   ObjectSetString(0, name, OBJPROP_FONT, "Segoe UI Semibold");
   ObjectSetInteger(0, name, OBJPROP_FONTSIZE, 8);
   ObjectSetInteger(0, name, OBJPROP_COLOR, c);
   ObjectSetInteger(0, name, OBJPROP_ANCHOR, ANCHOR_LEFT);
   ObjectSetInteger(0, name, OBJPROP_SELECTABLE, false);
   ObjectSetInteger(0, name, OBJPROP_HIDDEN, true);
   return made;
  }

// red box from the entry to the stop, green box from the entry to the take-profit, from the last bar 25 bars to the
// right, with the risk / reward in R and money at the right edge
bool RiskBox(const bool show, const double tp)
  {
   bool made = false;
   datetime t1 = iTime(_Symbol, PERIOD_CURRENT, 0);
   datetime t2 = t1 + PeriodSeconds() * 25;
   color bg = (color)ChartGetInteger(0, CHART_COLOR_BACKGROUND);
   color fg = (color)ChartGetInteger(0, CHART_COLOR_FOREGROUND);
   bool on = show && t1 > 0;
   made = ChartRect("BOX_SL", on ? v_e1 : 0, on ? v_sl : 0, t1, t2, UiMix(bg, C_RED, 0.22)) || made;
   made = ChartRect("BOX_TP", on && tp > 0 ? v_e1 : 0, on && tp > 0 ? tp : 0, t1, t2, UiMix(bg, C_GREEN, 0.22)) || made;
   double d = MathAbs(v_e1 - v_sl);
   string sl_t = on ? StringFormat("SL  -1R  -%s %s", Fmt(v_total, 2), Cur()) : "";
   string en_t = on ? StringFormat("%s  %s lot", g_buy ? "BUY" : "SELL", Lot(v_lots)) : "";
   string tp_t = on && tp > 0 && d > 0 ? StringFormat("TP  +%sR  +%s %s", Fmt(MathAbs(tp - v_e1) / d, 1), Fmt(MoneyAt(tp), 2), Cur()) : "";
   made = ChartLabel("LB_SL", t2, on ? v_sl : 0, sl_t, UiMix(fg, C_RED, 0.7)) || made;
   made = ChartLabel("LB_EN", t2, on ? v_e1 : 0, en_t, fg) || made;
   made = ChartLabel("LB_TP", t2, on && tp > 0 ? tp : 0, tp_t, UiMix(fg, C_GREEN, 0.7)) || made;
   return made;
  }

// the next trailing step of the positions on this chart's symbol (up to 3): a dashed amber line and what happens there
bool NextSteps()
  {
   bool made = false;
   int k = 0;
   datetime t2 = iTime(_Symbol, PERIOD_CURRENT, 0) + PeriodSeconds() * 25;
   for(int i = 0; i < v_pos_n && k < 3; i++)
     {
      if(v_pos[i].sym != _Symbol || v_pos[i].next_px <= 0)
         continue;
      made = HLine("NX" + IntegerToString(k), v_pos[i].next_px, C_AMBER, STYLE_DASHDOT, 1, false, "Trailing next: " + v_pos[i].next_txt) || made;
      made = ChartLabel("NXL" + IntegerToString(k), t2, v_pos[i].next_px, "Trail: " + v_pos[i].next_txt, C_AMBER) || made;
      k++;
     }
   for(; k < 3; k++)
     {
      HLine("NX" + IntegerToString(k), 0, C_AMBER, STYLE_DASHDOT, 1, false, "");
      ChartLabel("NXL" + IntegerToString(k), 0, 0, "", C_AMBER);
     }
   return made;
  }

// ---------------- open positions (2.60)
string RText(const double k) { return MathAbs(k) < 0.05 ? "entry" : StringFormat("%+.1fR", k); }

void PosScan()
  {
   v_pos_n = 0;
   TrailClean();                                        // remembered R of closed positions, once a minute
   int n = PositionsTotal();
   ArrayResize(v_pos, n);
   bool trail = TrailActive();
   for(int i = n - 1; i >= 0; i--)
     {
      ulong tk = PositionGetTicket(i);
      if(tk == 0)
         continue;
      RmPos q;
      q.tk = tk;
      q.sym = PositionGetString(POSITION_SYMBOL);
      q.buy = PositionGetInteger(POSITION_TYPE) == POSITION_TYPE_BUY;
      q.vol = PositionGetDouble(POSITION_VOLUME);
      q.op = PositionGetDouble(POSITION_PRICE_OPEN);
      q.sl = PositionGetDouble(POSITION_SL);
      q.tp = PositionGetDouble(POSITION_TP);
      q.pl = PositionGetDouble(POSITION_PROFIT) + PositionGetDouble(POSITION_SWAP);
      q.in_scope = g_trail_scope == 1 || PositionGetInteger(POSITION_MAGIC) == InpMagic;
      q.excluded = TrailExcluded(tk);
      double cost = 0;
      q.r = q.sl > 0 ? TrailR(tk, q.sym, q.buy, q.op, q.sl, cost) : 0;
      double px = q.buy ? SymbolInfoDouble(q.sym, SYMBOL_BID) : SymbolInfoDouble(q.sym, SYMBOL_ASK);
      q.gain = q.r > 0 && px > 0 ? (q.buy ? px - q.op : q.op - px) / q.r : 0;
      q.ksl = q.r > 0 && q.sl > 0 ? (q.buy ? q.sl - q.op : q.op - q.sl) / q.r : 0;
      q.next_px = 0;
      q.next_txt = "";
      if(trail && q.in_scope && !q.excluded && q.r > 0)
        {
         double st = RmTrailStep(q.gain, g_tr_start, g_tr_step);
         double nx = st < 0 ? g_tr_start : st + g_tr_step;
         double d = q.buy ? 1.0 : -1.0;
         q.next_px = q.op + d * nx * q.r;
         q.next_txt = "at " + XText(nx) + "R stop " + RText(nx - g_tr_lag) +
                      (g_tr_lead > 0 && q.tp > 0 ? ", TP " + XText(nx + g_tr_lead) + "R" : "");
         if(g_tr_mode > 0)
           {
            string mn = g_tr_mode == 1 ? "ATR" : "swing";
            q.next_txt = st < 0 ? "at " + XText(nx) + "R stop entry, then " + mn : (g_tr_lead > 0 && q.tp > 0 ? "at " + XText(nx) + "R TP " +
                         XText(nx + g_tr_lead) + "R  ·  stop: " + mn : "");
            if(q.next_txt == "")
               q.next_px = 0;
           }
        }
      v_pos[v_pos_n++] = q;
     }
   ArrayResize(v_pos, v_pos_n);
  }

int DrawPositions(const int L, const int R, int cy)
  {
   double tot = 0;
   for(int i = 0; i < v_pos_n; i++)
      tot += v_pos[i].pl;
   bool f = Folded(8);
   string sum = v_pos_n == 0 ? "none open" : IntegerToString(v_pos_n) + " open  ·  " + (tot >= 0 ? "+" : "") + Fmt(tot, 2) + " " + Cur() +
                (TrailActive() ? "  ·  " + IntegerToString(v_tr_n) + " trailed" : "");
   Section(PB + "s_pos", L, R, cy, "POSITIONS", "POS", f, sum, v_pos_n == 0 ? C_DIM : (tot >= 0 ? C_GREEN : C_RED));
   cy += Z(24);
   if(f)
      return cy;
   if(v_pos_n == 0)
     {
      Text(PB + "ps_none", L, cy, "No open position", C_FAINT, 8);
      cy += Z(18);
     }
   int np = MathMin(6, v_pos_n);
   bool trail = TrailActive();
   for(int i = 0; i < np; i++)
     {
      RmPos q = v_pos[i];
      string id = IntegerToString(i);
      color pc = q.pl >= 0 ? C_GREEN : C_RED;
      int dg = (int)SymbolInfoInteger(q.sym, SYMBOL_DIGITS);
      Dot(L + Z(4), cy + Z(8), pc);
      Text(PB + "ps_h" + id, L + Z(14), cy, FitText(q.sym + "  " + (q.buy ? "BUY" : "SELL") + "  " + DoubleToString(q.vol, 2), "Segoe UI Semibold", 9,
           Z(150)), q.sym == _Symbol ? C_TXT : C_DIM, 9, "Segoe UI Semibold");
      Text(PB + "ps_p" + id, R, cy, (q.pl >= 0 ? "+" : "") + Fmt(q.pl, 2) + " " + Cur() + (q.r > 0 ? StringFormat("  ·  %+.1fR", q.gain) : ""),
           pc, 9, "Segoe UI Semibold", true);
      cy += Z(17);
      string info = (q.sl > 0 ? "SL " + (q.r > 0 ? RText(q.ksl) : DoubleToString(q.sl, dg)) : "no stop") +
                    (q.tp > 0 ? "  ·  TP " + DoubleToString(q.tp, dg) : "  ·  no TP");
      bool can = (trail || PartialOn()) && q.in_scope && q.r > 0;
      if(trail && q.in_scope)
         info += q.excluded ? "  ·  trail off" : (q.r > 0 ? (q.next_txt != "" ? "  ·  next: " + q.next_txt : "") : "  ·  R unknown");
      int tw = can ? R - L - Z(56) : R - L - Z(14);
      Text(PB + "ps_i" + id, L + Z(14), cy, FitText(info, "Segoe UI", 8, tw), q.ksl >= -1e-9 && q.r > 0 ? C_GREEN : C_DIM, 8);
      if(can)
         Toggle(PB + "BTN_PTR" + IntegerToString((long)q.tk), R - Z(34), cy - Z(2), !q.excluded, C_GREEN,
                q.excluded ? "Trailing off for this position: click to trail it" : "Trailing on for this position: click to leave its stop where it is");
      cy += Z(21);
     }
   if(v_pos_n > np)
     {
      Text(PB + "ps_more", L, cy, "+" + IntegerToString(v_pos_n - np) + " more", C_FAINT, 8);
      cy += Z(16);
     }
   bool ph = TerminalInfoInteger(TERMINAL_NOTIFICATIONS_ENABLED) != 0;
   string pt = !g_push ? "Phone notifications off (EA input)" :
               (ph ? "Phone notifications on" : "Phone notifications: set your MetaQuotes ID in Tools > Options > Notifications");
   Text(PB + "ps_ph", L, cy, FitText(pt, "Segoe UI", 8, R - L), g_push && !ph ? C_AMBER : C_FAINT, 8);
   return cy + Z(22);
  }

// ---------------- phone notifications (2.60)
// to the MetaTrader app on the phone (at most 10 a minute; the terminal allows 2 a second and 10 a minute)
void Push(const string msg)
  {
   if(!g_push || !TerminalInfoInteger(TERMINAL_NOTIFICATIONS_ENABLED))
      return;
   uint now = GetTickCount();
   int k = 0;
   for(int i = 0; i < ArraySize(g_push_at); i++)
      if(now - g_push_at[i] < 60000)
         g_push_at[k++] = g_push_at[i];
   ArrayResize(g_push_at, k);
   if(k >= 10)
     {
      Print(RM_TITLE, " notification skipped (10 a minute): ", msg);
      return;
     }
   ArrayResize(g_push_at, k + 1);
   g_push_at[k] = now;
   string t = StringSubstr("SRM: " + LangTrPlain(msg), 0, 255);
   if(!SendNotification(t))
      Print(RM_TITLE, " notification not sent (error ", GetLastError(), "): ", msg);
   else
      Print(RM_TITLE, " notification: ", msg);
  }

// a position that closed since the last look: how and with what result
void NoteClosed(const ulong tk)
  {
   if(!HistorySelectByPosition((long)tk))
      return;
   double net = 0, op = 0, cp = 0;
   string sym = "";
   bool buy = true;
   long reason = -1;
   for(int i = 0; i < HistoryDealsTotal(); i++)
     {
      ulong d = HistoryDealGetTicket(i);
      if(d == 0)
         continue;
      long typ = HistoryDealGetInteger(d, DEAL_TYPE);
      if(typ != DEAL_TYPE_BUY && typ != DEAL_TYPE_SELL)
         continue;
      net += HistoryDealGetDouble(d, DEAL_PROFIT) + HistoryDealGetDouble(d, DEAL_COMMISSION) + HistoryDealGetDouble(d, DEAL_SWAP) +
             HistoryDealGetDouble(d, DEAL_FEE);
      sym = HistoryDealGetString(d, DEAL_SYMBOL);
      if(HistoryDealGetInteger(d, DEAL_ENTRY) == DEAL_ENTRY_IN)
        {
         op = HistoryDealGetDouble(d, DEAL_PRICE);
         buy = typ == DEAL_TYPE_BUY;
        }
      else
        {
         cp = HistoryDealGetDouble(d, DEAL_PRICE);
         reason = HistoryDealGetInteger(d, DEAL_REASON);
        }
     }
   if(sym == "" || cp <= 0)
      return;
   string how = reason == DEAL_REASON_SL ? "stop" : (reason == DEAL_REASON_TP ? "take-profit" : (reason == DEAL_REASON_SO ? "stop out" : "hand / other"));
   string kr = "RM_TR_R_" + IntegerToString((long)tk);
   string rr = "";
   if(GlobalVariableCheck(kr) && GlobalVariableGet(kr) > 0 && op > 0)
      rr = StringFormat(" (%+.1fR)", (buy ? cp - op : op - cp) / GlobalVariableGet(kr));
   Push(StringFormat("%s %s closed by %s: %s%s %s%s", sym, buy ? "BUY" : "SELL", how, net >= 0 ? "+" : "", Fmt(net, 2), Cur(), rr));
  }

// once a second, on one chart: closed positions, the daily limit, a session opening
void NoteRun()
  {
   if(!g_push || !Owner("NOTE"))
     {
      g_nt_init = false;
      return;
     }
   ulong now_tk[];
   int n = PositionsTotal();
   ArrayResize(now_tk, n);
   int m = 0;
   for(int i = 0; i < n; i++)
     {
      ulong tk = PositionGetTicket(i);
      if(tk > 0)
         now_tk[m++] = tk;
     }
   ArrayResize(now_tk, m);
   bool closed = false;
   if(g_nt_init && g_push_cl)
      for(int i = 0; i < ArraySize(g_nt_tk); i++)
        {
         bool open = false;
         for(int j = 0; j < m && !open; j++)
            open = now_tk[j] == g_nt_tk[i];
         if(!open)
           {
            NoteClosed(g_nt_tk[i]);
            closed = true;
           }
        }
   ArrayResize(g_nt_tk, m);
   for(int i = 0; i < m; i++)
      g_nt_tk[i] = now_tk[i];
   if(g_nt_init && g_push_day && g_nt_slots >= 1 && v_slots_left < 1 && v_slots_all > 0)
      Push("Daily loss limit used up: no new trade today (lost " + Fmt(v_day.used, 2) + " " + Cur() + ")");
   g_nt_slots = v_slots_left;
   bool win = g_v2on && v_win_on && v_win_in && v_ses_now >= 0;
   if(g_nt_init && g_nt_win_known && g_push_ses && win && !g_nt_win)
      Push(SES_NAME[v_ses_now] + " session open: your trading window on " + _Symbol);
   g_nt_win = win;
   g_nt_win_known = true;
   g_nt_init = true;
   if(closed)
      g_hist_dirty = true;                              // a trade closed: read today's history again
  }

// ---------------- trailing section (2.50): switch, which positions, the rule, one line per trailed position
int DrawTrail(const int L, const int R, int cy)
  {
   if(!InpTrailAllowed)
     {
      Text(PB + "tr_off", L, cy, FitText("Trailing off (EA input 'Allow trailing')", "Segoe UI", 8, R - L), C_FAINT, 8);
      return cy + Z(22);
     }
   bool f = Folded(7);
   string sum = (g_trail_on ? "ON" : "OFF") + string("  ·  ") + (g_trail_scope == 0 ? "panel positions" : "all positions") +
                (g_trail_on ? "  ·  " + IntegerToString(v_tr_n) + " trailed" : "");
   Section(PB + "s_tr", L, R, cy, "TRAILING", "TRL", f, sum, g_trail_on ? C_GREEN : C_DIM);
   cy += Z(24);
   if(f)
      return cy;
   int rh = Z(26);
   Toggle(PB + "BTN_TRL", L, cy + Z(4), g_trail_on, C_GREEN,
          g_trail_on ? "Click to stop the trailing (stops stay where they are)" : "Click to start the trailing (asks once)");
   TextV(L + Z(42), cy + rh / 2, g_trail_on ? "Trailing ON" : "Trailing OFF", g_trail_on ? C_GREEN : C_DIM, 9, "Segoe UI Semibold");
   string sl[2] = {"Panel", "All"};
   int sv[2] = {0, 1};
   string st[2] = {"Only positions opened by this panel (magic " + IntegerToString(InpMagic) + "), every symbol",
                   "Every open position of the account: manual trades and other tools too"};
   int sx = L + Z(150);
   Seg(PB + "BTN_TRS", sx, cy, R - sx, rh, sl, sv, 2, g_trail_scope, st);
   cy += Z(34);
   string ln[];
   int n = Wrap(TrailRule(), "Segoe UI", 8, R - L, 2, ln);
   for(int i = 0; i < n; i++)
     {
      Text(PB + "tr_r" + IntegerToString(i), L, cy, ln[i], C_DIM, 8);
      cy += Z(15);
     }
   Text(PB + "tr_st", L, cy, FitText(v_tr_state, "Segoe UI", 8, R - L), StringFind(v_tr_state, "Algo") >= 0 ? C_AMBER : C_TXT, 8);
   cy += Z(17);
   if(g_trail_on)
     {
      Text(PB + "tr_n", L, cy, IntegerToString(v_tr_n) + " position(s) trailed  ·  each one: POSITIONS", C_FAINT, 8);
      cy += Z(16);
     }
   if(g_trail_msg != "")
     {
      string mm[];
      int k = Wrap(g_trail_msg, "Segoe UI", 8, R - L, 2, mm);
      for(int i = 0; i < k; i++)
        {
         Text(PB + "tr_m" + IntegerToString(i), L, cy, mm[i], g_trail_ok ? C_GREEN : C_AMBER, 8);
         cy += Z(15);
        }
     }
   return cy + Z(8);
  }

// switch the trailing on (after one Windows dialog, default answer No) or off; one choice for every chart
void TrailSwitch()
  {
   if(!InpTrailAllowed || !TrailValid())
      return;
   if(g_trail_on)
     {
      g_trail_on = false;
      GlobalVariableSet("RM_TRAIL_ON", 0);
      g_trail_ok = false;
      g_trail_msg = "Trailing OFF: the stops stay where they are";
      return;
     }
   int n = 0;
   for(int i = PositionsTotal() - 1; i >= 0; i--)
      if(PositionGetTicket(i) > 0 && (g_trail_scope == 1 || PositionGetInteger(POSITION_MAGIC) == InpMagic))
         n++;
   string txt = StringFormat("Start the trailing on %s?\n\n%s\n\nIt moves the stop-loss and the take-profit of %d open position(s) now, "
                             "and of later ones, only forward (never back, never removed). It never opens or closes a position.\n"
                             "It works while MetaTrader and this EA are running.", g_trail_scope == 0 ? "the panel's positions" : "ALL positions",
                             TrailRule(), n);
   if(g_lang == 1)
      txt = StringFormat("تریلینگ روی %s شروع شود؟\n\n%s\n\nاستاپ و TP الان %d پوزیشن باز و پوزیشن‌های بعدی را فقط به جلو می‌برد "
                         "(هرگز عقب نمی‌برد و هرگز برنمی‌دارد). هرگز پوزیشنی باز یا بسته نمی‌کند.\nتا وقتی متاتریدر و این EA روشن‌اند کار می‌کند.",
                         g_trail_scope == 0 ? "پوزیشن‌های پنل" : "همه‌ی پوزیشن‌ها", LangTrPlain(TrailRule()), n);
   if(MessageBox(txt, g_lang == 1 ? "مدیر ریسک اسلات - تریلینگ" : RM_TITLE + " - trailing",
                 MB_YESNO | MB_ICONQUESTION | MB_DEFBUTTON2 | RtlFlags()) != IDYES)
     {
      g_trail_msg = "Trailing stays OFF";
      g_trail_ok = false;
      return;
     }
   g_trail_on = true;
   GlobalVariableSet("RM_TRAIL_ON", 1);
   g_trail_ok = true;
   g_trail_msg = "Trailing ON";
  }

// ---------------- engine card
string CardMsg()
  {
   return StringFormat("#A%d  %s %s  %s  ·  zone %s – %s", g_card.no, g_card.buy ? "BUY" : "SELL", g_card.tf,
                       g_card.stage, Px(g_card.zone_low), Px(g_card.zone_high));
  }

// card levels belong to one symbol: they must be near this chart's price (not EURUSD, gold, ...)
bool CardFitsChart()
  {
   if(IsFx() || IsCrypto())
      return false;
   double p = SymbolInfoDouble(_Symbol, SYMBOL_BID);
   double mid = (g_card.zone_low + g_card.zone_high) / 2.0;
   return p > 0 && mid > 0 && MathAbs(mid - p) / p < 0.25;
  }

void LoadCard()
  {
   string err = "";
   double v = 0;
   if(EdNum("CARD", v))
      g_card_no = (int)v;
   if(g_card_no <= 0)
     {
      g_card.found = false;
      g_card_msg = "type a card number, e.g. 247";
      return;
     }
   g_card = RmReadCard(InpCardsFolder, g_card_no, err);
   if(!g_card.found)
     {
      g_card_msg = err;
      return;
     }
   if(!CardFitsChart())
     {
      g_card.found = false;
      g_card_msg = "this card is for another symbol (its levels are far from this chart's price)";
      return;
     }
   g_buy = g_card.buy;
   if(g_sl_src == 4)
      g_sl_src = g_card.ref_low > 0 ? 0 : (g_card.bos_origin > 0 ? 1 : 2);
   if(g_entry_src == 0)
      g_entry_src = 1;                  // a card usually means a pending entry at the zone, not the market price
   g_card_msg = CardMsg();
  }

void ReadEdits()
  {
   double v = 0;
   if(EdNum("ENTRY", v)) g_entry_px = MathMax(0.0, v);
   if(EdNum("E2", v)) g_entry2 = MathMax(0.0, v);
   if(EdNum("E3", v)) g_entry3 = MathMax(0.0, v);
   if(EdNum("SL", v)) g_sl_manual = MathMax(0.0, v);
   if(EdNum("BUF", v)) g_buffer = MathMax(0.0, v);
   if(EdNum("PCT", v)) g_percent = MathMin(5.0, MathMax(0.0, v));
   if(EdNum("FIX", v)) g_fixed = MathMax(0.0, v);
   if(EdNum("REF", v)) g_ref = MathMax(0.0, v);
   if(EdNum("SH", v)) g_share1 = MathMin(100.0, MathMax(0.0, v));
   if(EdNum("SH2", v)) g_share2 = MathMin(100.0, MathMax(0.0, v));
   if(EdNum("DAY", v)) g_daily = MathMax(0.0, v);
   for(int f = 0; f <= RM_FAMILIES; f++)
      if(EdNum("MKX" + IntegerToString(f), v)) g_mk_x[f] = MathMin(50.0, MathMax(0.0, v));
   for(int s = 0; s < 3; s++)
     {
      EdTime("S" + IntegerToString(s) + "A", g_ses_a[s]);
      EdTime("S" + IntegerToString(s) + "B", g_ses_b[s]);
     }
   // 2.70 settings in the panel
   if(EdNum("TRST", v)) g_tr_start = MathMin(20.0, MathMax(0.1, v));
   if(EdNum("TRSP", v)) g_tr_step = MathMin(20.0, MathMax(0.1, v));
   if(EdNum("TRLG", v)) g_tr_lag = MathMin(20.0, MathMax(0.1, v));
   if(EdNum("TRLD", v)) g_tr_lead = MathMin(20.0, MathMax(0.0, v));
   if(EdNum("ATRK", v)) g_tr_atr_k = MathMin(10.0, MathMax(0.2, v));
   if(EdNum("ATRN", v)) g_tr_atr_n = (int)MathMin(200.0, MathMax(2.0, v));
   if(EdNum("SWB", v)) g_tr_swing = (int)MathMin(100.0, MathMax(2.0, v));
   if(EdNum("PCR", v)) g_pc_r = MathMin(20.0, MathMax(0.1, v));
   if(EdNum("PCP", v)) g_pc_pct = MathMin(99.0, MathMax(1.0, v));
   if(EdNum("NWB", v)) g_news_before = (int)MathMin(240.0, MathMax(0.0, v));
   if(EdNum("NWA", v)) g_news_after = (int)MathMin(240.0, MathMax(0.0, v));
   if(EdNum("QPK", v)) g_qp_k = MathMin(10.0, MathMax(0.2, v));
   string hx = "";
   color hc = clrNONE;
   if(EdText("ACCX", hx) && HexColor(hx, hc) && hc != g_acc_custom)
     {
      g_acc_custom = hc;
      g_acc_i = 5;
      ApplyTheme();
     }
   string t = "";
   for(int i = 0; i < 5; i++)
      if(EdText("CKT" + IntegerToString(i), t) && t != g_ck_txt[i])
        {
         g_ck_txt[i] = t;
         g_ck_dirty = true;
        }
   for(int k = 0; k < RM_PS_N; k++)
      if(EdText("PSN" + IntegerToString(k), t) && t != "")
         g_ps_name[k] = t;
  }

void SaveState()
  {
   SaveNum("buy", g_buy); SaveNum("ens", g_entry_src); SaveNum("enp", g_entry_px); SaveNum("en2", g_entry2);
   SaveNum("src", g_sl_src); SaveNum("slm", g_sl_manual); SaveNum("buf", g_buffer);
   SaveNum("mode", g_mode); SaveNum("pct", g_percent); SaveNum("ref", g_ref); SaveNum("fix", g_fixed);
   SaveNum("day", g_daily); SaveNum("parts", g_parts); SaveNum("sh", g_share1); SaveNum("card", g_card_no);
   SaveNum("px", g_px); SaveNum("py", g_py); SaveNum("min", g_min); SaveNum("tp", g_tp_r); SaveNum("tpx", g_tp_px);   // the Trading switch is never saved
   SaveNum("frisk", g_f_risk); SaveNum("ftgt", g_f_tgt); SaveNum("fday", g_f_day); SaveNum("fv2", g_f_v2);
   SaveNum("en3", g_entry3); SaveNum("sh2", g_share2); SaveNum("fses", g_f_ses); SaveNum("won", g_win_rule);
   SaveNum("fmk", g_f_mk); SaveNum("ftr", g_f_tr); SaveNum("fpos", g_f_pos); SaveNum("tab", g_tab);
   SaveSettings();                                                      // 2.70: panel settings, one choice for every chart
   if(g_ck_dirty)
      ChecklistSave();                       // the trailing switch: RM_TRAIL_ON (TrailSwitch)
   for(int f = 0; f <= RM_FAMILIES; f++)                                 // markets: one setting for every chart
     {
      GlobalVariableSet("RM_MK_" + (f < RM_FAMILIES ? RM_FAM_KEY[f] : "OTHER"), g_mk_allow[f] ? 1 : 0);
      GlobalVariableSet("RM_MKX_" + (f < RM_FAMILIES ? RM_FAM_KEY[f] : "OTHER"), g_mk_x[f]);
     }
   for(int s = 0; s < 3; s++)
     {
      string k = "s" + IntegerToString(s);
      SaveNum(k + "o", g_ses_on[s]); SaveNum(k + "a", g_ses_a[s]); SaveNum(k + "b", g_ses_b[s]);
     }
  }

void LoadState()
  {
   g_buy = LoadNum("buy", 1) != 0; g_entry_src = (int)LoadNum("ens", 0); g_entry_px = LoadNum("enp", 0); g_entry2 = LoadNum("en2", 0);
   g_sl_src = (int)LoadNum("src", 4); g_sl_manual = LoadNum("slm", 0); g_buffer = LoadNum("buf", InpSLBuffer);
   g_mode = (int)LoadNum("mode", InpRiskMode); g_percent = LoadNum("pct", InpRiskPercent);
   g_ref = LoadNum("ref", InpRefCapital); g_fixed = LoadNum("fix", InpFixedRisk); g_daily = LoadNum("day", InpDailyLimit);
   g_parts = (int)LoadNum("parts", InpParts); g_share1 = LoadNum("sh", InpShare1); g_card_no = (int)LoadNum("card", 0);
   g_px = (int)LoadNum("px", InpX); g_py = (int)LoadNum("py", InpY); g_min = LoadNum("min", 0) != 0;
   g_tp_r = (int)LoadNum("tp", 0); g_tp_px = LoadNum("tpx", 0);
   g_f_risk = LoadNum("frisk", 1) != 0; g_f_tgt = LoadNum("ftgt", 0) != 0; g_f_day = LoadNum("fday", 1) != 0;
   g_f_v2 = LoadNum("fv2", 0) != 0; g_entry3 = LoadNum("en3", 0); g_share2 = LoadNum("sh2", InpShare2);
   g_f_ses = LoadNum("fses", 0) != 0; g_win_rule = LoadNum("won", InpWindowOn) != 0;
   g_f_mk = LoadNum("fmk", 1) != 0; g_f_tr = LoadNum("ftr", 0) != 0; g_f_pos = LoadNum("fpos", 0) != 0;
   g_tab = (int)LoadNum("tab", 0);
   if(g_tab < 0 || g_tab > 3) g_tab = 0;
   MarketDefaults(false);
   int da[3], db[3];
   SesDefaults(da, db);
   for(int s = 0; s < 3; s++)
     {
      string k = "s" + IntegerToString(s);
      g_ses_on[s] = LoadNum(k + "o", s == 2) != 0;                   // first start: New York ticked
      g_ses_a[s] = (int)LoadNum(k + "a", da[s]);
      g_ses_b[s] = (int)LoadNum(k + "b", db[s]);
      if(g_ses_a[s] < 0 || g_ses_a[s] > 1440) g_ses_a[s] = da[s];
      if(g_ses_b[s] < 0 || g_ses_b[s] > 1440) g_ses_b[s] = db[s];
     }
   if(g_tp_r < 0 || g_tp_r > 4) g_tp_r = 0;
   if(g_parts < 1 || g_parts > 3) g_parts = 1;
   if(g_entry_src < 0 || g_entry_src > 3) g_entry_src = 0;
   if(g_sl_src < 0 || g_sl_src > 4) g_sl_src = 4;
  }

void Refresh()
  {
   Calc();
   Draw();
   SaveState();
  }

void ClampPanel()
  {
   int cw = (int)ChartGetInteger(0, CHART_WIDTH_IN_PIXELS);
   int ch = (int)ChartGetInteger(0, CHART_HEIGHT_IN_PIXELS);
   g_px = MathMax(0, MathMin(g_px, cw - Z(120)));
   g_py = MathMax(0, MathMin(g_py, ch - Z(HH)));
  }

// ---------------- events
int OnInit()
  {
   LoadSettings();                        // 2.70: panel settings (EA inputs at the first start)
   ApplySize();
   ChecklistLoad();
   PresetsLoad();
   g_card.found = false;
   LoadState();
   if(g_tp_r < DefaultTp())
      g_tp_r = DefaultTp();               // v2: orders start with a take-profit of at least 2R
   ClampPanel();
   g_scroll_orig = ChartGetInteger(0, CHART_MOUSE_SCROLL);
   g_mouse_orig = ChartGetInteger(0, CHART_EVENT_MOUSE_MOVE);
   ChartSetInteger(0, CHART_EVENT_MOUSE_MOVE, true);
   g_create_orig = ChartGetInteger(0, CHART_EVENT_OBJECT_CREATE);
   ChartSetInteger(0, CHART_EVENT_OBJECT_CREATE, true);     // to keep the panel above drawings made later
   g_wheel_orig = ChartGetInteger(0, CHART_EVENT_MOUSE_WHEEL);
   ChartSetInteger(0, CHART_EVENT_MOUSE_WHEEL, true);       // scroll the panel with the wheel
   g_qnav_orig = ChartGetInteger(0, CHART_QUICK_NAVIGATION);
   if(g_hot)
      ChartSetInteger(0, CHART_QUICK_NAVIGATION, 0);         // letters and Enter are hotkeys, not the quick navigation
   FindMarkets();
   FindCommission();
   if(g_card_no > 0)
     {
      string err = "";
      g_card = RmReadCard(InpCardsFolder, g_card_no, err);
      if(g_card.found && !CardFitsChart())
        {
         g_card.found = false;
         err = "this card is for another symbol (its levels are far from this chart's price)";
        }
      g_card_msg = g_card.found ? CardMsg() : err;
     }
   TrailRun();
   PosScan();
   NewsCheck();
   ScoreRun();
   UiDestroy();
   ObjectsDeleteAll(0, PH);               // buttons and labels of an older version: the canvas is drawn first, fields on top
   ObjectsDeleteAll(0, PB);
   Refresh();
   Print(RM_TITLE, " 2.90 on ", _Symbol, " (", MarketName(g_fam), g_mk_allow[g_fam < 0 ? RM_FAMILIES : g_fam] ? ", ticked" : ", not ticked",
         "; commission/lot ", Fmt(g_comm_lot, 2), "): v2 rules ", g_v2on ? "on" : "off", " | window ",
         g_win_rule ? SessionsText(true) : "off", v_win_in ? " (open)" : " (closed)", " | trades today ", v_hist.trades + v_book.pending_today,
         " | losing in a row ", v_hist.streak, " | idea legs ", v_book.idea_legs, " | open risk ", Fmt(v_book.open_risk, 2), " of ",
         Fmt(v_open_cap, 2), " | new order: ", v_v2_why == "" ? "allowed" : v_v2_why, " | trailing ", v_tr_state);
   g_shot = true;
   EventSetTimer(1);
   return(INIT_SUCCEEDED);
  }

void OnDeinit(const int reason)
  {
   EventKillTimer();
   TrailRelease();                         // another chart takes the trailing over at once
   Release("NOTE");
   Release("MANAGE");
   Release("JOURNAL");
   AtrFree();
   if(g_qp_atr != INVALID_HANDLE)
      IndicatorRelease(g_qp_atr);
   ChartSetInteger(0, CHART_QUICK_NAVIGATION, g_qnav_orig);
   ChartSetInteger(0, CHART_MOUSE_SCROLL, g_scroll_orig);
   ChartSetInteger(0, CHART_EVENT_MOUSE_MOVE, g_mouse_orig);
   ChartSetInteger(0, CHART_EVENT_OBJECT_CREATE, g_create_orig);
   ChartSetInteger(0, CHART_EVENT_MOUSE_WHEEL, g_wheel_orig);
   UiDestroy();
   ObjectsDeleteAll(0, "RM_");             // only this tool's objects; the user's drawings stay
   ChartRedraw();
  }

void OnTick() { TrailRun(); PartialRun(); PosScan(); }

// a deal or an order changed: read today's history again (v2 rules)
void OnTrade() { g_hist_dirty = true; g_sc_dirty = true; }

void OnTimer()
  {
   if(g_drag || g_sdrag)
      return;
   if(g_confirm && GetTickCount() - g_confirm_at > (uint)MathMax(5, InpConfirmSeconds) * 1000)
     {
      g_confirm = false;
      g_order_ok = false;
      g_order_msg = "Confirmation expired: nothing sent";
     }
   if(g_raise_at > 0 && GetTickCount() >= g_raise_at)
     {
      g_raise_at = 0;                     // no new drawing for 1.5 s: bring the panel back on top
      g_raise = true;
     }
   if(g_theme == 0)
      ApplyTheme();                                    // auto: follows the chart's background
   TrailRun();
   PartialRun();
   NoteRun();
   PosScan();
   NewsCheck();
   ScoreRun();
   Calc();
   Draw();
   if(g_shot)
     {
      g_shot = false;                     // one picture of the chart with the panel, in MQL5\Files (for support)
      int w = (int)ChartGetInteger(0, CHART_WIDTH_IN_PIXELS), h = (int)ChartGetInteger(0, CHART_HEIGHT_IN_PIXELS);
      if(w > 0 && h > 0)
         ChartScreenShot(0, "SlotRiskManager_" + _Symbol + ".png", w, h, ALIGN_RIGHT);
     }
  }

// a click on a panel button (zone "RM_P?_BTN_<name>")
void Button(const string id)
  {
   int k = StringFind(id, "_BTN_");
   if(k < 0)
      return;
   string b = StringSubstr(id, k + 5);
   ReadEdits();
   // orders: step 1 / step 2 / cancel; any other button cancels a pending confirmation
   if(b == "ORDER") { StartConfirm(); Draw(); return; }
   if(b == "CONFIRM") { DoConfirm(); Refresh(); return; }
   if(b == "CANCEL") { g_confirm = false; g_order_ok = false; g_order_msg = "Cancelled: nothing sent"; Draw(); return; }
   if(b != "MIN" && StringFind(b, "F") != 0 && StringFind(b, "TAB") != 0 && g_confirm)    // minimise / fold / tabs only change the view
     { g_confirm = false; g_order_ok = false; g_order_msg = "Confirmation cancelled (a setting changed)"; }
   if(b == "TRADE")
     {
      g_trade_on = InpTradingEnabled && !g_trade_on;
      g_order_ok = false;
      g_order_msg = g_trade_on ? "Trading ON: every order needs two confirmations" : "Trading OFF";
     }
   else if(b == "TRL") TrailSwitch();
   else if(b == "QP") QpToggle();                      // 2.90 quick place
   else if(b == "THM") { g_theme = g_dark ? 2 : 1; ApplyTheme(); }
   else if(StringFind(b, "THS") == 0) { int t = (int)StringToInteger(StringSubstr(b, 3)); if(t >= 0 && t <= 2) g_theme = t; ApplyTheme(); }
   else if(StringFind(b, "ACC") == 0) { int a = (int)StringToInteger(StringSubstr(b, 3)); if(a >= 0 && a <= 5) g_acc_i = a; ApplyTheme(); }
   else if(StringFind(b, "BSC") == 0) { g_bs_i = StringToInteger(StringSubstr(b, 3)) == 1 ? 1 : 0; ApplyTheme(); }
   else if(StringFind(b, "UFN") == 0)
     {
      int f = (int)StringToInteger(StringSubstr(b, 3));
      if(f >= 0 && f <= 4) g_font_i = f;
      ApplyFont();
      RaisePanel();                                    // the fields take the new font
     }
   else if(b == "HCON") { g_contrast = !g_contrast; ApplyTheme(); }
   else if(StringFind(b, "QPT") == 0) { int f = (int)StringToInteger(StringSubstr(b, 3)); if(f >= 0 && f <= 2) g_qp_tf = f; }
   else if(StringFind(b, "TAB") == 0)
     {
      int t = (int)StringToInteger(StringSubstr(b, 3));
      if(t >= 0 && t <= 3) { g_tab = t; g_scroll = 0; }
     }
   else if(b == "CBUY" || b == "CSELL")                // compact bar: side, open the panel, step 1 of 2
     {
      g_buy = b == "CBUY";
      StartConfirm();                                  // 2.90: confirmed in the bar itself (Confirm, then the Windows dialog)
      Draw();
      SaveState();
      return;
     }
   else if(b == "V2ON") g_v2on = !g_v2on;
   else if(b == "NWON") g_news_on = !g_news_on;
   else if(StringFind(b, "NWI") == 0) { g_news_imp = StringToInteger(StringSubstr(b, 3)) == 1 ? 1 : 0; g_news_at = 0; }
   else if(b == "CKON") g_chk_on = !g_chk_on;
   else if(StringFind(b, "CHK") == 0)
     {
      int i = (int)StringToInteger(StringSubstr(b, 3));
      if(i >= 0 && i < 5) g_ck[i] = !g_ck[i];
     }
   else if(b == "PCON") PartialSwitch();
   else if(StringFind(b, "CXL") == 0) CancelPending((ulong)StringToInteger(StringSubstr(b, 3)));
   else if(StringFind(b, "PSL") == 0) PresetApply((int)StringToInteger(StringSubstr(b, 3)));
   else if(StringFind(b, "PSS") == 0) PresetStore((int)StringToInteger(StringSubstr(b, 3)));
   else if(StringFind(b, "ZM") == 0 || StringFind(b, "WD") == 0)
     {
      int v = (int)StringToInteger(StringSubstr(b, 2));
      if(StringFind(b, "ZM") == 0 && v >= 0 && v <= 3) g_zoom_i = v;
      if(StringFind(b, "WD") == 0 && v >= 0 && v <= 2) g_width_i = v;
      ApplySize();
      ClampPanel();
      RaisePanel();                                    // canvas and fields made again at the new size
     }
   else if(StringFind(b, "LG") == 0)
     {
      g_lang = StringToInteger(StringSubstr(b, 2)) == 1 ? 1 : 0;
      ApplySize();
      RaisePanel();                                    // fields made again on the other side
      g_shot = true;
     }
   else if(b == "HOT")
     {
      g_hot = !g_hot;
      ChartSetInteger(0, CHART_QUICK_NAVIGATION, g_hot ? 0 : g_qnav_orig);
     }
   else if(b == "BOX") g_box = !g_box;
   else if(b == "PUSH") g_push = !g_push;
   else if(b == "PSHT") g_push_tr = !g_push_tr;
   else if(b == "PSHC") g_push_cl = !g_push_cl;
   else if(b == "PSHD") g_push_day = !g_push_day;
   else if(b == "PSHS") g_push_ses = !g_push_ses;
   else if(b == "PTEST")
     {
      if(!g_push) g_ps_msg = "Phone notifications are off";
      else if(!TerminalInfoInteger(TERMINAL_NOTIFICATIONS_ENABLED)) g_ps_msg = "Set your MetaQuotes ID first: Tools > Options > Notifications";
      else { Push("Test from " + RM_TITLE + " on " + _Symbol); g_ps_msg = "Test sent to your phone"; }
     }
   else if(StringFind(b, "TRM") == 0)
     {
      int m = (int)StringToInteger(StringSubstr(b, 3));
      if(m >= 0 && m <= 2) g_tr_mode = m;
     }
   else if(StringFind(b, "TRF") == 0)
     {
      int f = (int)StringToInteger(StringSubstr(b, 3));
      if(f >= 0 && f <= 2) g_tr_tf = f;
     }
   else if(b == "TRCC") g_tr_cost = !g_tr_cost;
   else if(StringFind(b, "TRS") == 0)
     {
      g_trail_scope = StringToInteger(StringSubstr(b, 3)) == 1 ? 1 : 0;
      GlobalVariableSet("RM_TRAIL_SCOPE", g_trail_scope);
     }
   else if(StringFind(b, "PTR") == 0)                   // trailing on / off for one position
     {
      ulong tk = (ulong)StringToInteger(StringSubstr(b, 3));
      if(TrailExcluded(tk)) GlobalVariableDel(TrailXKey(tk));
      else GlobalVariableSet(TrailXKey(tk), 1);
      g_trail_ok = !TrailExcluded(tk);
      g_trail_msg = "#" + IntegerToString((long)tk) + (g_trail_ok ? ": trailing on" : ": trailing off (its stop stays where it is)");
     }
   else if(StringFind(b, "TP") == 0)
     {
      g_tp_r = (int)StringToInteger(StringSubstr(b, 2));
      if(g_tp_r == 4 && g_tp_px <= 0 && v_ready)
         g_tp_px = v_tp[1];                                // the line starts at 2R
     }
   else if(b == "MIN") { g_py = g_draw_y; g_min = !g_min; }
   else if(b == "FRISK") ToggleFold(1);
   else if(b == "FTGT") ToggleFold(2);
   else if(b == "FDAY") ToggleFold(3);
   else if(b == "FV2") ToggleFold(4);
   else if(b == "FSES") ToggleFold(5);
   else if(b == "FMKT") ToggleFold(6);
   else if(b == "FTRL") ToggleFold(7);
   else if(b == "FPOS") ToggleFold(8);
   else if(StringFind(b, "MKA") == 0)
     {
      int f = (int)StringToInteger(StringSubstr(b, 3));
      if(f >= 0 && f <= RM_FAMILIES)
         g_mk_allow[f] = !g_mk_allow[f];
     }
   else if(StringFind(b, "MKO") == 0)
     {
      int f = (int)StringToInteger(StringSubstr(b, 3));
      if(f >= 0 && f < RM_FAMILIES && g_mk_sym[f] != "")
        {
         SaveState();
         SymbolSelect(g_mk_sym[f], true);                // into Market Watch, then this chart switches to it
         ChartSetSymbolPeriod(0, g_mk_sym[f], PERIOD_CURRENT);
         return;
        }
     }
   else if(b == "WIN") g_win_rule = !g_win_rule;
   else if(StringFind(b, "SES") == 0)
     {
      int s = (int)StringToInteger(StringSubstr(b, 3));
      if(s >= 0 && s < 3)
         g_ses_on[s] = !g_ses_on[s];
     }
   else if(b == "BUY") g_buy = true;
   else if(b == "SELL") g_buy = false;
   else if(b == "LOAD") LoadCard();
   else if(b == "CLR")
     {
      g_card.found = false; g_card_no = 0; g_card_msg = ""; SetEd("CARD", "");
      if(g_sl_src < 4) g_sl_src = 4;
      if(g_entry_src == 1 || g_entry_src == 2) g_entry_src = 0;
     }
   else if(StringFind(b, "EN") == 0)
     {
      g_entry_src = (int)StringToInteger(StringSubstr(b, 2));
      if(g_entry_src == 3 && g_entry_px <= 0)
        {
         g_entry_px = g_buy ? SymbolInfoDouble(_Symbol, SYMBOL_ASK) : SymbolInfoDouble(_Symbol, SYMBOL_BID);
         SetEd("ENTRY", DoubleToString(g_entry_px, _Digits));
        }
     }
   else if(StringFind(b, "SL") == 0) g_sl_src = (int)StringToInteger(StringSubstr(b, 2));
   else if(StringFind(b, "RK") == 0) g_mode = (int)StringToInteger(StringSubstr(b, 2));
   else if(b == "P1") g_parts = 1;
   else if(b == "P2") g_parts = 2;
   else if(b == "P3") g_parts = 3;
   else if(b == "RESET")
     {
      g_sl_src = 4; g_sl_manual = 0; g_entry_px = 0; g_entry2 = 0; g_entry3 = 0; g_entry_src = 0;
      g_parts = (InpParts >= 1 && InpParts <= 3) ? InpParts : 1; g_share2 = InpShare2;
      g_mode = InpRiskMode; g_percent = InpRiskPercent; g_ref = InpRefCapital; g_fixed = InpFixedRisk; g_daily = InpDailyLimit;
      g_buffer = InpSLBuffer; g_share1 = InpShare1; g_card.found = false; g_card_no = 0; g_card_msg = "";
      g_trade_on = false; g_confirm = false; g_tp_r = DefaultTp(); g_tp_px = 0; g_order_msg = "";
      g_win_rule = InpWindowOn;
      GlobalVariablesDeleteAll("RM_S_");               // panel settings back to the EA inputs
      LoadSettings();
      ApplySize();
      MarketDefaults(true);
      SesDefaults(g_ses_a, g_ses_b);
      for(int s = 0; s < 3; s++)
         g_ses_on[s] = s == 2;
      UiDestroy();
      ObjectsDeleteAll(0, "RM_");
     }
   Refresh();
  }

void OnChartEvent(const int id, const long &lparam, const double &dparam, const string &sparam)
  {
   // ---- the mouse: drag the panel by its title bar; hover; the chart does not scroll under the panel
   if(id == CHARTEVENT_MOUSE_MOVE)
     {
      int mx = (int)lparam, my = (int)dparam;
      bool down = (((int)StringToInteger(sparam)) & 1) == 1;
      int W = Z(g_pw);
      if(down && !g_was_down && !g_drag && !g_sdrag)
        {
         int tx, ty, th, sy, sh;
         bool sb = SbGeo(tx, ty, th, sy, sh);
         tx = UiFx(tx, Z(4));                            // 2.80: on the left in a right-to-left panel
         if(sb && mx >= tx - Z(6) && mx <= tx + Z(10) && my >= ty && my <= ty + th)
           {
            if(my < sy || my > sy + sh)                  // on the track: jump there
               ScrollTo((int)((double)(my - sh / 2 - ty) * (g_body_h - g_view_h) / (th - sh)));
            g_sdrag = true;
            g_sdrag_y0 = my;
            g_sdrag_s0 = g_scroll;
            ChartSetInteger(0, CHART_MOUSE_SCROLL, false);
            Draw();
           }
         bool in_head = !g_sdrag && mx >= g_px && mx <= g_px + W && my >= g_draw_y && my <= g_draw_y + Z(HT) && UiHit(mx, my) == "";
         if(in_head)
           {
            g_drag = true;
            g_py = g_draw_y;
            g_dx = mx - g_px;
            g_dy = my - g_py;
            ChartSetInteger(0, CHART_MOUSE_SCROLL, false);
           }
        }
      if(g_drag && down)
        {
         int nx = mx - g_dx, ny = my - g_dy;
         if((nx != g_px || ny != g_py) && GetTickCount() - g_last_move > 15)
           {
            g_px = nx;
            g_py = ny;
            ClampPanel();
            Draw();
            g_last_move = GetTickCount();
           }
        }
      if(g_sdrag && down)
        {
         int tx, ty, th, sy, sh;
         if(SbGeo(tx, ty, th, sy, sh) && GetTickCount() - g_last_move > 15)
           {
            ScrollTo(g_sdrag_s0 + (int)((double)(my - g_sdrag_y0) * (g_body_h - g_view_h) / (th - sh)));
            Draw();
            g_last_move = GetTickCount();
           }
        }
      if(g_sdrag && !down)
        {
         g_sdrag = false;
         Draw();
        }
      if(g_drag && !down)
        {
         g_drag = false;
         Draw();
         g_py = g_draw_y;                   // keep the place where the panel actually is
         SaveState();
         g_over = false;
         ChartSetInteger(0, CHART_MOUSE_SCROLL, g_scroll_orig);
        }
      if(!g_drag && !g_sdrag)
        {
         bool over = mx >= g_px && mx < g_px + W && my >= g_draw_y && my < g_draw_y + g_panel_h;
         if(over != g_over)
           {
            g_over = over;
            ChartSetInteger(0, CHART_MOUSE_SCROLL, over ? 0 : g_scroll_orig);
           }
         string hv = over ? UiHit(mx, my) : "";
         if(hv != g_hover)
           {
            g_hover = hv;
            UiSetTip(hv == "" ? "" : UiTipAt(mx, my));
            Draw();
           }
        }
      g_was_down = down;
      return;
     }
   if(id == CHARTEVENT_CHART_CHANGE)
     {
      ClampPanel();
      Draw();
      return;
     }
   // ---- mouse wheel over the panel: scroll its content
   if(id == CHARTEVENT_MOUSE_WHEEL)
     {
      int mx = (int)(short)lparam, my = (int)(short)(lparam >> 16);
      if(!g_min && g_body_h > g_view_h && mx >= g_px && mx < g_px + Z(g_pw) && my >= g_draw_y && my < g_draw_y + g_panel_h)
        {
         ScrollTo(g_scroll - (int)MathRound(dparam / 120.0 * Z(56)));
         Draw();
        }
      return;
     }
   // a drawing (yours, another tool's, an order line object) was made on the chart: it lies over the panel until the
   // panel is made again. Wait until the drawing stops for 1.5 s, so a tool that draws all the time does not make it flicker.
   if(id == CHARTEVENT_OBJECT_CREATE && StringFind(sparam, "RM_") != 0)
     {
      g_raise_at = GetTickCount() + 1500;
      if(g_raise_at == 0)
         g_raise_at = 1;
      return;
     }
   // ---- hotkeys (2.70): not while typing in a field
   if(id == CHARTEVENT_KEYDOWN)
     {
      HotKey((int)lparam);
      return;
     }
   if(id == CHARTEVENT_OBJECT_CLICK && StringFind(sparam, PB + "ED_") == 0)
     {
      g_editing = true;
      return;
     }
   // ---- clicks on the panel: hit-test the canvas zones (the click can be reported as a chart click and an object click)
   if(id == CHARTEVENT_CLICK || (id == CHARTEVENT_OBJECT_CLICK && sparam == UiName))
     {
      int mx = (int)lparam, my = (int)dparam;
      if(id == CHARTEVENT_CLICK)
         g_editing = OnEditField(mx, my);
      if(GetTickCount() - g_click_at < 300 && MathAbs(mx - g_click_x) <= 2 && MathAbs(my - g_click_y) <= 2)
         return;
      string hit = UiHit(mx, my);
      if(hit == "")
         return;
      g_click_at = GetTickCount();
      g_click_x = mx;
      g_click_y = my;
      Button(hit);
      // 2.51: the second report of the same click waits behind a Windows dialog (trailing, order confirmation): count the
      // 300 ms from the end of the handling, or it arrives "late" and clicks the switch again (trailing went off at once)
      g_click_at = GetTickCount();
      return;
     }
   if(id == CHARTEVENT_OBJECT_ENDEDIT && StringFind(sparam, PB + "ED_") == 0)
     {
      g_editing = false;
      if(StringFind(sparam, PB + "ED_NW") == 0)
         g_news_at = 0;                                // news window changed: read the calendar again
      if(g_confirm) { g_confirm = false; g_order_ok = false; g_order_msg = "Confirmation cancelled (a setting changed)"; }
      ReadEdits();
      if(sparam == PB + "ED_SL" && g_sl_manual > 0) g_sl_src = 4;
      if(sparam == PB + "ED_ENTRY" && g_entry_px > 0) g_entry_src = 3;
      if(sparam == PB + "ED_CARD") LoadCard();
      Refresh();
      return;
     }
   if(id == CHARTEVENT_OBJECT_DRAG)
     {
      // lines moved on the chart: the moved level becomes your value (the tool never moves it back)
      double p = NormalizeDouble(ObjectGetDouble(0, sparam, OBJPROP_PRICE), _Digits);
      if(sparam == PC + "SL") { g_sl_src = 4; g_sl_manual = p; SetEd("SL", DoubleToString(p, _Digits)); }
      else if(sparam == PC + "EN") { g_entry_src = 3; g_entry_px = p; SetEd("ENTRY", DoubleToString(p, _Digits)); }
      else if(sparam == PC + "E2") { g_entry2 = p; SetEd("E2", DoubleToString(p, _Digits)); }
      else if(sparam == PC + "E3") { g_entry3 = p; SetEd("E3", DoubleToString(p, _Digits)); }
      else if(sparam == PC + "TPL") { g_tp_px = p; g_tp_r = 4; }
      else return;
      QpSide();                                        // 2.90: stop below the entry = BUY, above = SELL
      if(g_confirm) { g_confirm = false; g_order_ok = false; g_order_msg = "Confirmation cancelled (a line was moved)"; }
      ObjectSetInteger(0, sparam, OBJPROP_SELECTED, false);
      Refresh();
     }
  }
//+------------------------------------------------------------------+
