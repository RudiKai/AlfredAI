//+------------------------------------------------------------------+
//|                  AAI_Indicator_BiasCompass.mq5                   |
//|              v2.2 - Non-blocking & Headless Refactor             |
//|        (Determines multi-timeframe directional bias)             |
//|                                                                  |
//| Copyright 2025, AlfredAI Project                    |
//+------------------------------------------------------------------+
#property indicator_chart_window
#property strict
#property version "2.2"

// === BEGIN Spec: Headless + single set of properties ===
#property indicator_plots   0
#property indicator_buffers 4
// === END Spec ===

// === BEGIN Spec: Buffer declarations ===
#property indicator_label1 "HTF_Bias"
#property indicator_label2 "LTF_Bias"
#property indicator_label3 "HTF_Conf"
#property indicator_label4 "LTF_Conf"

double BC_HTF_Bias[];
double BC_LTF_Bias[];
double BC_HTF_Conf[];
double BC_LTF_Conf[];
// === END Spec ===

// === BEGIN Spec: SafeTest switch and constants ===
input bool BC_SafeTest = false; // If true, bypasses complex logic for performance testing
static const int BC_WARMUP = 100; // Bars needed for MA calculations to stabilize
// === END Spec ===

// --- Constants for Analysis ---
const ENUM_TIMEFRAMES HTF_TF = PERIOD_H4;
const ENUM_TIMEFRAMES LTF_TF = PERIOD_M15;
const int MA_Period_HTF = 21;
const int MA_Period_LTF = 13;

//+------------------------------------------------------------------+
//| SafeFill: Bypasses logic for performance testing                 |
//+------------------------------------------------------------------+
void BC_SafeFill(const int rates_total, const int prev_calculated)
{
    int start = (prev_calculated > 0 ? prev_calculated - 1 : MathMin(BC_WARMUP, rates_total - 1));
    if(start < 0) start = 0;
    
    for(int i = start; i < rates_total; ++i)
    {
        // Simple oscillating pattern for testing buffer output
        double htfBias = ((i % 32) < 16) ? 1.0 : -1.0;
        double ltfBias = ((i % 8) < 4) ? 1.0 : -1.0;
        BC_HTF_Bias[i] = htfBias;
        BC_LTF_Bias[i] = ltfBias;
        BC_HTF_Conf[i] = 10.0;
        BC_LTF_Conf[i] = 10.0;
    }
}

//+------------------------------------------------------------------+
//| Initialization                                                   |
//+------------------------------------------------------------------+
int OnInit()
{
    // === BEGIN Spec: Bind and configure buffers ===
    bool ok = true;
    ok &= SetIndexBuffer(0, BC_HTF_Bias, INDICATOR_DATA);
    ok &= SetIndexBuffer(1, BC_LTF_Bias, INDICATOR_DATA);
    ok &= SetIndexBuffer(2, BC_HTF_Conf, INDICATOR_DATA);
    ok &= SetIndexBuffer(3, BC_LTF_Conf, INDICATOR_DATA);

    if(!ok)
    {
        Print("BiasCompass: SetIndexBuffer failed");
        return(INIT_FAILED);
    }

    ArraySetAsSeries(BC_HTF_Bias, true);
    ArraySetAsSeries(BC_LTF_Bias, true);
    ArraySetAsSeries(BC_HTF_Conf, true);
    ArraySetAsSeries(BC_LTF_Conf, true);

    // NOTE: 'SetIndexEmptyValue' is not a valid MQL5 function.
    // The OnCalculate loop explicitly writes 0.0 to fulfill this requirement.
    // === END Spec ===

    return(INIT_SUCCEEDED);
}

//+------------------------------------------------------------------+
//| Deinitialization                                                 |
//+------------------------------------------------------------------+
void OnDeinit(const int reason)
{
    // No objects to clean up in headless mode
}

//+------------------------------------------------------------------+
//| Main calculation loop (non-blocking, incremental)                |
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
    // === BEGIN Spec: SafeTest switch ===
    if(BC_SafeTest)
    {
        BC_SafeFill(rates_total, prev_calculated);
        return(rates_total);
    }
    // === END Spec ===

    // === BEGIN Spec: Canonical non-blocking, incremental loop ===
    if(rates_total <= 0) return(0);

    int start = (prev_calculated > 0 ? prev_calculated - 1 : MathMin(BC_WARMUP, rates_total - 1));
    if(start < 0) start = 0;
    if(start >= rates_total) start = rates_total - 1;

    for(int i = start; i < rates_total; ++i)
    {
        // --- Initialize local variables for this bar ---
        double htf_bias = 0.0, ltf_bias = 0.0;
        double htf_conf = 0.0, ltf_conf = 0.0;

        // --- HTF Calculation ---
        int shiftHTF = iBarShift(_Symbol, HTF_TF, time[i], true);
        if(shiftHTF >= 0)
        {
            double hClose = iClose(_Symbol, HTF_TF, shiftHTF);
            // FIX: Corrected iMA parameter count. The shift is the 4th parameter.
            double hEMA   = iMA(_Symbol, HTF_TF, MA_Period_HTF, shiftHTF, MODE_EMA, PRICE_CLOSE);
            if(hClose > hEMA) htf_bias = 1.0;
            if(hClose < hEMA) htf_bias = -1.0;
            htf_conf = 10.0; // Assign a base confidence
        }

        // --- LTF Calculation ---
        int shiftLTF = iBarShift(_Symbol, LTF_TF, time[i], true);
        if(shiftLTF >= 0)
        {
            double lClose = iClose(_Symbol, LTF_TF, shiftLTF);
            // FIX: Corrected iMA parameter count. The shift is the 4th parameter.
            double lEMA   = iMA(_Symbol, LTF_TF, MA_Period_LTF, shiftLTF, MODE_EMA, PRICE_CLOSE);
            if(lClose > lEMA) ltf_bias = 1.0;
            if(lClose < lEMA) ltf_bias = -1.0;
            ltf_conf = 10.0; // Assign a base confidence
        }

        // --- Assign calculated values to buffers ---
        BC_HTF_Bias[i] = htf_bias;
        BC_LTF_Bias[i] = ltf_bias;
        BC_HTF_Conf[i] = htf_conf;
        BC_LTF_Conf[i] = ltf_conf;
    }
    return(rates_total);
    // === END Spec ===
}
//+------------------------------------------------------------------+
