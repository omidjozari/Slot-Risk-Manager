// ---------------- the engine: English phrases -> Persian, at word edges, longest first; cached
bool   LgOn = false;                                   // Persian on (set by the EA)
#define LG_CACHE 4096
string LgCk[LG_CACHE], LgCv[LG_CACHE];

void LgClear()
  {
   for(int i = 0; i < LG_CACHE; i++)
     {
      LgCk[i] = "";
      LgCv[i] = "";
     }
  }

bool LgAz(const ushort c) { return (c >= 'a' && c <= 'z') || (c >= 'A' && c <= 'Z'); }

// replaces `en` by `fa` where `en` stands as whole words (no letter right before / after it)
string LgReplace(const string s, const string en, const string fa)
  {
   int n = StringLen(s), m = StringLen(en);
   bool aw = LgAz(StringGetCharacter(en, 0)), zw = LgAz(StringGetCharacter(en, m - 1));
   string out = "";
   int from = 0;
   while(true)
     {
      int k = StringFind(s, en, from);
      if(k < 0)
         break;
      bool okl = !aw || k == 0 || !LgAz(StringGetCharacter(s, k - 1));
      bool okr = !zw || k + m >= n || !LgAz(StringGetCharacter(s, k + m));
      if(okl && okr)
        {
         out += StringSubstr(s, from, k - from) + fa;
         from = k + m;
        }
      else
        {
         out += StringSubstr(s, from, k - from + 1);
         from = k + 1;
        }
     }
   return out + StringSubstr(s, from);
  }

bool LgHasFa(const string s)
  {
   for(int i = StringLen(s) - 1; i >= 0; i--)
     {
      ushort c = StringGetCharacter(s, i);
      if(c >= 0x0600 && c <= 0x06FF)
         return true;
     }
   return false;
  }

uint LgHash(const string s)
  {
   uint h = 2166136261;
   for(int i = StringLen(s) - 1; i >= 0; i--)
     {
      h ^= StringGetCharacter(s, i);
      h *= 16777619;
     }
   return h;
  }

// Persian text without direction marks (fields, dialogs, phone messages, measuring)
string LangTrPlain(const string s)
  {
   if(!LgOn || s == "" || (!LgAz(StringGetCharacter(s, 0)) && StringFind(s, " ") < 0 && StringLen(s) < 3))
      return s;
   int k = (int)(LgHash(s) % LG_CACHE);
   if(LgCk[k] == s && LgCv[k] != "")
      return LgCv[k];
   string r = s;
   for(int i = 0; i < LG_N; i++)
      if(StringFind(r, LgEn[i]) >= 0)
         r = LgReplace(r, LgEn[i], LgFa[i]);
   StringReplace(r, "→", "←");
   LgCk[k] = s;
   LgCv[k] = r;
   return r;
  }

// Persian text drawn on the panel: a right-to-left run (RLE ... PDF), so numbers and Latin words sit where Persian puts them
string LangTr(const string s)
  {
   if(!LgOn || s == "")
      return s;
   if(StringGetCharacter(s, 0) == 0x202B)
      return s;
   string r = LangTrPlain(s);
   if(!LgHasFa(r))
      return r;
   return ShortToString(0x202B) + r + ShortToString(0x202C);
  }
//+------------------------------------------------------------------+
