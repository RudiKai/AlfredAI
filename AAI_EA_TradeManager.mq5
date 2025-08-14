//+------------------------------------------------------------------+
//|                     AAI_EA_TradeManager.mq5                      |
//|           v3.13 - SafeTest Override & Closed-Bar Read            |
//|         (Takes trade signals from AAI_Indicator_SignalBrain)     |
//|                                                                  |
//| Copyright 2025, AlfredAI Project                    |
//+------------------------------------------------------------------+
#property strict
#property version   "3.13"
#property description "Manages trades and logs closed positions to a CSV journal."
#include <Trade\Trade.mqh>

#define EVT_INIT  "[INIT]"
#define EVT_BAR   "[BAR]"
#define EVT_ENTRY "[ENTRY]"
#define EVT_EXIT  "[EXIT]"
#define EVT_TS    "[TS]"
#define EVT_PARTIAL "[PARTIAL]"
#define EVT_JOURNAL "[JOURNAL]"
#define EVT_ENTRY_CHECK "[EVT_ENTRY_CHECK]"
#define EVT_ORDER_BLOCKED "[EVT_ORDER_BLOCKED]"
#define EVT_WAIT "[EVT_WAIT]"
#define EVT_HEARTBEAT "[EVT_HEARTBEAT]"
#define EVT_TICK "[EVT_TICK]"
#define EVT_FIRST_BAR_OR_NEW "[EVT_FIRST_BAR_OR_NEW]"
#define EVT_WARN "[EVT_WARN]"

// === BEGIN Spec: Constants for buffer indexes ===
#define SB_BUF_SIGNAL   0
#define SB_BUF_CONF     1
#define SB_BUF_REASON   2
#define SB_BUF_ZONETF   3

#define ZE_BUF_PROXIMAL 6
#define ZE_BUF_DISTAL   7
// === END Spec ===


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
    REASON_BIAS_CONFLICT,
    REASON_TEST_SCENARIO // Added for SafeTest override
};
//--- EA Inputs
enum ENUM_EXECUTION_MODE { SignalsOnly, AutoExecute };
input ENUM_EXECUTION_MODE ExecutionMode = SignalsOnly;
input bool UseBiasCompass = true;
input int  IndicatorInitRetries = 50;
input int      MinConfidenceToTrade = 13;
input ulong    MagicNumber          = 1337;
input ENUM_TIMEFRAMES SignalTimeframe = PERIOD_CURRENT;
input int SB_ReadShift = 1; // 0=current, 1=closed bar (default)

// === BEGIN Spec 2: Add EA inputs to forward into SignalBrain ===
input group "SignalBrain Pass-Through Inputs"
// ==== SignalBrain pass-through (so iCustom gets the right inputs) ====
input bool SB_PassThrough_SafeTest   = true;   // set TRUE for smoke runs
input bool SB_PassThrough_UseZE      = false;  // decouple ZE during smoke
input bool SB_PassThrough_UseBC      = false;  // decouple BC during smoke
input int  SB_PassThrough_WarmupBars = 150;    // match SB default
input int  SB_PassThrough_FastMA     = 10;     // match SB default (if present)
input int  SB_PassThrough_SlowMA     = 30;     // match SB default (if present)
// If your SignalBrain declares MinZoneStrength as an input, mirror it too:
input int  SB_PassThrough_MinZoneStrength = 4; // ONLY if SB has this input

// === END Spec 2 ===

//--- Debug Inputs ---
input group "Debugging"
input bool Debug_LogSBZE     = true;   // per-bar SB/ZE reads
input int  Debug_LogEveryN   = 1;      // log cadence in bars (1 = every processed bar)


//--- Dynamic Risk & Position Sizing Inputs ---
input group "Risk Management"
input double   RiskPercent          = 1.0;
input double   MinLotSize           = 0.01;
input double   MaxLotSize           = 10.0;
input int      StopLossBufferPips   = 5;
input double   RiskRewardRatio      = 1.5;

//--- Trade Management Inputs ---
input group "Trade Management"
input bool     EnablePartialProfits = true;
input double   PartialProfitRR      = 1.0;
input double   PartialClosePercent  = 50.0;
input int      BreakEvenPips      = 40;
input int      TrailingStartPips  = 40;
input int      TrailingStopPips   = 30;
input int      OvernightTrailPips = 30;
input int      FridayCloseHour    = 22;
input int      StartHour          = 1;
input int      StartMinute        = 0;
input int      EndHour            = 23;
input int      EndMinute          = 30;
input bool     EnableLogging      = true;

//--- Journaling Inputs ---
input group "Journaling"
input bool     EnableJournaling   = true;
input string   JournalFileName    = "AlfredAI_Journal.csv";

//--- Globals
CTrade    trade;
string    symbolName;
double    point;
static ulong g_logged_positions[];
int       g_logged_positions_total = 0;

// --- Persistent Indicator Handles ---
int sb_handle = INVALID_HANDLE;
int ze_handle = INVALID_HANDLE;
int g_hBiasCompass = INVALID_HANDLE; // Kept for future compatibility
ENUM_TIMEFRAMES g_sbTF = PERIOD_CURRENT;

// --- State Management Globals ---
static datetime g_lastBarTime = 0;
static ulong    g_tickCount   = 0;
static int      g_init_ticks  = 0;
static datetime g_last_wait_log_time = 0;
bool g_warmup_complete = false;
bool g_warn_log_flags[10]; // For one-time warnings per buffer index


// --- DEBUG FLAG ---
const bool EnableEADebugLogging = true;
const ENUM_TIMEFRAMES HTF_DEBUG = PERIOD_H4;
const ENUM_TIMEFRAMES LTF_DEBUG = PERIOD_M15;

//+------------------------------------------------------------------+
//| Pip Math Helpers                                                 |
//+------------------------------------------------------------------+
double PipPoint()
{
    double point_local = SymbolInfoDouble(_Symbol, SYMBOL_POINT);
    int digits = (int)SymbolInfoInteger(_Symbol, SYMBOL_DIGITS);
    double pip = (digits % 2 != 0) ? (10 * point_local) : point_local;
    return pip;
}
double PriceFromPips(double pips) { return pips * PipPoint(); }
double PipsFromPrice(double price_diff)
{
   double pip_point = PipPoint();
   if(pip_point <= 0.0) return 0.0;
   return price_diff / pip_point;
}

//+------------------------------------------------------------------+
//| Safe 1-value reader from any indicator buffer                    |
//+------------------------------------------------------------------+
inline bool ReadOne(const int handle, const int buf, const int shift, double &out)
{
    if(handle == INVALID_HANDLE)
    {
        out = 0.0;
        return false;
    }
    double tmp[1];
    // No need for ArraySetAsSeries on a locally scoped array
    int n = CopyBuffer(handle, buf, shift, 1, tmp);
    if(n == 1)
    {
        out = tmp[0];
        return true;
    }
    out = 0.0;
    return false;
}


//+------------------------------------------------------------------+
//| Calculate Lot Size                                               |
//+------------------------------------------------------------------+
double CalculateLotSize(int confidence, double sl_distance_price)
{
   if(sl_distance_price <= 0) return 0.0;
   double account_balance = AccountInfoDouble(ACCOUNT_BALANCE);
   double risk_amount = account_balance * (RiskPercent / 100.0);
   double tick_size = SymbolInfoDouble(symbolName, SYMBOL_TRADE_TICK_SIZE);
   double tick_value_loss = SymbolInfoDouble(symbolName, SYMBOL_TRADE_TICK_VALUE_LOSS);
   if(tick_size <= 0) return 0.0;
   double loss_per_lot = (sl_distance_price / tick_size) * tick_value_loss;
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
   ArrayInitialize(g_warn_log_flags, false);

   if(EnableJournaling) WriteJournalHeader();

   // --- Create and store indicator handles with positional inputs ---
   // The order of parameters MUST match the 'input' order in AAI_Indicator_SignalBrain.mq5
   sb_handle = iCustom(_Symbol, SignalTimeframe, "AAI_Indicator_SignalBrain",
                       SB_PassThrough_MinZoneStrength,
                       SB_PassThrough_SafeTest,
                       SB_PassThrough_UseZE,
                       SB_PassThrough_UseBC,
                       SB_PassThrough_WarmupBars,
                       SB_PassThrough_FastMA,
                       SB_PassThrough_SlowMA);
   
   ze_handle = iCustom(_Symbol, SignalTimeframe, "AAI_Indicator_ZoneEngine");
   
   if(sb_handle == INVALID_HANDLE)
   {
      Print("[ERR] SB iCustom handle invalid");
      return(INIT_FAILED);
   }

   PrintFormat("[INIT] EA→SB args: SafeTest=%c UseZE=%c UseBC=%c Warmup=%d Fast=%d Slow=%d MinZoneStr=%d | sb_handle=%d",
               SB_PassThrough_SafeTest ? 'T' : 'F', 
               SB_PassThrough_UseZE ? 'T' : 'F', 
               SB_PassThrough_UseBC ? 'T' : 'F',
               SB_PassThrough_WarmupBars, 
               SB_PassThrough_FastMA, 
               SB_PassThrough_SlowMA, 
               SB_PassThrough_MinZoneStrength,
               sb_handle);
               
   PrintFormat("[INIT] EA reading SB at shift=%d (closed bar if 1)", SB_ReadShift);

   EventSetTimer(1);
   return(INIT_SUCCEEDED);
}

//+------------------------------------------------------------------+
//| Expert deinitialization                                         |
//+------------------------------------------------------------------+
void OnDeinit(const int reason)
{
   EventKillTimer();
   PrintFormat("%s Deinitialized. Reason=%d", EVT_INIT, reason);
   if(sb_handle != INVALID_HANDLE) IndicatorRelease(sb_handle);
   if(ze_handle != INVALID_HANDLE) IndicatorRelease(ze_handle);
   if(g_hBiasCompass != INVALID_HANDLE) IndicatorRelease(g_hBiasCompass);
}

//+------------------------------------------------------------------+
//| Timer function for heartbeat                                     |
//+------------------------------------------------------------------+
void OnTimer()
{
    if((g_tickCount % 100) == 0) Print(EVT_HEARTBEAT);
}

//+------------------------------------------------------------------+
//| Trade Transaction Event Handler                                  |
//+------------------------------------------------------------------+
void OnTradeTransaction(const MqlTradeTransaction &trans,
                        const MqlTradeRequest &request,
                        const MqlTradeResult &result)
{
   if(!EnableJournaling) return;
   if(trans.type == TRADE_TRANSACTION_DEAL_ADD && HistoryDealSelect(trans.deal))
   {
      if((ulong)HistoryDealGetInteger(trans.deal, DEAL_MAGIC) == MagicNumber && HistoryDealGetInteger(trans.deal, DEAL_ENTRY) == DEAL_ENTRY_OUT)
      {
         ulong pos_id = HistoryDealGetInteger(trans.deal, DEAL_POSITION_ID);
         if(!PositionSelectByTicket(pos_id) && !IsPositionLogged(pos_id))
         {
            LogClosedPosition(pos_id);
            AddToLoggedList(pos_id);
         }
      }
   }
}

//+------------------------------------------------------------------+
//| OnTick: Event-driven logic                                      |
//+------------------------------------------------------------------+
void OnTick()
{
   g_tickCount++;

   if(PositionSelect(_Symbol))
   {
      MqlDateTime dt;
      TimeToStruct(TimeCurrent(), dt);
      ManageOpenPositions(dt, !IsTradingSession());
   }
   
   int sb_bars = BarsCalculated(sb_handle);
   if(sb_bars < 2)
   {
      if(TimeCurrent() - g_last_wait_log_time > 60)
      {
         PrintFormat("%s BarsCalculated SB=%d — deferring", EVT_WAIT, sb_bars);
         g_last_wait_log_time = TimeCurrent();
      }
      return;
   }

   datetime t = iTime(_Symbol, SignalTimeframe, 0);
   if(t == 0 || t == g_lastBarTime) return;
   
   if(g_lastBarTime == 0) PrintFormat("%s %s", EVT_FIRST_BAR_OR_NEW, TimeToString(t, TIME_DATE|TIME_MINUTES));
   g_lastBarTime = t;

   bool inSession = IsTradingSession();
   if(EnableLogging)
      PrintFormat("[BAR] srv=%s — InSession=%s", TimeToString(TimeCurrent()), inSession  ? "YES" : "NO");
   
   if(!PositionSelect(_Symbol))
   {
      CheckForNewTrades(inSession);
   }
}


//+------------------------------------------------------------------+
//| Check & execute new entries                                      |
//+------------------------------------------------------------------+
void CheckForNewTrades(bool inSession)
{
   if(!inSession) return;

   // --- Read SignalBrain and ZoneEngine buffers safely ---
   const int readShift = MathMax(0, SB_ReadShift);
   double sbSig=0, sbConf=0, sbReason=0, sbZoneTF=0;
   
   bool okSig = ReadOne(sb_handle, SB_BUF_SIGNAL, readShift, sbSig);
   bool okConf = ReadOne(sb_handle, SB_BUF_CONF, readShift, sbConf);
   bool okReason = ReadOne(sb_handle, SB_BUF_REASON, readShift, sbReason);
   bool okZoneTF = ReadOne(sb_handle, SB_BUF_ZONETF, readShift, sbZoneTF);

   if(!okSig || !okConf || !okReason || !okZoneTF)
   {
      if(!okSig) PrintFormat("%s Read failed: SB buf %d", EVT_WARN, SB_BUF_SIGNAL);
      if(!okConf) PrintFormat("%s Read failed: SB buf %d", EVT_WARN, SB_BUF_CONF);
      if(!okReason) PrintFormat("%s Read failed: SB buf %d", EVT_WARN, SB_BUF_REASON);
      if(!okZoneTF) PrintFormat("%s Read failed: SB buf %d", EVT_WARN, SB_BUF_ZONETF);
      return;
   }
   
   // --- SafeTest Override ---
   if(SB_PassThrough_SafeTest)
   {
      sbConf = 10.0;
      sbReason = (double)REASON_TEST_SCENARIO;
   }

   // --- Debug Logging ---
   PrintFormat("[DBG_SB] shift=%d sig=%.1f conf=%.1f reason=%g ztf=%g", 
               readShift, sbSig, sbConf, sbReason, sbZoneTF);
   
   double zeProx=0, zeDist=0;
   ReadOne(ze_handle, ZE_BUF_PROXIMAL, 1, zeProx);
   ReadOne(ze_handle, ZE_BUF_DISTAL,   1, zeDist);
   
   // --- Entry Conditions ---
   int signal = (int)sbSig;
   if(signal == 0) return;

   int confidence = (int)sbConf;
   if(MinConfidenceToTrade > 0 && confidence < MinConfidenceToTrade) return;

   ENUM_REASON_CODE reasonCode = (ENUM_REASON_CODE)sbReason;
      
   if(zeDist == 0.0)
   {
      if(!g_warn_log_flags[ZE_BUF_DISTAL]) 
      {
         PrintFormat("%s Read failed or invalid: ZE buf %d", EVT_WARN, ZE_BUF_DISTAL); 
         g_warn_log_flags[ZE_BUF_DISTAL] = true; 
      }
      return;
   }

   double ask = SymbolInfoDouble(symbolName, SYMBOL_ASK);
   double bid = SymbolInfoDouble(symbolName, SYMBOL_BID);
   double sl = 0, tp = 0;
   double sl_buffer_points = PriceFromPips(StopLossBufferPips);
   double risk_points = 0;
   double lots_to_trade = 0;

   if(signal == 1) { sl = zeDist - sl_buffer_points; risk_points = ask - sl; if(risk_points <= 0) return; tp = ask + risk_points * RiskRewardRatio; }
   else { sl = zeDist + sl_buffer_points; risk_points = sl - bid; if(risk_points <= 0) return; tp = bid - risk_points * RiskRewardRatio; }

   lots_to_trade = CalculateLotSize(confidence, risk_points);
   if(lots_to_trade < MinLotSize) return;

   double risk_pips = PipsFromPrice(risk_points);
   string comment = StringFormat("AAI|C%d|R%d|Risk%.1f", confidence, (int)reasonCode, risk_pips);
   
   string signal_str = (signal == 1) ? "BUY" : "SELL";
   bool is_allowed = (ExecutionMode == AutoExecute);
   PrintFormat("%s mode=%s signal=%s conf=%d/20 reason=%s allowed=%s",
               EVT_ENTRY_CHECK, EnumToString(ExecutionMode), signal_str, confidence, ReasonCodeToShortString(reasonCode), is_allowed ? "YES" : "NO");

   if(is_allowed)
   {
      if(signal == 1)
      {
         if(!trade.Buy(lots_to_trade, symbolName, ask, sl, tp, comment)) PrintFormat("%s BUY failed (Err:%d %s)", EVT_ENTRY, trade.ResultRetcode(), trade.ResultComment());
         else PrintFormat("%s Signal:BUY → Executed %.2f lots @%.5f | SL:%.5f TP:%.5f", EVT_ENTRY, lots_to_trade, trade.ResultPrice(), sl, tp);
      }
      else if(signal == -1)
      {
         if(!trade.Sell(lots_to_trade, symbolName, bid, sl, tp, comment)) PrintFormat("%s SELL failed (Err:%d %s)", EVT_ENTRY, trade.ResultRetcode(), trade.ResultComment());
         else PrintFormat("%s Signal:SELL → Executed %.2f lots @%.5f | SL:%.5f TP:%.5f", EVT_ENTRY, lots_to_trade, trade.ResultPrice(), sl, tp);
      }
   }
   else
   {
      Print("%s mode=SignalsOnly", EVT_ORDER_BLOCKED);
   }
}

//+------------------------------------------------------------------+
//| Manage open positions (logic unchanged)                          |
//+------------------------------------------------------------------+
void ManageOpenPositions(const MqlDateTime &loc, bool overnight)
{
   if(!PositionSelect(_Symbol)) return;
   if(EnablePartialProfits) { HandlePartialProfits(); if(!PositionSelect(_Symbol)) return; }
   double ask = SymbolInfoDouble(symbolName, SYMBOL_ASK);
   double bid = SymbolInfoDouble(symbolName, SYMBOL_BID);
   ulong ticket = PositionGetInteger(POSITION_TICKET);
   long type = PositionGetInteger(POSITION_TYPE);
   double openP = PositionGetDouble(POSITION_PRICE_OPEN);
   double currSL = PositionGetDouble(POSITION_SL);
   if(loc.day_of_week==FRIDAY && loc.hour>=FridayCloseHour) { trade.PositionClose(ticket); return; }
   double beDist = PriceFromPips(BreakEvenPips);
   if(type==POSITION_TYPE_BUY && bid-openP>=beDist && (currSL < openP || currSL == 0))
      if(trade.PositionModify(ticket, openP, PositionGetDouble(POSITION_TP))) currSL=openP;
   else if(type==POSITION_TYPE_SELL && openP-ask>=beDist && (currSL > openP || currSL == 0))
      if(trade.PositionModify(ticket, openP, PositionGetDouble(POSITION_TP))) currSL=openP;
   HandleTrailingStop(ticket, type, openP, currSL, (type==POSITION_TYPE_BUY ? bid : ask), overnight);
}

//+------------------------------------------------------------------+
//| Handle Partial Profits (logic unchanged)                         |
//+------------------------------------------------------------------+
void HandlePartialProfits()
{
   string comment = PositionGetString(POSITION_COMMENT);
   if(StringFind(comment, "|P1") != -1) return;
   string parts[];
   if(StringSplit(comment, '|', parts) < 4) return;
   StringReplace(parts[3], "Risk", "");
   double initial_risk_pips = StringToDouble(parts[3]);
   if(initial_risk_pips <= 0) return;
   long type = PositionGetInteger(POSITION_TYPE);
   double open_price = PositionGetDouble(POSITION_PRICE_OPEN);
   double current_profit_pips = (type == POSITION_TYPE_BUY) ? PipsFromPrice(SymbolInfoDouble(symbolName, SYMBOL_BID) - open_price) : PipsFromPrice(open_price - SymbolInfoDouble(symbolName, SYMBOL_ASK));
   if(current_profit_pips >= initial_risk_pips * PartialProfitRR)
   {
      ulong ticket = PositionGetInteger(POSITION_TICKET);
      double volume = PositionGetDouble(POSITION_VOLUME);
      double close_volume = volume * (PartialClosePercent / 100.0);
      double lot_step = SymbolInfoDouble(symbolName, SYMBOL_VOLUME_STEP);
      close_volume = round(close_volume / lot_step) * lot_step;
      if(close_volume < lot_step) return;
      if(trade.PositionClosePartial(ticket, close_volume))
      {
         if(trade.PositionModify(ticket, open_price, PositionGetDouble(POSITION_TP)))
         {
            MqlTradeRequest req; MqlTradeResult res; ZeroMemory(req);
            req.action = TRADE_ACTION_MODIFY; req.position = ticket;
            req.sl = open_price; req.tp = PositionGetDouble(POSITION_TP);
            req.comment = comment + "|P1";
            if(!OrderSend(req, res)) PrintFormat("%s Failed to send position modify request. Error: %d", EVT_PARTIAL, GetLastError());
         }
      }
   }
}

//+------------------------------------------------------------------+
//| Trailing Stop (logic unchanged)                                  |
//+------------------------------------------------------------------+
void HandleTrailingStop(ulong ticket,long type,double openP,double currSL,double currPrice,bool overnight)
{
   if(currSL<=0.0) return;
   double trailDist = PriceFromPips(overnight ? OvernightTrailPips : TrailingStopPips);
   double startDist = PriceFromPips(TrailingStartPips);
   double newSL = currSL;
   if(! (overnight || (type==POSITION_TYPE_BUY && currPrice-openP>=startDist) || (type==POSITION_TYPE_SELL && openP-currPrice>=startDist)) ) return;
   if(type==POSITION_TYPE_BUY && currPrice-trailDist>currSL) newSL = currPrice-trailDist;
   else if(type==POSITION_TYPE_SELL && currPrice+trailDist<currSL) newSL = currPrice+trailDist;
   if(newSL!=currSL) trade.PositionModify(ticket, newSL, PositionGetDouble(POSITION_TP));
}

//+------------------------------------------------------------------+
//| Session Check (logic unchanged)                                  |
//+------------------------------------------------------------------+
bool IsTradingSession()
{
   MqlDateTime dt; TimeToStruct(TimeCurrent(), dt);
   if(dt.day_of_week < MONDAY || dt.day_of_week > FRIDAY) return false;
   int curMin = dt.hour*60 + dt.min;
   return (curMin >= (StartHour*60+StartMinute) && curMin < (EndHour*60+EndMinute));
}

//+------------------------------------------------------------------+
//| Journaling Functions (logic unchanged)                           |
//+------------------------------------------------------------------+
void WriteJournalHeader()
{
   if(FileIsExist(JournalFileName, 0)) return;
   int handle = FileOpen(JournalFileName, FILE_WRITE|FILE_CSV|FILE_ANSI, ",");
   if(handle != INVALID_HANDLE) { FileWriteString(handle, "PositionID,Symbol,Type,Volume,EntryTime,EntryPrice,ExitTime,ExitPrice,Commission,Swap,Profit,Comment\n"); FileClose(handle); }
}
void LogClosedPosition(ulong position_id)
{
   if(!HistorySelectByPosition(position_id)) return;
   double total_profit=0, total_comm=0, total_swap=0, total_vol=0;
   datetime entry_t=0, exit_t=0;
   double entry_p=0, exit_p=0;
   string pos_sym="", pos_comm="";
   int pos_type=-1;
   for(int i=0; i<HistoryDealsTotal(); i++)
   {
      ulong deal = HistoryDealGetTicket(i);
      total_profit += HistoryDealGetDouble(deal, DEAL_PROFIT);
      total_comm += HistoryDealGetDouble(deal, DEAL_COMMISSION);
      total_swap += HistoryDealGetDouble(deal, DEAL_SWAP);
      if(HistoryDealGetInteger(deal, DEAL_ENTRY) == DEAL_ENTRY_IN)
      {
         if(entry_t==0)
         {
            entry_t = (datetime)HistoryDealGetInteger(deal, DEAL_TIME); entry_p = HistoryDealGetDouble(deal, DEAL_PRICE);
            pos_sym = HistoryDealGetString(deal, DEAL_SYMBOL); pos_comm = HistoryDealGetString(deal, DEAL_COMMENT);
            pos_type = (int)HistoryDealGetInteger(deal, DEAL_TYPE); total_vol += HistoryDealGetDouble(deal, DEAL_VOLUME);
         }
      }
      else { exit_t = (datetime)HistoryDealGetInteger(deal, DEAL_TIME); exit_p = HistoryDealGetDouble(deal, DEAL_PRICE); }
   }
   if(pos_sym=="") return;
   StringReplace(pos_comm, ",", ";");
   string csv_line = StringFormat("%d,%s,%s,%.2f,%s,%.5f,%s,%.5f,%.2f,%.2f,%.2f,%s", position_id, pos_sym, (pos_type==ORDER_TYPE_BUY?"BUY":"SELL"),
      total_vol, TimeToString(entry_t), entry_p, TimeToString(exit_t), exit_p, total_comm, total_swap, total_profit, pos_comm);
   int handle = FileOpen(JournalFileName, FILE_READ|FILE_WRITE|FILE_CSV|FILE_ANSI, ",");
   if(handle!=INVALID_HANDLE) { FileSeek(handle,0,SEEK_END); FileWriteString(handle,csv_line+"\n"); FileClose(handle); }
}
bool IsPositionLogged(ulong position_id)
{
   for(int i=0; i<g_logged_positions_total; i++) if(g_logged_positions[i] == position_id) return true;
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
      case REASON_TEST_SCENARIO:       return "SafeTest";
      default:                           return "None";
   }
}
//+------------------------------------------------------------------+
