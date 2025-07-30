//+------------------------------------------------------------------+
//| Alfred_AI_Pane.mq5 – HUD merged into Pane                        |
//+------------------------------------------------------------------+
#property indicator_chart_window
#property strict



// one dummy buffer/plot to satisfy MQL5
#property indicator_buffers 1
#property indicator_plots   1
#property indicator_type1   DRAW_NONE
double paneDummy[];


// includes
#include <AlfredSettings.mqh>
#include <AlfredInit.mqh>

SAlfred Alfred;


// Pane styling
input int    paneXOffset     = 10;
input int    paneYOffset     = 10;
input int    paneFontSize    = 12;
input color  paneTextColor   = clrWhite;

// strength thresholds
input double strongThreshold = 70.0;
input double weakThreshold   = 40.0;

// TF list for Pane
string tfsPane[] = {"H4","H2","H1","M30","M15"};

//+------------------------------------------------------------------+
//| Initialization                                                   |
//+------------------------------------------------------------------+
int OnInit()
{
   InitAlfredSettings();
   SetIndexBuffer(0, paneDummy);
   return(INIT_SUCCEEDED);
}

//+------------------------------------------------------------------+
//| Deinitialization                                                 |
//+------------------------------------------------------------------+
void OnDeinit(const int reason)
{
   for(int i=0; i<ArraySize(tfsPane); i++)
      ObjectDelete(0, "Pane_TFBias_"+tfsPane[i]);
}

//+------------------------------------------------------------------+
//| Stub OnCalculate (required by MQL5)                              |
//+------------------------------------------------------------------+
int OnCalculate(const int rates_total,
                const int prev_calculated,
                const datetime &time[],
                const double   &open[],
                const double   &high[],
                const double   &low[],
                const double   &close[],
                const long     &tick_volume[],
                const long     &volume[],
                const int      &spread[])
{
   // nothing to plot, we draw via ChartEvent
   return(rates_total);
}

//+------------------------------------------------------------------+
//| Chart Event: redraw Pane section                                 |
//+------------------------------------------------------------------+
void OnChartEvent(const int id,
                  const long &lparam,
                  const double &dparam,
                  const string &sparam)
{
   DrawPaneTimeframeBias();
   // … your existing Pane background & signal code …
}

//+------------------------------------------------------------------+
//| Draw the Timeframe Bias section                                 |
//+------------------------------------------------------------------+
void DrawPaneTimeframeBias()
{
   // clear old
   for(int i=0; i<ArraySize(tfsPane); i++)
   {
      string name = "Pane_TFBias_"+tfsPane[i];
      if(ObjectFind(0,name)>=0)
         ObjectDelete(0,name);
   }

   // skip if disabled
   if(!Alfred.enablePaneTFBias)
      return;

   // draw each TF
   for(int i=0; i<ArraySize(tfsPane); i++)
   {
      string tf        = tfsPane[i];
      int    bias      = GetCompassBias(tf);           // –1,0,+1
      double strength = GetCompassStrength(tf);        // 0–100

      // pick emoji
      string emoji = (bias>0 ? "🟢" : bias<0 ? "🔴" : "⚪");
      // pick label
      string lbl   = (strength>=strongThreshold ? "Strong"
                      : strength>=weakThreshold   ? "Weak" 
                                                   : "Neutral");

      string text  = StringFormat("%s %s %s", tf, emoji, lbl);
      string name  = "Pane_TFBias_"+tf;
      int    yOff  = paneYOffset + i*(paneFontSize+2);

      ObjectCreate(0, name, OBJ_LABEL, 0, 0, 0);
      ObjectSetInteger(0, name, OBJPROP_CORNER,      CORNER_LEFT_UPPER);
      ObjectSetInteger(0, name, OBJPROP_XDISTANCE,   paneXOffset);
      ObjectSetInteger(0, name, OBJPROP_YDISTANCE,   yOff);
      ObjectSetInteger(0, name, OBJPROP_COLOR,       paneTextColor);
      ObjectSetInteger(0, name, OBJPROP_FONTSIZE,    paneFontSize);
      ObjectSetString (0, name, OBJPROP_TEXT,        text);
      ObjectSetInteger(0, name, OBJPROP_SELECTABLE,  false);
      ObjectSetInteger(0, name, OBJPROP_HIDDEN,      true);
   }
}

//+------------------------------------------------------------------+
//| Simulated bias: cycles through -1, 0, +1                         |
//+------------------------------------------------------------------+
int GetCompassBias(string timeframe)
{
   static int bias = -1;

   // Cycle bias every call: -1 → 0 → +1 → -1 ...
   bias++;
   if (bias > 1)
      bias = -1;

   return bias;
}

//+------------------------------------------------------------------+
//| Simulated strength: random value between 0 and 100               |
//+------------------------------------------------------------------+
double GetCompassStrength(string timeframe)
{
   // Generate pseudo-random strength
   double strength = MathRand() % 101; // 0 to 100
   return strength;
}
