//+------------------------------------------------------------------+
//|                   AAI_Indicator_Dashboard.mq5                    |
//|             v3.1 - Fixed OnCalculate Signature Error             |
//|        (Displays all data from the AAI indicator suite)          |
//|              Copyright 2025, AlfredAI Project                    |
//+------------------------------------------------------------------+
#property strict
#property indicator_chart_window
#property indicator_plots 0
#property version "3.1"

// --- UI Constants ---
#define PANE_PREFIX "AAI_Dashboard_v3_"
#define PANE_X_POS 15
#define PANE_Y_POS 15
#define PANE_WIDTH 250

// --- Font Sizes ---
#define FONT_SIZE_TITLE 14
#define FONT_SIZE_HEADER 12
#define FONT_SIZE_NORMAL 10

// --- Colors ---
#define COLOR_BG         (color)C'34,34,34'
#define COLOR_HEADER     C'135,206,250' // LightSkyBlue
#define COLOR_LABEL      C'211,211,211' // LightGray
#define COLOR_BULL       C'34,139,34'   // ForestGreen
#define COLOR_BEAR       C'220,20,60'   // Crimson
#define COLOR_NEUTRAL    C'255,215,0'   // Gold
#define COLOR_AMBER      C'255,193,7'   // Amber
#define COLOR_WHITE      C'255,255,255'
#define COLOR_SEPARATOR  C'70,70,70'

// --- Indicator Handles ---
int g_sb_handle = INVALID_HANDLE;
int g_ze_handle = INVALID_HANDLE;
int g_bc_handle = INVALID_HANDLE;

// --- State Variables ---
struct DashboardState
{
    // SB Data
    double   signal;
    double   confidence;
    
    // ZE Data
    double   ze_strength;

    // BC Data
    double   bias;
    
    // Terminal Data
    int      spread;
    string   session_status;
    
    // Internal State
    datetime last_alert_time;
    bool     autotrade_enabled; // Visual kill-switch
};

DashboardState g_state;

// --- Forward Declarations ---
void DrawDashboard();
void DrawCard(int x, int &y, int width, string title, const string &rows[], const color &row_colors[]);
void DrawLabel(string name, string text, int x, int y, int size, color clr, string font = "Arial", ENUM_ANCHOR_POINT anchor = ANCHOR_LEFT);
void DrawRect(string name, int x, int y, int w, int h, color bg_color);
void UpdateState();
string GetSessionStatus();

//+------------------------------------------------------------------+
//| Initialization                                                   |
//+------------------------------------------------------------------+
int OnInit()
{
    // --- Initialize Indicator Handles ---
    g_sb_handle = iCustom(_Symbol, _Period, "AAI_Indicator_SignalBrain");
    g_ze_handle = iCustom(_Symbol, _Period, "AAI_Indicator_ZoneEngine");
    g_bc_handle = iCustom(_Symbol, _Period, "AAI_Indicator_BiasCompass");
    
    if(g_sb_handle == INVALID_HANDLE || g_ze_handle == INVALID_HANDLE || g_bc_handle == INVALID_HANDLE)
    {
        Print("Dashboard Error: Failed to initialize one or more indicator handles.");
        return INIT_FAILED;
    }
    
    // --- Initialize State ---
    g_state.signal = 0;
    g_state.confidence = 0;
    g_state.ze_strength = 0;
    g_state.bias = 0;
    g_state.spread = 0;
    g_state.session_status = "---";
    g_state.last_alert_time = 0;
    g_state.autotrade_enabled = true; // Default to on

    // --- Set Timer for updates. MQL5's minimum is 1 second. ---
    EventSetTimer(1); 
    
    return INIT_SUCCEEDED;
}

//+------------------------------------------------------------------+
//| Deinitialization                                                 |
//+------------------------------------------------------------------+
void OnDeinit(const int reason)
{
    EventKillTimer();
    ObjectsDeleteAll(0, PANE_PREFIX);
    ChartRedraw();
    
    // --- Release Handles ---
    if(g_sb_handle != INVALID_HANDLE) IndicatorRelease(g_sb_handle);
    if(g_ze_handle != INVALID_HANDLE) IndicatorRelease(g_ze_handle);
    if(g_bc_handle != INVALID_HANDLE) IndicatorRelease(g_bc_handle);
}

//+------------------------------------------------------------------+
//| OnCalculate - Required by MQL5, but logic is in OnTimer.         |
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
    return rates_total;
}

//+------------------------------------------------------------------+
//| OnTimer - Main update and drawing loop                           |
//+------------------------------------------------------------------+
void OnTimer()
{
    UpdateState();
    DrawDashboard();
    ChartRedraw();
}

//+------------------------------------------------------------------+
//| Fetches all data and updates the global state struct             |
//+------------------------------------------------------------------+
void UpdateState()
{
    // --- Fetch SignalBrain Data ---
    double sb_buffer[4];
    if(CopyBuffer(g_sb_handle, 0, 1, 4, sb_buffer) == 4)
    {
        g_state.signal = sb_buffer[0];
        g_state.confidence = sb_buffer[1];
        
        // Check for new alert (a high-confidence signal on a closed bar)
        if(g_state.signal != 0 && g_state.confidence >= 75)
        {
            g_state.last_alert_time = TimeCurrent();
        }
    }

    // --- Fetch ZoneEngine Data ---
    double ze_buffer[1];
    if(CopyBuffer(g_ze_handle, 0, 1, 1, ze_buffer) == 1)
    {
        g_state.ze_strength = ze_buffer[0];
    }
    
    // --- Fetch BiasCompass Data ---
    double bc_buffer[1];
    if(CopyBuffer(g_bc_handle, 0, 1, 1, bc_buffer) == 1)
    {
        g_state.bias = bc_buffer[0];
    }

    // --- Fetch Terminal Data ---
    g_state.spread = (int)SymbolInfoInteger(_Symbol, SYMBOL_SPREAD);
    g_state.session_status = GetSessionStatus();
    
    // Note: The kill-switch is visual only. In a real system, it would read a GlobalVariable.
    // We simulate it being toggled every 10 seconds for demonstration.
    g_state.autotrade_enabled = (TimeCurrent() / 10) % 2 == 0; 
}


//+------------------------------------------------------------------+
//| Main function to draw the entire dashboard UI                    |
//+------------------------------------------------------------------+
void DrawDashboard()
{
    int x = PANE_X_POS;
    int y = PANE_Y_POS;
    int y_start = y;
    
    // --- Draw Title ---
    DrawLabel("Title", "AlfredAI Dashboard", x + 5, y, FONT_SIZE_TITLE, COLOR_HEADER, "Calibri Bold");
    y += 30;

    // --- Card 1: Core Signal ---
    string signal_text;
    color signal_color;
    if(g_state.signal > 0.5) { signal_text = "BUY"; signal_color = COLOR_BULL; }
    else if(g_state.signal < -0.5) { signal_text = "SELL"; signal_color = COLOR_BEAR; }
    else { signal_text = "NEUTRAL"; signal_color = COLOR_NEUTRAL; }
    
    string card1_rows[] = {
        "Signal: " + signal_text,
        "Confidence: " + StringFormat("%.0f / 100", g_state.confidence)
    };
    color card1_colors[] = { signal_color, COLOR_WHITE };
    DrawCard(x, y, PANE_WIDTH, "CORE SIGNAL", card1_rows, card1_colors);
    
    // --- Card 2: Market Context ---
    string bias_text;
    color bias_color;
    if(g_state.bias > 0.5) { bias_text = "BULLISH"; bias_color = COLOR_BULL; }
    else if(g_state.bias < -0.5) { bias_text = "BEARISH"; bias_color = COLOR_BEAR; }
    else { bias_text = "NEUTRAL"; bias_color = COLOR_NEUTRAL; }
    
    string card2_rows[] = {
        "HTF Bias: " + bias_text,
        "ZE Strength: " + StringFormat("%.0f / 100", g_state.ze_strength),
        "Spread: " + (string)g_state.spread + " pts"
    };
    color card2_colors[] = { bias_color, COLOR_WHITE, (g_state.spread > 20 ? COLOR_AMBER : COLOR_WHITE) };
    DrawCard(x, y, PANE_WIDTH, "MARKET CONTEXT", card2_rows, card2_colors);

    // --- Card 3: System Status ---
    string last_alert_str = (g_state.last_alert_time == 0) ? "None" : TimeToString(g_state.last_alert_time, TIME_SECONDS);
    string autotrade_str = g_state.autotrade_enabled ? "ACTIVE" : "DISABLED";
    color autotrade_color = g_state.autotrade_enabled ? COLOR_BULL : COLOR_AMBER;

    string card3_rows[] = {
        "Session: " + g_state.session_status,
        "Last Alert: " + last_alert_str,
        "Auto-Trade: " + autotrade_str
    };
    color card3_colors[] = { COLOR_WHITE, COLOR_WHITE, autotrade_color };
    DrawCard(x, y, PANE_WIDTH, "SYSTEM STATUS", card3_rows, card3_colors);

    // --- Draw Background for all cards ---
    DrawRect("Background", x, y_start, PANE_WIDTH, y - y_start, COLOR_BG);
}

//+------------------------------------------------------------------+
//| Draws a card with a title and rows of text                       |
//+------------------------------------------------------------------+
void DrawCard(int x, int &y, int width, string title, const string &rows[], const color &row_colors[])
{
    int x_padding = 10;
    int y_padding = 10;
    int line_height = 20;

    DrawLabel("CardTitle_" + title, title, x + x_padding, y, FONT_SIZE_HEADER, COLOR_HEADER, "Calibri");
    y += line_height + 5;
    
    for(int i = 0; i < ArraySize(rows); i++)
    {
        string label_text = StringSubstr(rows[i], 0, StringFind(rows[i], ":") + 1);
        string value_text = StringSubstr(rows[i], StringFind(rows[i], ":") + 2);
        
        DrawLabel("CardRow_Label_" + title + (string)i, label_text, x + x_padding, y, FONT_SIZE_NORMAL, COLOR_LABEL, "Calibri");
        DrawLabel("CardRow_Value_" + title + (string)i, value_text, x + 120, y, FONT_SIZE_NORMAL, row_colors[i], "Calibri Bold");
        y += line_height;
    }
    
    y += y_padding;
    DrawLabel("CardSeparator_" + title, "------------------------------------", x + x_padding, y - 15, FONT_SIZE_NORMAL, COLOR_SEPARATOR);
}


//+------------------------------------------------------------------+
//| Creates or updates a text label on the chart                     |
//+------------------------------------------------------------------+
void DrawLabel(string name, string text, int x, int y, int size, color clr, string font="Arial", ENUM_ANCHOR_POINT anchor=ANCHOR_LEFT)
{
    string obj_name = PANE_PREFIX + name;
    if(ObjectFind(0, obj_name) < 0)
    {
        ObjectCreate(0, obj_name, OBJ_LABEL, 0, 0, 0);
        ObjectSetInteger(0, obj_name, OBJPROP_XDISTANCE, x);
        ObjectSetInteger(0, obj_name, OBJPROP_YDISTANCE, y);
        ObjectSetInteger(0, obj_name, OBJPROP_CORNER, CORNER_LEFT_UPPER);
        ObjectSetString(0, obj_name, OBJPROP_FONT, font);
        ObjectSetInteger(0, obj_name, OBJPROP_ANCHOR, anchor);
        ObjectSetInteger(0, obj_name, OBJPROP_BACK, false);
    }
    ObjectSetString(0, obj_name, OBJPROP_TEXT, text);
    ObjectSetInteger(0, obj_name, OBJPROP_FONTSIZE, size);
    ObjectSetInteger(0, obj_name, OBJPROP_COLOR, clr);
}

//+------------------------------------------------------------------+
//| Creates or updates a rectangle label on the chart                |
//+------------------------------------------------------------------+
void DrawRect(string name, int x, int y, int w, int h, color bg_color)
{
    string obj_name = PANE_PREFIX + name;
    if(ObjectFind(0, obj_name) < 0)
    {
        ObjectCreate(0, obj_name, OBJ_RECTANGLE_LABEL, 0, 0, 0);
        ObjectSetInteger(0, obj_name, OBJPROP_XDISTANCE, x);
        ObjectSetInteger(0, obj_name, OBJPROP_YDISTANCE, y);
        ObjectSetInteger(0, obj_name, OBJPROP_CORNER, CORNER_LEFT_UPPER);
        ObjectSetInteger(0, obj_name, OBJPROP_BACK, true);
        ObjectSetInteger(0, obj_name, OBJPROP_BORDER_TYPE, BORDER_FLAT);
    }
    ObjectSetInteger(0, obj_name, OBJPROP_XSIZE, w);
    ObjectSetInteger(0, obj_name, OBJPROP_YSIZE, h);
    ObjectSetInteger(0, obj_name, OBJPROP_BGCOLOR, bg_color);
    ObjectSetInteger(0, obj_name, OBJPROP_COLOR, bg_color);
}

//+------------------------------------------------------------------+
//| Determines the current trading session status                    |
//+------------------------------------------------------------------+
string GetSessionStatus()
{
   MqlDateTime dt;
   TimeCurrent(dt);
   int hour = dt.hour; // Using server time
   if(hour >= 1 && hour < 9) return "Asian";
   if(hour >= 9 && hour < 17) return "London";
   if(hour >= 14 && hour < 22) return "New York";
   if(hour >= 9 && hour < 12) return "London/Asian Overlap";
   if(hour >= 14 && hour < 17) return "London/NY Overlap";
   return "Inter-Session";
}

