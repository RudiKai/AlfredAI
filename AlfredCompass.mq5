//+------------------------------------------------------------------+
//|                           AlfredCompass™                         |
//|                            v1.00                                 |
//|                (FIXED: Self-Contained Version)                   |
//+------------------------------------------------------------------+
#property indicator_chart_window
#property strict
#property indicator_buffers 1
#property indicator_plots   1
#property indicator_type1   DRAW_NONE
#property indicator_label1  "AlfredCompass™"

#include <AlfredSettings.mqh>
// #include <AlfredInit.mqh> // Removed for self-containment

SAlfred Alfred;
double dummyBuffer[];

// reference timeframes
ENUM_TIMEFRAMES TFList[] = { PERIOD_M15, PERIOD_H1, PERIOD_H4 };

//+------------------------------------------------------------------+
//| Initialization                                                   |
//+------------------------------------------------------------------+
int OnInit()
{
   // --- Start: Manually set defaults (replaces InitAlfredDefaults) ---
   Alfred.enableCompass              = true;
   Alfred.compassYOffset             = 20;
   Alfred.fontSize                   = 12;
   // --- End: Manually set defaults ---

   SetIndexBuffer(0, dummyBuffer, INDICATOR_DATA);
   ArrayInitialize(dummyBuffer, EMPTY_VALUE);
   return(INIT_SUCCEEDED);
}

//+------------------------------------------------------------------+
//| Main iteration                                                  |
//+------------------------------------------------------------------+
int OnCalculate(const int rates_total,
                const int prev_calculated,
                const datetime &time[],
                const double   &open[],
                const double   &high[],
                const double   &low[],
                const double   &close[],
                const long     &tick_volume[],
                const long     &volume[],
                const int      &spread[])
{
   if(!Alfred.enableCompass)
      return(rates_total);

   // get magnet direction from SupDemCore
   string magnetDir = GetMagnetDirection();

   // get compass bias
   string arrow, biasText;
   bool conflict = false;
   int  confidence = GetCompassBias(magnetDir, arrow, biasText, conflict);

   // color by strength/conflict
   string strengthLbl = WeightToLabel(confidence/5);
   color  fontColor   = StrengthColor(strengthLbl);
   if(conflict) fontColor = clrRed;

   // time/price anchors
   datetime t     = iTime(_Symbol, _Period, 0);
   double   price = SymbolInfoDouble(_Symbol, SYMBOL_BID);

   // draw arrow
   string arrowObj = "CompassArrowObj";
   if(ObjectFind(0, arrowObj) < 0)
      ObjectCreate(0, arrowObj, OBJ_TEXT, 0, t, price);
   ObjectSetInteger(0, arrowObj, OBJPROP_FONTSIZE, 18);
   ObjectSetInteger(0, arrowObj, OBJPROP_COLOR,     fontColor);
   ObjectSetString (0, arrowObj, OBJPROP_TEXT,      arrow);
   ObjectMove(0, arrowObj, 0, t, price + Alfred.compassYOffset * _Point);

   // draw label
   string labelObj = "CompassLabelObj";
   string labelTxt = biasText + " (" + IntegerToString(confidence) + "%)";
   if(ObjectFind(0, labelObj) < 0)
      ObjectCreate(0, labelObj, OBJ_TEXT, 0, t, price);
   ObjectSetInteger(0, labelObj, OBJPROP_FONTSIZE,  Alfred.fontSize);
   ObjectSetInteger(0, labelObj, OBJPROP_COLOR,     fontColor);
   ObjectSetString (0, labelObj, OBJPROP_TEXT,      labelTxt);
   ObjectMove(0, labelObj, 0, t, price + (Alfred.compassYOffset + 20) * _Point);

   // draw warning if conflicted
   string warnObj = "CompassConflictObj";
   if(conflict)
   {
      if(ObjectFind(0, warnObj) < 0)
         ObjectCreate(0, warnObj, OBJ_TEXT, 0, t, price);
      ObjectSetInteger(0, warnObj, OBJPROP_FONTSIZE, 10);
      ObjectSetInteger(0, warnObj, OBJPROP_COLOR,    clrRed);
      ObjectSetString (0, warnObj, OBJPROP_TEXT,     "⚠️ Conflict with MagnetHUD");
      ObjectMove(0, warnObj, 0, t, price + (Alfred.compassYOffset + 38) * _Point);
   }
   else if(ObjectFind(0, warnObj) >= 0)
      ObjectDelete(0, warnObj);

   return(rates_total);
}

//+------------------------------------------------------------------+
//| Calculate Multi-TF bias                                          |
//+------------------------------------------------------------------+
int GetCompassBias(string magnetDir,
                   string &arrow,
                   string &biasText,
                   bool   &conflict)
{
   int buy = 0, sell = 0;
   for(int i = 0; i < ArraySize(TFList); i++)
   {
      ENUM_TIMEFRAMES tf = TFList[i];
      double slope = iMA(_Symbol, tf, 8, 3, MODE_SMA, PRICE_CLOSE)
                   - iMA(_Symbol, tf, 8, 0, MODE_SMA, PRICE_CLOSE);

      int upC = 0, downC = 0;
      for(int j = 1; j <= 5; j++)
      {
         double cNow  = iClose(_Symbol, tf, j);
         double cPrev = iClose(_Symbol, tf, j+1);
         if(cNow > cPrev) upC++;
         if(cNow < cPrev) downC++;
      }

      if(slope > 0.0003 || upC >= 4)      buy++;
      if(slope < -0.0003|| downC >= 4)     sell++;
   }

   int confidence = 50;
   arrow        = "→";
   biasText     = "Neutral";
   conflict     = false;

   if(buy > sell)
   {
      arrow      = "↑";
      biasText   = "Multi-TF Buy";
      confidence = MathMin(70 + buy * 5, 100);
      conflict   = (magnetDir == "🔴 Supply");
   }
   else if(sell > buy)
   {
      arrow      = "↓";
      biasText   = "Multi-TF Sell";
      confidence = MathMin(70 + sell * 5, 100);
      conflict   = (magnetDir == "🟢 Demand");
   }

   return(confidence);
}

//+------------------------------------------------------------------+
//| Grab Magnet direction from SupDemCore                            |
//+------------------------------------------------------------------+
string GetMagnetDirection()
{
   string d,s,e;
   GetTFMagnet(PERIOD_H1, d, s, e);
   return(d);
}

//+------------------------------------------------------------------+
//| Zone reader (as in SupDemCore)                                   |
//+------------------------------------------------------------------+
double GetTFMagnet(ENUM_TIMEFRAMES tf,
                   string &direction,
                   string &strength,
                   string &eta)
{
   string dZones[] = {"DZone_LTF","DZone_H1","DZone_H4","DZone_D1"};
   string sZones[] = {"SZone_LTF","SZone_H1","SZone_H4","SZone_D1"};
   double scoreD=-DBL_MAX, scoreS=-DBL_MAX, bestD=EMPTY_VALUE, bestS=EMPTY_VALUE;

   for(int i=0; i<ArraySize(dZones); i++)
   {
      string z = dZones[i];
      if(ObjectFind(0,z) < 0) continue;
      double p1 = ObjectGetDouble(0,z,OBJPROP_PRICE,0);
      double p2 = ObjectGetDouble(0,z,OBJPROP_PRICE,1);
      double mid = (p1+p2)/2;
      double sc  = 1000 - MathAbs(SymbolInfoDouble(_Symbol,SYMBOL_BID)-mid)/_Point
                      - MathAbs(p1-p2)/_Point;
      if(sc > scoreD) { scoreD=sc; bestD=mid; }
   }

   for(int i=0; i<ArraySize(sZones); i++)
   {
      string z = sZones[i];
      if(ObjectFind(0,z) < 0) continue;
      double p1 = ObjectGetDouble(0,z,OBJPROP_PRICE,0);
      double p2 = ObjectGetDouble(0,z,OBJPROP_PRICE,1);
      double mid = (p1+p2)/2;
      double sc  = 1000 - MathAbs(SymbolInfoDouble(_Symbol,SYMBOL_BID)-mid)/_Point
                      - MathAbs(p1-p2)/_Point;
      if(sc > scoreS) { scoreS=sc; bestS=mid; }
   }

   bool useD = (scoreD >= scoreS);
   direction    = useD ? "🟢 Demand" : "🔴 Supply";
   strength     = "";
   eta          = "~";
   return(useD ? bestD : bestS);
}

//+------------------------------------------------------------------+
//| Map confidence to label                                          |
//+------------------------------------------------------------------+
string WeightToLabel(int w)
{
   if(w <= 5)  return "Very Weak";
   if(w <= 10) return "Weak";
   if(w <= 15) return "Neutral";
   if(w <= 20) return "Strong";
               return "Very Strong";
}

//+------------------------------------------------------------------+
//| Map label to color                                              |
//+------------------------------------------------------------------+
color StrengthColor(string label)
{
   if(label=="Very Weak")   return clrGray;
   if(label=="Weak")        return clrSilver;
   if(label=="Neutral")     return clrKhaki;
   if(label=="Strong")      return clrAquamarine;
   if(label=="Very Strong") return clrLime;
   return clrWhite;
}
