//+------------------------------------------------------------------+
//|                     AAI_EA_TradeManager.mq5                      |
//|               v2.3 - Enhanced Trade Journaling                   |
//|         (Takes trade signals from AAI_Indicator_SignalBrain)     |
//|              Copyright 2025, AlfredAI Project                    |
//+------------------------------------------------------------------+
#property strict
#property version   "2.3"
#property description "Manages trades based on AlfredAI signals with enhanced journaling."

#include <Trade\Trade.mqh>

#define EVT_INIT  "[INIT]"
#define EVT_BAR   "[BAR]"
#define EVT_ENTRY "[ENTRY]"
#define EVT_EXIT  "[EXIT]"
#define EVT_TS    "[TS]"

//--- Helper Enums (copied from SignalBrain for decoding)
enum ENUM_REASON_CODE
{
    REASON_NONE,
    REASON_BUY_LIQ_GRAB_ALIGNED,     // R1
    REASON_SELL_LIQ_GRAB_ALIGNED,    // R2
    REASON_NO_ZONE,                  // R3
    REASON_LOW_ZONE_STRENGTH,        // R4
    REASON_BIAS_CONFLICT             // R5
};

//--- EA Inputs
input int      MinConfidenceToTrade = 13;      // Min confidence score (0-20) to open a new trade
input double   LotSize              = 0.10;   // Fixed lot size for now
input ulong    MagicNumber          = 1337;   // Magic for this EA
input ENUM_TIMEFRAMES SignalTimeframe = PERIOD_CURRENT; // Timeframe for SignalBrain & ZoneEngine to analyze

//--- Dynamic SL/TP Inputs ---
input int      StopLossBufferPips   = 5;      // Pips to add as a buffer to the zone's distal line for SL
input double   RiskRewardRatio      = 1.5;    // Risk:Reward ratio for calculating Take Profit

//--- Trade Management Inputs
input int      StartHour          = 1;      // Session start hour (local)
input int      StartMinute        = 0;      // Session start minute
input int      EndHour            = 23;     // Session end hour (local)
input int      EndMinute          = 30;     // Session end minute
input int      FridayCloseHour    = 22;     // Fri close hour (local)
input int      BreakEvenPips      = 40;     // Pips to BE
input int      TrailingStartPips  = 60;     // Pips to start session trail
input int      TrailingStopPips   = 20;     // Session trail distance
input int      OvernightTrailPips = 15;     // Overnight trail distance
input bool     EnableLogging      = true;   // Verbose logging

//--- Globals
CTrade    trade;
double    pipValue;
string    symbolName;
double    point;

//+------------------------------------------------------------------+
//| Expert initialization                                           |
//+------------------------------------------------------------------+
int OnInit()
  {
   symbolName = _Symbol;
   point = SymbolInfoDouble(symbolName, SYMBOL_POINT);
   trade.SetExpertMagicNumber(MagicNumber);

   pipValue = point * ((SymbolInfoInteger(symbolName, SYMBOL_DIGITS) % 2 != 0) ? 10 : 1);
   if(pipValue <= 0.0)
     {
      PrintFormat("%s Failed to compute pip value for %s", EVT_INIT, symbolName);
      return(INIT_FAILED);
     }

   if(EnableLogging)
     {
      PrintFormat("%s AAI_EA_TradeManager v2.3 initialized for %s", EVT_INIT, symbolName);
      PrintFormat("%s Minimum confidence to trade: %d", EVT_INIT, MinConfidenceToTrade);
      PrintFormat("%s Dynamic SL Buffer: %d pips | RR Ratio: 1:%.2f", EVT_INIT, StopLossBufferPips, RiskRewardRatio);
     }
   return(INIT_SUCCEEDED);
  }

//+------------------------------------------------------------------+
//| Expert deinitialization                                         |
//+------------------------------------------------------------------+
void OnDeinit(const int reason)
  {
   PrintFormat("%s Deinitialized. Reason=%d", EVT_INIT, reason);
  }

//+------------------------------------------------------------------+
//| OnTick: new-bar guard and main logic loop                       |
//+------------------------------------------------------------------+
void OnTick()
  {
    static datetime lastBarTime = 0;
    datetime nowSrv = TimeCurrent();
    
    if(iTime(_Symbol, SignalTimeframe, 0) == lastBarTime)
      return;
    lastBarTime = iTime(_Symbol, SignalTimeframe, 0);

    MqlDateTime dt; 
    TimeToStruct(nowSrv, dt);

    bool inSession = IsTradingSession();
    bool overnight = !inSession;

    if(EnableLogging)
      PrintFormat(
        "[BAR] srv=%s — InSession=%s",
        TimeToString(nowSrv),
        inSession  ? "YES" : "NO"
      );
      
    if(!PositionSelect(_Symbol))
    {
      CheckForNewTrades(inSession);
    }
    
    ManageOpenPositions(dt, overnight);
  }
  
//+------------------------------------------------------------------+
//| Check & execute new entries based on SignalBrain & ZoneEngine    |
//+------------------------------------------------------------------+
void CheckForNewTrades(bool inSession)
  {
   if(!inSession)
     {
      if(EnableLogging) PrintFormat("%s — Outside session. Skipping entries.", EVT_BAR);
      return;
     }

   //--- 1. Fetch latest data from AAI_Indicator_SignalBrain ---
   double brain_data[4]; // 0:Signal, 1:Confidence, 2:ReasonCode, 3:ZoneTF
   if(CopyBuffer(iCustom(_Symbol, SignalTimeframe, "AAI_Indicator_SignalBrain.ex5"), 0, 1, 4, brain_data) < 4)
   {
      PrintFormat("%s ❌ Could not copy data from SignalBrain indicator.", EVT_BAR);
      return;
   }
   
   int signal       = (int)brain_data[0];
   int confidence   = (int)brain_data[1];
   ENUM_REASON_CODE reasonCode = (ENUM_REASON_CODE)brain_data[2];
   
   if(EnableLogging)
      PrintFormat("   %s Brain Signal: %d, Confidence: %d, Reason: %s", EVT_BAR, signal, confidence, ReasonCodeToShortString(reasonCode));

   //--- 2. Check Entry Conditions ---
   if(signal != 0 && confidence >= MinConfidenceToTrade)
   {
      //--- 3. Fetch Zone Levels for SL/TP from AAI_Indicator_ZoneEngine ---
      double zone_levels[2]; // 0: Proximal, 1: Distal
      if(CopyBuffer(iCustom(_Symbol, SignalTimeframe, "AAI_Indicator_ZoneEngine.ex5"), 6, 1, 2, zone_levels) < 2 || zone_levels[1] == 0.0)
      {
         PrintFormat("%s ❌ Could not copy valid zone levels from ZoneEngine. Aborting trade.", EVT_ENTRY);
         return;
      }
      double distal_level = zone_levels[1];

      double ask = SymbolInfoDouble(symbolName, SYMBOL_ASK);
      double bid = SymbolInfoDouble(symbolName, SYMBOL_BID);
      double sl = 0;
      double tp = 0;
      double sl_buffer_points = StopLossBufferPips * pipValue;

      // NEW: Enhanced trade comment
      string comment = StringFormat("AAI | C%d | R%d", confidence, reasonCode);

      //--- 4. Execute Trade with Dynamic SL/TP ---
      if(signal == 1) // BUY Signal
      {
         sl = distal_level - sl_buffer_points;
         double risk_points = ask - sl;
         if(risk_points <= 0) { PrintFormat("%s Invalid risk for BUY. Aborting.", EVT_ENTRY); return; }
         tp = ask + risk_points * RiskRewardRatio;
         
         if(trade.Buy(LotSize, symbolName, ask, sl, tp, comment))
            // NEW: Enhanced log message
            PrintFormat("%s Signal:BUY → Executed @%.5f | SL:%.5f TP:%.5f | Conf: %d | Reason: %s", EVT_ENTRY, trade.ResultPrice(), sl, tp, confidence, ReasonCodeToFullString(reasonCode));
         else
            PrintFormat("%s BUY failed (Err:%d %s)", EVT_ENTRY, trade.ResultRetcode(), trade.ResultComment());
      }
      else if(signal == -1) // SELL Signal
      {
         sl = distal_level + sl_buffer_points;
         double risk_points = sl - bid;
         if(risk_points <= 0) { PrintFormat("%s Invalid risk for SELL. Aborting.", EVT_ENTRY); return; }
         tp = bid - risk_points * RiskRewardRatio;

         if(trade.Sell(LotSize, symbolName, bid, sl, tp, comment))
            // NEW: Enhanced log message
            PrintFormat("%s Signal:SELL → Executed @%.5f | SL:%.5f TP:%.5f | Conf: %d | Reason: %s", EVT_ENTRY, trade.ResultPrice(), sl, tp, confidence, ReasonCodeToFullString(reasonCode));
         else
            PrintFormat("%s SELL failed (Err:%d %s)", EVT_ENTRY, trade.ResultRetcode(), trade.ResultComment());
      }
   }
  }

//+------------------------------------------------------------------+
//| Manage open positions (Unchanged)                                |
//+------------------------------------------------------------------+
void ManageOpenPositions(const MqlDateTime &loc, bool overnight)
  {
   if(!PositionSelect(_Symbol)) return;

   double ask = SymbolInfoDouble(symbolName, SYMBOL_ASK);
   double bid = SymbolInfoDouble(symbolName, SYMBOL_BID);
   
   ulong ticket    = PositionGetInteger(POSITION_TICKET);
   long  type      = PositionGetInteger(POSITION_TYPE);
   double openP    = PositionGetDouble(POSITION_PRICE_OPEN);
   double currSL   = PositionGetDouble(POSITION_SL);
   double currPrice= (type==POSITION_TYPE_BUY ? bid : ask);

   if(loc.day_of_week==FRIDAY && loc.hour>=FridayCloseHour)
     {
      PrintFormat("%s Fri-close → closing #%d", EVT_EXIT, ticket);
      trade.PositionClose(ticket);
      return;
     }

   double beDist = BreakEvenPips * pipValue;
   if(type==POSITION_TYPE_BUY && bid-openP>=beDist && (currSL < openP || currSL == 0))
      if(trade.PositionModify(ticket, openP, PositionGetDouble(POSITION_TP)))
         { currSL=openP; PrintFormat("%s BE BUY #%d", EVT_TS, ticket); }
   else if(type==POSITION_TYPE_SELL && openP-ask>=beDist && (currSL > openP || currSL == 0))
      if(trade.PositionModify(ticket, openP, PositionGetDouble(POSITION_TP)))
         { currSL=openP; PrintFormat("%s BE SELL #%d", EVT_TS, ticket); }

   HandleTrailingStop(ticket, type, openP, currSL, currPrice, overnight);
  }

//+------------------------------------------------------------------+
//| Trailing-stop logic (Unchanged)                                  |
//+------------------------------------------------------------------+
void HandleTrailingStop(ulong ticket,long type,double openP,double currSL,double currPrice,bool overnight)
  {
   if(currSL<=0.0) return;

   double trailDist = (overnight ? OvernightTrailPips : TrailingStopPips) * pipValue;
   double startDist = TrailingStartPips * pipValue;
   double newSL     = currSL;

   bool canTrail = (overnight || 
                    (type==POSITION_TYPE_BUY && currPrice-openP>=startDist) ||
                    (type==POSITION_TYPE_SELL && openP-currPrice>=startDist));
   if(!canTrail) return;

   if(type==POSITION_TYPE_BUY && currPrice-trailDist>currSL)
      newSL = currPrice-trailDist;
   else if(type==POSITION_TYPE_SELL && currPrice+trailDist<currSL)
      newSL = currPrice+trailDist;

   if(newSL!=currSL)
      if(trade.PositionModify(ticket, newSL, PositionGetDouble(POSITION_TP)))
         PrintFormat("%s %s Trail #%d → %.5f",
                     EVT_TS,
                     (overnight?"O/N":"Session"),
                     ticket, newSL);
  }

//+------------------------------------------------------------------+
//| Is it within the trading session? (Unchanged)                    |
//+------------------------------------------------------------------+
bool IsTradingSession()
  {
    datetime nowSrv = TimeCurrent();
    MqlDateTime dt; TimeToStruct(nowSrv, dt);

    if(dt.day_of_week < MONDAY || dt.day_of_week > FRIDAY)
      return false;

    int curMin = dt.hour*60 + dt.min;
    int startTotalMin = StartHour * 60 + StartMinute;
    int endTotalMin = EndHour * 60 + EndMinute;

    return (curMin >= startTotalMin && curMin < endTotalMin);
  }
  
//+------------------------------------------------------------------+
//|           HELPER: Converts Reason Code to String                 |
//+------------------------------------------------------------------+
string ReasonCodeToFullString(ENUM_REASON_CODE code)
{
    switch(code)
    {
        case REASON_BUY_LIQ_GRAB_ALIGNED:  return "Buy signal: Liquidity Grab in Demand Zone with Bias Alignment.";
        case REASON_SELL_LIQ_GRAB_ALIGNED: return "Sell signal: Liquidity Grab in Supply Zone with Bias Alignment.";
        case REASON_NO_ZONE:               return "No Zone";
        case REASON_LOW_ZONE_STRENGTH:     return "Low Zone Strength";
        case REASON_BIAS_CONFLICT:         return "Bias Conflict";
        case REASON_NONE:
        default:                           return "N/A";
    }
}

string ReasonCodeToShortString(ENUM_REASON_CODE code)
{
    switch(code)
    {
        case REASON_BUY_LIQ_GRAB_ALIGNED:  return "BuyLiqGrab";
        case REASON_SELL_LIQ_GRAB_ALIGNED: return "SellLiqGrab";
        case REASON_NO_ZONE:               return "NoZone";
        case REASON_LOW_ZONE_STRENGTH:     return "LowStrength";
        case REASON_BIAS_CONFLICT:         return "Conflict";
        case REASON_NONE:
        default:                           return "None";
    }
}
//+------------------------------------------------------------------+
