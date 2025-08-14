//+------------------------------------------------------------------+
//|                  AAI_Indicator_SignalBrain.mq5                   |
//|               v3.4 - Corrected Headless Buffer Publishing        |
//|          Acts as the confluence and trade signal engine.         |
//|                                                                  |
//| Copyright 2025, AlfredAI Project                    |
//+------------------------------------------------------------------+
#property strict
#property indicator_chart_window
#property version "3.4"

// --- Indicator Buffers ---
#property indicator_buffers 4
#property indicator_plots   4 // FIX: Must match buffer count for EA/iCustom access.

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
input bool SB_SafeTest        = true;
input bool UseZoneEngine      = false;
input bool UseBiasCompass     = false;
input int  WarmupBars         = 150;
input int  FastMA             = 10;
input int  SlowMA             = 30;
input int  MinZoneStrength    = 4;
input bool EnableDebugLogging = true;

// --- Enums for Clarity
enum ENUM_REASON_CODE
{
    REASON_NONE,
    REASON_BUY_HTF_CONTINUATION,
    REASON_SELL_HTF_CONTINUATION,
    REASON_BUY_LIQ_GRAB_ALIGNED,
    REASON_SELL_LIQ_GRAB_ALIGNED,
    REASON_NO_ZONE,
    REASON_LOW_ZONE_STRENGTH,
    REASON_BIAS_CONFLICT,
    REASON_TEST_SCENARIO // Added for SafeTest
};

// --- Indicator Handles ---
int ZE_handle = INVALID_HANDLE;
int BC_handle = INVALID_HANDLE;
int fastMA_handle = INVALID_HANDLE;
int slowMA_handle = INVALID_HANDLE;
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
    PlotIndexSetDouble(0, PLOT_EMPTY_VALUE, EMPTY_VALUE);
    PlotIndexSetDouble(1, PLOT_EMPTY_VALUE, EMPTY_VALUE);
    PlotIndexSetDouble(2, PLOT_EMPTY_VALUE, EMPTY_VALUE);
    PlotIndexSetDouble(3, PLOT_EMPTY_VALUE, EMPTY_VALUE);
    IndicatorSetInteger(INDICATOR_DIGITS,0);

    // --- Create dependent indicator handles ---
    if(SB_SafeTest)
    {
        fastMA_handle = iMA(_Symbol, _Period, FastMA, 0, MODE_SMA, PRICE_CLOSE);
        slowMA_handle = iMA(_Symbol, _Period, SlowMA, 0, MODE_SMA, PRICE_CLOSE);
        if(fastMA_handle == INVALID_HANDLE || slowMA_handle == INVALID_HANDLE)
            Print("[SB_WARN] Failed to create one or more MA handles for SafeTest mode.");
    }
    else
    {
        if(UseZoneEngine)
        {
            ZE_handle = iCustom(_Symbol, _Period, "AAI_Indicator_ZoneEngine");
            if(ZE_handle == INVALID_HANDLE)
                Print("[SB_WARN] Failed to create ZoneEngine handle.");
        }

        if(UseBiasCompass)
        {
            BC_handle = iCustom(_Symbol, _Period, "AAI_Indicator_BiasCompass");
            if(BC_handle == INVALID_HANDLE)
                Print("[SB_WARN] Failed to create BiasCompass handle.");
        }
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

    if(SB_SafeTest)
    {
        static double fastArr[], slowArr[];
        ArraySetAsSeries(fastArr, true);
        ArraySetAsSeries(slowArr, true);

        if(CopyBuffer(fastMA_handle, 0, 0, rates_total, fastArr) <= 0 ||
           CopyBuffer(slowMA_handle, 0, 0, rates_total, slowArr) <= 0)
        {
            return(prev_calculated);
        }

        for(int i = start_bar; i >= 1; i--)
        {
            double signal = 0.0;
            double fast_val = fastArr[i];
            double slow_val = slowArr[i];

            if(fast_val > slow_val && fast_val != 0 && slow_val != 0) signal = 1.0;
            else if(fast_val < slow_val && fast_val != 0 && slow_val != 0) signal = -1.0;
            
            SignalBuffer[i]     = signal;
            ConfidenceBuffer[i] = (signal != 0.0) ? 10.0 : 0.0;
            ReasonCodeBuffer[i] = (signal != 0.0) ? (double)REASON_TEST_SCENARIO : (double)REASON_NONE;
            ZoneTFBuffer[i]     = (double)PeriodSeconds(_Period);
        }
    }
    else
    {
        for(int i = start_bar; i >= 1; i--)
        {
            double signal = 0.0, conf = 0.0;
            ENUM_REASON_CODE reasonCode = REASON_NONE;
            
            double htfBias_arr[1], htfConf_arr[1];
            double zeStatus_arr[1], zeStrength_arr[1], zeLiquidity_arr[1];
            
            htfBias_arr[0] = 0; htfConf_arr[0] = 0;
            zeStatus_arr[0] = 0;
            zeStrength_arr[0] = 0; zeLiquidity_arr[0] = 0;

            if(BC_handle != INVALID_HANDLE)
            {
                CopyBuffer(BC_handle, 0, i, 1, htfBias_arr);
                CopyBuffer(BC_handle, 2, i, 1, htfConf_arr);
            }

            if(ZE_handle != INVALID_HANDLE)
            {
                CopyBuffer(ZE_handle, 0, i, 1, zeStatus_arr);
                CopyBuffer(ZE_handle, 2, i, 1, zeStrength_arr);
                CopyBuffer(ZE_handle, 5, i, 1, zeLiquidity_arr);
            }
            
            double htfBias = htfBias_arr[0];
            double htfConf = htfConf_arr[0];
            double zoneStatus = zeStatus_arr[0];
            double zoneStrength = zeStrength_arr[0];
            double liquidity = zeLiquidity_arr[0];

            if(zoneStatus > 0.5) // Demand Zone
            {
                if(htfBias > 0.5) // Bullish Bias
                {
                    if(zoneStrength >= MinZoneStrength)
                    {
                        signal = 1.0;
                        conf = zoneStrength + htfConf;
                        reasonCode = (liquidity > 0.5) ? REASON_BUY_LIQ_GRAB_ALIGNED : REASON_BUY_HTF_CONTINUATION;
                    } else { reasonCode = REASON_LOW_ZONE_STRENGTH; }
                } else { reasonCode = REASON_BIAS_CONFLICT; }
            }
            else if(zoneStatus < -0.5) // Supply Zone
            {
                if(htfBias < -0.5) // Bearish Bias
                {
                    if(zoneStrength >= MinZoneStrength)
                    {
                        signal = -1.0;
                        conf = zoneStrength + htfConf;
                        reasonCode = (liquidity > 0.5) ? REASON_SELL_LIQ_GRAB_ALIGNED : REASON_SELL_HTF_CONTINUATION;
                    } else { reasonCode = REASON_LOW_ZONE_STRENGTH; }
                } else { reasonCode = REASON_BIAS_CONFLICT; }
            }
            else
            {
               reasonCode = REASON_NO_ZONE;
            }
            
            SignalBuffer[i]     = signal;
            ConfidenceBuffer[i] = conf;
            ReasonCodeBuffer[i] = (double)reasonCode;
            ZoneTFBuffer[i]     = (double)PeriodSeconds(_Period);
        }
    }
    
    // --- Mirror the last closed bar to the current bar for visual convenience ---
    SignalBuffer[0]     = SignalBuffer[1];
    ConfidenceBuffer[0] = ConfidenceBuffer[1];
    ReasonCodeBuffer[0] = ReasonCodeBuffer[1];
    ZoneTFBuffer[0]     = ZoneTFBuffer[1];

    // --- Optional Debug Logging ---
    if(EnableDebugLogging && time[rates_total-1] != g_last_log_time)
    {
        PrintFormat("[SB_OUT] t=%s sig=%.1f conf=%.1f reason=%g ztf=%g",
                    TimeToString(time[rates_total-2]), // Log time of closed bar
                    SignalBuffer[1],
                    ConfidenceBuffer[1],
                    ReasonCodeBuffer[1],
                    ZoneTFBuffer[1]);
        g_last_log_time = time[rates_total-1];
    }

    return(rates_total);
}
//+------------------------------------------------------------------+
