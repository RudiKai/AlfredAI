#property indicator_chart_window
#property strict
#property indicator_buffers 1
#property indicator_plots   1
#property indicator_type1   DRAW_NONE
#property indicator_label1  "MagnetHUD"

double dummyBuffer[];

ENUM_TIMEFRAMES TFList[] = { PERIOD_H4, PERIOD_H2, PERIOD_H1, PERIOD_M30, PERIOD_M15 };
input bool EnableMagnetDashboard = true;
input int  DashboardCorner       = CORNER_LEFT_UPPER;
input int  DashboardXOffset      = 10;
input int  DashboardYOffset      = 20;

int OnInit()
{
   SetIndexBuffer(0, dummyBuffer, INDICATOR_DATA);
   ArrayInitialize(dummyBuffer, EMPTY_VALUE);
   return INIT_SUCCEEDED;
}

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
   if(!EnableMagnetDashboard) return rates_total;

   int lineHeight = 16;

   for(int i=0; i<ArraySize(TFList); i++)
   {
      ENUM_TIMEFRAMES tf = TFList[i];
      string tfLabel = TFToString(tf);
      string strength, direction, eta;
      double magnetPrice = GetTFMagnet(tf, direction, strength, eta);

      string display = tfLabel + ": " + direction + " [" + strength + "]  " + eta;
      string objName = "MagHUD_" + tfLabel;

      if(ObjectFind(0,objName)<0)
         ObjectCreate(0,objName,OBJ_LABEL,0,0,0);

      ObjectSetInteger(0,objName,OBJPROP_CORNER, DashboardCorner);
      ObjectSetInteger(0,objName,OBJPROP_XDISTANCE, DashboardXOffset);
      ObjectSetInteger(0,objName,OBJPROP_YDISTANCE, DashboardYOffset + (i * lineHeight));
      ObjectSetInteger(0,objName,OBJPROP_FONTSIZE, 10);
      ObjectSetInteger(0,objName,OBJPROP_COLOR, StrengthColor(strength));
      ObjectSetString(0,objName,OBJPROP_TEXT, display);
   }

   // Symbol Footer under HUD
   string titleObj = "MagHUD_Footer";
   string titleTxt = "📊 Magnet Dashboard → " + _Symbol;
   int footerOffset = DashboardYOffset + ArraySize(TFList) * lineHeight + 6;

   if(ObjectFind(0,titleObj)<0)
      ObjectCreate(0,titleObj,OBJ_LABEL,0,0,0);

   ObjectSetInteger(0,titleObj,OBJPROP_CORNER, DashboardCorner);
   ObjectSetInteger(0,titleObj,OBJPROP_XDISTANCE, DashboardXOffset);
   ObjectSetInteger(0,titleObj,OBJPROP_YDISTANCE, footerOffset);
   ObjectSetInteger(0,titleObj,OBJPROP_FONTSIZE, 10);
   ObjectSetInteger(0,titleObj,OBJPROP_COLOR, clrDodgerBlue);
   ObjectSetString(0,titleObj,OBJPROP_TEXT, titleTxt);

   return rates_total;
}

//== Magnet scoring ==
double GetTFMagnet(ENUM_TIMEFRAMES tf, string &direction, string &strength, string &eta)
{
   string demandZones[] = {"DZone_LTF","DZone_H1","DZone_H4","DZone_D1"};
   string supplyZones[] = {"SZone_LTF","SZone_H1","SZone_H4","SZone_D1"};

   double bestDemand = EMPTY_VALUE, scoreD = -999;
   double bestSupply = EMPTY_VALUE, scoreS = -999;

   for(int i=0; i<ArraySize(demandZones); i++)
   {
      string z = demandZones[i];
      if(ObjectFind(0,z)>=0)
      {
         double p1 = ObjectGetDouble(0,z,OBJPROP_PRICE,0);
         double p2 = ObjectGetDouble(0,z,OBJPROP_PRICE,1);
         double mid = (p1+p2)/2;
         double dist = MathAbs(SymbolInfoDouble(_Symbol,SYMBOL_BID)-mid);
         double width = MathAbs(p1-p2);
         double score = 1000 - dist/_Point - width/_Point;
         if(score > scoreD) { scoreD = score; bestDemand = mid; }
      }
   }

   for(int i=0; i<ArraySize(supplyZones); i++)
   {
      string z = supplyZones[i];
      if(ObjectFind(0,z)>=0)
      {
         double p1 = ObjectGetDouble(0,z,OBJPROP_PRICE,0);
         double p2 = ObjectGetDouble(0,z,OBJPROP_PRICE,1);
         double mid = (p1+p2)/2;
         double dist = MathAbs(SymbolInfoDouble(_Symbol,SYMBOL_BID)-mid);
         double width = MathAbs(p1-p2);
         double score = 1000 - dist/_Point - width/_Point;
         if(score > scoreS) { scoreS = score; bestSupply = mid; }
      }
   }

   bool useDemand = (scoreD >= scoreS);
   double finalPrice = useDemand ? bestDemand : bestSupply;
   double finalScore = useDemand ? scoreD : scoreS;

   direction = useDemand ? "🟢 Demand" : "🔴 Supply";
   strength  = ScoreToLabel(finalScore);
   eta       = EstimateETA(finalPrice);

   return finalPrice;
}

//== Score to label ==
string ScoreToLabel(double score)
{
   if(score <  50) return "Very Weak";
   if(score < 150) return "Weak";
   if(score < 250) return "Neutral";
   if(score < 350) return "Strong";
   return "Very Strong";
}

//== Label color mapper ==
color StrengthColor(string label)
{
   if(label=="Very Weak")   return clrGray;
   if(label=="Weak")        return clrSilver;
   if(label=="Neutral")     return clrKhaki;
   if(label=="Strong")      return clrAquamarine;
   if(label=="Very Strong") return clrLime;
   return clrWhite;
}

//== Velocity ETA (in minutes) ==
string EstimateETA(double targetPrice)
{
   double dist = MathAbs(SymbolInfoDouble(_Symbol,SYMBOL_BID) - targetPrice)/_Point;
   double velocity = GetVelocityPerMinute();
   if(velocity < 0.3) return "Offline";
   double etaMins = dist / velocity;
   return "~" + IntegerToString((int)MathCeil(etaMins)) + "m";
}

//== Measure candle motion velocity ==
double GetVelocityPerMinute()
{
   int bars = 10;
   double total = 0;
   for(int i=1; i<=bars; i++)
   {
      double delta = MathAbs(iClose(_Symbol,_Period,i) - iClose(_Symbol,_Period,i+1))/_Point;
      total += delta;
   }
   double avg = total / bars;
   double tfMins = GetTFMinutes(_Period);
   return avg / tfMins;
}

int GetTFMinutes(ENUM_TIMEFRAMES tf)
{
   switch(tf)
   {
      case PERIOD_M1:  return 1;
      case PERIOD_M5:  return 5;
      case PERIOD_M15: return 15;
      case PERIOD_M30: return 30;
      case PERIOD_H1:  return 60;
      case PERIOD_H2:  return 120;
      case PERIOD_H4:  return 240;
      case PERIOD_D1:  return 1440;
      default:         return 60;
   }
}

string TFToString(ENUM_TIMEFRAMES tf)
{
   switch(tf)
   {
      case PERIOD_M1:  return "M1";
      case PERIOD_M5:  return "M5";
      case PERIOD_M15: return "M15";
      case PERIOD_M30: return "M30";
      case PERIOD_H1:  return "H1";
      case PERIOD_H2:  return "H2";
      case PERIOD_H4:  return "H4";
      case PERIOD_D1:  return "D1";
      default:         return "TF";
   }
}
