//+------------------------------------------------------------------+
//|                     AAI_EA_TradeManager.mq5                      |
//|                 v3.6 - Hardened Reads & Inputs                   |
//|         (Takes trade signals from AAI_Indicator_SignalBrain)     |
//|                                                                  |
//| Copyright 2025, AlfredAI Project                    |
//+------------------------------------------------------------------+
#property strict
#property version   "3.6"
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

// === BEGIN Spec 1: Constants for buffer indexes ===
// ==== SignalBrain buffer contract ====
#define SB_BUF_SIGNAL   0   // -1/0/1
#define SB_BUF_CONF     1   // 0..20
#define SB_BUF_REASON   2   // enum (as double)
#define SB_BUF_ZONETF   3   // seconds

// ZoneEngine Buffers
#define ZE_BUF_STATUS    0
#define ZE_BUF_STRENGTH  2
#define ZE_BUF_LIQUIDITY 5
#define ZE_BUF_PROXIMAL  6
#define ZE_BUF_DISTAL    7

// BiasCompass Buffers
#define BC_BUF_BIAS 0
#define BC_BUF_CONF 1
// === END Spec 1 ===


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
enum ENUM_EXECUTION_MODE { SignalsOnly, AutoExecute };
input ENUM_EXECUTION_MODE ExecutionMode = SignalsOnly;
input bool UseBiasCompass = true;
input int  IndicatorInitRetries = 50;
input int      MinConfidenceToTrade = 13;
input ulong    MagicNumber          = 1337;
input ENUM_TIMEFRAMES SignalTimeframe = PERIOD_CURRENT;

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
int g_hSignalBrain = INVALID_HANDLE;
int g_hZoneEngine  = INVALID_HANDLE;
int g_hBiasCompass = INVALID_HANDLE;
ENUM_TIMEFRAMES g_sbTF = PERIOD_CURRENT;

// --- State Management Globals ---
static datetime g_lastBarTime = 0;
static ulong    g_tickCount   = 0;
static int      g_init_ticks  = 0;
bool g_SB_Available = false, g_ZE_Available = false, g_BC_Available = false;
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

// === BEGIN Spec 5: Safe CopyBuffer helper ===
bool ReadOne(const int handle, const int buf, const int shift, double &outVal)
{
    if(handle == INVALID_HANDLE)
    {
        outVal = 0.0;
        return false;
    }
    double tmp[1];
    // No need for ArraySetAsSeries on a locally scoped array
    int n = CopyBuffer(handle, buf, shift, 1, tmp);
    if(n == 1)
    {
        outVal = tmp[0];
        return true;
    }
    outVal = 0.0;
    return false;
}
// === END Spec 5 ===

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

   // === BEGIN Spec 3: Create handles with explicit params ===
   g_sbTF = SignalTimeframe;
   
   // The order of parameters MUST match the 'input' order in AAI_Indicator_SignalBrain.mq5
   g_hSignalBrain = iCustom(_Symbol, g_sbTF, "AAI_Indicator_SignalBrain",
                            SB_PassThrough_MinZoneStrength,
                            SB_PassThrough_SafeTest,
                            SB_PassThrough_UseZE,
                            SB_PassThrough_UseBC);

   g_hZoneEngine  = iCustom(_Symbol, g_sbTF, "AAI_Indicator_ZoneEngine");
   
   g_hBiasCompass = (UseBiasCompass ? iCustom(_Symbol, g_sbTF, "AAI_Indicator_BiasCompass") : INVALID_HANDLE);

   PrintFormat("%s SB_handle=%d ZE_handle=%d BC_handle=%d TF=%s", EVT_INIT, g_hSignalBrain, g_hZoneEngine, g_hBiasCompass, EnumToString(g_sbTF));
   // === END Spec 3 ===

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
   if(g_hSignalBrain != INVALID_HANDLE) IndicatorRelease(g_hSignalBrain);
   if(g_hZoneEngine != INVALID_HANDLE) IndicatorRelease(g_hZoneEngine);
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
   if((g_tickCount % 500) == 0) Print(EVT_TICK);

   if(PositionSelect(_Symbol))
   {
      MqlDateTime dt;
      TimeToStruct(TimeCurrent(), dt);
      ManageOpenPositions(dt, !IsTradingSession());
   }

   // === BEGIN Spec 4: BarsCalculated waiter (non-blocking, fail-soft) ===
   if(!g_warmup_complete)
   {
       int sb = (g_hSignalBrain == INVALID_HANDLE ? -1 : BarsCalculated(g_hSignalBrain));
       int ze = (g_hZoneEngine  == INVALID_HANDLE ? -1 : BarsCalculated(g_hZoneEngine));
       int bc = (g_hBiasCompass == INVALID_HANDLE ? -1 : BarsCalculated(g_hBiasCompass));

       bool sb_ready = (g_hSignalBrain == INVALID_HANDLE) || (sb >= 1);
       bool ze_ready = (g_hZoneEngine  == INVALID_HANDLE) || (ze >= 1);
       bool bc_ready = (!UseBiasCompass) || (g_hBiasCompass == INVALID_HANDLE) || (bc >= 1);

       if(!(sb_ready && ze_ready && bc_ready))
       {
           if((g_init_ticks++) % 10 == 0)
               PrintFormat("%s BarsCalculated SB=%d ZE=%d BC=%d — deferring", EVT_WAIT, sb, ze, bc);

           if(g_init_ticks > IndicatorInitRetries)
           {
               PrintFormat("%s Indicator warmup exceeded (%d). Proceeding without: SB=%s ZE=%s BC=%s",
                           EVT_WARN, IndicatorInitRetries,
                           sb_ready ? "OK" : "MISSING",
                           ze_ready ? "OK" : "MISSING",
                           bc_ready ? "OK" : "MISSING");
               g_warmup_complete = true; // Force ready state
           }
           else
           {
               return; // Defer this tick, try again
           }
       }
       else
       {
           g_warmup_complete = true; // All indicators are ready
       }
   }
   // === END Spec 4 ===

   datetime t = iTime(_Symbol, SignalTimeframe, 0);
   if(t == 0 || t == g_lastBarTime) return;
   
   if(g_lastBarTime == 0) PrintFormat("%s %s", EVT_FIRST_BAR_OR_NEW, TimeToString(t, TIME_DATE|TIME_MINUTES));
   g_lastBarTime = t;

   if(g_sbTF != SignalTimeframe) { /* Handle TF changes */ }

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

   // === BEGIN Spec 5 & 6: Hardened Reads and Gating ===
   double sbSig, sbConf, sbReason, sbZoneTf;
   bool ok0 = ReadOne(g_hSignalBrain, SB_BUF_SIGNAL, 1, sbSig);
   bool ok1 = ReadOne(g_hSignalBrain, SB_BUF_CONF,   1, sbConf);
   bool ok2 = ReadOne(g_hSignalBrain, SB_BUF_REASON, 1, sbReason);
   bool ok3 = ReadOne(g_hSignalBrain, SB_BUF_ZONETF, 1, sbZoneTf);

   // Log read failures only once
   if(!ok0 && !g_warn_log_flags[SB_BUF_SIGNAL]) { PrintFormat("%s Read failed: SB buf %d", EVT_WARN, SB_BUF_SIGNAL); g_warn_log_flags[SB_BUF_SIGNAL] = true; }
   if(!ok1 && !g_warn_log_flags[SB_BUF_CONF])   { PrintFormat("%s Read failed: SB buf %d", EVT_WARN, SB_BUF_CONF);   g_warn_log_flags[SB_BUF_CONF]   = true; }
   if(!ok2 && !g_warn_log_flags[SB_BUF_REASON]) { PrintFormat("%s Read failed: SB buf %d", EVT_WARN, SB_BUF_REASON); g_warn_log_flags[SB_BUF_REASON] = true; }
   if(!ok3 && !g_warn_log_flags[SB_BUF_ZONETF]) { PrintFormat("%s Read failed: SB buf %d", EVT_WARN, SB_BUF_ZONETF); g_warn_log_flags[SB_BUF_ZONETF] = true; }

   int signal = (int)sbSig;
   if(signal == 0) return; // Gating: No signal, skip entry logic

   int confidence = (int)sbConf;
   if(MinConfidenceToTrade > 0 && confidence < MinConfidenceToTrade) return; // Gating: Confidence too low

   ENUM_REASON_CODE reasonCode = (ok2 ? (ENUM_REASON_CODE)sbReason : REASON_NONE);
   // === END Spec 5 & 6 ===
      
   double distal_level = 0.0;
   if(!ReadOne(g_hZoneEngine, ZE_BUF_DISTAL, 1, distal_level) || distal_level == 0.0)
   {
      if(!g_warn_log_flags[ZE_BUF_DISTAL]) { PrintFormat("%s Read failed or invalid: ZE buf %d", EVT_WARN, ZE_BUF_DISTAL); g_warn_log_flags[ZE_BUF_DISTAL] = true; }
      return;
   }

   double ask = SymbolInfoDouble(symbolName, SYMBOL_ASK);
   double bid = SymbolInfoDouble(symbolName, SYMBOL_BID);
   double sl = 0, tp = 0;
   double sl_buffer_points = PriceFromPips(StopLossBufferPips);
   double risk_points = 0;
   double lots_to_trade = 0;

   if(signal == 1) { sl = distal_level - sl_buffer_points; risk_points = ask - sl; if(risk_points <= 0) return; tp = ask + risk_points * RiskRewardRatio; }
   else { sl = distal_level + sl_buffer_points; risk_points = sl - bid; if(risk_points <= 0) return; tp = bid - risk_points * RiskRewardRatio; }

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
      default:                           return "None";
   }
}
//+------------------------------------------------------------------+
