//+------------------------------------------------------------------+
//|                  AAI_Indicator_SignalBrain.mq5                   |
//|               v4.0 - Triple Confluence Logic                     |
//|                                                                  |
//| Acts as the confluence and trade signal engine.                  |
//|                                                                  |
//| Copyright 2025, AlfredAI Project                                 |
//+------------------------------------------------------------------+
#property strict
#property indicator_chart_window
#property version "4.0"

// --- Indicator Buffers ---
#property indicator_buffers 4
#property indicator_plots   4

// --- Buffer 0: Signal ---
#property indicator_type1   DRAW_NONE
#property indicator_label1  "Signal"
double SignalBuffer[];

// --- Buffer 1: Confidence ---
#property indicator_type2   DRAW_NONE
#property indicator_label2  "Confidence"
double ConfidenceBuffer[];

// --- Buffer 2: ReasonCode ---
#property indicator_type3   DRAW_NONE
#property indicator_label3  "ReasonCode"
double ReasonCodeBuffer[];

// --- Buffer 3: ZoneTimeframe ---
#property indicator_type4   DRAW_NONE
#property indicator_label4  "ZoneTimeframe"
double ZoneTFBuffer[];

//--- Indicator Inputs (Stable Order) ---
input bool SB_SafeTest        = false;
input bool UseZoneEngine      = true;  // Default to true for Triple Confluence
input bool UseBiasCompass     = true;  // Default to true for Triple Confluence
input int  WarmupBars         = 150;
input int  FastMA             = 10;
input int  SlowMA             = 30;
input int  MinZoneStrength    = 4;
input bool EnableDebugLogging = true;

// --- Enums for Clarity
enum ENUM_REASON_CODE
{
    REASON_NONE,
    REASON_BUY_HTF_CONTINUATION,     // Old reason
    REASON_SELL_HTF_CONTINUATION,    // Old reason
    REASON_BUY_TRIPLE_CONFLUENCE,    // New reason for high-quality signal
    REASON_SELL_TRIPLE_CONFLUENCE,   // New reason for high-quality signal
    REASON_NO_ZONE,
    REASON_LOW_ZONE_STRENGTH,
    REASON_BIAS_CONFLICT,
    REASON_TEST_SCENARIO
};

// --- Indicator Handles ---
int ZE_handle = INVALID_HANDLE;
int BC_handle = INVALID_HANDLE;
int fastMA_handle = INVALID_HANDLE;
int slowMA_handle = INVALID_HANDLE;
int atr_handle = INVALID_HANDLE;

// --- Globals for one-time logging ---
static datetime g_last_log_time = 0;

//+------------------------------------------------------------------+
//| Custom indicator initialization function                         |
//+------------------------------------------------------------------+
int OnInit()
{
    // --- Bind all 4 data buffers ---
    SetIndexBuffer(0, SignalBuffer,     INDICATOR_DATA);
    SetIndexBuffer(1, ConfidenceBuffer, INDICATOR_DATA);
    SetIndexBuffer(2, ReasonCodeBuffer, INDICATOR_DATA);
    SetIndexBuffer(3, ZoneTFBuffer,     INDICATOR_DATA);

    // --- Set buffers as series arrays ---
    ArraySetAsSeries(SignalBuffer,     true);
    ArraySetAsSeries(ConfidenceBuffer, true);
    ArraySetAsSeries(ReasonCodeBuffer, true);
    ArraySetAsSeries(ZoneTFBuffer,     true);

    // --- Set empty values for buffers ---
    PlotIndexSetDouble(0, PLOT_EMPTY_VALUE, 0.0);
    PlotIndexSetDouble(1, PLOT_EMPTY_VALUE, 0.0);
    PlotIndexSetDouble(2, PLOT_EMPTY_VALUE, 0.0);
    PlotIndexSetDouble(3, PLOT_EMPTY_VALUE, 0.0);
    IndicatorSetInteger(INDICATOR_DIGITS,0);

    // --- Create dependent indicator handles ---
    fastMA_handle = iMA(_Symbol, _Period, FastMA, 0, MODE_SMA, PRICE_CLOSE);
    slowMA_handle = iMA(_Symbol, _Period, SlowMA, 0, MODE_SMA, PRICE_CLOSE);
    atr_handle = iATR(_Symbol, _Period, 14);

    if(fastMA_handle == INVALID_HANDLE || slowMA_handle == INVALID_HANDLE || atr_handle == INVALID_HANDLE)
    {
        Print("[SB_ERR] Failed to create one or more core handles (MA, ATR). Indicator cannot function.");
        return(INIT_FAILED);
    }

    if(UseZoneEngine)
    {
        ZE_handle = iCustom(_Symbol, _Period, "AAI_Indicator_ZoneEngine");
        if(ZE_handle == INVALID_HANDLE)
            Print("[SB_WARN] Failed to create ZoneEngine handle. It will be ignored.");
    }

    if(UseBiasCompass)
    {
        BC_handle = iCustom(_Symbol, _Period, "AAI_Indicator_BiasCompass");
        if(BC_handle == INVALID_HANDLE)
            Print("[SB_WARN] Failed to create BiasCompass handle. It will be ignored.");
    }

    return(INIT_SUCCEEDED);
}

//+------------------------------------------------------------------+
//| Deinitialization                                                 |
//+------------------------------------------------------------------+
void OnDeinit(const int reason)
{
    if(ZE_handle != INVALID_HANDLE) IndicatorRelease(ZE_handle);
    if(BC_handle != INVALID_HANDLE) IndicatorRelease(BC_handle);
    if(fastMA_handle != INVALID_HANDLE) IndicatorRelease(fastMA_handle);
    if(slowMA_handle != INVALID_HANDLE) IndicatorRelease(slowMA_handle);
    if(atr_handle != INVALID_HANDLE) IndicatorRelease(atr_handle);
}

//+------------------------------------------------------------------+
//| Custom indicator iteration function                              |
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
    if(rates_total < WarmupBars)
    {
        return(0);
    }
    
    int start_bar = rates_total - 2;
    if(prev_calculated > 0)
    {
        start_bar = rates_total - prev_calculated;
    }
    start_bar = MathMax(1, start_bar);

    for(int i = start_bar; i >= 1; i--)
    {
        // --- Initialize outputs for this bar ---
        double signal = 0.0;
        double conf = 0.0;
        ENUM_REASON_CODE reasonCode = REASON_NONE;

        // --- Condition 1: MA Cross (The Trigger) ---
        double initial_signal = 0.0;
        double fast_arr[1], slow_arr[1];
        if (CopyBuffer(fastMA_handle, 0, i, 1, fast_arr) > 0 && CopyBuffer(slowMA_handle, 0, i, 1, slow_arr) > 0)
        {
            if(fast_arr[0] > slow_arr[0] && fast_arr[0] != 0 && slow_arr[0] != 0) initial_signal = 1.0;
            else if(fast_arr[0] < slow_arr[0] && fast_arr[0] != 0 && slow_arr[0] != 0) initial_signal = -1.0;
        }

        // --- If there's no initial signal, no need to check other conditions ---
        if(initial_signal != 0.0)
        {
            // --- Condition 2: ZoneEngine Alignment (Market Structure) ---
            bool zone_aligned = false;
            if(UseZoneEngine && ZE_handle != INVALID_HANDLE)
            {
                double zeStatus_arr[1], zeStrength_arr[1];
                if(CopyBuffer(ZE_handle, 0, i, 1, zeStatus_arr) > 0 && CopyBuffer(ZE_handle, 2, i, 1, zeStrength_arr) > 0)
                {
                    bool is_strong_demand = zeStatus_arr[0] > 0.5 && zeStrength_arr[0] >= MinZoneStrength;
                    bool is_strong_supply = zeStatus_arr[0] < -0.5 && zeStrength_arr[0] >= MinZoneStrength;
                    
                    if((initial_signal > 0 && is_strong_demand) || (initial_signal < 0 && is_strong_supply))
                    {
                        zone_aligned = true;
                    } else {
                        reasonCode = REASON_NO_ZONE;
                    }
                }
            }
            else
            {
                zone_aligned = true; // If ZE is not used, this condition passes by default
            }

            // --- Condition 3: BiasCompass Alignment (Trend Filter) ---
            bool bias_aligned = false;
            if(UseBiasCompass && BC_handle != INVALID_HANDLE)
            {
                double htfBias_arr[1];
                if(CopyBuffer(BC_handle, 0, i, 1, htfBias_arr) > 0)
                {
                    bool is_bull_bias = htfBias_arr[0] > 0.5;
                    bool is_bear_bias = htfBias_arr[0] < -0.5;

                    if((initial_signal > 0 && is_bull_bias) || (initial_signal < 0 && is_bear_bias))
                    {
                        bias_aligned = true;
                    } else {
                        reasonCode = REASON_BIAS_CONFLICT;
                    }
                }
            }
            else
            {
                bias_aligned = true; // If BC is not used, this condition passes by default
            }

            // --- Final Decision: All 3 Conditions Must Be Met ---
            if(zone_aligned && bias_aligned)
            {
                signal = initial_signal; // Confirm the signal
                reasonCode = (signal > 0) ? REASON_BUY_TRIPLE_CONFLUENCE : REASON_SELL_TRIPLE_CONFLUENCE;
                
                // --- Calculate Dynamic Confidence only for valid signals ---
                double atr_arr[1];
                if (CopyBuffer(atr_handle, 0, i, 1, atr_arr) > 0 && atr_arr[0] > 0)
                {
                    double atr_val = atr_arr[0];
                    double ma_separation = MathAbs(fast_arr[0] - slow_arr[0]);
                    double momentum_ratio = ma_separation / atr_val;
                    
                    double base_confidence = 10.0 + (momentum_ratio - 0.5) * 4.0; 
                    conf = fmax(5.0, fmin(15.0, base_confidence));
                }
                else 
                {
                    conf = 10.0; // Fallback
                }
            }
        }

        // --- Write results to buffers ---
        SignalBuffer[i]     = signal;
        ConfidenceBuffer[i] = fmin(20.0, conf);
        ReasonCodeBuffer[i] = (double)reasonCode;
        ZoneTFBuffer[i]     = (double)PeriodSeconds(_Period);
    }

    // --- Mirror the last closed bar to the current bar for EA access ---
    if (rates_total > 1)
    {
        SignalBuffer[0]     = SignalBuffer[1];
        ConfidenceBuffer[0] = ConfidenceBuffer[1];
        ReasonCodeBuffer[0] = ReasonCodeBuffer[1];
        ZoneTFBuffer[0]     = ZoneTFBuffer[1];
    }
    
    // --- Optional Debug Logging ---
    if(EnableDebugLogging && time[rates_total-1] != g_last_log_time)
    {
        PrintFormat("[SB_OUT] t=%s sig=%.1f conf=%.1f reason=%g ztf=%g",
                    TimeToString(time[rates_total-2]),
                    SignalBuffer[1],
                    ConfidenceBuffer[1],
                    ReasonCodeBuffer[1],
                    ZoneTFBuffer[1]);
        g_last_log_time = time[rates_total-1];
    }

    return(rates_total);
}
//+------------------------------------------------------------------+
