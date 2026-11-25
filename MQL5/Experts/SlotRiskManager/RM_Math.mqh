//+------------------------------------------------------------------+
//| RM_Math.mqh - risk arithmetic of the Slot Risk Manager            |
//| Pure functions: no chart objects, no orders. The volume is always |
//| rounded DOWN to the broker step, so the estimated loss at the stop |
//| never exceeds the budget (before slippage, gaps and commission).  |
//+------------------------------------------------------------------+

// result of one sizing
struct RmSize
  {
   bool     ok;          // a volume was found
   double   lot;         // volume (broker step, rounded down)
   double   risk;        // estimated loss at the stop for that volume (deposit currency, positive)
   double   loss_per_lot;// loss at the stop for 1.00 lot
   string   why;         // reason when not ok
  };

// decimals of the volume step (0.1 -> 1, 0.01 -> 2)
int RmStepDigits(const double step)
  {
   int d = 0;
   double s = step;
   while(d < 8 && MathAbs(s - MathRound(s)) > 1e-9)
     {
      s *= 10.0;
      d++;
     }
   return d;
  }

// largest broker volume whose loss at the stop does not exceed `budget`
RmSize RmSizeFor(const double budget, const double loss_per_lot,
                 const double vmin, const double vmax, const double vstep)
  {
   RmSize r;
   r.ok = false;
   r.lot = 0.0;
   r.risk = 0.0;
   r.loss_per_lot = loss_per_lot;
   r.why = "";
   if(budget <= 0.0)
     {
      r.why = "risk budget is zero";
      return r;
     }
   if(loss_per_lot <= 0.0)
     {
      r.why = "invalid stop distance";
      return r;
     }
   if(vstep <= 0.0 || vmin <= 0.0)
     {
      r.why = "broker volume settings unavailable";
      return r;
     }
   double raw = budget / loss_per_lot;
   double lot = MathFloor(raw / vstep + 1e-9) * vstep;
   lot = NormalizeDouble(lot, RmStepDigits(vstep));
   if(vmax > 0.0 && lot > vmax)
      lot = NormalizeDouble(MathFloor(vmax / vstep + 1e-9) * vstep, RmStepDigits(vstep));
   if(lot < vmin - 1e-9)
     {
      r.why = "Trade rejected: minimum lot size exceeds the selected risk limit";
      return r;
     }
   r.ok = true;
   r.lot = lot;
   r.risk = lot * loss_per_lot;
   return r;
  }

// budget of one trade (one "slot")
// mode 0 = % of the fixed reference capital, 1 = % of equity, 2 = fixed amount
double RmBudget(const int mode, const double percent, const double ref_capital,
                const double equity, const double fixed_amount)
  {
   if(mode == 2)
      return MathMax(0.0, fixed_amount);
   double base = (mode == 1) ? equity : ref_capital;
   return MathMax(0.0, base * percent / 100.0);
  }

// break-even win rate (before costs) of a reward:risk ratio
double RmBreakEvenWinRate(const double rr)
  {
   if(rr <= 0.0)
      return 100.0;
   return 100.0 / (1.0 + rr);
  }

//+------------------------------------------------------------------+
//| v2 rules (discipline rules, 2.20) - pure helpers                 |
//+------------------------------------------------------------------+

// "16:30" -> 990 (minutes after midnight); -1 when empty or not a time
int RmHhmm(const string s)
  {
   string t = s;
   StringTrimLeft(t);
   StringTrimRight(t);
   int c = StringFind(t, ":");
   if(t == "" || c < 1)
      return -1;
   int h = (int)StringToInteger(StringSubstr(t, 0, c));
   int m = (int)StringToInteger(StringSubstr(t, c + 1));
   if(h < 0 || h > 24 || m < 0 || m > 59 || h * 60 + m > 1440)
      return -1;
   return h * 60 + m;
  }

// minute `m` of the day inside the window [start, end); a window past midnight (22:00-02:00) wraps.
// No window (a time missing, or start = end): always inside.
bool RmInWindow(const int m, const int start, const int end)
  {
   if(start < 0 || end < 0 || start == end)
      return true;
   if(start < end)
      return m >= start && m < end;
   return m >= start || m < end;
  }

// minutes from minute `m` until the window closes (inside) or opens (outside); 0 without a window
int RmMinutesToEdge(const int m, const int start, const int end)
  {
   if(start < 0 || end < 0 || start == end)
      return 0;
   int edge = RmInWindow(m, start, end) ? end : start;
   return ((edge - m) % 1440 + 1440) % 1440;
  }

// minutes from minute `m` of weekday `dow` (0 = Sunday) until the window start `ws` on the next day whose flag in
// `trades` (7 flags, Sunday first) says the symbol trades at that time: Friday evening -> Monday, not Saturday.
// Without the flags: the next start by the clock.
int RmMinutesToOpen(const int m, const int dow, const int ws, const bool &trades[])
  {
   if(ws < 0)
      return 0;
   int base = ((ws - m) % 1440 + 1440) % 1440;
   if(ArraySize(trades) < 7)
      return base;
   for(int d = 0; d < 8; d++)
     {
      int mins = base + d * 1440;
      int day = (dow + (m + mins) / 1440) % 7;
      if(trades[day])
         return mins;
     }
   return base;
  }

// 990 -> "16:30"
string RmHhmmText(const int m)
  {
   if(m < 0)
      return "";
   return StringFormat("%02d:%02d", m / 60, m % 60);
  }

// minute `m` inside at least one ticked session (a session may run past midnight; one without times is ignored)
bool RmInSessions(const int m, const int &from[], const int &to[], const bool &on[])
  {
   int n = MathMin(ArraySize(on), MathMin(ArraySize(from), ArraySize(to)));
   for(int s = 0; s < n; s++)
      if(on[s] && from[s] >= 0 && to[s] >= 0 && from[s] != to[s] && RmInWindow(m, from[s], to[s]))
         return true;
   return false;
  }

// minutes until the ticked sessions close; sessions that overlap or touch count as one window
// (London 10:00-18:30 + New York 16:30-21:00 at 12:00 -> 540, i.e. 21:00). 0 when minute `m` is in none of them.
int RmMinutesToClose(const int m, const int &from[], const int &to[], const bool &on[])
  {
   int n = MathMin(ArraySize(on), MathMin(ArraySize(from), ArraySize(to)));
   int total = 0, cur = m;
   for(int it = 0; it <= 4 * n; it++)
     {
      int ext = 0;
      for(int s = 0; s < n; s++)
        {
         if(!on[s] || from[s] < 0 || to[s] < 0 || from[s] == to[s] || !RmInWindow(cur % 1440, from[s], to[s]))
            continue;
         int e = RmMinutesToEdge(cur % 1440, from[s], to[s]);
         if(e > ext)
            ext = e;
        }
      if(ext <= 0)
         break;
      total += ext;
      cur += ext;
      if(total >= 7 * 1440)
         break;
     }
   return total;
  }

// ---------------- markets the tool knows by name, whatever the broker calls them
// (YM_l, US30.cash, DJ30, WS30m / XAUUSD.r, GOLD / BTCUSD_l, XBTUSD / ETHUSD / EURUSD.m / GBPUSDpro ...)
#define RM_FAMILIES 6
string RM_FAM_KEY[RM_FAMILIES]  = {"US30", "XAUUSD", "BTCUSD", "ETHUSD", "EURUSD", "GBPUSD"};
string RM_FAM_NAME[RM_FAMILIES] = {"Dow Jones", "Gold", "Bitcoin", "Ethereum", "EUR/USD", "GBP/USD"};

// letters and digits only, upper case ("US30.cash" -> "US30CASH")
string RmAlnum(const string s)
  {
   string u = s, out = "";
   StringToUpper(u);
   int n = StringLen(u);
   for(int i = 0; i < n; i++)
     {
      ushort c = StringGetCharacter(u, i);
      if((c >= 'A' && c <= 'Z') || (c >= '0' && c <= '9'))
         out += ShortToString(c);
     }
   return out;
  }

// family of a symbol from its name (and description): 0 Dow Jones, 1 gold, 2 Bitcoin, 3 Ethereum, 4 EURUSD, 5 GBPUSD;
// -1 for any other symbol
int RmFamily(const string name, const string desc)
  {
   string n = RmAlnum(name), d = desc;
   StringToUpper(d);
   if(StringFind(n, "XAUUSD") >= 0 || (StringFind(n, "GOLD") == 0 && StringFind(n, "GOLDMAN") < 0))
      return 1;
   if(StringFind(n, "BTCUSD") >= 0 || StringFind(n, "XBTUSD") >= 0)
      return 2;
   if(StringFind(n, "ETHUSD") >= 0)
      return 3;
   if(StringFind(n, "EURUSD") >= 0)
      return 4;
   if(StringFind(n, "GBPUSD") >= 0)
      return 5;
   if(StringFind(n, "US30") >= 0 || StringFind(n, "DJ30") >= 0 || StringFind(n, "WS30") >= 0 || StringFind(n, "USA30") >= 0 ||
      StringFind(n, "DJI") == 0 || StringFind(n, "DOWJONES") >= 0 || (StringFind(n, "YM") == 0 && StringLen(n) <= 6) ||
      StringFind(d, "DOW JONES INDUSTRIAL") >= 0 || StringFind(d, "DJIA") >= 0)
      return 0;
   return -1;
  }

// value of `key` in a list like "US30=8,BTCUSD=5" (spaces and case do not matter); `def` when the key is not there
double RmListValue(const string list, const string key, const double def)
  {
   string l = list, k = key;
   StringToUpper(l);
   StringToUpper(k);
   StringReplace(l, " ", "");
   string p[];
   int n = StringSplit(l, ',', p);
   for(int i = 0; i < n; i++)
     {
      int e = StringFind(p[i], "=");
      if(e > 0 && StringSubstr(p[i], 0, e) == k)
         return StringToDouble(StringSubstr(p[i], e + 1));
     }
   return def;
  }

// budget of a new order: the slot budget, but never more than the room left under the idea cap and the open-risk cap
// (a room < 0 means that cap is off)
double RmCapBudget(const double slot, const double idea_room, const double open_room)
  {
   double b = MathMax(0.0, slot);
   if(idea_room >= 0.0)
      b = MathMin(b, idea_room);
   if(open_room >= 0.0)
      b = MathMin(b, open_room);
   return MathMax(0.0, b);
  }

// symbol allowed by a comma list of prefixes ("YM" allows YM_l); an empty list allows every symbol
bool RmSymbolAllowed(const string sym, const string list)
  {
   string l = list;
   StringTrimLeft(l);
   StringTrimRight(l);
   if(l == "")
      return true;
   string s = sym;
   StringToUpper(s);
   string p[];
   int n = StringSplit(l, ',', p);
   for(int i = 0; i < n; i++)
     {
      string t = p[i];
      StringTrimLeft(t);
      StringTrimRight(t);
      StringToUpper(t);
      if(t != "" && StringFind(s, t) == 0)
         return true;
     }
   return false;
  }

// losing IDEAS in a row, counted back from the newest. Closed positions of one symbol and side whose open periods
// overlap are one idea (a ladder stopped out at its shared stop is one loss, not three). One row per closed position;
// an idea's result is the sum of its legs and its close is the last leg's close.
int RmIdeaLossStreak(const string &sym[], const bool &buy[], const long &t_in[], const long &t_out[], const double &net[])
  {
   int n = ArraySize(net);
   if(n == 0 || ArraySize(sym) < n || ArraySize(buy) < n || ArraySize(t_in) < n || ArraySize(t_out) < n)
      return 0;
   int ord[];
   ArrayResize(ord, n);
   for(int i = 0; i < n; i++)
      ord[i] = i;
   for(int i = 1; i < n; i++)                    // by open time (insertion sort: a day has few trades)
     {
      int k = ord[i], j = i - 1;
      while(j >= 0 && t_in[ord[j]] > t_in[k])
        {
         ord[j + 1] = ord[j];
         j--;
        }
      ord[j + 1] = k;
     }
   int cl[];
   ArrayResize(cl, n);
   string key[];
   int kid[];
   long klast[];
   int nid = 0;
   for(int q = 0; q < n; q++)
     {
      int i = ord[q];
      string k = sym[i] + (buy[i] ? "|B" : "|S");
      int f = -1;
      for(int j = 0; j < ArraySize(key); j++)
         if(key[j] == k) { f = j; break; }
      if(f >= 0 && t_in[i] <= klast[f])
        {
         cl[i] = kid[f];                         // opened while the idea was still open: same idea
         if(t_out[i] > klast[f])
            klast[f] = t_out[i];
         continue;
        }
      if(f < 0)
        {
         f = ArraySize(key);
         ArrayResize(key, f + 1);
         ArrayResize(kid, f + 1);
         ArrayResize(klast, f + 1);
         key[f] = k;
        }
      kid[f] = nid++;
      klast[f] = t_out[i];
      cl[i] = kid[f];
     }
   double res[];
   long fin[];
   bool used[];
   ArrayResize(res, nid);
   ArrayResize(fin, nid);
   ArrayResize(used, nid);
   for(int c = 0; c < nid; c++) { res[c] = 0.0; fin[c] = 0; used[c] = false; }
   for(int i = 0; i < n; i++)
     {
      res[cl[i]] += net[i];
      if(t_out[i] > fin[cl[i]])
         fin[cl[i]] = t_out[i];
     }
   int streak = 0;
   for(int c = 0; c < nid; c++)                  // newest idea first, until one that did not lose
     {
      int best = -1;
      for(int j = 0; j < nid; j++)
         if(!used[j] && (best < 0 || fin[j] > fin[best]))
            best = j;
      used[best] = true;
      if(res[best] < 0.0)
         streak++;
      else
         break;
     }
   return streak;
  }

// ---------------- trailing (2.50): the ladder of the stop and the take-profit, in R
// R = distance from the entry to the FIRST stop of the position. `gain_r` = how far the closing price has moved in
// profit, in R. Steps: start, start + step, start + 2 x step, ... The step reached is the highest one at or under
// gain_r (-1 = none yet).
double RmTrailStep(const double gain_r, const double start, const double step)
  {
   if(start <= 0 || gain_r < start - 1e-9)
      return -1;
   if(step <= 0)
      return start;
   return start + MathFloor((gain_r - start) / step + 1e-9) * step;
  }

// stop and take-profit wanted at step `n` (prices). Stop = n - lag R from the entry; when that is at or beyond the
// entry, `cost` (price distance of the commission) is added so the stop is truly free of risk. Take-profit = n + lead R
// (0 when lead is 0: the take-profit is not moved).
void RmTrailTargets(const bool buy, const double entry, const double r, const double n, const double lag, const double lead,
                    const double cost, double &sl, double &tp)
  {
   double d = buy ? 1.0 : -1.0;
   double k = n - lag;
   sl = entry + d * k * r + (k >= -1e-9 ? d * MathMax(0.0, cost) : 0.0);
   tp = lead > 0 ? entry + d * (n + lead) * r : 0.0;
  }

// true when `want` is a move of the stop in the profit direction (never back, never removed)
bool RmStopForward(const bool buy, const double cur, const double want, const double tick)
  {
   if(cur <= 0 || want <= 0)
      return false;
   return buy ? want > cur + tick / 2 : want < cur - tick / 2;
  }

// true when `want` moves the take-profit further from the entry (a position without a take-profit keeps none)
bool RmTpFurther(const bool buy, const double cur, const double want, const double tick)
  {
   if(cur <= 0 || want <= 0)
      return false;
   return buy ? want > cur + tick / 2 : want < cur - tick / 2;
  }
//+------------------------------------------------------------------+
