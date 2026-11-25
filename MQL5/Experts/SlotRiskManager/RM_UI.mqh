//+------------------------------------------------------------------+
//| RM_UI.mqh - drawing layer of the Slot Risk Manager panel (2.30)   |
//| The whole panel is one canvas (OBJ_BITMAP_LABEL): rounded cards,  |
//| soft shadow, anti-aliased corners and text, switches and bars.    |
//| Clickable places are "zones", hit-tested on mouse clicks; input   |
//| fields stay OBJ_EDIT objects on top of the canvas.                |
//| Pure drawing: no trading code, no chart lines.                    |
//| 2.80: right to left: every shape, text and click zone mirrored     |
//| (UiMirror), every text through LangTr (RM_Lang.mqh)               |
//| 2.40: a clip rectangle (the scrolled body): shapes, text, icons   |
//| and click zones outside it are not drawn / not clickable.         |
//+------------------------------------------------------------------+
#include <Canvas\Canvas.mqh>

CCanvas UiCv;
bool    UiOk = false;
string  UiName = "RM_UI_PANEL";
int     UiOx = 0, UiOy = 0, UiW = 0, UiH = 0;      // canvas position on the chart and size (pixels)
string  UiZid[], UiZtip[];
int     UiZx[], UiZy[], UiZw[], UiZh[];
int     UiZn = 0;
bool    UiClipOn = false;
double  UiZoom = 1.0;                                 // panel size (2.70): text scale on top of the Windows scale
bool    UiMirror = false;                             // 2.80 right to left: the panel drawn as in a mirror
int     UiAx = 0;                                     // mirror axis: left + right edge of the panel card

// 2.90 fonts: the panel's "Segoe UI" / "Segoe UI Semibold" are drawn in the font chosen in Settings
string  UiFR = "Segoe UI", UiFB = "Segoe UI Semibold";
uint    UiFBf = 0;                                    // weight flag for the bold face (FW_BOLD when the font has no "Semibold" face)
string  UiFontName(const string f) { return f == "Segoe UI Semibold" ? UiFB : (f == "Segoe UI" ? UiFR : f); }
uint    UiFontFlags(const string f) { return f == "Segoe UI Semibold" ? UiFBf : 0; }

// x of a box of width w after the mirror (chart coordinates)
int UiFx(const int X, const int w) { return UiMirror ? UiAx - X - w : X; }
int     UiCx0 = 0, UiCy0 = 0, UiCx1 = 0, UiCy1 = 0;  // clip rectangle, chart coordinates, inclusive

// draw only inside (x0, y0)-(x1, y1) until UiNoClip()
void UiClip(const int x0, const int y0, const int x1, const int y1)
  {
   UiClipOn = true;
   UiCx0 = UiMirror ? UiAx - x1 - 1 : x0; UiCy0 = y0; UiCx1 = UiMirror ? UiAx - x0 - 1 : x1; UiCy1 = y1;
  }

void UiNoClip() { UiClipOn = false; }

// the band y0 .. y1 (y1 excluded) is fully inside the clip (an input field is shown only then)
bool UiInClipY(const int y0, const int y1) { return !UiClipOn || (y0 >= UiCy0 && y1 - 1 <= UiCy1); }

// mix two colours: t = 0 -> a, t = 1 -> b
color UiMix(const color a, const color b, const double t)
  {
   double k = MathMax(0.0, MathMin(1.0, t));
   uint ua = (uint)a, ub = (uint)b;
   int ar = (int)(ua & 0xFF), ag = (int)((ua >> 8) & 0xFF), ab = (int)((ua >> 16) & 0xFF);
   int br = (int)(ub & 0xFF), bg = (int)((ub >> 8) & 0xFF), bb = (int)((ub >> 16) & 0xFF);
   int r = (int)MathRound(ar + (br - ar) * k), g = (int)MathRound(ag + (bg - ag) * k), bl = (int)MathRound(ab + (bb - ab) * k);
   return (color)(r | (g << 8) | (bl << 16));
  }

// blend colour `c` with coverage / opacity `a` (0..1) over the pixel already there (canvas coordinates)
void UiPx(const int x, const int y, const color c, const double a)
  {
   if(a <= 0.0 || x < 0 || y < 0 || x >= UiW || y >= UiH)
      return;
   if(UiClipOn && (x + UiOx < UiCx0 || x + UiOx > UiCx1 || y + UiOy < UiCy0 || y + UiOy > UiCy1))
      return;
   uint d = UiCv.PixelGet(x, y);
   double da = (double)((d >> 24) & 0xFF) / 255.0;
   double sa = MathMin(1.0, a);
   double oa = sa + da * (1.0 - sa);
   if(oa <= 0.0)
      return;
   uint uc = (uint)c;
   double sr = (double)(uc & 0xFF), sg = (double)((uc >> 8) & 0xFF), sb = (double)((uc >> 16) & 0xFF);
   double dr = (double)((d >> 16) & 0xFF), dg = (double)((d >> 8) & 0xFF), db = (double)(d & 0xFF);
   uint r = (uint)MathMin(255.0, MathRound((sr * sa + dr * da * (1.0 - sa)) / oa));
   uint g = (uint)MathMin(255.0, MathRound((sg * sa + dg * da * (1.0 - sa)) / oa));
   uint b = (uint)MathMin(255.0, MathRound((sb * sa + db * da * (1.0 - sa)) / oa));
   uint A = (uint)MathMin(255.0, MathRound(oa * 255.0));
   UiCv.PixelSet(x, y, (A << 24) | (r << 16) | (g << 8) | b);
  }

// filled rectangle in canvas coordinates (inclusive), cut to the canvas and the clip
void UiRect(int x1, int y1, int x2, int y2, const uint argb)
  {
   if(x1 > x2 || y1 > y2)
      return;
   int cx0 = 0, cy0 = 0, cx1 = UiW - 1, cy1 = UiH - 1;
   if(UiClipOn)
     {
      cx0 = MathMax(cx0, UiCx0 - UiOx); cy0 = MathMax(cy0, UiCy0 - UiOy);
      cx1 = MathMin(cx1, UiCx1 - UiOx); cy1 = MathMin(cy1, UiCy1 - UiOy);
     }
   x1 = MathMax(x1, cx0); y1 = MathMax(y1, cy0); x2 = MathMin(x2, cx1); y2 = MathMin(y2, cy1);
   if(x1 > x2 || y1 > y2)
      return;
   UiCv.FillRectangle(x1, y1, x2, y2, argb);
  }

// start a frame. The panel's card is at (x, y, w, h) on the chart; `pad` pixels around it hold the shadow.
bool UiBegin(const int x, const int y, const int w, const int h, const int pad)
  {
   int l = MathMax(0, x - pad), t = MathMax(0, y - pad);
   int cw = MathMax(1, x + w + pad - l), ch = MathMax(1, y + h + pad - t);
   if(!UiOk || ObjectFind(0, UiName) < 0)
     {
      if(UiOk)
         UiCv.Destroy();
      UiOk = UiCv.CreateBitmapLabel(0, 0, UiName, l, t, cw, ch, COLOR_FORMAT_ARGB_NORMALIZE);
      if(!UiOk)
         return false;
      ObjectSetInteger(0, UiName, OBJPROP_CORNER, CORNER_LEFT_UPPER);
      ObjectSetInteger(0, UiName, OBJPROP_SELECTABLE, false);
      ObjectSetInteger(0, UiName, OBJPROP_HIDDEN, true);
      ObjectSetInteger(0, UiName, OBJPROP_BACK, false);
      ObjectSetString(0, UiName, OBJPROP_TOOLTIP, "\n");
     }
   else if(cw != UiCv.Width() || ch != UiCv.Height())
      UiCv.Resize(cw, ch);
   ObjectSetInteger(0, UiName, OBJPROP_XDISTANCE, l);
   ObjectSetInteger(0, UiName, OBJPROP_YDISTANCE, t);
   ObjectSetInteger(0, UiName, OBJPROP_XSIZE, cw);
   ObjectSetInteger(0, UiName, OBJPROP_YSIZE, ch);
   UiOx = l;
   UiOy = t;
   UiAx = 2 * x + w;
   UiW = cw;
   UiH = ch;
   UiCv.Erase(0);                                   // fully transparent
   UiZn = 0;
   UiClipOn = false;
   return true;
  }

void UiEnd()
  {
   if(UiOk)
      UiCv.Update(false);
  }

void UiDestroy()
  {
   if(UiOk)
      UiCv.Destroy();
   UiOk = false;
   UiZn = 0;
  }

void UiSetTip(const string t)
  {
   if(UiOk)
      ObjectSetString(0, UiName, OBJPROP_TOOLTIP, t == "" ? "\n" : LangTr(t));
  }

// ---------------- shapes (chart coordinates)
// filled rounded rectangle, opaque colour, anti-aliased corners
void UiRound(const int X, const int Y, const int w, const int h, const int radius, const color c)
  {
   if(!UiOk || w <= 0 || h <= 0)
      return;
   int x = UiFx(X, w) - UiOx, y = Y - UiOy;
   int r = MathMax(0, MathMin(radius, MathMin(w, h) / 2));
   uint argb = ColorToARGB(c, 255);
   if(r == 0)
     {
      UiRect(x, y, x + w - 1, y + h - 1, argb);
      return;
     }
   if(w - 2 * r > 0)
      UiRect(x + r, y, x + w - 1 - r, y + h - 1, argb);
   if(h - 2 * r > 0)
     {
      UiRect(x, y + r, x + r - 1, y + h - 1 - r, argb);
      UiRect(x + w - r, y + r, x + w - 1, y + h - 1 - r, argb);
     }
   for(int j = 0; j < r; j++)
      for(int i = 0; i < r; i++)
        {
         double dx = r - (i + 0.5), dy = r - (j + 0.5);
         double cov = r + 0.5 - MathSqrt(dx * dx + dy * dy);
         if(cov <= 0.0)
            continue;
         if(cov > 1.0)
            cov = 1.0;
         UiPx(x + i, y + j, c, cov);
         UiPx(x + w - 1 - i, y + j, c, cov);
         UiPx(x + i, y + h - 1 - j, c, cov);
         UiPx(x + w - 1 - i, y + h - 1 - j, c, cov);
        }
  }

void UiFill(const int X, const int Y, const int w, const int h, const color c) { UiRound(X, Y, w, h, 0, c); }

// rounded card with a 1 px border (edge = bg: no border)
void UiCard(const int X, const int Y, const int w, const int h, const int r, const color bg, const color edge)
  {
   if(edge == bg || w < 3 || h < 3)
     {
      UiRound(X, Y, w, h, r, bg);
      return;
     }
   UiRound(X, Y, w, h, r, edge);
   UiRound(X + 1, Y + 1, w - 2, h - 2, MathMax(0, r - 1), bg);
  }

void UiCircle(const int cx, const int cy, const int r, const color c) { UiRound(cx - r, cy - r, 2 * r, 2 * r, r, c); }

void UiLineH(const int X, const int Y, const int w, const color c)
  {
   if(UiOk && w > 0)
      UiRect(UiFx(X, w) - UiOx, Y - UiOy, UiFx(X, w) - UiOx + w - 1, Y - UiOy, ColorToARGB(c, 255));
  }

// soft drop shadow of a rounded card, `s` pixels wide, `dy` pixels lower, opacity `maxa` at the edge
void UiShadow(const int X, const int Y, const int w, const int h, const int r, const int s, const int dy, const double maxa)
  {
   if(!UiOk || s <= 0)
      return;
   int x0 = UiFx(X, w) - UiOx, y0 = Y - UiOy + dy;
   double hw = w / 2.0, hh = h / 2.0, cx = x0 + hw, cy = y0 + hh;
   int ax = MathMax(0, x0 - s), ay = MathMax(0, y0 - s);
   int bx = MathMin(UiW - 1, x0 + w + s), by = MathMin(UiH - 1, y0 + h + s);
   for(int py = ay; py <= by; py++)
     {
      double qy = MathAbs(py + 0.5 - cy) - (hh - r);
      bool mid = py >= y0 + r && py < y0 + h - r;
      for(int px = ax; px <= bx; px++)
        {
         if(mid && px >= x0 + 2 && px < x0 + w - 2)
           {
            px = x0 + w - 3;                         // the card covers its inside: skip it
            continue;
           }
         double qx = MathAbs(px + 0.5 - cx) - (hw - r);
         double ox = MathMax(qx, 0.0), oy = MathMax(qy, 0.0);
         double d = MathSqrt(ox * ox + oy * oy) + MathMin(MathMax(qx, qy), 0.0) - r;   // distance to the card's edge
         if(d >= s)
            continue;
         double k = d <= 0.0 ? 1.0 : 1.0 - d / s;
         UiPx(px, py, clrBlack, maxa * k * k);
        }
     }
  }

// ---------------- text and icons
void UiText(const int X, const int Y, const string t, const color c, const int size, const string font, const uint align)
  {
   if(!UiOk || t == "")
      return;
   string s = LangTr(t);                            // 2.80: Persian when chosen
   int X2 = X;
   uint al = align;
   if(UiMirror)                                     // right to left: mirrored place, left and right alignment swapped
     {
      X2 = UiAx - X;
      uint hz = align & (uint)(TA_CENTER | TA_RIGHT);
      al = align & ~((uint)(TA_CENTER | TA_RIGHT));
      if(hz == (uint)TA_CENTER)
         al |= TA_CENTER;
      else if(hz != (uint)TA_RIGHT)
         al |= TA_RIGHT;
     }
   UiCv.FontSet(UiFontName(font), -(int)MathRound(MathMax(size, 8) * 10 * UiZoom), UiFontFlags(font));   // 2.90: chosen font, 8 pt at least
   if(UiClipOn)
     {
      int th = UiCv.TextHeight(s);
      int top = ((al & TA_VCENTER) == TA_VCENTER) ? Y - th / 2 : (((al & TA_BOTTOM) == TA_BOTTOM) ? Y - th : Y);
      if(top < UiCy0 || top + th - 1 > UiCy1)
         return;                                   // text is shown whole or not at all
     }
   UiCv.TextOut(X2 - UiOx, Y - UiOy, s, ColorToARGB(c, 255), al);
  }

// chevron centred at (X, Y): pointing down (section open) or right (folded)
void UiChevron(const int X, const int Y, const int s, const bool down, const color c)
  {
   if(!UiOk || (UiClipOn && (Y - s < UiCy0 || Y + s > UiCy1)))
      return;
   int x = (UiMirror ? UiAx - X : X) - UiOx, y = Y - UiOy;
   int sg = UiMirror ? -1 : 1;                     // folded: points the other way in a mirror
   uint a = ColorToARGB(c, 255);
   for(int k = 0; k < 2; k++)
     {
      if(down)
        {
         UiCv.LineAA(x - s, y - s / 2 + k, x, y + s / 2 + k, a);
         UiCv.LineAA(x, y + s / 2 + k, x + s, y - s / 2 + k, a);
        }
      else
        {
         UiCv.LineAA(x - sg * (s / 2) + k, y - s, x + sg * (s / 2) + k, y, a);
         UiCv.LineAA(x + sg * (s / 2) + k, y, x - sg * (s / 2) + k, y + s, a);
        }
     }
  }

// "–" or "+" of `s` half-length, 2 px thick, centred at (X, Y)
void UiPlusMinus(const int X, const int Y, const int s, const bool plus, const color c)
  {
   UiFill(X - s, Y - 1, 2 * s, 2, c);
   if(plus)
      UiFill(X - 1, Y - s, 2, 2 * s, c);
  }

// check mark centred at (X, Y), half-size s
void UiCheck(const int X, const int Y, const int s, const color c)
  {
   if(!UiOk || (UiClipOn && (Y - s < UiCy0 || Y + s > UiCy1)))
      return;
   int x = (UiMirror ? UiAx - X : X) - UiOx, y = Y - UiOy;
   uint a = ColorToARGB(c, 255);
   for(int k = 0; k < 2; k++)
     {
      UiCv.LineAA(x - s, y + k, x - s / 3, y + s * 2 / 3 + k, a);
      UiCv.LineAA(x - s / 3, y + s * 2 / 3 + k, x + s, y - s * 2 / 3 + k, a);
     }
  }

// sun (the light theme) or moon (the dark theme), centred at (X, Y), radius r; `bg` cuts the moon's crescent
void UiSunMoon(const int X, const int Y, const int r, const bool sun, const color c, const color bg)
  {
   if(!UiOk)
      return;
   if(sun)
     {
      UiCircle(X, Y, r * 5 / 9, c);
      int fx = (UiMirror ? UiAx - X : X) - UiOx, fy = Y - UiOy;
      uint a = ColorToARGB(c, 255);
      for(int k = 0; k < 8; k++)
        {
         double an = k * M_PI / 4.0;
         int x1 = fx + (int)MathRound(MathCos(an) * r * 0.80), y1 = fy + (int)MathRound(MathSin(an) * r * 0.80);
         int x2 = fx + (int)MathRound(MathCos(an) * r * 1.10), y2 = fy + (int)MathRound(MathSin(an) * r * 1.10);
         UiCv.LineAA(x1, y1, x2, y2, a);
        }
     }
   else
     {
      UiCircle(X, Y, r * 4 / 5, c);
      UiCircle(X + r * 2 / 5, Y - r * 3 / 10, r * 7 / 10, bg);
     }
  }

// ---------------- clickable zones (chart coordinates)
void UiZone(const string id, const int X0, const int Y0, const int w0, const int h0, const string tip)
  {
   int X = UiFx(X0, w0), Y = Y0, w = w0, h = h0;
   if(UiClipOn)                                     // only the visible part of a zone can be clicked
     {
      int x2 = MathMin(X + w, UiCx1 + 1), y2 = MathMin(Y + h, UiCy1 + 1);
      X = MathMax(X, UiCx0);
      Y = MathMax(Y, UiCy0);
      w = x2 - X;
      h = y2 - Y;
      if(w <= 0 || h <= 0)
         return;
     }
   if(UiZn >= ArraySize(UiZid))
     {
      int n = UiZn + 32;
      ArrayResize(UiZid, n); ArrayResize(UiZtip, n);
      ArrayResize(UiZx, n); ArrayResize(UiZy, n); ArrayResize(UiZw, n); ArrayResize(UiZh, n);
     }
   UiZid[UiZn] = id;
   UiZtip[UiZn] = tip;
   UiZx[UiZn] = X;
   UiZy[UiZn] = Y;
   UiZw[UiZn] = w;
   UiZh[UiZn] = h;
   UiZn++;
  }

int UiHitIndex(const int mx, const int my)
  {
   for(int i = UiZn - 1; i >= 0; i--)
      if(mx >= UiZx[i] && mx < UiZx[i] + UiZw[i] && my >= UiZy[i] && my < UiZy[i] + UiZh[i])
         return i;
   return -1;
  }

string UiHit(const int mx, const int my)
  {
   int i = UiHitIndex(mx, my);
   return i >= 0 ? UiZid[i] : "";
  }

string UiTipAt(const int mx, const int my)
  {
   int i = UiHitIndex(mx, my);
   return i >= 0 ? UiZtip[i] : "";
  }
//+------------------------------------------------------------------+
