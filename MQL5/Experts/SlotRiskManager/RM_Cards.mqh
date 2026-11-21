//+------------------------------------------------------------------+
//| RM_Cards.mqh - read the analysis engine's card levels             |
//| File written by the engine (one way):                             |
//|   <Terminal>\Common\Files\US30Analyzer\cards.csv                  |
//| card_no;direction;zone_tf;stage;zone_low;zone_high;refined_low;   |
//| refined_high;bos_level;bos_origin;liquidity;invalidation;         |
//| created_utc;price                                                 |
//+------------------------------------------------------------------+

struct RmCard
  {
   bool     found;
   int      no;
   bool     buy;
   string   tf;
   string   stage;
   double   zone_low, zone_high;
   double   ref_low, ref_high;
   double   bos_level, bos_origin;
   double   liquidity, invalidation;
   string   created;
   double   price;
  };

double RmNum(const string s)
  {
   string t = s;
   StringTrimLeft(t);
   StringTrimRight(t);
   if(t == "")
      return 0.0;
   return StringToDouble(t);
  }

// looks up card `no` in the engine's file; found=false when the file or the card is missing
RmCard RmReadCard(const string folder, const int no, string &err)
  {
   RmCard c;
   c.found = false;
   c.no = no;
   c.buy = true;
   c.tf = "";
   c.stage = "";
   c.zone_low = 0; c.zone_high = 0; c.ref_low = 0; c.ref_high = 0;
   c.bos_level = 0; c.bos_origin = 0; c.liquidity = 0; c.invalidation = 0;
   c.created = "";
   c.price = 0;
   err = "";
   string path = folder + "\\cards.csv";
   int h = FileOpen(path, FILE_READ | FILE_TXT | FILE_ANSI | FILE_COMMON | FILE_SHARE_READ | FILE_SHARE_WRITE);
   if(h == INVALID_HANDLE)
     {
      err = "cards file not found (is the engine running on this PC?)";
      return c;
     }
   ushort sep = StringGetCharacter(";", 0);
   while(!FileIsEnding(h))
     {
      string line = FileReadString(h);
      string p[];
      int n = StringSplit(line, sep, p);
      if(n < 14 || p[0] == "card_no")
         continue;
      if((int)StringToInteger(p[0]) != no)
         continue;
      c.found = true;
      c.buy = (p[1] == "buy");
      c.tf = p[2];
      c.stage = p[3];
      c.zone_low = RmNum(p[4]);
      c.zone_high = RmNum(p[5]);
      c.ref_low = RmNum(p[6]);
      c.ref_high = RmNum(p[7]);
      c.bos_level = RmNum(p[8]);
      c.bos_origin = RmNum(p[9]);
      c.liquidity = RmNum(p[10]);
      c.invalidation = RmNum(p[11]);
      c.created = p[12];
      c.price = RmNum(p[13]);
      break;
     }
   FileClose(h);
   if(!c.found)
      err = "card #A" + IntegerToString(no) + " is not in the engine's file (older than the last 40 cards?)";
   return c;
  }
//+------------------------------------------------------------------+
