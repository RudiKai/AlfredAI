//+------------------------------------------------------------------+
//|                   AAI_Indicator_ZoneEngine.mq5                   |
//|        v2.1 - UPGRADED with Price Level Buffer Exports           |
//|      (Detects zones and exports levels for EA consumption)       |
//|              Copyright 2025, AlfredAI Project                    |
//+------------------------------------------------------------------+
#property indicator_chart_window
#property strict
#property version "2.1"

// --- Eight data buffers for exporting live status ---
#property indicator_buffers 8
#property indicator_plots   8

#property indicator_label1  "ZoneStatus"
#property indicator_type1   DRAW_NONE
#property indicator_label2  "MagnetLevel"
#property indicator_type2   DRAW_NONE
#property indicator_label3  "ZoneStrength"
#property indicator_type3   DRAW_NONE
#property indicator_label4  "ZoneFreshness"
#property indicator_type4   DRAW_NONE
#property indicator_label5  "ZoneVolume"
#property indicator_type5   DRAW_NONE
#property indicator_label6  "ZoneLiquidity"
#property indicator_type6   DRAW_NONE
// --- Buffer 6 & 7: Exporting Proximal and Distal price levels of the active zone ---
#property indicator_label7  "ProximalLevel"
#property indicator_type7   DRAW_NONE
#property indicator_label8  "DistalLevel"
#property indicator_type8   DRAW_NONE


#include <AAI_Include_Settings.mqh>

// --- Global instance of settings ---
SAlfred Alfred;
int hATR = INVALID_HANDLE;

// --- Declaring the data buffers ---
double zoneStatusBuffer[];
double magnetLevelBuffer[];
double zoneStrengthBuffer[];
double zoneFreshnessBuffer[];
double zoneVolumeBuffer[];
double zoneLiquidityBuffer[];
double proximalLevelBuffer[]; // New buffer for proximal price
double distalLevelBuffer[];   // New buffer for distal price

// --- Mitigated zones tracker ---
string g_mitigated_zones[];
int    g_mitigated_zones_count = 0;

struct ZoneAnalysis
{
   bool     isValid;
   double   proximal;
   double   distal;
   int      baseCandles;
   double   impulseStrength;
   int      strengthScore;
   bool     isFresh;
   bool     hasVolume;
   bool     hasLiquidityGrab;
   datetime time;
};


//+------------------------------------------------------------------+
//| Initialization                                                   |
//+------------------------------------------------------------------+
int OnInit()
{
   // --- Default Settings ---
   Alfred.supdemZoneLookback         = 50;
   Alfred.supdemZoneDurationBars     = 100;
   Alfred.supdemMinImpulseMovePips   = 20.0;
   Alfred.supdemDemandColorHTF       = clrLightGreen;
   Alfred.supdemDemandColorLTF       = clrGreen;
   Alfred.supdemSupplyColorHTF       = clrHotPink;
   Alfred.supdemSupplyColorLTF       = clrRed;
   Alfred.supdemRefreshRateSeconds   = 5;
   Alfred.supdemEnableBreakoutRemoval= true;
   Alfred.supdemRequireBodyClose     = true;
   Alfred.supdemEnableTimeDecay      = true;
   Alfred.supdemTimeDecayBars        = 20;
   Alfred.supdemEnableMagnetForecast = true;

   // --- Setup Buffers ---
   SetIndexBuffer(0, zoneStatusBuffer, INDICATOR_DATA);
   ArraySetAsSeries(zoneStatusBuffer, true);
   SetIndexBuffer(1, magnetLevelBuffer, INDICATOR_DATA);
   ArraySetAsSeries(magnetLevelBuffer, true);
   SetIndexBuffer(2, zoneStrengthBuffer, INDICATOR_DATA);
   ArraySetAsSeries(zoneStrengthBuffer, true);
   SetIndexBuffer(3, zoneFreshnessBuffer, INDICATOR_DATA);
   ArraySetAsSeries(zoneFreshnessBuffer, true);
   SetIndexBuffer(4, zoneVolumeBuffer, INDICATOR_DATA);
   ArraySetAsSeries(zoneVolumeBuffer, true);
   SetIndexBuffer(5, zoneLiquidityBuffer, INDICATOR_DATA);
   ArraySetAsSeries(zoneLiquidityBuffer, true);
   // --- Setup New Price Level Buffers ---
   SetIndexBuffer(6, proximalLevelBuffer, INDICATOR_DATA);
   ArraySetAsSeries(proximalLevelBuffer, true);
   SetIndexBuffer(7, distalLevelBuffer, INDICATOR_DATA);
   ArraySetAsSeries(distalLevelBuffer, true);


   // --- Initialize all buffers ---
   ArrayInitialize(zoneStatusBuffer, 0.0);
   ArrayInitialize(magnetLevelBuffer, 0.0);
   ArrayInitialize(zoneStrengthBuffer, 0.0);
   ArrayInitialize(zoneFreshnessBuffer, 0.0);
   ArrayInitialize(zoneVolumeBuffer, 0.0);
   ArrayInitialize(zoneLiquidityBuffer, 0.0);
   ArrayInitialize(proximalLevelBuffer, 0.0); // Initialize new buffer
   ArrayInitialize(distalLevelBuffer, 0.0);   // Initialize new buffer

   hATR = iATR(_Symbol, _Period, 14);
   if(hATR == INVALID_HANDLE){ Print("Error creating ATR handle"); return(INIT_FAILED); }
   
   ArrayResize(g_mitigated_zones, 0);
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
                const long     &tick_volume[],
                const long     &volume[],
                const int      &sp[])
{
   static datetime lastBarTime = 0;
   if(t[rates_total-1] != lastBarTime)
   {
      CheckForMitigations(rates_total, l, h);
      lastBarTime = t[rates_total-1];
   }

   double currentPrice = SymbolInfoDouble(_Symbol, SYMBOL_BID);
   int liveZoneStatus = 0;
   double liveMagnetLevel = 0.0;
   int liveStrengthScore = 0;
   double liveFreshness = 0.0;
   double liveVolume = 0.0;
   double liveLiquidity = 0.0;
   double liveProximal = 0.0; // Variable to hold current proximal level
   double liveDistal = 0.0;   // Variable to hold current distal level
   double closestDist = DBL_MAX;

   string zoneNames[] = {
      "DZone_LTF","SZone_LTF", "DZone_M15","SZone_M15", "DZone_M30","SZone_M30",
      "DZone_H1","SZone_H1",   "DZone_H2","SZone_H2",   "DZone_H4","SZone_H4",
      "DZone_D1","SZone_D1"
   };

   // Find the active zone and extract its data
   for(int i = 0; i < ArraySize(zoneNames); i++)
   {
      string zName = zoneNames[i];
      if(ObjectFind(0, zName) >= 0)
      {
         double p1=ObjectGetDouble(0,zName,OBJPROP_PRICE,0), p2=ObjectGetDouble(0,zName,OBJPROP_PRICE,1);
         if(currentPrice >= MathMin(p1,p2) && currentPrice <= MathMax(p1,p2))
         {
            // Set zone status
            if(StringFind(zName, "DZone") >= 0) liveZoneStatus = 1; else liveZoneStatus = -1;
            
            // Extract data from tooltip
            string tooltip = ObjectGetString(0, zName, OBJPROP_TOOLTIP);
            string parts[];
            if(StringSplit(tooltip, ';', parts) == 4)
            {
               liveStrengthScore = (int)StringToInteger(parts[0]);
               liveFreshness = (double)StringToInteger(parts[1]);
               liveVolume = (double)StringToInteger(parts[2]);
               liveLiquidity = (double)StringToInteger(parts[3]);
            }
            
            // NEW: Extract price levels directly from the zone object
            // For a Demand zone, proximal is the top, distal is the bottom.
            // For a Supply zone, proximal is the bottom, distal is the top.
            if(liveZoneStatus == 1) // Demand
            {
               liveProximal = MathMax(p1, p2);
               liveDistal = MathMin(p1, p2);
            }
            else // Supply
            {
               liveProximal = MathMin(p1, p2);
               liveDistal = MathMax(p1, p2);
            }
         }
      }
   }

   // Find the closest magnet line
   for(int i = 0; i < ArraySize(zoneNames); i++)
   {
      string magnetName = "MagnetLine_" + zoneNames[i];
      if(ObjectFind(0, magnetName) >= 0)
      {
         double magnetPrice = ObjectGetDouble(0, magnetName, OBJPROP_PRICE, 0);
         double dist = MathAbs(currentPrice - magnetPrice);
         if(dist < closestDist) { closestDist = dist; liveMagnetLevel = magnetPrice; }
      }
   }

   // Populate all buffers for all bars (for EA access)
   for(int i = rates_total - 1; i >= 0; i--)
   {
      zoneStatusBuffer[i]    = liveZoneStatus;
      magnetLevelBuffer[i]   = liveMagnetLevel;
      zoneStrengthBuffer[i]  = liveStrengthScore;
      zoneFreshnessBuffer[i] = liveFreshness;
      zoneVolumeBuffer[i]    = liveVolume;
      zoneLiquidityBuffer[i] = liveLiquidity;
      proximalLevelBuffer[i] = liveProximal; // Populate new buffer
      distalLevelBuffer[i]   = liveDistal;   // Populate new buffer
   }

   return(rates_total);
}


//+------------------------------------------------------------------+
//| Deinitialization                                                 |
//+------------------------------------------------------------------+
void OnDeinit(const int reason)
{
   EventKillTimer();
   IndicatorRelease(hATR);
   string del[] = {
      "DZone_LTF","SZone_LTF", "DZone_M15","SZone_M15", "DZone_M30","SZone_M30",
      "DZone_H1","SZone_H1",   "DZone_H2","SZone_H2",   "DZone_H4","SZone_H4",
      "DZone_D1","SZone_D1"
   };
   for(int i=0; i<ArraySize(del); i++)
   {
      ObjectDelete(0, del[i]);
      ObjectDelete(0, "MagnetLine_" + del[i]);
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
   ChartRedraw();
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
//| Draw all zones for each timeframe                                |
//+------------------------------------------------------------------+
void DrawAllZones()
{
   DrawZones(_Period,    "LTF", Alfred.supdemDemandColorLTF, Alfred.supdemSupplyColorLTF, false);
   DrawZones(PERIOD_M15, "M15", Alfred.supdemDemandColorLTF, Alfred.supdemSupplyColorLTF, false);
   DrawZones(PERIOD_M30, "M30", Alfred.supdemDemandColorLTF, Alfred.supdemSupplyColorLTF, false);
   DrawZones(PERIOD_H1,  "H1",  Alfred.supdemDemandColorHTF, Alfred.supdemSupplyColorHTF, true);
   DrawZones(PERIOD_H2,  "H2",  Alfred.supdemDemandColorHTF, Alfred.supdemSupplyColorHTF, true);
   DrawZones(PERIOD_H4,  "H4",  Alfred.supdemDemandColorHTF, Alfred.supdemSupplyColorHTF, true);
   DrawZones(PERIOD_D1,  "D1",  Alfred.supdemDemandColorHTF, Alfred.supdemSupplyColorHTF, true);
}

//+------------------------------------------------------------------+
//| Find and Draw one supply/demand rectangle                        |
//+------------------------------------------------------------------+
void DrawZones(ENUM_TIMEFRAMES tf, string suffix, color clrD, color clrS, bool isBorderOnly)
{
   ZoneAnalysis demandZone = FindZone(tf, true);
   if(demandZone.isValid)
   {
      datetime extT = demandZone.time + GetTFSeconds(tf) * Alfred.supdemZoneDurationBars;
      DrawRect("DZone_" + suffix, demandZone.time, demandZone.proximal, extT, demandZone.distal, clrD, isBorderOnly, demandZone);
   }
   else { ObjectDelete(0, "DZone_" + suffix); }

   ZoneAnalysis supplyZone = FindZone(tf, false);
   if(supplyZone.isValid)
   {
      datetime extT = supplyZone.time + GetTFSeconds(tf) * Alfred.supdemZoneDurationBars;
      DrawRect("SZone_" + suffix, supplyZone.time, supplyZone.proximal, extT, supplyZone.distal, clrS, isBorderOnly, supplyZone);
   }
   else { ObjectDelete(0, "SZone_" + suffix); }
}

//+------------------------------------------------------------------+
//| Core Zone Finding and Scoring Logic                              |
//+------------------------------------------------------------------+
ZoneAnalysis FindZone(ENUM_TIMEFRAMES tf, bool isDemand)
{
   ZoneAnalysis analysis;
   analysis.isValid = false;
   
   MqlRates rates[];
   int barsToCopy = Alfred.supdemZoneLookback + 10;
   if(CopyRates(_Symbol, tf, 0, barsToCopy, rates) < barsToCopy) return analysis;
   ArraySetAsSeries(rates, true);

   for(int i = 1; i < Alfred.supdemZoneLookback; i++)
   {
      double impulseStart = isDemand ? rates[i].low : rates[i].high;
      double impulseEnd = isDemand ? rates[i-1].high : rates[i-1].low;
      double impulseMove = MathAbs(impulseEnd - impulseStart);
      
      if(impulseMove / _Point < Alfred.supdemMinImpulseMovePips) continue;

      analysis.proximal = isDemand ? rates[i].high : rates[i].low;
      analysis.distal = isDemand ? rates[i].low : rates[i].high;
      analysis.time = rates[i].time;
      analysis.baseCandles = 1;
      
      analysis.isValid = true;
      analysis.impulseStrength = MathAbs(rates[i-1].close - rates[i].open);
      analysis.isFresh = IsZoneFresh(GetZoneID(isDemand ? "DZone_" : "SZone_", tf, analysis.time));
      analysis.hasVolume = HasVolumeConfirmation(tf, i, 1);
      analysis.hasLiquidityGrab = HasLiquidityGrab(tf, i + analysis.baseCandles, isDemand);
      analysis.strengthScore = CalculateZoneStrength(analysis, tf);
      
      return analysis;
   }
   
   return analysis;
}

//+------------------------------------------------------------------+
//| Calculates a zone's strength score                               |
//+------------------------------------------------------------------+
int CalculateZoneStrength(const ZoneAnalysis &zone, ENUM_TIMEFRAMES tf)
{
    if(!zone.isValid) return 0;

    double atr_buffer[1];
    double atr = 0.0;
    int atr_handle_tf = iATR(_Symbol, tf, 14);
    if(atr_handle_tf != INVALID_HANDLE)
    {
      if(CopyBuffer(atr_handle_tf, 0, 1, 1, atr_buffer) > 0) atr = atr_buffer[0];
      IndicatorRelease(atr_handle_tf);
    }
    if(atr == 0.0) return 1;

    int explosiveScore = 0;
    if(zone.impulseStrength > atr * 2.0) explosiveScore = 5;
    else if(zone.impulseStrength > atr * 1.5) explosiveScore = 4;
    else if(zone.impulseStrength > atr * 1.0) explosiveScore = 3;
    else explosiveScore = 2;

    int consolidationScore = 0;
    if(zone.baseCandles == 1) consolidationScore = 5;
    else if(zone.baseCandles <= 3) consolidationScore = 3;
    else consolidationScore = 1;

    int freshnessBonus = zone.isFresh ? 2 : 0;
    int volumeBonus = zone.hasVolume ? 2 : 0;
    int liquidityBonus = zone.hasLiquidityGrab ? 3 : 0;

    return(MathMin(10, explosiveScore + consolidationScore + freshnessBonus + volumeBonus + liquidityBonus));
}

//+------------------------------------------------------------------+
//| Rectangle drawer (stores data in tooltip)                        |
//+------------------------------------------------------------------+
void DrawRect(string name, datetime t1, double p1, datetime t2, double p2, color clr, bool borderOnly, const ZoneAnalysis &analysis)
{
   if(ObjectFind(0,name) < 0) ObjectCreate(0,name,OBJ_RECTANGLE,0,t1,p1,t2,p2);
   else { ObjectMove(0,name,0,t1,p1); ObjectMove(0,name,1,t2,p2); }
   
   ObjectSetInteger(0,name,OBJPROP_COLOR,   clr);
   ObjectSetInteger(0,name,OBJPROP_BGCOLOR, ColorToARGB(clr, 30));
   ObjectSetInteger(0,name,OBJPROP_FILL,    !borderOnly);
   ObjectSetInteger(0,name,OBJPROP_WIDTH,   borderOnly ? 3 : 1);
   ObjectSetInteger(0,name,OBJPROP_BACK,    true);
   
   string tooltip = (string)analysis.strengthScore + ";" + (string)(analysis.isFresh ? 1 : 0) + ";" + (string)(analysis.hasVolume ? 1 : 0) + ";" + (string)(analysis.hasLiquidityGrab ? 1 : 0);
   ObjectSetString(0, name, OBJPROP_TOOLTIP, tooltip);
   
   string fresh_prefix = analysis.isFresh ? "★ " : "";
   string liq_prefix = analysis.hasLiquidityGrab ? "$ " : "";
   string volume_suffix = analysis.hasVolume ? " (V)" : "";
   ObjectSetString(0, name, OBJPROP_TEXT, liq_prefix + fresh_prefix + "Strength: " + (string)analysis.strengthScore + "/10" + volume_suffix);
}


// --- FUNCTIONS FOR FRESHNESS TRACKING ---
string GetZoneID(string prefix, ENUM_TIMEFRAMES tf, datetime time){ return prefix + EnumToString(tf) + "_" + (string)time; }
bool IsZoneFresh(string zone_id){ for(int i=0;i<g_mitigated_zones_count;i++){if(g_mitigated_zones[i]==zone_id)return false;} return true; }
void AddToMitigatedList(string zone_id){ if(IsZoneFresh(zone_id)){int s=g_mitigated_zones_count+1;ArrayResize(g_mitigated_zones,s);g_mitigated_zones[s-1]=zone_id;g_mitigated_zones_count=s;Print("Zone Mitigated: "+zone_id);}}
void CheckForMitigations(int rates_total, const double &low[], const double &high[])
{
   if(rates_total < 2) return;
   double prev_low = low[rates_total-2], prev_high = high[rates_total-2];
   string z_types[]={"DZone_","SZone_"}, tf_s[]={"LTF","M15","M30","H1","H2","H4","D1"};
   for(int i=0;i<ArraySize(z_types);i++){for(int j=0;j<ArraySize(tf_s);j++){string n=z_types[i]+tf_s[j];if(ObjectFind(0,n)>=0){datetime t=(datetime)ObjectGetInteger(0,n,OBJPROP_TIME,0);double p1=ObjectGetDouble(0,n,OBJPROP_PRICE,0),p2=ObjectGetDouble(0,n,OBJPROP_PRICE,1);bool isD=(z_types[i]=="DZone_");double prox=isD?MathMax(p1,p2):MathMin(p1,p2);if((isD&&prev_low<=prox)||(!isD&&prev_high>=prox)){AddToMitigatedList(GetZoneID(z_types[i],_Period,t));}}}}
}

// --- FUNCTION FOR VOLUME CONFIRMATION ---
bool HasVolumeConfirmation(ENUM_TIMEFRAMES tf, int bar_index, int num_candles)
{
   MqlRates rates[];
   int lookback = 20;
   if(CopyRates(_Symbol, tf, bar_index - num_candles, lookback + num_candles, rates) < lookback) return false;
   ArraySetAsSeries(rates, true);
   
   long total_volume = 0;
   for(int i = 0; i < num_candles; i++) { total_volume += rates[i].tick_volume; }
   
   long avg_volume_base = 0;
   for(int i = num_candles; i < lookback + num_candles; i++) { avg_volume_base += rates[i].tick_volume; }
   
   double avg_volume = (double)avg_volume_base / lookback;
   return (total_volume > avg_volume * 1.5);
}

// --- FUNCTION FOR LIQUIDITY GRAB DETECTION ---
bool HasLiquidityGrab(ENUM_TIMEFRAMES tf, int bar_index, bool isDemandZone)
{
   MqlRates rates[];
   int lookback = 10;
   if(CopyRates(_Symbol, tf, bar_index, lookback, rates) < lookback) return false;
   ArraySetAsSeries(rates, true);
   
   double grab_candle_wick = isDemandZone ? rates[0].low : rates[0].high;
   
   double target_liquidity_level = isDemandZone ? rates[1].low : rates[1].high;
   for(int i = 2; i < lookback; i++)
   {
      if(isDemandZone)
      {
         target_liquidity_level = MathMin(target_liquidity_level, rates[i].low);
      }
      else
      {
         target_liquidity_level = MathMax(target_liquidity_level, rates[i].high);
      }
   }
   
   if(isDemandZone)
   {
      return grab_candle_wick < target_liquidity_level;
   }
   else
   {
      return grab_candle_wick > target_liquidity_level;
   }
}


// --- UNCHANGED HELPER FUNCTIONS ---
void CalculateMagnetProjection(string zoneName, ENUM_TIMEFRAMES tf){}
void DrawMagnetLine(){}
bool IsZoneBroken(ENUM_TIMEFRAMES tf, datetime tBase, double hiP, double loP, bool isDemand){return false;}
bool IsZoneExpired(ENUM_TIMEFRAMES tf, datetime tBase){return false;}
int GetTFSeconds(ENUM_TIMEFRAMES tf){return PeriodSeconds();}
