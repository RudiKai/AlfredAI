//+------------------------------------------------------------------+
//|                        AlfredAI_Pane.mq5                         |
//|         v3.1 - Added Session & Volatility Module                 |
//|                    Copyright 2024, RudiKai                       |
//|                     https://github.com/RudiKai                   |
//+------------------------------------------------------------------+
#property strict
#property indicator_chart_window
#property indicator_plots 0 // Suppress "no indicator plot" warning

// --- Optional Inputs ---
input bool ShowDebugInfo = false;          // Toggle for displaying debug information
input bool ShowZoneHeatmap = true;         // Toggle for the Zone Heatmap
input bool ShowMagnetProjection = true;    // Toggle for the Magnet Projection status
input bool ShowMultiTFMagnets = true;      // Toggle for the Multi-TF Magnet Summary
input bool ShowConfidenceMatrix = true;    // Toggle for the Confidence Matrix
input bool ShowTradeRecommendation = true; // Toggle for the Trade Recommendation
input bool ShowRiskModule = true;          // Toggle for the Risk & Positioning module
input bool ShowSessionModule = true;       // NEW: Toggle for the Session & Volatility module

// --- Includes
#include <ChartObjects\ChartObjectsTxtControls.mqh>

// --- Enums for State Management
enum ENUM_BIAS { BIAS_BULL, BIAS_BEAR, BIAS_NEUTRAL };
enum ENUM_ZONE { ZONE_DEMAND, ZONE_SUPPLY, ZONE_NONE };
enum ENUM_ZONE_INTERACTION { INTERACTION_DEMAND, INTERACTION_SUPPLY, INTERACTION_NONE };
enum ENUM_TRADE_SIGNAL { SIGNAL_NONE, SIGNAL_BUY, SIGNAL_SELL };
enum ENUM_HEATMAP_STATUS { HEATMAP_NONE, HEATMAP_DEMAND, HEATMAP_SUPPLY };
enum ENUM_MAGNET_RELATION { RELATION_ABOVE, RELATION_BELOW, RELATION_AT };
enum ENUM_MATRIX_CONFIDENCE { CONFIDENCE_WEAK, CONFIDENCE_MEDIUM, CONFIDENCE_STRONG };
// NEW: Enums for Session & Volatility
enum ENUM_VOLATILITY { VOLATILITY_LOW, VOLATILITY_MEDIUM, VOLATILITY_HIGH };

// --- Structs for Data Handling
struct LiveTradeData { bool trade_exists; double entry, sl, tp; };
struct CompassData { ENUM_BIAS bias; double confidence; };
struct MatrixRowData { ENUM_BIAS bias; ENUM_ZONE zone; ENUM_MAGNET_RELATION magnet; ENUM_MATRIX_CONFIDENCE score; };
struct TradeRecommendation { ENUM_TRADE_SIGNAL action; string reasoning; };
struct RiskModuleData { double risk_percent; double position_size; string rr_ratio; };
// NEW: Struct for Session Module data
struct SessionData { string session_name; string session_overlap; ENUM_VOLATILITY volatility; };


// --- Constants for Panel Layout
#define PANE_PREFIX "AlfredPane_"
#define PANE_WIDTH 230
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
#define COLOR_HIGHLIGHT_DEMAND (color)ColorToARGB(clrDarkGreen, 100)
#define COLOR_HIGHLIGHT_SUPPLY (color)ColorToARGB(clrMaroon, 100)
#define COLOR_HIGHLIGHT_NONE (color)ColorToARGB(clrGray, 50)
#define COLOR_MAGNET_AT clrGoldenrod
#define COLOR_TEXT_DIM clrSilver
#define COLOR_MATRIX_STRONG (color)ColorToARGB(clrDarkGreen, 120)
#define COLOR_MATRIX_MEDIUM (color)ColorToARGB(clrGoldenrod, 100)
#define COLOR_MATRIX_WEAK (color)ColorToARGB(clrMaroon, 120)
#define COLOR_SESSION clrCyan
#define COLOR_VOL_HIGH_BG (color)ColorToARGB(clrMaroon, 80)
#define COLOR_VOL_MED_BG (color)ColorToARGB(clrGoldenrod, 80)
#define COLOR_VOL_LOW_BG (color)ColorToARGB(clrDarkGreen, 80)

// --- Font Sizes & Spacing
#define FONT_SIZE_NORMAL 8
#define FONT_SIZE_HEADER 9
#define FONT_SIZE_SIGNAL 10
#define FONT_SIZE_SIGNAL_ACTIVE 11
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
string g_heatmap_tf_strings[] = {"M15", "H1", "H4", "D1"};
ENUM_TIMEFRAMES g_heatmap_tfs[] = {PERIOD_M15, PERIOD_H1, PERIOD_H4, PERIOD_D1};
string g_magnet_summary_tf_strings[] = {"M15", "H1", "H4", "D1"};
ENUM_TIMEFRAMES g_magnet_summary_tfs[] = {PERIOD_M15, PERIOD_H1, PERIOD_H4, PERIOD_D1};
string g_matrix_tf_strings[] = {"M15", "H1", "H4", "D1"};
ENUM_TIMEFRAMES g_matrix_tfs[] = {PERIOD_M15, PERIOD_H1, PERIOD_H4, PERIOD_D1};


//+------------------------------------------------------------------+
//|                  MOCK & REAL DATA FUNCTIONS                      |
//+------------------------------------------------------------------+
double GetCurrentTP() { return SymbolInfoDouble(_Symbol, SYMBOL_BID) + (50 * g_pip_value); }
double GetCurrentSL() { return SymbolInfoDouble(_Symbol, SYMBOL_BID) - (50 * g_pip_value); }
ENUM_TRADE_SIGNAL GetTradeSignal()
{
    long time_cycle = TimeCurrent() / 10;
    switch(time_cycle % 3) { case 0: return SIGNAL_BUY; case 1: return SIGNAL_SELL; default: return SIGNAL_NONE; }
}
ENUM_ZONE_INTERACTION GetCurrentZoneInteraction()
{
    long time_cycle = TimeCurrent() / 15;
    switch(time_cycle % 3) { case 0: return INTERACTION_DEMAND; case 1: return INTERACTION_SUPPLY; default: return INTERACTION_NONE; }
}
ENUM_HEATMAP_STATUS GetZoneHeatmapStatus(ENUM_TIMEFRAMES tf)
{
    long time_cycle = TimeCurrent() / (5 * (int)tf);
    switch(time_cycle % 5) { case 0: return HEATMAP_DEMAND; case 1: return HEATMAP_SUPPLY; default: return HEATMAP_NONE; }
}
double GetMagnetProjectionLevel() { return iClose(_Symbol, _Period, 1) + 20 * _Point; }
ENUM_MAGNET_RELATION GetMagnetProjectionRelation(double price, double magnet)
{
    double proximity = 5 * _Point;
    if(price > magnet + proximity) return RELATION_ABOVE;
    if(price < magnet - proximity) return RELATION_BELOW;
    return RELATION_AT;
}
double GetMagnetLevelTF(ENUM_TIMEFRAMES tf) { return iClose(_Symbol, tf, 1) + (MathRand()%100-50)*_Point; }
ENUM_MAGNET_RELATION GetMagnetRelationTF(double price, double magnet) {
   if(price>magnet) return RELATION_ABOVE;
   if(price<magnet) return RELATION_BELOW;
   return RELATION_AT;
}

MatrixRowData GetConfidenceMatrixRow(ENUM_TIMEFRAMES tf)
{
    MatrixRowData data;
    data.bias = GetCompassData(tf).bias;
    data.zone = GetZoneStatus(tf);
    data.magnet = GetMagnetRelationTF(SymbolInfoDouble(_Symbol, SYMBOL_BID), GetMagnetLevelTF(tf));
    int score = 0;
    if(data.bias == BIAS_BULL && (data.zone == ZONE_DEMAND || data.magnet == RELATION_ABOVE)) score++;
    if(data.bias == BIAS_BEAR && (data.zone == ZONE_SUPPLY || data.magnet == RELATION_BELOW)) score++;
    if(data.zone == ZONE_DEMAND && data.magnet == RELATION_ABOVE) score++;
    if(data.zone == ZONE_SUPPLY && data.magnet == RELATION_BELOW) score++;
    if(score >= 2) data.score = CONFIDENCE_STRONG;
    else if (score == 1) data.score = CONFIDENCE_MEDIUM;
    else data.score = CONFIDENCE_WEAK;
    return data;
}

TradeRecommendation GetTradeRecommendation()
{
    TradeRecommendation rec;
    rec.action = SIGNAL_NONE;
    rec.reasoning = "Mixed Signals";
    int strong_bullish_tfs = 0;
    int strong_bearish_tfs = 0;
    for(int i = 0; i < ArraySize(g_matrix_tfs); i++)
    {
        MatrixRowData row = GetConfidenceMatrixRow(g_matrix_tfs[i]);
        if(row.score == CONFIDENCE_STRONG)
        {
            if(row.bias == BIAS_BULL) strong_bullish_tfs++;
            if(row.bias == BIAS_BEAR) strong_bearish_tfs++;
        }
    }
    if(strong_bullish_tfs >= 2)
    {
        rec.action = SIGNAL_BUY;
        rec.reasoning = "Strong Multi-TF Bullish Alignment";
    }
    else if(strong_bearish_tfs >= 2)
    {
        rec.action = SIGNAL_SELL;
        rec.reasoning = "Strong Multi-TF Bearish Alignment";
    }
    return rec;
}

RiskModuleData GetRiskModuleData()
{
    RiskModuleData data;
    data.risk_percent = 1.0;
    data.position_size = 0.10;
    int rand_val = MathRand() % 3;
    switch(rand_val)
    {
        case 0: data.rr_ratio = "1 : 1.5"; break;
        case 1: data.rr_ratio = "1 : 2.0"; break;
        default: data.rr_ratio = "1 : 3.0"; break;
    }
    return data;
}

// NEW: Mock function for Session & Volatility
SessionData GetSessionData()
{
    SessionData data;
    MqlDateTime dt;
    TimeCurrent(dt); // Using client time for mock logic
    int hour = dt.hour;

    // Determine Session (exclusive for main name)
    if(hour >= 13 && hour < 16) data.session_name = "London / NY";
    else if(hour >= 8 && hour < 13) data.session_name = "London";
    else if(hour >= 16 && hour < 21) data.session_name = "New York";
    else if(hour >= 21 || hour < 6) data.session_name = "Sydney";
    else if(hour >= 6 && hour < 8) data.session_name = "Tokyo";
    else data.session_name = "Inter-Session";

    // Determine Overlap
    if(hour >= 13 && hour < 16) data.session_overlap = "NY + London";
    else data.session_overlap = "None";

    // Determine Volatility (random mock)
    int rand_val = MathRand() % 3;
    switch(rand_val)
    {
        case 0: data.volatility = VOLATILITY_LOW; break;
        case 1: data.volatility = VOLATILITY_MEDIUM; break;
        default: data.volatility = VOLATILITY_HIGH; break;
    }
    return data;
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
string ZoneToString(ENUM_ZONE z) { switch(z){case ZONE_DEMAND:return"Demand";case ZONE_SUPPLY:return"Supply";}return"None";}
color  ZoneToColor(ENUM_ZONE z) { switch(z){case ZONE_DEMAND:return COLOR_DEMAND;case ZONE_SUPPLY:return COLOR_SUPPLY;}return COLOR_NA;}
string SignalToString(ENUM_TRADE_SIGNAL s){switch(s){case SIGNAL_BUY:return"BUY";case SIGNAL_SELL:return"SELL";}return"NO SIGNAL";}
color  SignalToColor(ENUM_TRADE_SIGNAL s){switch(s){case SIGNAL_BUY:return COLOR_BULL;case SIGNAL_SELL:return COLOR_BEAR;}return COLOR_NO_SIGNAL;}
string ZoneInteractionToString(ENUM_ZONE_INTERACTION z){switch(z){case INTERACTION_DEMAND:return"INSIDE DEMAND";case INTERACTION_SUPPLY:return"INSIDE SUPPLY";}return"NO ZONE INTERACTION";}
color  ZoneInteractionToColor(ENUM_ZONE_INTERACTION z){switch(z){case INTERACTION_DEMAND:return COLOR_DEMAND;case INTERACTION_SUPPLY:return COLOR_SUPPLY;}return COLOR_NA;}
color  ZoneInteractionToHighlightColor(ENUM_ZONE_INTERACTION z){switch(z){case INTERACTION_DEMAND:return COLOR_HIGHLIGHT_DEMAND;case INTERACTION_SUPPLY:return COLOR_HIGHLIGHT_SUPPLY;}return COLOR_HIGHLIGHT_NONE;}
string HeatmapStatusToString(ENUM_HEATMAP_STATUS s) { switch(s) { case HEATMAP_DEMAND: return "D"; case HEATMAP_SUPPLY: return "S"; } return "-"; }
color  HeatmapStatusToColor(ENUM_HEATMAP_STATUS s) { switch(s) { case HEATMAP_DEMAND: return COLOR_DEMAND; case HEATMAP_SUPPLY: return COLOR_SUPPLY; } return COLOR_NA; }
string MagnetRelationToString(ENUM_MAGNET_RELATION r) { switch(r) { case RELATION_ABOVE: return "(Above)"; case RELATION_BELOW: return "(Below)"; } return "(At)"; }
color  MagnetRelationToColor(ENUM_MAGNET_RELATION r) { switch(r) { case RELATION_ABOVE: return COLOR_BULL; case RELATION_BELOW: return COLOR_BEAR; } return COLOR_MAGNET_AT; }
string MagnetRelationTFToString(ENUM_MAGNET_RELATION r) { switch(r) { case RELATION_ABOVE: return "Above"; case RELATION_BELOW: return "Below"; } return "At"; }
color  MagnetRelationTFToColor(ENUM_MAGNET_RELATION r) { switch(r) { case RELATION_ABOVE: return COLOR_BULL; case RELATION_BELOW: return COLOR_BEAR; } return COLOR_MAGNET_AT; }
color MatrixScoreToColor(ENUM_MATRIX_CONFIDENCE s) { switch(s) { case CONFIDENCE_STRONG: return COLOR_MATRIX_STRONG; case CONFIDENCE_MEDIUM: return COLOR_MATRIX_MEDIUM; } return COLOR_MATRIX_WEAK; }
string RecoActionToString(ENUM_TRADE_SIGNAL s) { switch(s) { case SIGNAL_BUY: return "BUY"; case SIGNAL_SELL: return "SELL"; } return "WAIT"; }
color RecoActionToColor(ENUM_TRADE_SIGNAL s) { switch(s) { case SIGNAL_BUY: return COLOR_BULL; case SIGNAL_SELL: return COLOR_BEAR; } return COLOR_NO_SIGNAL; }
// NEW: Helpers for Session & Volatility
string VolatilityToString(ENUM_VOLATILITY v) { switch(v) { case VOLATILITY_LOW: return "Low"; case VOLATILITY_MEDIUM: return "Medium"; } return "High"; }
color VolatilityToColor(ENUM_VOLATILITY v) { switch(v) { case VOLATILITY_LOW: return COLOR_BULL; case VOLATILITY_MEDIUM: return COLOR_MAGNET_AT; } return COLOR_BEAR; }
color VolatilityToHighlightColor(ENUM_VOLATILITY v) { switch(v) { case VOLATILITY_LOW: return COLOR_VOL_LOW_BG; case VOLATILITY_MEDIUM: return COLOR_VOL_MED_BG; } return COLOR_VOL_HIGH_BG; }


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
    CreateRectangle("zone_interaction_highlight", x_col1 - 5, y_offset - 2, PANE_WIDTH - 20, 14, COLOR_HIGHLIGHT_NONE);
    CreateLabel("zone_interaction_status", "NO ZONE INTERACTION", x_col1, y_offset, COLOR_NA, FONT_SIZE_NORMAL); y_offset += SPACING_MEDIUM;
    DrawSeparator("sep_zone", y_offset, x_offset);

    // --- Zone Heatmap Section
    if(ShowZoneHeatmap)
    {
        CreateLabel("heatmap_header", "ZONE HEATMAP", x_col1, y_offset, COLOR_HEADER, FONT_SIZE_HEADER); y_offset += SPACING_MEDIUM;
        int heatmap_x = x_col1 + 20;
        for(int i = 0; i < ArraySize(g_heatmap_tf_strings); i++)
        {
            string tf = g_heatmap_tf_strings[i];
            CreateLabel("heatmap_tf_"+tf, tf, heatmap_x, y_offset, COLOR_HEADER, FONT_SIZE_NORMAL, ANCHOR_CENTER);
            CreateLabel("heatmap_status_"+tf, "-", heatmap_x, y_offset + 12, COLOR_NA, FONT_SIZE_NORMAL, ANCHOR_CENTER);
            heatmap_x += 45;
        }
        y_offset += SPACING_LARGE;
        DrawSeparator("sep_heatmap", y_offset, x_offset);
    }
    
    // --- Magnet Projection Section
    if(ShowMagnetProjection)
    {
        CreateLabel("magnet_header", "MAGNET PROJECTION", x_col1, y_offset, COLOR_HEADER, FONT_SIZE_HEADER); y_offset += SPACING_MEDIUM;
        CreateLabel("magnet_level", "Magnet → ---", x_col1, y_offset, COLOR_NEUTRAL_TEXT, FONT_SIZE_NORMAL + 1);
        CreateLabel("magnet_relation", "(---)", x_col1 + 150, y_offset, COLOR_NA, FONT_SIZE_NORMAL);
        y_offset += SPACING_MEDIUM;
        DrawSeparator("sep_magnet", y_offset, x_offset);
    }
    
    // --- Multi-TF Magnet Summary Section
    if(ShowMultiTFMagnets)
    {
        CreateLabel("mtf_magnet_header", "MULTI-TF MAGNETS", x_col1, y_offset, COLOR_HEADER, FONT_SIZE_HEADER); y_offset += SPACING_MEDIUM;
        int mtf_magnet_x1 = x_col1, mtf_magnet_x2 = x_col1 + 70, mtf_magnet_x3 = x_col1 + 140;
        for(int i = 0; i < ArraySize(g_magnet_summary_tfs); i++)
        {
            string tf = g_magnet_summary_tf_strings[i];
            CreateLabel("mtf_magnet_tf_"+tf, tf + " →", mtf_magnet_x1, y_offset, COLOR_HEADER);
            CreateLabel("mtf_magnet_relation_"+tf, "---", mtf_magnet_x2, y_offset, COLOR_NA);
            CreateLabel("mtf_magnet_level_"+tf, "(---)", mtf_magnet_x3, y_offset, COLOR_NA);
            y_offset += SPACING_MEDIUM;
        }
        DrawSeparator("sep_mtf_magnet", y_offset, x_offset);
    }
    
    // --- Confidence Matrix Section
    if(ShowConfidenceMatrix)
    {
        CreateLabel("matrix_header", "CONFIDENCE MATRIX", x_col1, y_offset, COLOR_HEADER, FONT_SIZE_HEADER); y_offset += SPACING_MEDIUM;
        CreateLabel("matrix_hdr_tf", "TF", x_col1, y_offset, COLOR_HEADER);
        CreateLabel("matrix_hdr_bias", "Bias", x_col1 + 40, y_offset, COLOR_HEADER);
        CreateLabel("matrix_hdr_zone", "Zone", x_col1 + 100, y_offset, COLOR_HEADER);
        CreateLabel("matrix_hdr_magnet", "Magnet", x_col1 + 160, y_offset, COLOR_HEADER);
        y_offset += SPACING_MEDIUM;
        for(int i = 0; i < ArraySize(g_matrix_tfs); i++)
        {
            string tf = g_matrix_tf_strings[i];
            CreateRectangle("matrix_bg_"+tf, x_col1 - 5, y_offset - 2, PANE_WIDTH - 20, 14, clrNONE);
            CreateLabel("matrix_tf_"+tf, tf, x_col1, y_offset, COLOR_NEUTRAL_TEXT);
            CreateLabel("matrix_bias_"+tf, "---", x_col1 + 40, y_offset, COLOR_NA);
            CreateLabel("matrix_zone_"+tf, "---", x_col1 + 100, y_offset, COLOR_NA);
            CreateLabel("matrix_magnet_"+tf, "---", x_col1 + 160, y_offset, COLOR_NA);
            y_offset += SPACING_MEDIUM;
        }
        DrawSeparator("sep_matrix", y_offset, x_offset);
    }
    
    // --- Trade Recommendation Section
    if(ShowTradeRecommendation)
    {
        CreateLabel("reco_header", "TRADE RECOMMENDATION", x_col1, y_offset, COLOR_HEADER, FONT_SIZE_HEADER); y_offset += SPACING_MEDIUM;
        CreateLabel("reco_action_prefix", "Action:", x_col1, y_offset, COLOR_HEADER);
        CreateLabel("reco_action_value", "WAIT", x_col1 + 70, y_offset, COLOR_NO_SIGNAL);
        y_offset += SPACING_MEDIUM;
        CreateLabel("reco_reason_prefix", "Reason:", x_col1, y_offset, COLOR_HEADER);
        CreateLabel("reco_reason_value", "---", x_col1 + 70, y_offset, COLOR_NEUTRAL_TEXT);
        y_offset += SPACING_MEDIUM;
        DrawSeparator("sep_reco", y_offset, x_offset);
    }
    
    // --- Risk & Positioning Section
    if(ShowRiskModule)
    {
        CreateLabel("risk_header", "RISK & POSITIONING", x_col1, y_offset, COLOR_HEADER, FONT_SIZE_HEADER); y_offset += SPACING_MEDIUM;
        CreateLabel("risk_pct_prefix", "Risk %:", x_col1, y_offset, COLOR_HEADER, FONT_SIZE_NORMAL);
        CreateLabel("risk_pct_value", "---", x_col2, y_offset, COLOR_NEUTRAL_TEXT, FONT_SIZE_NORMAL);
        y_offset += SPACING_MEDIUM;
        CreateLabel("risk_pos_size_prefix", "Position Size:", x_col1, y_offset, COLOR_HEADER, FONT_SIZE_NORMAL);
        CreateLabel("risk_pos_size_value", "---", x_col2, y_offset, COLOR_NEUTRAL_TEXT, FONT_SIZE_NORMAL);
        y_offset += SPACING_MEDIUM;
        CreateLabel("risk_rr_prefix", "RR Ratio:", x_col1, y_offset, COLOR_HEADER, FONT_SIZE_NORMAL);
        CreateLabel("risk_rr_value", "---", x_col2, y_offset, COLOR_NEUTRAL_TEXT, FONT_SIZE_NORMAL);
        y_offset += SPACING_MEDIUM;
        DrawSeparator("sep_risk", y_offset, x_offset);
    }
    
    // --- NEW: Session & Volatility Section ---
    if(ShowSessionModule)
    {
        CreateLabel("session_header", "SESSION & VOLATILITY", x_col1, y_offset, COLOR_HEADER, FONT_SIZE_HEADER); y_offset += SPACING_MEDIUM;
        CreateLabel("session_name_prefix", "Active Session:", x_col1, y_offset, COLOR_HEADER);
        CreateLabel("session_name_value", "---", x_col2, y_offset, COLOR_NEUTRAL_TEXT);
        y_offset += SPACING_MEDIUM;
        CreateLabel("session_overlap_prefix", "Session Overlap:", x_col1, y_offset, COLOR_HEADER);
        CreateLabel("session_overlap_value", "---", x_col2, y_offset, COLOR_NEUTRAL_TEXT);
        y_offset += SPACING_MEDIUM;
        CreateLabel("session_vol_prefix", "Volatility:", x_col1, y_offset, COLOR_HEADER);
        CreateRectangle("session_vol_bg", x_col2, y_offset - 2, 60, 14, clrNONE);
        CreateLabel("session_vol_value", "---", x_col2 + 4, y_offset, COLOR_NEUTRAL_TEXT);
        y_offset += SPACING_MEDIUM;
        DrawSeparator("sep_session", y_offset, x_offset);
    }

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
    ENUM_ZONE_INTERACTION interaction = GetCurrentZoneInteraction();
    UpdateLabel("zone_interaction_status", ZoneInteractionToString(interaction), ZoneInteractionToColor(interaction));
    string highlight_obj = PANE_PREFIX + "zone_interaction_highlight";
    ObjectSetInteger(0, highlight_obj, OBJPROP_BGCOLOR, ZoneInteractionToHighlightColor(interaction));

    // --- Update Zone Heatmap
    if(ShowZoneHeatmap)
    {
        for(int i = 0; i < ArraySize(g_heatmap_tfs); i++)
        {
            ENUM_TIMEFRAMES tf = g_heatmap_tfs[i];
            string tf_str = g_heatmap_tf_strings[i];
            ENUM_HEATMAP_STATUS status = GetZoneHeatmapStatus(tf);
            UpdateLabel("heatmap_status_"+tf_str, HeatmapStatusToString(status), HeatmapStatusToColor(status));
        }
    }
    
    // --- Update Magnet Projection
    if(ShowMagnetProjection)
    {
        double magnet_level = GetMagnetProjectionLevel();
        double current_price = SymbolInfoDouble(_Symbol, SYMBOL_BID);
        ENUM_MAGNET_RELATION relation = GetMagnetProjectionRelation(current_price, magnet_level);
        
        string price_format = "%." + IntegerToString(_Digits) + "f";
        UpdateLabel("magnet_level", "Magnet → " + StringFormat(price_format, magnet_level), COLOR_NEUTRAL_TEXT);
        UpdateLabel("magnet_relation", MagnetRelationToString(relation), MagnetRelationToColor(relation));
    }
    
    // --- Update Multi-TF Magnet Summary
    if(ShowMultiTFMagnets)
    {
        double current_price = SymbolInfoDouble(_Symbol, SYMBOL_BID);
        for(int i = 0; i < ArraySize(g_magnet_summary_tfs); i++)
        {
            ENUM_TIMEFRAMES tf = g_magnet_summary_tfs[i];
            string tf_str = g_magnet_summary_tf_strings[i];
            
            double magnet_level = GetMagnetLevelTF(tf);
            ENUM_MAGNET_RELATION relation = GetMagnetRelationTF(current_price, magnet_level);
            
            color relation_color = MagnetRelationTFToColor(relation);
            if(tf == PERIOD_M15) { relation_color = COLOR_TEXT_DIM; }
            
            string price_format = "(%." + IntegerToString(_Digits) + "f)";
            
            UpdateLabel("mtf_magnet_relation_"+tf_str, MagnetRelationTFToString(relation), relation_color);
            UpdateLabel("mtf_magnet_level_"+tf_str, StringFormat(price_format, magnet_level), relation_color);
        }
    }
    
    // --- Update Confidence Matrix
    if(ShowConfidenceMatrix)
    {
        for(int i = 0; i < ArraySize(g_matrix_tfs); i++)
        {
            ENUM_TIMEFRAMES tf = g_matrix_tfs[i];
            string tf_str = g_matrix_tf_strings[i];
            MatrixRowData data = GetConfidenceMatrixRow(tf);
            UpdateLabel("matrix_bias_"+tf_str, BiasToString(data.bias), BiasToColor(data.bias));
            UpdateLabel("matrix_zone_"+tf_str, ZoneToString(data.zone), ZoneToColor(data.zone));
            UpdateLabel("matrix_magnet_"+tf_str, MagnetRelationTFToString(data.magnet), MagnetRelationTFToColor(data.magnet));
            string bg_obj = PANE_PREFIX + "matrix_bg_" + tf_str;
            ObjectSetInteger(0, bg_obj, OBJPROP_BGCOLOR, MatrixScoreToColor(data.score));
            string font_style = (data.score == CONFIDENCE_STRONG) ? "Arial Bold" : "Arial";
            ObjectSetString(0, PANE_PREFIX + "matrix_tf_"+tf_str, OBJPROP_FONT, font_style);
            ObjectSetString(0, PANE_PREFIX + "matrix_bias_"+tf_str, OBJPROP_FONT, font_style);
            ObjectSetString(0, PANE_PREFIX + "matrix_zone_"+tf_str, OBJPROP_FONT, font_style);
            ObjectSetString(0, PANE_PREFIX + "matrix_magnet_"+tf_str, OBJPROP_FONT, font_style);
        }
    }
    
    // --- Update Trade Recommendation
    if(ShowTradeRecommendation)
    {
        TradeRecommendation rec = GetTradeRecommendation();
        UpdateLabel("reco_action_value", RecoActionToString(rec.action), RecoActionToColor(rec.action));
        UpdateLabel("reco_reason_value", rec.reasoning, COLOR_NEUTRAL_TEXT);
        string reco_obj = PANE_PREFIX + "reco_action_value";
        if(rec.action == SIGNAL_NONE) ObjectSetString(0, reco_obj, OBJPROP_FONT, "Arial Italic");
        else ObjectSetString(0, reco_obj, OBJPROP_FONT, "Arial Bold");
    }
    
    // --- Update Risk & Positioning
    if(ShowRiskModule)
    {
        RiskModuleData risk_data = GetRiskModuleData();
        UpdateLabel("risk_pct_value", StringFormat("%.1f%%", risk_data.risk_percent), COLOR_NEUTRAL_TEXT);
        UpdateLabel("risk_pos_size_value", StringFormat("%.2f lots", risk_data.position_size), COLOR_NEUTRAL_TEXT);
        UpdateLabel("risk_rr_value", risk_data.rr_ratio, COLOR_NEUTRAL_TEXT);
        string rr_obj = PANE_PREFIX + "risk_rr_value";
        ObjectSetString(0, rr_obj, OBJPROP_FONT, "Arial Bold");
    }
    
    // --- NEW: Update Session & Volatility ---
    if(ShowSessionModule)
    {
        SessionData s_data = GetSessionData();
        UpdateLabel("session_name_value", s_data.session_name, COLOR_SESSION);
        UpdateLabel("session_overlap_value", s_data.session_overlap, COLOR_NEUTRAL_TEXT);
        
        UpdateLabel("session_vol_value", VolatilityToString(s_data.volatility), VolatilityToColor(s_data.volatility));
        string vol_obj = PANE_PREFIX + "session_vol_value";
        ObjectSetString(0, vol_obj, OBJPROP_FONT, "Arial Bold");
        
        string vol_bg_obj = PANE_PREFIX + "session_vol_bg";
        ObjectSetInteger(0, vol_bg_obj, OBJPROP_BGCOLOR, VolatilityToHighlightColor(s_data.volatility));
    }


    // --- Update HUD Metrics
    if(g_hud_expanded)
    {
        long spread_points = SymbolInfoInteger(_Symbol, SYMBOL_SPREAD); UpdateLabel("hud_spread_val", IntegerToString(spread_points) + " pts", COLOR_NEUTRAL_TEXT);
        double atr_buffer[1]; if(CopyBuffer(hATR_current, 0, 0, 1, atr_buffer) > 0) { UpdateLabel("hud_atr_val", DoubleToString(atr_buffer[0], _Digits), COLOR_NEUTRAL_TEXT); }
    }
    
    // --- Update Final Signal with Dynamic Confidence
    CompassData h1_compass = GetCompassData(PERIOD_H1);
    UpdateLabel("signal_dir_value", BiasToString(h1_compass.bias), BiasToColor(h1_compass.bias));
    double base_conf = h1_compass.confidence;
    double adjusted_conf = base_conf;
    if(interaction == INTERACTION_DEMAND && h1_compass.bias == BIAS_BULL) { adjusted_conf += 5; }
    if(interaction == INTERACTION_SUPPLY && h1_compass.bias == BIAS_BEAR) { adjusted_conf += 5; }
    adjusted_conf = MathMin(100, adjusted_conf);
    color conf_color = adjusted_conf > 70 ? COLOR_CONF_HIGH : adjusted_conf > 40 ? COLOR_CONF_MED : COLOR_CONF_LOW;
    UpdateLabel("signal_conf_percent", StringFormat("(%.0f%%)", adjusted_conf), conf_color);
    int bar_width = (int)(adjusted_conf / 100.0 * CONFIDENCE_BAR_MAX_WIDTH);
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
    
    // --- Update Trade Signal with Enlarged Font
    ENUM_TRADE_SIGNAL signal = GetTradeSignal();
    string signal_obj = PANE_PREFIX + "trade_signal_status";
    ObjectSetString(0, signal_obj, OBJPROP_TEXT, SignalToString(signal));
    ObjectSetInteger(0, signal_obj, OBJPROP_COLOR, SignalToColor(signal));
    if(signal == SIGNAL_NONE)
    {
        ObjectSetString(0, signal_obj, OBJPROP_FONT, "Arial Italic");
        ObjectSetInteger(0, signal_obj, OBJPROP_FONTSIZE, FONT_SIZE_SIGNAL);
    }
    else
    {
        ObjectSetString(0, signal_obj, OBJPROP_FONT, "Arial Bold");
        ObjectSetInteger(0, signal_obj, OBJPROP_FONTSIZE, FONT_SIZE_SIGNAL_ACTIVE);
    }

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
    MathSrand((int)TimeCurrent()); // Seed random generator
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
