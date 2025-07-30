//+------------------------------------------------------------------+
//| AlfredCompass.mq5 – Simplified Bias “Dots”                       |
//+------------------------------------------------------------------+
#property indicator_chart_window
#property strict

// one dummy buffer/plot to satisfy MQL5
#property indicator_buffers 1
#property indicator_plots   1
#property indicator_type1   DRAW_NONE
double dummyBuffer[];


// includes
#include <AlfredSettings.mqh>
#include <AlfredInit.mqh>

SAlfred Alfred;


// styling inputs
input int   compassFontSize = 12;
input int   compassXOffset  = 20;
input int   compassYOffset  = 20;
input color bullishColor    = clrLimeGreen;
input color bearishColor    = clrRed;
input color neutralColor    = clrSilver;

// only these TFs
string tfs[] = {"H4","H2","H1","M30","M15"};

//+------------------------------------------------------------------+
//| Initialization                                                   |
//+------------------------------------------------------------------+
int OnInit()
{
   // initialize settings
   InitAlfredSettings();

   // assign dummy buffer
   SetIndexBuffer(0, dummyBuffer);

   // redraw on timer
   EventSetTimer(1);
   return(INIT_SUCCEEDED);
}

//+------------------------------------------------------------------+
//| Deinitialization                                                 |
//+------------------------------------------------------------------+
void OnDeinit(const int reason)
{
   EventKillTimer();

   // delete any remaining dots
   for(int i=0; i<ArraySize(tfs); i++)
      ObjectDelete(0, "Compass_"+tfs[i]);
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
   // we draw via OnTimer(), so nothing here
   return(rates_total);
}

//+------------------------------------------------------------------+
//| Timer: redraw dots                                               |
//+------------------------------------------------------------------+
void OnTimer()
{
   // clear old
   for(int i=0; i<ArraySize(tfs); i++)
      if(ObjectFind(0, "Compass_"+tfs[i])>=0)
         ObjectDelete(0, "Compass_"+tfs[i]);

   // draw new
   for(int i=0; i<ArraySize(tfs); i++)
   {
      string tf   = tfs[i];
      int    bias = GetCompassBias(tf);   // –1,0,+1
      color  col  = (bias>0 ? bullishColor 
                      : bias<0 ? bearishColor 
                               : neutralColor);
      string name = "Compass_"+tf;
      int    yOff = compassYOffset + i*(compassFontSize+4);

      ObjectCreate(0, name, OBJ_LABEL, 0, 0, 0);
      ObjectSetInteger(0, name, OBJPROP_CORNER,      CORNER_RIGHT_LOWER);
      ObjectSetInteger(0, name, OBJPROP_XDISTANCE,   compassXOffset);
      ObjectSetInteger(0, name, OBJPROP_YDISTANCE,   yOff);
      ObjectSetInteger(0, name, OBJPROP_COLOR,       col);
      ObjectSetInteger(0, name, OBJPROP_FONTSIZE,    compassFontSize);
      ObjectSetString (0, name, OBJPROP_TEXT,        "●");
      ObjectSetInteger(0, name, OBJPROP_SELECTABLE,  false);
      ObjectSetInteger(0, name, OBJPROP_HIDDEN,      true);
   }
}

//+------------------------------------------------------------------+
//| Stub – return –1,0,+1 based on your bias logic                   |
//+------------------------------------------------------------------+
int GetCompassBias(string timeframe) {
  // Example logic
  if(timeframe == "H1") {
    return(1);
  } else if(timeframe == "M15") {
    return(-1);
  }
  return(0);
}
