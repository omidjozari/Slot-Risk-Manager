//+------------------------------------------------------------------+
//| RM_Tests.mq5 - checks of the Slot Risk Manager arithmetic         |
//| Script: drag it onto any chart (a demo account is enough).        |
//| It only calculates and prints to the Experts tab; it has no       |
//| trading code.                                                     |
//+------------------------------------------------------------------+
#property copyright "Copyright 2026, OmidBibak (MIT licence)"
#property version   "1.00"
#property script_show_inputs

#include "..\..\Experts\SlotRiskManager\RM_Math.mqh"

int g_fail = 0, g_pass = 0;

void Check(const bool ok, const string what)
  {
   if(ok) { g_pass++; Print("ok    ", what); }
   else   { g_fail++; Print("FAIL  ", what); }
  }

bool Near(const double a, const double b) { return MathAbs(a - b) < 1e-6; }

void OnStart()
  {
   // 1) budget: 0.5% of the fixed 5,000 capital, not of a grown equity
   Check(Near(RmBudget(0, 0.5, 5000, 5500, 10), 25.0), "0.5% of reference 5,000 = 25 even with equity 5,500");
   Check(Near(RmBudget(1, 0.5, 5000, 5500, 10), 27.5), "0.5% of equity 5,500 = 27.5 (equity mode)");
   Check(Near(RmBudget(2, 0.5, 5000, 5500, 10), 10.0), "fixed risk 10");

   // 2) an index CFD (example broker: US30): 1.00 lot = 1 USD per point, min 0.1, step 0.1
   RmSize s = RmSizeFor(10.0, 40.0, 0.1, 100, 0.1);       // 10 USD, stop 40 pts
   Check(s.ok && Near(s.lot, 0.2) && Near(s.risk, 8.0), "10 USD / 40 pts -> 0.2 lot, 8 USD (rounded down, never up)");
   s = RmSizeFor(5.0, 50.0, 0.1, 100, 0.1);
   Check(s.ok && Near(s.lot, 0.1) && Near(s.risk, 5.0), "5 USD / 50 pts -> 0.1 lot, 5 USD");
   s = RmSizeFor(3.0, 40.0, 0.1, 100, 0.1);
   Check(!s.ok && StringFind(s.why, "minimum lot") >= 0, "3 USD / 40 pts -> rejected (min lot 0.1 = 4 USD)");
   s = RmSizeFor(25.0, 120.0, 0.1, 100, 0.1);
   Check(s.ok && Near(s.lot, 0.2) && Near(s.risk, 24.0), "25 USD / 120 pts -> 0.2 lot, 24 USD");

   // EURUSD (standard contract): 1.00 lot = 10 USD per pip, min 0.01, step 0.01; stop 20 pips = 200 USD per lot
   s = RmSizeFor(10.0, 200.0, 0.01, 100, 0.01);
   Check(s.ok && Near(s.lot, 0.05) && Near(s.risk, 10.0), "EURUSD 10 USD / 20 pips -> 0.05 lot, 10 USD");
   RmSize fx7 = RmSizeFor(7.0, 200.0, 0.01, 100, 0.01), fx3 = RmSizeFor(3.0, 200.0, 0.01, 100, 0.01);
   Check(fx7.ok && fx3.ok && Near(fx7.lot, 0.03) && Near(fx3.lot, 0.01), "EURUSD split 7+3, 20 pips -> 0.03 + 0.01 lot");

   // BTCUSD (example broker): 1.00 lot = 1 BTC = 1 USD per 1.00 move, min 0.01, step 0.01; stop 600 = 600 USD per lot
   s = RmSizeFor(10.0, 600.0, 0.01, 100, 0.01);
   Check(s.ok && Near(s.lot, 0.01) && Near(s.risk, 6.0), "BTCUSD 10 USD / 600 pts -> 0.01 lot, 6 USD");
   s = RmSizeFor(10.0, 1200.0, 0.01, 100, 0.01);
   Check(!s.ok, "BTCUSD 10 USD / 1,200 pts -> rejected (0.01 lot = 12 USD)");
   // ETHUSD_l: stop 40 = 40 USD per lot -> 10 / 40 = 0.25 lot
   s = RmSizeFor(10.0, 40.0, 0.01, 100, 0.01);
   Check(s.ok && Near(s.lot, 0.25) && Near(s.risk, 10.0), "ETHUSD 10 USD / 40 pts -> 0.25 lot, 10 USD");

   // 3) other brokers: unusual step and the maximum volume
   s = RmSizeFor(25.0, 37.0, 0.01, 100, 0.01);
   Check(s.ok && Near(s.lot, 0.67) && s.risk <= 25.0, "step 0.01: 25 / 37 -> 0.67 lot");
   s = RmSizeFor(1000.0, 1.0, 0.1, 50, 0.1);
   Check(s.ok && Near(s.lot, 50.0), "capped at the broker maximum volume");
   s = RmSizeFor(10.0, 0.0, 0.1, 100, 0.1);
   Check(!s.ok, "zero stop distance is rejected");

   // 4) the loss at the stop never exceeds the budget (many random cases)
   MathSrand(7);
   bool all = true;
   for(int i = 0; i < 5000; i++)
     {
      double budget = 1 + MathRand() % 200;
      double lpl = 0.5 + (MathRand() % 5000) / 10.0;
      RmSize r = RmSizeFor(budget, lpl, 0.1, 100, 0.1);
      if(r.ok && r.risk > budget + 1e-9) all = false;
     }
   Check(all, "5,000 random cases: estimated loss <= budget");

   // 5) split 7 + 3 of a 10 USD slot, stop 30 pts: 0.2 lot (6 USD) + 0.1 lot (3 USD) = 9 <= 10
   RmSize a = RmSizeFor(7.0, 30.0, 0.1, 100, 0.1), b = RmSizeFor(3.0, 30.0, 0.1, 100, 0.1);
   Check(a.ok && b.ok && Near(a.lot, 0.2) && Near(b.lot, 0.1) && a.risk + b.risk <= 10.0, "split 7+3, 30 pts -> 0.2 + 0.1 lot");
   Check(Near(RmBreakEvenWinRate(2.0), 100.0 / 3.0), "break-even win rate at 2R = 33%");

   // 7) v2 rules (discipline rules, 2.20)
   Check(RmHhmm("16:30") == 990 && RmHhmm("21:00") == 1260 && RmHhmm("") == -1 && RmHhmm("x") == -1, "window times parse");
   Check(RmInWindow(990, 990, 1260) && RmInWindow(1259, 990, 1260) && !RmInWindow(1260, 990, 1260) && !RmInWindow(989, 990, 1260),
         "window 16:30-21:00: open from 16:30, closed from 21:00");
   Check(RmInWindow(30, 1320, 120) && !RmInWindow(600, 1320, 120) && RmInWindow(600, -1, 1260), "window past midnight; no window");
   Check(RmMinutesToEdge(1200, 990, 1260) == 60 && RmMinutesToEdge(960, 990, 1260) == 30 && RmMinutesToEdge(1300, 990, 1260) == 1130,
         "minutes until the window closes / opens");
   bool wk[7] = {false, true, true, true, true, true, false};           // an index: Monday to Friday
   bool all7[7] = {true, true, true, true, true, true, true};           // crypto: every day
   Check(RmMinutesToOpen(104, 0, 990, wk) == 2326 && RmMinutesToOpen(1290, 5, 990, wk) == 4020 &&
         RmMinutesToOpen(600, 3, 990, wk) == 390 && RmMinutesToOpen(104, 0, 990, all7) == 886,
         "window opens: Sunday 01:44 -> Monday 16:30, Friday 21:30 -> Monday, crypto -> Sunday 16:30");
   int    sa[3] = {120, 600, 990}, sb[3] = {660, 1110, 1260};                // Asia, London, New York (server time)
   bool   so[3] = {false, true, true};                                          // London + New York ticked
   Check(RmInSessions(720, sa, sb, so) && RmInSessions(1200, sa, sb, so) && !RmInSessions(300, sa, sb, so) &&
         !RmInSessions(1300, sa, sb, so), "sessions London + New York: in at 12:00 and 20:00, out at 05:00 and 21:40");
   Check(RmMinutesToClose(720, sa, sb, so) == 540 && RmMinutesToClose(1200, sa, sb, so) == 60 && RmMinutesToClose(300, sa, sb, so) == 0,
         "overlapping London + New York close together at 21:00");
   so[0] = true; so[1] = false;
   Check(RmMinutesToClose(300, sa, sb, so) == 360 && !RmInSessions(720, sa, sb, so) && RmHhmmText(990) == "16:30",
         "Asia only: 05:00 -> closes in 6 h; time text");
   // markets recognised whatever the broker calls them
   Check(RmFamily("YM_l", "") == 0 && RmFamily("US30.cash", "") == 0 && RmFamily("DJ30", "") == 0 && RmFamily("WS30m", "") == 0 &&
         RmFamily("XAUUSD_l", "") == 1 && RmFamily("GOLD", "") == 1 && RmFamily("BTCUSD_l", "") == 2 && RmFamily("XBTUSD", "") == 2 &&
         RmFamily("ETHUSD_l", "") == 3 && RmFamily("EURUSD.m", "") == 4 && RmFamily("GBPUSD_l", "") == 5,
         "markets: Dow Jones, gold, Bitcoin, Ethereum, EURUSD, GBPUSD under broker names");
   Check(RmFamily("XAUPUSD_l", "Perpetual Gold Contract") == -1 && RmFamily("BCHUSD_l", "Bitcoin Cash") == -1 &&
         RmFamily("#GS_l", "Goldman Sachs Group Inc") == -1 && RmFamily("#GFI_l", "Gold Fields Ltd") == -1 && RmFamily("USTEC", "") == -1,
         "other symbols are not taken for one of the six markets");
   Check(Near(RmListValue("US30=8, btcusd=5,OTHER=0", "BTCUSD", 8), 5) && Near(RmListValue("US30=8,BTCUSD=5,OTHER=0", "OTHER", 8), 0) &&
         Near(RmListValue("US30=8,BTCUSD=5", "EURUSD", 8), 8), "stop / spread multiplier per market from the input list");
   Check(Near(RmCapBudget(25, 53.5, 107), 25) && Near(RmCapBudget(25, 10, 107), 10) && Near(RmCapBudget(25, 53.5, 4), 4) &&
         Near(RmCapBudget(25, -1, -1), 25) && Near(RmCapBudget(25, 0, 50), 0), "budget capped by the idea / open-risk room");
   Check(RmSymbolAllowed("YM_l", "YM") && !RmSymbolAllowed("BTCUSD_l", "YM") && RmSymbolAllowed("EURUSD_l", "") &&
         RmSymbolAllowed("ym_l", " XAU , YM "), "symbol list");
   // a 3-leg sell ladder stopped out at its shared stop is ONE loss; one more losing buy makes 2 in a row
   string s1[] = {"YM_l", "YM_l", "YM_l", "YM_l"};
   bool   b1[] = {false, false, false, true};
   long   i1[] = {1000, 1100, 1200, 2000};
   long   o1[] = {1500, 1500, 1500, 2500};
   double n1[] = {-10.0, -8.0, -6.0, -12.0};
   Check(RmIdeaLossStreak(s1, b1, i1, o1, n1) == 2, "3 legs stopped together + 1 losing trade = 2 losses in a row");
   n1[3] = 5.0;
   Check(RmIdeaLossStreak(s1, b1, i1, o1, n1) == 0, "a winning trade after the losses: streak 0");
   string s2[] = {"YM_l", "YM_l"};
   bool   b2[] = {true, true};
   long   i2[] = {1000, 3000};
   long   o2[] = {2000, 4000};
   double n2[] = {-5.0, -5.0};
   Check(RmIdeaLossStreak(s2, b2, i2, o2, n2) == 2, "two separate losing buys = 2 in a row");
   o2[0] = 3500; n2[0] = 15.0;
   Check(RmIdeaLossStreak(s2, b2, i2, o2, n2) == 0, "overlapping legs are one idea: -5 + 15 = a win");

   // 2.50) trailing ladder: start 2R, step 1R, stop 2R behind, take-profit 2R ahead
   Check(RmTrailStep(1.9, 2, 1) < 0 && Near(RmTrailStep(2.0, 2, 1), 2) && Near(RmTrailStep(3.4, 2, 1), 3) &&
         Near(RmTrailStep(5.0, 2, 1), 5), "trail steps: 1.9R none, 2R -> 2, 3.4R -> 3, 5R -> 5");
   double tsl = 0, ttp = 0;
   RmTrailTargets(true, 100, 10, 2, 2, 2, 0, tsl, ttp);
   Check(Near(tsl, 100) && Near(ttp, 140), "buy 100, R 10, at 2R: stop at the entry, TP 4R (140)");
   RmTrailTargets(true, 100, 10, 3, 2, 2, 0, tsl, ttp);
   Check(Near(tsl, 110) && Near(ttp, 150), "buy at 3R: stop +1R (110), TP 5R (150)");
   RmTrailTargets(false, 100, 10, 3, 2, 2, 0, tsl, ttp);
   Check(Near(tsl, 90) && Near(ttp, 50), "sell at 3R: stop 90, TP 50");
   RmTrailTargets(true, 100, 10, 2, 2, 0, 0.5, tsl, ttp);
   Check(Near(tsl, 100.5) && Near(ttp, 0), "risk-free stop covers the commission (+0.5); lead 0 = TP not moved");
   Check(RmStopForward(true, 100, 110, 0.01) && !RmStopForward(true, 100, 95, 0.01) && !RmStopForward(false, 100, 105, 0.01) &&
         !RmStopForward(true, 0, 110, 0.01) && !RmStopForward(true, 100, 0, 0.01), "the stop only moves forward, never removed");
   Check(RmTpFurther(true, 140, 150, 0.01) && !RmTpFurther(true, 140, 130, 0.01) && !RmTpFurther(true, 0, 150, 0.01) &&
         RmTpFurther(false, 60, 50, 0.01), "the take-profit only moves further; none stays none");

   // 6) the real symbol of this chart: loss of 1.00 lot over 40 points, from the terminal (calculation only)
   double ask = SymbolInfoDouble(_Symbol, SYMBOL_ASK), pr = 0;
   if(ask > 0 && OrderCalcProfit(ORDER_TYPE_BUY, _Symbol, 1.0, ask, ask - 40.0, pr))
      Print("info  ", _Symbol, ": 1.00 lot over 40 points = ", DoubleToString(-pr, 2), " ", AccountInfoString(ACCOUNT_CURRENCY),
            " | min ", SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MIN), " step ", SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_STEP));
   else
      Print("info  no quote for ", _Symbol, " (market closed?) - symbol check skipped");
   Print(StringFormat("RM tests: %d passed, %d failed", g_pass, g_fail));
  }
//+------------------------------------------------------------------+
