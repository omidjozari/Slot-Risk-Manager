//+------------------------------------------------------------------+
//| RM_Manage.mqh - partial close and cancelling pending orders       |
//| (2.70, 25 Nov 2026, at the user's request): the ONLY file of the  |
//| risk tool that closes part of a position or removes an order.     |
//|                                                                   |
//| Rules kept here (checked by tests/test_slot_risk_manager.py):     |
//|  - a partial close is one market deal against ONE open position   |
//|    (rq.position): it always leaves part of the position open, so  |
//|    it never closes a whole position, never opens or reverses one  |
//|  - only pending orders are removed; positions are never touched   |
//|    here, stops and take-profits are never changed here            |
//|  - the caller (SlotRiskManager.mq5) runs them only with the EA    |
//|    input on: the partial close after the panel switch (asked      |
//|    once), each cancel after its own Windows dialog                |
//+------------------------------------------------------------------+

// closes `volume` lots (rounded down to the broker step) of one open position at the market; true when the server
// accepted it. `msg` = what was done, or why nothing was sent.
bool RmPartialClose(const ulong ticket, const double volume, const ulong deviation, const string comment, string &msg)
  {
   msg = "";
   if(!PositionSelectByTicket(ticket))
     {
      msg = "position closed";
      return false;
     }
   string sym = PositionGetString(POSITION_SYMBOL);
   bool buy = PositionGetInteger(POSITION_TYPE) == POSITION_TYPE_BUY;
   double vol = PositionGetDouble(POSITION_VOLUME);
   double vmin = SymbolInfoDouble(sym, SYMBOL_VOLUME_MIN), step = SymbolInfoDouble(sym, SYMBOL_VOLUME_STEP);
   if(step <= 0)
      step = vmin > 0 ? vmin : 0.01;
   double v = NormalizeDouble(MathFloor(volume / step + 1e-9) * step, RmStepDigits(step));
   if(v < vmin - 1e-9 || v <= 0)
     {
      msg = "RM_TOO_SMALL: " + DoubleToString(volume, 3) + " lot is under the broker minimum (" + DoubleToString(vmin, 2) + ")";
      return false;
     }
   if(vol - v < vmin - 1e-9)
     {
      msg = "RM_FULL_CLOSE: a partial close always leaves part of the position open (" + DoubleToString(vol, 2) + " lot)";
      return false;
     }
   MqlTradeRequest rq;
   MqlTradeResult  rs;
   MqlTradeCheckResult ck;
   ZeroMemory(rq);
   ZeroMemory(rs);
   ZeroMemory(ck);
   rq.action = TRADE_ACTION_DEAL;
   rq.position = ticket;                    // against THIS position only: part of it is closed, nothing new is opened
   rq.symbol = sym;
   rq.volume = v;
   rq.type = buy ? ORDER_TYPE_SELL : ORDER_TYPE_BUY;
   rq.price = buy ? SymbolInfoDouble(sym, SYMBOL_BID) : SymbolInfoDouble(sym, SYMBOL_ASK);
   rq.deviation = deviation;
   rq.magic = PositionGetInteger(POSITION_MAGIC);
   rq.comment = StringSubstr(comment, 0, 31);
   rq.type_filling = RmFilling(sym, true);
   if(rq.price <= 0)
     {
      msg = "no live price";
      return false;
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
   if(rs.retcode != TRADE_RETCODE_DONE && rs.retcode != TRADE_RETCODE_DONE_PARTIAL && rs.retcode != TRADE_RETCODE_PLACED)
     {
      msg = "server: " + rs.comment + " (" + IntegerToString(rs.retcode) + ")";
      return false;
     }
   msg = StringFormat("%s #%I64u: closed %s of %s lot", sym, ticket, DoubleToString(v, 2), DoubleToString(vol, 2));
   return true;
  }

// removes ONE pending order; true when the server accepted it
bool RmCancelPending(const ulong ticket, string &msg)
  {
   msg = "";
   if(!OrderSelect(ticket))
     {
      msg = "order not found (filled or removed already?)";
      return false;
     }
   long ty = OrderGetInteger(ORDER_TYPE);
   bool pending = ty == ORDER_TYPE_BUY_LIMIT || ty == ORDER_TYPE_SELL_LIMIT || ty == ORDER_TYPE_BUY_STOP ||
                  ty == ORDER_TYPE_SELL_STOP || ty == ORDER_TYPE_BUY_STOP_LIMIT || ty == ORDER_TYPE_SELL_STOP_LIMIT;
   if(!pending)
     {
      msg = "RM_NOT_PENDING: only pending orders are cancelled";
      return false;
     }
   string sym = OrderGetString(ORDER_SYMBOL);
   MqlTradeRequest rq;
   MqlTradeResult  rs;
   ZeroMemory(rq);
   ZeroMemory(rs);
   rq.action = TRADE_ACTION_REMOVE;         // removes the pending order, nothing else
   rq.order = ticket;
   rq.symbol = sym;
   if(!OrderSend(rq, rs))
     {
      msg = "not cancelled: " + rs.comment + " (" + IntegerToString(rs.retcode) + ")";
      return false;
     }
   if(rs.retcode != TRADE_RETCODE_DONE && rs.retcode != TRADE_RETCODE_PLACED)
     {
      msg = "server: " + rs.comment + " (" + IntegerToString(rs.retcode) + ")";
      return false;
     }
   msg = StringFormat("%s #%I64u", sym, ticket);
   return true;
  }
//+------------------------------------------------------------------+
