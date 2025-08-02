//+------------------------------------------------------------------+
//| AlfredCompass.mq5 – Simplified Bias “Dots” + Arrow on Chart      |
//+------------------------------------------------------------------+
#property indicator_chart_window
#property strict

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
   InitAlfredSettings();
   SetIndexBuffer(0, dummyBuffer);
   EventSetTimer(1);
   return(INIT_SUCCEEDED);
}

//+------------------------------------------------------------------+
//| Deinitialization                                                 |
//+------------------------------------------------------------------+
void OnDeinit(const int reason)
{
   EventKillTimer();

   for(int i=0; i<ArraySize(tfs); i++)
      ObjectDelete(0, "Compass_"+tfs[i]);

   ObjectDelete(0, "Compass_ChartArrow");
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
   return(rates_total);
}

//+------------------------------------------------------------------+
//| Timer: redraw dots + arrow                                       |
//+------------------------------------------------------------------+
void OnTimer()
{
   // clear old dots
   for(int i=0; i<ArraySize(tfs); i++)
      ObjectDelete(0, "Compass_"+tfs[i]);

   // draw dots
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

   // draw arrow on price chart
   string arrowName = "Compass_ChartArrow";
   ObjectDelete(0, arrowName);

   string direction = GetCompassDirection();
   int arrowCode;
   color arrowColor;

   if(direction == "Bullish") {
      arrowCode = 233; // Wingdings up arrow
      arrowColor = bullishColor;
   }
   else if(direction == "Bearish") {
      arrowCode = 234; // Wingdings down arrow
      arrowColor = bearishColor;
   }
   else {
      arrowCode = 236; // Wingdings right arrow
      arrowColor = neutralColor;
   }

   // place arrow 5 bars ahead
   datetime futureTime = iTime(_Symbol, PERIOD_CURRENT, 0) + PeriodSeconds() * 5;
   double price = SymbolInfoDouble(_Symbol, SYMBOL_BID);

   ObjectCreate(0, arrowName, OBJ_ARROW, 0, futureTime, price);
   ObjectSetInteger(0, arrowName, OBJPROP_ARROWCODE, arrowCode);
   ObjectSetInteger(0, arrowName, OBJPROP_COLOR, arrowColor);
   ObjectSetInteger(0, arrowName, OBJPROP_WIDTH, 2);
   ObjectSetInteger(0, arrowName, OBJPROP_SELECTABLE, false);
   ObjectSetInteger(0, arrowName, OBJPROP_HIDDEN, true);
}

//+------------------------------------------------------------------+
//| Stub – return –1,0,+1 based on your bias logic                   |
//+------------------------------------------------------------------+
int GetCompassBias(string timeframe)
{
   // Example logic
   if(timeframe == "H1") return(1);
   if(timeframe == "M15") return(-1);
   return(0);
}

//+------------------------------------------------------------------+
//| Determine majority direction                                     |
//+------------------------------------------------------------------+
string GetCompassDirection()
{
   int bullishCount = 0;
   int bearishCount = 0;

   for(int i=0; i<ArraySize(tfs); i++)
   {
      int bias = GetCompassBias(tfs[i]);
      if(bias > 0) bullishCount++;
      if(bias < 0) bearishCount++;
   }

   if(bullishCount >= 3) return "Bullish";
   if(bearishCount >= 3) return "Bearish";
   return "Neutral";
}
