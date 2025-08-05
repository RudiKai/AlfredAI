//+------------------------------------------------------------------+
//|                        AlfredAI_Pane.mq5                         |
//|        v2.3 - Trade Signal Logic & Visual Polish                 |
//|                    Copyright 2024, RudiKai                       |
//|                     https://github.com/RudiKai                   |
//+------------------------------------------------------------------+
#property strict
#property indicator_chart_window
#property indicator_plots 0 // Suppress "no indicator plot" warning

// --- Optional Input ---
input bool ShowDebugInfo = false; // Toggle for displaying debug information

// --- Includes
#include <ChartObjects\ChartObjectsTxtControls.mqh>

// --- Enums for State Management
enum ENUM_BIAS { BIAS_BULL, BIAS_BEAR, BIAS_NEUTRAL };
enum ENUM_ZONE { ZONE_DEMAND, ZONE_SUPPLY, ZONE_NONE };
enum ENUM_ZONE_INTERACTION { INTERACTION_DEMAND, INTERACTION_SUPPLY, INTERACTION_NONE };
enum ENUM_TRADE_SIGNAL { SIGNAL_NONE, SIGNAL_BUY, SIGNAL_SELL }; // Updated for clarity

// --- Structs for Data Handling
struct LiveTradeData { bool trade_exists; double entry, sl, tp; };
struct CompassData { ENUM_BIAS bias; double confidence; };

// --- Constants for Panel Layout
#define PANE_PREFIX "AlfredPane_"
#define PANE_WIDTH 230 // Slightly wider for better spacing
#define PANE_X_POS 15
#define PANE_Y_POS 15
#define PANE_BG_COLOR clrDimGray
#define PANE_BG_OPACITY 210
#define CONFIDENCE_BAR_MAX_WIDTH 100
#define SEPARATOR_TEXT "───────────────"

// --- Colors
#define COLOR_BULL clrLimeGreen
#define COLOR_BEAR clrOrangeRed
#define COLOR_NEUTRAL_TEXT clrWhite
#define COLOR_NEUTRAL_BIAS clrGoldenrod
#define COLOR_HEADER clrSilver
#define COLOR_TOGGLE clrLightGray
#define COLOR_ALFRED_MSG clrLightYellow
#define COLOR_DEMAND clrLimeGreen
#define COLOR_SUPPLY clrOrangeRed
#define COLOR_CONF_HIGH clrLimeGreen
#define COLOR_CONF_MED clrOrange
#define COLOR_CONF_LOW clrOrangeRed
#define COLOR_SEPARATOR clrGray
#define COLOR_NA clrGray
#define COLOR_NO_SIGNAL clrGray

// --- Font Sizes & Spacing
#define FONT_SIZE_NORMAL 8
#define FONT_SIZE_HEADER 9
#define FONT_SIZE_SIGNAL 10
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
//|                  MOCK & REAL DATA FUNCTIONS                      |
//+------------------------------------------------------------------+
double GetCurrentTP() { return SymbolInfoDouble(_Symbol, SYMBOL_BID) + (50 * g_pip_value); }
double GetCurrentSL() { return SymbolInfoDouble(_Symbol, SYMBOL_BID) - (50 * g_pip_value); }

// UPDATED: Mock function for trade signal
ENUM_TRADE_SIGNAL GetTradeSignal()
{
    long time_cycle = TimeCurrent() / 10;
    switch(time_cycle % 3) { case 0: return SIGNAL_BUY; case 1: return SIGNAL_SELL; default: return SIGNAL_NONE; }
}

ENUM_ZONE_INTERACTION GetZoneInteraction()
{
    long time_cycle = TimeCurrent() / 15;
    switch(time_cycle % 3) { case 0: return INTERACTION_DEMAND; case 1: return INTERACTION_SUPPLY; default: return INTERACTION_NONE; }
}

CompassData GetCompassData(ENUM_TIMEFRAMES tf)
{
    CompassData data; data.bias = BIAS_NEUTRAL; data.confidence = 0.0;
    double bias_buffer[1], conf_buffer[1];
    if(CopyBuffer(iCustom(_Symbol, tf, "AlfredCompass"), 0, 0, 1, bias_buffer) > 0 &&
       CopyBuffer(iCustom(_Symbol, tf, "AlfredCompass"), 1, 0, 1, conf_buffer) > 0)
    {
        if(bias_buffer[0] > 0) data.bias = BIAS_BULL; else if(bias_buffer[0] < 0) data.bias = BIAS_BEAR;
        data.confidence = conf_buffer[0];
    }
    return data;
}

ENUM_ZONE GetZoneStatus(ENUM_TIMEFRAMES tf)
{
    string tf_str = EnumToString(tf); StringReplace(tf_str, "PERIOD_", "");
    if(ObjectFind(0, "DZone_" + tf_str) >= 0) return ZONE_DEMAND;
    if(ObjectFind(0, "SZone_" + tf_str) >= 0) return ZONE_SUPPLY;
    return ZONE_NONE;
}

LiveTradeData FetchTradeLevels()
{
    LiveTradeData data; data.trade_exists = false;
    for(int i = PositionsTotal() - 1; i >= 0; i--)
    {
        if(PositionGetString(POSITION_SYMBOL) == _Symbol)
        {
            data.trade_exists = true; data.entry = PositionGetDouble(POSITION_PRICE_OPEN);
            data.sl = PositionGetDouble(POSITION_SL); data.tp = PositionGetDouble(POSITION_TP);
            break;
        }
    }
    return data;
}

//+------------------------------------------------------------------+
//|                   HELPER & CONVERSION FUNCTIONS                  |
//+------------------------------------------------------------------+
double CalculatePips(double p1, double p2) { if(g_pip_value==0||p1==0||p2==0) return 0; return MathAbs(p1-p2)/g_pip_value; }
string BiasToString(ENUM_BIAS b) { switch(b){case BIAS_BULL:return"BULL";case BIAS_BEAR:return"BEAR";}return"NEUTRAL";}
color  BiasToColor(ENUM_BIAS b) { switch(b){case BIAS_BULL:return COLOR_BULL;case BIAS_BEAR:return COLOR_BEAR;}return COLOR_NEUTRAL_BIAS;}
string ZoneToString(ENUM_ZONE z) { switch(z){case ZONE_DEMAND:case ZONE_SUPPLY:return"Active";}return"---";}
color  ZoneToColor(ENUM_ZONE z) { switch(z){case ZONE_DEMAND:return COLOR_DEMAND;case ZONE_SUPPLY:return COLOR_SUPPLY;}return COLOR_NA;}
string SignalToString(ENUM_TRADE_SIGNAL s){switch(s){case SIGNAL_BUY:return"BUY";case SIGNAL_SELL:return"SELL";}return"NO SIGNAL";}
color  SignalToColor(ENUM_TRADE_SIGNAL s){switch(s){case SIGNAL_BUY:return COLOR_BULL;case SIGNAL_SELL:return COLOR_BEAR;}return COLOR_NO_SIGNAL;}
string ZoneInteractionToString(ENUM_ZONE_INTERACTION z){switch(z){case INTERACTION_DEMAND:return"INSIDE DEMAND";case INTERACTION_SUPPLY:return"INSIDE SUPPLY";}return"OUTSIDE ZONES";}
color  ZoneInteractionToColor(ENUM_ZONE_INTERACTION z){switch(z){case INTERACTION_DEMAND:return COLOR_DEMAND;case INTERACTION_SUPPLY:return COLOR_SUPPLY;}return COLOR_NA;}

//+------------------------------------------------------------------+
//|                       UI DRAWING HELPERS                         |
//+------------------------------------------------------------------+
void CreateLabel(string n,string t,int x,int y,color c,int fs=FONT_SIZE_NORMAL,ENUM_ANCHOR_POINT a=ANCHOR_LEFT){string o=PANE_PREFIX+n;ObjectCreate(0,o,OBJ_LABEL,0,0,0);ObjectSetString(0,o,OBJPROP_TEXT,t);ObjectSetInteger(0,o,OBJPROP_XDISTANCE,x);ObjectSetInteger(0,o,OBJPROP_YDISTANCE,y);ObjectSetInteger(0,o,OBJPROP_COLOR,c);ObjectSetInteger(0,o,OBJPROP_FONTSIZE,fs);ObjectSetString(0,o,OBJPROP_FONT,"Arial");ObjectSetInteger(0,o,OBJPROP_ANCHOR,a);ObjectSetInteger(0,o,OBJPROP_BACK,false);ObjectSetInteger(0,o,OBJPROP_CORNER,0);}
void CreateRectangle(string n,int x,int y,int w,int h,color c,ENUM_BORDER_TYPE b=BORDER_FLAT){string o=PANE_PREFIX+n;ObjectCreate(0,o,OBJ_RECTANGLE_LABEL,0,0,0);ObjectSetInteger(0,o,OBJPROP_XDISTANCE,x);ObjectSetInteger(0,o,OBJPROP_YDISTANCE,y);ObjectSetInteger(0,o,OBJPROP_XSIZE,w);ObjectSetInteger(0,o,OBJPROP_YSIZE,h);ObjectSetInteger(0,o,OBJPROP_BGCOLOR,c);ObjectSetInteger(0,o,OBJPROP_COLOR,c);ObjectSetInteger(0,o,OBJPROP_BORDER_TYPE,b);ObjectSetInteger(0,o,OBJPROP_BACK,true);ObjectSetInteger(0,o,OBJPROP_CORNER,0);}
void UpdateLabel(string n,string t,color c=clrNONE){string o=PANE_PREFIX+n;if(ObjectFind(0,o)<0)return;ObjectSetString(0,o,OBJPROP_TEXT,t);if(c!=clrNONE)ObjectSetInteger(0,o,OBJPROP_COLOR,c);}
void DrawSeparator(string name, int &y_offset, int x_offset) { CreateLabel(name, SEPARATOR_TEXT, x_offset, y_offset, COLOR_SEPARATOR); y_offset += SPACING_SEPARATOR; }

void DrawOrUpdatePriceLine(string name, double price, color clr)
{
    string line_name = PANE_PREFIX + name + "_line";
    if(ObjectFind(0, line_name) < 0)
    {
        ObjectCreate(0, line_name, OBJ_HLINE, 0, 0, price);
        ObjectSetInteger(0, line_name, OBJPROP_COLOR, clr); ObjectSetInteger(0, line_name, OBJPROP_STYLE, STYLE_DASH);
        ObjectSetInteger(0, line_name, OBJPROP_WIDTH, 1); ObjectSetInteger(0, line_name, OBJPROP_BACK, true);
    }
    else { ObjectMove(0, line_name, 0, 0, price); }
}

//+------------------------------------------------------------------+
//|                MAIN PANEL CREATION & UPDATE LOGIC                |
//+------------------------------------------------------------------+
void CreatePanel()
{
    int x_offset = PANE_X_POS + 10;
    int y_offset = PANE_Y_POS + 10;
    int x_col1 = x_offset;
    int x_col2 = x_offset + 120;
    int x_toggle = PANE_X_POS + PANE_WIDTH - 20;

    CreateLabel("symbol_header", _Symbol, x_offset, y_offset, COLOR_HEADER, 10);
    y_offset += SPACING_LARGE;

    // --- TF Biases Section
    CreateLabel("biases_header", "TF Biases & Zones", x_col1, y_offset, COLOR_HEADER, FONT_SIZE_HEADER);
    CreateLabel("biases_toggle", g_biases_expanded ? "[-]" : "[+]", x_toggle, y_offset, COLOR_TOGGLE, FONT_SIZE_HEADER);
    y_offset += SPACING_MEDIUM;
    if(g_biases_expanded)
    {
        for(int i=0; i<ArraySize(g_timeframe_strings); i++)
        {
            string tf=g_timeframe_strings[i];
            CreateLabel("biases_"+tf+"_prefix",tf+":",x_col1,y_offset,COLOR_HEADER); CreateLabel("biases_"+tf+"_value","N/A",x_col1+30,y_offset,COLOR_NA);
            CreateLabel("zone_"+tf+"_prefix","Zone:",x_col2,y_offset,COLOR_HEADER); CreateLabel("zone_"+tf+"_value","N/A",x_col2+35,y_offset,COLOR_NA);
            y_offset+=SPACING_MEDIUM;
        }
    }
    y_offset += SPACING_SEPARATOR - (g_biases_expanded ? SPACING_MEDIUM : 0);
    DrawSeparator("sep1", y_offset, x_offset);
    
    // --- Zone Interaction Status Section
    CreateLabel("zone_interaction_header", "ZONE STATUS", x_col1, y_offset, COLOR_HEADER, FONT_SIZE_HEADER); y_offset += SPACING_MEDIUM;
    CreateLabel("zone_interaction_status", "OUTSIDE ZONES", x_col1, y_offset, COLOR_NA, FONT_SIZE_NORMAL); y_offset += SPACING_MEDIUM;
    DrawSeparator("sep_zone", y_offset, x_offset);

    // --- HUD Metrics Section
    CreateLabel("hud_header", "HUD Metrics", x_col1, y_offset, COLOR_HEADER, FONT_SIZE_HEADER);
    CreateLabel("hud_toggle", g_hud_expanded ? "[-]" : "[+]", x_toggle, y_offset, COLOR_TOGGLE, FONT_SIZE_HEADER);
    y_offset += SPACING_MEDIUM;
    if(g_hud_expanded)
    {
        CreateLabel("hud_spread","Spread:",x_col1,y_offset,COLOR_HEADER); CreateLabel("hud_spread_val","-",x_col2,y_offset,COLOR_NEUTRAL_TEXT); y_offset+=SPACING_MEDIUM;
        CreateLabel("hud_atr","ATR ("+IntegerToString(atr_period)+"):",x_col1,y_offset,COLOR_HEADER); CreateLabel("hud_atr_val","-",x_col2,y_offset,COLOR_NEUTRAL_TEXT);
    }
    y_offset += SPACING_SEPARATOR - (g_hud_expanded ? SPACING_MEDIUM : 0);
    DrawSeparator("sep2", y_offset, x_offset);

    // --- Final Signal Section
    CreateLabel("signal_header", "Final Signal (H1)", x_col1, y_offset, COLOR_HEADER, FONT_SIZE_HEADER); y_offset += SPACING_MEDIUM;
    CreateLabel("signal_dir_prefix","Signal:",x_col1,y_offset,COLOR_HEADER); CreateLabel("signal_dir_value","N/A",x_col2,y_offset,COLOR_NA); y_offset+=SPACING_MEDIUM;
    CreateLabel("signal_conf_prefix","Confidence:",x_col1,y_offset,COLOR_HEADER);
    CreateLabel("signal_conf_percent", "(0%)", x_col2 + CONFIDENCE_BAR_MAX_WIDTH + 5, y_offset, COLOR_NEUTRAL_TEXT);
    CreateRectangle("signal_conf_bar_bg",x_col2,y_offset,CONFIDENCE_BAR_MAX_WIDTH,10,clrGray); CreateRectangle("signal_conf_bar_fg",x_col2,y_offset,0,10,clrNONE); y_offset+=SPACING_MEDIUM;
    CreateLabel("magnet_zone_prefix","Magnet Zone:",x_col1,y_offset,COLOR_HEADER); CreateLabel("magnet_zone_value","N/A",x_col2,y_offset,COLOR_NA);
    y_offset += SPACING_SEPARATOR;
    DrawSeparator("sep3", y_offset, x_offset);

    // --- Trade Info Section
    CreateLabel("trade_header","Trade Info",x_col1,y_offset,COLOR_HEADER); y_offset+=SPACING_MEDIUM;
    CreateLabel("trade_entry_prefix","Entry:",x_col1,y_offset,COLOR_HEADER); CreateLabel("trade_entry_value","-",x_col2,y_offset,COLOR_NEUTRAL_TEXT); y_offset+=SPACING_MEDIUM;
    CreateLabel("trade_tp_prefix","TP:",x_col1,y_offset,COLOR_HEADER); CreateLabel("trade_tp_value","-",x_col2,y_offset,COLOR_NEUTRAL_TEXT); y_offset+=SPACING_MEDIUM;
    CreateLabel("trade_sl_prefix","SL:",x_col1,y_offset,COLOR_HEADER); CreateLabel("trade_sl_value","-",x_col2,y_offset,COLOR_NEUTRAL_TEXT); y_offset+=SPACING_MEDIUM;
    CreateLabel("trade_status_prefix","Status:",x_col1,y_offset,COLOR_HEADER); CreateLabel("trade_status_value","☐ No Trade",x_col2,y_offset,COLOR_NEUTRAL_TEXT);
    y_offset += SPACING_SEPARATOR;
    DrawSeparator("sep4", y_offset, x_offset);
    
    // --- Trade Signal Section
    CreateLabel("trade_signal_header", "TRADE SIGNAL", x_col1, y_offset, COLOR_HEADER, FONT_SIZE_HEADER);
    CreateLabel("trade_signal_status", "NO SIGNAL", x_col2, y_offset, COLOR_NO_SIGNAL, FONT_SIZE_SIGNAL);
    y_offset += SPACING_LARGE;

    // --- Debug Info (Optional)
    if(ShowDebugInfo)
    {
        CreateLabel("debug_mode", "DEBUG MODE ACTIVE", x_offset, y_offset, COLOR_ALFRED_MSG, FONT_SIZE_NORMAL);
        y_offset += SPACING_MEDIUM;
    }

    // --- Background
    string bg_name = PANE_PREFIX + "background";
    ObjectCreate(0, bg_name, OBJ_RECTANGLE_LABEL, 0, 0, 0);
    ObjectSetInteger(0, bg_name, OBJPROP_XDISTANCE, PANE_X_POS); ObjectSetInteger(0, bg_name, OBJPROP_YDISTANCE, PANE_Y_POS);
    ObjectSetInteger(0, bg_name, OBJPROP_XSIZE, PANE_WIDTH); ObjectSetInteger(0, bg_name, OBJPROP_YSIZE, y_offset - PANE_Y_POS);
    ObjectSetInteger(0, bg_name, OBJPROP_BACK, true); ObjectSetInteger(0, bg_name, OBJPROP_BORDER_TYPE, BORDER_FLAT);
    ObjectSetInteger(0, bg_name, OBJPROP_COLOR, clrNONE); color bg_color_opacity = (color)ColorToARGB(PANE_BG_COLOR, PANE_BG_OPACITY);
    ObjectSetInteger(0, bg_name, OBJPROP_BGCOLOR, bg_color_opacity);
}

void UpdatePanel()
{
    // --- Update TF Biases
    if(g_biases_expanded)
    {
        for(int i=0; i<ArraySize(g_timeframes); i++)
        {
             string tf_str = g_timeframe_strings[i]; ENUM_TIMEFRAMES tf_enum = g_timeframes[i];
             CompassData compass = GetCompassData(tf_enum); UpdateLabel("biases_"+tf_str+"_value", BiasToString(compass.bias), BiasToColor(compass.bias));
             ENUM_ZONE zone = GetZoneStatus(tf_enum); UpdateLabel("zone_"+tf_str+"_value", ZoneToString(zone), ZoneToColor(zone));
        }
    }
    
    // --- Update Zone Interaction Status
    ENUM_ZONE_INTERACTION interaction = GetZoneInteraction();
    UpdateLabel("zone_interaction_status", ZoneInteractionToString(interaction), ZoneInteractionToColor(interaction));

    // --- Update HUD Metrics
    if(g_hud_expanded)
    {
        long spread_points = SymbolInfoInteger(_Symbol, SYMBOL_SPREAD); UpdateLabel("hud_spread_val", IntegerToString(spread_points) + " pts", COLOR_NEUTRAL_TEXT);
        double atr_buffer[1]; if(CopyBuffer(hATR_current, 0, 0, 1, atr_buffer) > 0) { UpdateLabel("hud_atr_val", DoubleToString(atr_buffer[0], _Digits), COLOR_NEUTRAL_TEXT); }
    }
    
    // --- Update Final Signal
    CompassData h1_compass = GetCompassData(PERIOD_H1);
    UpdateLabel("signal_dir_value", BiasToString(h1_compass.bias), BiasToColor(h1_compass.bias));
    double conf = h1_compass.confidence;
    color conf_color = conf > 70 ? COLOR_CONF_HIGH : conf > 40 ? COLOR_CONF_MED : COLOR_CONF_LOW;
    UpdateLabel("signal_conf_percent", StringFormat("(%.0f%%)", conf), conf_color);
    int bar_width = (int)(conf / 100.0 * CONFIDENCE_BAR_MAX_WIDTH);
    string bar_name = PANE_PREFIX + "signal_conf_bar_fg";
    ObjectSetInteger(0, bar_name, OBJPROP_XSIZE, bar_width); ObjectSetInteger(0, bar_name, OBJPROP_BGCOLOR, conf_color); ObjectSetInteger(0, bar_name, OBJPROP_COLOR, conf_color);
    ENUM_ZONE h1_zone = GetZoneStatus(PERIOD_H1); UpdateLabel("magnet_zone_value", ZoneToString(h1_zone), ZoneToColor(h1_zone));

    // --- Update Trade Data & TP/SL
    LiveTradeData trade_data = FetchTradeLevels();
    string price_format = "%." + IntegerToString(_Digits) + "f";
    if(trade_data.trade_exists)
    {
        UpdateLabel("trade_entry_value", StringFormat(price_format, trade_data.entry), COLOR_NEUTRAL_TEXT);
        double sl_pips = -CalculatePips(trade_data.entry, trade_data.sl);
        double tp_pips = CalculatePips(trade_data.entry, trade_data.tp);
        string sl_text = StringFormat(price_format, trade_data.sl) + StringFormat(" (%.1f p)", sl_pips);
        string tp_text = StringFormat(price_format, trade_data.tp) + StringFormat(" (+%.1f p)", tp_pips);
        UpdateLabel("trade_sl_value", sl_text, COLOR_NEUTRAL_TEXT); UpdateLabel("trade_tp_value", tp_text, COLOR_NEUTRAL_TEXT);
        UpdateLabel("trade_status_value", "☑ Active", COLOR_BULL);
        DrawOrUpdatePriceLine("tp", trade_data.tp, COLOR_BULL);
        DrawOrUpdatePriceLine("sl", trade_data.sl, COLOR_BEAR);
    }
    else
    {
        UpdateLabel("trade_entry_value", "---", COLOR_NEUTRAL_TEXT); UpdateLabel("trade_sl_value", "---", COLOR_NEUTRAL_TEXT);
        UpdateLabel("trade_tp_value", "---", COLOR_NEUTRAL_TEXT); UpdateLabel("trade_status_value", "☐ No Trade", COLOR_NEUTRAL_TEXT);
        double mock_tp = GetCurrentTP(); double mock_sl = GetCurrentSL();
        DrawOrUpdatePriceLine("tp", mock_tp, COLOR_BULL);
        DrawOrUpdatePriceLine("sl", mock_sl, COLOR_BEAR);
    }
    
    // --- Update Trade Signal
    ENUM_TRADE_SIGNAL signal = GetTradeSignal();
    string signal_obj = PANE_PREFIX + "trade_signal_status";
    ObjectSetString(0, signal_obj, OBJPROP_TEXT, SignalToString(signal));
    ObjectSetInteger(0, signal_obj, OBJPROP_COLOR, SignalToColor(signal));
    // Set font style
    if(signal == SIGNAL_NONE) ObjectSetString(0, signal_obj, OBJPROP_FONT, "Arial Italic");
    else ObjectSetString(0, signal_obj, OBJPROP_FONT, "Arial Bold");


    ChartRedraw();
}

//+------------------------------------------------------------------+
//| Redraws the entire panel after a state change                    |
//+------------------------------------------------------------------+
void RedrawPanel(){ObjectsDeleteAll(0,PANE_PREFIX);CreatePanel();UpdatePanel();ChartRedraw();}

//+------------------------------------------------------------------+
//| Custom indicator initialization function                         |
//+------------------------------------------------------------------+
int OnInit()
{
    hATR_current = iATR(_Symbol, _Period, atr_period);
    g_pip_value = SymbolInfoDouble(_Symbol, SYMBOL_POINT);
    if(SymbolInfoInteger(_Symbol, SYMBOL_DIGITS) == 3 || SymbolInfoInteger(_Symbol, SYMBOL_DIGITS) == 5) { g_pip_value *= 10; }
    RedrawPanel();
    EventSetTimer(1);
    return(INIT_SUCCEEDED);
}

//+------------------------------------------------------------------+
//| Timer function to trigger updates                                |
//+------------------------------------------------------------------+
void OnTimer(){UpdatePanel();}

//+------------------------------------------------------------------+
//| Custom indicator iteration function (not used for timer updates) |
//+------------------------------------------------------------------+
int OnCalculate(const int rates_total,const int p,const int b,const double &price[]){return(rates_total);}

//+------------------------------------------------------------------+
//| Chart event function                                             |
//+------------------------------------------------------------------+
void OnChartEvent(const int id,const long &l,const double &d,const string &s)
{
    if(id==CHARTEVENT_OBJECT_CLICK)
    {
        bool changed=false;
        if(StringFind(s,PANE_PREFIX)==0&&StringFind(s,"_toggle")>0)
        {
            if(s==PANE_PREFIX+"biases_toggle")g_biases_expanded=!g_biases_expanded;
            else if(s==PANE_PREFIX+"hud_toggle")g_hud_expanded=!g_hud_expanded;
            changed=true;
        }
        if(changed)RedrawPanel();
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
