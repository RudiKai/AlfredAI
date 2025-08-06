//+------------------------------------------------------------------+
//|                           AlfredHUD™                             |
//|                            v1.10 (Export Buffers)                |
//| (MODIFIED: Added export buffers for multi-TF zone status)        |
//+------------------------------------------------------------------+
#property indicator_chart_window
#property strict

// --- MODIFICATION: Increased buffer count for data export ---
#property indicator_buffers 6 // 1 dummy + 5 for TF zones
#property indicator_plots   6

// --- Original dummy buffer ---
#property indicator_type1   DRAW_NONE
#property indicator_label1  "AlfredHUD™"
double dummyBuffer[];

// --- MODIFICATION: Added buffers for each timeframe's zone status ---
#property indicator_type2   DRAW_NONE
#property indicator_label2  "H4_Zone"
double h4ZoneBuffer[];

#property indicator_type3   DRAW_NONE
#property indicator_label3  "H2_Zone"
double h2ZoneBuffer[];

#property indicator_type4   DRAW_NONE
#property indicator_label4  "H1_Zone"
double h1ZoneBuffer[];

#property indicator_type5   DRAW_NONE
#property indicator_label5  "M30_Zone"
double m30ZoneBuffer[];

#property indicator_type6   DRAW_NONE
#property indicator_label6  "M15_Zone"
double m15ZoneBuffer[];
// --- END MODIFICATION ---

#include <AlfredSettings.mqh>
#include <AlfredInit.mqh>

SAlfred Alfred;
int    maHandle = INVALID_HANDLE;

//--------------------------------------------------------------------
// Configuration
ENUM_TIMEFRAMES TFList[] = { PERIOD_H4, PERIOD_H2, PERIOD_H1, PERIOD_M30, PERIOD_M15 };

struct MagnetScore
{
   double total;
   double proximity;
   double width;
   double age;
   double midPrice;
};

//--------------------------------------------------------------------
// Helpers
//--------------------------------------------------------------------
string TFToString(ENUM_TIMEFRAMES tf)
{
   switch(tf)
   {
      case PERIOD_M15: return "M15";
      case PERIOD_M30: return "M30";
      case PERIOD_H1:  return "H1";
      case PERIOD_H2:  return "H2";
      case PERIOD_H4:  return "H4";
      default:         return "TF";
   }
}

int GetTFMinutes(ENUM_TIMEFRAMES tf)
{
   switch(tf)
   {
      case PERIOD_M15: return 15;
      case PERIOD_M30: return 30;
      case PERIOD_H1:  return 60;
      case PERIOD_H2:  return 120;
      case PERIOD_H4:  return 240;
      default:         return 60;
   }
}

double GetVelocityPerMinute()
{
   int    bars     = 10;
   double total    = 0.0;
   for(int i = 1; i <= bars; i++)
      total += MathAbs(iClose(_Symbol, _Period, i) - iClose(_Symbol, _Period, i + 1)) / _Point;
   double avg      = total / bars;
   double tfMin    = GetTFMinutes(_Period);
   return (tfMin > 0) ? (avg / tfMin) : 0.0;
}

string EstimateETA(double targetPrice)
{
   if(targetPrice == EMPTY_VALUE) return "Offline";
   double dist     = MathAbs(SymbolInfoDouble(_Symbol, SYMBOL_BID) - targetPrice) / _Point;
   double velocity = GetVelocityPerMinute();
   if(velocity < 0.0001) return "Offline";
   int etaMins = (int)MathCeil(dist / velocity);
   return "~" + IntegerToString(etaMins) + "m";
}

color StrengthColor(string label)
{
   if(label == "Very Weak")   return clrGray;
   if(label == "Weak")        return clrSilver;
   if(label == "Neutral")     return clrKhaki;
   if(label == "Strong")      return clrAquamarine;
   if(label == "Very Strong") return clrLime;
   return clrWhite;
}

string ScoreToLabel(double score)
{
   if(score < 50)   return "Very Weak";
   if(score < 150)  return "Weak";
   if(score < 250)  return "Neutral";
   if(score < 350)  return "Strong";
   return "Very Strong";
}

MagnetScore GetZoneScore(string objName)
{
   MagnetScore s = { -DBL_MAX, 0, 0, 0, EMPTY_VALUE };
   if(ObjectFind(0, objName) >= 0)
   {
      double p1 = ObjectGetDouble(0, objName, OBJPROP_PRICE, 0);
      double p2 = ObjectGetDouble(0, objName, OBJPROP_PRICE, 1);
      s.midPrice  = (p1 + p2) / 2.0;
      double bid  = SymbolInfoDouble(_Symbol, SYMBOL_BID);
      s.proximity = 1000 - MathAbs(bid - s.midPrice) / _Point;
      s.width     = 200  - MathAbs(p1 - p2)   / _Point;
      datetime zt = (datetime)ObjectGetInteger(0, objName, OBJPROP_TIME, 0);
      s.age       = MathMax(0.0, (TimeCurrent() - zt) / 60.0);
      double ageF = MathMax(1.0, s.age / 60.0);
      s.total     = s.proximity + s.width - ageF;
   }
   return s;
}

double GetTFMagnet(ENUM_TIMEFRAMES tf, string &direction, string &strength, string &eta)
{
   string tfStr    = TFToString(tf);
   string dName    = "DZone_" + tfStr;
   string sName    = "SZone_" + tfStr;
   MagnetScore sd  = GetZoneScore(dName);
   MagnetScore ss  = GetZoneScore(sName);
   bool useDemand  = (sd.total >= ss.total);
   MagnetScore pick= useDemand ? sd : ss;
   direction       = useDemand ? "🟢 Demand" : "🔴 Supply";
   strength        = ScoreToLabel(pick.total);
   eta             = EstimateETA(pick.midPrice);
   if(Alfred.enableHUDDiagnostics)
      eta += StringFormat(" (Score:%.0f Prox:%.0f Wid:%.0f Age:%.0f)",
                          pick.total, pick.proximity, pick.width, pick.age);
   return pick.midPrice;
}

string GetCompassBias(string magnetDirection, double slope)
{
   int bars = 5, upC = 0, downC = 0;
   for(int i = 1; i <= bars; i++)
   {
      double cNow  = iClose(_Symbol, _Period, i);
      double cPrev = iClose(_Symbol, _Period, i + 1);
      if(cNow > cPrev) upC++;
      if(cNow < cPrev) downC++;
   }
   string biasDir = "→", biasStr = "Neutral";
   if(slope > 0.0003 || upC >= 4)       { biasDir = "↑"; biasStr = "Strong Buy"; }
   else if(slope < -0.0003 || downC >= 4){ biasDir = "↓"; biasStr = "Strong Sell"; }
   bool aligned = (biasDir=="↑" && magnetDirection=="🟢 Demand") ||
                  (biasDir=="↓" && magnetDirection=="🔴 Supply");
   string alignStr = aligned ? "Aligned with Magnet" : "Diverging from Magnet";
   return "📍 Compass: " + biasDir + " " + biasStr + " [" + alignStr + "]";
}

//+------------------------------------------------------------------+
//| Initialization                                                   |
//+------------------------------------------------------------------+
int OnInit()
{
   // --- MODIFICATION: Initialize SAlfred struct ---
   // This ensures the struct is usable even without the include file.
   // A more robust solution would be a centralized settings manager.
   Alfred.enableHUD = true;
   Alfred.hudCorner = CORNER_LEFT_LOWER;
   Alfred.hudXOffset = 10;
   Alfred.hudYOffset = 10;
   Alfred.fontSize = 10;
   Alfred.enableHUDDiagnostics = false;
   // --- END MODIFICATION ---

   // --- MODIFICATION: Set up all indicator buffers ---
   SetIndexBuffer(0, dummyBuffer, INDICATOR_DATA);
   SetIndexBuffer(1, h4ZoneBuffer, INDICATOR_DATA);
   SetIndexBuffer(2, h2ZoneBuffer, INDICATOR_DATA);
   SetIndexBuffer(3, h1ZoneBuffer, INDICATOR_DATA);
   SetIndexBuffer(4, m30ZoneBuffer, INDICATOR_DATA);
   SetIndexBuffer(5, m15ZoneBuffer, INDICATOR_DATA);

   ArrayInitialize(dummyBuffer, EMPTY_VALUE);
   ArrayInitialize(h4ZoneBuffer, 0.0);
   ArrayInitialize(h2ZoneBuffer, 0.0);
   ArrayInitialize(h1ZoneBuffer, 0.0);
   ArrayInitialize(m30ZoneBuffer, 0.0);
   ArrayInitialize(m15ZoneBuffer, 0.0);
   // --- END MODIFICATION ---

   // create MA handle
   maHandle = iMA(_Symbol, _Period, 8, 0, MODE_SMA, PRICE_CLOSE);
   if(maHandle == INVALID_HANDLE)
      return(INIT_FAILED);

   return(INIT_SUCCEEDED);
}

//+------------------------------------------------------------------+
//| Main HUD Loop                                                    |
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
   // --- MODIFICATION: Populate the export buffers on every tick ---
   int bar_index = rates_total - 1;
   if(bar_index < 0) return rates_total;

   // Check each timeframe and set the buffer value
   h4ZoneBuffer[bar_index]  = (ObjectFind(0, "DZone_H4") >= 0 || ObjectFind(0, "SZone_H4") >= 0) ? 1.0 : 0.0;
   h2ZoneBuffer[bar_index]  = (ObjectFind(0, "DZone_H2") >= 0 || ObjectFind(0, "SZone_H2") >= 0) ? 1.0 : 0.0;
   h1ZoneBuffer[bar_index]  = (ObjectFind(0, "DZone_H1") >= 0 || ObjectFind(0, "SZone_H1") >= 0) ? 1.0 : 0.0;
   m30ZoneBuffer[bar_index] = (ObjectFind(0, "DZone_M30") >= 0 || ObjectFind(0, "SZone_M30") >= 0) ? 1.0 : 0.0;
   m15ZoneBuffer[bar_index] = (ObjectFind(0, "DZone_M15") >= 0 || ObjectFind(0, "SZone_M15") >= 0) ? 1.0 : 0.0;
   // --- END MODIFICATION ---

   if(!Alfred.enableHUD)
      return(rates_total);

   // fetch slope once
   double maArr[2], slope = 0.0;
   if(CopyBuffer(maHandle, 0, 0, 2, maArr) == 2)
      slope = maArr[0] - maArr[1];

   int lineHeight = Alfred.fontSize + 5;

   // draw each TF line (Original visual logic remains unchanged)
   for(int i = 0; i < ArraySize(TFList); i++)
   {
      ENUM_TIMEFRAMES tf   = TFList[i];
      string          tfLbl = TFToString(tf);
      string          dir, str, eta;
      GetTFMagnet(tf, dir, str, eta);

      string compass = GetCompassBias(dir, slope);

      string display = tfLbl + ": " + dir + " [" + str + "] " + eta + "\n" + compass;
      string objName = "AlfredHUD_" + tfLbl;

      if(ObjectFind(0, objName) < 0)
         ObjectCreate(0, objName, OBJ_LABEL, 0, 0, 0);

      ObjectSetInteger(0, objName, OBJPROP_CORNER,    Alfred.hudCorner);
      ObjectSetInteger(0, objName, OBJPROP_XDISTANCE, Alfred.hudXOffset);
      ObjectSetInteger(0, objName, OBJPROP_YDISTANCE, Alfred.hudYOffset + i * lineHeight);
      ObjectSetInteger(0, objName, OBJPROP_FONTSIZE,  Alfred.fontSize);
      ObjectSetInteger(0, objName, OBJPROP_COLOR,     StrengthColor(str));
      ObjectSetString(0, objName, OBJPROP_TEXT,       display);
   }

   // draw footer
   string footerObj  = "AlfredHUD_Footer";
   string footerText = "🧲 AlfredHUD™ → " + _Symbol;
   int footerOffset  = Alfred.hudYOffset + ArraySize(TFList) * lineHeight + 6;

   if(ObjectFind(0, footerObj) < 0)
      ObjectCreate(0, footerObj, OBJ_LABEL, 0, 0, 0);

   ObjectSetInteger(0, footerObj, OBJPROP_CORNER,    Alfred.hudCorner);
   ObjectSetInteger(0, footerObj, OBJPROP_XDISTANCE, Alfred.hudXOffset);
   ObjectSetInteger(0, footerObj, OBJPROP_YDISTANCE, footerOffset);
   ObjectSetInteger(0, footerObj, OBJPROP_FONTSIZE,  Alfred.fontSize);
   ObjectSetInteger(0, footerObj, OBJPROP_COLOR,     clrDodgerBlue);
   ObjectSetString(0, footerObj, OBJPROP_TEXT,       footerText);

   return(rates_total);
}
//+------------------------------------------------------------------+
