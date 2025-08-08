//+------------------------------------------------------------------+
//|                       AlfredAlertCenter.mq5                      |
//|                  v2.0 - Brain Integrated (Live)                  |
//|       Sends Telegram alerts based on AlfredBrain signals.        |
//|              Copyright 2025, AlfredAI Project                    |
//+------------------------------------------------------------------+
#property indicator_chart_window
#property strict
#property version "2.0"
#property description "Sends Telegram alerts for AlfredBrain signals"

// --- This indicator has no buffers or plots; it only sends alerts.
#property indicator_plots 0

//--- Indicator Inputs
input int    MinConfidenceThreshold = 13;          // Min confidence score (0-20) to trigger an alert
input string TelegramToken          = "8108702678:AAHVifzEw3AHY8rzcBxwvRbiqPEoZ1ZH6Nk"; // Your Telegram Bot Token
input string TelegramChatID         = "8336722682";   // Your Telegram Chat ID or Channel ID

// --- Globals to prevent duplicate alerts
static datetime g_lastAlertBarTime = 0;

// --- Helper Enums (copied from AlfredBrain for decoding)
enum ENUM_TRADE_SIGNAL
{
    SIGNAL_NONE = 0,
    SIGNAL_BUY  = 1,
    SIGNAL_SELL = -1
};

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
   //--- Check if WebRequest is allowed (FIXED using integer value)
   // The integer value for TERMINAL_WEBREQUEST_ENABLED is 26.
   if((int)TerminalInfoInteger(26) == 0)
     {
      Print("Error: WebRequest is not enabled. Please go to Tools -> Options -> Expert Advisors and add 'https://api.telegram.org' to the list.");
      return(INIT_FAILED);
     }
   Print("✅ AlfredAlertCenter Initialized. Monitoring for high-confidence signals...");
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

    //--- 1. Fetch latest data from AlfredBrain ---
    double brain_data[4]; // 0:Signal, 1:Confidence, 2:ReasonCode, 3:ZoneTF
    if(CopyBuffer(iCustom(_Symbol, _Period, "AlfredBrain.ex5"), 0, 0, 4, brain_data) < 4)
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
   if(TelegramToken == "<YOUR_BOT_TOKEN>" || TelegramChatID == "<YOUR_CHAT_ID>" || TelegramToken == "" || TelegramChatID == "")
     {
      Print("Telegram credentials are not set. Please update indicator inputs.");
      return;
     }

   //--- 2. Format the message components
   string signal_str = (signal == SIGNAL_BUY) ? "BUY" : "SELL";
   string zone_tf_str = PeriodMinutesToTFString(zone_tf_minutes);
   string reason_str = ReasonCodeToString(reason);
   string server_time_str = TimeToString(TimeCurrent(), TIME_MINUTES);

   //--- 3. Build the full message string
   string message = "🚨 *AlfredAI Trade Alert* 🚨\n\n"
                    "📈 *Signal:* " + signal_str + "\n"
                    "🔹 *Confidence:* " + (string)confidence + " / 20\n"
                    "🧱 *Zone:* " + zone_tf_str + ((signal == SIGNAL_BUY) ? " Demand" : " Supply") + "\n"
                    "🧠 *Alfred Says:* \"" + reason_str + "\"\n\n"
                    "💬 *Time:* " + server_time_str + " (server) | *Symbol:* " + _Symbol;

   //--- 4. URL Encode the message for the web request
   string encoded_message = message;
   StringReplace(encoded_message, " ", "%20");
   StringReplace(encoded_message, "\n", "%0A");
   StringReplace(encoded_message, "&", "%26");
   StringReplace(encoded_message, "*", "%2A");
   StringReplace(encoded_message, "_", "%5F");


   //--- 5. Construct the final URL
   string url = "https://api.telegram.org/bot" + TelegramToken +
                "/sendMessage?chat_id=" + TelegramChatID +
                "&text=" + encoded_message + "&parse_mode=Markdown";

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

//--- Converts reason code buffer value to a readable string
string ReasonCodeToString(ENUM_REASON_CODE code)
{
    switch(code)
    {
        case REASON_BUY_LIQ_GRAB_ALIGNED:
            return "Strong demand + liquidity grab + HTF bias match.";
        case REASON_SELL_LIQ_GRAB_ALIGNED:
            return "Strong supply + liquidity grab + HTF bias match.";
        // These reasons won't typically generate alerts but are here for completeness
        case REASON_NO_ZONE:
            return "Price is not inside an active Supply/Demand zone.";
        case REASON_LOW_ZONE_STRENGTH:
            return "Active zone strength is below threshold.";
        case REASON_BIAS_CONFLICT:
            return "HTF and LTF biases are in conflict.";
        case REASON_NONE:
        default:
            return "High confluence setup detected.";
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
