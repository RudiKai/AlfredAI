//+------------------------------------------------------------------+
//|                       AlfredSupDemCore™                         |
//|      Structural Supply/Demand zone generator for Alfred Suite    |
//|                (FIXED: Self-Contained Version)                   |
//+------------------------------------------------------------------+
#property indicator_chart_window
#property strict
#property indicator_buffers 1
#property indicator_plots   1
#property indicator_type1   DRAW_NONE
#property indicator_label1  "AlfredSupDemCore™"

#include <AlfredSettings.mqh>
// #include <AlfredInit.mqh> // Removed for self-containment

SAlfred Alfred;


double zoneBuffer[];

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
   Alfred.supdemRefreshRateSeconds   = 30;
   Alfred.supdemEnableBreakoutRemoval= true;
   Alfred.supdemRequireBodyClose     = true;
   Alfred.supdemEnableTimeDecay      = true;
   Alfred.supdemTimeDecayBars        = 20;
   Alfred.supdemEnableMagnetForecast = true;
   // --- End: Manually set defaults ---

   // set up dummy buffer
   SetIndexBuffer(0, zoneBuffer, INDICATOR_DATA);
   ArrayInitialize(zoneBuffer, EMPTY_VALUE);

   // timer for dynamic redraw
   EventSetTimer(Alfred.supdemRefreshRateSeconds);

   return(INIT_SUCCEEDED);
}

//+------------------------------------------------------------------+
//| Helper: Draw or update one “magnet” projection line              |
//+------------------------------------------------------------------+
void CalculateMagnetProjection(string zoneName, ENUM_TIMEFRAMES tf)
{
   if(ObjectFind(0, zoneName) < 0) 
      return;

   // midpoint of the zone
   double p1   = ObjectGetDouble(0, zoneName, OBJPROP_PRICE, 0);
   double p2   = ObjectGetDouble(0, zoneName, OBJPROP_PRICE, 1);
   double mid  = (p1 + p2) / 2.0;

   // time anchor
   datetime t1 = iTime(_Symbol, tf, 1);
   datetime t2 = iTime(_Symbol, tf, 4);

   // pick color by zone type & timeframe
   color c;
   if(StringFind(zoneName, "DZone_LTF") >= 0)
      c = Alfred.supdemDemandColorLTF;
   else if(StringFind(zoneName, "DZone") >= 0)
      c = Alfred.supdemDemandColorHTF;
   else if(StringFind(zoneName, "SZone_LTF") >= 0)
      c = Alfred.supdemSupplyColorLTF;
   else
      c = Alfred.supdemSupplyColorHTF;

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
//| Deinitialization                                                 |
//+------------------------------------------------------------------+
void OnDeinit(const int reason)
{
   EventKillTimer();
   // delete all zone & magnet objects
   string del[] = {
      "DZone_LTF","SZone_LTF",
      "DZone_M15","SZone_M15",
      "DZone_M30","SZone_M30",
      "DZone_H1","SZone_H1",
      "DZone_H2","SZone_H2",
      "DZone_H4","SZone_H4",
      "DZone_D1","SZone_D1"
   };
   for(int i=0; i<ArraySize(del); i++)
      ObjectDelete(0, del[i]);

   // also remove any magnet lines
   int total = ObjectsTotal(0);
   for(int i=total-1; i>=0; i--)
   {
      string name = ObjectName(0, i);
      if(StringFind(name,"MagnetLine_") == 0)
         ObjectDelete(0, name);
   }
}

//+------------------------------------------------------------------+
//| Timer and Chart-Change → redraw                                  |
//+------------------------------------------------------------------+
void OnTimer()
{
   DrawAllZones();
   if(Alfred.supdemEnableMagnetForecast)
      DrawMagnetLine();
}

void OnChartEvent(const int id,const long &l,const double &d,const string &s)
{
   if(id==CHARTEVENT_CHART_CHANGE)
   {
      DrawAllZones();
      if(Alfred.supdemEnableMagnetForecast)
         DrawMagnetLine();
   }
}

//+------------------------------------------------------------------+
//| Draw all zones for each timeframe                                |
//+------------------------------------------------------------------+
void DrawAllZones()
{
   // LTF zones
   DrawZones(_Period,      "LTF", Alfred.supdemDemandColorLTF, Alfred.supdemSupplyColorLTF, true);
   DrawZones(PERIOD_M15,   "M15", Alfred.supdemDemandColorLTF, Alfred.supdemSupplyColorLTF, true);
   DrawZones(PERIOD_M30,   "M30", Alfred.supdemDemandColorLTF, Alfred.supdemSupplyColorLTF, true);

   // HTF zones
   DrawZones(PERIOD_H1,    "H1",  Alfred.supdemDemandColorHTF, Alfred.supdemSupplyColorHTF, false);
   DrawZones(PERIOD_H2,    "H2",  Alfred.supdemDemandColorHTF, Alfred.supdemSupplyColorHTF, false);
   DrawZones(PERIOD_H4,    "H4",  Alfred.supdemDemandColorHTF, Alfred.supdemSupplyColorHTF, false);
   DrawZones(PERIOD_D1,    "D1",  Alfred.supdemDemandColorHTF, Alfred.supdemSupplyColorHTF, false);
}

//+------------------------------------------------------------------+
//| Draw one supply/demand rectangle                                 |
//+------------------------------------------------------------------+
void DrawZones(ENUM_TIMEFRAMES tf,
               string          suffix,
               color           clrD,
               color           clrS,
               bool            isLTF)
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
      if(ok) DrawRect("DZone_" + suffix, t0, highP, extT, lowP, clrD, isLTF);
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
      if(ok) DrawRect("SZone_" + suffix, t0, lowP, extT, highP, clrS, isLTF);
      else   ObjectDelete(0, "SZone_" + suffix);
   }
}

//+------------------------------------------------------------------+
//| Rectangle drawer                                                 |
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
   ObjectSetInteger(0,name,OBJPROP_BGCOLOR, ColorToARGB(clr,255));
   ObjectSetInteger(0,name,OBJPROP_FILL,    !borderOnly);
   ObjectSetInteger(0,name,OBJPROP_WIDTH,   borderOnly?3:1);
   ObjectSetInteger(0,name,OBJPROP_BACK,    true);
}

//+------------------------------------------------------------------+
//| Zone “breakout” detection                                        |
//+------------------------------------------------------------------+
bool IsZoneBroken(ENUM_TIMEFRAMES tf,
                  datetime        tBase,
                  double          hiP,
                  double          loP,
                  bool            isDemand)
{
   if(!Alfred.supdemEnableBreakoutRemoval)
      return false;

   int total     = Bars(_Symbol, tf);
   int shift     = iBarShift(_Symbol, tf, tBase, false);
   int checkBars = MathMin(Alfred.supdemZoneDurationBars, total - shift);

   for(int i=0; i<checkBars; i++)
   {
      double price = Alfred.supdemRequireBodyClose
                     ? iClose(_Symbol, tf, shift + i)
                     : SymbolInfoDouble(_Symbol, SYMBOL_BID);

      if( isDemand && price < loP ) return true;
      if(!isDemand && price > hiP ) return true;
   }
   return false;
}

//+------------------------------------------------------------------+
//| Time‐decay cleanup                                               |
//+------------------------------------------------------------------+
bool IsZoneExpired(ENUM_TIMEFRAMES tf, datetime tBase)
{
   if(!Alfred.supdemEnableTimeDecay)
      return false;

   int cs = iBarShift(_Symbol, tf, TimeCurrent(), false);
   int bs = iBarShift(_Symbol, tf, tBase,       false);
   return (cs - bs) >= Alfred.supdemTimeDecayBars;
}

//+------------------------------------------------------------------+
//| Convert timeframe to seconds                                     |
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
//| Draw combined magnet forecast                                   |
//+------------------------------------------------------------------+
void DrawMagnetLine()
{
   // project strongest Demand & Supply zones
   string dZones[] = {"DZone_LTF","DZone_H1","DZone_H4","DZone_D1"};
   string sZones[] = {"SZone_LTF","SZone_H1","SZone_H4","SZone_D1"};

   for(int i=0; i< ArraySize(dZones); i++)
      CalculateMagnetProjection(dZones[i], (i<2 ? _Period : (i==2?PERIOD_H4:PERIOD_D1)));

   for(int i=0; i< ArraySize(sZones); i++)
      CalculateMagnetProjection(sZones[i], (i<2 ? _Period : (i==2?PERIOD_H4:PERIOD_D1)));
}

//+------------------------------------------------------------------+
//| Dummy OnCalculate to satisfy MT5                                |
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
   // redraw every tick
   DrawAllZones();
   if(Alfred.supdemEnableMagnetForecast)
      DrawMagnetLine();

   return(rates_total);
}
//+------------------------------------------------------------------+
