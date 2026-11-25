//+------------------------------------------------------------------+
//| RM_Trade.mqh - the ONLY file of the risk tool that can place an   |
//| order (version 2, 22 Nov 2026, at the user's request).            |
//|                                                                   |
//| Rules kept here (checked by tests/test_risk_tool.py):             |
//|  - only NEW orders: a market order or a pending order, nothing    |
//|    else; existing orders and positions are never modified,        |
//|    closed or deleted                                              |
//|  - every order carries a stop-loss; no stop = no order            |
//|  - the caller (SlotRiskManager.mq5) sends only after the trader   |
//|    enabled trading twice (EA input + panel switch) and confirmed  |
//|    twice (panel + Windows dialog), within the daily loss limit    |
//|    and the v2 rules                                               |
//|  - 2.20: a pending order may carry an expiry (end of the v2      |
//|    trading window) when the broker allows it; otherwise GTC      |
//+------------------------------------------------------------------+

// one planned order
struct RmOrder
  {
   bool     ok;
   bool     market;
   ENUM_ORDER_TYPE type;
   double   price;      // market: the price at the time of the check; pending: the order price
   double   sl;
   double   tp;         // 0 = no take-profit
   double   lot;
   datetime expire;     // pending orders: expiry time (0 = good till cancelled)
   string   why;        // reason when not ok
  };

string RmTypeName(const ENUM_ORDER_TYPE t)
  {
   switch(t)
     {
      case ORDER_TYPE_BUY:        return "BUY";
      case ORDER_TYPE_SELL:       return "SELL";
      case ORDER_TYPE_BUY_LIMIT:  return "BUY LIMIT";
      case ORDER_TYPE_SELL_LIMIT: return "SELL LIMIT";
      case ORDER_TYPE_BUY_STOP:   return "BUY STOP";
      case ORDER_TYPE_SELL_STOP:  return "SELL STOP";
      default:                    return "?";
     }
  }

// the broker accepts an expiry time on pending orders of this symbol
bool RmCanExpire(const string sym)
  {
   return (SymbolInfoInteger(sym, SYMBOL_EXPIRATION_MODE) & SYMBOL_EXPIRATION_SPECIFIED) == SYMBOL_EXPIRATION_SPECIFIED;
  }

double RmTickRound(const string sym, const double p)
  {
   double ts = SymbolInfoDouble(sym, SYMBOL_TRADE_TICK_SIZE);
   int dg = (int)SymbolInfoInteger(sym, SYMBOL_DIGITS);
   if(ts <= 0)
      return NormalizeDouble(p, dg);
   return NormalizeDouble(MathRound(p / ts) * ts, dg);
  }

// market order at the live price, or a pending order at `entry` (limit when the entry is better than the live price,
// stop when it is worse). The stop must be on the losing side and at least the broker's stop level away.
RmOrder RmBuildOrder(const string sym, const bool buy, const bool market, const double entry, const double sl,
                     const double tp, const double lot, const datetime expire = 0)
  {
   RmOrder o;
   o.ok = false; o.market = market; o.type = buy ? ORDER_TYPE_BUY : ORDER_TYPE_SELL;
   o.price = 0; o.sl = 0; o.tp = 0; o.lot = lot; o.why = ""; o.expire = 0;
   double bid = SymbolInfoDouble(sym, SYMBOL_BID), ask = SymbolInfoDouble(sym, SYMBOL_ASK);
   double pt = SymbolInfoDouble(sym, SYMBOL_POINT);
   double lvl = (double)SymbolInfoInteger(sym, SYMBOL_TRADE_STOPS_LEVEL) * pt;
   if(bid <= 0 || ask <= 0)
     {
      o.why = "no live price";
      return o;
     }
   if(lot <= 0)
     {
      o.why = "no volume";
      return o;
     }
   if(sl <= 0)
     {
      o.why = "RM_NO_SL: an order without a stop-loss is never sent";
      return o;
     }
   if(market)
      o.price = buy ? ask : bid;
   else
     {
      o.price = RmTickRound(sym, entry);
      double ref = buy ? ask : bid;
      if(MathAbs(o.price - ref) < MathMax(lvl, pt))
        {
         o.why = "pending price too close to the market: use Market, or move the entry";
         return o;
        }
      if(buy)
         o.type = o.price < ref ? ORDER_TYPE_BUY_LIMIT : ORDER_TYPE_BUY_STOP;
      else
         o.type = o.price > ref ? ORDER_TYPE_SELL_LIMIT : ORDER_TYPE_SELL_STOP;
     }
   o.sl = RmTickRound(sym, sl);
   o.tp = tp > 0 ? RmTickRound(sym, tp) : 0;
   if((buy && o.sl >= o.price) || (!buy && o.sl <= o.price))
     {
      o.why = "the stop is on the wrong side of the entry";
      return o;
     }
   if(MathAbs(o.price - o.sl) < lvl)
     {
      o.why = "stop closer than the broker's minimum distance";
      return o;
     }
   if(o.tp > 0 && ((buy && o.tp <= o.price) || (!buy && o.tp >= o.price)))
     {
      o.why = "the take-profit is on the wrong side of the entry";
      return o;
     }
   if(!market && expire > TimeTradeServer() && RmCanExpire(sym))
      o.expire = expire;
   o.ok = true;
   return o;
  }

// filling type the symbol allows (e.g. brokers with Market execution and FOK only),
// used for pending orders too: "Return" is not accepted in Market execution
ENUM_ORDER_TYPE_FILLING RmFilling(const string sym, const bool market)
  {
   long fm = SymbolInfoInteger(sym, SYMBOL_FILLING_MODE);
   if((fm & SYMBOL_FILLING_FOK) == SYMBOL_FILLING_FOK)
      return ORDER_FILLING_FOK;
   if((fm & SYMBOL_FILLING_IOC) == SYMBOL_FILLING_IOC)
      return ORDER_FILLING_IOC;
   return ORDER_FILLING_RETURN;
  }

// sends ONE new order; returns true when the server accepted it. `msg` = ticket or the server's answer.
bool RmSendOrder(const string sym, const RmOrder &o, const long magic, const string comment, const ulong deviation,
                 string &msg)
  {
   msg = "";
   if(!o.ok || o.sl <= 0)
     {
      msg = "RM_NO_SL: refused";
      return false;
     }
   MqlTradeRequest rq;
   MqlTradeResult  rs;
   MqlTradeCheckResult ck;
   ZeroMemory(rq);
   ZeroMemory(rs);
   ZeroMemory(ck);
   rq.action = o.market ? TRADE_ACTION_DEAL : TRADE_ACTION_PENDING;
   rq.symbol = sym;
   rq.volume = o.lot;
   rq.type = o.type;
   rq.price = o.market ? ((o.type == ORDER_TYPE_BUY) ? SymbolInfoDouble(sym, SYMBOL_ASK) : SymbolInfoDouble(sym, SYMBOL_BID)) : o.price;
   rq.sl = o.sl;
   rq.tp = o.tp;
   rq.deviation = deviation;
   rq.magic = magic;
   rq.comment = StringSubstr(comment, 0, 31);
   rq.type_filling = RmFilling(sym, o.market);
   rq.type_time = ORDER_TIME_GTC;
   if(!o.market && o.expire > 0)
     {
      rq.type_time = ORDER_TIME_SPECIFIED;   // the pending order is removed by the server at the end of the window
      rq.expiration = o.expire;
     }
   if(!OrderCheck(rq, ck))
     {
      msg = "check failed: " + ck.comment + " (" + IntegerToString(ck.retcode) + ")";
      return false;
     }
   if(!OrderSend(rq, rs))
     {
      msg = "not sent: " + rs.comment + " (" + IntegerToString(rs.retcode) + ")";
      return false;
     }
   if(rs.retcode != TRADE_RETCODE_DONE && rs.retcode != TRADE_RETCODE_PLACED && rs.retcode != TRADE_RETCODE_DONE_PARTIAL)
     {
      msg = "server: " + rs.comment + " (" + IntegerToString(rs.retcode) + ")";
      return false;
     }
   msg = StringFormat("%s %s lot  #%I64u", RmTypeName(o.type), DoubleToString(o.lot, 2), o.market ? rs.deal : rs.order);
   return true;
  }
//+------------------------------------------------------------------+
