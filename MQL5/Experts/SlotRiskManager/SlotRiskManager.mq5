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
//+------------------------------------------------------------------+
#property copyright "Copyright 2026, OmidBibak (MIT licence)"
#property link      "https://github.com/omidjozari/Slot-Risk-Manager"
#property version   "2.10"
#property description "Risk calculator: lot size from entry, stop-loss and a fixed risk; daily loss slots."
#property description "Orders only when you allow them (EA input + panel switch) and confirm twice; otherwise calculation only."

#include "RM_Math.mqh"
#include "RM_Cards.mqh"
#include "RM_Trade.mqh"

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

input group "Risk per trade (one slot)"
input RM_RISK_MODE InpRiskMode   = RISK_REF_PERCENT; // Risk mode
input double InpRiskPercent      = 0.5;      // Risk % (reference capital or equity)
input double InpRefCapital       = 5000.0;   // Reference capital (does not grow with profits)
input double InpFixedRisk        = 10.0;     // Fixed risk per trade (deposit currency)
input group "Daily limit"
input double InpDailyLimit       = 50.0;     // Maximum loss per day (deposit currency)
input RM_DAY_COUNT InpDayCount   = DAY_LOSSES_ONLY; // What uses the daily limit
input group "Split of one trade"
input int    InpParts            = 1;        // Entries per trade (1 or 2)
input double InpShare1           = 50.0;     // Share of the first entry in % (50 = 5+5, 70 = 7+3)
input group "Stop-loss"
input double InpSLBuffer         = 5.0;      // Buffer beyond the level (points on indices, pips on forex)
input double InpMaxSpread        = 5.0;      // Warn when the spread is above (index points; indices, gold, CFDs)
input double InpMaxSpreadPips    = 2.0;      // Warn when the spread is above (pips; forex pairs)
input double InpMaxSpreadCryptoPct = 0.10;   // Warn when the spread is above (% of price; Bitcoin, Ethereum...)
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

#define PH "RM_PH_"   // panel header (always shown)
#define PB "RM_PB_"   // panel body (hidden when minimised)
#define PC "RM_C_"    // chart objects (lines, zone boxes)
#define RM_TITLE "Slot Risk Manager"
#define PW 332        // panel width (pixels at 100% Windows scale)
#define HH 30         // header height

const color C_HEAD  = C'31,35,44';
const color C_BG    = C'21,24,30';
const color C_CARD  = C'29,33,41';
const color C_EDGE  = C'52,58,70';
const color C_TXT   = C'226,230,236';
const color C_DIM   = C'135,143,158';
const color C_ON    = C'45,112,200';
const color C_OFF   = C'40,45,55';
const color C_GREEN = C'52,180,112';
const color C_BUYON = C'34,140,90';
const color C_SELON = C'190,60,60';
const color C_RED   = C'235,85,85';
const color C_AMBER = C'240,172,64';

// ---------------- state (saved per symbol in terminal global variables)
bool   g_buy = true;
int    g_entry_src = 0;          // 0 market, 1 zone edge, 2 refine edge, 3 price
double g_entry_px = 0, g_entry2 = 0;
int    g_sl_src = 4;             // 0 refine, 1 BOS leg, 2 zone, 3 liquidity, 4 manual
double g_sl_manual = 0;
double g_buffer = 5;
int    g_mode = 0;
double g_percent = 0.5, g_ref = 5000, g_fixed = 10, g_daily = 50;
int    g_parts = 1;
double g_share1 = 50;
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
// folding sections: 1 risk settings, 2 targets, 3 the day. Saved; the auto_ flags fold extra sections only while the
// panel is taller than the chart (never saved). The section opened last stays open.
bool   g_f_risk = true, g_f_tgt = false, g_f_day = true;
bool   g_a_risk = false, g_a_tgt = false, g_a_day = false;
int    g_last_open = 0;
bool   g_dry = false;            // measuring pass: compute the height, draw nothing
int    g_draw_y = 30;            // where the panel is drawn (kept inside the chart)
bool   g_cards = false;          // the engine's cards file exists on this computer

// ---------------- orders (version 2)
bool    g_trade_on = false;      // panel switch: OFF at every start, never saved
int     g_tp_r = 0;              // take-profit sent with the order: 0 none, 1..3 = R
bool    g_confirm = false;       // step 1 shown, waiting for "Confirm"
uint    g_confirm_at = 0;
RmOrder g_plan[2];
int     g_plan_n = 0;
string  g_order_msg = "";
bool    g_order_ok = false;

// ---------------- the day
struct RmDay
  {
   double used;      // part of the daily limit used by closed trades
   double net;       // net closed result today
   double open_risk; // loss if every open position hits its stop
   int    no_sl;     // open positions without a stop (risk unknown)
  };

// ---------------- results of the last calculation (shown by Draw)
double v_bid, v_ask, v_spread, v_budget, v_e1, v_e2, v_sl, v_b1, v_b2, v_total, v_lots, v_margin, v_left;
long   v_age;
string v_base, v_err;
bool   v_ready;                  // entry and stop known and on the right sides
RmSize v_s1, v_s2;
double v_tp[3], v_rw[3];
RmDay  v_day;
int    v_slots_left, v_slots_all;
string v_warn[];
double v_raw1, v_minrisk1, v_maxstop1;

// ---------------- small helpers
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
   TextSetFont(font, -size * 10);              // tenths of a point, like the labels (follows the Windows scale)
   TextGetSize(t, w, h);
   return (int)w;
  }

string FitText(const string t, const string font, const int size, const int maxw)
  {
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
   int n = StringSplit(t, ' ', w);
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

// ---------------- panel objects (screen coordinates). In the measuring pass (g_dry) nothing is drawn.
void Rect(const string n, const int x, const int y, const int w, const int h, const color bg, const color edge)
  {
   if(g_dry)
      return;
   if(ObjectFind(0, n) < 0)
      ObjectCreate(0, n, OBJ_RECTANGLE_LABEL, 0, 0, 0);
   ObjectSetInteger(0, n, OBJPROP_CORNER, CORNER_LEFT_UPPER);
   ObjectSetInteger(0, n, OBJPROP_XDISTANCE, x);
   ObjectSetInteger(0, n, OBJPROP_YDISTANCE, y);
   ObjectSetInteger(0, n, OBJPROP_XSIZE, w);
   ObjectSetInteger(0, n, OBJPROP_YSIZE, h);
   ObjectSetInteger(0, n, OBJPROP_BGCOLOR, bg);
   ObjectSetInteger(0, n, OBJPROP_BORDER_TYPE, BORDER_FLAT);
   ObjectSetInteger(0, n, OBJPROP_COLOR, edge);
   ObjectSetInteger(0, n, OBJPROP_SELECTABLE, false);
   ObjectSetInteger(0, n, OBJPROP_HIDDEN, true);
   ObjectSetString(0, n, OBJPROP_TOOLTIP, "\n");                  // no object-name tooltips
   Seen(n);
  }

void Text(const string n, const int x, const int y, const string t, const color c, const int size = 9,
          const string font = "Segoe UI", const bool right = false)
  {
   if(g_dry)
      return;
   if(ObjectFind(0, n) < 0)
      ObjectCreate(0, n, OBJ_LABEL, 0, 0, 0);
   ObjectSetInteger(0, n, OBJPROP_CORNER, CORNER_LEFT_UPPER);
   ObjectSetInteger(0, n, OBJPROP_ANCHOR, right ? ANCHOR_RIGHT_UPPER : ANCHOR_LEFT_UPPER);
   ObjectSetInteger(0, n, OBJPROP_XDISTANCE, x);
   ObjectSetInteger(0, n, OBJPROP_YDISTANCE, y);
   ObjectSetString(0, n, OBJPROP_TEXT, t == "" ? " " : t);        // an empty label would show the word "Label"
   ObjectSetString(0, n, OBJPROP_FONT, font);
   ObjectSetInteger(0, n, OBJPROP_FONTSIZE, size);
   ObjectSetInteger(0, n, OBJPROP_COLOR, c);
   ObjectSetInteger(0, n, OBJPROP_SELECTABLE, false);
   ObjectSetInteger(0, n, OBJPROP_HIDDEN, true);
   ObjectSetString(0, n, OBJPROP_TOOLTIP, "\n");
   Seen(n);
  }

void Btn(const string n, const int x, const int y, const int w, const int h, const string t, const bool on,
         const color on_color = C'45,112,200', const int size = 8, const string tip = "")
  {
   if(g_dry)
      return;
   if(ObjectFind(0, n) < 0)
      ObjectCreate(0, n, OBJ_BUTTON, 0, 0, 0);
   ObjectSetInteger(0, n, OBJPROP_CORNER, CORNER_LEFT_UPPER);
   ObjectSetInteger(0, n, OBJPROP_XDISTANCE, x);
   ObjectSetInteger(0, n, OBJPROP_YDISTANCE, y);
   ObjectSetInteger(0, n, OBJPROP_XSIZE, w);
   ObjectSetInteger(0, n, OBJPROP_YSIZE, h);
   ObjectSetString(0, n, OBJPROP_TEXT, t);
   ObjectSetString(0, n, OBJPROP_FONT, on ? "Segoe UI Semibold" : "Segoe UI");
   ObjectSetInteger(0, n, OBJPROP_FONTSIZE, size);
   ObjectSetInteger(0, n, OBJPROP_COLOR, on ? clrWhite : C_DIM);
   ObjectSetInteger(0, n, OBJPROP_BGCOLOR, on ? on_color : C_OFF);
   ObjectSetInteger(0, n, OBJPROP_BORDER_COLOR, on ? on_color : C_EDGE);
   ObjectSetInteger(0, n, OBJPROP_STATE, false);
   ObjectSetInteger(0, n, OBJPROP_SELECTABLE, false);
   ObjectSetInteger(0, n, OBJPROP_HIDDEN, true);
   ObjectSetString(0, n, OBJPROP_TOOLTIP, tip == "" ? "\n" : tip);
   Seen(n);
  }

// text of an edit box is set only when it is created (or by SetEd): the timer never overwrites what you type
void Ed(const string n, const int x, const int y, const int w, const int h, const string t, const string tip = "")
  {
   if(g_dry)
      return;
   if(ObjectFind(0, n) < 0)
     {
      ObjectCreate(0, n, OBJ_EDIT, 0, 0, 0);
      ObjectSetString(0, n, OBJPROP_TEXT, t);
     }
   ObjectSetInteger(0, n, OBJPROP_CORNER, CORNER_LEFT_UPPER);
   ObjectSetInteger(0, n, OBJPROP_XDISTANCE, x);
   ObjectSetInteger(0, n, OBJPROP_YDISTANCE, y);
   ObjectSetInteger(0, n, OBJPROP_XSIZE, w);
   ObjectSetInteger(0, n, OBJPROP_YSIZE, h);
   ObjectSetString(0, n, OBJPROP_FONT, "Consolas");
   ObjectSetInteger(0, n, OBJPROP_FONTSIZE, 9);
   ObjectSetInteger(0, n, OBJPROP_COLOR, C_TXT);
   ObjectSetInteger(0, n, OBJPROP_BGCOLOR, C_CARD);
   ObjectSetInteger(0, n, OBJPROP_BORDER_COLOR, C_EDGE);
   ObjectSetInteger(0, n, OBJPROP_ALIGN, ALIGN_RIGHT);
   ObjectSetInteger(0, n, OBJPROP_SELECTABLE, false);
   ObjectSetInteger(0, n, OBJPROP_HIDDEN, true);
   ObjectSetString(0, n, OBJPROP_TOOLTIP, tip == "" ? "\n" : tip);
   Seen(n);
  }

// a tooltip on an object drawn this time (not in the measuring pass)
void Tip(const string n, const string tip)
  {
   if(!g_dry && ObjectFind(0, n) >= 0)
      ObjectSetString(0, n, OBJPROP_TOOLTIP, tip);
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

// ---------------- chart objects
void HLine(const string n, const double p, const color c, const ENUM_LINE_STYLE st, const int width, const bool drag, const string tip)
  {
   string name = PC + n;
   if(p <= 0)
     {
      ObjectDelete(0, name);
      return;
     }
   if(ObjectFind(0, name) < 0)
      ObjectCreate(0, name, OBJ_HLINE, 0, 0, p);
   if(!(drag && ObjectGetInteger(0, name, OBJPROP_SELECTED)))
      ObjectSetDouble(0, name, OBJPROP_PRICE, p);
   ObjectSetInteger(0, name, OBJPROP_COLOR, c);
   ObjectSetInteger(0, name, OBJPROP_STYLE, st);
   ObjectSetInteger(0, name, OBJPROP_WIDTH, width);
   ObjectSetInteger(0, name, OBJPROP_SELECTABLE, drag);
   ObjectSetInteger(0, name, OBJPROP_BACK, false);
   ObjectSetString(0, name, OBJPROP_TOOLTIP, tip);
   ObjectSetString(0, name, OBJPROP_TEXT, tip);
  }

void Box(const string n, const double lo, const double hi, const color c, const bool fill, const datetime t1)
  {
   string name = PC + n;
   if(lo <= 0 || hi <= 0)
     {
      ObjectDelete(0, name);
      return;
     }
   datetime t2 = TimeCurrent() + PeriodSeconds() * 20;
   if(ObjectFind(0, name) < 0)
      ObjectCreate(0, name, OBJ_RECTANGLE, 0, t1, hi, t2, lo);
   ObjectSetInteger(0, name, OBJPROP_TIME, 0, t1);
   ObjectSetDouble(0, name, OBJPROP_PRICE, 0, hi);
   ObjectSetInteger(0, name, OBJPROP_TIME, 1, t2);
   ObjectSetDouble(0, name, OBJPROP_PRICE, 1, lo);
   ObjectSetInteger(0, name, OBJPROP_COLOR, c);
   ObjectSetInteger(0, name, OBJPROP_FILL, fill);       // only the zone is filled: overlapping fills mix colours
   ObjectSetInteger(0, name, OBJPROP_WIDTH, fill ? 1 : 2);
   ObjectSetInteger(0, name, OBJPROP_BACK, true);
   ObjectSetInteger(0, name, OBJPROP_SELECTABLE, false);
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

   string w1 = "", w2 = "";
   v_e1 = EntryPrice(w1);
   v_e2 = (g_parts == 2 && g_entry2 > 0) ? g_entry2 : v_e1;
   v_sl = StopPrice(w2);
   v_ready = false;
   v_err = "";
   v_s1.ok = false; v_s1.lot = 0; v_s1.risk = 0; v_s1.loss_per_lot = 0; v_s1.why = "";
   v_s2 = v_s1;
   v_total = 0; v_lots = 0; v_margin = 0; v_raw1 = 0; v_minrisk1 = 0; v_maxstop1 = 0;
   for(int r = 0; r < 3; r++) { v_tp[r] = 0; v_rw[r] = 0; }
   if(v_e1 <= 0) { v_err = "Entry: " + w1; return; }
   if(v_sl <= 0) { v_err = "Stop: " + w2; return; }
   if((g_buy && (v_sl >= v_e1 || v_sl >= v_e2)) || (!g_buy && (v_sl <= v_e1 || v_sl <= v_e2)))
     {
      v_err = g_buy ? "The stop must be BELOW the entry for a BUY" : "The stop must be ABOVE the entry for a SELL";
      return;
     }
   v_ready = true;
   ENUM_ORDER_TYPE ot = g_buy ? ORDER_TYPE_BUY : ORDER_TYPE_SELL;
   v_b1 = (g_parts == 2) ? v_budget * g_share1 / 100.0 : v_budget;
   v_b2 = (g_parts == 2) ? v_budget - v_b1 : 0;
   double l1 = 0, l2 = 0, pr = 0;
   if(OrderCalcProfit(ot, _Symbol, 1.0, v_e1, v_sl, pr)) l1 = -pr;
   if(g_parts == 2 && OrderCalcProfit(ot, _Symbol, 1.0, v_e2, v_sl, pr)) l2 = -pr;
   v_s1 = RmSizeFor(v_b1, l1, vmin, vmax, vstep);
   if(g_parts == 2)
      v_s2 = RmSizeFor(v_b2, l2, vmin, vmax, vstep);
   double dist = MathAbs(v_e1 - v_sl);
   if(l1 > 0)
     {
      v_raw1 = v_b1 / l1;                              // exact volume before the broker step
      v_minrisk1 = vmin * l1;                          // what the smallest volume would risk
      v_maxstop1 = dist > 0 ? v_b1 / (vmin * l1 / dist) : 0;   // widest stop the budget allows at the smallest volume
     }
   v_total = (v_s1.ok ? v_s1.risk : 0) + (v_s2.ok ? v_s2.risk : 0);
   v_lots = (v_s1.ok ? v_s1.lot : 0) + (v_s2.ok ? v_s2.lot : 0);
   if(v_lots > 0 && !OrderCalcMargin(ot, _Symbol, v_lots, v_e1, v_margin))
      v_margin = 0;
   if(v_total > v_left + 1e-6)
      Warn("More than today's remaining loss (" + Fmt(v_left, 2) + " " + Cur() + ")");
   if(v_margin > AccountInfoDouble(ACCOUNT_MARGIN_FREE))
      Warn("Not enough free margin");
   for(int r = 1; r <= 3; r++)
     {
      double tp = g_buy ? v_e1 + r * dist : v_e1 - r * dist;
      double p1 = 0, p2 = 0, rw = 0;
      if(v_s1.ok && OrderCalcProfit(ot, _Symbol, v_s1.lot, v_e1, tp, p1)) rw += p1;
      if(v_s2.ok && OrderCalcProfit(ot, _Symbol, v_s2.lot, v_e2, tp, p2)) rw += p2;
      v_tp[r - 1] = tp;
      v_rw[r - 1] = rw;
     }
  }

// ---------------- drawing
bool Folded(const int k)
  {
   if(k == 1) return g_f_risk || g_a_risk;
   if(k == 2) return g_f_tgt || g_a_tgt;
   return g_f_day || g_a_day;
  }

// fold an open section for this draw only (panel taller than the chart); false when it is folded already or opened last
bool AutoFold(const int k)
  {
   if(Folded(k) || k == g_last_open)
      return false;
   if(k == 1) g_a_risk = true;
   else if(k == 2) g_a_tgt = true;
   else g_a_day = true;
   return true;
  }

void ToggleFold(const int k)
  {
   bool opening = Folded(k);
   if(k == 1) { g_f_risk = !opening; g_a_risk = false; }
   else if(k == 2) { g_f_tgt = !opening; g_a_tgt = false; }
   else { g_f_day = !opening; g_a_day = false; }
   if(opening)
      g_last_open = k;
   else if(g_last_open == k)
      g_last_open = 0;
  }

// section title; with a fold key a small +/– button on the right, and when folded a one-line summary instead of the rule
void Section(const string n, const int L, const int R, const int y, const string t, const string key = "",
             const bool folded = false, const string summary = "", const color sc = C'135,143,158')
  {
   Text(n, L, y, t, C_DIM, 7, "Segoe UI Semibold");
   int tx = L + TextW(t, "Segoe UI Semibold", 7) + Z(8);
   int r = key == "" ? R : R - Z(26);
   if(folded && summary != "")
      Text(n + "_sum", tx, y - Z(2), FitText(summary, "Segoe UI", 8, r - tx), sc, 8);
   else
      Rect(n + "_ln", tx, y + Z(7), MathMax(1, r - tx), 1, C_EDGE, C_EDGE);
   if(key != "")
      Btn(PB + "BTN_F" + key, R - Z(18), y - Z(3), Z(18), Z(17), folded ? "+" : "–", false, C_ON, 9, folded ? "Show" : "Hide");
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

// two passes: measure (fold extra sections while the panel is taller than the chart), then draw it inside the chart
void Draw()
  {
   int ch = (int)ChartGetInteger(0, CHART_HEIGHT_IN_PIXELS);
   if(ch <= 0)
      ch = 100000;
   g_a_risk = false; g_a_tgt = false; g_a_day = false;
   g_dry = true;
   int h = Panel(g_px, 0);
   int seq[3] = {2, 3, 1};                // targets, the day, risk settings
   for(int i = 0; i < 3 && h > ch; i++)
      if(AutoFold(seq[i]))
         h = Panel(g_px, 0);
   g_dry = false;
   ArrayResize(g_seen, 0);
   g_draw_y = MathMax(0, MathMin(g_py, ch - h));
   Panel(g_px, g_draw_y);
   Sweep();
   DrawChart();
   ChartRedraw();
  }

// the panel at (x, y); returns its bottom edge
int Panel(const int x, const int y)
  {
   int W = Z(PW);
   int L = x + Z(12), R = x + W - Z(12);
   int hh = Z(HH);
   bool live = InpTradingEnabled && g_trade_on;
   // header: drag it to move the panel; "–" minimises
   Rect(PH + "bg", x, y, W, hh, C_HEAD, C_EDGE);
   Text(PH + "title", L, y + Z(6), RM_TITLE, C_TXT, 10, "Segoe UI Semibold");
   int bx = L + TextW(RM_TITLE, "Segoe UI Semibold", 10) + Z(8);
   string badge = live ? "TRADING ON" : (g_min ? "" : "CALC ONLY");
   Text(PH + "badge", bx, y + Z(10), badge, live ? C_RED : C_AMBER, 7, "Segoe UI Semibold");
   int sx = bx + (badge == "" ? 0 : TextW(badge, "Segoe UI Semibold", 7) + Z(8));
   Text(PH + "sum", R - Z(28), y + Z(7), g_min ? FitText(Summary(), "Segoe UI Semibold", 9, R - Z(28) - sx) : "",
        (v_ready && v_s1.ok) ? C_GREEN : C_DIM, 9, "Segoe UI Semibold", true);
   Btn(PH + "BTN_MIN", R - Z(22), y + Z(5), Z(22), Z(20), g_min ? "+" : "–", false, C_ON, 10, g_min ? "Open the panel" : "Minimise");
   if(g_min)
      return y + hh;

   int top = y + hh;
   Rect(PB + "bg", x, top, W, Z(100), C_BG, C_EDGE);
   int cy = top + Z(10);
   int lw = Z(50);                       // label column
   int cx = L + lw;                      // controls start
   int cw = R - cx;                      // controls width
   int rh = Z(22), st = Z(26);           // control height, row step

   // ---- side
   int hw = (R - L - Z(6)) / 2;
   Btn(PB + "BTN_BUY", L, cy, hw, Z(26), "BUY", g_buy, C_BUYON, 10);
   Btn(PB + "BTN_SELL", L + hw + Z(6), cy, hw, Z(26), "SELL", !g_buy, C_SELON, 10);
   cy += Z(32);

   // ---- engine card: only when the engine's cards file is on this computer
   bool cards = g_cards || g_card.found;
   if(cards)
     {
      Text(PB + "l_card", L, cy + Z(3), "Card #A", C_DIM, 9);
      Ed(PB + "ED_CARD", cx, cy, Z(58), rh, g_card_no > 0 ? IntegerToString(g_card_no) : "", "Engine card number, then Enter or Load");
      Btn(PB + "BTN_LOAD", cx + Z(62), cy, Z(48), rh, "Load", false, C_ON, 8, "Take the levels of this engine card");
      Btn(PB + "BTN_CLR", cx + Z(114), cy, Z(22), rh, "×", false, C_ON, 8, "Clear the card");
      cy += st;
      if(g_card_msg != "")
        {
         Text(PB + "cmsg", L, cy - Z(2), FitText(g_card_msg, "Segoe UI", 8, R - L), g_card.found ? C_GREEN : C_AMBER, 8);
         cy += Z(18);
        }
     }

   // ---- entry and stop
   Text(PB + "l_entry", L, cy + Z(3), "Entry", C_DIM, 9);
   if(cards)
     {
      string es[4] = {"Market", "Zone", "Refine", "Price"};
      string et[4] = {"Market order at the live price", "Near edge of the card's zone", "Near edge of the card's M15 refine",
                      "Your price: type it, or drag the green line"};
      int bw = (cw - Z(3) * 3) / 4;
      for(int i = 0; i < 4; i++)
         Btn(PB + "BTN_EN" + IntegerToString(i), cx + i * (bw + Z(3)), cy, bw, rh, es[i], g_entry_src == i, C_ON, 8, et[i]);
     }
   else
     {
      int bw = (cw - Z(3)) / 2;
      Btn(PB + "BTN_EN0", cx, cy, bw, rh, "Market", g_entry_src == 0, C_ON, 8, "Market order at the live price");
      Btn(PB + "BTN_EN3", cx + bw + Z(3), cy, bw, rh, "Price", g_entry_src == 3, C_ON, 8, "Your price: type it, or drag the green line");
     }
   cy += st;
   if(cards)
     {
      string ss[5] = {"Refine", "BOS leg", "Zone", "Liq.", "Manual"};
      string sst[5] = {"Beyond the far edge of the refine", "Beyond the origin of the BOS leg", "Beyond the far edge of the zone",
                       "Beyond the liquidity level", "Your stop: type it, or drag the red line"};
      Text(PB + "l_sl", L, cy + Z(3), "Stop", C_DIM, 9);
      int sw = (cw - Z(3) * 4) / 5;
      for(int i = 0; i < 5; i++)
         Btn(PB + "BTN_SL" + IntegerToString(i), cx + i * (sw + Z(3)), cy, sw, rh, ss[i], g_sl_src == i, C_ON, 8, sst[i]);
      cy += st;
     }
   int ew = (cw - Z(36)) / 2;
   Text(PB + "l_px", L, cy + Z(3), "Price", C_DIM, 9);
   Ed(PB + "ED_ENTRY", cx, cy, ew, rh, g_entry_px > 0 ? DoubleToString(g_entry_px, _Digits) : "", "Entry price (Entry switches to Price)");
   Text(PB + "l_slm", cx + ew + Z(8), cy + Z(3), "SL", C_DIM, 9);
   Ed(PB + "ED_SL", R - ew, cy, ew, rh, g_sl_manual > 0 ? DoubleToString(g_sl_manual, _Digits) : "",
      "Stop-loss price" + (cards ? " (Stop switches to Manual)" : ""));
   cy += st;
   if(g_parts == 2)
     {
      Text(PB + "l_e2", L, cy + Z(3), "2nd", C_DIM, 9);
      Ed(PB + "ED_E2", cx, cy, ew, rh, g_entry2 > 0 ? DoubleToString(g_entry2, _Digits) : "", "Second entry price (empty = same as the first)");
      Text(PB + "l_sh", cx + ew + Z(8), cy + Z(3), "1st %", C_DIM, 9);
      Ed(PB + "ED_SH", R - Z(52), cy, Z(52), rh, DoubleToString(g_share1, 0), "Share of the risk on the first entry (50 = 5+5, 70 = 7+3)");
      cy += st;
     }
   cy += Z(4);

   // ---- risk settings (folded: one line)
   string rs = g_mode == 2 ? "Fixed " + Fmt(g_fixed, 2) + " " + Cur()
               : StringFormat("%.2f%% of ", g_percent) + (g_mode == 1 ? "equity" : Fmt(g_ref, 0));
   rs += "  ·  " + (g_parts == 2 ? StringFormat("2 entries %.0f/%.0f", g_share1, 100 - g_share1) : "1 entry") + "  ·  day max " + Fmt(g_daily, 0);
   bool fr = Folded(1);
   Section(PB + "s_risk", L, R, cy, "RISK", "RISK", fr, rs, C_TXT);
   cy += Z(20);
   if(!fr)
     {
      string ms[3] = {"% of capital", "% of equity", "Fixed " + Cur()};
      string mt[3] = {"Risk % of the fixed reference capital (does not grow with profits)", "Risk % of the current equity",
                      "Fixed amount per trade"};
      int mw = (R - L - Z(3) * 2) / 3;
      for(int i = 0; i < 3; i++)
         Btn(PB + "BTN_RK" + IntegerToString(i), L + i * (mw + Z(3)), cy, mw, rh, ms[i], g_mode == i, C_ON, 8, mt[i]);
      cy += st;
      Text(PB + "l_pct", L, cy + Z(3), "Risk %", C_DIM, 9);
      Ed(PB + "ED_PCT", L + Z(44), cy, Z(50), rh, DoubleToString(g_percent, 2));
      Text(PB + "l_fix", L + Z(102), cy + Z(3), "Fixed", C_DIM, 9);
      Ed(PB + "ED_FIX", L + Z(136), cy, Z(54), rh, DoubleToString(g_fixed, 2), "Fixed risk per trade (" + Cur() + ")");
      Text(PB + "l_ref", L + Z(198), cy + Z(3), "Capital", C_DIM, 9);
      Ed(PB + "ED_REF", R - Z(64), cy, Z(64), rh, DoubleToString(g_ref, 0), "Reference capital for '% of capital' (does not grow with profits)");
      cy += st;
      Text(PB + "l_split", L, cy + Z(3), "Entries", C_DIM, 9);
      Btn(PB + "BTN_P1", L + Z(44), cy, Z(24), rh, "1", g_parts == 1, C_ON, 8, "One entry per trade");
      Btn(PB + "BTN_P2", L + Z(71), cy, Z(24), rh, "2", g_parts == 2, C_ON, 8, "Two entries per trade, sharing one slot");
      Text(PB + "l_day", L + Z(102), cy + Z(3), "Day max", C_DIM, 9);
      Ed(PB + "ED_DAY", L + Z(150), cy, Z(40), rh, DoubleToString(g_daily, 0), "Maximum loss per day (" + Cur() + ")");
      Text(PB + "l_buf", L + Z(198), cy + Z(3), "Buffer", C_DIM, 9);
      Ed(PB + "ED_BUF", R - Z(64), cy, Z(64), rh, DoubleToString(g_buffer, 1), "Stop distance beyond a card level (" + UnitName() + ")");
      cy += st;
      Btn(PB + "BTN_RESET", L, cy, Z(70), rh, "Reset all", false, C_ON, 8, "Back to the EA inputs; Trading switches OFF");
      Text(PB + "l_note", R, cy + Z(4), "Day = server midnight to midnight", C_DIM, 8, "Segoe UI", true);
      cy += st;
     }
   cy += Z(2);

   // ---- result
   int rt = cy;
   color acc = !v_ready ? C_EDGE : (v_s1.ok ? C_GREEN : C_RED);
   Rect(PB + "res", L, rt, R - L, Z(60), C_CARD, acc);
   Rect(PB + "res_acc", L, rt, Z(4), Z(60), acc, acc);
   Tip(PB + "res", "Estimates: slippage, gaps and costs come on top");
   int ix = L + Z(12), ir = R - Z(10);
   int ry = rt + Z(8);
   if(!v_ready)
     {
      Text(PB + "r_big", ix, ry, "—", C_DIM, 16, "Segoe UI Semibold");
      string ln[];
      int n = Wrap(v_err, "Segoe UI", 9, ir - ix - Z(30), 2, ln);
      for(int i = 0; i < n; i++)
         Text(PB + "r_" + IntegerToString(i + 1), ix + Z(30), ry + Z(2) + i * Z(16), ln[i], C_AMBER, 9);
      ry += Z(38);
     }
   else if(!v_s1.ok)
     {
      int tw = ir - ix;
      Text(PB + "r_big", ix, ry, "REJECTED", C_RED, 14, "Segoe UI Semibold");
      Text(PB + "r_rk", ir, ry + Z(4), "budget " + Fmt(v_b1, 2) + " " + Cur(), C_TXT, 9, "Segoe UI Semibold", true);
      ry += Z(30);
      Text(PB + "r_1", ix, ry, FitText(StringFormat("Needed %s lot  ·  %s lot would risk %s %s", DoubleToString(v_raw1, 3),
           Lot(SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MIN)), Fmt(v_minrisk1, 2), Cur()), "Segoe UI", 8, tw), C_TXT, 8);
      ry += Z(16);
      Text(PB + "r_2", ix, ry, FitText(StringFormat("Stop %s  ·  widest for this risk %s", Dist(MathAbs(v_e1 - v_sl)),
           Dist(v_maxstop1)), "Segoe UI", 8, tw), C_TXT, 8);
      ry += Z(16);
      Text(PB + "r_3", ix, ry, cards ? "Closer entry (Zone / Refine) or a nearer stop" : "A nearer stop or a closer entry", C_DIM, 8);
      ry += Z(20);
     }
   else
     {
      Text(PB + "r_big", ix, ry - Z(2), Lot(v_lots) + " lot", C_TXT, 18, "Segoe UI Semibold");
      Text(PB + "r_rk", ir, ry, "risk " + Fmt(v_total, 2) + " " + Cur(), C_GREEN, 10, "Segoe UI Semibold", true);
      Text(PB + "r_rp", ir, ry + Z(18), StringFormat("%.0f%% of the %s budget", v_budget > 0 ? 100 * v_total / v_budget : 0,
           Fmt(v_budget, 2)), C_DIM, 8, "Segoe UI", true);
      ry += Z(38);
      if(g_parts == 2)
        {
         KV(PB + "r_p1", ix, ir, ry, "1st", v_s1.ok ? Lot(v_s1.lot) + " lot @ " + Px(v_e1) + "  ·  " + Fmt(v_s1.risk, 2) : v_s1.why,
            v_s1.ok ? C_TXT : C_RED);
         ry += Z(17);
         KV(PB + "r_p2", ix, ir, ry, "2nd", v_s2.ok ? Lot(v_s2.lot) + " lot @ " + Px(v_e2) + "  ·  " + Fmt(v_s2.risk, 2) : v_s2.why,
            v_s2.ok ? C_TXT : C_RED);
         ry += Z(17);
        }
      KV(PB + "r_es", ix, ir, ry, "Entry → SL", Px(v_e1) + "  →  " + Px(v_sl) + "  (" + Dist(MathAbs(v_e1 - v_sl)) + ")", C_TXT);
      ry += Z(17);
      KV(PB + "r_mg", ix, ir, ry, "Margin", Fmt(v_margin, 2) + " " + Cur(), C_TXT);
      ry += Z(21);
     }
   if(!g_dry)
     {
      ObjectSetInteger(0, PB + "res", OBJPROP_YSIZE, ry - rt);
      ObjectSetInteger(0, PB + "res_acc", OBJPROP_YSIZE, ry - rt);
     }
   cy = ry + Z(8);

   // ---- targets (folded: one line)
   if(v_ready && v_s1.ok)
     {
      bool ft = Folded(2);
      string ts = "1R +" + Fmt(v_rw[0], 2) + "  ·  2R +" + Fmt(v_rw[1], 2) + "  ·  3R +" + Fmt(v_rw[2], 2);
      Section(PB + "s_tp", L, R, cy, "TARGETS", "TGT", ft, ts, C_GREEN);
      cy += Z(20);
      if(!ft)
        {
         for(int r = 0; r < 3; r++)
           {
            string k = PB + "tp" + IntegerToString(r);
            Text(k + "_k", L, cy, IntegerToString(r + 1) + "R", C_DIM, 9, "Segoe UI Semibold");
            Text(k + "_p", L + Z(28), cy, Px(v_tp[r]), C_TXT, 9, "Consolas");
            Text(k + "_v", R - Z(90), cy, "+" + Fmt(v_rw[r], 2), C_GREEN, 9, "Segoe UI Semibold", true);
            Text(k + "_b", R, cy, StringFormat("needs %.0f%% wins", RmBreakEvenWinRate(r + 1)), C_DIM, 8, "Segoe UI", true);
            cy += Z(17);
           }
         cy += Z(4);
        }
     }

   // ---- orders (version 2): only with the EA input on; panel switch starts OFF; two confirmations
   cy = DrawOrders(L, R, cy);

   // ---- the day (folded: one line)
   bool wide = SpreadLimit(v_bid) > 0 && v_spread > SpreadLimit(v_bid) + 1e-12;
   bool fd = Folded(3);
   string ds = "left " + Fmt(v_left, 2) + " / " + Fmt(g_daily, 0) + "  ·  slots " + IntegerToString(v_slots_left) + "/" +
               IntegerToString(v_slots_all) + "  ·  spread " + Dist(v_spread);
   color dc = v_slots_left < 1 ? C_RED : ((v_left < v_budget || wide) ? C_AMBER : C_TXT);
   Section(PB + "s_day", L, R, cy, "TODAY", "DAY", fd, ds, dc);
   cy += Z(20);
   if(!fd)
     {
      KV(PB + "k_mkt", L, R, cy, _Symbol, "Bid " + Px(v_bid) + "  ·  spread " + Dist(v_spread), wide ? C_AMBER : C_TXT);
      cy += Z(17);
      KV(PB + "k_day", L, R, cy, "Limit", "lost " + Fmt(v_day.used, 2) + "  ·  open risk " + Fmt(v_day.open_risk, 2) + "  ·  left " +
         Fmt(v_left, 2), v_left < v_budget ? C_AMBER : C_TXT);
      cy += Z(17);
      KV(PB + "k_slot", L, R, cy, "Slots", IntegerToString(v_slots_left) + " of " + IntegerToString(v_slots_all) + " left  ·  " +
         Fmt(v_budget, 2) + " " + Cur() + " each", v_slots_left > 0 ? C_GREEN : C_RED);
      cy += Z(19);
     }
   int nw = MathMin(3, ArraySize(v_warn));
   for(int i = 0; i < nw; i++)
     {
      Text(PB + "w" + IntegerToString(i), L, cy, FitText("! " + v_warn[i], "Segoe UI", 8, R - L), C_AMBER, 8);
      cy += Z(15);
     }
   cy += Z(6);
   if(!g_dry)
      ObjectSetInteger(0, PB + "bg", OBJPROP_YSIZE, cy - top);
   return cy;
  }

// delete panel objects that were not drawn this time (rows that are not needed any more)
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

void DrawChart()
  {
   bool show = v_ready;
   HLine("SL", show ? v_sl : 0, C_RED, STYLE_SOLID, 2, true, "SL  -" + Fmt(v_total, 2));
   HLine("EN", show ? v_e1 : 0, C_GREEN, STYLE_SOLID, 1, true, "Entry");
   HLine("E2", (show && g_parts == 2) ? v_e2 : 0, C_GREEN, STYLE_DASH, 1, true, "2nd entry");
   for(int r = 0; r < 3; r++)
      HLine("TP" + IntegerToString(r + 1), (show && v_s1.ok) ? v_tp[r] : 0, C_GREEN, STYLE_DOT, 1, false,
            StringFormat("TP %dR  +%.2f", r + 1, v_rw[r]));
   HLine("INV", g_card.found ? g_card.invalidation : 0, C_AMBER, STYLE_DASHDOT, 1, false,
         "Zone invalid on a " + g_card.tf + " body close beyond");
   if(g_card.found)
     {
      datetime t1 = CardTime();
      Box("ZONE", g_card.zone_low, g_card.zone_high, g_card.buy ? C'28,52,88' : C'88,48,30', true, t1);
      Box("REF", g_card.ref_low, g_card.ref_high, g_card.buy ? C'70,140,230' : C'235,140,60', false, t1);
     }
   else
     {
      ObjectDelete(0, PC + "ZONE");
      ObjectDelete(0, PC + "REF");
     }
  }

// ---------------- orders (version 2): every lock is in BuildPlan; sending only in DoConfirm after the Windows dialog
string OrderLine(const RmOrder &o)
  {
   return StringFormat("%s %s @ %s  SL %s%s", RmTypeName(o.type), Lot(o.lot), o.market ? "market" : Px(o.price), Px(o.sl),
                       o.tp > 0 ? "  TP " + Px(o.tp) : "");
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
   if(!v_s1.ok || (g_parts == 2 && !v_s2.ok)) { why = "volume rejected for this risk"; return false; }
   if(v_sl <= 0) { why = "no stop-loss"; return false; }
   if(v_slots_left < 1 || v_total > v_left + 1e-6) { why = "daily loss limit: no room for this trade today"; return false; }
   if(v_margin > AccountInfoDouble(ACCOUNT_MARGIN_FREE)) { why = "not enough free margin"; return false; }
   if(SymbolInfoInteger(_Symbol, SYMBOL_TRADE_MODE) == SYMBOL_TRADE_MODE_DISABLED) { why = "this symbol cannot be traded"; return false; }
   bool market = g_entry_src == 0;
   if(market && (v_bid <= 0 || v_age > 10)) { why = "no fresh quote for a market order"; return false; }
   if(market && SpreadLimit(v_bid) > 0 && v_spread > SpreadLimit(v_bid) + 1e-12) { why = "spread too wide for a market order"; return false; }
   if(LosingSameSide()) { why = "a position on this side is in loss: no averaging down"; return false; }
   double tp = g_tp_r > 0 ? v_tp[g_tp_r - 1] : 0;
   g_plan[0] = RmBuildOrder(_Symbol, g_buy, market, v_e1, v_sl, tp, v_s1.lot);
   g_plan_n = 1;
   if(g_parts == 2)
     {
      g_plan[1] = RmBuildOrder(_Symbol, g_buy, market && g_entry2 <= 0, v_e2, v_sl, tp, v_s2.lot);
      g_plan_n = 2;
     }
   for(int i = 0; i < g_plan_n; i++)
      if(!g_plan[i].ok)
        {
         why = (g_plan_n == 2 ? "entry " + IntegerToString(i + 1) + ": " : "") + g_plan[i].why;
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
   RmOrder before[2];
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
   int ans = MessageBox(txt, RM_TITLE + " - confirm 2 of 2", MB_YESNO | MB_ICONWARNING | MB_DEFBUTTON2);
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
      bool ok = RmSendOrder(_Symbol, g_plan[i], InpMagic, cmt + (g_plan_n == 2 ? StringFormat(" P%d", i + 1) : ""),
                            (ulong)MathMax(0, InpDeviation), m);
      all = all && ok;
      out += (i > 0 ? "  |  " : "") + (ok ? "Sent " : "FAILED ") + m;
      Print(RM_TITLE, ": ", ok ? "sent " : "failed ", m);
     }
   g_order_ok = all;
   g_order_msg = out;
  }

int DrawOrders(const int L, const int R, int cy)
  {
   if(!InpTradingEnabled)
     {
      Text(PB + "o_off", L, cy, FitText("Orders off (EA input 'Allow order buttons'): calculation only", "Segoe UI", 8, R - L), C_DIM, 8);
      return cy + Z(20);
     }
   Section(PB + "s_ord", L, R, cy, "ORDER");
   cy += Z(20);
   Btn(PB + "BTN_TRADE", L, cy, Z(96), Z(22), g_trade_on ? "Trading ON" : "Trading OFF", g_trade_on, C_SELON, 8,
       g_trade_on ? "Click to lock the order button" : "Click to allow orders (each order still needs two confirmations)");
   Text(PB + "l_tp", L + Z(104), cy + Z(3), "TP", C_DIM, 9);
   string tps[4] = {"none", "1R", "2R", "3R"};
   int tx0 = L + Z(124);
   int tw = (R - tx0 - Z(3) * 3) / 4;
   for(int i = 0; i < 4; i++)
      Btn(PB + "BTN_TP" + IntegerToString(i), tx0 + i * (tw + Z(3)), cy, tw, Z(22), tps[i], g_tp_r == i, C_ON, 8,
          i == 0 ? "Order without a take-profit" : "Take-profit at " + tps[i]);
   cy += Z(28);
   if(!g_confirm)
     {
      bool can = g_trade_on && v_ready && v_s1.ok;
      string side = g_buy ? "BUY" : "SELL";
      string act = side + (g_entry_src == 0 ? " now" : " order") + "  ·  " + Lot(v_lots) + " lot  ·  risk " + Fmt(v_total, 2);
      string t = can ? act : (g_trade_on ? "Order: set entry and stop first" : "Order button locked (Trading OFF)");
      Btn(PB + "BTN_ORDER", L, cy, R - L, Z(28), t, can, g_buy ? C_BUYON : C_SELON, 10, "Step 1 of 2: shows the order to confirm");
      cy += Z(34);
     }
   else
     {
      int secs = MathMax(0, InpConfirmSeconds - (int)((GetTickCount() - g_confirm_at) / 1000));
      int tw2 = R - L - Z(20);
      Rect(PB + "cf_bg", L, cy, R - L, Z(90), C_CARD, C_AMBER);
      Text(PB + "cf_t", L + Z(10), cy + Z(6), StringFormat("Confirm 1 of 2  ·  %d s left", secs), C_AMBER, 9, "Segoe UI Semibold");
      int yy = cy + Z(26);
      for(int i = 0; i < g_plan_n; i++)
        {
         string head = (g_plan_n == 2 ? IntegerToString(i + 1) + ")  " : "") + RmTypeName(g_plan[i].type) + "  " + Lot(g_plan[i].lot) +
                       " lot  @ " + (g_plan[i].market ? "market" : Px(g_plan[i].price));
         string stops = "SL " + Px(g_plan[i].sl) + (g_plan[i].tp > 0 ? "  ·  TP " + Px(g_plan[i].tp) : "  ·  no TP");
         Text(PB + "cf_l" + IntegerToString(i), L + Z(10), yy, FitText(head, "Segoe UI Semibold", 9, tw2), C_TXT, 9, "Segoe UI Semibold");
         yy += Z(16);
         Text(PB + "cf_s" + IntegerToString(i), L + Z(10), yy, FitText(stops, "Segoe UI", 8, tw2), C_TXT, 8);
         yy += Z(18);
        }
      Text(PB + "cf_r", L + Z(10), yy, FitText("Risk " + Fmt(v_total, 2) + " " + Cur() + "  ·  left today " + Fmt(v_left, 2),
           "Segoe UI", 8, tw2), C_DIM, 8);
      yy += Z(18);
      int bw2 = (R - L - Z(26)) / 2;
      Btn(PB + "BTN_CONFIRM", L + Z(10), yy, bw2, Z(24), "Confirm", true, g_buy ? C_BUYON : C_SELON, 9,
          "Step 2 of 2 opens a Windows dialog (default answer: No)");
      Btn(PB + "BTN_CANCEL", L + Z(16) + bw2, yy, bw2, Z(24), "Cancel", false, C_ON, 9);
      yy += Z(32);
      if(!g_dry)
         ObjectSetInteger(0, PB + "cf_bg", OBJPROP_YSIZE, yy - cy);
      cy = yy + Z(6);
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
   return cy;
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
   if(EdNum("SL", v)) g_sl_manual = MathMax(0.0, v);
   if(EdNum("BUF", v)) g_buffer = MathMax(0.0, v);
   if(EdNum("PCT", v)) g_percent = MathMin(5.0, MathMax(0.0, v));
   if(EdNum("FIX", v)) g_fixed = MathMax(0.0, v);
   if(EdNum("REF", v)) g_ref = MathMax(0.0, v);
   if(EdNum("SH", v)) g_share1 = MathMin(100.0, MathMax(0.0, v));
   if(EdNum("DAY", v)) g_daily = MathMax(0.0, v);
  }

void SaveState()
  {
   SaveNum("buy", g_buy); SaveNum("ens", g_entry_src); SaveNum("enp", g_entry_px); SaveNum("en2", g_entry2);
   SaveNum("src", g_sl_src); SaveNum("slm", g_sl_manual); SaveNum("buf", g_buffer);
   SaveNum("mode", g_mode); SaveNum("pct", g_percent); SaveNum("ref", g_ref); SaveNum("fix", g_fixed);
   SaveNum("day", g_daily); SaveNum("parts", g_parts); SaveNum("sh", g_share1); SaveNum("card", g_card_no);
   SaveNum("px", g_px); SaveNum("py", g_py); SaveNum("min", g_min); SaveNum("tp", g_tp_r);   // the Trading switch is never saved
   SaveNum("frisk", g_f_risk); SaveNum("ftgt", g_f_tgt); SaveNum("fday", g_f_day);
  }

void LoadState()
  {
   g_buy = LoadNum("buy", 1) != 0; g_entry_src = (int)LoadNum("ens", 0); g_entry_px = LoadNum("enp", 0); g_entry2 = LoadNum("en2", 0);
   g_sl_src = (int)LoadNum("src", 4); g_sl_manual = LoadNum("slm", 0); g_buffer = LoadNum("buf", InpSLBuffer);
   g_mode = (int)LoadNum("mode", InpRiskMode); g_percent = LoadNum("pct", InpRiskPercent);
   g_ref = LoadNum("ref", InpRefCapital); g_fixed = LoadNum("fix", InpFixedRisk); g_daily = LoadNum("day", InpDailyLimit);
   g_parts = (int)LoadNum("parts", InpParts); g_share1 = LoadNum("sh", InpShare1); g_card_no = (int)LoadNum("card", 0);
   g_px = (int)LoadNum("px", InpX); g_py = (int)LoadNum("py", InpY); g_min = LoadNum("min", 0) != 0;
   g_tp_r = (int)LoadNum("tp", 0);
   g_f_risk = LoadNum("frisk", 1) != 0; g_f_tgt = LoadNum("ftgt", 0) != 0; g_f_day = LoadNum("fday", 1) != 0;
   if(g_tp_r < 0 || g_tp_r > 3) g_tp_r = 0;
   if(g_parts != 2) g_parts = 1;
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
   g_s = MathMax(1.0, MathMin(3.0, TerminalInfoInteger(TERMINAL_SCREEN_DPI) / 96.0));
   g_card.found = false;
   LoadState();
   ClampPanel();
   g_scroll_orig = ChartGetInteger(0, CHART_MOUSE_SCROLL);
   g_mouse_orig = ChartGetInteger(0, CHART_EVENT_MOUSE_MOVE);
   ChartSetInteger(0, CHART_EVENT_MOUSE_MOVE, true);
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
   Refresh();
   EventSetTimer(1);
   return(INIT_SUCCEEDED);
  }

void OnDeinit(const int reason)
  {
   EventKillTimer();
   ChartSetInteger(0, CHART_MOUSE_SCROLL, g_scroll_orig);
   ChartSetInteger(0, CHART_EVENT_MOUSE_MOVE, g_mouse_orig);
   ObjectsDeleteAll(0, "RM_");             // only this tool's objects; the user's drawings stay
   ChartRedraw();
  }

void OnTick() {}

void OnTimer()
  {
   if(g_drag)
      return;
   if(g_confirm && GetTickCount() - g_confirm_at > (uint)MathMax(5, InpConfirmSeconds) * 1000)
     {
      g_confirm = false;
      g_order_ok = false;
      g_order_msg = "Confirmation expired: nothing sent";
     }
   Calc();
   Draw();
  }

void OnChartEvent(const int id, const long &lparam, const double &dparam, const string &sparam)
  {
   // ---- move the panel: press on the title bar and drag
   if(id == CHARTEVENT_MOUSE_MOVE)
     {
      int mx = (int)lparam, my = (int)dparam;
      bool down = (((int)StringToInteger(sparam)) & 1) == 1;
      int W = Z(PW);
      if(down && !g_was_down && !g_drag)
        {
         bool in_head = mx >= g_px && mx <= g_px + W - Z(40) && my >= g_draw_y && my <= g_draw_y + Z(HH);
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
      if(g_drag && !down)
        {
         g_drag = false;
         ChartSetInteger(0, CHART_MOUSE_SCROLL, g_scroll_orig);
         Draw();
         g_py = g_draw_y;                   // keep the place where the panel actually is
         SaveState();
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
   if(id == CHARTEVENT_OBJECT_CLICK && StringFind(sparam, "_BTN_") > 0)
     {
      string b = StringSubstr(sparam, StringFind(sparam, "_BTN_") + 5);
      ObjectSetInteger(0, sparam, OBJPROP_STATE, false);
      ReadEdits();
      // orders: step 1 / step 2 / cancel; any other button cancels a pending confirmation
      if(b == "ORDER") { StartConfirm(); Draw(); return; }
      if(b == "CONFIRM") { DoConfirm(); Refresh(); return; }
      if(b == "CANCEL") { g_confirm = false; g_order_ok = false; g_order_msg = "Cancelled: nothing sent"; Draw(); return; }
      if(b != "MIN" && StringFind(b, "F") != 0 && g_confirm)    // minimise / fold only change the view
        { g_confirm = false; g_order_ok = false; g_order_msg = "Confirmation cancelled (a setting changed)"; }
      if(b == "TRADE")
        {
         g_trade_on = InpTradingEnabled && !g_trade_on;
         g_order_ok = false;
         g_order_msg = g_trade_on ? "Trading ON: every order needs two confirmations" : "Trading OFF";
        }
      else if(StringFind(b, "TP") == 0) g_tp_r = (int)StringToInteger(StringSubstr(b, 2));
      else if(b == "MIN") { g_py = g_draw_y; g_min = !g_min; }
      else if(b == "FRISK") ToggleFold(1);
      else if(b == "FTGT") ToggleFold(2);
      else if(b == "FDAY") ToggleFold(3);
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
      else if(b == "RESET")
        {
         g_sl_src = 4; g_sl_manual = 0; g_entry_px = 0; g_entry2 = 0; g_entry_src = 0; g_parts = InpParts == 2 ? 2 : 1;
         g_mode = InpRiskMode; g_percent = InpRiskPercent; g_ref = InpRefCapital; g_fixed = InpFixedRisk; g_daily = InpDailyLimit;
         g_buffer = InpSLBuffer; g_share1 = InpShare1; g_card.found = false; g_card_no = 0; g_card_msg = "";
         g_trade_on = false; g_confirm = false; g_tp_r = 0; g_order_msg = "";
         ObjectsDeleteAll(0, "RM_");
        }
      Refresh();
      return;
     }
   if(id == CHARTEVENT_OBJECT_ENDEDIT && StringFind(sparam, PB + "ED_") == 0)
     {
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
      else return;
      if(g_confirm) { g_confirm = false; g_order_ok = false; g_order_msg = "Confirmation cancelled (a line was moved)"; }
      ObjectSetInteger(0, sparam, OBJPROP_SELECTED, false);
      Refresh();
     }
  }
//+------------------------------------------------------------------+
