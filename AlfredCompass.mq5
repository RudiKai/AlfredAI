//+------------------------------------------------------------------+
//|                           AlfredCompass™                         |
//|                            v1.10 (Smoothed)                      |
//| (FIXED: Added 3-bar confirmation for stable bias output)         |
//+------------------------------------------------------------------+
#property indicator_chart_window
#property strict

// CORRECTED: Two buffers for stable Bias and Confidence output
#property indicator_buffers 2
#property indicator_plots   2

#property indicator_type1   DRAW_NONE
#property indicator_label1  "Bias"
double BiasBuffer[];

#property indicator_type2   DRAW_NONE
#property indicator_label2  "Confidence"
double ConfidenceBuffer[];


#include <AlfredSettings.mqh>

// --- Enums for State Management
enum ENUM_BIAS
{
    BIAS_BULL,
    BIAS_BEAR,
    BIAS_NEUTRAL
};

// --- Globals for Smoothing Logic ---
SAlfred Alfred;
ENUM_BIAS g_confirmedBias = BIAS_NEUTRAL;
int       g_confirmedConfidence = 50;
bool      g_confirmedConflict = false;

ENUM_BIAS g_pendingBias = BIAS_NEUTRAL;
int       g_confirmationCount = 0;
datetime  g_lastBarTime = 0;

// reference timeframes
ENUM_TIMEFRAMES TFList[] = { PERIOD_M15, PERIOD_H1, PERIOD_H4 };

//+------------------------------------------------------------------+
//| Initialization                                                   |
//+------------------------------------------------------------------+
int OnInit()
{
   // --- Start: Manually set defaults (replaces InitAlfredDefaults) ---
   Alfred.enableCompass              = true;
   Alfred.compassYOffset             = 20;
   Alfred.fontSize                   = 12;
   // --- End: Manually set defaults ---

   // Setup indicator buffers
   SetIndexBuffer(0, BiasBuffer, INDICATOR_DATA);
   ArrayInitialize(BiasBuffer, 0);
   PlotIndexSetInteger(0, PLOT_DRAW_BEGIN, 1);

   SetIndexBuffer(1, ConfidenceBuffer, INDICATOR_DATA);
   ArrayInitialize(ConfidenceBuffer, 0);
   PlotIndexSetInteger(1, PLOT_DRAW_BEGIN, 1);

   return(INIT_SUCCEEDED);
}

//+------------------------------------------------------------------+
//| Main iteration with Smoothing Logic                              |
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
   if(!Alfred.enableCompass)
      return(rates_total);

   // --- Run logic only on a new bar ---
   if(time[rates_total-1] != g_lastBarTime)
   {
      g_lastBarTime = time[rates_total-1];

      // 1. Get RAW (unstable) bias from original logic
      string rawArrow, rawBiasText;
      bool rawConflict = false;
      int rawConfidence = GetRawCompassBias(rawConflict, rawBiasText);
      ENUM_BIAS rawBiasEnum = TextToBias(rawBiasText);

      // 2. Compare with pending bias and count confirmations
      if(rawBiasEnum == g_pendingBias)
      {
         g_confirmationCount++;
      }
      else
      {
         g_pendingBias = rawBiasEnum;
         g_confirmationCount = 1;
      }

      // 3. If 3 bars agree, confirm the bias for display
      if(g_confirmationCount >= 3)
      {
         g_confirmedBias = g_pendingBias;
         g_confirmedConfidence = rawConfidence; // Use the latest confidence
         g_confirmedConflict = rawConflict;
      }
   }

   // 4. Update visuals using the STABLE confirmed values
   UpdateChartVisuals();
   
   // 5. Set buffer values for other indicators (like the Pane) to read
   BiasBuffer[rates_total-1] = (g_confirmedBias == BIAS_BULL) ? 1.0 : (g_confirmedBias == BIAS_BEAR) ? -1.0 : 0.0;
   ConfidenceBuffer[rates_total-1] = g_confirmedConfidence;

   return(rates_total);
}

//+------------------------------------------------------------------+
//| Updates all chart objects based on confirmed state               |
//+------------------------------------------------------------------+
void UpdateChartVisuals()
{
    // Convert confirmed enum back to text for display
    string confirmedArrow, confirmedBiasText;
    BiasToText(g_confirmedBias, confirmedArrow, confirmedBiasText);

    // Color by strength/conflict
    string strengthLbl = WeightToLabel(g_confirmedConfidence / 5);
    color fontColor = StrengthColor(strengthLbl);
    if(g_confirmedConflict) fontColor = clrRed;

    // Time/price anchors
    datetime t = iTime(_Symbol, _Period, 0);
    double price = SymbolInfoDouble(_Symbol, SYMBOL_BID);

    // --- Draw Arrow ---
    string arrowObj = "CompassArrowObj";
    if(ObjectFind(0, arrowObj) < 0) ObjectCreate(0, arrowObj, OBJ_TEXT, 0, t, price);
    ObjectSetInteger(0, arrowObj, OBJPROP_FONTSIZE, 18);
    ObjectSetInteger(0, arrowObj, OBJPROP_COLOR, fontColor);
    ObjectSetString(0, arrowObj, OBJPROP_TEXT, confirmedArrow);
    ObjectMove(0, arrowObj, 0, t, price + Alfred.compassYOffset * _Point);

    // --- Draw Label ---
    string labelObj = "CompassLabelObj";
    string labelTxt = confirmedBiasText + " (" + IntegerToString(g_confirmedConfidence) + "%)";
    if(ObjectFind(0, labelObj) < 0) ObjectCreate(0, labelObj, OBJ_TEXT, 0, t, price);
    ObjectSetInteger(0, labelObj, OBJPROP_FONTSIZE, Alfred.fontSize);
    ObjectSetInteger(0, labelObj, OBJPROP_COLOR, fontColor);
    ObjectSetString(0, labelObj, OBJPROP_TEXT, labelTxt);
    ObjectMove(0, labelObj, 0, t, price + (Alfred.compassYOffset + 20) * _Point);

    // --- Draw Warning ---
    string warnObj = "CompassConflictObj";
    if(g_confirmedConflict)
    {
        if(ObjectFind(0, warnObj) < 0) ObjectCreate(0, warnObj, OBJ_TEXT, 0, t, price);
        ObjectSetInteger(0, warnObj, OBJPROP_FONTSIZE, 10);
        ObjectSetInteger(0, warnObj, OBJPROP_COLOR, clrRed);
        ObjectSetString(0, warnObj, OBJPROP_TEXT, "⚠️ Conflict with MagnetHUD");
        ObjectMove(0, warnObj, 0, t, price + (Alfred.compassYOffset + 38) * _Point);
    }
    else if(ObjectFind(0, warnObj) >= 0)
    {
        ObjectDelete(0, warnObj);
    }
}


//+------------------------------------------------------------------+
//| Calculate RAW Multi-TF bias (Original Logic)                     |
//+------------------------------------------------------------------+
int GetRawCompassBias(bool &conflict, string &biasText)
{
   string magnetDir = GetMagnetDirection();
   int buy = 0, sell = 0;
   
   for(int i = 0; i < ArraySize(TFList); i++)
   {
      ENUM_TIMEFRAMES tf = TFList[i];
      double slope = iMA(_Symbol, tf, 8, 3, MODE_SMA, PRICE_CLOSE)
                   - iMA(_Symbol, tf, 8, 0, MODE_SMA, PRICE_CLOSE);

      int upC = 0, downC = 0;
      for(int j = 1; j <= 5; j++)
      {
         double cNow  = iClose(_Symbol, tf, j);
         double cPrev = iClose(_Symbol, tf, j+1);
         if(cNow > cPrev) upC++;
         if(cNow < cPrev) downC++;
      }

      if(slope > 0.0003 || upC >= 4) buy++;
      if(slope < -0.0003|| downC >= 4) sell++;
   }

   int confidence = 50;
   biasText     = "NEUTRAL";
   conflict     = false;

   if(buy > sell)
   {
      biasText   = "BULL";
      confidence = MathMin(70 + buy * 5, 100);
      conflict   = (magnetDir == "🔴 Supply");
   }
   else if(sell > buy)
   {
      biasText   = "BEAR";
      confidence = MathMin(70 + sell * 5, 100);
      conflict   = (magnetDir == "🟢 Demand");
   }

   return(confidence);
}

//+------------------------------------------------------------------+
//| Grab Magnet direction from SupDemCore                            |
//+------------------------------------------------------------------+
string GetMagnetDirection()
{
   string d,s,e;
   GetTFMagnet(PERIOD_H1, d, s, e);
   return(d);
}

//+------------------------------------------------------------------+
//| Zone reader (as in SupDemCore)                                   |
//+------------------------------------------------------------------+
double GetTFMagnet(ENUM_TIMEFRAMES tf,
                   string &direction,
                   string &strength,
                   string &eta)
{
   string dZones[] = {"DZone_LTF","DZone_H1","DZone_H4","DZone_D1"};
   string sZones[] = {"SZone_LTF","SZone_H1","SZone_H4","SZone_D1"};
   double scoreD=-DBL_MAX, scoreS=-DBL_MAX, bestD=EMPTY_VALUE, bestS=EMPTY_VALUE;

   for(int i=0; i<ArraySize(dZones); i++)
   {
      string z = dZones[i];
      if(ObjectFind(0,z) < 0) continue;
      double p1 = ObjectGetDouble(0,z,OBJPROP_PRICE,0);
      double p2 = ObjectGetDouble(0,z,OBJPROP_PRICE,1);
      double mid = (p1+p2)/2;
      double sc  = 1000 - MathAbs(SymbolInfoDouble(_Symbol,SYMBOL_BID)-mid)/_Point
                      - MathAbs(p1-p2)/_Point;
      if(sc > scoreD) { scoreD=sc; bestD=mid; }
   }

   for(int i=0; i<ArraySize(sZones); i++)
   {
      string z = sZones[i];
      if(ObjectFind(0,z) < 0) continue;
      double p1 = ObjectGetDouble(0,z,OBJPROP_PRICE,0);
      double p2 = ObjectGetDouble(0,z,OBJPROP_PRICE,1);
      double mid = (p1+p2)/2;
      double sc  = 1000 - MathAbs(SymbolInfoDouble(_Symbol,SYMBOL_BID)-mid)/_Point
                      - MathAbs(p1-p2)/_Point;
      if(sc > scoreS) { scoreS=sc; bestS=mid; }
   }

   bool useD = (scoreD >= scoreS);
   direction    = useD ? "🟢 Demand" : "🔴 Supply";
   strength     = "";
   eta          = "~";
   return(useD ? bestD : bestS);
}

//+------------------------------------------------------------------+
//| --- Helper Functions ---                                         |
//+------------------------------------------------------------------+
ENUM_BIAS TextToBias(string biasText)
{
    if(biasText == "BULL") return BIAS_BULL;
    if(biasText == "BEAR") return BIAS_BEAR;
    return BIAS_NEUTRAL;
}

void BiasToText(ENUM_BIAS bias, string &arrow, string &biasText)
{
    switch(bias)
    {
        case BIAS_BULL:
            arrow = "↑";
            biasText = "BULL";
            break;
        case BIAS_BEAR:
            arrow = "↓";
            biasText = "BEAR";
            break;
        default:
            arrow = "→";
            biasText = "NEUTRAL";
            break;
    }
}

string WeightToLabel(int w)
{
   if(w <= 5)  return "Very Weak";
   if(w <= 10) return "Weak";
   if(w <= 15) return "Neutral";
   if(w <= 20) return "Strong";
               return "Very Strong";
}

color StrengthColor(string label)
{
   if(label=="Very Weak")   return clrGray;
   if(label=="Weak")        return clrSilver;
   if(label=="Neutral")     return clrKhaki;
   if(label=="Strong")      return clrAquamarine;
   if(label=="Very Strong") return clrLime;
   return clrWhite;
}
