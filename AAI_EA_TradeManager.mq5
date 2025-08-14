//+------------------------------------------------------------------+
//|                     AAI_EA_TradeManager.mq5                      |
//|         v3.20 - Unified Price Helpers & Compile Fixes            |
//|         (Takes trade signals from AAI_Indicator_SignalBrain)     |
//|                                                                  |
//| Copyright 2025, AlfredAI Project                    |
//+------------------------------------------------------------------+
#property strict
#property version   "3.20"
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
#define DBG_GATES "[DBG_GATES]"
#define DBG_STOPS "[DBG_STOPS]"
#define EVT_SUPPRESS "[EVT_SUPPRESS]"

// === BEGIN Spec: Constants for buffer indexes ===
#define SB_BUF_SIGNAL   0
#define SB_BUF_CONF     1
#define SB_BUF_REASON   2
#define SB_BUF_ZONETF   3
#define BC_BUF_HTF_BIAS 0 // BiasCompass HTF Bias buffer
#define ZE_BUF_STATUS   0 // ZoneEngine ZoneStatus buffer

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
enum ENUM_ENTRY_MODE { FirstBarOrEdge, EdgeOnly };
input ENUM_EXECUTION_MODE ExecutionMode = AutoExecute;
input ENUM_ENTRY_MODE     EntryMode     = FirstBarOrEdge;
input int  IndicatorInitRetries = 50;
input int      MinConfidenceToTrade = 1;
input ulong    MagicNumber          = 1337;
input ENUM_TIMEFRAMES SignalTimeframe = PERIOD_CURRENT;
input int SB_ReadShift = 1;

// === BEGIN Spec 2: Add EA inputs to forward into SignalBrain ===
input group "SignalBrain Pass-Through Inputs"
input bool SB_PassThrough_SafeTest   = false;
input bool SB_PassThrough_UseZE      = false;
input bool SB_PassThrough_UseBC      = false;
input int  SB_PassThrough_WarmupBars = 150;
input int  SB_PassThrough_FastMA     = 10;
input int  SB_PassThrough_SlowMA     = 30;
input int  SB_PassThrough_MinZoneStrength = 4;
input bool SB_PassThrough_EnableDebug = true; 
// === END Spec 2 ===

//--- Dynamic Risk & Position Sizing Inputs ---
input group "Risk Management"
input double   RiskPercent          = 1.0;
input double   MinLotSize           = 0.01;
input double   MaxLotSize           = 10.0;
input int      StopLossBufferPips   = 5;
input double   RiskRewardRatio      = 1.5;

//--- Trade Management Inputs ---
input group "Trade Management"
input int      MaxSpreadPoints      = 20;
input int      MaxSlippagePoints    = 10;
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
int bc_handle = INVALID_HANDLE;
int g_hATR = INVALID_HANDLE;
ENUM_TIMEFRAMES g_sbTF = PERIOD_CURRENT;

// --- State Management Globals ---
static datetime g_lastBarTime = 0;
static datetime g_last_suppress_log_time = 0;
static ulong    g_tickCount   = 0;
static int      g_init_ticks  = 0;
static datetime g_last_wait_log_time = 0;
bool g_warmup_complete = false;
bool g_bootstrap_done = false;
bool g_warn_log_flags[10];

//+------------------------------------------------------------------+
//| Pip Math Helpers (FIXED)                                         |
//+------------------------------------------------------------------+
inline double PipSize()
{
   const int digits = (int)SymbolInfoInteger(_Symbol, SYMBOL_DIGITS);
   return (digits == 3 || digits == 5) ? 10 * _Point : _Point;
}

inline double PriceFromPips(double pips)
{
   return pips * PipSize();
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

   sb_handle = iCustom(_Symbol, SignalTimeframe, "AAI_Indicator_SignalBrain",
                       SB_PassThrough_SafeTest,
                       SB_PassThrough_UseZE,
                       SB_PassThrough_UseBC,
                       SB_PassThrough_WarmupBars,
                       SB_PassThrough_FastMA,
                       SB_PassThrough_SlowMA,
                       SB_PassThrough_MinZoneStrength,
                       SB_PassThrough_EnableDebug
                       );
   
   if(SB_PassThrough_UseZE) ze_handle = iCustom(_Symbol, SignalTimeframe, "AAI_Indicator_ZoneEngine");
   if(SB_PassThrough_UseBC) bc_handle = iCustom(_Symbol, SignalTimeframe, "AAI_Indicator_BiasCompass");
   
   if(sb_handle == INVALID_HANDLE)
   {
      Print("[ERR] SB iCustom handle invalid");
      return(INIT_FAILED);
   }
   
   PrintFormat("%s EntryMode=%s", EVT_INIT, EnumToString(EntryMode));
   PrintFormat("%s EA→SB args: SafeTest=%c UseZE=%c UseBC=%c Warmup=%d Fast=%d Slow=%d MinZoneStr=%d Debug=%c | sb_handle=%d",
               EVT_INIT,
               SB_PassThrough_SafeTest ? 'T' : 'F', 
               SB_PassThrough_UseZE ? 'T' : 'F', 
               SB_PassThrough_UseBC ? 'T' : 'F',
               SB_PassThrough_WarmupBars, 
               SB_PassThrough_FastMA, 
               SB_PassThrough_SlowMA, 
               SB_PassThrough_MinZoneStrength,
               SB_PassThrough_EnableDebug ? 'T' : 'F',
               sb_handle);
               
   PrintFormat("[DBG_SHIFT] EA reading SB at shift=%d (closed bar if 1)", SB_ReadShift);

   g_hATR = iATR(_Symbol, _Period, 14);
   if(g_hATR == INVALID_HANDLE)
   {
       Print("[ERR] Failed to create ATR indicator handle");
       return(INIT_FAILED);
   }

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
   if(bc_handle != INVALID_HANDLE) IndicatorRelease(bc_handle);
   if(g_hATR != INVALID_HANDLE) IndicatorRelease(g_hATR);
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
   
   if(!g_warmup_complete)
   {
       if(Bars(_Symbol, SignalTimeframe) > SB_PassThrough_WarmupBars)
       {
           g_warmup_complete = true;
           PrintFormat("[INIT] Warmup complete (%d bars). Live trading enabled.", SB_PassThrough_WarmupBars);
       }
       else
       {
           return;
       }
   }
   
   datetime bar_time = iTime(_Symbol, _Period, SB_ReadShift);
   if(bar_time == 0 || bar_time == g_lastBarTime) return;
   
   g_lastBarTime = bar_time;
   
   CheckForNewTrades();
}


//+------------------------------------------------------------------+
//| Check & execute new entries                                      |
//+------------------------------------------------------------------+
void CheckForNewTrades()
{
   const int readShift = MathMax(1, SB_ReadShift);
   double sbSig_curr=0, sbConf=0, sbReason=0, sbZoneTF=0;
   double sbSig_prev=0;
   
   ReadOne(sb_handle, SB_BUF_SIGNAL, readShift, sbSig_curr);
   if(!ReadOne(sb_handle, SB_BUF_SIGNAL, readShift + 1, sbSig_prev)) sbSig_prev = sbSig_curr;
   ReadOne(sb_handle, SB_BUF_CONF,   readShift, sbConf);
   ReadOne(sb_handle, SB_BUF_REASON, readShift, sbReason);
   ReadOne(sb_handle, SB_BUF_ZONETF, readShift, sbZoneTF);

   bool flat = !PositionSelect(_Symbol);
   bool in_sess = IsTradingSession();
   bool conf_ok = ((int)sbConf >= MinConfidenceToTrade);
   long current_spread = SymbolInfoInteger(_Symbol, SYMBOL_SPREAD);
   bool spread_ok = (MaxSpreadPoints == 0 || current_spread <= MaxSpreadPoints);
   bool is_edge = ((int)sbSig_curr != (int)sbSig_prev);

   bool bc_ok = !SB_PassThrough_UseBC;
   if(SB_PassThrough_UseBC)
   {
      double htf_bias = 0;
      if(ReadOne(bc_handle, BC_BUF_HTF_BIAS, readShift, htf_bias))
         bc_ok = ((sbSig_curr > 0 && htf_bias > 0) || (sbSig_curr < 0 && htf_bias < 0));
   }

   bool ze_ok = !SB_PassThrough_UseZE;
   if(SB_PassThrough_UseZE)
   {
      double zone_status = 0;
      if(ReadOne(ze_handle, ZE_BUF_STATUS, readShift, zone_status))
         ze_ok = ((sbSig_curr > 0 && zone_status > 0) || (sbSig_curr < 0 && zone_status < 0));
   }

   PrintFormat("%s t=%s sig_prev=%d sig_curr=%d conf=%d min=%d flat=%s in_sess=%s spread_ok=%s bc_ok=%s ze_ok=%s bootstrap_done=%s entry_mode=%s",
               DBG_GATES, TimeToString(g_lastBarTime), (int)sbSig_prev, (int)sbSig_curr, (int)sbConf, MinConfidenceToTrade,
               flat ? "T" : "F", in_sess ? "T" : "F", spread_ok ? "T" : "F", bc_ok ? "T" : "F", ze_ok ? "T" : "F",
               g_bootstrap_done ? "T" : "F", EnumToString(EntryMode));

   bool attempt_trade = false;
   bool is_bootstrap_attempt = false;

   if(EntryMode == FirstBarOrEdge && !g_bootstrap_done)
   {
       if(flat && in_sess && conf_ok && spread_ok && bc_ok && ze_ok && (int)sbSig_curr != 0)
       {
           attempt_trade = true;
           is_bootstrap_attempt = true;
       }
   }
   else if (is_edge && flat && in_sess && conf_ok && spread_ok && bc_ok && ze_ok && (int)sbSig_curr != 0)
   {
       attempt_trade = true;
   }
   
   if(attempt_trade)
   {
      bool success = TryOpenPosition((int)sbSig_curr, (int)sbConf, is_bootstrap_attempt);
      if(is_bootstrap_attempt && success)
      {
         g_bootstrap_done = true;
      }
   }
}

//+------------------------------------------------------------------+
//| Attempts to open a trade and returns true on success             |
//+------------------------------------------------------------------+
bool TryOpenPosition(int signal, int confidence, bool is_bootstrap)
{
   MqlTick t;
   if(!SymbolInfoTick(_Symbol, t) || t.time_msc == 0)
   {
      if(g_lastBarTime != g_last_suppress_log_time)
      {
         PrintFormat("%s bootstrap=%s reason=no_tick", EVT_SUPPRESS, is_bootstrap ? "YES" : "NO");
         g_last_suppress_log_time = g_lastBarTime;
      }
      return false;
   }

   const int    digs = (int)SymbolInfoInteger(_Symbol, SYMBOL_DIGITS);
   const double pip_size = PipSize();
   const double step = MathMax(SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_SIZE), point);
   const double min_stop_dist = (double)SymbolInfoInteger(_Symbol, SYMBOL_TRADE_STOPS_LEVEL) * point;
   const double buf_price = PriceFromPips(StopLossBufferPips);
   const double sl_dist = MathMax(min_stop_dist + step, buf_price);

   double entry = (signal > 0) ? t.ask : t.bid;
   entry = NormalizeDouble(entry, digs);
   
   double sl = 0, tp = 0;
   if(signal > 0)
   {
      sl = NormalizeDouble(entry - sl_dist, digs);
      tp = NormalizeDouble(entry + RiskRewardRatio * (entry - sl), digs);
   }
   else if(signal < 0)
   {
      sl = NormalizeDouble(entry + sl_dist, digs);
      tp = NormalizeDouble(entry - RiskRewardRatio * (sl - entry), digs);
   }

   if(g_lastBarTime != g_last_suppress_log_time)
   {
       PrintFormat("%s side=%s bid=%.5f ask=%.5f entry=%.5f pip=%.5f minStop=%.5f buf=%gp(%.5f) sl=%.5f tp=%.5f",
                   DBG_STOPS, signal > 0 ? "BUY" : "SELL", t.bid, t.ask, entry, pip_size, min_stop_dist,
                   (double)StopLossBufferPips, buf_price, sl, tp);
   }

   bool ok_side = (signal > 0) ? (sl < entry && entry < tp) : (tp < entry && entry < sl);
   bool ok_dist = (MathAbs(entry - sl) >= min_stop_dist) && (MathAbs(tp - entry) >= min_stop_dist);

   if(!ok_side || !ok_dist)
   {
      if(g_lastBarTime != g_last_suppress_log_time)
      {
         PrintFormat("%s bootstrap=%s reason=stops_invalid side=%s entry=%.5f sl=%.5f tp=%.5f minStop=%.5f buf=%.5f",
                     EVT_SUPPRESS, is_bootstrap ? "YES" : "NO", signal > 0 ? "BUY" : "SELL", entry, sl, tp, min_stop_dist, buf_price);
         g_last_suppress_log_time = g_lastBarTime;
      }
      return false;
   }

   double lots_to_trade = CalculateLotSize(confidence, MathAbs(entry - sl));
   if(lots_to_trade < MinLotSize) return false;

   string signal_str = (signal == 1) ? "BUY" : "SELL";
   string comment = StringFormat("AAI|C%d|Risk%.1f", confidence, MathAbs(entry - sl) / pip_size);
   
   PrintFormat("%s bootstrap=%s mode=%s signal=%s conf=%d/20 allowed=YES",
               EVT_ENTRY_CHECK, is_bootstrap ? "YES" : "NO", EnumToString(ExecutionMode), signal_str, confidence);

   if(ExecutionMode == AutoExecute)
   {
      trade.SetDeviationInPoints(MaxSlippagePoints);
      bool order_sent = (signal > 0) ? trade.Buy(lots_to_trade, symbolName, entry, sl, tp, comment) : trade.Sell(lots_to_trade, symbolName, entry, sl, tp, comment);
      
      if(order_sent && (trade.ResultRetcode() == TRADE_RETCODE_DONE || trade.ResultRetcode() == TRADE_RETCODE_DONE_PARTIAL))
      {
         PrintFormat("%s Signal:%s → Executed %.2f lots @%.5f | SL:%.5f TP:%.5f", EVT_ENTRY, signal_str, trade.ResultVolume(), trade.ResultPrice(), sl, tp);
         return true;
      }
      else
      {
         if(g_lastBarTime != g_last_suppress_log_time)
         {
            PrintFormat("%s bootstrap=%s reason=trade_send_failed retcode=%d", EVT_SUPPRESS, is_bootstrap ? "YES" : "NO", trade.ResultRetcode());
            g_last_suppress_log_time = g_lastBarTime;
         }
         return false;
      }
   }
   
   return false;
}


//+------------------------------------------------------------------+
//| Manage open positions                                            |
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
//| Handle Partial Profits                                           |
//+------------------------------------------------------------------+
void HandlePartialProfits()
{
   string comment = PositionGetString(POSITION_COMMENT);
   if(StringFind(comment, "|P1") != -1) return;
   string parts[];
   if(StringSplit(comment, '|', parts) < 3) return;
   StringReplace(parts[2], "Risk", "");
   double initial_risk_pips = StringToDouble(parts[2]);
   if(initial_risk_pips <= 0) return;
   long type = PositionGetInteger(POSITION_TYPE);
   double open_price = PositionGetDouble(POSITION_PRICE_OPEN);
   double current_profit_pips = (type == POSITION_TYPE_BUY) ?
      (SymbolInfoDouble(symbolName, SYMBOL_BID) - open_price) / PipSize() : (open_price - SymbolInfoDouble(symbolName, SYMBOL_ASK)) / PipSize();
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
            MqlTradeRequest req;
            MqlTradeResult res; ZeroMemory(req);
            req.action = TRADE_ACTION_MODIFY; req.position = ticket;
            req.sl = open_price; req.tp = PositionGetDouble(POSITION_TP);
            req.comment = comment + "|P1";
            if(!OrderSend(req, res)) PrintFormat("%s Failed to send position modify request. Error: %d", EVT_PARTIAL, GetLastError());
         }
      }
   }
}

//+------------------------------------------------------------------+
//| Trailing Stop                                                    |
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
//| Session Check                                                    |
//+------------------------------------------------------------------+
bool IsTradingSession()
{
   MqlDateTime dt; TimeToStruct(TimeCurrent(), dt);
   if(dt.day_of_week < MONDAY || dt.day_of_week > FRIDAY) return false;
   int curMin = dt.hour*60 + dt.min;
   return (curMin >= (StartHour*60+StartMinute) && curMin < (EndHour*60+EndMinute));
}

//+------------------------------------------------------------------+
//| Journaling Functions                                             |
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
            entry_t = (datetime)HistoryDealGetInteger(deal, DEAL_TIME);
            entry_p = HistoryDealGetDouble(deal, DEAL_PRICE);
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
