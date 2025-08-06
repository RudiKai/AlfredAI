//+------------------------------------------------------------------+
//|                       AlfredSupDemCore™                         |
//|          v1.5 - UPGRADED with Liquidity Grab Engine              |
//| (Detects stop hunts to validate high-quality zones)              |
//+------------------------------------------------------------------+
#property indicator_chart_window
#property strict
#property version "1.5"

// --- UPGRADED: Six data buffers for exporting live status ---
#property indicator_buffers 6
#property indicator_plots   6

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
// --- NEW Buffer 5: Liquidity Grab Status (1=Confirmed, 0=Not) ---
#property indicator_label6  "ZoneLiquidity"
#property indicator_type6   DRAW_NONE


#include <AlfredSettings.mqh>

// --- Global instance of settings ---
SAlfred Alfred;
int hATR = INVALID_HANDLE;

// --- UPGRADED: Declaring the six data buffers ---
double zoneStatusBuffer[];
double magnetLevelBuffer[];
double zoneStrengthBuffer[];
double zoneFreshnessBuffer[];
double zoneVolumeBuffer[];
double zoneLiquidityBuffer[]; // NEW: Buffer for liquidity grab status

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
   bool     hasLiquidityGrab; // NEW: Flag for liquidity grab
   datetime time;
};


//+------------------------------------------------------------------+
//| Initialization                                                   |
//+------------------------------------------------------------------+
int OnInit()
{
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
   // --- NEW: Set up the liquidity buffer ---
   SetIndexBuffer(5, zoneLiquidityBuffer, INDICATOR_DATA);
   ArraySetAsSeries(zoneLiquidityBuffer, true);

   ArrayInitialize(zoneStatusBuffer, 0.0);
   ArrayInitialize(magnetLevelBuffer, 0.0);
   ArrayInitialize(zoneStrengthBuffer, 0.0);
   ArrayInitialize(zoneFreshnessBuffer, 0.0);
   ArrayInitialize(zoneVolumeBuffer, 0.0);
   ArrayInitialize(zoneLiquidityBuffer, 0.0); // Default to no grab

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
   double liveLiquidity = 0.0; // NEW
   double closestDist = DBL_MAX;

   string zoneNames[] = {
      "DZone_LTF","SZone_LTF", "DZone_M15","SZone_M15", "DZone_M30","SZone_M30",
      "DZone_H1","SZone_H1",   "DZone_H2","SZone_H2",   "DZone_H4","SZone_H4",
      "DZone_D1","SZone_D1"
   };

   for(int i = 0; i < ArraySize(zoneNames); i++)
   {
      string zName = zoneNames[i];
      if(ObjectFind(0, zName) >= 0)
      {
         double p1=ObjectGetDouble(0,zName,OBJPROP_PRICE,0), p2=ObjectGetDouble(0,zName,OBJPROP_PRICE,1);
         if(currentPrice >= MathMin(p1,p2) && currentPrice <= MathMax(p1,p2))
         {
            if(StringFind(zName, "DZone") >= 0) liveZoneStatus = 1; else liveZoneStatus = -1;
            string tooltip = ObjectGetString(0, zName, OBJPROP_TOOLTIP);
            string parts[];
            if(StringSplit(tooltip, ';', parts) == 4) // UPGRADED: Expects 4 parts
            {
               liveStrengthScore = (int)StringToInteger(parts[0]);
               liveFreshness = (double)StringToInteger(parts[1]);
               liveVolume = (double)StringToInteger(parts[2]);
               liveLiquidity = (double)StringToInteger(parts[3]); // NEW
            }
         }
      }
   }

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

   for(int i = rates_total - 1; i >= 0; i--)
   {
      zoneStatusBuffer[i] = liveZoneStatus;
      magnetLevelBuffer[i] = liveMagnetLevel;
      zoneStrengthBuffer[i] = liveStrengthScore;
      zoneFreshnessBuffer[i] = liveFreshness;
      zoneVolumeBuffer[i] = liveVolume;
      zoneLiquidityBuffer[i] = liveLiquidity; // NEW
   }

   static datetime lastPrintTime = 0;
   if(TimeCurrent() != lastPrintTime)
   {
      PrintFormat("AlfredSupDemCore DEBUG | Status:%d | Strength:%d | Fresh:%.0f | Volume:%.0f | Liq:%.0f",
                  liveZoneStatus, liveStrengthScore, liveFreshness, liveVolume, liveLiquidity);
      lastPrintTime = TimeCurrent();
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
//| Core Zone Finding and Scoring Logic (UPGRADED)                   |
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
      // NEW: Check for liquidity grab
      analysis.hasLiquidityGrab = HasLiquidityGrab(tf, i + analysis.baseCandles, isDemand);
      analysis.strengthScore = CalculateZoneStrength(analysis, tf);
      
      return analysis;
   }
   
   return analysis;
}

//+------------------------------------------------------------------+
//| Calculates a zone's strength score (UPGRADED)                    |
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
    // NEW: Add liquidity grab bonus (high value)
    int liquidityBonus = zone.hasLiquidityGrab ? 3 : 0;

    return(MathMin(10, explosiveScore + consolidationScore + freshnessBonus + volumeBonus + liquidityBonus));
}

//+------------------------------------------------------------------+
//| Rectangle drawer (UPGRADED to store more data)                   |
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
   
   // Store data in tooltip: "score;freshness;volume;liquidity"
   string tooltip = (string)analysis.strengthScore + ";" + (string)(analysis.isFresh ? 1 : 0) + ";" + (string)(analysis.hasVolume ? 1 : 0) + ";" + (string)(analysis.hasLiquidityGrab ? 1 : 0);
   ObjectSetString(0, name, OBJPROP_TOOLTIP, tooltip);
   
   // Update visual text
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

// --- NEW FUNCTION FOR LIQUIDITY GRAB DETECTION ---
bool HasLiquidityGrab(ENUM_TIMEFRAMES tf, int bar_index, bool isDemandZone)
{
   MqlRates rates[];
   int lookback = 10; // How far back to look for a swing high/low
   if(CopyRates(_Symbol, tf, bar_index, lookback, rates) < lookback) return false;
   ArraySetAsSeries(rates, true);
   
   double grab_candle_wick = isDemandZone ? rates[0].low : rates[0].high;
   
   // Find the highest high / lowest low in the lookback period (excluding the grab candle itself)
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
   
   // Check if the grab candle's wick went past the liquidity level
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
