"""Static checks of the Slot Risk Manager (MQL5/Experts/SlotRiskManager/): the order safety rules (only RM_Trade.mqh sends
new orders, only RM_Trail.mqh moves stops forward, only RM_Manage.mqh closes part of a position or removes a pending order;
two switches and two confirmations), the v2 discipline rules, the panel and its Persian text.
The arithmetic itself is tested inside MT5 by the RM_Tests script (MQL5/Scripts/SlotRiskManager).
Run: python tests/test_slot_risk_manager.py   (or pytest)"""
import pathlib
import re
import sys

TOOL = pathlib.Path(__file__).resolve().parent.parent / "MQL5" / "Experts" / "SlotRiskManager"
FORBIDDEN = ["OrderSend", "OrderSendAsync", "CTrade", "Trade.mqh", "PositionClose", "PositionModify", "OrderModify",
             "OrderDelete", "TRADE_ACTION", "MqlTradeRequest", "CPositionInfo"]


def _has(src, w):
    return re.search(r"\b" + re.escape(w) + r"\b", src) is not None


def _main():
    return (TOOL / "SlotRiskManager.mq5").read_text(encoding="utf-8")


def _between(src, a, b):
    return src[src.index(a):src.index(b, src.index(a))]


def test_order_code_only_in_the_trade_module():
    files = [f for f in list(TOOL.glob("*.mq5")) + list(TOOL.glob("*.mqh")) if f.name not in ("RM_Trade.mqh", "RM_Trail.mqh", "RM_Manage.mqh")]
    assert len(files) >= 4, files
    for f in files:
        src = f.read_text(encoding="utf-8")
        for w in FORBIDDEN:
            assert not _has(src, w), f"{f.name}: {w}"


def test_trade_module_only_places_new_orders_with_a_stop():
    src = (TOOL / "RM_Trade.mqh").read_text(encoding="utf-8")
    for w in ("OrderSendAsync", "CTrade", "Trade.mqh", "PositionClose", "PositionModify", "OrderModify", "OrderDelete",
              "CPositionInfo"):
        assert not _has(src, w), w
    assert set(re.findall(r"TRADE_ACTION_\w+", src)) == {"TRADE_ACTION_DEAL", "TRADE_ACTION_PENDING"}   # never modify / remove / close
    assert src.count("OrderSend(") == 1 and "OrderCheck(" in src
    assert src.count("RM_NO_SL") >= 2                                                    # no stop -> refused, twice
    assert "rq.sl = o.sl" in src
    assert set(re.findall(r"ORDER_TIME_\w+", src)) == {"ORDER_TIME_GTC", "ORDER_TIME_SPECIFIED"}   # 2.20: expiry or GTC only
    assert "SYMBOL_EXPIRATION_SPECIFIED" in src                                          # only when the broker allows it


def test_orders_only_behind_two_switches_and_two_confirmations():
    main = _main()
    assert re.search(r"input bool\s+InpTradingEnabled\s*=\s*false;", main)                # switch 1: EA input, off
    assert re.search(r"bool\s+g_trade_on\s*=\s*false;", main) and 'SaveNum("trade' not in main   # switch 2: starts OFF, not saved
    assert main.count("RmSendOrder(") == 1
    body = _between(main, "void DoConfirm()", "int DrawOrders(")
    assert "RmSendOrder(" in body and body.index("MessageBox(") < body.index("RmSendOrder(")          # dialog before sending
    assert "MB_DEFBUTTON2" in body and "IDYES" in body                                    # default answer = No
    assert "changed" in body and "expired" in body                                        # same plan as step 1, in time
    assert "TERMINAL_TRADE_ALLOWED" in body and "MQL_TRADE_ALLOWED" in body
    plan = _between(main, "bool BuildPlan(", "void StartConfirm()")
    for lock in ("InpTradingEnabled", "g_trade_on", "daily loss limit", "no averaging down", "no stop-loss"):
        assert lock in plan, lock


def test_panel_is_narrow_and_stays_inside_the_chart():
    main = _main()
    assert int(re.search(r"#define PW (\d+)", main).group(1)) <= 340
    draw = _between(main, "void Draw()", "int Panel(")
    assert "g_dry = true" in draw and "UiClip(" in draw                                  # measure, then paint the scrolled body clipped
    assert "MathMin(g_py, ch - vmin" in draw and "ch - g_draw_y" in draw                 # stays in place, down to the chart bottom at most
    for fold in ("FRISK", "FTGT", "FDAY", "FV2"):
        assert '"' + fold + '"' in main, fold
    for f in ("void Rect(", "void Text(", "void Btn(", "void Ed("):
        body = main[main.index(f):main.index("{", main.index(f)) + 40]
        assert "if(g_dry)" in body, f


V2_DEFAULTS = {
    "InpV2On": "false", "InpIdeaRiskPct": "1.0", "InpIdeaMaxLegs": "3", "InpOpenRiskPct": "2.0",
    "InpWindowStart": '"16:30"', "InpWindowEnd": '"21:00"', "InpPendingExpire": "true", "InpMaxTradesDay": "4",
    "InpMaxLossStreak": "2", "InpDayLossPct": "2.0", "InpPauseMin": "30", "InpMinTpR": "2.0",
    "InpStopSpreads": '"US30=8,XAUUSD=8,BTCUSD=5,ETHUSD=5,EURUSD=8,GBPUSD=8,OTHER=8"',
    "InpMarkets": '"US30,XAUUSD,BTCUSD,ETHUSD,EURUSD,GBPUSD,OTHER"',
}


def test_v2_inputs_have_the_review_values():
    main = _main()
    for name, val in V2_DEFAULTS.items():
        m = re.search(r"input\s+\w+\s+" + name + r"\s*=\s*([^;]+);", main)
        assert m and m.group(1).strip() == val, (name, m and m.group(1))


def test_v2_rules_lock_the_order_button():
    main = _main()
    plan = _between(main, "bool BuildPlan(", "void StartConfirm()")
    assert "v_v2_why" in plan and "g_v2on" in plan                                       # any failing v2 rule: no order
    assert plan.index("v_v2_why") < plan.index("RmBuildOrder(")
    check = _between(main, "void V2Check()", "datetime PendingExpiry()")
    for rule in ("InpDayLossPct", "InpMaxLossStreak", "v_pause_left", "InpMaxTradesDay", "v_win_in", "g_mk_allow",
                 "no_sl", "InpIdeaMaxLegs", "InpIdeaRiskPct", "InpOpenRiskPct", "v_min_stop", "InpMinTpR"):
        assert rule in check, rule
    calc = _between(main, "void Calc()", "// ---------------- drawing")
    assert calc.index("CalcCore();") < calc.index("V2Check();")
    assert "double bud = v_size_budget;" in calc                                         # lot sized on the capped budget
    pre = _between(main, "void V2Pre()", "void V2Block(")
    assert "RmCapBudget(v_budget, idea_room, open_room)" in pre
    assert "void OnTrade()" in main and "g_hist_dirty = true" in main                    # history read again after a trade
    assert "TradesAt(dt.day_of_week, m)" in check and "RmMinutesToOpen(" in check      # weekend: window opens Monday


def test_v2_never_raises_the_risk():
    math = (TOOL / "RM_Math.mqh").read_text(encoding="utf-8")
    cap = _between(math, "double RmCapBudget(", "bool RmSymbolAllowed(")
    assert "MathMax(" not in cap.replace("MathMax(0.0", "")                              # only MathMin against the rooms
    assert cap.count("MathMin(") == 2


def test_three_entries_share_one_stop():
    main = _main()
    plan = _between(main, "bool BuildPlan(", "void StartConfirm()")
    assert plan.count("RmBuildOrder(") == 3 and plan.count("v_sl, tp,") == 3              # same stop on every entry
    assert "RmOrder g_plan[3];" in main and "RmOrder before[3];" in main



def test_sessions_are_chosen_in_the_panel():
    main = _main()
    for name, val in {"InpWindowOn": "true", "InpLondonStart": '"10:00"', "InpLondonEnd": '"18:30"',
                      "InpAsiaStart": '"02:00"', "InpAsiaEnd": '"11:00"'}.items():
        m = re.search(r"input\s+\w+\s+" + name + r"\s*=\s*([^;]+);", main)
        assert m and m.group(1).strip() == val, (name, m and m.group(1))
    btn = _between(main, "void Button(", "void OnChartEvent(")
    assert 'b == "WIN"' in btn and 'StringFind(b, "SES") == 0' in btn and '"FSES"' in btn   # switch, tick a session, fold
    check = _between(main, "void V2Check()", "datetime PendingExpiry()")
    assert "RmInSessions(" in check and "RmMinutesToClose(" in check and "g_win_rule" in check and '"no session"' in check
    state = _between(main, "void SaveState()", "void Refresh()")
    assert 'SaveNum("won"' in state and 'SaveNum(k + "o"' in state and "EdTime(" in _between(main, "void ReadEdits()", "void SaveState()")


def test_panel_is_one_canvas_with_click_zones():
    ui = (TOOL / "RM_UI.mqh").read_text(encoding="utf-8")
    assert "CreateBitmapLabel(" in ui and "COLOR_FORMAT_ARGB_NORMALIZE" in ui and "UiHit(" in ui
    main = _main()
    for old in ("OBJ_BUTTON", "OBJ_RECTANGLE_LABEL", "OBJ_LABEL"):                     # everything but the fields is on the canvas
        assert old not in main, old
    ev = main[main.index("void OnChartEvent("):]
    assert "CHARTEVENT_CLICK" in ev and "UiHit(" in ev and "Button(hit)" in ev
    assert "UiDestroy();" in _between(main, "void OnDeinit(", "void OnTick()")
    assert '#include "RM_UI.mqh"' in main


def test_panel_stays_above_the_chart_lines():
    main = _main()
    draw = _between(main, "void Draw()", "int Panel(")
    assert draw.index("DrawChart()") < draw.index("UiBegin(")                         # lines made before the canvas is painted
    assert "RaisePanel();" in draw
    raise_fn = _between(main, "void RaisePanel()", "\n  }\n")
    assert "UiDestroy();" in raise_fn and "ObjectsDeleteAll(0, PB);" in raise_fn       # canvas made again, then its fields
    assert "made = HLine(" in _between(main, "bool DrawChart()", "void RaisePanel()")
    ev = main[main.index("void OnChartEvent("):]
    assert "CHARTEVENT_OBJECT_CREATE" in ev and 'StringFind(sparam, "RM_") != 0' in ev   # other drawings, not our own
    assert "ChartSetInteger(0, CHART_EVENT_OBJECT_CREATE, g_create_orig);" in _between(main, "void OnDeinit(", "void OnTick()")


def test_markets_found_by_name_and_ticked_in_the_panel():
    main = _main()
    assert "InpAllowedSymbols" not in main                                              # the YM-only list is gone (2.40)
    find = _between(main, "void FindMarkets()", "string SpreadOf(")
    assert "SymbolsTotal(false)" in find and "RmFamily(" in find and "SYMBOL_TRADE_MODE_FULL" in find
    btn = _between(main, "void Button(", "void OnChartEvent(")
    assert 'StringFind(b, "MKA") == 0' in btn and "ChartSetSymbolPeriod(" in btn and '"FMKT"' in btn
    assert 'GlobalVariableSet("RM_MK_"' in _between(main, "void SaveState()", "void LoadState()")   # one choice for every chart
    math = (TOOL / "RM_Math.mqh").read_text(encoding="utf-8")
    assert '{"US30", "XAUUSD", "BTCUSD", "ETHUSD", "EURUSD", "GBPUSD"}' in math


def test_costs_are_in_the_risk():
    main = _main()
    calc = _between(main, "void CalcCore()", "// ---------------- drawing")
    assert "l1 += g_comm_lot + (mk1 ? v_slip_lot : 0);" in calc                          # commission + slippage in the loss per lot
    assert calc.index("l1 += g_comm_lot") < calc.index("v_s1 = RmSizeFor(")              # ... before the volume is sized
    assert "InpDeviation * _Point" in calc and "rw -= v_cost_comm;" in calc
    assert '"Spread now"' in main and "FindCommission();" in main


def test_panel_scrolls():
    main = _main()
    ev = main[main.index("void OnChartEvent("):]
    assert "CHARTEVENT_MOUSE_WHEEL" in ev and "g_sdrag" in ev and "ScrollTo(" in ev
    assert "ChartSetInteger(0, CHART_EVENT_MOUSE_WHEEL, g_wheel_orig);" in _between(main, "void OnDeinit(", "void OnTick()")
    ui = (TOOL / "RM_UI.mqh").read_text(encoding="utf-8")
    assert "void UiClip(" in ui and "UiInClipY(" in main                                 # nothing drawn or clickable outside the view


def test_stop_spread_multiplier_is_per_market():
    main = _main()
    assert "InpMinStopSpreads" not in main                                              # one number for all markets is gone (2.41)
    check = _between(main, "void V2Check()", "datetime PendingExpiry()")
    assert "StopSpreads() * v_spread" in check
    assert 'EdNum("MKX" + IntegerToString(f), v)' in _between(main, "void ReadEdits()", "void SaveState()")
    assert 'GlobalVariableSet("RM_MKX_"' in _between(main, "void SaveState()", "void LoadState()")
    row = _between(main, "int MarketRow(", "int DrawMarkets(")
    assert 'PB + "ED_MKX"' in row and "R - L - Z(90)" in row                            # field, outside the "open" click zone


def test_trailing_only_moves_stops_forward():
    src = (TOOL / "RM_Trail.mqh").read_text(encoding="utf-8")
    for w in ("OrderSendAsync", "CTrade", "Trade.mqh", "PositionClose", "PositionModify", "OrderModify", "OrderDelete",
              "CPositionInfo"):
        assert not _has(src, w), w                                                       # no new order, no close
    for w in ("rq.volume", "rq.type", "rq.price", "rq.deviation"):
        assert w not in src, w
    assert set(re.findall(r"TRADE_ACTION_\w+", src)) == {"TRADE_ACTION_SLTP"}            # only stop-loss / take-profit
    assert src.count("OrderSend(") == 1
    send = src.index("OrderSend(")
    for guard in ("RM_NO_SL", "RM_SL_BACK", "RM_TP_BACK"):                               # refused before sending
        assert guard in src and src.index(guard) < send, guard
    main = _main()
    assert re.search(r"input bool\s+InpTrailAllowed\s*=\s*false;", main)               # switch 1: EA input, off
    assert main.count("RmModifyStops(") == 1
    run = _between(main, "void TrailRun()", "int DefaultTp()")
    assert "RmModifyStops(" in run
    for lock in ("InpTrailAllowed", "g_trail_on", "TrailOwner()", "MQL_TRADE_ALLOWED", "RmStopForward(", "RmTpFurther(", "n >= 0"):
        assert lock in run, lock
    sw = _between(main, "void TrailSwitch()", "// ---------------- engine card")
    assert "MessageBox(" in sw and "MB_DEFBUTTON2" in sw and "IDYES" in sw              # switch 2: asked once, default No
    assert sw.index("MessageBox(") < sw.index('GlobalVariableSet("RM_TRAIL_ON", 1)')
    btn = _between(main, "void Button(", "void OnChartEvent(")
    assert 'b == "TRL") TrailSwitch();' in btn and '"FTRL"' in btn
    ev = main[main.index("void OnChartEvent("):]
    click = ev[ev.index("Button(hit);"):ev.index("return;", ev.index("Button(hit);"))]
    assert "g_click_at = GetTickCount();" in click                                       # 2.51: the late second report is ignored
    math = (TOOL / "RM_Math.mqh").read_text(encoding="utf-8")
    fwd = _between(math, "bool RmStopForward(", "bool RmTpFurther(")
    assert "want > cur + tick / 2 : want < cur - tick / 2" in fwd and "cur <= 0 || want <= 0" in fwd
    assert "OrderTpR() < InpMinTpR" in _between(main, "void V2Check()", "datetime PendingExpiry()")


def test_chart_box_positions_and_phone():
    main = _main()
    chart = _between(main, "bool DrawChart()", "void RaisePanel()")
    assert "RiskBox(" in chart and "NextSteps()" in chart and 'HLine("TPL"' in chart       # 2.60: box, next step, TP line
    ev = main[main.index("void OnChartEvent("):]
    assert 'sparam == PC + "TPL") { g_tp_px = p; g_tp_r = 4; }' in ev                   # dragging the TP line sets it
    assert "return g_tp_px;" in _between(main, "double SelTp()", "string TrailRule()")
    assert "double tp = SelTp();" in _between(main, "bool BuildPlan(", "void StartConfirm()")
    run = _between(main, "void TrailRun()", "int DefaultTp()")
    assert run.index("TrailExcluded(tk)") < run.index("RmModifyStops(")                 # off for one position = never moved
    btn = _between(main, "void Button(", "void OnChartEvent(")
    assert 'StringFind(b, "PTR") == 0' in btn and "TrailXKey(tk)" in btn and '"FPOS"' in btn
    push = _between(main, "void Push(", "void NoteClosed(")
    assert "SendNotification(" in push and "k >= 10" in push                             # at most 10 a minute
    assert main.count("SendNotification(") == 1
    note = _between(main, "void NoteRun()", "// ---------------- trailing section")
    assert 'Owner("NOTE")' in note                                                       # one chart sends, no duplicates
    assert 'Release("NOTE");' in _between(main, "void OnDeinit(", "void OnTick()")
    for w in ("OrderSend", "TRADE_ACTION", "PositionClose"):                             # display and phone only
        assert w not in _between(main, "// ---------------- chart (2.60)", "// ---------------- trailing section"), w


def test_manage_module_only_closes_part_or_removes_pending():
    src = (TOOL / "RM_Manage.mqh").read_text(encoding="utf-8")
    for w in ("OrderSendAsync", "CTrade", "Trade.mqh", "PositionClose", "PositionModify", "OrderModify", "CPositionInfo"):
        assert not _has(src, w), w
    assert set(re.findall(r"TRADE_ACTION_\w+", src)) == {"TRADE_ACTION_DEAL", "TRADE_ACTION_REMOVE"}   # no stops, no new pending
    assert "rq.sl" not in src and "rq.tp" not in src
    assert src.count("OrderSend(") == 2
    part = _between(src, "bool RmPartialClose(", "bool RmCancelPending(")
    assert "rq.position = ticket;" in part                                               # against one position: never a new one
    assert part.index("RM_FULL_CLOSE") < part.index("OrderSend(")                        # always leaves part of it open
    assert "vol - v < vmin" in part and "OrderCheck(" in part
    canc = src[src.index("bool RmCancelPending("):]
    assert canc.index("RM_NOT_PENDING") < canc.index("OrderSend(") and "rq.order = ticket;" in canc
    main = _main()
    assert re.search(r"input bool\s+InpManageAllowed\s*=\s*false;", main)              # switch 1: EA input, off
    assert main.count("RmPartialClose(") == 1 and main.count("RmCancelPending(") == 1
    run = _between(main, "void PartialRun()", "void PartialSwitch()")
    for lock in ("InpManageAllowed", "g_pc_on", 'Owner("MANAGE")', "MQL_TRADE_ALLOWED", "TrailExcluded(tk)", "RM_PC_D_"):
        assert lock in run, lock
    sw = _between(main, "void PartialSwitch()", "int DrawPartial(")
    assert "MB_DEFBUTTON2" in sw and sw.index("MessageBox(") < sw.index('GlobalVariableSet("RM_PC_ON", 1)')   # switch 2: asked once
    cxl = _between(main, "void CancelPending(", "// ---------------- partial close")
    assert "MB_DEFBUTTON2" in cxl and cxl.index("MessageBox(") < cxl.index("RmCancelPending(")   # every cancel asked


def test_tabs_settings_hotkeys_news_checklist_journal():
    main = _main()
    head = _between(main, "void Head(", "// the panel's content below the header")
    assert 'BTN_TAB' in head and "SPill(" in head and "Compact(" in head               # tabs, status pills, compact bar
    panel = _between(main, "int Panel(", "int TabTrade(")
    for t in ("TabTrade(", "TabPositions(", "TabRules(", "TabSettings("):
        assert t in panel or t in main, t
    plan = _between(main, "bool BuildPlan(", "void StartConfirm()")
    assert "v_news_lock" in plan and "ChecklistOk()" in plan                             # news lock and checklist lock the order
    assert plan.index("ChecklistOk()") < plan.index("RmBuildOrder(")
    keys = _between(main, "void HotKey(", "// ---------------- news lock")
    assert "g_editing" in keys and "StartConfirm();" in keys and "DoConfirm" not in keys   # Enter = step 1 only, never sends
    assert "CHARTEVENT_KEYDOWN" in main and "CHART_QUICK_NAVIGATION, g_qnav_orig" in _between(main, "void OnDeinit(", "void OnTick()")
    assert "CalendarValueHistory(" in main and "CALENDAR_IMPORTANCE_HIGH" in main
    assert 'GlobalVariablesDeleteAll("RM_S_")' in _between(main, "void Button(", "void OnChartEvent(")   # Reset all -> EA inputs
    assert "SaveSettings();" in _between(main, "void SaveState()", "void LoadState()")
    assert "RM_JOURNAL" in main and 'Owner("JOURNAL")' in _between(main, "void ScoreRun()", "int DrawPending(")
    assert "RM_PRESETS" in main and "void PresetApply(" in main
    ap = _between(main, "void PresetApply(", "int DrawPresets(")
    assert "TrailSwitch();" in ap and "PartialSwitch();" in ap                           # a preset never switches them on silently


def test_quick_place_theme_and_persian():
    main = _main()
    qp = _between(main, "void QpOn()", "int DrawQpSet(")
    for w in ("StartConfirm", "DoConfirm", "RmSendOrder", "BuildPlan"):                 # quick place only puts lines
        assert w not in qp, w
    comp = _between(main, "void Compact(", "// ---------------- the tabs")
    assert "BTN_CONFIRM" in comp and "BTN_ORDER" in comp                                # the same two steps, in the bar
    assert "QpOff();" in _between(main, "void DoConfirm()", "int DrawOrders(")          # lines go once the order is sent
    assert "else if(k == 'Q')" in _between(main, "void HotKey(", "// ---------------- news lock")
    assert "g_dark = g_theme == 1 || (g_theme == 0 && lum < 128);" in main               # auto follows the chart
    ui = (TOOL / "RM_UI.mqh").read_text(encoding="utf-8")
    assert "UiFx(" in ui and "LangTr(t)" in ui and "UiSunMoon(" in ui                    # mirrored, translated, sun / moon
    lang = (TOOL / "RM_Lang.mqh").read_text(encoding="utf-8")
    assert "#define LG_N" in lang and "OrderSend" not in lang

if __name__ == "__main__":
    fails = 0
    for name, fn in list(globals().items()):
        if name.startswith("test_") and callable(fn):
            try:
                fn()
                print("ok  ", name)
            except AssertionError as ex:
                fails += 1
                print("FAIL", name, ex)
    sys.exit(1 if fails else 0)
