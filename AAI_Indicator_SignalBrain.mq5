//+------------------------------------------------------------------+
//|                  AAI_Indicator_SignalBrain.mq5                   |
//|                 v2.4 - Debug Logging Forced ON                   |
//|          Acts as the confluence and trade signal engine.         |
//|              Copyright 2025, AlfredAI Project                    |
//+------------------------------------------------------------------+

#property indicator_chart_window
#property strict
#property version "2.4"

// --- Brain Outputs (Exported via Buffers)
#property indicator_buffers 4
#property indicator_plots   4

// --- Buffer 0: Trade Signal (1=BUY, -1=SELL, 0=NONE)
#property indicator_type1   DRAW_NONE
#property indicator_label1  "TradeSignal"
double SignalBuffer[];

// --- Buffer 1: Confidence Score (0-20)
#property indicator_type2   DRAW_NONE
#property indicator_label2  "ConfidenceScore"
double ConfidenceBuffer[];

// --- Buffer 2: Reason Code (for comments/logging)
#property indicator_type3   DRAW_NONE
#property indicator_label3  "ReasonCode"
double ReasonCodeBuffer[];

// --- Buffer 3: Timeframe of the Zone that triggered the signal
#property indicator_type4   DRAW_NONE
#property indicator_label4  "ZoneTimeframe"
double ZoneTFBuffer[];


//--- Indicator Inputs ---
input int  MinZoneStrength    = 4;      // Minimum zone strength score (1-10) to consider for a signal

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
    REASON_BUY_HTF_CONTINUATION,     // Standard Buy: HTF Trend + Zone Pullback
    REASON_SELL_HTF_CONTINUATION,    // Standard Sell: HTF Trend + Zone Pullback
    REASON_BUY_LIQ_GRAB_ALIGNED,     // Premium Buy: Std + Liq Grab
    REASON_SELL_LIQ_GRAB_ALIGNED,    // Premium Sell: Std + Liq Grab
    REASON_NO_ZONE,
    REASON_LOW_ZONE_STRENGTH,
    REASON_BIAS_CONFLICT
};

// --- Constants for Analysis
const ENUM_TIMEFRAMES HTF = PERIOD_H4;
const ENUM_TIMEFRAMES LTF = PERIOD_M15;
// --- DEBUG FLAG ---
const bool EnableDebugLogging = true; // DEBUG: This is now hard-coded to ON for testing.

// --- Globals
datetime g_lastBarTime = 0;

//+------------------------------------------------------------------+
//| Custom indicator initialization function                         |
//+------------------------------------------------------------------+
int OnInit()
{
    //--- Setup Buffers
    SetIndexBuffer(0, SignalBuffer, INDICATOR_DATA);
    SetIndexBuffer(1, ConfidenceBuffer, INDICATOR_DATA);
    SetIndexBuffer(2, ReasonCodeBuffer, INDICATOR_DATA);
    SetIndexBuffer(3, ZoneTFBuffer, INDICATOR_DATA);
    
    //--- Initialize Buffers
    ArrayInitialize(SignalBuffer, 0.0);
    ArrayInitialize(ConfidenceBuffer, 0.0);
    ArrayInitialize(ReasonCodeBuffer, 0.0);
    ArrayInitialize(ZoneTFBuffer, 0.0);

    return(INIT_SUCCEEDED);
}

//+------------------------------------------------------------------+
//| Main Calculation - Runs once per bar                             |
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
    //--- Only run on the close of a new bar
    if(rates_total < 2 || time[rates_total - 1] == g_lastBarTime)
    {
        return(rates_total);
    }
    g_lastBarTime = time[rates_total - 1];
    
    //--- 1. Initialize variables for this run
    ENUM_TRADE_SIGNAL signal = SIGNAL_NONE;
    int confidence = 0;
    ENUM_REASON_CODE reasonCode = REASON_NONE;
    int zoneTimeframe = 0;

    //--- 2. Fetch data from AAI Modules on the current timeframe (_Period)
    double zone_engine_data[6]; // 0:Status, 1:Magnet, 2:Strength, 3:Fresh, 4:Vol, 5:Liq
    if(CopyBuffer(iCustom(_Symbol, _Period, "AAI_Indicator_ZoneEngine.ex5"), 0, 0, 6, zone_engine_data) < 6)
    {
       return(rates_total);
    }
    
    double zone_status         = zone_engine_data[0];
    double zone_strength       = zone_engine_data[2];
    bool   has_liquidity_grab  = (zone_engine_data[5] > 0.5);
    
    double htf_bias_arr[1], ltf_bias_arr[1];
    CopyBuffer(iCustom(_Symbol, HTF, "AAI_Indicator_BiasCompass.ex5"), 0, 0, 1, htf_bias_arr);
    CopyBuffer(iCustom(_Symbol, LTF, "AAI_Indicator_BiasCompass.ex5"), 0, 0, 1, ltf_bias_arr);
    double htf_bias = htf_bias_arr[0];
    double ltf_bias = ltf_bias_arr[0];

    //--- NEW: Debug Logging ---
    if(EnableDebugLogging)
    {
        string debug_msg = StringFormat("BrainDebug | BarTime: %s | ZoneStatus: %.0f, ZoneStr: %.0f, LiqGrab: %s | HTFBias: %.1f, LTFBias: %.1f",
                                        TimeToString(time[rates_total-1]),
                                        zone_status,
                                        zone_strength,
                                        has_liquidity_grab ? "true" : "false",
                                        htf_bias,
                                        ltf_bias);
        Print(debug_msg);
    }


    //--- 3. Pre-analysis checks (exit conditions)
    if(zone_status == 0)
    {
        reasonCode = REASON_NO_ZONE;
    }
    else if(zone_strength < MinZoneStrength)
    {
        reasonCode = REASON_LOW_ZONE_STRENGTH;
    }
    else
    {
        //--- 4. Main analysis logic if pre-checks pass
        
        // --- Check for Bias Conflict FIRST ---
        if (htf_bias * ltf_bias < -0.5) 
        {
            reasonCode = REASON_BIAS_CONFLICT;
        }
        else
        {
            // --- LOGIC PATH 1: A+ Reversal Setup (Highest Confidence) ---
            if(has_liquidity_grab)
            {
                if(zone_status > 0.5 && ltf_bias > 0.5) // Demand Zone + LTF Bullish Bias
                {
                    signal = SIGNAL_BUY;
                    reasonCode = REASON_BUY_LIQ_GRAB_ALIGNED;
                    confidence = 13; // High base confidence
                    if (htf_bias > 0.5) confidence += 5; // HTF alignment bonus
                }
                else if(zone_status < -0.5 && ltf_bias < -0.5) // Supply Zone + LTF Bearish Bias
                {
                    signal = SIGNAL_SELL;
                    reasonCode = REASON_SELL_LIQ_GRAB_ALIGNED;
                    confidence = 13; // High base confidence
                    if (htf_bias < -0.5) confidence += 5; // HTF alignment bonus
                }
            }
            
            // --- LOGIC PATH 2: HTF Continuation Setup (Standard Confidence) ---
            // This runs only if the A+ setup was not found
            if(signal == SIGNAL_NONE)
            {
                if(zone_status > 0.5 && htf_bias > 0.5) // Demand Zone & HTF Bullish Trend
                {
                    signal = SIGNAL_BUY;
                    reasonCode = REASON_BUY_HTF_CONTINUATION;
                    confidence = 8; // Standard base confidence
                }
                else if(zone_status < -0.5 && htf_bias < -0.5) // Supply Zone & HTF Bearish Trend
                {
                    signal = SIGNAL_SELL;
                    reasonCode = REASON_SELL_HTF_CONTINUATION;
                    confidence = 8; // Standard base confidence
                }
            }
        }
        
        zoneTimeframe = (int)PeriodSeconds(_Period) / 60;
    }

    //--- Clamp confidence to the 0-20 range
    confidence = MathMax(0, MathMin(20, confidence));
    
    // If confidence is zero, there is no valid signal
    if(confidence == 0)
    {
       signal = SIGNAL_NONE;
       // Keep the reason code if it was a specific failure (e.g., conflict, no zone)
       if(reasonCode != REASON_NO_ZONE && reasonCode != REASON_LOW_ZONE_STRENGTH && reasonCode != REASON_BIAS_CONFLICT)
       {
          reasonCode = REASON_NONE;
       }
    }

    //--- 5. Populate indicator buffers
    int bar = rates_total - 1;
    SignalBuffer[bar]     = signal;
    ConfidenceBuffer[bar] = confidence;
    ReasonCodeBuffer[bar] = reasonCode;
    ZoneTFBuffer[bar]     = zoneTimeframe;

    // Also populate previous bar to ensure data is available for EAs
    if(bar > 0)
    {
        SignalBuffer[bar - 1]     = SignalBuffer[bar];
        ConfidenceBuffer[bar - 1] = ConfidenceBuffer[bar];
        ReasonCodeBuffer[bar - 1] = ReasonCodeBuffer[bar];
        ZoneTFBuffer[bar - 1]     = ZoneTFBuffer[bar];
    }

    return(rates_total);
}
//+------------------------------------------------------------------+
