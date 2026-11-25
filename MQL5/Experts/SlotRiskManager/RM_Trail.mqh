//+------------------------------------------------------------------+
//| RM_Trail.mqh - trailing (2.50, 24 Nov 2026, at the user's         |
//| request): the ONLY file of the risk tool that changes an open     |
//| position.                                                         |
//|                                                                   |
//| Rules kept here (checked by tests/test_slot_risk_manager.py):     |
//|  - one action only: TRADE_ACTION_SLTP = the stop-loss and the     |
//|    take-profit of an open position. Never a new order, a close,   |
//|    a pending order or a delete (new orders: RM_Trade.mqh)         |
//|  - the stop only moves in the profit direction: never back, never |
//|    removed; a position without a stop is left alone               |
//|  - the take-profit only moves further from the entry and is never |
//|    removed; a position without a take-profit keeps none           |
//|  - the caller (SlotRiskManager.mq5) runs it only with the EA      |
//|    input on and the panel switch on (confirmed once)              |
//+------------------------------------------------------------------+

// moves the stop (and the take-profit) of ONE open position; true when the server accepted it. `msg` = what was done
// or why nothing was sent ("RM_WAIT": try again on a later tick).
bool RmModifyStops(const ulong ticket, const double sl, const double tp, string &msg)
  {
   msg = "";
   if(!PositionSelectByTicket(ticket))
     {
      msg = "position closed";
      return false;
     }
   string sym = PositionGetString(POSITION_SYMBOL);
   bool buy = PositionGetInteger(POSITION_TYPE) == POSITION_TYPE_BUY;
   double cur_sl = PositionGetDouble(POSITION_SL), cur_tp = PositionGetDouble(POSITION_TP);
   double ts = SymbolInfoDouble(sym, SYMBOL_TRADE_TICK_SIZE);
   if(ts <= 0)
      ts = SymbolInfoDouble(sym, SYMBOL_POINT);
   double nsl = sl > 0 ? RmTickRound(sym, sl) : 0;
   double ntp = cur_tp;
   if(cur_sl <= 0 || nsl <= 0)
     {
      msg = "RM_NO_SL: a position without a stop is not trailed, and a stop is never removed";
      return false;
     }
   if(buy ? nsl < cur_sl - ts / 2 : nsl > cur_sl + ts / 2)
     {
      msg = "RM_SL_BACK: the stop never moves back";
      return false;
     }
   if(cur_tp > 0 && tp > 0)
     {
      ntp = RmTickRound(sym, tp);
      if(buy ? ntp < cur_tp - ts / 2 : ntp > cur_tp + ts / 2)
        {
         msg = "RM_TP_BACK: the take-profit never moves closer";
         return false;
        }
     }
   bool sl_ch = MathAbs(nsl - cur_sl) >= ts / 2, tp_ch = MathAbs(ntp - cur_tp) >= ts / 2;
   if(!sl_ch && !tp_ch)
     {
      msg = "no change";
      return false;
     }
   double bid = SymbolInfoDouble(sym, SYMBOL_BID), ask = SymbolInfoDouble(sym, SYMBOL_ASK);
   double pt = SymbolInfoDouble(sym, SYMBOL_POINT);
   double lvl = (double)MathMax(SymbolInfoInteger(sym, SYMBOL_TRADE_STOPS_LEVEL), SymbolInfoInteger(sym, SYMBOL_TRADE_FREEZE_LEVEL)) * pt;
   if(bid <= 0 || ask <= 0)
     {
      msg = "RM_WAIT: no live price";
      return false;
     }
   if(buy ? nsl > bid - lvl - pt / 2 : nsl < ask + lvl + pt / 2)
     {
      msg = "RM_WAIT: the new stop would be too close to the price";
      return false;
     }
   if(ntp > 0 && tp_ch && (buy ? ntp < bid + lvl : ntp > ask - lvl))
     {
      msg = "RM_WAIT: the new take-profit would be too close to the price";
      return false;
     }
   MqlTradeRequest rq;
   MqlTradeResult  rs;
   ZeroMemory(rq);
   ZeroMemory(rs);
   rq.action = TRADE_ACTION_SLTP;          // stop-loss / take-profit of an open position, nothing else
   rq.position = ticket;
   rq.symbol = sym;
   rq.sl = nsl;
   rq.tp = ntp;
   rq.magic = PositionGetInteger(POSITION_MAGIC);
   if(!OrderSend(rq, rs))
     {
      msg = "not changed: " + rs.comment + " (" + IntegerToString(rs.retcode) + ")";
      return false;
     }
   if(rs.retcode != TRADE_RETCODE_DONE && rs.retcode != TRADE_RETCODE_PLACED)
     {
      msg = "server: " + rs.comment + " (" + IntegerToString(rs.retcode) + ")";
      return false;
     }
   int dg = (int)SymbolInfoInteger(sym, SYMBOL_DIGITS);
   msg = StringFormat("%s #%I64u  SL %s%s", sym, ticket, DoubleToString(nsl, dg), ntp > 0 ? "  TP " + DoubleToString(ntp, dg) : "");
   return true;
  }
//+------------------------------------------------------------------+
