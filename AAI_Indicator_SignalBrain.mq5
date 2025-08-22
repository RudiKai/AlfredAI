//+------------------------------------------------------------------+
//|                  AAI_Indicator_SignalBrain.mq5                   |
//|             v4.2 - Corrected ZoneEngine Buffer Reading           |
//|                                                                  |
//| Copyright 2025, AlfredAI Project                                 |
//+------------------------------------------------------------------+
#property strict
#property indicator_chart_window
#property version "4.2"

// --- Indicator Buffers ---
#property indicator_buffers 4
#property indicator_plots   4

#property indicator_type1   DRAW_NONE
#property indicator_label1  "Signal"
double SignalBuffer[];

#property indicator_type2   DRAW_NONE
#property indicator_label2  "Confidence"
double ConfidenceBuffer[];

#property indicator_type3   DRAW_NONE
#property indicator_label3  "ReasonCode"
double ReasonCodeBuffer[];

#property indicator_type4   DRAW_NONE
#property indicator_label4  "ZoneTimeframe"
double ZoneTFBuffer[];

//--- Indicator Inputs ---
input bool UseZoneEngine      = true;
input bool UseBiasCompass     = true;
input int  WarmupBars         = 150;
input int  FastMA             = 10;
input int  SlowMA             = 30;
input int  MinZoneStrength    = 4;
input bool EnableDebugLogging = true;

// --- Enums for Clarity ---
enum ENUM_REASON_CODE
{
    REASON_NONE,
    REASON_BUY_STATE_CONFIRMED,
    REASON_SELL_STATE_CONFIRMED,
    REASON_NO_ZONE,
    REASON_LOW_ZONE_STRENGTH,
    REASON_BIAS_CONFLICT,
    REASON_MOMENTUM_CONFLICT
};

// --- Indicator Handles ---
int ZE_handle = INVALID_HANDLE;
int BC_handle = INVALID_HANDLE;
int fastMA_handle = INVALID_HANDLE;
int slowMA_handle = INVALID_HANDLE;
int atr_handle = INVALID_HANDLE;

// --- Globals ---
static datetime g_last_log_time = 0;

//+------------------------------------------------------------------+
//| Custom indicator initialization function                         |
//+------------------------------------------------------------------+
int OnInit()
{
    SetIndexBuffer(0, SignalBuffer,     INDICATOR_DATA);
    SetIndexBuffer(1, ConfidenceBuffer, INDICATOR_DATA);
    SetIndexBuffer(2, ReasonCodeBuffer, INDICATOR_DATA);
    SetIndexBuffer(3, ZoneTFBuffer,     INDICATOR_DATA);

    ArraySetAsSeries(SignalBuffer,     true);
    ArraySetAsSeries(ConfidenceBuffer, true);
    ArraySetAsSeries(ReasonCodeBuffer, true);
    ArraySetAsSeries(ZoneTFBuffer,     true);

    PlotIndexSetDouble(0, PLOT_EMPTY_VALUE, 0.0);
    PlotIndexSetDouble(1, PLOT_EMPTY_VALUE, 0.0);
    PlotIndexSetDouble(2, PLOT_EMPTY_VALUE, 0.0);
    PlotIndexSetDouble(3, PLOT_EMPTY_VALUE, 0.0);
    IndicatorSetInteger(INDICATOR_DIGITS,0);

    fastMA_handle = iMA(_Symbol, _Period, FastMA, 0, MODE_SMA, PRICE_CLOSE);
    slowMA_handle = iMA(_Symbol, _Period, SlowMA, 0, MODE_SMA, PRICE_CLOSE);
    atr_handle = iATR(_Symbol, _Period, 14);

    if(fastMA_handle == INVALID_HANDLE || slowMA_handle == INVALID_HANDLE || atr_handle == INVALID_HANDLE)
    {
        Print("[SB_ERR] Failed to create core handles. Indicator cannot function.");
        return(INIT_FAILED);
    }

    if(UseZoneEngine)
    {
        ZE_handle = iCustom(_Symbol, _Period, "AAI_Indicator_ZoneEngine");
        if(ZE_handle == INVALID_HANDLE) Print("[SB_WARN] Failed to create ZoneEngine handle.");
    }

    if(UseBiasCompass)
    {
        BC_handle = iCustom(_Symbol, _Period, "AAI_Indicator_BiasCompass");
        if(BC_handle == INVALID_HANDLE) Print("[SB_WARN] Failed to create BiasCompass handle.");
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
    if(rates_total < WarmupBars) return(0);
    
    int start_bar = rates_total - 2;
    if(prev_calculated > 1) start_bar = rates_total - prev_calculated;
    start_bar = MathMax(1, start_bar);

    for(int i = start_bar; i >= 1; i--)
    {
        double signal = 0.0;
        double conf = 0.0;
        ENUM_REASON_CODE reasonCode = REASON_NONE;

        // --- Condition 1: Price must be in a strong Zone (The Trigger) ---
        bool in_strong_demand = false;
        bool in_strong_supply = false;
        
        if(UseZoneEngine && ZE_handle != INVALID_HANDLE)
        {
            // *** CORRECTED BUFFER READING ***
            double zeStrength_arr[1], zeType_arr[1];
            if(CopyBuffer(ZE_handle, 0, i, 1, zeStrength_arr) > 0 && CopyBuffer(ZE_handle, 1, i, 1, zeType_arr) > 0)
            {
                if(zeStrength_arr[0] >= MinZoneStrength)
                {
                    if(zeType_arr[0] > 0.5) in_strong_demand = true;     // Type 1.0 = Demand
                    else if(zeType_arr[0] < -0.5) in_strong_supply = true; // Type -1.0 = Supply
                }
            }
        }

        // --- If not in a valid zone, no signal is possible. Continue to next bar. ---
        if(in_strong_demand || in_strong_supply)
        {
            // --- Condition 2: Momentum must be aligned ---
            bool momentum_aligned = false;
            double fast_arr[1], slow_arr[1];
            if(CopyBuffer(fastMA_handle, 0, i, 1, fast_arr) > 0 && CopyBuffer(slowMA_handle, 0, i, 1, slow_arr) > 0)
            {
                if((in_strong_demand && fast_arr[0] > slow_arr[0]) || (in_strong_supply && fast_arr[0] < slow_arr[0]))
                {
                    momentum_aligned = true;
                } else {
                    reasonCode = REASON_MOMENTUM_CONFLICT;
                }
            }

            // --- Condition 3: HTF Trend must be aligned ---
            bool bias_aligned = false;
            if(UseBiasCompass && BC_handle != INVALID_HANDLE)
            {
                double htfBias_arr[1];
                if(CopyBuffer(BC_handle, 0, i, 1, htfBias_arr) > 0)
                {
                    if((in_strong_demand && htfBias_arr[0] > 0.5) || (in_strong_supply && htfBias_arr[0] < -0.5))
                    {
                        bias_aligned = true;
                    } else {
                        reasonCode = REASON_BIAS_CONFLICT;
                    }
                }
            } else {
                bias_aligned = true; // Pass if BiasCompass is not used
            }

            // --- Final Decision: All confirmations must be met ---
            if(momentum_aligned && bias_aligned)
            {
                signal = in_strong_demand ? 1.0 : -1.0;
                reasonCode = (signal > 0) ? REASON_BUY_STATE_CONFIRMED : REASON_SELL_STATE_CONFIRMED;
                
                // Calculate Dynamic Confidence for the valid signal
                double atr_arr[1];
                if (CopyBuffer(atr_handle, 0, i, 1, atr_arr) > 0 && atr_arr[0] > 0)
                {
                    double ma_separation = MathAbs(fast_arr[0] - slow_arr[0]);
                    double momentum_ratio = ma_separation / atr_arr[0];
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
        ConfidenceBuffer[i] = conf;
        ReasonCodeBuffer[i] = (double)reasonCode;
        ZoneTFBuffer[i]     = (double)PeriodSeconds(_Period);
    }

    // Mirror the last closed bar to the current bar
    if (rates_total > 1)
    {
        SignalBuffer[0]     = SignalBuffer[1];
        ConfidenceBuffer[0] = ConfidenceBuffer[1];
        ReasonCodeBuffer[0] = ReasonCodeBuffer[1];
        ZoneTFBuffer[0]     = ZoneTFBuffer[1];
    }
    
    if(EnableDebugLogging && time[rates_total-1] != g_last_log_time)
    {
        PrintFormat("[SB_OUT] t=%s sig=%.1f conf=%.1f reason=%g ztf=%g",
                    TimeToString(time[rates_total-2]),
                    SignalBuffer[1], ConfidenceBuffer[1], ReasonCodeBuffer[1], ZoneTFBuffer[1]);
        g_last_log_time = time[rates_total-1];
    }

    return(rates_total);
}
//+------------------------------------------------------------------+
