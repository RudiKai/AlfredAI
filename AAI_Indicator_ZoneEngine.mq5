//+------------------------------------------------------------------+
//|                   AAI_Indicator_ZoneEngine.mq5                   |
//|            v2.4 - Non-blocking Calculation Update                |
//|      (Detects zones and exports levels for EA consumption)       |
//|                                                                  |
//| Copyright 2025, AlfredAI Project                    |
//+------------------------------------------------------------------+
#property indicator_chart_window
#property strict
#property version "2.4"

// === BEGIN Spec: Headless + buffers ===
#property indicator_plots   0
#property indicator_buffers 8

// --- Buffer declarations
#property indicator_label1  "ZoneStatus"
double BufZoneStatus[];
#property indicator_label2  "MagnetLevel"
double BufMagnetLevel[];
#property indicator_label3  "ZoneStrength"
double BufZoneStrength[];
#property indicator_label4  "ZoneFreshness"
double BufZoneFreshness[];
#property indicator_label5  "ZoneVolume"
double BufZoneVolume[];
#property indicator_label6  "ZoneLiquidity"
double BufZoneLiquidity[];
#property indicator_label7  "ProximalLevel"
double BufProximal[];
#property indicator_label8  "DistalLevel"
double BufDistal[];
// === END Spec ===

//--- Indicator Inputs ---
input double MinImpulseMovePips = 10.0;

// --- Struct for analysis results ---
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

// --- Forward declarations
ZoneAnalysis FindZone(ENUM_TIMEFRAMES tf, bool isDemand, int shift);
int CalculateZoneStrength(const ZoneAnalysis &zone, ENUM_TIMEFRAMES tf, int shift);
bool HasVolumeConfirmation(ENUM_TIMEFRAMES tf, int shift, int base_candle_index, int num_candles);
bool HasLiquidityGrab(ENUM_TIMEFRAMES tf, int shift, int base_candle_index, bool isDemandZone);

//+------------------------------------------------------------------+
//| Initialization                                                   |
//+------------------------------------------------------------------+
int OnInit()
{
    // === BEGIN Spec: Bind as DATA + series ===
    bool ok = true;
    ok &= SetIndexBuffer(0, BufZoneStatus,    INDICATOR_DATA);
    ok &= SetIndexBuffer(1, BufMagnetLevel,   INDICATOR_DATA);
    ok &= SetIndexBuffer(2, BufZoneStrength,  INDICATOR_DATA);
    ok &= SetIndexBuffer(3, BufZoneFreshness, INDICATOR_DATA);
    ok &= SetIndexBuffer(4, BufZoneVolume,    INDICATOR_DATA);
    ok &= SetIndexBuffer(5, BufZoneLiquidity, INDICATOR_DATA);
    ok &= SetIndexBuffer(6, BufProximal,      INDICATOR_DATA);
    ok &= SetIndexBuffer(7, BufDistal,        INDICATOR_DATA);

    if(!ok)
    {
        Print("ZE SetIndexBuffer failed");
        return(INIT_FAILED);
    }

    ArraySetAsSeries(BufZoneStatus,    true);
    ArraySetAsSeries(BufMagnetLevel,   true);
    ArraySetAsSeries(BufZoneStrength,  true);
    ArraySetAsSeries(BufZoneFreshness, true);
    ArraySetAsSeries(BufZoneVolume,    true);
    ArraySetAsSeries(BufZoneLiquidity, true);
    ArraySetAsSeries(BufProximal,      true);
    ArraySetAsSeries(BufDistal,        true);
    // === END Spec ===

    return(INIT_SUCCEEDED);
}

//+------------------------------------------------------------------+
//| Deinitialization                                                 |
//+------------------------------------------------------------------+
void OnDeinit(const int reason)
{
   // Nothing to do in a headless indicator
}

//+------------------------------------------------------------------+
//| Main Calculation: Fills buffers for each bar.                    |
//+------------------------------------------------------------------+
int OnCalculate(const int rates_total,
                const int prev_calculated,
                const datetime &time[],
                const double &open[],
                const double &high[],
                const double &low[],
                const double &close[],
                const long &tick_volume[],
                const long &volume[],
                const int &spread[])
{
    // === BEGIN Spec: Canonical incremental pattern ===
    const int WARMUP = 100; // Requires lookback for zone detection

    if(rates_total <= WARMUP)
    {
        for(int i = 0; i < rates_total; i++)
        {
            BufZoneStatus[i] = 0; BufMagnetLevel[i] = 0; BufZoneStrength[i] = 0;
            BufZoneFreshness[i] = 0; BufZoneVolume[i] = 0; BufZoneLiquidity[i] = 0;
            BufProximal[i] = 0; BufDistal[i] = 0;
        }
        return(rates_total);
    }

    int start = (prev_calculated > 0) ? prev_calculated - 1 : WARMUP;
    if(start < 0) start = 0;
    if(start >= rates_total) start = rates_total - 1;
    
    for(int i = start; i < rates_total; i++)
    {
        int shift = rates_total - 1 - i;

        ZoneAnalysis demandZone = FindZone(_Period, true, shift);
        ZoneAnalysis supplyZone = FindZone(_Period, false, shift);

        double barClose = close[i];

        double status = 0.0, magnet = 0.0, strength = 0.0;
        double freshness = 0.0, vol = 0.0, liquidity = 0.0;
        double proximal = 0.0, distal = 0.0;

        bool isInDemand = demandZone.isValid && (barClose >= demandZone.distal && barClose <= demandZone.proximal);
        bool isInSupply = supplyZone.isValid && (barClose >= supplyZone.proximal && barClose <= supplyZone.distal);

        ZoneAnalysis activeZone;
        if (isInDemand) { activeZone = demandZone; status = 1; }
        if (isInSupply) { activeZone = supplyZone; status = -1; }

        if (status != 0.0)
        {
            strength  = activeZone.strengthScore;
            freshness = activeZone.isFresh ? 1.0 : 0.0;
            vol       = activeZone.hasVolume ? 1.0 : 0.0;
            liquidity = activeZone.hasLiquidityGrab ? 1.0 : 0.0;
            proximal  = activeZone.proximal;
            distal    = activeZone.distal;
        }

        double distD = demandZone.isValid ? MathAbs(barClose - (demandZone.proximal + demandZone.distal) / 2.0) : DBL_MAX;
        double distS = supplyZone.isValid ? MathAbs(barClose - (supplyZone.proximal + supplyZone.distal) / 2.0) : DBL_MAX;
        
        if (demandZone.isValid && distD <= distS)
            magnet = (demandZone.proximal + demandZone.distal) / 2.0;
        else if (supplyZone.isValid)
            magnet = (supplyZone.proximal + supplyZone.distal) / 2.0;

        BufZoneStatus[i]    = status;
        BufMagnetLevel[i]   = magnet;
        BufZoneStrength[i]  = strength;
        BufZoneFreshness[i] = freshness;
        BufZoneVolume[i]    = vol;
        BufZoneLiquidity[i] = liquidity;
        BufProximal[i]      = proximal;
        BufDistal[i]        = distal;
    }
    return(rates_total);
    // === END Spec ===
}

//+------------------------------------------------------------------+
//| Core Zone Finding and Scoring Logic                              |
//+------------------------------------------------------------------+
ZoneAnalysis FindZone(ENUM_TIMEFRAMES tf, bool isDemand, int shift)
{
   ZoneAnalysis analysis;
   analysis.isValid = false;
   
   MqlRates rates[];
   int lookback = 50;
   int barsToCopy = lookback + 10;
   
   if(CopyRates(_Symbol, tf, shift, barsToCopy, rates) < barsToCopy) 
      return analysis;
      
   ArraySetAsSeries(rates, true);

   for(int i = 1; i < lookback; i++)
   {
      double impulseStart = isDemand ? rates[i].low : rates[i].high;
      double impulseEnd = isDemand ? rates[i-1].high : rates[i-1].low;
      double impulseMove = MathAbs(impulseEnd - impulseStart);

      if(impulseMove / _Point < MinImpulseMovePips) continue;

      analysis.proximal = isDemand ? rates[i].high : rates[i].low;
      analysis.distal = isDemand ? rates[i].low : rates[i].high;
      analysis.time = rates[i].time;
      analysis.baseCandles = 1;
      analysis.isValid = true;
      analysis.impulseStrength = MathAbs(rates[i-1].close - rates[i].open);
      analysis.isFresh = true; // Historical freshness check is complex, default to true
      analysis.hasVolume = HasVolumeConfirmation(tf, shift, i, analysis.baseCandles);
      analysis.hasLiquidityGrab = HasLiquidityGrab(tf, shift, i, isDemand);
      analysis.strengthScore = CalculateZoneStrength(analysis, tf, shift);
      
      return analysis;
   }
   
   return analysis;
}

//+------------------------------------------------------------------+
//| Calculates a zone's strength score                               |
//+------------------------------------------------------------------+
int CalculateZoneStrength(const ZoneAnalysis &zone, ENUM_TIMEFRAMES tf, int shift)
{
    if(!zone.isValid) return 0;

    double atr_buffer[1];
    double atr = 0.0;
    int atr_handle = iATR(_Symbol, tf, 14);
    if(atr_handle != INVALID_HANDLE)
    {
      if(CopyBuffer(atr_handle, 0, shift, 1, atr_buffer) > 0) 
        atr = atr_buffer[0];
    }
    if(atr == 0.0) atr = _Point * 10;

    int explosiveScore = 0;
    if(zone.impulseStrength > atr * 2.0) explosiveScore = 5;
    else if(zone.impulseStrength > atr * 1.5) explosiveScore = 4;
    else if(zone.impulseStrength > atr * 1.0) explosiveScore = 3;
    else explosiveScore = 2;

    int consolidationScore = (zone.baseCandles == 1) ? 5 : (zone.baseCandles <= 3) ? 3 : 1;
    int freshnessBonus = zone.isFresh ? 2 : 0;
    int volumeBonus = zone.hasVolume ? 2 : 0;
    int liquidityBonus = zone.hasLiquidityGrab ? 3 : 0;

    return(MathMin(10, explosiveScore + consolidationScore + freshnessBonus + volumeBonus + liquidityBonus));
}

//+------------------------------------------------------------------+
//| Checks for volume confirmation at the zone's base.               |
//+------------------------------------------------------------------+
bool HasVolumeConfirmation(ENUM_TIMEFRAMES tf, int shift, int base_candle_index, int num_candles)
{
   MqlRates rates[];
   int lookback = 20;
   if(CopyRates(_Symbol, tf, shift + base_candle_index, lookback + num_candles, rates) < lookback) 
     return false;
   ArraySetAsSeries(rates, true);
   
   long total_volume = 0;
   for(int i = 0; i < num_candles; i++) { total_volume += rates[i].tick_volume; }
   
   long avg_volume_base = 0;
   for(int i = num_candles; i < lookback + num_candles; i++) { avg_volume_base += rates[i].tick_volume; }
   
   if(lookback == 0) return false;
   double avg_volume = (double)avg_volume_base / lookback;
   return (total_volume > avg_volume * 1.5);
}

//+------------------------------------------------------------------+
//| Detects if the zone was formed by a liquidity grab.              |
//+------------------------------------------------------------------+
bool HasLiquidityGrab(ENUM_TIMEFRAMES tf, int shift, int base_candle_index, bool isDemandZone)
{
   MqlRates rates[];
   int lookback = 10;
   int grab_candle_shift = shift + base_candle_index;
   
   if(CopyRates(_Symbol, tf, grab_candle_shift, lookback + 1, rates) < lookback + 1) 
     return false;
   ArraySetAsSeries(rates, true);
   
   double grab_candle_wick = isDemandZone ? rates[0].low : rates[0].high;
   
   double target_liquidity_level = isDemandZone ? rates[1].low : rates[1].high;
   for(int i = 2; i < lookback + 1; i++)
   {
      if(isDemandZone)
         target_liquidity_level = MathMin(target_liquidity_level, rates[i].low);
      else
         target_liquidity_level = MathMax(target_liquidity_level, rates[i].high);
   }
   
   return (isDemandZone ? (grab_candle_wick < target_liquidity_level) : (grab_candle_wick > target_liquidity_level));
}
//+------------------------------------------------------------------+
