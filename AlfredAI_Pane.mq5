//+------------------------------------------------------------------+
//|                        AlfredAI_Pane.mq5                         |
//|               Refactored for Clarity and Performance             |
//|                    Copyright 2024, RudiKai                       |
//|                     https://github.com/RudiKai                   |
//+------------------------------------------------------------------+
#property strict
#property indicator_chart_window
#property indicator_plots 0 // Suppress "no indicator plot" warning

// --- Includes
#include <ChartObjects\ChartObjectsTxtControls.mqh>
#include <AlfredAlertCenter_Include.mqh> // <-- NEW: Integration with AlertCenter

// --- Enums for State Management (Clean & Safe)
enum ENUM_BIAS
{
    BIAS_BULL,
    BIAS_BEAR,
    BIAS_NEUTRAL
};

enum ENUM_ZONE
{
    ZONE_DEMAND,
    ZONE_SUPPLY,
    ZONE_NONE
};

// --- Structs for Data Handling
struct LiveTradeData
{
    bool   trade_exists;
    double entry;
    double sl;
    double tp;

    LiveTradeData() { trade_exists = false; entry = 0.0; sl = 0.0; tp = 0.0; }
    // Copy constructor to resolve compiler warning
    LiveTradeData(const LiveTradeData &other)
    {
        trade_exists = other.trade_exists;
        entry = other.entry;
        sl = other.sl;
        tp = other.tp;
    }
};

struct SignalData
{
    ENUM_BIAS direction;
    double    confidence; // 0.0 to 100.0

    SignalData(const SignalData &other) { direction = other.direction; confidence = other.confidence; }
    SignalData() {}
};


// --- Constants for Panel Layout
#define PANE_PREFIX "AlfredPane_"
#define PANE_WIDTH 220
#define PANE_X_POS 10
#define PANE_Y_POS 10
#define PANE_BG_COLOR clrDimGray
#define PANE_BG_OPACITY 204
#define CONFIDENCE_BAR_MAX_WIDTH 100
#define BIAS_CONFIRMATION_COUNT 3
#define ALERT_COOLDOWN_SECONDS 300

// --- Colors
#define COLOR_BULL clrLimeGreen
#define COLOR_BEAR clrOrangeRed
#define COLOR_NEUTRAL clrWhite
#define COLOR_HEADER clrSilver
#define COLOR_TOGGLE clrLightGray
#define COLOR_ALFRED_MSG clrLightYellow
#define COLOR_DEMAND clrLimeGreen
#define COLOR_SUPPLY clrOrangeRed
#define COLOR_CONF_HIGH clrSeaGreen
#define COLOR_CONF_MED clrGoldenrod
#define COLOR_CONF_LOW clrFireBrick
#define COLOR_SEPARATOR clrGray

// --- Font Sizes & Spacing
#define FONT_SIZE_NORMAL 8
#define FONT_SIZE_HEADER 9
#define SPACING_MEDIUM 16
#define SPACING_LARGE 24
#define SPACING_SEPARATOR 12

// --- Indicator Handles & Globals
int hATR_current;
int atr_period = 14;
bool g_biases_expanded = true;
bool g_hud_expanded = true;
ENUM_BIAS g_last_displayed_bias[6];
ENUM_BIAS g_pending_bias[6];
int       g_confirmation_count[6];
datetime  g_last_alert_time = 0;
ENUM_BIAS g_last_final_signal = BIAS_NEUTRAL;
ENUM_ZONE g_last_zone_status = ZONE_NONE;
double g_pip_value;


//+------------------------------------------------------------------+
//|                  REAL DATA INTEGRATION FUNCTIONS                 |
//+------------------------------------------------------------------+
ENUM_BIAS GetCompassBiasTF(string tf)
{
    // --- LIVE DATA from AlfredCompass.mq5 ---
    int tf_index = -1;
    if(tf == "M1") tf_index = 0; else if(tf == "M5") tf_index = 1; else if(tf == "M15") tf_index = 2;
    else if(tf == "H1") tf_index = 3; else if(tf == "H4") tf_index = 4; else if(tf == "D1") tf_index = 5;
    if(tf_index == -1) return BIAS_NEUTRAL;

    static ENUM_BIAS last_known_bias[6];
    double raw_value = iCustom(_Symbol, 0, "AlfredCompass", tf_index, 0);

    if(raw_value == EMPTY_VALUE) return last_known_bias[tf_index];

    ENUM_BIAS current_bias = (raw_value > 0) ? BIAS_BULL : (raw_value < 0) ? BIAS_BEAR : BIAS_NEUTRAL;
    last_known_bias[tf_index] = current_bias;
    return current_bias;
}

ENUM_ZONE GetZoneStatus()
{
    // --- LIVE DATA from AlfredSupDemCore.mq5 ---
    static ENUM_ZONE last_known_zone = ZONE_NONE;
    double raw_value = iCustom(_Symbol, 0, "AlfredSupDemCore", 0, 0);

    if(raw_value == EMPTY_VALUE) return last_known_zone;

    ENUM_ZONE current_zone = (raw_value > 0) ? ZONE_DEMAND : (raw_value < 0) ? ZONE_SUPPLY : ZONE_NONE;
    last_known_zone = current_zone;
    return current_zone;
}

LiveTradeData FetchTradeLevels()
{
    LiveTradeData data;
    for(int i = PositionsTotal() - 1; i >= 0; i--)
    {
        if(PositionGetString(POSITION_SYMBOL) == _Symbol)
        {
            data.trade_exists = true;
            data.entry = PositionGetDouble(POSITION_PRICE_OPEN);
            data.sl = PositionGetDouble(POSITION_SL);
            data.tp = PositionGetDouble(POSITION_TP);
            break;
        }
    }
    return data;
}

SignalData GetSignalData()
{
    // --- MOCK DATA FOR TESTING ALERTS ---
    SignalData data;
    if(TimeCurrent() % 20 > 10)
    {
       data.direction = BIAS_BULL;
    }
    else
    {
       data.direction = BIAS_BEAR;
    }
    data.confidence = 85.0;
    return data;
}


//+------------------------------------------------------------------+
//|                        ALERTING SYSTEM                           |
//+------------------------------------------------------------------+
void PaneTriggerAlert(string msg)
{
    // Enforce a 5-minute cooldown between alerts
    if(TimeCurrent() - g_last_alert_time < ALERT_COOLDOWN_SECONDS) return;

    // --- NEW: Send alert to the central AlertCenter ---
    AlertCenter_Send("Pane", msg);
    
    // Update the timestamp locally to maintain the cooldown
    g_last_alert_time = TimeCurrent();
}


//+------------------------------------------------------------------+
//|                   HELPER & CONVERSION FUNCTIONS                  |
//+------------------------------------------------------------------+
double CalculatePips(double price1, double price2)
{
    if(g_pip_value == 0 || price1 == 0 || price2 == 0) return 0;
    return MathAbs(price1 - price2) / g_pip_value;
}

string BiasToString(ENUM_BIAS bias)
{
    switch(bias) { case BIAS_BULL: return "BUY"; case BIAS_BEAR: return "SELL"; default: return "NEUTRAL"; }
}

color BiasToColor(ENUM_BIAS bias)
{
    switch(bias) { case BIAS_BULL: return COLOR_BULL; case BIAS_BEAR: return COLOR_BEAR; default: return COLOR_NEUTRAL; }
}

string ZoneToString(ENUM_ZONE zone)
{
    switch(zone) { case ZONE_DEMAND: return "Demand"; case ZONE_SUPPLY: return "Supply"; default: return "None"; }
}

color ZoneToColor(ENUM_ZONE zone)
{
    switch(zone) { case ZONE_DEMAND: return COLOR_DEMAND; case ZONE_SUPPLY: return COLOR_SUPPLY; default: return COLOR_NEUTRAL; }
}


//+------------------------------------------------------------------+
//|                       UI DRAWING HELPERS                         |
//+------------------------------------------------------------------+
void CreateLabel(string name, string text, int x, int y, color clr, int font_size=FONT_SIZE_NORMAL, ENUM_ANCHOR_POINT anchor=ANCHOR_LEFT)
{
    string obj_name = PANE_PREFIX + name;
    ObjectCreate(0, obj_name, OBJ_LABEL, 0, 0, 0);
    ObjectSetString(0, obj_name, OBJPROP_TEXT, text);
    ObjectSetInteger(0, obj_name, OBJPROP_XDISTANCE, x);
    ObjectSetInteger(0, obj_name, OBJPROP_YDISTANCE, y);
    ObjectSetInteger(0, obj_name, OBJPROP_COLOR, clr);
    ObjectSetInteger(0, obj_name, OBJPROP_FONTSIZE, font_size);
    ObjectSetString(0, obj_name, OBJPROP_FONT, "Arial");
    ObjectSetInteger(0, obj_name, OBJPROP_ANCHOR, anchor);
    ObjectSetInteger(0, obj_name, OBJPROP_BACK, false);
}

void CreateRectangle(string name, int x, int y, int width, int height, color clr, ENUM_BORDER_TYPE border=BORDER_FLAT)
{
    string obj_name = PANE_PREFIX + name;
    ObjectCreate(0, obj_name, OBJ_RECTANGLE_LABEL, 0, 0, 0);
    ObjectSetInteger(0, obj_name, OBJPROP_XDISTANCE, x);
    ObjectSetInteger(0, obj_name, OBJPROP_YDISTANCE, y);
    ObjectSetInteger(0, obj_name, OBJPROP_XSIZE, width);
    ObjectSetInteger(0, obj_name, OBJPROP_YSIZE, height);
    ObjectSetInteger(0, obj_name, OBJPROP_BGCOLOR, clr);
    ObjectSetInteger(0, obj_name, OBJPROP_COLOR, clr);
    ObjectSetInteger(0, obj_name, OBJPROP_BORDER_TYPE, border);
    ObjectSetInteger(0, obj_name, OBJPROP_BACK, true);
}

void UpdateLabel(string name, string text, color clr = clrNONE)
{
    string obj_name = PANE_PREFIX + name;
    if(ObjectFind(0, obj_name) < 0) return;
    ObjectSetString(0, obj_name, OBJPROP_TEXT, text);
    if(clr != clrNONE) ObjectSetInteger(0, obj_name, OBJPROP_COLOR, clr);
}

//+------------------------------------------------------------------+
//|                MAIN PANEL CREATION & UPDATE LOGIC                |
//+------------------------------------------------------------------+
void CreatePanel()
{
    int x_offset = PANE_X_POS + 10;
    int y_offset = PANE_Y_POS + 10;
    int x_col2_prefix = x_offset + 55;
    int x_col2_value = x_col2_prefix + 50;
    int x_toggle = PANE_X_POS + PANE_WIDTH - 20;

    CreateLabel("symbol_header", _Symbol, x_offset, y_offset, COLOR_HEADER, 10);
    y_offset += SPACING_LARGE;

    // --- TF Biases Section
    CreateLabel("biases_header", "TF Biases", x_offset, y_offset, COLOR_HEADER, FONT_SIZE_HEADER);
    CreateLabel("biases_toggle", g_biases_expanded ? "[-]" : "[+]", x_toggle, y_offset, COLOR_TOGGLE, FONT_SIZE_HEADER);
    y_offset += SPACING_MEDIUM;
    if(g_biases_expanded)
    {
        int x_bias_prefix = x_offset + 100;
        int x_bias_value  = x_bias_prefix + 32;
        string tfs[] = {"M1", "M5", "M15", "H1", "H4", "D1"};
        for(int i=0; i<ArraySize(tfs); i++)
        {
            CreateLabel("biases_"+tfs[i]+"_prefix", tfs[i]+":", x_bias_prefix, y_offset, COLOR_HEADER, FONT_SIZE_NORMAL);
            CreateLabel("biases_"+tfs[i]+"_value", "-", x_bias_value, y_offset, COLOR_NEUTRAL, FONT_SIZE_NORMAL);
            y_offset += SPACING_MEDIUM;
        }
    }
    y_offset += SPACING_SEPARATOR - (g_biases_expanded ? SPACING_MEDIUM : 0);
    CreateRectangle("sep1", x_offset, y_offset, PANE_WIDTH - 20, 1, COLOR_SEPARATOR, BORDER_FLAT);
    y_offset += SPACING_SEPARATOR;

    // --- HUD Metrics Section
    CreateLabel("hud_header", "HUD Metrics", x_offset, y_offset, COLOR_HEADER, FONT_SIZE_HEADER);
    CreateLabel("hud_toggle", g_hud_expanded ? "[-]" : "[+]", x_toggle, y_offset, COLOR_TOGGLE, FONT_SIZE_HEADER);
    y_offset += SPACING_MEDIUM;
    if(g_hud_expanded)
    {
        CreateLabel("hud_spread", "Spread:", x_col2_prefix, y_offset, COLOR_HEADER, FONT_SIZE_NORMAL);
        CreateLabel("hud_spread_val", "-", x_col2_value, y_offset, COLOR_NEUTRAL, FONT_SIZE_NORMAL);
        y_offset += SPACING_MEDIUM;
        CreateLabel("hud_atr", "ATR ("+IntegerToString(atr_period)+"):", x_col2_prefix, y_offset, COLOR_HEADER, FONT_SIZE_NORMAL);
        CreateLabel("hud_atr_val", "-", x_col2_value, y_offset, COLOR_NEUTRAL, FONT_SIZE_NORMAL);
    }
    y_offset += SPACING_SEPARATOR - (g_hud_expanded ? SPACING_MEDIUM : 0);
    CreateRectangle("sep2", x_offset, y_offset, PANE_WIDTH - 20, 1, COLOR_SEPARATOR, BORDER_FLAT);
    y_offset += SPACING_SEPARATOR;

    // --- Final Signal Section
    CreateLabel("signal_header", "Final Signal", x_offset, y_offset, COLOR_HEADER, FONT_SIZE_HEADER);
    y_offset += SPACING_MEDIUM;
    CreateLabel("signal_dir_prefix", "Signal:", x_col2_prefix, y_offset, COLOR_HEADER, FONT_SIZE_NORMAL);
    CreateLabel("signal_dir_value", "-", x_col2_value, y_offset, COLOR_NEUTRAL, FONT_SIZE_NORMAL);
    y_offset += SPACING_MEDIUM;
    CreateLabel("signal_conf_prefix", "Confidence:", x_col2_prefix, y_offset, COLOR_HEADER, FONT_SIZE_NORMAL);
    CreateLabel("signal_conf_value", "-", x_col2_value + 60, y_offset, COLOR_NEUTRAL, FONT_SIZE_NORMAL);
    CreateRectangle("signal_conf_bar_bg", x_col2_value, y_offset, CONFIDENCE_BAR_MAX_WIDTH, 10, clrGray, BORDER_FLAT);
    CreateRectangle("signal_conf_bar_fg", x_col2_value, y_offset, 0, 10, clrNONE, BORDER_FLAT);
    y_offset += SPACING_MEDIUM;
    CreateLabel("magnet_zone_prefix", "Magnet Zone:", x_col2_prefix, y_offset, COLOR_HEADER, FONT_SIZE_NORMAL);
    CreateLabel("magnet_zone_value", "-", x_col2_value, y_offset, COLOR_NEUTRAL, FONT_SIZE_NORMAL);
    y_offset += SPACING_SEPARATOR;
    CreateRectangle("sep3", x_offset, y_offset, PANE_WIDTH - 20, 1, COLOR_SEPARATOR, BORDER_FLAT);
    y_offset += SPACING_SEPARATOR;

    // --- Trade Now Section
    CreateLabel("trade_header", "Trade Now", x_offset, y_offset, COLOR_HEADER, FONT_SIZE_HEADER);
    y_offset += SPACING_MEDIUM;
    CreateLabel("trade_entry_prefix", "Entry:", x_col2_prefix, y_offset, COLOR_HEADER, FONT_SIZE_NORMAL);
    CreateLabel("trade_entry_value", "-", x_col2_value, y_offset, COLOR_NEUTRAL, FONT_SIZE_NORMAL);
    y_offset += SPACING_MEDIUM;
    CreateLabel("trade_tp_prefix", "TP:", x_col2_prefix, y_offset, COLOR_HEADER, FONT_SIZE_NORMAL);
    CreateLabel("trade_tp_value", "-", x_col2_value, y_offset, COLOR_NEUTRAL, FONT_SIZE_NORMAL);
    y_offset += SPACING_MEDIUM;
    CreateLabel("trade_sl_prefix", "SL:", x_col2_prefix, y_offset, COLOR_HEADER, FONT_SIZE_NORMAL);
    CreateLabel("trade_sl_value", "-", x_col2_value, y_offset, COLOR_NEUTRAL, FONT_SIZE_NORMAL);
    y_offset += SPACING_MEDIUM;
    CreateLabel("trade_status_prefix", "Status:", x_col2_prefix, y_offset, COLOR_HEADER, FONT_SIZE_NORMAL);
    CreateLabel("trade_status_value", "☐ No Trade", x_col2_value, y_offset, COLOR_NEUTRAL, FONT_SIZE_NORMAL);
    y_offset += SPACING_SEPARATOR;
    CreateRectangle("sep4", x_offset, y_offset, PANE_WIDTH - 20, 1, COLOR_SEPARATOR, BORDER_FLAT);
    y_offset += SPACING_SEPARATOR;

    // --- Alfred Says Section
    CreateLabel("alfred_header", "Alfred Says:", x_offset, y_offset, COLOR_HEADER, FONT_SIZE_HEADER);
    y_offset += SPACING_MEDIUM;
    CreateLabel("alfred_says", "Thinking...", x_offset, y_offset, COLOR_ALFRED_MSG, FONT_SIZE_NORMAL);
    y_offset += SPACING_MEDIUM;
    
    // --- Background
    string bg_name = PANE_PREFIX + "background";
    ObjectCreate(0, bg_name, OBJ_RECTANGLE_LABEL, 0, 0, 0);
    ObjectSetInteger(0, bg_name, OBJPROP_XDISTANCE, PANE_X_POS);
    ObjectSetInteger(0, bg_name, OBJPROP_YDISTANCE, PANE_Y_POS);
    ObjectSetInteger(0, bg_name, OBJPROP_XSIZE, PANE_WIDTH);
    ObjectSetInteger(0, bg_name, OBJPROP_YSIZE, y_offset - PANE_Y_POS);
    ObjectSetInteger(0, bg_name, OBJPROP_BACK, true);
    ObjectSetInteger(0, bg_name, OBJPROP_BORDER_TYPE, BORDER_FLAT);
    ObjectSetInteger(0, bg_name, OBJPROP_COLOR, clrNONE);
    color bg_color_opacity = (color)ColorToARGB(PANE_BG_COLOR, PANE_BG_OPACITY);
    ObjectSetInteger(0, bg_name, OBJPROP_BGCOLOR, bg_color_opacity);
}

void UpdatePanel()
{
    // --- Stabilize and Update TF Biases Section
    if(g_biases_expanded)
    {
        string tfs[] = {"M1", "M5", "M15", "H1", "H4", "D1"};
        for(int i=0; i<ArraySize(tfs); i++)
        {
             ENUM_BIAS current_raw_bias = GetCompassBiasTF(tfs[i]);
             if(current_raw_bias == g_pending_bias[i]) g_confirmation_count[i]++;
             else { g_pending_bias[i] = current_raw_bias; g_confirmation_count[i] = 1; }
             
             if(g_confirmation_count[i] >= BIAS_CONFIRMATION_COUNT)
             {
                 ENUM_BIAS confirmed_bias = g_pending_bias[i];
                 if(confirmed_bias != BIAS_NEUTRAL && confirmed_bias != g_last_displayed_bias[i])
                 {
                     g_last_displayed_bias[i] = confirmed_bias;
                     UpdateLabel("biases_"+tfs[i]+"_value", BiasToString(g_last_displayed_bias[i]), BiasToColor(g_last_displayed_bias[i]));
                 }
             }
        }
    }

    // --- Update HUD Metrics Section
    if(g_hud_expanded)
    {
        long spread_points = SymbolInfoInteger(_Symbol, SYMBOL_SPREAD);
        UpdateLabel("hud_spread_val", IntegerToString(spread_points) + " pts", COLOR_NEUTRAL);
        double atr_buffer[1];
        if(CopyBuffer(hATR_current, 0, 0, 1, atr_buffer) > 0)
        {
            UpdateLabel("hud_atr_val", DoubleToString(atr_buffer[0], _Digits), COLOR_NEUTRAL);
        }
    }
    
    SignalData signal = GetSignalData();
    UpdateLabel("signal_dir_value", BiasToString(signal.direction), BiasToColor(signal.direction));
    UpdateLabel("signal_conf_value", StringFormat("%.1f%%", signal.confidence));
    
    int bar_width = (int)(signal.confidence / 100.0 * CONFIDENCE_BAR_MAX_WIDTH);
    color bar_color = COLOR_CONF_LOW;
    if(signal.confidence > 75) bar_color = COLOR_CONF_HIGH;
    else if(signal.confidence > 50) bar_color = COLOR_CONF_MED;
    
    string bar_name = PANE_PREFIX + "signal_conf_bar_fg";
    ObjectSetInteger(0, bar_name, OBJPROP_XSIZE, bar_width);
    ObjectSetInteger(0, bar_name, OBJPROP_BGCOLOR, bar_color);
    ObjectSetInteger(0, bar_name, OBJPROP_COLOR, bar_color);

    ENUM_ZONE magnet_zone = GetZoneStatus();
    UpdateLabel("magnet_zone_value", ZoneToString(magnet_zone), ZoneToColor(magnet_zone));

    if(signal.direction != g_last_final_signal && signal.direction != BIAS_NEUTRAL)
    {
        PaneTriggerAlert("Final Signal changed to " + BiasToString(signal.direction));
        g_last_final_signal = signal.direction;
    }
    if(magnet_zone != g_last_zone_status && magnet_zone != ZONE_NONE)
    {
        PaneTriggerAlert("Magnet Zone changed to " + ZoneToString(magnet_zone));
        g_last_zone_status = magnet_zone;
    }

    LiveTradeData trade_data = FetchTradeLevels();
    string price_format = "%." + IntegerToString(_Digits) + "f";

    if(trade_data.trade_exists)
    {
        UpdateLabel("trade_entry_value", StringFormat(price_format, trade_data.entry), COLOR_NEUTRAL);
        string sl_text = StringFormat(price_format, trade_data.sl) + " (" + DoubleToString(CalculatePips(trade_data.entry, trade_data.sl), 1) + " p)";
        string tp_text = StringFormat(price_format, trade_data.tp) + " (" + DoubleToString(CalculatePips(trade_data.entry, trade_data.tp), 1) + " p)";
        UpdateLabel("trade_sl_value", sl_text, COLOR_NEUTRAL);
        UpdateLabel("trade_tp_value", tp_text, COLOR_NEUTRAL);
        UpdateLabel("trade_status_value", "☑ Active", COLOR_BULL);
    }
    else
    {
        UpdateLabel("trade_entry_value", "---", COLOR_NEUTRAL);
        UpdateLabel("trade_sl_value", "---", COLOR_NEUTRAL);
        UpdateLabel("trade_tp_value", "---", COLOR_NEUTRAL);
        UpdateLabel("trade_status_value", "☐ No Trade", COLOR_NEUTRAL);
    }

    UpdateLabel("alfred_says", "Thinking...", COLOR_ALFRED_MSG);

    ChartRedraw();
}

//+------------------------------------------------------------------+
//| Redraws the entire panel after a state change                    |
//+------------------------------------------------------------------+
void RedrawPanel()
{
    ObjectsDeleteAll(0, PANE_PREFIX);
    CreatePanel();
    UpdatePanel();
    ChartRedraw();
}

//+------------------------------------------------------------------+
//| Custom indicator initialization function                         |
//+------------------------------------------------------------------+
int OnInit()
{
    hATR_current = iATR(_Symbol, _Period, atr_period);
    g_pip_value = SymbolInfoDouble(_Symbol, SYMBOL_POINT);
    if(SymbolInfoInteger(_Symbol, SYMBOL_DIGITS) == 3 || SymbolInfoInteger(_Symbol, SYMBOL_DIGITS) == 5)
    {
        g_pip_value *= 10;
    }
    
    for(int i=0; i<6; i++)
    {
        g_last_displayed_bias[i] = BIAS_NEUTRAL;
        g_pending_bias[i] = BIAS_NEUTRAL;
        g_confirmation_count[i] = 0;
    }
    
    RedrawPanel();
    return(INIT_SUCCEEDED);
}

//+------------------------------------------------------------------+
//| Custom indicator iteration function                              |
//+------------------------------------------------------------------+
int OnCalculate(const int rates_total, const int prev_calculated, const int begin, const double &price[])
{
    UpdatePanel();
    return(rates_total);
}

//+------------------------------------------------------------------+
//| Chart event function                                             |
//+------------------------------------------------------------------+
void OnChartEvent(const int id, const long &lparam, const double &dparam, const string &sparam)
{
    if(id == CHARTEVENT_OBJECT_CLICK)
    {
        bool state_changed = false;
        if(StringFind(sparam, PANE_PREFIX) == 0 && StringFind(sparam, "_toggle") > 0)
        {
            if(sparam == PANE_PREFIX + "biases_toggle") g_biases_expanded = !g_biases_expanded;
            else if(sparam == PANE_PREFIX + "hud_toggle") g_hud_expanded = !g_hud_expanded;
            state_changed = true;
        }

        if(state_changed) RedrawPanel();
    }
}

//+------------------------------------------------------------------+
//| Deinitialization function                                        |
//+------------------------------------------------------------------+
void OnDeinit(const int reason)
{
    IndicatorRelease(hATR_current);
    ObjectsDeleteAll(0, PANE_PREFIX);
    ChartRedraw();
}
//+------------------------------------------------------------------+
