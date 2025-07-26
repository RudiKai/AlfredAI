//+------------------------------------------------------------------+
//|                       AlfredAlertCenter™                         |
//|                            v1.00                                 |
//+------------------------------------------------------------------+
#property indicator_chart_window
#property strict
#property indicator_buffers 1
#property indicator_plots   1
#property indicator_type1   DRAW_NONE
#property indicator_label1  "AlfredAlertCenter™"

#include <AlfredSettings.mqh>
#include <AlfredInit.mqh>

double dummyBuffer[];
string lastBias = "Neutral";

//+------------------------------------------------------------------+
//| Initialization                                                   |
//+------------------------------------------------------------------+
int OnInit()
{
   InitAlfredDefaults();
   SetIndexBuffer(0, dummyBuffer, INDICATOR_DATA);
   ArrayInitialize(dummyBuffer, EMPTY_VALUE);
   return(INIT_SUCCEEDED);
}

//+------------------------------------------------------------------+
//| Main iteration                                                   |
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
   if(!Alfred.enableAlertCenter)
      return(rates_total);

   string magnetDir = GetMagnetDirection();
   string arrow, biasText;
   bool   conflict = false;
   int    confidence = GetCompassBias(magnetDir, arrow, biasText, conflict);

   // Strong Bias Aligned
   if(Alfred.alertStrongBiasAligned
      && confidence >= Alfred.alertConfidenceThreshold
      && !conflict)
      TriggerAlert("Strong Bias Aligned: " + biasText +
                   " (" + IntegerToString(confidence) + "%)");

   // Divergence Detected
   if(Alfred.alertDivergence && conflict)
      TriggerAlert("Divergence Detected: Compass vs MagnetHUD");

   // Zone Entry Confirmed
   if(Alfred.alertZoneEntry
      && IsInsideZone()
      && confidence >= Alfred.alertConfidenceThreshold)
      TriggerAlert("Zone Entry Confirmed: Price inside zone");

   // Bias Flip Detected
   if(Alfred.alertBiasFlip
      && biasText != lastBias
      && lastBias != "Neutral")
      TriggerAlert("Bias Flip Detected: " + lastBias +
                   " → " + biasText);

   lastBias = biasText;
   return(rates_total);
}

//+------------------------------------------------------------------+
//| Dispatch an alert on–screen & in log                             |
//+------------------------------------------------------------------+
void TriggerAlert(string msg)
{
   Print("🔔 AlfredAlertCenter: ", msg);

   string obj   = "AlertLabel_" + IntegerToString(TimeLocal());
   double price = SymbolInfoDouble(_Symbol, SYMBOL_BID);
   datetime t   = iTime(_Symbol, _Period, 0);

   ObjectCreate(0, obj, OBJ_TEXT, 0, t, price);
   ObjectSetInteger(0, obj, OBJPROP_FONTSIZE, 10);
   ObjectSetInteger(0, obj, OBJPROP_COLOR,    clrOrangeRed);
   ObjectSetString (0, obj, OBJPROP_TEXT,     msg);
   ObjectMove      (0, obj, 0, t, price + 30 * _Point);

if(Alfred.sendTelegram)
{
   // TODO: call your Telegram API here
}

if(Alfred.sendWhatsApp)
{
   // TODO: call your WhatsApp API here
}
}

//+------------------------------------------------------------------+
//| Multi-TF compass scanner                                         |
//+------------------------------------------------------------------+
int GetCompassBias(string magnetDir,
                   string &arrow,
                   string &biasText,
                   bool   &conflict)
{
   ENUM_TIMEFRAMES TFList[] = { PERIOD_M15, PERIOD_H1, PERIOD_H4 };
   int buy = 0, sell = 0;

   for(int i = 0; i < ArraySize(TFList); i++)
   {
      ENUM_TIMEFRAMES tf = TFList[i];
      double slope = iMA(_Symbol, tf, 8, 3, MODE_SMA, PRICE_CLOSE)
                   - iMA(_Symbol, tf, 8, 0, MODE_SMA, PRICE_CLOSE);

      int upC=0, downC=0;
      for(int j=1; j<=5; j++)
      {
         double cNow  = iClose(_Symbol, tf, j);
         double cPrev = iClose(_Symbol, tf, j+1);
         if(cNow > cPrev) upC++;
         if(cNow < cPrev) downC++;
      }

      if(slope > 0.0003 || upC >= 4) buy++;
      if(slope < -0.0003|| downC >= 4) sell++;
   }

   int confidence = 50;
   arrow        = "→";
   biasText     = "Neutral";
   conflict     = false;

   if(buy > sell)
   {
      arrow      = "↑";
      biasText   = "Buy";
      confidence = MathMin(70 + buy * 5, 100);
      conflict   = (magnetDir == "🔴 Supply");
   }
   else if(sell > buy)
   {
      arrow      = "↓";
      biasText   = "Sell";
      confidence = MathMin(70 + sell * 5, 100);
      conflict   = (magnetDir == "🟢 Demand");
   }

   return(confidence);
}

//+------------------------------------------------------------------+
//| MagnetHUD direction (from SupDemCore)                           |
//+------------------------------------------------------------------+
string GetMagnetDirection()
{
   string d,s,e;
   GetTFMagnet(PERIOD_H1, d, s, e);
   return(d);
}

//+------------------------------------------------------------------+
//| Zone-inside check                                                |
//+------------------------------------------------------------------+
bool IsInsideZone()
{
   string zones[] = {
      "DZone_LTF","DZone_H1","DZone_H4","DZone_D1",
      "SZone_LTF","SZone_H1","SZone_H4","SZone_D1"
   };
   double bid = SymbolInfoDouble(_Symbol, SYMBOL_BID);

   for(int i=0; i<ArraySize(zones); i++)
   {
      string z = zones[i];
      if(ObjectFind(0, z) < 0) continue;
      double p1 = ObjectGetDouble(0, z, OBJPROP_PRICE, 0);
      double p2 = ObjectGetDouble(0, z, OBJPROP_PRICE, 1);
      if(bid >= MathMin(p1,p2) && bid <= MathMax(p1,p2))
         return(true);
   }
   return(false);
}

//+------------------------------------------------------------------+
//| SupDemCore zone reader                                           |
//+------------------------------------------------------------------+
double GetTFMagnet(ENUM_TIMEFRAMES tf,
                   string &direction,
                   string &strength,
                   string &eta)
{
   string dZones[] = {"DZone_LTF","DZone_H1","DZone_H4","DZone_D1"};
   string sZones[] = {"SZone_LTF","SZone_H1","SZone_H4","SZone_D1"};
   double scoreD = -DBL_MAX, scoreS = -DBL_MAX, bestD=EMPTY_VALUE, bestS=EMPTY_VALUE;

   for(int i=0; i<ArraySize(dZones); i++)
   {
      string z = dZones[i];
      if(ObjectFind(0,z) < 0) continue;
      double p1 = ObjectGetDouble(0,z,OBJPROP_PRICE,0);
      double p2 = ObjectGetDouble(0,z,OBJPROP_PRICE,1);
      double mid= (p1+p2)/2;
      double sc = 1000 - MathAbs(SymbolInfoDouble(_Symbol,SYMBOL_BID)-mid)/_Point
                     - MathAbs(p1-p2)/_Point;
      if(sc > scoreD) { scoreD = sc; bestD = mid; }
   }

   for(int i=0; i<ArraySize(sZones); i++)
   {
      string z = sZones[i];
      if(ObjectFind(0,z) < 0) continue;
      double p1 = ObjectGetDouble(0,z,OBJPROP_PRICE,0);
      double p2 = ObjectGetDouble(0,z,OBJPROP_PRICE,1);
      double mid= (p1+p2)/2;
      double sc = 1000 - MathAbs(SymbolInfoDouble(_Symbol,SYMBOL_BID)-mid)/_Point
                     - MathAbs(p1-p2)/_Point;
      if(sc > scoreS) { scoreS = sc; bestS = mid; }
   }

   bool useD = (scoreD >= scoreS);
   direction = useD ? "🟢 Demand" : "🔴 Supply";
   strength  = "";
   eta       = "~";
   return(useD ? bestD : bestS);
}
