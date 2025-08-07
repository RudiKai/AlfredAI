//+------------------------------------------------------------------+
//|                       AlfredDebugHelper.mq5                      |
//|                        v2.0 (Phase 1.2)                          |
//|      Prints live data from Alfred modules for validation.        |
//|              Copyright 2025, AlfredAI Project                    |
//+------------------------------------------------------------------+

#property indicator_chart_window
#property strict
#property version "2.0"

// --- This indicator has no buffers or plots; it only prints.
#property indicator_plots 0

// --- Constants for Analysis (should match AlfredBrain)
const ENUM_TIMEFRAMES HTF = PERIOD_H4;
const ENUM_TIMEFRAMES LTF = PERIOD_M15;

// --- Globals for per-bar execution
datetime g_lastBarTime = 0;

// --- Helper Enums (copied from AlfredBrain for decoding)
enum ENUM_REASON_CODE
{
    REASON_NONE,
    REASON_BUY_LIQ_GRAB_ALIGNED,
    REASON_SELL_LIQ_GRAB_ALIGNED,
    REASON_NO_ZONE,
    REASON_LOW_ZONE_STRENGTH,
    REASON_BIAS_CONFLICT
};

//+------------------------------------------------------------------+
//| Custom indicator initialization function                         |
//+------------------------------------------------------------------+
int OnInit()
{
    Print("✅ AlfredDebugHelper Initialized. Waiting for new bar to print data...");
    return(INIT_SUCCEEDED);
}

//+------------------------------------------------------------------+
//| Main Calculation - Runs once per bar to print debug info         |
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

    //--- 1. Fetch Compass Data ---
    double htf_bias_arr[1], ltf_bias_arr[1];
    CopyBuffer(iCustom(_Symbol, HTF, "AlfredCompass.ex5"), 0, 0, 1, htf_bias_arr);
    CopyBuffer(iCustom(_Symbol, LTF, "AlfredCompass.ex5"), 0, 0, 1, ltf_bias_arr);
    string htf_bias_str = BiasToString(htf_bias_arr[0]);
    string ltf_bias_str = BiasToString(ltf_bias_arr[0]);

    //--- 2. Fetch SupDemCore Data (from current chart timeframe) ---
    double supdem_data[6]; // 0:Status, 1:Magnet, 2:Strength, 3:Fresh, 4:Vol, 5:Liq
    CopyBuffer(iCustom(_Symbol, _Period, "AlfredSupDemCore.ex5"), 0, 0, 6, supdem_data);
    string zone_type_str = ZoneTypeToString(supdem_data[0]);
    double zone_score = supdem_data[2];
    string liq_grab_str = (supdem_data[5] > 0.5) ? "true" : "false";
    
    //--- 3. Fetch Brain Data ---
    double brain_data[4]; // 0:Signal, 1:Confidence, 2:ReasonCode, 3:ZoneTF
    CopyBuffer(iCustom(_Symbol, _Period, "AlfredBrain.ex5"), 0, 0, 4, brain_data);
    string signal_str = SignalToString(brain_data[0]);
    double confidence_score = brain_data[1];
    string reason_str = ReasonCodeToString(brain_data[2]);
    string zone_tf_str = PeriodSecondsToTFString((int)brain_data[3] * 60);
    
    //--- 4. Format and Print All Data ---
    Print("------------------------------------------------------------------");
    PrintFormat("🧭 Compass — HTF Bias: %s, LTF Bias: %s", htf_bias_str, ltf_bias_str);
    PrintFormat("🧱 SupDem — Zone: %s %s | Score: %.0f | LiquidityGrab: %s", zone_tf_str, zone_type_str, zone_score, liq_grab_str);
    PrintFormat("🧠 Brain — Signal: %s | Confidence: %.0f | Reason: \"%s\"", signal_str, confidence_score, reason_str);

    return(rates_total);
}

//+------------------------------------------------------------------+
//|                      HELPER FUNCTIONS                          |
//+------------------------------------------------------------------+

//--- Converts bias buffer value to a readable string
string BiasToString(double bias_value)
{
    if(bias_value > 0.5) return "BULL";
    if(bias_value < -0.5) return "BEAR";
    return "NEUTRAL";
}

//--- Converts zone status buffer value to a readable string
string ZoneTypeToString(double zone_status)
{
    if(zone_status > 0.5) return "Demand";
    if(zone_status < -0.5) return "Supply";
    return "None";
}

//--- Converts signal buffer value to a readable string
string SignalToString(double signal_value)
{
    if(signal_value > 0.5) return "BUY";
    if(signal_value < -0.5) return "SELL";
    return "NONE";
}

//--- Converts timeframe (in seconds) to a short string like "H1"
string PeriodSecondsToTFString(int seconds)
{
    switch(seconds)
    {
        case 900:    return "M15";
        case 1800:   return "M30";
        case 3600:   return "H1";
        case 7200:   return "H2";
        case 14400:  return "H4";
        case 86400:  return "D1";
        default:     return "Chart"; // Fallback for current chart period if not matched
    }
}


//--- Converts reason code buffer value to a readable string
string ReasonCodeToString(double reason_code)
{
    ENUM_REASON_CODE code = (ENUM_REASON_CODE)reason_code;
    switch(code)
    {
        case REASON_BUY_LIQ_GRAB_ALIGNED:
            return "Buy signal due to Liquidity Grab in Demand Zone with Bias Alignment.";
        case REASON_SELL_LIQ_GRAB_ALIGNED:
            return "Sell signal due to Liquidity Grab in Supply Zone with Bias Alignment.";
        case REASON_NO_ZONE:
            return "No signal: Price is not inside an active Supply/Demand zone.";
        case REASON_LOW_ZONE_STRENGTH:
            return "No signal: Active zone strength is below threshold.";
        case REASON_BIAS_CONFLICT:
            return "No signal: HTF and LTF biases are in conflict.";
        case REASON_NONE:
        default:
            return "No signal: Conditions not met.";
    }
}
//+------------------------------------------------------------------+
