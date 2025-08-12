//+------------------------------------------------------------------+
//|                       AAI_Indicator_Alerts.mq5                     |
//|            v2.2 - Bug Fixes for Compilation                      |
//|       Sends Telegram alerts based on AAI_Indicator_SignalBrain   |
//|                                                                  |
//| Copyright 2025, AlfredAI Project                                 |
//+------------------------------------------------------------------+
#property indicator_chart_window
#property strict
#property version "2.2"
#property description "Sends Telegram alerts for AAI_Indicator_SignalBrain signals"

// --- This indicator has no buffers or plots; it only sends alerts.
#property indicator_plots 0

//--- Indicator Inputs
input int    MinConfidenceThreshold = 13;     // Min confidence score (0-20) to trigger an alert
input bool   AlertsDryRun = true;
input string TelegramToken   = "REPLACE_ME";
input string TelegramChatID  = "REPLACE_ME";

// --- Globals to prevent duplicate alerts
static datetime g_lastAlertBarTime = 0;

// --- Helper Enums (copied from SignalBrain for decoding)
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

//+------------------------------------------------------------------+
//| Custom indicator initialization function                         |
//+------------------------------------------------------------------+
int OnInit()
{
   //--- Check if WebRequest is allowed (FIXED using integer value)
   // The integer value for TERMINAL_WEBREQUEST is 26.
   if((int)TerminalInfoInteger(26) == 0)
     {
      Print("Error: WebRequest is not enabled. Please go to Tools -> Options -> Expert Advisors and add 'https://api.telegram.org' to the list.");
      return(INIT_FAILED);
     }
   Print("✅ AAI Alerts Initialized. Monitoring for high-confidence signals...");
   return(INIT_SUCCEEDED);
}

//+------------------------------------------------------------------+
//| Main Calculation - Runs once per bar to check for alerts         |
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
    if(rates_total < 2)
        return(rates_total);
    datetime currentBarTime = time[rates_total - 1];

    //--- Avoid duplicate alerts on the same bar
    if(currentBarTime == g_lastAlertBarTime)
    {
        return(rates_total);
    }

    //--- 1. Fetch latest data from AAI_Indicator_SignalBrain ---
    double brain_data[4]; // 0:Signal, 1:Confidence, 2:ReasonCode, 3:ZoneTF
    if(CopyBuffer(iCustom(_Symbol, _Period, "AAI_Indicator_SignalBrain.ex5"), 0, 0, 4, brain_data) < 4)
    {
       // If Brain is not available, cannot proceed.
       return(rates_total);
    }

    ENUM_TRADE_SIGNAL signal = (ENUM_TRADE_SIGNAL)brain_data[0];
    double confidence        = brain_data[1];
    ENUM_REASON_CODE reason  = (ENUM_REASON_CODE)brain_data[2];
    int zone_tf_minutes      = (int)brain_data[3];

    //--- 2. Check Alert Conditions ---
    if(signal != SIGNAL_NONE && confidence >= MinConfidenceThreshold)
    {
        //--- Conditions met, send the alert ---
        SendTelegramAlert(signal, confidence, reason, zone_tf_minutes);
        //--- Update the timestamp to prevent sending another alert for this bar
        g_lastAlertBarTime = currentBarTime;
    }

    return(rates_total);
}

//+------------------------------------------------------------------+
//|               SEND TELEGRAM ALERT FUNCTION                     |
//+------------------------------------------------------------------+
void SendTelegramAlert(ENUM_TRADE_SIGNAL signal, double confidence, ENUM_REASON_CODE reason, int zone_tf_minutes)
{
   //--- 1. Validate inputs
   if(TelegramToken == "" || TelegramChatID == "")
     {
      Print("Telegram credentials are not set. Please update indicator inputs.");
      return;
     }

   //--- 2. Format the message components
   string symbol_str    = _Symbol;
   string chart_tf_str  = PeriodToString(_Period);
   string signal_str    = (signal == SIGNAL_BUY) ? "BUY" : "SELL";
   string conf_str      = StringFormat("%.0f%%", (confidence / 20.0) * 100.0);
   string reason_str    = ReasonCodeToShortString(reason);
   string zone_tf_str   = (zone_tf_minutes > 0) ? PeriodMinutesToTFString(zone_tf_minutes) : "None";
   string price_str     = DoubleToString(SymbolInfoDouble(_Symbol, SYMBOL_BID), _Digits);


   //--- 3. Build the full message string (new single-line format)
   string message = StringFormat("[%s][%s] SIGNAL: %s  Conf: %s  Reason: %s  Zone: %s  Price: %s",
                                 symbol_str,
                                 chart_tf_str,
                                 signal_str,
                                 conf_str,
                                 reason_str,
                                 zone_tf_str,
                                 price_str
                                );

   //--- 4. URL Encode the message for the web request
   string encoded_message = message;
   StringReplace(encoded_message, " ", "%20");
   StringReplace(encoded_message, "&", "%26");

   //--- 5. Construct the final URL (no markdown needed)
   string url = "https://api.telegram.org/bot" + TelegramToken +
                "/sendMessage?chat_id=" + TelegramChatID +
                "&text=" + encoded_message;

   //--- 6. Send the WebRequest
   char post_data[];
   char result[];
   int result_code;
   string result_headers;

   ResetLastError();
   result_code = WebRequest("GET", url, NULL, NULL, 5000, post_data, 0, result, result_headers);

   //--- 7. Handle the response
   if(result_code == 200)
     {
      Print("Telegram alert sent successfully for " + _Symbol);
     }
   else
     {
      PrintFormat("Error sending Telegram alert for %s. Code: %d, Error: %s", _Symbol, result_code, GetLastErrorDescription(GetLastError()));
     }
}


//+------------------------------------------------------------------+
//|                      HELPER FUNCTIONS                          |
//+------------------------------------------------------------------+

//--- Converts reason code to a short, readable string for alerts
string ReasonCodeToShortString(ENUM_REASON_CODE code)
{
    switch(code)
    {
        case REASON_BUY_HTF_CONTINUATION:
        case REASON_SELL_HTF_CONTINUATION:
            return "HTF Cont.";
        case REASON_BUY_LIQ_GRAB_ALIGNED:
        case REASON_SELL_LIQ_GRAB_ALIGNED:
            return "Liq. Grab";
        // These reasons won't typically generate alerts but are here for completeness
        case REASON_NO_ZONE:
            return "No Zone";
        case REASON_LOW_ZONE_STRENGTH:
            return "Low Strength";
        case REASON_BIAS_CONFLICT:
            return "Bias Conflict";
        case REASON_NONE:
        default:
            return "Confluence";
    }
}

//--- Converts zone TF in minutes to a string label
string PeriodMinutesToTFString(int minutes)
{
    if(minutes >= 1440) return "D"+IntegerToString(minutes/1440);
    if(minutes >= 60)   return "H"+IntegerToString(minutes/60);
    if(minutes > 0)     return "M"+IntegerToString(minutes);
    return "Chart"; // Fallback
}

//--- Converts MQL5 ENUM_TIMEFRAMES to a readable string
string PeriodToString(ENUM_TIMEFRAMES period)
{
   switch(period)
   {
      case PERIOD_M1:  return "M1";
      case PERIOD_M5:  return "M5";
      case PERIOD_M15: return "M15";
      case PERIOD_M30: return "M30";
      case PERIOD_H1:  return "H1";
      case PERIOD_H2:  return "H2";
      case PERIOD_H4:  return "H4";
      case PERIOD_D1:  return "D1";
      case PERIOD_W1:  return "W1";
      case PERIOD_MN1: return "MN1";
      default:         return EnumToString(period);
   }
}

//--- Translates MQL5 GetLastError() into a readable string
string GetLastErrorDescription(int error_code)
{
    switch(error_code)
    {
        case 4014: return "WebRequest function is not allowed";
        case 4015: return "Error opening URL";
        case 4016: return "Error connecting to URL";
        case 4017: return "Error sending request";
        case 4018: return "Error receiving data";
        default:   return "Unknown WebRequest error (" + (string)error_code + ")";
    }
}
//+------------------------------------------------------------------+
