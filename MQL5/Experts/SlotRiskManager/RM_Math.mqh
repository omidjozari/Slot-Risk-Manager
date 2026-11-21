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
