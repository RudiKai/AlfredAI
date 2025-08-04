//+------------------------------------------------------------------+
//|                        AlfredAI_Pane.mq5                         |
//|               Refactored for Clarity and Performance             |
//|                    Copyright 2024, RudiKai                       |
//|                     https://github.com/RudiKai                   |
//+------------------------------------------------------------------+
#property strict
#property indicator_chart_window

// --- Includes
#include <ChartObjects\ChartObjectsTxtControls.mqh>

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


// --- Constants for Panel Layout
#define PANE_PREFIX "AlfredPane_"
#define PANE_WIDTH 220
#define PANE_X_POS 10
#define PANE_Y_POS 10
#define PANE_BG_COLOR clrDimGray
#define PANE_BG_OPACITY 204 // Approx 80% (255 * 0.8)

// --- Colors (Optimized for Dark Backgrounds)
#define COLOR_BULL clrLimeGreen
#define COLOR_BEAR clrOrangeRed
#define COLOR_NEUTRAL clrWhite
#define COLOR_HEADER clrSilver
#define COLOR_TOGGLE clrLightGray
#define COLOR_ALFRED_MSG clrLightYellow
#define COLOR_DEMAND clrLimeGreen
#define COLOR_SUPPLY clrOrangeRed

// --- Font Sizes
#define FONT_SIZE_NORMAL 8
#define FONT_SIZE_HEADER 9 // Slightly larger to appear bold

// --- Spacing
#define SPACING_SMALL 8
#define SPACING_MEDIUM 16
#define SPACING_LARGE 24

// --- Indicator Handles
int hATR_current; // ATR for the current timeframe
int atr_period = 14;

// --- Global State for Collapsible Sections
bool g_biases_expanded = true;
bool g_hud_expanded = true;
bool g_zones_expanded = true;

//+------------------------------------------------------------------+
//| Forward declarations                                             |
//+------------------------------------------------------------------+
void UpdatePanel();
string GetAlfredMessage(ENUM_BIAS final_bias);
ENUM_BIAS GetCompassBiasTF(string tf);
ENUM_ZONE GetZoneStatus();
string BiasToString(ENUM_BIAS bias);
color BiasToColor(ENUM_BIAS bias);
string ZoneToString(ENUM_ZONE zone);
color ZoneToColor(ENUM_ZONE zone);

//+------------------------------------------------------------------+
//| Helper to create a text label                                    |
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

//+------------------------------------------------------------------+
//| Function to create the entire panel based on current states      |
//+------------------------------------------------------------------+
void CreatePanel()
{
    // --- Define layout positions
    int x_offset = PANE_X_POS + 10;
    int y_offset = PANE_Y_POS + 10;
    int x_col2 = x_offset + 110;
    int x_toggle = PANE_X_POS + PANE_WIDTH - 20;

    // --- Symbol Header (always visible)
    CreateLabel("symbol_header", _Symbol, x_offset, y_offset, COLOR_HEADER, 10);
    y_offset += SPACING_LARGE;

    // --- TF Biases Section
    CreateLabel("biases_header", "TF Biases", x_offset, y_offset, COLOR_HEADER, FONT_SIZE_HEADER);
    CreateLabel("biases_toggle", g_biases_expanded ? "[-]" : "[+]", x_toggle, y_offset, COLOR_TOGGLE, FONT_SIZE_HEADER);
    y_offset += SPACING_MEDIUM;
    if(g_biases_expanded)
    {
        int x_col2_prefix = x_col2;
        int x_col2_value  = x_col2_prefix + 32;
        CreateLabel("biases_M1_prefix",   "M1:", x_col2_prefix, y_offset, COLOR_HEADER);
        CreateLabel("biases_M1_value",    "-",   x_col2_value,  y_offset, COLOR_NEUTRAL);
        y_offset += SPACING_MEDIUM;
        CreateLabel("biases_M5_prefix",   "M5:", x_col2_prefix, y_offset, COLOR_HEADER);
        CreateLabel("biases_M5_value",    "-",   x_col2_value,  y_offset, COLOR_NEUTRAL);
        y_offset += SPACING_MEDIUM;
        CreateLabel("biases_M15_prefix",  "M15:",x_col2_prefix, y_offset, COLOR_HEADER);
        CreateLabel("biases_M15_value",   "-",   x_col2_value,  y_offset, COLOR_NEUTRAL);
        y_offset += SPACING_MEDIUM;
        CreateLabel("biases_H1_prefix",   "H1:", x_col2_prefix, y_offset, COLOR_HEADER);
        CreateLabel("biases_H1_value",    "-",   x_col2_value,  y_offset, COLOR_NEUTRAL);
        y_offset += SPACING_MEDIUM;
        CreateLabel("biases_H4_prefix",   "H4:", x_col2_prefix, y_offset, COLOR_HEADER);
        CreateLabel("biases_H4_value",    "-",   x_col2_value,  y_offset, COLOR_NEUTRAL);
        y_offset += SPACING_MEDIUM;
        CreateLabel("biases_D1_prefix",   "D1:", x_col2_prefix, y_offset, COLOR_HEADER);
        CreateLabel("biases_D1_value",    "-",   x_col2_value,  y_offset, COLOR_NEUTRAL);
    }
    y_offset += SPACING_LARGE; // Section break

    // --- HUD Metrics Section
    CreateLabel("hud_header", "HUD Metrics", x_offset, y_offset, COLOR_HEADER, FONT_SIZE_HEADER);
    CreateLabel("hud_toggle", g_hud_expanded ? "[-]" : "[+]", x_toggle, y_offset, COLOR_TOGGLE, FONT_SIZE_HEADER);
    y_offset += SPACING_MEDIUM;
    if(g_hud_expanded)
    {
        CreateLabel("hud_spread", "Spread:", x_col2 - 40, y_offset, COLOR_HEADER);
        CreateLabel("hud_spread_val", "-", x_col2 + 20, y_offset, COLOR_NEUTRAL);
        y_offset += SPACING_MEDIUM;
        CreateLabel("hud_atr", "ATR ("+IntegerToString(atr_period)+"):", x_col2-40, y_offset, COLOR_HEADER);
        CreateLabel("hud_atr_val", "-", x_col2+20, y_offset, COLOR_NEUTRAL);
    }
    y_offset += SPACING_LARGE; // Section break

    // --- Zones Section
    CreateLabel("zones_header", "Zones", x_offset, y_offset, COLOR_HEADER, FONT_SIZE_HEADER);
    CreateLabel("zones_toggle", g_zones_expanded ? "[-]" : "[+]", x_toggle, y_offset, COLOR_TOGGLE, FONT_SIZE_HEADER);
    y_offset += SPACING_MEDIUM;
    if(g_zones_expanded)
    {
        CreateLabel("zone_status_prefix", "Status:", x_col2-40, y_offset, COLOR_HEADER);
        CreateLabel("zone_status_value", "-", x_col2+20, y_offset, COLOR_NEUTRAL);
    }
    y_offset += SPACING_LARGE; // Section break

    // --- Trade Now Section (always visible)
    CreateLabel("trade_header", "Trade Now", x_offset, y_offset, COLOR_HEADER, FONT_SIZE_HEADER);
    CreateLabel("final_signal", "Signal: -", x_col2, y_offset, COLOR_NEUTRAL);
    y_offset += SPACING_LARGE;

    // --- Status Section (always visible)
    CreateLabel("status_header", "Trade Status", x_offset, y_offset, COLOR_HEADER, FONT_SIZE_HEADER);
    CreateLabel("trade_status",  "-", x_col2, y_offset, COLOR_NEUTRAL);
    y_offset += SPACING_LARGE;

    // --- Alfred Says Section (always visible)
    CreateLabel("alfred_header", "Alfred Says:", x_offset, y_offset, COLOR_HEADER, FONT_SIZE_HEADER);
    y_offset += SPACING_MEDIUM;
    CreateLabel("alfred_says",   "Thinking...", x_offset, y_offset, COLOR_ALFRED_MSG);
    y_offset += SPACING_MEDIUM; // Bottom padding

    // --- Finally, create the background with the calculated height
    string bg_name = PANE_PREFIX + "background";
    ObjectCreate(0, bg_name, OBJ_RECTANGLE_LABEL, 0, 0, 0);
    ObjectSetInteger(0, bg_name, OBJPROP_XDISTANCE, PANE_X_POS);
    ObjectSetInteger(0, bg_name, OBJPROP_YDISTANCE, PANE_Y_POS);
    ObjectSetInteger(0, bg_name, OBJPROP_XSIZE, PANE_WIDTH);
    ObjectSetInteger(0, bg_name, OBJPROP_YSIZE, y_offset - PANE_Y_POS); // Dynamic height
    ObjectSetInteger(0, bg_name, OBJPROP_BACK, true);
    ObjectSetInteger(0, bg_name, OBJPROP_BORDER_TYPE, BORDER_FLAT);
    ObjectSetInteger(0, bg_name, OBJPROP_COLOR, clrBlack);
    color bg_color_opacity = ColorToARGB(PANE_BG_COLOR, PANE_BG_OPACITY);
    ObjectSetInteger(0, bg_name, OBJPROP_BGCOLOR, bg_color_opacity);
}

//+------------------------------------------------------------------+
//| Redraws the entire panel after a state change                    |
//+------------------------------------------------------------------+
void RedrawPanel()
{
    ObjectsDeleteAll(0, PANE_PREFIX);
    CreatePanel();
    UpdatePanel(); // Immediately populate with data
    ChartRedraw();
}

//+------------------------------------------------------------------+
//| Helper to update a label's text and color                        |
//+------------------------------------------------------------------+
void UpdateLabel(string name, string text, color clr = clrNONE)
{
    string obj_name = PANE_PREFIX + name;
    if(ObjectFind(0, obj_name) < 0) return; // Don't update if object doesn't exist (section collapsed)
    
    ObjectSetString(0, obj_name, OBJPROP_TEXT, text);
    if(clr != clrNONE)
    {
        ObjectSetInteger(0, obj_name, OBJPROP_COLOR, clr);
    }
}

//+------------------------------------------------------------------+
//| Function to update all dynamic data on the panel                 |
//+------------------------------------------------------------------+
void UpdatePanel()
{
    // --- Get all biases from the placeholder function
    ENUM_BIAS biasM1 = GetCompassBiasTF("M1");
    ENUM_BIAS biasM5 = GetCompassBiasTF("M5");
    ENUM_BIAS biasM15 = GetCompassBiasTF("M15");
    ENUM_BIAS biasH1 = GetCompassBiasTF("H1");
    ENUM_BIAS biasH4 = GetCompassBiasTF("H4");
    ENUM_BIAS biasD1 = GetCompassBiasTF("D1");

    // --- Update TF Biases if expanded
    if(g_biases_expanded)
    {
        UpdateLabel("biases_M1_value", BiasToString(biasM1), BiasToColor(biasM1));
        UpdateLabel("biases_M5_value", BiasToString(biasM5), BiasToColor(biasM5));
        UpdateLabel("biases_M15_value", BiasToString(biasM15), BiasToColor(biasM15));
        UpdateLabel("biases_H1_value", BiasToString(biasH1), BiasToColor(biasH1));
        UpdateLabel("biases_H4_value", BiasToString(biasH4), BiasToColor(biasH4));
        UpdateLabel("biases_D1_value", BiasToString(biasD1), BiasToColor(biasD1));
    }

    // --- Update HUD Metrics if expanded
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
    
    // --- Update Zones if expanded
    if(g_zones_expanded)
    {
        ENUM_ZONE current_zone = GetZoneStatus();
        UpdateLabel("zone_status_value", ZoneToString(current_zone), ZoneToColor(current_zone));
    }
    
    // --- Always update these sections
    int bull_count = 0, bear_count = 0;
    ENUM_BIAS biases[] = {biasM1, biasM5, biasM15, biasH1, biasH4, biasD1};
    for(int i = 0; i < 6; i++)
    {
        if(biases[i] == BIAS_BULL) bull_count++;
        if(biases[i] == BIAS_BEAR) bear_count++;
    }
    ENUM_BIAS final_signal = BIAS_NEUTRAL;
    if(bull_count >= 4) final_signal = BIAS_BULL;
    if(bear_count >= 4) final_signal = BIAS_BEAR;
    UpdateLabel("final_signal", "Signal: " + BiasToString(final_signal), BiasToColor(final_signal));

    UpdateLabel("trade_status", "No Position", COLOR_NEUTRAL);
    UpdateLabel("alfred_says", GetAlfredMessage(final_signal), COLOR_ALFRED_MSG);

    ChartRedraw();
}

//+------------------------------------------------------------------+
//| Custom indicator initialization function                         |
//+------------------------------------------------------------------+
int OnInit()
{
    hATR_current = iATR(_Symbol, _Period, atr_period);
    RedrawPanel();
    return(INIT_SUCCEEDED);
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
    UpdatePanel();
    return(rates_total);
}

//+------------------------------------------------------------------+
//| Chart event function                                             |
//+------------------------------------------------------------------+
void OnChartEvent(const int id,
                  const long &lparam,
                  const double &dparam,
                  const string &sparam)
{
    if(id == CHARTEVENT_OBJECT_CLICK)
    {
        bool state_changed = false;
        if(sparam == PANE_PREFIX + "biases_toggle")
        {
            g_biases_expanded = !g_biases_expanded;
            state_changed = true;
        }
        else if(sparam == PANE_PREFIX + "hud_toggle")
        {
            g_hud_expanded = !g_hud_expanded;
            state_changed = true;
        }
        else if(sparam == PANE_PREFIX + "zones_toggle")
        {
            g_zones_expanded = !g_zones_expanded;
            state_changed = true;
        }

        if(state_changed)
        {
            RedrawPanel();
        }
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
//|                  DATA INTEGRATION PLACEHOLDERS                   |
//+------------------------------------------------------------------+
//| Replace the logic in these functions with your actual calls to   |
//| the Compass and SupDemCore indicators.                           |
//+------------------------------------------------------------------+

ENUM_BIAS GetCompassBiasTF(string tf)
{
    // --- PLACEHOLDER LOGIC ---
    // Replace this with: iCustom(_Symbol, _Period, "CompassIndicator", ...);
    // For now, it returns a random bias to demonstrate functionality.
    double random_val = MathRand() / 32767.0;
    if(random_val > 0.66) return BIAS_BULL;
    if(random_val < 0.33) return BIAS_BEAR;
    return BIAS_NEUTRAL;
}

ENUM_ZONE GetZoneStatus()
{
    // --- PLACEHOLDER LOGIC ---
    // Replace this with: iCustom(_Symbol, _Period, "SupDemCore", ...);
    // For now, it returns a random zone to demonstrate functionality.
    double random_val = MathRand() / 32767.0;
    if(random_val > 0.66) return ZONE_DEMAND;
    if(random_val < 0.33) return ZONE_SUPPLY;
    return ZONE_NONE;
}

//+------------------------------------------------------------------+
//|                   HELPER & CONVERSION FUNCTIONS                  |
//+------------------------------------------------------------------+
string GetAlfredMessage(ENUM_BIAS final_bias)
{
    switch(final_bias)
    {
        case BIAS_BULL: return "Strong bullish sentiment detected.";
        case BIAS_BEAR: return "Strong bearish sentiment detected.";
        case BIAS_NEUTRAL: return "Market is consolidating. Awaiting signal.";
    }
    return "Thinking...";
}

string BiasToString(ENUM_BIAS bias)
{
    switch(bias)
    {
        case BIAS_BULL: return "BULL";
        case BIAS_BEAR: return "BEAR";
        case BIAS_NEUTRAL: return "NEUTRAL";
    }
    return "N/A";
}

color BiasToColor(ENUM_BIAS bias)
{
    switch(bias)
    {
        case BIAS_BULL: return COLOR_BULL;
        case BIAS_BEAR: return COLOR_BEAR;
        case BIAS_NEUTRAL: return COLOR_NEUTRAL;
    }
    return COLOR_NEUTRAL;
}

string ZoneToString(ENUM_ZONE zone)
{
    switch(zone)
    {
        case ZONE_DEMAND: return "Demand";
        case ZONE_SUPPLY: return "Supply";
        case ZONE_NONE: return "None";
    }
    return "N/A";
}

color ZoneToColor(ENUM_ZONE zone)
{
    switch(zone)
    {
        case ZONE_DEMAND: return COLOR_DEMAND;
        case ZONE_SUPPLY: return COLOR_SUPPLY;
        case ZONE_NONE: return COLOR_NEUTRAL;
    }
    return COLOR_NEUTRAL;
}
//+------------------------------------------------------------------+
