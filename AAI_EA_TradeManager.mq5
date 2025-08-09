//+------------------------------------------------------------------+
//|                     AAI_EA_TradeManager.mq5                      |
//|               v3.4 - Final Clean Compile                         |
//|         (Takes trade signals from AAI_Indicator_SignalBrain)     |
//|                                                                  |
//|              Copyright 2025, AlfredAI Project                    |
//+------------------------------------------------------------------+
#property strict
#property version   "3.4"
#property description "Manages trades and logs closed positions to a CSV journal."
#include <Trade\Trade.mqh>

#define EVT_INIT  "[INIT]"
#define EVT_BAR   "[BAR]"
#define EVT_ENTRY "[ENTRY]"
#define EVT_EXIT  "[EXIT]"
#define EVT_TS    "[TS]"
#define EVT_PARTIAL "[PARTIAL]"
#define EVT_JOURNAL "[JOURNAL]"


//--- Helper Enums (copied from SignalBrain for decoding)
enum ENUM_REASON_CODE
{
    REASON_NONE,
    REASON_BUY_HTF_CONTINUATION,
    REASON_SELL_HTF_CONTINUATION,
    REASON_BUY_LIQ_GRAB_ALIGNED,
    REASON_SELL_LIQ_GRAB_ALIGNED,
    REASON_NO_ZONE,
    REASON_LOW_ZONE_STRENGTH,
    REASON_BIAS_CONFLICT
};

//--- EA Inputs
input int      MinConfidenceToTrade = 13;      // Min confidence score (0-20) to open a new trade
input ulong    MagicNumber          = 1337;   // Magic for this EA
input ENUM_TIMEFRAMES SignalTimeframe = PERIOD_CURRENT; // Timeframe for SignalBrain & ZoneEngine to analyze

//--- Dynamic Risk & Position Sizing Inputs ---
input double   RiskPercent          = 1.0;    // Percent of account balance to risk per trade
input double   MinLotSize           = 0.01;   // Minimum allowable lot size
input double   MaxLotSize           = 10.0;   // Maximum allowable lot size
input int      StopLossBufferPips   = 5;      // Pips to add as a buffer to the zone's distal line for SL
input double   RiskRewardRatio      = 1.5;    // Final Risk:Reward ratio for calculating Take Profit

//--- Trade Management Inputs ---
input bool     EnablePartialProfits = true;    // Enable taking partial profits at 1R
input double   PartialProfitRR      = 1.0;    // RR level to take partial profit (e.g., 1.0 = 1R)
input double   PartialClosePercent  = 50.0;   // Percentage of position to close for partial profit
input int      BreakEvenPips      = 40;     // Pips to BE
input int      TrailingStartPips  = 40;     // Pips to start session trail
input int      TrailingStopPips   = 30;     // Session trail distance
input int      OvernightTrailPips = 30;     // Overnight trail distance
input int      FridayCloseHour    = 22;     // Fri close hour (local)
input int      StartHour          = 1;      // Session start hour (local)
input int      StartMinute        = 0;      // Session start minute
input int      EndHour            = 23;     // Session end hour (local)
input int      EndMinute          = 30;     // Session end minute
input bool     EnableLogging      = true;   // Verbose logging

//--- Journaling Inputs ---
input bool     EnableJournaling   = true;   // Enable writing closed trades to a CSV file
input string   JournalFileName    = "AlfredAI_Journal.csv"; // File name for the trade journal

//--- Globals
CTrade    trade;
double    pipValue;
string    symbolName;
double    point;
static ulong g_logged_positions[]; // Array to store tickets of logged positions
int       g_logged_positions_total = 0;
// --- DEBUG FLAG ---
const bool EnableEADebugLogging = true; // DEBUG: This is now hard-coded to ON for testing.
const ENUM_TIMEFRAMES HTF_DEBUG = PERIOD_H4;
const ENUM_TIMEFRAMES LTF_DEBUG = PERIOD_M15;


//+------------------------------------------------------------------+
//| Calculate Lot Size based on Risk % and Confidence                |
//+------------------------------------------------------------------+
double CalculateLotSize(int confidence, double sl_distance_points)
{
   if(sl_distance_points <= 0) return 0.0;
   double account_balance = AccountInfoDouble(ACCOUNT_BALANCE);
   double risk_amount = account_balance * (RiskPercent / 100.0);
   double tick_value_loss = SymbolInfoDouble(symbolName, SYMBOL_TRADE_TICK_VALUE_LOSS);
   double loss_per_lot = sl_distance_points * tick_value_loss;
   if(loss_per_lot <= 0) return 0.0;
   double base_lot_size = risk_amount / loss_per_lot;
   double scale_min = 0.5;
   double scale_max = 1.0;
   double conf_range = 20.0 - MinConfidenceToTrade;
   double conf_step = confidence - MinConfidenceToTrade;
   double scaling_factor = scale_min;
   if(conf_range > 0)
     {
      scaling_factor = scale_min + ((scale_max - scale_min) * (conf_step / conf_range));
     }
   scaling_factor = fmax(scale_min, fmin(scale_max, scaling_factor));
   double final_lot_size = base_lot_size * scaling_factor;
   double lot_step = SymbolInfoDouble(symbolName, SYMBOL_VOLUME_STEP);
   final_lot_size = round(final_lot_size / lot_step) * lot_step;
   final_lot_size = fmax(MinLotSize, fmin(MaxLotSize, final_lot_size));

   if(EnableLogging)
      PrintFormat("   LotCalc: RiskAmt=%.2f, BaseLots=%.2f, Conf=%d, Scale=%.2f, FinalLots=%.2f",
                  risk_amount, base_lot_size, confidence, scaling_factor, final_lot_size);

   return final_lot_size;
}


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
   if(EnableJournaling)
      WriteJournalHeader();

   if(EnableLogging)
     {
      PrintFormat("%s AAI_EA_TradeManager v3.4 initialized for %s", EVT_INIT, symbolName);
      PrintFormat("%s Journaling: %s to file '%s'", EVT_INIT, EnableJournaling ? "Enabled" : "Disabled", JournalFileName);
     }
   ArrayResize(g_logged_positions, 0);
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
//| Trade Transaction Event Handler                                  |
//+------------------------------------------------------------------+
void OnTradeTransaction(const MqlTradeTransaction &trans,
                        const MqlTradeRequest &request,
                        const MqlTradeResult &result)
{
    if(!EnableJournaling) return;

    // WORKAROUND: Check magic number from the deal history to bypass compiler issue
    if(trans.type == TRADE_TRANSACTION_DEAL_ADD)
    {
        if(HistoryDealSelect(trans.deal))
        {
            if((ulong)HistoryDealGetInteger(trans.deal, DEAL_MAGIC) == MagicNumber)
            {
                if(HistoryDealGetInteger(trans.deal, DEAL_ENTRY) == DEAL_ENTRY_OUT)
                {
                    ulong position_id = HistoryDealGetInteger(trans.deal, DEAL_POSITION_ID);
                    
                    if(!PositionSelectByTicket(position_id))
                    {
                        if(!IsPositionLogged(position_id))
                        {
                            LogClosedPosition(position_id);
                            AddToLoggedList(position_id);
                        }
                    }
                }
            }
        }
    }
}


//+------------------------------------------------------------------+
//| OnTick: new-bar guard and main logic loop                       |
//+------------------------------------------------------------------+
void OnTick()
  {
   static datetime lastBarTime = 0;
   datetime nowSrv = TimeCurrent();
   if(iTime(_Symbol, SignalTimeframe, 0) == lastBarTime)
     {
      if(PositionSelect(_Symbol))
        {
         MqlDateTime dt;
         TimeToStruct(nowSrv, dt);
         ManageOpenPositions(dt, !IsTradingSession());
        }
      return;
     }
   lastBarTime = iTime(_Symbol, SignalTimeframe, 0);

   MqlDateTime dt;
   TimeToStruct(nowSrv, dt);
   bool inSession = IsTradingSession();

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
   else
     {
      ManageOpenPositions(dt, !inSession);
     }
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

   //--- NEW: EA-Level Debug Logging ---
   if(EnableEADebugLogging)
   {
        double zone_data[6];
        CopyBuffer(iCustom(_Symbol, SignalTimeframe, "AAI_Indicator_ZoneEngine.ex5"), 0, 1, 6, zone_data);
        double htf_bias_arr[1], ltf_bias_arr[1];
        CopyBuffer(iCustom(_Symbol, HTF_DEBUG, "AAI_Indicator_BiasCompass.ex5"), 0, 1, 1, htf_bias_arr);
        CopyBuffer(iCustom(_Symbol, LTF_DEBUG, "AAI_Indicator_BiasCompass.ex5"), 0, 1, 1, ltf_bias_arr);

        string debug_msg = StringFormat("EADebug | ZoneStatus: %.0f, ZoneStr: %.0f, LiqGrab: %s | HTFBias: %.1f, LTFBias: %.1f",
                                        zone_data[0], // Status
                                        zone_data[2], // Strength
                                        (zone_data[5] > 0.5) ? "true" : "false", // Liquidity
                                        htf_bias_arr[0],
                                        ltf_bias_arr[0]);
        Print(debug_msg);
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

      //--- 4. Calculate Lot Size, SL, and TP ---
      double risk_points = 0;
      double lots_to_trade = 0;

      if(signal == 1) // BUY
        {
         sl = distal_level - sl_buffer_points;
         risk_points = ask - sl;
         if(risk_points <= 0) { PrintFormat("%s Invalid risk for BUY. Aborting.", EVT_ENTRY); return; }
         tp = ask + risk_points * RiskRewardRatio;
        }
      else // SELL
        {
         sl = distal_level + sl_buffer_points;
         risk_points = sl - bid;
         if(risk_points <= 0) { PrintFormat("%s Invalid risk for SELL. Aborting.", EVT_ENTRY); return; }
         tp = bid - risk_points * RiskRewardRatio;
        }

      lots_to_trade = CalculateLotSize(confidence, risk_points / point);
      if(lots_to_trade < MinLotSize)
        {
         PrintFormat("%s Calculated lot size %.2f is below minimum %.2f. Aborting trade.", EVT_ENTRY, lots_to_trade, MinLotSize);
         return;
        }

      double risk_pips = risk_points / pipValue;
      string comment = StringFormat("AAI|C%d|R%d|Risk%.1f", confidence, (int)reasonCode, risk_pips);


      //--- 5. Execute Trade ---
      if(signal == 1) // BUY Signal
        {
         if(trade.Buy(lots_to_trade, symbolName, ask, sl, tp, comment))
            PrintFormat("%s Signal:BUY → Executed %.2f lots @%.5f | SL:%.5f TP:%.5f | Conf: %d | Reason: %s", EVT_ENTRY, lots_to_trade, trade.ResultPrice(), sl, tp, confidence, ReasonCodeToFullString(reasonCode));
         else
            PrintFormat("%s BUY failed (Err:%d %s)", EVT_ENTRY, trade.ResultRetcode(), trade.ResultComment());
        }
      else if(signal == -1) // SELL Signal
        {
         if(trade.Sell(lots_to_trade, symbolName, bid, sl, tp, comment))
            PrintFormat("%s Signal:SELL → Executed %.2f lots @%.5f | SL:%.5f TP:%.5f | Conf: %d | Reason: %s", EVT_ENTRY, lots_to_trade, trade.ResultPrice(), sl, tp, confidence, ReasonCodeToFullString(reasonCode));
         else
            PrintFormat("%s SELL failed (Err:%d %s)", EVT_ENTRY, trade.ResultRetcode(), trade.ResultComment());
        }
     }
  }

//+------------------------------------------------------------------+
//| Manage open positions                                            |
//+------------------------------------------------------------------+
void ManageOpenPositions(const MqlDateTime &loc, bool overnight)
  {
   if(!PositionSelect(_Symbol)) return;

   if(EnablePartialProfits)
     {
      HandlePartialProfits();
      if(!PositionSelect(_Symbol)) return;
     }

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
//| Handle Partial Profit Logic                                      |
//+------------------------------------------------------------------+
void HandlePartialProfits()
  {
   string comment = PositionGetString(POSITION_COMMENT);

   if(StringFind(comment, "|P1") != -1) return;

   string parts[];
   if(StringSplit(comment, '|', parts) < 4) return;

   string risk_part = parts[3];
   StringReplace(risk_part, "Risk", "");
   double initial_risk_pips = StringToDouble(risk_part);
   if(initial_risk_pips <= 0) return;

   long type = PositionGetInteger(POSITION_TYPE);
   double open_price = PositionGetDouble(POSITION_PRICE_OPEN);
   double current_profit_pips = 0;

   if(type == POSITION_TYPE_BUY)
      current_profit_pips = (SymbolInfoDouble(symbolName, SYMBOL_BID) - open_price) / pipValue;
   else
      current_profit_pips = (open_price - SymbolInfoDouble(symbolName, SYMBOL_ASK)) / pipValue;

   if(current_profit_pips >= initial_risk_pips * PartialProfitRR)
     {
      ulong ticket = PositionGetInteger(POSITION_TICKET);
      double volume = PositionGetDouble(POSITION_VOLUME);
      double close_volume = volume * (PartialClosePercent / 100.0);

      double lot_step = SymbolInfoDouble(symbolName, SYMBOL_VOLUME_STEP);
      close_volume = round(close_volume / lot_step) * lot_step;

      if(close_volume < lot_step) return;

      PrintFormat("%s Profit target of %.1fR reached. Closing %.2f lots (%.0f%%) of ticket #%d.",
                  EVT_PARTIAL, PartialProfitRR, close_volume, PartialClosePercent, ticket);

      if(trade.PositionClosePartial(ticket, close_volume))
        {
         PrintFormat("%s Partial closed. Moving SL to BE for remaining position.", EVT_PARTIAL);
         if(trade.PositionModify(ticket, open_price, PositionGetDouble(POSITION_TP)))
           {
            string new_comment = comment + "|P1";

            MqlTradeRequest request;
            MqlTradeResult  result;
            ZeroMemory(request);

            request.action   = TRADE_ACTION_MODIFY;
            request.position = ticket;
            request.sl       = open_price;
            request.tp       = PositionGetDouble(POSITION_TP);
            request.comment  = new_comment;

            if(!OrderSend(request, result))
              {
               PrintFormat("%s Failed to send position modify request. Error: %d", EVT_PARTIAL, GetLastError());
              }
            else if(result.retcode != TRADE_RETCODE_DONE && result.retcode != TRADE_RETCODE_PLACED)
              {
               PrintFormat("%s Failed to modify position comment. Server response: %s (%d)", EVT_PARTIAL, trade.ResultComment(), result.retcode);
              }
           }
        }
      else
        {
         PrintFormat("%s Failed to close partial position. Error: %d", EVT_PARTIAL, trade.ResultRetcode());
        }
     }
  }


//+------------------------------------------------------------------+
//| Trailing-stop logic                                              |
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
//| Is it within the trading session?                                |
//+------------------------------------------------------------------+
bool IsTradingSession()
  {
   datetime nowSrv = TimeCurrent();
   MqlDateTime dt;
   TimeToStruct(nowSrv, dt);
   if(dt.day_of_week < MONDAY || dt.day_of_week > FRIDAY)
      return false;

   int curMin = dt.hour*60 + dt.min;
   int startTotalMin = StartHour * 60 + StartMinute;
   int endTotalMin = EndHour * 60 + EndMinute;
   return (curMin >= startTotalMin && curMin < endTotalMin);
  }
  
//+------------------------------------------------------------------+
//| JOURNALING: Write CSV header if file doesn't exist               |
//+------------------------------------------------------------------+
void WriteJournalHeader()
{
    if(FileIsExist(JournalFileName, 0)) return;

    int handle = FileOpen(JournalFileName, FILE_WRITE|FILE_CSV|FILE_ANSI, ",");
    if(handle != INVALID_HANDLE)
    {
        FileWriteString(handle, "PositionID,Symbol,Type,Volume,EntryTime,EntryPrice,ExitTime,ExitPrice,Commission,Swap,Profit,Comment\n");
        FileClose(handle);
    }
    else
    {
        PrintFormat("%s Could not create journal file '%s'. Error: %d", EVT_JOURNAL, JournalFileName, GetLastError());
    }
}

//+------------------------------------------------------------------+
//| JOURNALING: Log a closed position's details to the CSV           |
//+------------------------------------------------------------------+
void LogClosedPosition(ulong position_id)
{
    if(!HistorySelectByPosition(position_id))
    {
        PrintFormat("%s Could not select history for position #%d.", EVT_JOURNAL, position_id);
        return;
    }

    int deals_total = HistoryDealsTotal();
    double total_profit = 0, total_commission = 0, total_swap = 0, total_volume = 0;
    datetime entry_time = 0, exit_time = 0;
    double entry_price = 0, exit_price = 0;
    string pos_symbol = "", pos_comment = "";
    int pos_type = -1;

    for(int i = 0; i < deals_total; i++)
    {
        ulong deal_ticket = HistoryDealGetTicket(i);
        total_profit += HistoryDealGetDouble(deal_ticket, DEAL_PROFIT);
        total_commission += HistoryDealGetDouble(deal_ticket, DEAL_COMMISSION);
        total_swap += HistoryDealGetDouble(deal_ticket, DEAL_SWAP);
        
        long entry_type = HistoryDealGetInteger(deal_ticket, DEAL_ENTRY);
        if(entry_type == DEAL_ENTRY_IN)
        {
            if(entry_time == 0)
            {
                entry_time = (datetime)HistoryDealGetInteger(deal_ticket, DEAL_TIME);
                entry_price = HistoryDealGetDouble(deal_ticket, DEAL_PRICE);
                pos_symbol = HistoryDealGetString(deal_ticket, DEAL_SYMBOL);
                pos_comment = HistoryDealGetString(deal_ticket, DEAL_COMMENT);
                pos_type = (int)HistoryDealGetInteger(deal_ticket, DEAL_TYPE);
                total_volume += HistoryDealGetDouble(deal_ticket, DEAL_VOLUME);
            }
        }
        else
        {
            exit_time = (datetime)HistoryDealGetInteger(deal_ticket, DEAL_TIME);
            exit_price = HistoryDealGetDouble(deal_ticket, DEAL_PRICE);
        }
    }
    
    if(pos_symbol == "") return;

    string type_str = (pos_type == ORDER_TYPE_BUY) ? "BUY" : "SELL";
    string entry_time_str = TimeToString(entry_time, TIME_DATE|TIME_SECONDS);
    string exit_time_str = TimeToString(exit_time, TIME_DATE|TIME_SECONDS);
    
    StringReplace(pos_comment, ",", ";");

    string csv_line = StringFormat("%d,%s,%s,%.2f,%s,%.5f,%s,%.5f,%.2f,%.2f,%.2f,%s",
                                   position_id,
                                   pos_symbol,
                                   type_str,
                                   total_volume,
                                   entry_time_str,
                                   entry_price,
                                   exit_time_str,
                                   exit_price,
                                   total_commission,
                                   total_swap,
                                   total_profit,
                                   pos_comment
                                   );

    int handle = FileOpen(JournalFileName, FILE_READ|FILE_WRITE|FILE_CSV|FILE_ANSI, ",");
    if(handle != INVALID_HANDLE)
    {
        FileSeek(handle, 0, SEEK_END);
        FileWriteString(handle, csv_line + "\n");
        FileClose(handle);
        PrintFormat("%s Logged closed position #%d to journal.", EVT_JOURNAL, position_id);
    }
    else
    {
        PrintFormat("%s Could not open journal file '%s' to write. Error: %d", EVT_JOURNAL, JournalFileName, GetLastError());
    }
}

//+------------------------------------------------------------------+
//| JOURNALING: Helper to track logged positions                     |
//+------------------------------------------------------------------+
bool IsPositionLogged(ulong position_id)
{
   for(int i=0; i<g_logged_positions_total; i++)
   {
      if(g_logged_positions[i] == position_id) return true;
   }
   return false;
}

void AddToLoggedList(ulong position_id)
{
   if(IsPositionLogged(position_id)) return;
   int new_size = g_logged_positions_total + 1;
   ArrayResize(g_logged_positions, new_size);
   g_logged_positions[new_size - 1] = position_id;
   g_logged_positions_total = new_size;
}


//+------------------------------------------------------------------+
//| HELPER: Converts Reason Code to String                           |
//+------------------------------------------------------------------+
string ReasonCodeToFullString(ENUM_REASON_CODE code)
{
    switch(code)
    {
        case REASON_BUY_HTF_CONTINUATION:  return "Buy signal: HTF Continuation.";
        case REASON_SELL_HTF_CONTINUATION: return "Sell signal: HTF Continuation.";
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
        case REASON_BUY_HTF_CONTINUATION:  return "BuyCont";
        case REASON_SELL_HTF_CONTINUATION: return "SellCont";
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
