//+------------------------------------------------------------------+
//|                   AAI_Indicator_ZoneEngine.mq5                   |
//|            v2.9 - Added Zone Type Buffer for EA Comms            |
//|      (Detects zones and exports levels for EA consumption)       |
//+------------------------------------------------------------------+
#property indicator_chart_window
#property strict
#property version "2.9"

// === BEGIN Spec: Headless + Buffers for Strength & Type ===
#property indicator_plots   2
#property indicator_buffers 2

#property indicator_type1   DRAW_NONE
#property indicator_label1  "ZE_Strength"
double ZE_StrengthBuf[];

#property indicator_type2   DRAW_NONE
#property indicator_label2  "ZE_Type"
double ZE_TypeBuf[];
// === END Spec ===

//--- Indicator Inputs ---
input double MinImpulseMovePips = 10.0;
input bool   ZE_TelemetryEnabled = true;

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
    // === Bind Buffers ===
    if(!SetIndexBuffer(0, ZE_StrengthBuf, INDICATOR_DATA))
    {
        Print("ZE SetIndexBuffer failed for Strength");
        return(INIT_FAILED);
    }
    if(!SetIndexBuffer(1, ZE_TypeBuf, INDICATOR_DATA))
    {
        Print("ZE SetIndexBuffer failed for Type");
        return(INIT_FAILED);
    }
    ArraySetAsSeries(ZE_StrengthBuf, true);
    ArraySetAsSeries(ZE_TypeBuf, true);
    return(INIT_SUCCEEDED);
}

//+------------------------------------------------------------------+
//| Deinitialization                                                 |
//+------------------------------------------------------------------+
void OnDeinit(const int reason) {}

//+------------------------------------------------------------------+
//| Main Calculation                                                 |
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
    const int WARMUP = 100;
    if(rates_total <= WARMUP) return(0);

    int start_bar = rates_total - 2;
    if(prev_calculated > 1) start_bar = rates_total - prev_calculated;

    for(int i = start_bar; i >= 0; i--)
    {
        ZoneAnalysis demandZone = FindZone(_Period, true, i);
        ZoneAnalysis supplyZone = FindZone(_Period, false, i);

        double strength = 0.0;
        double zoneType = 0.0; // 1 for Demand, -1 for Supply
        double barClose = close[i];

        bool isInDemand = demandZone.isValid && (barClose >= demandZone.distal && barClose <= demandZone.proximal);
        bool isInSupply = supplyZone.isValid && (barClose >= supplyZone.proximal && barClose <= supplyZone.distal);

        if(isInDemand)
        {
            strength = demandZone.strengthScore;
            zoneType = 1.0;
        }
        else if(isInSupply)
        {
            strength = supplyZone.strengthScore;
            zoneType = -1.0;
        }

        ZE_StrengthBuf[i] = strength;
        ZE_TypeBuf[i] = zoneType;
    }

    // Mirror to current bar
    if(rates_total > 1) {
        ZE_StrengthBuf[0] = ZE_StrengthBuf[1];
        ZE_TypeBuf[0] = ZE_TypeBuf[1];
    }
    
    if(ZE_TelemetryEnabled)
    {
        static datetime last_log_time = 0;
        if(time[rates_total - 2] != last_log_time)
        {
            PrintFormat("[ZE_EMIT] t=%s strength=%.1f type=%.1f", TimeToString(time[rates_total - 2]), ZE_StrengthBuf[1], ZE_TypeBuf[1]);
            last_log_time = time[rates_total - 2];
        }
    }

    return(rates_total);
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
      // *** NEW, MORE ROBUST IMPULSE LOGIC ***
      // We now define the impulse by the size of the candle body FOLLOWING the base candle.
      MqlRates impulse_candle = rates[i-1];
      double impulseMove = MathAbs(impulse_candle.close - impulse_candle.open);

      // Check if the impulse move meets our minimum requirement in pips
      if(impulseMove / _Point < MinImpulseMovePips) continue;
      // *** END OF NEW LOGIC ***

      // If we found a valid impulse, define the zone based on the candle before it.
      MqlRates base_candle = rates[i];
      analysis.proximal = isDemand ? base_candle.high : base_candle.low;
      analysis.distal = isDemand ? base_candle.low : base_candle.high;
      analysis.time = base_candle.time;
      analysis.baseCandles = 1;
      analysis.isValid = true;
      analysis.impulseStrength = MathAbs(impulse_candle.close - base_candle.open);
      analysis.isFresh = true; // Defaulting to true for now
      analysis.hasVolume = HasVolumeConfirmation(tf, shift, i, analysis.baseCandles);
      analysis.hasLiquidityGrab = HasLiquidityGrab(tf, shift, i, isDemand);
      analysis.strengthScore = CalculateZoneStrength(analysis, tf, shift);

      return analysis; // Return the first valid zone found
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
      IndicatorRelease(atr_handle);
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
