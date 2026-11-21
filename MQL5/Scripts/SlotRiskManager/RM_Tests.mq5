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

   // 2) an index CFD (example: a US30 contract): 1.00 lot = 1 USD per point, min 0.1, step 0.1
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
   // ETHUSD: stop 40 = 40 USD per lot -> 10 / 40 = 0.25 lot
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
