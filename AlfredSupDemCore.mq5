//+------------------------------------------------------------------+
//|                       AlfredSupDemCore™                         |
//|      Structural Supply/Demand zone generator for Alfred Suite    |
//|    (v1.1 REFINED: Added live data buffers for Pane integration)  |
//+------------------------------------------------------------------+
#property indicator_chart_window
#property strict
#property version "1.1"

// --- MODIFIED: Two data buffers for exporting live status ---
#property indicator_buffers 2
#property indicator_plots   2

// --- Buffer 0: Zone Status ---
// Exports 1 for Demand, -1 for Supply, 0 for None.
// Plot is not visible on the chart, but data is available in the Data Window.
#property indicator_label1  "ZoneStatus"
#property indicator_type1   DRAW_NONE
#property indicator_color1  clrNONE

// --- Buffer 1: Magnet Level ---
// Exports the price of the nearest magnet line.
// Plot is not visible on the chart, but data is available in the Data Window.
#property indicator_label2  "MagnetLevel"
#property indicator_type2   DRAW_NONE
#property indicator_color2  clrNONE


#include <AlfredSettings.mqh>
// #include <AlfredInit.mqh> // Removed for self-containment

// --- Global instance of settings ---
SAlfred Alfred;

// --- MODIFIED: Declaring the two data buffers ---
double zoneStatusBuffer[];   // Buffer for zone status (-1, 0, 1)
double magnetLevelBuffer[];  // Buffer for the nearest magnet price


//+------------------------------------------------------------------+
//| Initialization                                                   |
//+------------------------------------------------------------------+
int OnInit()
{
   // --- Start: Manually set defaults (replaces InitAlfredDefaults) ---
   Alfred.supdemZoneLookback         = 50;
   Alfred.supdemZoneDurationBars     = 100;
   Alfred.supdemMinImpulseMovePips   = 20.0;
   Alfred.supdemDemandColorHTF       = clrLightGreen;
   Alfred.supdemDemandColorLTF       = clrGreen;
   Alfred.supdemSupplyColorHTF       = clrHotPink;
   Alfred.supdemSupplyColorLTF       = clrRed;
   Alfred.supdemRefreshRateSeconds   = 5; // Refreshes visuals every 5 seconds
   Alfred.supdemEnableBreakoutRemoval= true;
   Alfred.supdemRequireBodyClose     = true;
   Alfred.supdemEnableTimeDecay      = true;
   Alfred.supdemTimeDecayBars        = 20;
   Alfred.supdemEnableMagnetForecast = true;
   // --- End: Manually set defaults ---

   // --- NEW: Set up the data buffers for export ---
   // Buffer 0: Zone Status
   SetIndexBuffer(0, zoneStatusBuffer, INDICATOR_DATA);
   PlotIndexSetString(0, PLOT_LABEL, "ZoneStatus"); // Set label for Data Window
   ArraySetAsSeries(zoneStatusBuffer, true);       // Set as series for correct indexing

   // Buffer 1: Magnet Level
   SetIndexBuffer(1, magnetLevelBuffer, INDICATOR_DATA);
   PlotIndexSetString(1, PLOT_LABEL, "MagnetLevel"); // Set label for Data Window
   ArraySetAsSeries(magnetLevelBuffer, true);        // Set as series for correct indexing

   // Initialize buffer values
   ArrayInitialize(magnetLevelBuffer, 0.0);
   ArrayInitialize(zoneStatusBuffer, 0.0);

   // Timer for dynamic redraw of visual objects (zones, magnets)
   EventSetTimer(Alfred.supdemRefreshRateSeconds);

   return(INIT_SUCCEEDED);
}

//+------------------------------------------------------------------+
//| Main Calculation: Updates buffers on every new tick              |
//+------------------------------------------------------------------+
int OnCalculate(const int rates_total,
                const int prev_calculated,
                const datetime &t[],
                const double   &o[],
                const double   &h[],
                const double   &l[],
                const double   &c[],
                const long     &tv[],
                const long     &v[],
                const int      &sp[])
{
   // --- START: NEW BUFFER CALCULATION LOGIC ---
   // This section runs on every tick to provide live data to the buffers.

   // 1. Get the current market price for calculations.
   double currentPrice = SymbolInfoDouble(_Symbol, SYMBOL_BID);

   // 2. Initialize variables for the current tick's status.
   int liveZoneStatus = 0;      // Default to 0 (no zone)
   double liveMagnetLevel = 0.0; // Default to 0.0
   double closestDist = DBL_MAX; // Used to find the nearest magnet

   // 3. Define all possible zone object names to check against.
   string zoneNames[] = {
      "DZone_LTF","SZone_LTF", "DZone_M15","SZone_M15", "DZone_M30","SZone_M30",
      "DZone_H1","SZone_H1",   "DZone_H2","SZone_H2",   "DZone_H4","SZone_H4",
      "DZone_D1","SZone_D1"
   };

   // 4. Check for current price interaction with any active zone.
   for(int i = 0; i < ArraySize(zoneNames); i++)
   {
      string zName = zoneNames[i];
      if(ObjectFind(0, zName) >= 0) // Check if the zone object exists
      {
         // Get the zone's price boundaries
         double p1 = ObjectGetDouble(0, zName, OBJPROP_PRICE, 0);
         double p2 = ObjectGetDouble(0, zName, OBJPROP_PRICE, 1);
         double top = MathMax(p1, p2);
         double bottom = MathMin(p1, p2);

         // If the current price is inside the zone's boundaries...
         if(currentPrice >= bottom && currentPrice <= top)
         {
            // ...set the status based on zone type (Demand or Supply).
            if(StringFind(zName, "DZone") >= 0) liveZoneStatus = 1;  // Demand
            else if(StringFind(zName, "SZone") >= 0) liveZoneStatus = -1; // Supply
         }
      }
   }

   // 5. Find the nearest magnet line to the current price.
   for(int i = 0; i < ArraySize(zoneNames); i++)
   {
      string zName = zoneNames[i];
      string magnetName = "MagnetLine_" + zName;
      if(ObjectFind(0, magnetName) >= 0) // Check if the magnet line object exists
      {
         // Get the magnet's price level
         double magnetPrice = ObjectGetDouble(0, magnetName, OBJPROP_PRICE, 0);
         double dist = MathAbs(currentPrice - magnetPrice);

         // If this magnet is closer than the last one found, update it.
         if(dist < closestDist)
         {
            closestDist = dist;
            liveMagnetLevel = magnetPrice;
         }
      }
   }

   // 6. Fill the entire buffer history with the new live values.
   // This ensures that any iCustom() call, regardless of the bar index,
   // receives the most up-to-date status.
   for(int i = rates_total - 1; i >= 0; i--)
   {
      zoneStatusBuffer[i] = liveZoneStatus;
      magnetLevelBuffer[i] = liveMagnetLevel;
   }

   // 7. Print debug information to the Experts log on each new tick.
   // This helps verify the buffer values in real-time.
   static datetime lastPrintTime = 0;
   if(TimeCurrent() != lastPrintTime) // Prevents flooding the log on historical calculations
   {
      PrintFormat("AlfredSupDemCore DEBUG | Time: %s | ZoneStatus: %d | MagnetLevel: %.5f",
                  TimeToString(TimeCurrent(), TIME_SECONDS),
                  liveZoneStatus,
                  liveMagnetLevel);
      lastPrintTime = TimeCurrent();
   }

   // --- END: NEW BUFFER CALCULATION LOGIC ---

   return(rates_total);
}


//+------------------------------------------------------------------+
//| Deinitialization                                                 |
//+------------------------------------------------------------------+
void OnDeinit(const int reason)
{
   EventKillTimer();
   // Delete all zone & magnet objects created by this indicator
   string del[] = {
      "DZone_LTF","SZone_LTF", "DZone_M15","SZone_M15",
      "DZone_M30","SZone_M30", "DZone_H1","SZone_H1",
      "DZone_H2","SZone_H2",   "DZone_H4","SZone_H4",
      "DZone_D1","SZone_D1"
   };
   for(int i=0; i<ArraySize(del); i++)
   {
      ObjectDelete(0, del[i]);
      ObjectDelete(0, "MagnetLine_" + del[i]); // Also remove associated magnet line
   }
   ChartRedraw();
}

//+------------------------------------------------------------------+
//| Timer: Redraws all visual objects periodically.                  |
//+------------------------------------------------------------------+
void OnTimer()
{
   DrawAllZones();
   if(Alfred.supdemEnableMagnetForecast)
      DrawMagnetLine();
   ChartRedraw(); // Force the chart to update with new/moved objects
}

//+------------------------------------------------------------------+
//| Chart Event: Redraws on manual chart changes.                    |
//+------------------------------------------------------------------+
void OnChartEvent(const int id,const long &l,const double &d,const string &s)
{
   if(id==CHARTEVENT_CHART_CHANGE)
   {
      DrawAllZones();
      if(Alfred.supdemEnableMagnetForecast)
         DrawMagnetLine();
      ChartRedraw();
   }
}

//+------------------------------------------------------------------+
//| Draw all zones for each timeframe (VISUALS UNCHANGED)            |
//+------------------------------------------------------------------+
void DrawAllZones()
{
   // LTF zones (filled, borderOnly=false)
   DrawZones(_Period,      "LTF", Alfred.supdemDemandColorLTF, Alfred.supdemSupplyColorLTF, false);
   DrawZones(PERIOD_M15,   "M15", Alfred.supdemDemandColorLTF, Alfred.supdemSupplyColorLTF, false);
   DrawZones(PERIOD_M30,   "M30", Alfred.supdemDemandColorLTF, Alfred.supdemSupplyColorLTF, false);

   // HTF zones (border only, borderOnly=true)
   DrawZones(PERIOD_H1,    "H1",  Alfred.supdemDemandColorHTF, Alfred.supdemSupplyColorHTF, true);
   DrawZones(PERIOD_H2,    "H2",  Alfred.supdemDemandColorHTF, Alfred.supdemSupplyColorHTF, true);
   DrawZones(PERIOD_H4,    "H4",  Alfred.supdemDemandColorHTF, Alfred.supdemSupplyColorHTF, true);
   DrawZones(PERIOD_D1,    "D1",  Alfred.supdemDemandColorHTF, Alfred.supdemSupplyColorHTF, true);
}

//+------------------------------------------------------------------+
//| Draw one supply/demand rectangle (LOGIC UNCHANGED)               |
//+------------------------------------------------------------------+
void DrawZones(ENUM_TIMEFRAMES tf,
               string          suffix,
               color           clrD,
               color           clrS,
               bool            isBorderOnly)
{
   datetime nowT  = iTime(_Symbol, tf, 0);
   int      tfSec = GetTFSeconds(tf);
   datetime extT  = nowT + tfSec * Alfred.supdemZoneDurationBars;

   // Demand
   int idxL = iLowest(_Symbol, tf, MODE_LOW, Alfred.supdemZoneLookback, 1);
   if(idxL >= 0)
   {
      datetime t0    = iTime(_Symbol, tf, idxL);
      double   lowP  = iLow (_Symbol, tf, idxL);
      double   highP = iHigh(_Symbol, tf, idxL);
      double   dist  = (SymbolInfoDouble(_Symbol,SYMBOL_BID) - highP)/_Point;

      bool ok = (dist >= Alfred.supdemMinImpulseMovePips)
                && (!Alfred.supdemEnableBreakoutRemoval || !IsZoneBroken(tf,t0,highP,lowP,true))
                && (!Alfred.supdemEnableTimeDecay     || !IsZoneExpired(tf,t0));
      if(ok) DrawRect("DZone_" + suffix, t0, highP, extT, lowP, clrD, isBorderOnly);
      else   ObjectDelete(0, "DZone_" + suffix);
   }

   // Supply
   int idxH = iHighest(_Symbol, tf, MODE_HIGH, Alfred.supdemZoneLookback, 1);
   if(idxH >= 0)
   {
      datetime t0    = iTime(_Symbol, tf, idxH);
      double   highP = iHigh(_Symbol, tf, idxH);
      double   lowP  = iLow (_Symbol, tf, idxH);
      double   dist  = (lowP - SymbolInfoDouble(_Symbol,SYMBOL_BID))/_Point;

      bool ok = (dist >= Alfred.supdemMinImpulseMovePips)
                && (!Alfred.supdemEnableBreakoutRemoval || !IsZoneBroken(tf,t0,highP,lowP,false))
                && (!Alfred.supdemEnableTimeDecay     || !IsZoneExpired(tf,t0));
      if(ok) DrawRect("SZone_" + suffix, t0, lowP, extT, highP, clrS, isBorderOnly);
      else   ObjectDelete(0, "SZone_" + suffix);
   }
}

//+------------------------------------------------------------------+
//| Rectangle drawer (VISUALS UNCHANGED)                             |
//+------------------------------------------------------------------+
void DrawRect(string name,
              datetime t1,
              double   p1,
              datetime t2,
              double   p2,
              color    clr,
              bool     borderOnly)
{
   if(ObjectFind(0,name) < 0)
      ObjectCreate(0,name,OBJ_RECTANGLE,0,t1,p1,t2,p2);
   else
   {
      ObjectMove(0,name,0,t1,p1);
      ObjectMove(0,name,1,t2,p2);
   }
   ObjectSetInteger(0,name,OBJPROP_COLOR,   clr);
   ObjectSetInteger(0,name,OBJPROP_BGCOLOR, ColorToARGB(clr, 30));
   ObjectSetInteger(0,name,OBJPROP_FILL,    !borderOnly);
   ObjectSetInteger(0,name,OBJPROP_WIDTH,   borderOnly ? 3 : 1);
   ObjectSetInteger(0,name,OBJPROP_BACK,    true);
}

//+------------------------------------------------------------------+
//| Helper: Draw or update one “magnet” projection line (UNCHANGED)  |
//+------------------------------------------------------------------+
void CalculateMagnetProjection(string zoneName, ENUM_TIMEFRAMES tf)
{
   if(ObjectFind(0, zoneName) < 0)
      return;

   double p1   = ObjectGetDouble(0, zoneName, OBJPROP_PRICE, 0);
   double p2   = ObjectGetDouble(0, zoneName, OBJPROP_PRICE, 1);
   double mid  = (p1 + p2) / 2.0;
   datetime t1 = iTime(_Symbol, tf, 1);
   datetime t2 = iTime(_Symbol, tf, 4);
   color c;
   if(StringFind(zoneName, "DZone_LTF") >= 0) c = Alfred.supdemDemandColorLTF;
   else if(StringFind(zoneName, "DZone") >= 0) c = Alfred.supdemDemandColorHTF;
   else if(StringFind(zoneName, "SZone_LTF") >= 0) c = Alfred.supdemSupplyColorLTF;
   else c = Alfred.supdemSupplyColorHTF;

   string obj = "MagnetLine_" + zoneName;
   if(ObjectFind(0, obj) < 0)
      ObjectCreate(0, obj, OBJ_TREND, 0, t1, mid, t2, mid);
   else
   {
      ObjectMove(0, obj, 0, t1, mid);
      ObjectMove(0, obj, 1, t2, mid);
   }
   ObjectSetInteger(0, obj, OBJPROP_COLOR, c);
   ObjectSetInteger(0, obj, OBJPROP_WIDTH, 2);
   ObjectSetInteger(0, obj, OBJPROP_STYLE, STYLE_DASH);
   ObjectSetString (0, obj, OBJPROP_TEXT, "Magnet → " + zoneName);
}

//+------------------------------------------------------------------+
//| Draw combined magnet forecast (UNCHANGED)                        |
//+------------------------------------------------------------------+
void DrawMagnetLine()
{
   string dZones[] = {"DZone_LTF","DZone_H1","DZone_H4","DZone_D1"};
   string sZones[] = {"SZone_LTF","SZone_H1","SZone_H4","SZone_D1"};

   for(int i=0; i< ArraySize(dZones); i++)
      CalculateMagnetProjection(dZones[i], (i<2 ? _Period : (i==2?PERIOD_H4:PERIOD_D1)));

   for(int i=0; i< ArraySize(sZones); i++)
      CalculateMagnetProjection(sZones[i], (i<2 ? _Period : (i==2?PERIOD_H4:PERIOD_D1)));
}

//+------------------------------------------------------------------+
//| Zone “breakout” detection (UNCHANGED)                            |
//+------------------------------------------------------------------+
bool IsZoneBroken(ENUM_TIMEFRAMES tf, datetime tBase, double hiP, double loP, bool isDemand)
{
   if(!Alfred.supdemEnableBreakoutRemoval) return false;
   int total = Bars(_Symbol, tf);
   int shift = iBarShift(_Symbol, tf, tBase, false);
   int checkBars = MathMin(Alfred.supdemZoneDurationBars, total - shift);
   for(int i=0; i<checkBars; i++)
   {
      double price = Alfred.supdemRequireBodyClose ? iClose(_Symbol, tf, shift + i) : SymbolInfoDouble(_Symbol, SYMBOL_BID);
      if( isDemand && price < loP ) return true;
      if(!isDemand && price > hiP ) return true;
   }
   return false;
}

//+------------------------------------------------------------------+
//| Time‐decay cleanup (UNCHANGED)                                   |
//+------------------------------------------------------------------+
bool IsZoneExpired(ENUM_TIMEFRAMES tf, datetime tBase)
{
   if(!Alfred.supdemEnableTimeDecay) return false;
   int cs = iBarShift(_Symbol, tf, TimeCurrent(), false);
   int bs = iBarShift(_Symbol, tf, tBase, false);
   return (cs - bs) >= Alfred.supdemTimeDecayBars;
}

//+------------------------------------------------------------------+
//| Convert timeframe to seconds (UNCHANGED)                         |
//+------------------------------------------------------------------+
int GetTFSeconds(ENUM_TIMEFRAMES tf)
{
   switch(tf)
   {
      case PERIOD_M1:  return 60;
      case PERIOD_M5:  return 300;
      case PERIOD_M15: return 900;
      case PERIOD_M30: return 1800;
      case PERIOD_H1:  return 3600;
      case PERIOD_H4:  return 14400;
      case PERIOD_D1:  return 86400;
      default:         return PeriodSeconds();
   }
}
//+------------------------------------------------------------------+
