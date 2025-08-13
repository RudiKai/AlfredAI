//+------------------------------------------------------------------+
//|                  AAI_Indicator_SignalBrain.mq5                   |
//|                 v2.7 - Fail-soft & Non-blocking                  |
//|          Acts as the confluence and trade signal engine.         |
//|                                                                  |
//| Copyright 2025, AlfredAI Project                    |
//+------------------------------------------------------------------+

// ---- Program properties (indicator, headless)
#property strict
#property indicator_chart_window
#property indicator_plots 0
#property indicator_buffers 4
//#property version "2.7"

// === BEGIN Spec 1: Headless + single set of properties ===
#property indicator_plots 0
#property indicator_buffers 4

// === END Spec 1 ===

// --- Buffer declarations
#property indicator_label1  "Signal"
#property indicator_label2  "Confidence"
#property indicator_label3  "ReasonCode"
#property indicator_label4  "ZoneTimeframe"

// ---- Published buffers (Signal, Confidence, Reason, ZoneTF)
double BufSignal[];
double BufConf[];
double BufReason[];
double BufZoneTF[];


// ---- Temporary aliases to keep older code compiling
//      (you can remove these after refactoring reads)
#define BC_handle_HTF BC_handle
#define BC_handle_LTF BC_handle

// ---- BiasCompass buffer indexes (match your BiasCompass)
#define BC_BUF_HTF_BIAS 0
#define BC_BUF_LTF_BIAS 1
#define BC_BUF_HTF_CONF 2
#define BC_BUF_LTF_CONF 3

// ---- Write one bar into all SB buffers
inline void SB_WriteBar(const int i, const double sig, const double conf, const double reason, const double zonetf)
{
   BufSignal[i] = sig;
   BufConf[i]   = conf;
   BufReason[i] = reason;
   BufZoneTF[i] = zonetf;
}

// ---- Safe 1-value reader from any indicator buffer
inline bool SafeCopy1(const int handle, const int buf, const int shift, double &outVal)
{
   if(handle==INVALID_HANDLE){ outVal=0.0; return false; }
   double t[]; ArraySetAsSeries(t,true);
   int n = CopyBuffer(handle, buf, shift, 1, t);
   if(n==1){ outVal = t[0]; return true; }
   outVal = 0.0; return false;
}

// ---- Convenience reader for BiasCompass (single handle, 4 buffers)
inline bool ReadBC(const int buf, const int shift, double &outVal)
{
   return SafeCopy1(BC_handle, buf, shift, outVal);
}

// ---- Deterministic filler for SB_SafeTest (writes ALL 4 buffers)
void SB_SafeFill(const int rates_total, const int prev_calculated)
{
   const int warm = 150;
   int start = (prev_calculated>0 ? prev_calculated-1 : MathMax(0, rates_total - warm));
   const double ztf = (double)PeriodSeconds(_Period);

   for(int i=start; i<rates_total; ++i)
   {
      // simple deterministic pattern: flip every 10 bars
      int age  = rates_total - 1 - i;          // 0 = current bar
      double s = ((age/10)%2==0 ? 1.0 : -1.0); // 10-bar alternating
      double c = 5.0;                           // constant confidence
      SB_WriteBar(i, s, c, 0.0, ztf);
   }
}




//--- Indicator Inputs ---
input int  MinZoneStrength    = 4;      // Minimum zone strength score (1-10) to consider for a signal
// === BEGIN Spec 3: Inputs ===
input bool SB_SafeTest   = false;
input bool UseZoneEngine = true;
input bool UseBiasCompass= true;
input int  SB_WarmupBars = 150;
// === END Spec 3 ===

// --- Enums for Clarity
enum ENUM_TRADE_SIGNAL
{
    SIGNAL_NONE = 0,
    SIGNAL_BUY  = 1,
    SIGNAL_SELL = -1
};
enum ENUM_REASON_CODE
{
    REASON_NONE,
    REASON_BUY_HTF_CONTINUATION,
    REASON_SELL_HTF_CONTINUATION,
    REASON_BUY_LIQ_GRAB_ALIGNED,
    REASON_SELL_LIQ_GRAB_ALIGNED,
    REASON_NO_ZONE,
    REASON_LOW_ZONE_STRENGTH,
    REASON_BIAS_CONFLICT
};
// --- Constants for Analysis
const ENUM_TIMEFRAMES HTF = PERIOD_H4;
const ENUM_TIMEFRAMES LTF = PERIOD_M15;

// NEW — single BiasCompass instance publishes both HTF & LTF
int ZE_handle = INVALID_HANDLE;
int BC_handle = INVALID_HANDLE;

//+------------------------------------------------------------------+
//| SB_SafeFill: Bypasses logic for performance testing              |
//+------------------------------------------------------------------+


//+------------------------------------------------------------------+
//| Custom indicator initialization function                         |
//+------------------------------------------------------------------+
int OnInit()
{
    // --- Bind all 4 data buffers
    bool ok = true;
    ok &= SetIndexBuffer(0, BufSignal, INDICATOR_DATA);
    ok &= SetIndexBuffer(1, BufConf,   INDICATOR_DATA);
    ok &= SetIndexBuffer(2, BufReason, INDICATOR_DATA);
    ok &= SetIndexBuffer(3, BufZoneTF, INDICATOR_DATA);

    ArraySetAsSeries(BufSignal, true);
    ArraySetAsSeries(BufConf,   true);
    ArraySetAsSeries(BufReason, true);
    ArraySetAsSeries(BufZoneTF, true);

    // MQL5 style "empty value" setup (not SetIndexEmptyValue)
    PlotIndexSetDouble(0, PLOT_EMPTY_VALUE, 0.0);
    PlotIndexSetDouble(1, PLOT_EMPTY_VALUE, 0.0);
    PlotIndexSetDouble(2, PLOT_EMPTY_VALUE, 0.0);
    PlotIndexSetDouble(3, PLOT_EMPTY_VALUE, 0.0);

    if(!ok)
    {
        Print("[SB_ERR] SetIndexBuffer failed");
        return(INIT_FAILED);
    }

    // --- Create dependent indicator handles (fail-soft)
    if(UseZoneEngine)
    {
        ZE_handle = iCustom(_Symbol, _Period, "AAI_Indicator_ZoneEngine");
        if(ZE_handle == INVALID_HANDLE)
            Print("[SB_ERR] Failed to create ZoneEngine handle.");
    }
    else
        ZE_handle = INVALID_HANDLE;

    if(UseBiasCompass)
    {
        // Single BiasCompass instance; it publishes both HTF & LTF
        BC_handle = iCustom(_Symbol, _Period, "AAI_Indicator_BiasCompass");
        if(BC_handle == INVALID_HANDLE)
            Print("[SB_ERR] Failed to create BiasCompass handle.");
    }
    else
        BC_handle = INVALID_HANDLE;

    PrintFormat("[INIT] SB handles → ZE=%d BC=%d TF=%d", ZE_handle, BC_handle, _Period);
    return(INIT_SUCCEEDED);
}


//+------------------------------------------------------------------+
//| Deinitialization                                                 |
//+------------------------------------------------------------------+
void OnDeinit(const int reason)
{
    if(ZE_handle != INVALID_HANDLE) IndicatorRelease(ZE_handle);
    if(BC_handle_HTF != INVALID_HANDLE) IndicatorRelease(BC_handle_HTF);
    if(BC_handle_LTF != INVALID_HANDLE) IndicatorRelease(BC_handle_LTF);
}


//+------------------------------------------------------------------+
//| Custom indicator iteration function (LONG signature)             |
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
   if(rates_total<=0) return prev_calculated;

   // --- Smoke path: fill deterministically and exit
   if(SB_SafeTest)
   {
      SB_SafeFill(rates_total, prev_calculated);
      return rates_total;
   }

   // --- Incremental processing window
   int start = (prev_calculated>0 ? prev_calculated-1 : MathMax(0, rates_total - SB_WarmupBars));
   const double ztf = (double)PeriodSeconds(_Period);

   for(int i=start; i<rates_total; ++i)
   {
      // shift: 0=current bar, so map i→shift
      const int shift = (rates_total - 1 - i);

      // ===== BiasCompass reads (fail-soft to zeros) =====
      double htfBias=0, ltfBias=0, htfConf=0, ltfConf=0;
      if(UseBiasCompass && BC_handle!=INVALID_HANDLE)
      {
         ReadBC(BC_BUF_HTF_BIAS, shift, htfBias);
         ReadBC(BC_BUF_LTF_BIAS, shift, ltfBias);
         ReadBC(BC_BUF_HTF_CONF, shift, htfConf);
         ReadBC(BC_BUF_LTF_CONF, shift, ltfConf);
      }
      // else, they stay zero

      // ===== ZoneEngine reads (optional; keep zeros if missing) =====
      // (Only if you need ZE for your signal today; otherwise leave zeros)
      double zoneStatus=0, zoneStrength=0;
      if(UseZoneEngine && ZE_handle!=INVALID_HANDLE)
      {
         // Example if you know ZE buffer indexes:
         // SafeCopy1(ZE_handle, ZE_BUF_STATUS,   shift, zoneStatus);
         // SafeCopy1(ZE_handle, ZE_BUF_STRENGTH, shift, zoneStrength);
      }

      // ====== Your signal logic (keep trivial for now) ======
      double sig    = 0.0;
      double conf   = 0.0;
      double reason = 0.0; // map your ENUM_REASON_CODE to double when you add real logic

      // Minimal example: alignments produce a weak signal
      if(htfBias>0 && ltfBias>0 && htfConf>=1 && ltfConf>=1) { sig= 1.0; conf= (htfConf+ltfConf)*0.5; }
      if(htfBias<0 && ltfBias<0 && htfConf>=1 && ltfConf>=1) { sig=-1.0; conf= (htfConf+ltfConf)*0.5; }

      // Always write all 4 buffers
      SB_WriteBar(i, sig, conf, reason, ztf);
   }

   return rates_total;
}

//+------------------------------------------------------------------+
