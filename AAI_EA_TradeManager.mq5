//+------------------------------------------------------------------+
//|                     AAI_EA_TradeManager.mq5                      |
//|             v3.32 - Fixed Enum Conflicts & Const Modify Error    |
//|                                                                  |
//| (Takes trade signals from AAI_Indicator_SignalBrain)     |
//|                                                                  |
//| Copyright 2025, AlfredAI Project                    |
//+------------------------------------------------------------------+
#property strict
#property version   "3.38" // As Coder, incremented version for this change
#property description "Manages trades and logs closed positions to a CSV journal."
#include <Trade\Trade.mqh>
#include <Arrays\ArrayLong.mqh>

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
#define DBG_ZE    "[DBG_ZE]"
#define EVT_SUPPRESS "[EVT_SUPPRESS]"
#define EVT_COOLDOWN "[EVT_COOLDOWN]"
#define DBG_CONF  "[DBG_CONF]"

// === BEGIN Spec: Constants for buffer indexes ===
#define SB_BUF_SIGNAL   0
#define SB_BUF_CONF     1
#define SB_BUF_REASON   2
#define SB_BUF_ZONETF   3
#define BC_BUF_HTF_BIAS 0
// === END Spec ===


//--- Helper Enums
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
    REASON_TEST_SCENARIO
};
enum ENUM_EXECUTION_MODE { SignalsOnly, AutoExecute };
enum ENUM_ENTRY_MODE { FirstBarOrEdge, EdgeOnly };
enum ENUM_OVEREXT_MODE { HardBlock, WaitForBand };
enum ENUM_BC_ALIGN_MODE { BC_REQUIRED, BC_PREFERRED };
enum ENUM_ZE_GATE_MODE { ZE_GATE_OFF=0, ZE_GATE_PREFERRED=1, ZE_GATE_REQUIRED=2 };
enum ENUM_OVEREXT_STATE { OK, BLOCK, ARMED, READY, TIMEOUT };
//--- State struct for overextension pullback
struct OverextArm
{
   datetime until;
   int      side;
   bool     armed;
   int      bars_waited;
};
//--- EA Inputs
input ENUM_EXECUTION_MODE ExecutionMode = AutoExecute;
input ENUM_ENTRY_MODE     EntryMode     = FirstBarOrEdge;
input int      MinConfidenceToTrade = 4;
input ulong    MagicNumber          = 1337;
input ENUM_TIMEFRAMES SignalTimeframe = PERIOD_CURRENT;
input int SB_ReadShift = 1;
// --- SignalBrain Pass-Through Inputs ---
input group "SignalBrain Pass-Through Inputs"
input bool SB_PassThrough_SafeTest   = false;
input bool SB_PassThrough_UseZE      = false;
input bool SB_PassThrough_UseBC      = true;
input int  SB_PassThrough_WarmupBars = 150;
input int  SB_PassThrough_FastMA     = 10;
input int  SB_PassThrough_SlowMA     = 30;
input int  SB_PassThrough_MinZoneStrength = 4;
input bool SB_PassThrough_EnableDebug = true;

//--- Risk Management Inputs ---
input group "Risk Management"
input double   RiskPercent          = 1.0;
input double   MinLotSize           = 0.01;
input double   MaxLotSize           = 10.0;
input int      StopLossBufferPips   = 5;
input double   RiskRewardRatio      = 1.5;
//--- Trade Management Inputs ---
input group "Trade Management"
input bool     PerBarDebounce       = true;
input uint     DuplicateGuardMs     = 300;
input int      CooldownAfterSLBars  = 2;
input ENUM_OVEREXT_MODE OverextMode = WaitForBand;
input int      OverextPullbackBars  = 8;
input ENUM_BC_ALIGN_MODE BC_AlignMode = BC_PREFERRED;
input int      MinATRPoints         = 8;
input int      MaxOverextPips       = 10;
input int      OverextMAPeriod      = 10;
input int      MaxSpreadPoints      = 20;
input int      MaxSlippagePoints    = 10;
input bool     EnablePartialProfits = true;
input double   PartialProfitRR      = 1.0;
input double   PartialClosePercent  = 50.0;
input int      BreakEvenPips      = 40;
input int      BreakEvenOffsetPips = 0;   // 0 = pure BE; 1 = BE+1 pip, etc.
input int      TrailingStartPips  = 40;
input int      TrailingStopPips   = 30;
input int      OvernightTrailPips = 30;
input int      FridayCloseHour    = 22;
input int      StartHour          = 1;
input int      StartMinute        = 0;
input int      EndHour            = 23;
input int      EndMinute          = 30;
input bool     EnableLogging      = true;
//--- ZoneEngine Gating & Telemetry ---
input group "ZoneEngine Gating & Telemetry"
input ENUM_ZE_GATE_MODE ZE_GateMode = ZE_GATE_OFF;
input double   ZE_MinStrength       = 4.0;
input int      ZE_PrefBonus         = 2;
input bool     ZE_TelemetryEnabled    = true;
input int      ZE_BufferIndexStrength = 0;
input int      ZE_ReadShift           = 1;
//--- Journaling Inputs ---
input group "Journaling"
input bool     EnableJournaling     = true;
input string   JournalFileName      = "AlfredAI_Journal.csv";
input bool     JournalUseCommonFiles = true;

//--- Globals
CTrade    trade;
string    symbolName;
double    point;
static ulong g_logged_positions[];
int       g_logged_positions_total = 0;
static OverextArm g_ox;
int g_ze_buf_idx = 0;
// --- Persistent Indicator Handles ---
int sb_handle = INVALID_HANDLE;
int g_ze_handle = INVALID_HANDLE;
double g_ze_strength = 0.0;
int bc_handle = INVALID_HANDLE;
int g_hATR = INVALID_HANDLE;
int g_hOverextMA = INVALID_HANDLE;
// --- State Management Globals ---
static datetime g_lastBarTime = 0;
static datetime g_last_suppress_log_time = 0;
static ulong    g_tickCount   = 0;
bool g_warmup_complete = false;
bool g_bootstrap_done = false;
static datetime g_last_entry_bar_buy = 0, g_last_entry_bar_sell = 0;
static ulong    g_last_send_sig_hash = 0;
static ulong g_last_send_ms = 0;
static datetime g_cool_until_buy = 0, g_cool_until_sell = 0;
bool g_ze_ok = true;
static bool g_ze_fallback_logged = false;
/*** AAI: block counters ***/
long g_blk_conf=0, g_blk_ze=0, g_blk_bc=0, g_blk_over=0,
     g_blk_sess=0, g_blk_spd=0, g_blk_cool=0, g_blk_bar=0, g_blk_no=0;

// Placed after the global variables section

/*** AAI G-015: Centralized Helpers ***/

// Centralized block counting and logging
bool AAI_Block(const string reason)
{
   if(g_lastBarTime == g_last_suppress_log_time) return false; // Prevent per-tick multi-counting on same bar
   g_last_suppress_log_time = g_lastBarTime;

   if(reason=="confidence")  g_blk_conf++;
   else if(reason=="ze_gate") g_blk_ze++;
   else if(reason=="bc")      g_blk_bc++;
   else if(StringFind(reason, "overext")==0) g_blk_over++; // Group all overext reasons
   else if(reason=="session")  g_blk_sess++;
   else if(reason=="spread")   g_blk_spd++;
   else if(reason=="cooldown") g_blk_cool++;
   else if(reason=="same_bar") g_blk_bar++;
   else if(reason=="no_trigger") g_blk_no++;
   
   PrintFormat("[EVT_SUPPRESS] reason=%s", reason);
   return(false); 
}

// Forward-declare if this appears below the call site
bool AAI_ComputeConfidence(double sb_conf, bool ze_ok, double &conf_raw, double &conf_eff);

// Compute effective confidence (ZE bonus first), return pass/fail
bool AAI_ComputeConfidence(double sb_conf, bool ze_ok, double &conf_raw, double &conf_eff)
{
   conf_raw = sb_conf;
   conf_eff = conf_raw;

   // NOTE: pick the enum token you actually have:
   // if(ZE_GateMode==ZE_PREFERRED && ze_ok)
   if(ZE_GateMode==ZE_GATE_PREFERRED && ze_ok)
      conf_eff += ZE_PrefBonus;

   bool gate_conf = (conf_eff >= MinConfidenceToTrade);

   PrintFormat("[DBG_CONF] raw=%.1f ze_ok=%s bonus=%d eff=%.1f thr=%.1f",
               conf_raw,
               (ze_ok ? "T" : "F"),
               (int)((ZE_GateMode==ZE_GATE_PREFERRED && ze_ok) ? ZE_PrefBonus : 0),
               conf_eff, (double)MinConfidenceToTrade);

   return gate_conf;
}


//+------------------------------------------------------------------+
//| Auto-detect which ZE buffer contains strength (0..3)             |
//+------------------------------------------------------------------+
int AAI_AutoDetectZEBuffer(const int handle, const int shift)
{
   double tmp[1];
   for(int b = 0; b < 4; ++b)
   {
      if(CopyBuffer(handle, b, shift, 1, tmp) == 1)
      {
         // Strength is a sane [0..10] value in our indicator
         if(tmp[0] >= 0.0 && tmp[0] <= 10.0)
         {
            PrintFormat("[INIT] ZE auto-detect picked buffer %d (%.1f)", b, tmp[0]);
            return b;
         }
      }
   }
   Print("[INIT] ZE auto-detect failed; defaulting to 0");
   return 0;
}


//+------------------------------------------------------------------+
//| Pip Math Helpers                                                 |
//+------------------------------------------------------------------+
inline double PipSize()
{
   const int digits = (int)SymbolInfoInteger(_Symbol, SYMBOL_DIGITS);
   return (digits == 3 || digits == 5) ?
   10 * _Point : _Point;
}

inline double PriceFromPips(double pips)
{
   return pips * PipSize();
}

//+------------------------------------------------------------------+
//|
//| Simple string to ulong hash (for duplicate guard)                |
//+------------------------------------------------------------------+
ulong StringToULongHash(string s)
{
    ulong hash = 5381;
    int len = StringLen(s);
    for(int i = 0; i < len; i++)
    {
        hash = ((hash << 5) + hash) + (ulong)StringGetCharacter(s, i);
    }
    return hash;
}

string ZE_GateModeToString(ENUM_ZE_GATE_MODE m)
{
  if(m==ZE_GATE_OFF)      return "ZE_OFF";
  if(m==ZE_GATE_PREFERRED) return "ZE_PREFERRED";
  return "ZE_REQUIRED";
}

//+------------------------------------------------------------------+
//| Safe 1-value reader from any indicator buffer                    |
//+------------------------------------------------------------------+
inline bool ReadOne(const int handle, const int buf, const int shift, double &out)
{
    if(handle == INVALID_HANDLE){ out = 0.0;
    return false; }
    double tmp[1];
    if(CopyBuffer(handle, buf, shift, 1, tmp) == 1){ out = tmp[0]; return true;
    }
    out = 0.0;
    return false;
}

//+------------------------------------------------------------------+
//|
//| Safe updater for ZoneEngine strength                             |
//+------------------------------------------------------------------+
void AAI_UpdateZE(datetime t_now)
{
   g_ze_strength = 0.0;
   if(g_ze_handle == INVALID_HANDLE) return;

   int calc = BarsCalculated(g_ze_handle);
   if(calc < ZE_ReadShift + 1)
   {
      PrintFormat("[EVT_WAIT] BarsCalculated ZE=%d (<%d)", calc, ZE_ReadShift + 1);
      return;
   }

   double ze_buf[1];
   ResetLastError();

   // First try the chosen buffer index
   if(CopyBuffer(g_ze_handle, g_ze_buf_idx, ZE_ReadShift, 1, ze_buf) != 1)
   {
      int le = GetLastError();
      PrintFormat("[EVT_WARN] ZE CopyBuffer failed (buf=%d shift=%d le=%d)", g_ze_buf_idx, ZE_ReadShift, le);
      // Fallback to 0 if we weren't already on 0
      if(g_ze_buf_idx != 0 && CopyBuffer(g_ze_handle, 0, ZE_ReadShift, 1, ze_buf) == 1)
      {
         Print("[EVT_WARN] ZE fallback to buf=0 succeeded");
         g_ze_strength = ze_buf[0];
      }
      else
      {
         g_ze_strength = 0.0;
      }
   }
   else
   {
      g_ze_strength = ze_buf[0];
   }

   if(ZE_TelemetryEnabled)
   {
      string ts = TimeToString(iTime(_Symbol, (ENUM_TIMEFRAMES)SignalTimeframe, ZE_ReadShift));
      PrintFormat("[DBG_ZE] t=%s strength=%.1f", ts, g_ze_strength);
   }
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
//|
//| Expert initialization                                           |
//+------------------------------------------------------------------+
int OnInit()
{
   symbolName = _Symbol;
   point = SymbolInfoDouble(symbolName, SYMBOL_POINT);
   trade.SetExpertMagicNumber(MagicNumber);
   g_ox.armed = false;
   g_last_entry_bar_buy=0; g_last_entry_bar_sell=0;
   g_cool_until_buy=0; g_cool_until_sell=0;
   sb_handle = iCustom(_Symbol, SignalTimeframe, "AAI_Indicator_SignalBrain",
                       SB_PassThrough_SafeTest, SB_PassThrough_UseZE, SB_PassThrough_UseBC,
                       SB_PassThrough_WarmupBars, SB_PassThrough_FastMA, SB_PassThrough_SlowMA,
                       SB_PassThrough_MinZoneStrength, SB_PassThrough_EnableDebug);
   if(SB_PassThrough_UseBC) bc_handle = iCustom(_Symbol, SignalTimeframe, "AAI_Indicator_BiasCompass");

   g_ze_handle = iCustom(_Symbol, SignalTimeframe, "AAI_Indicator_ZoneEngine");
   if(g_ze_handle == INVALID_HANDLE)
   {
      PrintFormat("%s ZE handle init failed. Telemetry will show strength=0.", EVT_WARN);
   }
   // Use tester input as a hint; -1 means auto-detect
   g_ze_buf_idx = ZE_BufferIndexStrength;
   if(g_ze_buf_idx < 0)
      g_ze_buf_idx = AAI_AutoDetectZEBuffer(g_ze_handle, ZE_ReadShift);

// Log the final gate config
   PrintFormat("[INIT] ZE gate=%d buf=%d shift=%d min=%.1f bonus=%d handle=%d",
            ZE_GateMode, g_ze_buf_idx, ZE_ReadShift, ZE_MinStrength, ZE_PrefBonus, g_ze_handle);
   if(sb_handle == INVALID_HANDLE){ Print("[ERR] SB iCustom handle invalid"); return(INIT_FAILED); }

   PrintFormat("%s EntryMode=%s", EVT_INIT, EnumToString(EntryMode));
   PrintFormat("%s ZE gate=%s buf=%d shift=%d min=%.1f bonus=%d handle=%d", EVT_INIT, ZE_GateModeToString(ZE_GateMode), ZE_BufferIndexStrength, ZE_ReadShift, ZE_MinStrength, ZE_PrefBonus, g_ze_handle);
   PrintFormat("%s EA→SB args: SafeTest=%c UseZE=%c UseBC=%c Warmup=%d | sb_handle=%d",
               EVT_INIT, SB_PassThrough_SafeTest ? 'T' : 'F', SB_PassThrough_UseZE ? 'T' : 'F',
               SB_PassThrough_UseBC ? 'T' : 'F', SB_PassThrough_WarmupBars, sb_handle);
   g_hATR = iATR(_Symbol, _Period, 14);
   if(g_hATR == INVALID_HANDLE){ Print("[ERR] Failed to create ATR indicator handle"); return(INIT_FAILED);
   }

   g_hOverextMA = iMA(_Symbol, _Period, OverextMAPeriod, 0, MODE_SMA, PRICE_CLOSE);
   if(g_hOverextMA == INVALID_HANDLE){ Print("[ERR] Failed to create Overextension MA handle"); return(INIT_FAILED); }

   EventSetTimer(1);
   return(INIT_SUCCEEDED);
}

void AAI_LogTestSummary()
{
   PrintFormat("[TEST_SUMMARY] blocks: conf=%I64d ze=%I64d bc=%I64d over=%I64d sess=%I64d spd=%I64d cool=%I64d bar=%I64d none=%I64d",
               g_blk_conf,g_blk_ze,g_blk_bc,g_blk_over,g_blk_sess,g_blk_spd,g_blk_cool,g_blk_bar,g_blk_no);
}

void OnTesterDeinit() { AAI_LogTestSummary(); }

//+------------------------------------------------------------------+
//|
//| Expert deinitialization                                         |
//+------------------------------------------------------------------+
void OnDeinit(const int reason)
{
   EventKillTimer();
   PrintFormat("%s Deinitialized. Reason=%d", EVT_INIT, reason);
   AAI_LogTestSummary();
   if(sb_handle != INVALID_HANDLE) IndicatorRelease(sb_handle);
   if(g_ze_handle != INVALID_HANDLE) IndicatorRelease(g_ze_handle);
   if(bc_handle != INVALID_HANDLE) IndicatorRelease(bc_handle);
   if(g_hATR != INVALID_HANDLE) IndicatorRelease(g_hATR);
   if(g_hOverextMA != INVALID_HANDLE) IndicatorRelease(g_hOverextMA);
}

//+------------------------------------------------------------------+
//|
//| Timer function for heartbeat                                     |
//+------------------------------------------------------------------+
void OnTimer()
{
    if((g_tickCount % 100) == 0) Print(EVT_HEARTBEAT);
}

//+------------------------------------------------------------------+
//|
//| Trade Transaction Event Handler                                  |
//+------------------------------------------------------------------+
void OnTradeTransaction(const MqlTradeTransaction &trans, const MqlTradeRequest &request, const MqlTradeResult &result)
{
   if(EnableJournaling && trans.type == TRADE_TRANSACTION_DEAL_ADD && HistoryDealSelect(trans.deal))
   {
      if((ulong)HistoryDealGetInteger(trans.deal, DEAL_MAGIC) == MagicNumber && HistoryDealGetInteger(trans.deal, DEAL_ENTRY) == DEAL_ENTRY_OUT)
      {
         ulong pos_id = HistoryDealGetInteger(trans.deal, DEAL_POSITION_ID);
         if(!PositionSelectByTicket(pos_id) && !IsPositionLogged(pos_id))
         {
            JournalClosedPosition(pos_id);
            AddToLoggedList(pos_id);
         }
      }
   }

   if (CooldownAfterSLBars > 0 && trans.type == TRADE_TRANSACTION_DEAL_ADD && HistoryDealSelect(trans.deal))
   {
       if ((ulong)HistoryDealGetInteger(trans.deal, DEAL_MAGIC) == MagicNumber &&
           HistoryDealGetInteger(trans.deal, DEAL_ENTRY) == DEAL_ENTRY_OUT &&
           HistoryDealGetInteger(trans.deal, DEAL_REASON) == DEAL_REASON_SL)
       {
           long closing_deal_type = HistoryDealGetInteger(trans.deal, DEAL_TYPE);
           datetime bar_time = iTime(_Symbol, _Period, 0);
           datetime cooldown_end_time = bar_time + CooldownAfterSLBars * PeriodSeconds(_Period);
           if (closing_deal_type == DEAL_TYPE_SELL) // Closed a BUY position
           {
               g_cool_until_buy = cooldown_end_time;
               PrintFormat("%s SL close side=BUY pause=%d bars until %s", EVT_COOLDOWN, CooldownAfterSLBars, TimeToString(g_cool_until_buy));
           }
           else if (closing_deal_type == DEAL_TYPE_BUY) // Closed a SELL position
           {
               g_cool_until_sell = cooldown_end_time;
               PrintFormat("%s SL close side=SELL pause=%d bars until %s", EVT_COOLDOWN, CooldownAfterSLBars, TimeToString(g_cool_until_sell));
           }
       }
   }
}

//+------------------------------------------------------------------+
//|
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
       else return;
   }

   datetime bar_time = iTime(_Symbol, _Period, SB_ReadShift);
   if(bar_time == 0 || bar_time == g_lastBarTime) return;
   g_lastBarTime = bar_time;
   CheckForNewTrades();
}


// This entire function replaces the existing CheckForNewTrades()

//+------------------------------------------------------------------+
//| Check & execute new entries                                      |
//+------------------------------------------------------------------+
void CheckForNewTrades()
{
   const int readShift = MathMax(1, SB_ReadShift);
   double sbSig_curr=0, sbConf=0, sbSig_prev=0, sbReason=0;

   ReadOne(sb_handle, SB_BUF_SIGNAL, readShift, sbSig_curr);
   if(!ReadOne(sb_handle, SB_BUF_SIGNAL, readShift + 1, sbSig_prev)) sbSig_prev = sbSig_curr;
   ReadOne(sb_handle, SB_BUF_CONF, readShift, sbConf);
   ReadOne(sb_handle, SB_BUF_REASON, readShift, sbReason);
   int direction = (sbSig_curr > 0) ? 1 : (sbSig_curr < 0 ? -1 : 0);
   
   AAI_UpdateZE(g_lastBarTime);
   if(direction == 0) return; // No signal from brain, nothing to check.

   // --- Calculate supporting metrics ---
   double atr_val=0, fast_ma_val=0, close_price=0;
   double atr_buffer[1];
   if(CopyBuffer(g_hATR, 0, readShift, 1, atr_buffer) > 0) atr_val = atr_buffer[0];
   double ma_buffer[1];
   if(CopyBuffer(g_hOverextMA, 0, readShift, 1, ma_buffer) > 0) fast_ma_val = ma_buffer[0];
   MqlRates rates[1];
   if(CopyRates(_Symbol, _Period, readShift, 1, rates) > 0) close_price = rates[0].close;
   const double pip = PipSize();
   double over_p = (fast_ma_val > 0 && close_price > 0) ? MathAbs(close_price - fast_ma_val) / pip : 0.0;

   // --- Compute Gate States ---
   bool sess_ok = IsTradingSession();
   bool spread_ok = (MaxSpreadPoints == 0 || (int)SymbolInfoInteger(_Symbol, SYMBOL_SPREAD) <= MaxSpreadPoints);
   bool atr_ok = (MinATRPoints == 0) || (atr_val >= MinATRPoints * point);
   bool bc_ok = !SB_PassThrough_UseBC;
   if(SB_PassThrough_UseBC){
      double htf_bias=0;
      if(ReadOne(bc_handle, BC_BUF_HTF_BIAS, readShift, htf_bias)){
         bool aligned = ((direction > 0 && htf_bias > 0) || (direction < 0 && htf_bias < 0));
         bc_ok = (BC_AlignMode == BC_PREFERRED) ? true : aligned;
      }
   }
   
   if(ZE_GateMode == ZE_GATE_REQUIRED || ZE_GateMode == ZE_GATE_PREFERRED)
      g_ze_ok = (g_ze_strength >= ZE_MinStrength);
   else
      g_ze_ok = true;

// --- confidence (ZE bonus applied inside AAI_ComputeConfidence)
double conf_raw = 0.0, conf_eff = 0.0;
bool pass_conf = AAI_ComputeConfidence(sbConf, g_ze_ok, conf_raw, conf_eff);
// >>> PLACE THIS RIGHT HERE (before any overextension/session/spread gates)
if(!pass_conf)
{
   g_blk_conf++;                // NOTE: see step 2 if this variable doesn't exist
   Print("[EVT_SUPPRESS] reason=confidence");
   return;                              // exit the entry check early
}
ENUM_OVEREXT_STATE over_state = OK;
if(MaxOverextPips > 0)
{
   if(OverextMode == HardBlock)
      over_state = (over_p <= MaxOverextPips) ? OK : BLOCK;
   else
   {
      if(g_ox.armed)
      {
         if(direction != g_ox.side || g_lastBarTime > g_ox.until)
         { 
            over_state = TIMEOUT; 
            g_ox.armed = false; 
         }
         else if(over_p <= MaxOverextPips) 
            over_state = READY; 
         else 
         { 
            g_ox.bars_waited++; 
            over_state = ARMED; 
         }
      }
      else
      {
         if(over_p <= MaxOverextPips) over_state = OK;
         else
         {
            g_ox.armed = true; 
            g_ox.side  = direction; 
            g_ox.until = g_lastBarTime + OverextPullbackBars*PeriodSeconds();
            g_ox.bars_waited = 0;
            over_state = ARMED;
         }
      }
   }
}

   
   int secs = PeriodSeconds();
   datetime until = (direction > 0) ? g_cool_until_buy : g_cool_until_sell;
   int delta = (int)(until - g_lastBarTime);
   int bars_left = (delta <= 0 || secs <= 0) ? 0 : ( (delta + secs - 1) / secs );
   bool cool_ok = (bars_left == 0);
   bool perbar_ok = !PerBarDebounce || ((direction > 0) ? (g_last_entry_bar_buy != g_lastBarTime) : (g_last_entry_bar_sell != g_lastBarTime));

 PrintFormat("[DBG_GATES] %s t=%s sig_prev=%d sig_curr=%d conf=%.0f/%.0f/min=%.0f over_p=%.1f bc_mode=%s ox_armed=%s ox_wait=%d samebar=%s cool=%s ze_ok=%s ze_strength=%.1f",
            DBG_GATES, TimeToString(g_lastBarTime),
            (int)sbSig_prev, (int)sbSig_curr,
            conf_raw, conf_eff, (double)MinConfidenceToTrade,
            over_p,
            EnumToString(BC_AlignMode),
            g_ox.armed ? "T" : "F",
            g_ox.bars_waited,
            !perbar_ok ? "T" : "F",
            !cool_ok ? "T" : "F",
            g_ze_ok ? "T" : "F",
            g_ze_strength);

   // --- Gate Enforcement using Centralized Blocker ---
   if(!sess_ok) { AAI_Block("session"); return; }
   if(!spread_ok) { AAI_Block("spread"); return; }
   if(!atr_ok) { AAI_Block("atr"); return; }
   if(!bc_ok) { AAI_Block("bc"); return; }
   if(ZE_GateMode == ZE_GATE_REQUIRED && !g_ze_ok) { AAI_Block(StringFormat("ze_gate strength=%.1f min=%.1f", g_ze_strength, ZE_MinStrength)); return; }
   if(!pass_conf) { AAI_Block(StringFormat("confidence eff=%.1f min=%.1f", conf_eff, (double)MinConfidenceToTrade)); return; }
   
   if(over_state == BLOCK) { AAI_Block(StringFormat("overext_block over=%.1fp max=%dp", over_p, MaxOverextPips)); return; }
   if(over_state == ARMED) { 
      PrintFormat("[EVT_SUPPRESS] reason=overext_armed side=%s over=%.1fp max=%dp wait_bars=%d",
                  direction > 0 ? "BUY" : "SELL", over_p, MaxOverextPips, OverextPullbackBars);
      AAI_Block("overext_armed"); // Count it, but also print details
      return; 
   }
   if(over_state == TIMEOUT) { AAI_Block(StringFormat("overext_timeout waited=%d", g_ox.bars_waited)); return; }

   // --- Trigger Resolution ---
   string trigger = "";
   bool is_edge = ((int)sbSig_curr != (int)sbSig_prev);
   if(EntryMode == FirstBarOrEdge && !g_bootstrap_done) trigger = "bootstrap";
   else if(OverextMode == WaitForBand && over_state == READY) trigger = "pullback";
   else if(is_edge) trigger = "edge";

   if(trigger == "") { AAI_Block("no_trigger"); return; }
   if(!cool_ok) { AAI_Block(StringFormat("cooldown side=%s bars_left=%d", direction > 0 ? "BUY" : "SELL", bars_left)); return; }
   if(!perbar_ok) { AAI_Block(StringFormat("same_bar side=%s", direction > 0 ? "BUY" : "SELL")); return; }

   // --- Allow Path ---
   if(!PositionSelect(_Symbol))
   {
      string gates_summary = StringFormat("sess:%s,spd:%s,atr:%s,bc:%s,ze:%s,over:%s,cool:%s,bar:%s,mode:%s",
                                          sess_ok?"T":"F", spread_ok?"T":"F", atr_ok?"T":"F", bc_ok?"T":"F",
                                          g_ze_ok?"T":"F", over_state==OK||over_state==READY?"T":"F", cool_ok?"T":"F", perbar_ok?"T":"F",
                                          ZE_GateModeToString(ZE_GateMode));
      PrintFormat("%s trigger=%s side=%s conf=%.0f/%.0f/20 gates={%s}", EVT_ENTRY_CHECK, trigger,
                  direction > 0 ? "BUY" : "SELL", conf_raw, conf_eff, gates_summary);
      if(TryOpenPosition(direction, (int)conf_eff, (int)sbReason))
      {
         if(trigger == "bootstrap") g_bootstrap_done = true;
         if(trigger == "pullback") g_ox.armed = false;
      }
   }
}
//+------------------------------------------------------------------+
//|
//| Attempts to open a trade and returns true on success             |
//+------------------------------------------------------------------+
bool TryOpenPosition(int signal, int confidence, int reason_code)
{
   MqlTick t;
   if(!SymbolInfoTick(_Symbol, t) || t.time_msc == 0){
      if(g_lastBarTime != g_last_suppress_log_time){
         PrintFormat("%s reason=no_tick", EVT_SUPPRESS);
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

   ulong now_ms = GetTickCount64();
   string hash_str = StringFormat("%I64d|%d|%.*f", (long)g_lastBarTime, signal, digs, entry);
   ulong sig_h = StringToULongHash(hash_str);
   if(DuplicateGuardMs > 0 && g_last_send_sig_hash == sig_h && (now_ms - g_last_send_ms) < DuplicateGuardMs)
   {
      if(g_lastBarTime != g_last_suppress_log_time){
         PrintFormat("%s reason=duplicate_guard details=%dms", EVT_SUPPRESS, (int)(now_ms - g_last_send_ms));
         g_last_suppress_log_time = g_lastBarTime;
      }
      return false;
   }

   double sl = 0, tp = 0;
   if(signal > 0){ sl = NormalizeDouble(entry - sl_dist, digs);
   tp = NormalizeDouble(entry + RiskRewardRatio * (entry - sl), digs);
   }
   else if(signal < 0){ sl = NormalizeDouble(entry + sl_dist, digs);
   tp = NormalizeDouble(entry - RiskRewardRatio * (sl - entry), digs);
   }

   PrintFormat("%s side=%s bid=%.5f ask=%.5f entry=%.5f pip=%.5f minStop=%.5f buf=%gp(%.5f) sl=%.5f tp=%.5f",
               DBG_STOPS, signal > 0 ? "BUY" : "SELL", t.bid, t.ask, entry, pip_size, min_stop_dist,
               (double)StopLossBufferPips, buf_price, sl, tp);
   bool ok_side = (signal > 0) ? (sl < entry && entry < tp) : (tp < entry && entry < sl);
   bool ok_dist = (MathAbs(entry - sl) >= min_stop_dist) && (MathAbs(tp - entry) >= min_stop_dist);
   if(!ok_side || !ok_dist){
      if(g_lastBarTime != g_last_suppress_log_time){
         PrintFormat("%s reason=stops_invalid details=side:%s entry:%.5f sl:%.5f tp:%.5f", EVT_SUPPRESS, signal > 0 ? "BUY" : "SELL", entry, sl, tp);
         g_last_suppress_log_time = g_lastBarTime;
      }
      return false;
   }

   double lots_to_trade = CalculateLotSize(confidence, MathAbs(entry - sl));
   if(lots_to_trade < MinLotSize) return false;
   string signal_str = (signal == 1) ? "BUY" : "SELL";
   // Store context for journaling: AAI|Conf|Reason|ZE_Strength|SL|TP
   string comment = StringFormat("AAI|%d|%d|%.2f|%.5f|%.5f",
                                 confidence,
                                 reason_code,
                       
                                 g_ze_strength,
                                 sl,
                                 tp);
   if(ExecutionMode == AutoExecute){
      g_last_send_sig_hash = sig_h;
      g_last_send_ms = now_ms;
      trade.SetDeviationInPoints(MaxSlippagePoints);
      bool order_sent = (signal > 0) ? trade.Buy(lots_to_trade, symbolName, entry, sl, tp, comment) : trade.Sell(lots_to_trade, symbolName, entry, sl, tp, comment);
      if(order_sent && (trade.ResultRetcode() == TRADE_RETCODE_DONE || trade.ResultRetcode() == TRADE_RETCODE_DONE_PARTIAL)){
         PrintFormat("%s Signal:%s → Executed %.2f lots @%.5f | SL:%.5f TP:%.5f", EVT_ENTRY, signal_str, trade.ResultVolume(), trade.ResultPrice(), sl, tp);
         if(signal > 0) g_last_entry_bar_buy = g_lastBarTime; else g_last_entry_bar_sell = g_lastBarTime;
         return true;
      }
      else{
         if(g_lastBarTime != g_last_suppress_log_time){
            PrintFormat("%s reason=trade_send_failed details=retcode:%d", EVT_SUPPRESS, trade.ResultRetcode());
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
   if(EnablePartialProfits) { HandlePartialProfits(); if(!PositionSelect(_Symbol)) return;
   }
   
   ulong ticket = PositionGetInteger(POSITION_TICKET);
   if(loc.day_of_week==FRIDAY && loc.hour>=FridayCloseHour) { trade.PositionClose(ticket); return;
   }

   ENUM_POSITION_TYPE side = (ENUM_POSITION_TYPE)PositionGetInteger(POSITION_TYPE);
   double entry = PositionGetDouble(POSITION_PRICE_OPEN);
   double sl    = PositionGetDouble(POSITION_SL);
   double tp    = PositionGetDouble(POSITION_TP);

   if(AAI_ApplyBEAndTrail(side, entry, sl))
   {
      // apply SL only; keep TP unchanged
      trade.PositionModify(_Symbol, sl, tp);
   }
}

//+------------------------------------------------------------------+
//| Helper to get pip size
//+------------------------------------------------------------------+
double AAI_Pip() { return (_Digits==3 || _Digits==5) ? 10*_Point : _Point; }

//+------------------------------------------------------------------+
//| Unified SL updater
//+------------------------------------------------------------------+
bool AAI_ApplyBEAndTrail(const ENUM_POSITION_TYPE side, const double entry_price, double &sl_io)
{
   const double pip = AAI_Pip();
   const double bid = SymbolInfoDouble(_Symbol, SYMBOL_BID);
   const double ask = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
   const bool   is_long = (side==POSITION_TYPE_BUY);
   const double px     = is_long ? bid : ask;
   const double move_p = is_long ? (px - entry_price) : (entry_price - px);
   const double move_pips = move_p / pip;

   bool changed=false;

   // --- 1) Break-even snap (one-shot tighten; never loosen)
   if(BreakEvenPips > 0 && move_pips >= BreakEvenPips)
   {
      double be_target = entry_price + (is_long ? +1 : -1) * BreakEvenOffsetPips * pip;
      if( (is_long && (sl_io < be_target)) || (!is_long && (sl_io > be_target)) )
      {
         sl_io = be_target;
         changed = true;
      }
   }

   // --- 2) Trailing (after start; never loosen; respects BE already set)
   if(TrailingStartPips > 0 && move_pips >= TrailingStartPips && TrailingStopPips > 0)
   {
      double trail_target = px - (is_long ? TrailingStopPips : -TrailingStopPips) * pip;
      if( (is_long && (trail_target > sl_io)) || (!is_long && (trail_target < sl_io)) )
      {
         sl_io = trail_target;
         changed = true;
      }
   }

   return changed;
}


//+------------------------------------------------------------------+
//|
//| Handle Partial Profits                                           |
//+------------------------------------------------------------------+
void HandlePartialProfits()
{
   string comment = PositionGetString(POSITION_COMMENT);
   if(StringFind(comment, "|P1") != -1) return;
   // Already took partials

   string parts[];
   if(StringSplit(comment, '|', parts) < 6) return;
   // AAI|C|R|ZE|SL|TP

   double sl_price = StringToDouble(parts[4]);
   double open_price = PositionGetDouble(POSITION_PRICE_OPEN);
   if(sl_price == 0) return;
   double initial_risk_pips = MathAbs(open_price - sl_price) / PipSize();
   if(initial_risk_pips <= 0) return;

   long type = PositionGetInteger(POSITION_TYPE);
   double current_profit_pips = (type == POSITION_TYPE_BUY) ? (SymbolInfoDouble(symbolName, SYMBOL_BID) - open_price) / PipSize() : (open_price - SymbolInfoDouble(symbolName, SYMBOL_ASK)) / PipSize();
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
//|
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
//|
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
//|
//| Journaling Functions                                             |
//+------------------------------------------------------------------+
void JournalClosedPosition(ulong position_id)
{
   if(!HistorySelectByPosition(position_id)) return;

   // --- Data to collect ---
   datetime timestamp_close = 0;
   string   symbol = "";
   string   side = "";
   double   lots = 0;
   double   entry_price = 0;
   double   sl_price = 0;
   double   tp_price = 0;
   double   exit_price = 0;
   double   profit = 0;
   int      conf = 0;
   int      reason = 0;
   double   ze_strength = 0;
   string   bc_mode = EnumToString(BC_AlignMode);
   // --- Parse deals ---
   for(int i=0; i<HistoryDealsTotal(); i++)
   {
      ulong deal_ticket = HistoryDealGetTicket(i);
      profit += HistoryDealGetDouble(deal_ticket, DEAL_PROFIT) + HistoryDealGetDouble(deal_ticket, DEAL_COMMISSION) + HistoryDealGetDouble(deal_ticket, DEAL_SWAP);
      if(HistoryDealGetInteger(deal_ticket, DEAL_ENTRY) == DEAL_ENTRY_IN)
      {
         if(entry_price == 0) // First entry deal
         {
            symbol = HistoryDealGetString(deal_ticket, DEAL_SYMBOL);
            side = (HistoryDealGetInteger(deal_ticket, DEAL_TYPE) == DEAL_TYPE_BUY) ? "BUY" : "SELL";
            entry_price = HistoryDealGetDouble(deal_ticket, DEAL_PRICE);

            string comment = HistoryDealGetString(deal_ticket, DEAL_COMMENT);
            string parts[];
            if(StringSplit(comment, '|', parts) >= 6)
            {
               conf = (int)StringToInteger(parts[1]);
               reason = (int)StringToInteger(parts[2]);
               ze_strength = StringToDouble(parts[3]);
               sl_price = StringToDouble(parts[4]);
               tp_price = StringToDouble(parts[5]);
            }
         }
         lots += HistoryDealGetDouble(deal_ticket, DEAL_VOLUME);
      }
      else // Exit deal
      {
         timestamp_close = (datetime)HistoryDealGetInteger(deal_ticket, DEAL_TIME);
         exit_price = HistoryDealGetDouble(deal_ticket, DEAL_PRICE);
      }
   }

   if(symbol == "") return;
   // Should not happen if position existed

   // --- Calculate derived metrics ---
   double profit_points = 0;
   if(lots > 0)
   {
       profit_points = (exit_price - entry_price) * (side == "BUY" ? 1 : -1) / point;
   }

   double rr = 0;
   double risk_dist = MathAbs(entry_price - sl_price);
   if(risk_dist > 0)
   {
      double profit_dist = MathAbs(exit_price - entry_price);
      rr = profit_dist / risk_dist;
   }

   // --- Format and write to file ---
   int file_handle = FileOpen(JournalFileName, FILE_READ|FILE_WRITE|FILE_CSV|(JournalUseCommonFiles ? FILE_COMMON : 0), ';');
   if(file_handle != INVALID_HANDLE)
   {
      if(FileSize(file_handle) == 0)
      {
         FileWriteString(file_handle, "timestamp_close;symbol;side;lots;entry;sl;tp;exit;profit;profit_points;rr;conf;reason;ze_strength;bc_mode\n");
      }

      FileSeek(file_handle, 0, SEEK_END);

      string line = StringFormat("%s;%s;%s;%.2f;%.5f;%.5f;%.5f;%.5f;%.2f;%.1f;%.2f;%d;%d;%.2f;%s\n",
                                 TimeToString(timestamp_close, TIME_DATE|TIME_SECONDS),
                                 symbol,
                     
                                 side,
                                 lots,
                                 entry_price,
                      
                                 sl_price,
                                 tp_price,
                                 exit_price,
                       
                                 profit,
                                 profit_points,
                                 rr,
                        
                                 conf,
                                 reason,
                                 ze_strength,
                         
                                 bc_mode);

      FileWriteString(file_handle, line);
      FileFlush(file_handle);
      FileClose(file_handle);
   }
   else
   {
      PrintFormat("%s Failed to open journal file '%s'. Error: %d", EVT_JOURNAL, JournalFileName, GetLastError());
   }
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
