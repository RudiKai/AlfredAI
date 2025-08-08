//+------------------------------------------------------------------+
//|                     AAI_EA_TradeManager.mq5                      |
//|               v2.1 - Brain Integrated Entry Logic                |
//|         (Takes trade signals from AAI_Indicator_SignalBrain)     |
//|              Copyright 2025, AlfredAI Project                    |
//+------------------------------------------------------------------+
#property strict
#property version   "2.1"
#property description "Manages trades based on AlfredAI signals."

#include <Trade\Trade.mqh>

#define EVT_INIT  "[INIT]"
#define EVT_BAR   "[BAR]"
#define EVT_ENTRY "[ENTRY]"
#define EVT_EXIT  "[EXIT]"
#define EVT_TS    "[TS]"

//--- EA Inputs
input int      MinConfidenceToTrade = 13;      // Min confidence score (0-20) to open a new trade
input double   LotSize              = 0.10;   // Fixed lot size for now
input ulong    MagicNumber          = 1337;   // Magic for this EA
input ENUM_TIMEFRAMES SignalTimeframe = PERIOD_CURRENT; // Timeframe for the SignalBrain to analyze

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

//+------------------------------------------------------------------+
//| Expert initialization                                           |
//+------------------------------------------------------------------+
int OnInit()
  {
   symbolName = _Symbol;
   trade.SetExpertMagicNumber(MagicNumber);

   // compute pip-value
   pipValue = SymbolInfoDouble(symbolName, SYMBOL_POINT) *
              ((SymbolInfoInteger(symbolName, SYMBOL_DIGITS) % 2)!=0 ? 10 : 1);
   if(pipValue<=0.0)
     {
      PrintFormat("%s Failed to compute pip value for %s", EVT_INIT, symbolName);
      return(INIT_FAILED);
     }

   if(EnableLogging)
     {
      PrintFormat("%s AAI_EA_TradeManager initialized for %s", EVT_INIT, symbolName);
      PrintFormat("%s Minimum confidence to trade: %d", EVT_INIT, MinConfidenceToTrade);
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
    datetime nowSrv = TimeCurrent(); // Use TimeCurrent for more reliable new bar detection
    
    // Check for new bar on the signal timeframe
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
      
    // --- Main Logic Flow ---
    // Only check for new trades if no position is currently open for this symbol
    if(!PositionSelect(_Symbol))
    {
      CheckForNewTrades(inSession);
    }
    
    ManageOpenPositions(dt, overnight);
  }
  
//+------------------------------------------------------------------+
//| Check & execute new entries based on SignalBrain                 |
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
   // We check the closed bar (index 1) for a stable signal
   if(CopyBuffer(iCustom(_Symbol, SignalTimeframe, "AAI_Indicator_SignalBrain.ex5"), 0, 1, 4, brain_data) < 4)
   {
      PrintFormat("%s ❌ Could not copy data from SignalBrain indicator.", EVT_BAR);
      return;
   }
   
   int signal     = (int)brain_data[0];
   int confidence = (int)brain_data[1];
   
   if(EnableLogging)
      PrintFormat("   %s Brain Signal: %d, Confidence: %d", EVT_BAR, signal, confidence);

   //--- 2. Check Entry Conditions ---
   if(signal != 0 && confidence >= MinConfidenceToTrade)
   {
      double ask = SymbolInfoDouble(symbolName, SYMBOL_ASK);
      double bid = SymbolInfoDouble(symbolName, SYMBOL_BID);
      
      // NOTE: SL/TP are 0 for now. This will be replaced in the next phase
      // with dynamic levels from the ZoneEngine.
      double sl = 0;
      double tp = 0;
      
      string comment = "AAI | Conf " + (string)confidence;

      //--- 3. Execute Trade ---
      if(signal == 1) // BUY Signal
      {
         if(trade.Buy(LotSize, symbolName, ask, sl, tp, comment))
            PrintFormat("%s Signal:BUY → Executed BUY @%.5f | Confidence: %d", EVT_ENTRY, trade.ResultPrice(), confidence);
         else
            PrintFormat("%s BUY failed (Err:%d %s)", EVT_ENTRY, trade.ResultRetcode(), trade.ResultComment());
      }
      else if(signal == -1) // SELL Signal
      {
         if(trade.Sell(LotSize, symbolName, bid, sl, tp, comment))
            PrintFormat("%s Signal:SELL → Executed SELL @%.5f | Confidence: %d", EVT_ENTRY, trade.ResultPrice(), confidence);
         else
            PrintFormat("%s SELL failed (Err:%d %s)", EVT_ENTRY, trade.ResultRetcode(), trade.ResultComment());
      }
   }
  }

//+------------------------------------------------------------------+
//| Manage open positions (Unchanged for now)                        |
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

   // 1) Friday close
   if(loc.day_of_week==FRIDAY && loc.hour>=FridayCloseHour)
     {
      PrintFormat("%s Fri-close → closing #%d", EVT_EXIT, ticket);
      trade.PositionClose(ticket);
      return;
     }

   // 2) Break-even
   double beDist = BreakEvenPips * pipValue;
   if(type==POSITION_TYPE_BUY && bid-openP>=beDist && (currSL < openP || currSL == 0))
      if(trade.PositionModify(ticket, openP, PositionGetDouble(POSITION_TP)))
         { currSL=openP; PrintFormat("%s BE BUY #%d", EVT_TS, ticket); }
   else if(type==POSITION_TYPE_SELL && openP-ask>=beDist && (currSL > openP || currSL == 0))
      if(trade.PositionModify(ticket, openP, PositionGetDouble(POSITION_TP)))
         { currSL=openP; PrintFormat("%s BE SELL #%d", EVT_TS, ticket); }

   // 3) Trailing stop
   HandleTrailingStop(ticket, type, openP, currSL, currPrice, overnight);
  }

//+------------------------------------------------------------------+
//| Trailing-stop logic (Unchanged for now)                          |
//+------------------------------------------------------------------+
void HandleTrailingStop(ulong ticket,long type,double openP,double currSL,double currPrice,bool overnight)
  {
   if(currSL<=0.0) return;

   double trailDist = (overnight ? OvernightTrailPips : TrailingStopPips) * pipValue;
   double startDist = TrailingStartPips * pipValue;
   double newSL     = currSL;

   // condition to start trailing
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
