//+------------------------------------------------------------------+
//|                        AlfredAI_Pane.mq5                         |
//|           v2.0 - Live Data Integration from Core Indicators      |
//|                    Copyright 2024, RudiKai                       |
//|                     https://github.com/RudiKai                   |
//+------------------------------------------------------------------+
#property strict
#property indicator_chart_window
#property indicator_plots 0 // Suppress "no indicator plot" warning

// --- Includes
#include <ChartObjects\ChartObjectsTxtControls.mqh>
// #include <AlfredAlertCenter_Include.mqh> // Excluded as per request

// --- Enums for State Management
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
};

struct CompassData
{
    ENUM_BIAS bias;
    double    confidence;
};

// --- Constants for Panel Layout
#define PANE_PREFIX "AlfredPane_"
#define PANE_WIDTH 220
#define PANE_X_POS 10
#define PANE_Y_POS 10
#define PANE_BG_COLOR clrDimGray
#define PANE_BG_OPACITY 204
#define CONFIDENCE_BAR_MAX_WIDTH 100

// --- Colors
#define COLOR_BULL clrLimeGreen
#define COLOR_BEAR clrOrangeRed
#define COLOR_NEUTRAL_TEXT clrWhite
#define COLOR_NEUTRAL_BIAS clrGoldenrod // Yellow for Neutral Bias
#define COLOR_HEADER clrSilver
#define COLOR_TOGGLE clrLightGray
#define COLOR_ALFRED_MSG clrLightYellow
#define COLOR_DEMAND clrLimeGreen
#define COLOR_SUPPLY clrOrangeRed
#define COLOR_CONF_HIGH clrSeaGreen
#define COLOR_CONF_MED clrGoldenrod
#define COLOR_CONF_LOW clrFireBrick
#define COLOR_SEPARATOR clrGray
#define COLOR_NA clrGray

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
double g_pip_value;
string g_timeframe_strings[] = {"M1", "M5", "M15", "M30", "H1", "H4", "D1"};
ENUM_TIMEFRAMES g_timeframes[] = {PERIOD_M1, PERIOD_M5, PERIOD_M15, PERIOD_M30, PERIOD_H1, PERIOD_H4, PERIOD_D1};


//+------------------------------------------------------------------+
//|                  REAL DATA INTEGRATION FUNCTIONS                 |
//+------------------------------------------------------------------+

// Safely gets data from AlfredCompass indicator
CompassData GetCompassData(ENUM_TIMEFRAMES tf)
{
    CompassData data;
    data.bias = BIAS_NEUTRAL;
    data.confidence = 0.0;

    double bias_buffer[1];
    double conf_buffer[1];

    // Attempt to copy data from the indicator buffers
    if(CopyBuffer(iCustom(_Symbol, tf, "AlfredCompass"), 0, 0, 1, bias_buffer) > 0 &&
       CopyBuffer(iCustom(_Symbol, tf, "AlfredCompass"), 1, 0, 1, conf_buffer) > 0)
    {
        if(bias_buffer[0] > 0) data.bias = BIAS_BULL;
        else if(bias_buffer[0] < 0) data.bias = BIAS_BEAR;
        else data.bias = BIAS_NEUTRAL;
        
        data.confidence = conf_buffer[0];
    }
    // If it fails, the default "NEUTRAL" values are returned
    return data;
}


// Safely checks for active zones from AlfredSupDemCore
ENUM_ZONE GetZoneStatus(ENUM_TIMEFRAMES tf)
{
    string tf_str = EnumToString(tf);
    StringReplace(tf_str, "PERIOD_", "");

    string demand_zone_name = "DZone_" + tf_str;
    string supply_zone_name = "SZone_" + tf_str;

    if(ObjectFind(0, demand_zone_name) >= 0) return ZONE_DEMAND;
    if(ObjectFind(0, supply_zone_name) >= 0) return ZONE_SUPPLY;

    return ZONE_NONE;
}

LiveTradeData FetchTradeLevels()
{
    LiveTradeData data;
    data.trade_exists = false;
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
    switch(bias) { case BIAS_BULL: return "BULL"; case BIAS_BEAR: return "BEAR"; default: return "NEUTRAL"; }
}

color BiasToColor(ENUM_BIAS bias)
{
    switch(bias) { case BIAS_BULL: return COLOR_BULL; case BIAS_BEAR: return COLOR_BEAR; default: return COLOR_NEUTRAL_BIAS; }
}

string ZoneToString(ENUM_ZONE zone)
{
    switch(zone) { case ZONE_DEMAND: return "Active"; case ZONE_SUPPLY: return "Active"; default: return "---"; }
}

color ZoneToColor(ENUM_ZONE zone)
{
    switch(zone) { case ZONE_DEMAND: return COLOR_DEMAND; case ZONE_SUPPLY: return COLOR_SUPPLY; default: return COLOR_NA; }
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
    CreateLabel("biases_header", "TF Biases & Zones", x_offset, y_offset, COLOR_HEADER, FONT_SIZE_HEADER);
    CreateLabel("biases_toggle", g_biases_expanded ? "[-]" : "[+]", x_toggle, y_offset, COLOR_TOGGLE, FONT_SIZE_HEADER);
    y_offset += SPACING_MEDIUM;
    if(g_biases_expanded)
    {
        int x_bias_prefix = x_offset + 20;
        int x_bias_value  = x_bias_prefix + 35;
        int x_zone_prefix = x_bias_value + 55;
        int x_zone_value = x_zone_prefix + 35;
        
        for(int i=0; i<ArraySize(g_timeframe_strings); i++)
        {
            string tf = g_timeframe_strings[i];
            CreateLabel("biases_"+tf+"_prefix", tf+":", x_bias_prefix, y_offset, COLOR_HEADER, FONT_SIZE_NORMAL);
            CreateLabel("biases_"+tf+"_value", "N/A", x_bias_value, y_offset, COLOR_NA, FONT_SIZE_NORMAL);
            
            CreateLabel("zone_"+tf+"_prefix", "Zone:", x_zone_prefix, y_offset, COLOR_HEADER, FONT_SIZE_NORMAL);
            CreateLabel("zone_"+tf+"_value", "N/A", x_zone_value, y_offset, COLOR_NA, FONT_SIZE_NORMAL);
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
        CreateLabel("hud_spread_val", "-", x_col2_value, y_offset, COLOR_NEUTRAL_TEXT, FONT_SIZE_NORMAL);
        y_offset += SPACING_MEDIUM;
        CreateLabel("hud_atr", "ATR ("+IntegerToString(atr_period)+"):", x_col2_prefix, y_offset, COLOR_HEADER, FONT_SIZE_NORMAL);
        CreateLabel("hud_atr_val", "-", x_col2_value, y_offset, COLOR_NEUTRAL_TEXT, FONT_SIZE_NORMAL);
    }
    y_offset += SPACING_SEPARATOR - (g_hud_expanded ? SPACING_MEDIUM : 0);
    CreateRectangle("sep2", x_offset, y_offset, PANE_WIDTH - 20, 1, COLOR_SEPARATOR, BORDER_FLAT);
    y_offset += SPACING_SEPARATOR;

    // --- Final Signal Section
    CreateLabel("signal_header", "Final Signal (H1)", x_offset, y_offset, COLOR_HEADER, FONT_SIZE_HEADER);
    y_offset += SPACING_MEDIUM;
    CreateLabel("signal_dir_prefix", "Signal:", x_col2_prefix, y_offset, COLOR_HEADER, FONT_SIZE_NORMAL);
    CreateLabel("signal_dir_value", "N/A", x_col2_value, y_offset, COLOR_NA, FONT_SIZE_NORMAL);
    y_offset += SPACING_MEDIUM;
    CreateLabel("signal_conf_prefix", "Confidence:", x_col2_prefix, y_offset, COLOR_HEADER, FONT_SIZE_NORMAL);
    CreateLabel("signal_conf_value", "-", x_col2_value + 60, y_offset, COLOR_NEUTRAL_TEXT, FONT_SIZE_NORMAL);
    CreateRectangle("signal_conf_bar_bg", x_col2_value, y_offset, CONFIDENCE_BAR_MAX_WIDTH, 10, clrGray, BORDER_FLAT);
    CreateRectangle("signal_conf_bar_fg", x_col2_value, y_offset, 0, 10, clrNONE, BORDER_FLAT);
    y_offset += SPACING_MEDIUM;
    CreateLabel("magnet_zone_prefix", "Magnet Zone:", x_col2_prefix, y_offset, COLOR_HEADER, FONT_SIZE_NORMAL);
    CreateLabel("magnet_zone_value", "N/A", x_col2_value, y_offset, COLOR_NA, FONT_SIZE_NORMAL);
    y_offset += SPACING_SEPARATOR;
    CreateRectangle("sep3", x_offset, y_offset, PANE_WIDTH - 20, 1, COLOR_SEPARATOR, BORDER_FLAT);
    y_offset += SPACING_SEPARATOR;

    // --- Trade Now Section
    CreateLabel("trade_header", "Trade Now", x_offset, y_offset, COLOR_HEADER, FONT_SIZE_HEADER);
    y_offset += SPACING_MEDIUM;
    CreateLabel("trade_entry_prefix", "Entry:", x_col2_prefix, y_offset, COLOR_HEADER, FONT_SIZE_NORMAL);
    CreateLabel("trade_entry_value", "-", x_col2_value, y_offset, COLOR_NEUTRAL_TEXT, FONT_SIZE_NORMAL);
    y_offset += SPACING_MEDIUM;
    CreateLabel("trade_tp_prefix", "TP:", x_col2_prefix, y_offset, COLOR_HEADER, FONT_SIZE_NORMAL);
    CreateLabel("trade_tp_value", "-", x_col2_value, y_offset, COLOR_NEUTRAL_TEXT, FONT_SIZE_NORMAL);
    y_offset += SPACING_MEDIUM;
    CreateLabel("trade_sl_prefix", "SL:", x_col2_prefix, y_offset, COLOR_HEADER, FONT_SIZE_NORMAL);
    CreateLabel("trade_sl_value", "-", x_col2_value, y_offset, COLOR_NEUTRAL_TEXT, FONT_SIZE_NORMAL);
    y_offset += SPACING_MEDIUM;
    CreateLabel("trade_status_prefix", "Status:", x_col2_prefix, y_offset, COLOR_HEADER, FONT_SIZE_NORMAL);
    CreateLabel("trade_status_value", "☐ No Trade", x_col2_value, y_offset, COLOR_NEUTRAL_TEXT, FONT_SIZE_NORMAL);
    y_offset += SPACING_SEPARATOR;
    CreateRectangle("sep4", x_offset, y_offset, PANE_WIDTH - 20, 1, COLOR_SEPARATOR, BORDER_FLAT);
    y_offset += SPACING_SEPARATOR;

    // --- Alfred Says Section
    CreateLabel("alfred_header", "Alfred Says:", x_offset, y_offset, COLOR_HEADER, FONT_SIZE_HEADER);
    y_offset += SPACING_MEDIUM;
    CreateLabel("alfred_says", "Awaiting signals...", x_offset, y_offset, COLOR_ALFRED_MSG, FONT_SIZE_NORMAL);
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
    // --- Update TF Biases Section
    if(g_biases_expanded)
    {
        for(int i=0; i<ArraySize(g_timeframes); i++)
        {
             string tf_str = g_timeframe_strings[i];
             ENUM_TIMEFRAMES tf_enum = g_timeframes[i];

             // Update Compass Bias
             CompassData compass = GetCompassData(tf_enum);
             UpdateLabel("biases_"+tf_str+"_value", BiasToString(compass.bias), BiasToColor(compass.bias));

             // Update Zone Status
             ENUM_ZONE zone = GetZoneStatus(tf_enum);
             UpdateLabel("zone_"+tf_str+"_value", ZoneToString(zone), ZoneToColor(zone));
        }
    }

    // --- Update HUD Metrics Section
    if(g_hud_expanded)
    {
        long spread_points = SymbolInfoInteger(_Symbol, SYMBOL_SPREAD);
        UpdateLabel("hud_spread_val", IntegerToString(spread_points) + " pts", COLOR_NEUTRAL_TEXT);
        double atr_buffer[1];
        if(CopyBuffer(hATR_current, 0, 0, 1, atr_buffer) > 0)
        {
            UpdateLabel("hud_atr_val", DoubleToString(atr_buffer[0], _Digits), COLOR_NEUTRAL_TEXT);
        }
    }
    
    // --- Update Final Signal Section (using H1 data)
    CompassData h1_compass = GetCompassData(PERIOD_H1);
    UpdateLabel("signal_dir_value", BiasToString(h1_compass.bias), BiasToColor(h1_compass.bias));
    UpdateLabel("signal_conf_value", StringFormat("%.0f%%", h1_compass.confidence));
    
    int bar_width = (int)(h1_compass.confidence / 100.0 * CONFIDENCE_BAR_MAX_WIDTH);
    color bar_color = COLOR_CONF_LOW;
    if(h1_compass.confidence > 75) bar_color = COLOR_CONF_HIGH;
    else if(h1_compass.confidence > 50) bar_color = COLOR_CONF_MED;
    
    string bar_name = PANE_PREFIX + "signal_conf_bar_fg";
    ObjectSetInteger(0, bar_name, OBJPROP_XSIZE, bar_width);
    ObjectSetInteger(0, bar_name, OBJPROP_BGCOLOR, bar_color);
    ObjectSetInteger(0, bar_name, OBJPROP_COLOR, bar_color);

    ENUM_ZONE h1_zone = GetZoneStatus(PERIOD_H1);
    UpdateLabel("magnet_zone_value", ZoneToString(h1_zone), ZoneToColor(h1_zone));

    // --- Update Trade Data Section
    LiveTradeData trade_data = FetchTradeLevels();
    string price_format = "%." + IntegerToString(_Digits) + "f";

    if(trade_data.trade_exists)
    {
        UpdateLabel("trade_entry_value", StringFormat(price_format, trade_data.entry), COLOR_NEUTRAL_TEXT);
        string sl_text = StringFormat(price_format, trade_data.sl) + " (" + DoubleToString(CalculatePips(trade_data.entry, trade_data.sl), 1) + " p)";
        string tp_text = StringFormat(price_format, trade_data.tp) + " (" + DoubleToString(CalculatePips(trade_data.entry, trade_data.tp), 1) + " p)";
        UpdateLabel("trade_sl_value", sl_text, COLOR_NEUTRAL_TEXT);
        UpdateLabel("trade_tp_value", tp_text, COLOR_NEUTRAL_TEXT);
        UpdateLabel("trade_status_value", "☑ Active", COLOR_BULL);
    }
    else
    {
        UpdateLabel("trade_entry_value", "---", COLOR_NEUTRAL_TEXT);
        UpdateLabel("trade_sl_value", "---", COLOR_NEUTRAL_TEXT);
        UpdateLabel("trade_tp_value", "---", COLOR_NEUTRAL_TEXT);
        UpdateLabel("trade_status_value", "☐ No Trade", COLOR_NEUTRAL_TEXT);
    }
    
    // --- Update Alfred Says Section (Example logic)
    if(h1_compass.bias == BIAS_BULL && h1_zone == ZONE_DEMAND)
    {
        UpdateLabel("alfred_says", "Strong bullish alignment. Awaiting entry.", COLOR_ALFRED_MSG);
    }
    else if (h1_compass.bias == BIAS_BEAR && h1_zone == ZONE_SUPPLY)
    {
        UpdateLabel("alfred_says", "Strong bearish alignment. Awaiting entry.", COLOR_ALFRED_MSG);
    }
    else
    {
        UpdateLabel("alfred_says", "Market conditions are mixed. Standing by.", COLOR_ALFRED_MSG);
    }


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
    
    RedrawPanel();
    EventSetTimer(1); // Set timer to refresh data every second
    return(INIT_SUCCEEDED);
}

//+------------------------------------------------------------------+
//| Timer function to trigger updates                                |
//+------------------------------------------------------------------+
void OnTimer()
{
    UpdatePanel();
}


//+------------------------------------------------------------------+
//| Custom indicator iteration function (not used for timer updates) |
//+------------------------------------------------------------------+
int OnCalculate(const int rates_total, const int prev_calculated, const int begin, const double &price[])
{
    // Main logic moved to OnTimer to ensure consistent updates
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
    EventKillTimer();
    IndicatorRelease(hATR_current);
    ObjectsDeleteAll(0, PANE_PREFIX);
    ChartRedraw();
}
//+------------------------------------------------------------------+
