//+------------------------------------------------------------------+
//|                     AAI_EA_TradeManager.mq5                      |
//|             v3.32 - Fixed Enum Conflicts & Const Modify Error    |
//|                                                                  |
//|
//| (Takes trade signals from AAI_Indicator_SignalBrain)             |
//|                                                                  |
//| Copyright 2025, AlfredAI Project                                 |
//+------------------------------------------------------------------+
#property strict
#property version   "3.39" // As Coder, incremented version for this change
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
#define AAI_BLOCK_LOG "[AAI_BLOCK]"

// === BEGIN Spec: Constants for buffer indexes ===
#define SB_BUF_SIGNAL   0
#define SB_BUF_CONF     1
#define SB_BUF_REASON   2
#define SB_BUF_ZONETF   3
#define BC_BUF_HTF_BIAS 0
// === END Spec ===


// HYBRID toggle + timeout
input bool InpHybrid_RequireApproval = true;
input int  InpHybrid_TimeoutSec      = 180;

// Subfolders under MQL5/Files (no trailing backslash)
string   g_dir_base   = "AlfredAI";
string   g_dir_intent = "AlfredAI\\intents";
string   g_dir_cmds   = "AlfredAI\\cmds";

// Pending intent state
string   g_pending_id = "";
datetime g_pending_ts = 0;

// Store last computed order params for approval placement
string   g_last_side  = "";
double   g_last_entry = 0.0, g_last_sl = 0.0, g_last_tp = 0.0, g_last_vol = 0.0;
double   g_last_rr    = 0.0, g_last_conf_raw = 0.0, g_last_conf_eff = 0.0, g_last_ze = 0.0;
string   g_last_comment = "";


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
enum ENUM_ZE_GATE_MODE { ZE_OFF = 0, ZE_PREFERRED = 1, ZE_REQUIRED = 2 };
enum ENUM_BC_ALIGN_MODE { BC_OFF = 0, BC_PREFERRED = 1, BC_REQUIRED = 2 };
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
input group "Risk Management (M15 Baseline)"
input double   InpRiskPct           = 0.25;
// Risk Percentage
input double   MinLotSize           = 0.01;
input double   MaxLotSize           = 10.0;
input int      InpSL_Buffer_Points  = 10;
// SL Buffer in Points

//--- Trade Management Inputs ---
input group "Trade Management (M15 Baseline)"
input bool     PerBarDebounce       = true;
input uint     DuplicateGuardMs     = 300;
input int      CooldownAfterSLBars  = 2;
input int      MaxSpreadPoints      = 20;
input int      MaxSlippagePoints    = 10;
input int      FridayCloseHour      = 22;
input int      StartHour            = 1;
input int      StartMinute          = 0;
input int      EndHour              = 23;
input int      EndMinute            = 30;
input bool     EnableLogging        = true;
//--- Exit Strategy Inputs (M15 Baseline) ---
input group "Exit Strategy"
input bool     InpExit_FixedRR        = true;
// Use Fixed RR (a) or Partials (b)
input double   InpFixed_RR            = 1.6;
// (a) Fixed Risk-Reward Ratio
input double   InpPartial_Pct         = 50.0;
// (b) Percent to close at partial target
input double   InpPartial_R_multiple  = 1.0;
// (b) R-multiple for partial profit
input int      InpBE_Offset_Points    = 1;
// (b) Points to add for Break-Even
input int      InpTrail_Start_Pips    = 22;
// (b) Pips in profit to start trailing
input int      InpTrail_Stop_Pips     = 10;
// (b) Trailing stop distance in pips

//--- Entry Filter Inputs (M15 Baseline) ---
input group "Entry Filters"
input int        InpMinConfidence        = 11;
// Minimum confidence score to trade
input bool       InpOver_SoftWait        = true;
// Use SoftWait for overextension
input int        InpMaxOverextPips       = 18;
// Max pips from MA for overextension
input int        InpPullbackBarsMin      = 7;
// Min bars to wait for pullback
input int        InpPullbackBarsMax      = 9;
// Max bars to wait for pullback
input int        InpATR_MinPips          = 18;
// Minimum ATR value in pips
input int        OverextMAPeriod         = 10;
//--- Confluence Module Inputs (M15 Baseline) ---
input group "Confluence Modules"
input ENUM_BC_ALIGN_MODE InpBC_AlignMode   = BC_PREFERRED;
// Bias Compass alignment mode
input ENUM_ZE_GATE_MODE  InpZE_Gate        = ZE_PREFERRED;
// ZoneEngine gating mode
input int        InpZE_MinStrength       = 6;
// ZE minimum strength
input int        InpZE_PrefBonus         = 2;
// ZE confidence bonus for PREFERRED
input int        InpZE_BufferIndexStrength = -1;
// ZE Strength Buffer (-1 for auto)
input int        InpZE_ReadShift         = 1;
// ZE lookback shift
input bool       ZE_TelemetryEnabled     = true;
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

// --- Block counters ---
int g_blk_conf = 0; // confidence gate
int g_blk_ze = 0;
// ZoneEngine gate (REQUIRED only)
int g_blk_bc = 0;   // BiasCompass misalignment
int g_blk_over = 0;
// any over-extension abort
int g_blk_sess = 0; // session filter block
int g_blk_spd = 0;
// spread filter block
int g_blk_cool = 0; // cooldown / recent trade block
int g_blk_bar = 0;
// same-bar re-entry guard
int g_blk_no = 0;   // no_trigger / other fallthrough
bool g_test_summary_printed = false; // ensure exactly-one [TEST_SUMMARY]


//+------------------------------------------------------------------+
//| HYBRID Approval Helper Functions                                 |
//+------------------------------------------------------------------+
bool WriteText(const string path, const string text)
{
   int h = FileOpen(path, FILE_WRITE|FILE_TXT|FILE_ANSI);
   if(h==INVALID_HANDLE){ PrintFormat("[HYBRID] FileOpen write fail %s (%d)", path, GetLastError()); return false; }
   FileWriteString(h, text);
   FileClose(h);
   return true;
}

string ReadAll(const string path)
{
   int h = FileOpen(path, FILE_READ|FILE_TXT|FILE_ANSI);
   if(h==INVALID_HANDLE) return "";
   string s = FileReadString(h, (int)FileSize(h));
   FileClose(h);
   return s;
}

string JsonGetStr(const string json, const string key)
{
   string pat="\""+key+"\":\"";
   int p=StringFind(json, pat); if(p<0) return "";
   p+=StringLen(pat);
   int q=StringFind(json,"\"",p); if(q<0) return "";
   return StringSubstr(json, p, q-p);
}

//+------------------------------------------------------------------+
//| Centralized block counting and logging                           |
//+------------------------------------------------------------------+
void AAI_Block(const string reason)
{
    // Create a mutable copy of the constant input string
    string r = reason;
    // Now, convert the copy to lowercase in place
    StringToLower(r);
    // Check the reason using the lowercase copy
    if(StringFind(r, "overext") == 0 || StringFind(r, "over") == 0) { g_blk_over++; }
    else if(r == "confidence")         { g_blk_conf++; }
    else if(r == "ze_gate")            { g_blk_ze++; }
    else if(r == "bc")                 { g_blk_bc++; }
    else if(r == "session")            { g_blk_sess++; }
    else if(r == "spread")             { g_blk_spd++; }
    else if(r == "cooldown")           { g_blk_cool++; }
    else if(r == "same_bar")           { g_blk_bar++; }
    else if(r == "no_trigger")         { g_blk_no++; }
    else                               { g_blk_no++; } // Catch-all for any other reason

    PrintFormat("%s reason=%s", AAI_BLOCK_LOG, reason);
}


// Forward-declare if this appears below the call site
bool AAI_ComputeConfidence(double sb_conf, bool ze_ok, double &conf_raw, double &conf_eff);
// Compute effective confidence (ZE bonus first), return pass/fail
bool AAI_ComputeConfidence(double sb_conf, bool ze_ok, double &conf_raw, double &conf_eff)
{
   conf_raw = sb_conf;
   conf_eff = conf_raw;

   if(InpZE_Gate == ZE_PREFERRED && ze_ok)
      conf_eff += InpZE_PrefBonus;
   bool gate_conf = (conf_eff >= InpMinConfidence);

   PrintFormat("[DBG_CONF] raw=%.1f ze_ok=%s bonus=%d eff=%.1f thr=%.1f",
               conf_raw,
               (ze_ok ? "T" : "F"),
               (int)((InpZE_Gate == ZE_PREFERRED && ze_ok) ? InpZE_PrefBonus : 0),
               conf_eff, (double)InpMinConfidence);
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
  if(m==ZE_OFF)      return "ZE_OFF";
  if(m==ZE_PREFERRED) return "ZE_PREFERRED";
  return "ZE_REQUIRED";
}

//+------------------------------------------------------------------+
//| Safe 1-value reader from any indicator buffer                    |
//+------------------------------------------------------------------+
inline bool ReadOne(const int handle, const int buf, const int shift, double &out)
{
    if(handle == INVALID_HANDLE){ out = 0.0; return false; }
    double tmp[1];
    if(CopyBuffer(handle, buf, shift, 1, tmp) == 1){ out = tmp[0]; return true; }
    out = 0.0;
    return false;
}

//+------------------------------------------------------------------+
//| Safe updater for ZoneEngine strength                             |
//+------------------------------------------------------------------+
void AAI_UpdateZE(datetime t_now)
{
   g_ze_strength = 0.0;
   if(g_ze_handle == INVALID_HANDLE) return;

   int calc = BarsCalculated(g_ze_handle);
   if(calc < InpZE_ReadShift + 1)
   {
      PrintFormat("[EVT_WAIT] BarsCalculated ZE=%d (<%d)", calc, InpZE_ReadShift + 1);
      return;
   }

   double ze_buf[1];
   ResetLastError();

   // First try the chosen buffer index
   if(CopyBuffer(g_ze_handle, g_ze_buf_idx, InpZE_ReadShift, 1, ze_buf) != 1)
   {
      int le = GetLastError();
      PrintFormat("[EVT_WARN] ZE CopyBuffer failed (buf=%d shift=%d le=%d)", g_ze_buf_idx, InpZE_ReadShift, le);
      // Fallback to 0 if we weren't already on 0
      if(g_ze_buf_idx != 0 && CopyBuffer(g_ze_handle, 0, InpZE_ReadShift, 1, ze_buf) == 1)
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
      string ts = TimeToString(iTime(_Symbol, (ENUM_TIMEFRAMES)SignalTimeframe, InpZE_ReadShift));
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
   double risk_amount = account_balance * (InpRiskPct / 100.0);
   double tick_size = SymbolInfoDouble(symbolName, SYMBOL_TRADE_TICK_SIZE);
   double tick_value_loss = SymbolInfoDouble(symbolName, SYMBOL_TRADE_TICK_VALUE_LOSS);
   if(tick_size <= 0) return 0.0;
   double loss_per_lot = (sl_distance_price / tick_size) * tick_value_loss;
   if(loss_per_lot <= 0) return 0.0;
   double base_lot_size = risk_amount / loss_per_lot;
   double scale_min = 0.5;
   double scale_max = 1.0;
   double conf_range = 20.0 - InpMinConfidence;
   double conf_step = confidence - InpMinConfidence;
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
//| Reset and Print Summary Functions                                |
//+------------------------------------------------------------------+
void AAI_ResetBlockCounters()
{
    g_blk_conf = 0; g_blk_ze = 0; g_blk_bc = 0; g_blk_over = 0; g_blk_sess = 0;
    g_blk_spd = 0; g_blk_cool = 0; g_blk_bar = 0; g_blk_no = 0;
}

void AAI_PrintTestSummaryOnce()
{
    if(g_test_summary_printed) return;
    g_test_summary_printed = true;
    PrintFormat("[TEST_SUMMARY] conf=%d ze=%d bc=%d over=%d sess=%d spd=%d cool=%d bar=%d none=%d",
                g_blk_conf, g_blk_ze, g_blk_bc, g_blk_over, g_blk_sess,
                g_blk_spd, g_blk_cool, g_blk_bar, g_blk_no);
}

//+------------------------------------------------------------------+
//| Expert initialization                                            |
//+------------------------------------------------------------------+
int OnInit()
{
   AAI_ResetBlockCounters();
   g_test_summary_printed = false; // Allow a new summary per test run

   symbolName = _Symbol;
   point = SymbolInfoDouble(symbolName, SYMBOL_POINT);
   trade.SetExpertMagicNumber(MagicNumber);
   g_ox.armed = false;
   g_last_entry_bar_buy=0; g_last_entry_bar_sell=0;
   g_cool_until_buy=0; g_cool_until_sell=0;
   
   bool useZE = (InpZE_Gate != ZE_OFF);
   bool useBC = (InpBC_AlignMode != BC_OFF);
   
   sb_handle = iCustom(_Symbol, SignalTimeframe, "AAI_Indicator_SignalBrain",
                       SB_PassThrough_SafeTest, useZE, useBC,
                       SB_PassThrough_WarmupBars, SB_PassThrough_FastMA, SB_PassThrough_SlowMA,
                       SB_PassThrough_MinZoneStrength, SB_PassThrough_EnableDebug);
                       
   if(useBC) bc_handle = iCustom(_Symbol, SignalTimeframe, "AAI_Indicator_BiasCompass");

   g_ze_handle = iCustom(_Symbol, SignalTimeframe, "AAI_Indicator_ZoneEngine");
   if(g_ze_handle == INVALID_HANDLE)
   {
      PrintFormat("%s ZE handle init failed. Telemetry will show strength=0.", EVT_WARN);
   }
   // Use tester input as a hint; -1 means auto-detect
   g_ze_buf_idx = InpZE_BufferIndexStrength;
   if(g_ze_buf_idx < 0)
      g_ze_buf_idx = AAI_AutoDetectZEBuffer(g_ze_handle, InpZE_ReadShift);
   // Log the final gate config
   PrintFormat("[INIT] ZE gate=%d buf=%d shift=%d min=%.1f bonus=%d handle=%d",
            InpZE_Gate, g_ze_buf_idx, InpZE_ReadShift, (double)InpZE_MinStrength, InpZE_PrefBonus, g_ze_handle);
   if(sb_handle == INVALID_HANDLE){ Print("[ERR] SB iCustom handle invalid"); return(INIT_FAILED); }

   PrintFormat("%s EntryMode=%s", EVT_INIT, EnumToString(EntryMode));
   PrintFormat("%s ZE gate=%s buf=%d shift=%d min=%.1f bonus=%d handle=%d", EVT_INIT, ZE_GateModeToString(InpZE_Gate), InpZE_BufferIndexStrength, InpZE_ReadShift, (double)InpZE_MinStrength, InpZE_PrefBonus, g_ze_handle);
   PrintFormat("%s EA→SB args: SafeTest=%c UseZE=%c UseBC=%c Warmup=%d | sb_handle=%d",
               EVT_INIT, SB_PassThrough_SafeTest ? 'T' : 'F', useZE ? 'T' : 'F',
               useBC ? 'T' : 'F', SB_PassThrough_WarmupBars, sb_handle);
   g_hATR = iATR(_Symbol, _Period, 14);
   if(g_hATR == INVALID_HANDLE){ Print("[ERR] Failed to create ATR indicator handle"); return(INIT_FAILED);
   }

   g_hOverextMA = iMA(_Symbol, _Period, OverextMAPeriod, 0, MODE_SMA, PRICE_CLOSE);
   if(g_hOverextMA == INVALID_HANDLE){ Print("[ERR] Failed to create Overextension MA handle"); return(INIT_FAILED); }
   
   if(InpHybrid_RequireApproval)
   {
      FolderCreate(g_dir_base);
      FolderCreate(g_dir_intent);
      FolderCreate(g_dir_cmds);
      Print("[HYBRID] Approval mode active. Timer set to 2 seconds.");
      EventSetTimer(2);
   }

   return(INIT_SUCCEEDED);
}


void OnTesterDeinit() { AAI_PrintTestSummaryOnce();
}

//+------------------------------------------------------------------+
//| Expert deinitialization                                          |
//+------------------------------------------------------------------+
void OnDeinit(const int reason)
{
   if(InpHybrid_RequireApproval)
      EventKillTimer();
   PrintFormat("%s Deinitialized. Reason=%d", EVT_INIT, reason);
   AAI_PrintTestSummaryOnce();
   if(sb_handle != INVALID_HANDLE) IndicatorRelease(sb_handle);
   if(g_ze_handle != INVALID_HANDLE) IndicatorRelease(g_ze_handle);
   if(bc_handle != INVALID_HANDLE) IndicatorRelease(bc_handle);
   if(g_hATR != INVALID_HANDLE) IndicatorRelease(g_hATR);
   if(g_hOverextMA != INVALID_HANDLE) IndicatorRelease(g_hOverextMA);
}


//+------------------------------------------------------------------+
//| HYBRID: Emit trade intent to file                                |
//+------------------------------------------------------------------+
bool EmitIntent(const string side, double entry, double sl, double tp, double volume,
                double rr_target, double conf_raw, double conf_eff, double ze_strength)
{
   g_pending_id = StringFormat("%s_%s_%I64d", _Symbol, EnumToString(_Period), (long)TimeCurrent());
   g_pending_ts = TimeCurrent();
   string fn = g_dir_intent + "\\intent_" + g_pending_id + ".json";
   string json = StringFormat(
      "{\"id\":\"%s\",\"symbol\":\"%s\",\"timeframe\":\"%s\",\"side\":\"%s\","
      "\"entry\":%.5f,\"sl\":%.5f,\"tp\":%.5f,\"volume\":%.2f,"
      "\"rr_target\":%.2f,\"conf_raw\":%.2f,\"conf_eff\":%.2f,\"ze_strength\":%.2f,"
      "\"created_ts\":\"%s\"}",
      g_pending_id, _Symbol, EnumToString(_Period), side,
      entry, sl, tp, volume,
      rr_target, conf_raw, conf_eff, ze_strength,
      TimeToString(TimeCurrent(), TIME_DATE|TIME_MINUTES)
   );
   if(WriteText(fn, json)){ PrintFormat("[HYBRID] intent written: %s", fn); return true; }
   return false;
   
   string filesRoot = TerminalInfoString(TERMINAL_DATA_PATH) + "\\MQL5\\Files\\";
PrintFormat("[HYBRID] intent written at: %s%s", filesRoot, fn);  // fn is your relative intents path

}

//+------------------------------------------------------------------+
//| HYBRID: Execute order after approval                             |
//+------------------------------------------------------------------+
void PlaceOrderFromApproval()
{
    // This function assumes all g_last_* globals have been set by TryOpenPosition
    PrintFormat("[HYBRID] Executing approved trade. Side: %s, Vol: %.2f, Entry: Market, SL: %.5f, TP: %.5f",
                g_last_side, g_last_vol, g_last_sl, g_last_tp);

    trade.SetDeviationInPoints(MaxSlippagePoints);
    bool order_sent = false;
    
    // Using 0 for price executes a market order
    if(g_last_side == "BUY")
    {
        order_sent = trade.Buy(g_last_vol, symbolName, 0, g_last_sl, g_last_tp, g_last_comment);
    }
    else if(g_last_side == "SELL")
    {
        order_sent = trade.Sell(g_last_vol, symbolName, 0, g_last_sl, g_last_tp, g_last_comment);
    }

    if(order_sent && (trade.ResultRetcode() == TRADE_RETCODE_DONE || trade.ResultRetcode() == TRADE_RETCODE_DONE_PARTIAL))
    {
       PrintFormat("%s HYBRID Signal:%s → Executed %.2f lots @%.5f | SL:%.5f TP:%.5f", EVT_ENTRY, g_last_side, trade.ResultVolume(), trade.ResultPrice(), g_last_sl, g_last_tp);
       if(g_last_side == "BUY") g_last_entry_bar_buy = g_lastBarTime; else g_last_entry_bar_sell = g_lastBarTime;
    }
    else
    {
       if(g_lastBarTime != g_last_suppress_log_time)
       {
          PrintFormat("%s reason=trade_send_failed details=retcode:%d", EVT_SUPPRESS, trade.ResultRetcode());
          g_last_suppress_log_time = g_lastBarTime;
       }
    }
}


//+------------------------------------------------------------------+
//| Timer function for HYBRID polling                                |
//+------------------------------------------------------------------+
void OnTimer()
{
   if(!InpHybrid_RequireApproval || g_pending_id=="") return;

   // timeout guard
   if((TimeCurrent() - g_pending_ts) > InpHybrid_TimeoutSec){
      Print("[HYBRID] intent timeout, discarding: ", g_pending_id);
      g_pending_id = "";
      return;
   }

   // full path base for clarity (prints once per pending ID)
   static string filesRoot="";
   if(filesRoot=="")
      filesRoot = TerminalInfoString(TERMINAL_DATA_PATH) + "\\MQL5\\Files\\";

   // look for the EXACT matching command file
   string cmd_rel  = g_dir_cmds + "\\cmd_" + g_pending_id + ".json";
   string cmd_full = filesRoot + cmd_rel;

   // optional breadcrumb (helps confirm folder in the log)
   // PrintFormat("[HYBRID] checking cmd: %s", cmd_full);

   if(!FileIsExist(cmd_rel))  // NOTE: File* APIs use relative path from MQL5/Files
      return;

   string s = ReadAll(cmd_rel);
   if(s==""){ FileDelete(cmd_rel); return; }

   string id     = JsonGetStr(s, "id");
   string action = JsonGetStr(s, "action");
   StringToLower(action);

   if(id != g_pending_id){
      // stale/wrong id; ignore or delete
      // FileDelete(cmd_rel);
      return;
   }

   if(action=="approve"){
      Print("[HYBRID] APPROVED: ", id);
      // TODO: call your placement using g_last_* values
      // PlaceOrderFromApproval();
   } else {
      Print("[HYBRID] REJECTED: ", id);
   }

   FileDelete(cmd_rel);
   g_pending_id = "";
}


//+------------------------------------------------------------------+
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
//| OnTick: Event-driven logic                                       |
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
   // --- ZoneEngine Gating (Step 1) ---
   if(InpZE_Gate == ZE_REQUIRED || InpZE_Gate == ZE_PREFERRED)
      g_ze_ok = (g_ze_strength >= InpZE_MinStrength);
   else
      g_ze_ok = true;
      
   // --- Compute Confidence (Step 2) ---
   double conf_raw = 0.0, conf_eff = 0.0;
   AAI_ComputeConfidence(sbConf, g_ze_ok, conf_raw, conf_eff);

   // --- Main Gate #1: Confidence Short-Circuit ---
   if(conf_eff < InpMinConfidence)
   {
       AAI_Block("confidence");
       return; 
   }

   // --- Compute Other Gate States ---
   bool sess_ok = IsTradingSession();
   bool spread_ok = (MaxSpreadPoints == 0 || (int)SymbolInfoInteger(_Symbol, SYMBOL_SPREAD) <= MaxSpreadPoints);
   bool atr_ok = (InpATR_MinPips == 0) ||
   ((atr_val / pip) >= InpATR_MinPips);

   bool bc_ok = true; // Default to true
   if (InpBC_AlignMode == BC_REQUIRED && SB_PassThrough_UseBC) {
       double htf_bias = 0;
       if (ReadOne(bc_handle, BC_BUF_HTF_BIAS, readShift, htf_bias)) {
           bc_ok = ((direction > 0 && htf_bias > 0) || (direction < 0 && htf_bias < 0));
       }
   }
   bool useZE = (InpZE_Gate != ZE_OFF);
bool useBC = (InpBC_AlignMode != BC_OFF);
// when you log, it should say UseZE=F for ZE_OFF
// EA→SB args: SafeTest=F UseZE=F UseBC=T Warmup=150

   ENUM_OVEREXT_STATE over_state = OK;
   if(InpMaxOverextPips > 0)
   {
      if(!InpOver_SoftWait) // HardBlock Mode
         over_state = (over_p <= InpMaxOverextPips) ?
OK : BLOCK;
      else // SoftWait Mode
      {
         if(g_ox.armed)
         {
            datetime pullback_end = g_lastBarTime + InpPullbackBarsMax * PeriodSeconds();
            if(direction != g_ox.side || TimeCurrent() > pullback_end)
            { 
               over_state = TIMEOUT;
               g_ox.armed = false; 
            }
            else if(over_p <= InpMaxOverextPips) 
               over_state = READY;
            else 
            { 
               g_ox.bars_waited++;
               over_state = ARMED; 
            }
         }
         else
         {
            if(over_p <= InpMaxOverextPips) over_state = OK;
            else
            {
               g_ox.armed = true;
               g_ox.side  = direction;
               g_ox.until = g_lastBarTime + InpPullbackBarsMax * PeriodSeconds();
               g_ox.bars_waited = 0;
               over_state = ARMED;
            }
         }
      }
   }

   int secs = PeriodSeconds();
   datetime until = (direction > 0) ? g_cool_until_buy : g_cool_until_sell;
   int delta = (int)(until - g_lastBarTime);
   int bars_left = (delta <= 0 || secs <= 0) ?
0 : ( (delta + secs - 1) / secs );
   bool cool_ok = (bars_left == 0);
   bool perbar_ok = !PerBarDebounce || ((direction > 0) ? (g_last_entry_bar_buy != g_lastBarTime) : (g_last_entry_bar_sell != g_lastBarTime));
   PrintFormat("[DBG_GATES] %s t=%s sig_prev=%d sig_curr=%d conf=%.0f/%.0f/min=%d over_p=%.1f bc_mode=%s ox_armed=%s ox_wait=%d samebar=%s cool=%s ze_ok=%s ze_strength=%.1f",
            DBG_GATES, TimeToString(g_lastBarTime),
            (int)sbSig_prev, (int)sbSig_curr,
            conf_raw, conf_eff, InpMinConfidence,
            over_p,
            EnumToString(InpBC_AlignMode),
            g_ox.armed ? "T" : "F",
       
            g_ox.bars_waited,
            !perbar_ok ? "T" : "F",
            !cool_ok ? "T" : "F",
            g_ze_ok ? "T" : "F",
            g_ze_strength);
   // --- Gate Enforcement using Centralized Blocker ---
   if(!sess_ok) { AAI_Block("session"); return; }
   if(!spread_ok) { AAI_Block("spread");
   return; }
   if(!atr_ok) { AAI_Block("atr"); return; }
   if(!bc_ok) { AAI_Block("bc"); return;
   }
   if(InpZE_Gate == ZE_REQUIRED && !g_ze_ok) { AAI_Block("ze_gate"); return;
   }
   
   if(over_state == BLOCK) { AAI_Block("overext_block"); return; }
   if(over_state == ARMED) { AAI_Block("overext_armed");
   return; }
   if(over_state == TIMEOUT) { AAI_Block("overext_timeout"); return;
   }

   // --- Trigger Resolution ---
   string trigger = "";
   bool is_edge = ((int)sbSig_curr != (int)sbSig_prev);
   if(EntryMode == FirstBarOrEdge && !g_bootstrap_done) trigger = "bootstrap";
   else if(InpOver_SoftWait && over_state == READY) trigger = "pullback";
   else if(is_edge) trigger = "edge";

   if(trigger == "") { AAI_Block("no_trigger"); return; }
   if(!cool_ok) { AAI_Block("cooldown"); return;
   }
   if(!perbar_ok) { AAI_Block("same_bar"); return; }

   // --- Allow Path ---
   if(!PositionSelect(_Symbol))
   {
      string gates_summary = StringFormat("sess:%s,spd:%s,atr:%s,bc:%s,ze:%s,over:%s,cool:%s,bar:%s,mode:%s",
                                          sess_ok?"T":"F", spread_ok?"T":"F", atr_ok?"T":"F", bc_ok?"T":"F",
                          
                                 g_ze_ok?"T":"F", over_state==OK||over_state==READY?"T":"F", cool_ok?"T":"F", perbar_ok?"T":"F",
                                          ZE_GateModeToString(InpZE_Gate));
      PrintFormat("%s trigger=%s side=%s conf=%.0f/%.0f/20 gates={%s}", EVT_ENTRY_CHECK, trigger,
                  direction > 0 ? "BUY" : "SELL", conf_raw, conf_eff, gates_summary);
      if(TryOpenPosition(direction, conf_raw, conf_eff, (int)sbReason, g_ze_strength))
      {
         if(trigger == "bootstrap") g_bootstrap_done = true;
         if(trigger == "pullback") g_ox.armed = false;
      }
   }
}
//+------------------------------------------------------------------+
//| Attempts to open a trade and returns true on success             |
//+------------------------------------------------------------------+
bool TryOpenPosition(int signal, double conf_raw, double conf_eff, int reason_code, double ze_strength)
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
   const double buf_price = InpSL_Buffer_Points * point;
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
   if(signal > 0){ 
      sl = NormalizeDouble(entry - sl_dist, digs);
      if(InpExit_FixedRR) tp = NormalizeDouble(entry + InpFixed_RR * (entry - sl), digs);
      else tp = 0;
      // TP managed by partials/trail
   }
   else if(signal < 0){ 
      sl = NormalizeDouble(entry + sl_dist, digs);
      if(InpExit_FixedRR) tp = NormalizeDouble(entry - InpFixed_RR * (sl - entry), digs);
      else tp = 0;
      // TP managed by partials/trail
   }

   PrintFormat("%s side=%s bid=%.5f ask=%.5f entry=%.5f pip=%.5f minStop=%.5f buf=%dp(%.5f) sl=%.5f tp=%.5f",
               DBG_STOPS, signal > 0 ? "BUY" : "SELL", t.bid, t.ask, entry, pip_size, min_stop_dist,
               InpSL_Buffer_Points, buf_price, sl, tp);
   bool ok_side = (signal > 0) ? (sl < entry) : (entry < sl);
   if (tp != 0) ok_side &= (signal > 0) ? (entry < tp) : (tp < entry);
   bool ok_dist = (MathAbs(entry - sl) >= min_stop_dist);
   if(tp != 0) ok_dist &= (MathAbs(tp - entry) >= min_stop_dist);
   if(!ok_side || !ok_dist){
      if(g_lastBarTime != g_last_suppress_log_time){
         PrintFormat("%s reason=stops_invalid details=side:%s entry:%.5f sl:%.5f tp:%.5f", EVT_SUPPRESS, signal > 0 ? "BUY" : "SELL", entry, sl, tp);
         g_last_suppress_log_time = g_lastBarTime;
      }
      return false;
   }

   double lots_to_trade = CalculateLotSize((int)conf_eff, MathAbs(entry - sl));
   if(lots_to_trade < MinLotSize) return false;
   string signal_str = (signal == 1) ? "BUY" : "SELL";
   string comment = StringFormat("AAI|%d|%d|%.2f|%.5f|%.5f",
                                 (int)conf_eff, reason_code, ze_strength, sl, tp);

   if(ExecutionMode == AutoExecute){
      // --- HYBRID APPROVAL INTERCEPTION ---
      g_last_side      = signal_str;
      g_last_entry     = entry; 
      g_last_sl        = sl; 
      g_last_tp        = tp; 
      g_last_vol       = lots_to_trade;
      g_last_rr        = InpExit_FixedRR ? InpFixed_RR : InpPartial_R_multiple;
      g_last_conf_raw  = conf_raw;
      g_last_conf_eff  = conf_eff;
      g_last_ze        = ze_strength;
      g_last_comment   = comment;

      if(InpHybrid_RequireApproval)
      {
         if(EmitIntent(g_last_side, g_last_entry, g_last_sl, g_last_tp, g_last_vol,
                       g_last_rr, g_last_conf_raw, g_last_conf_eff, g_last_ze))
            return false; // Return false because trade is NOT placed yet. It waits for approval.
         else
            return false; // Failed to emit intent, so don't proceed.
      }
      
      // --- ORIGINAL PLACEMENT LOGIC (if not in HYBRID mode) ---
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
   // If not using Fixed RR, manage partials
   if(!InpExit_FixedRR) { 
      HandlePartialProfits();
      if(!PositionSelect(_Symbol)) return;
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
      // apply SL only;
      // keep TP unchanged
      trade.PositionModify(_Symbol, sl, tp);
   }
}

//+------------------------------------------------------------------+
//| Helper to get pip size                                           |
//+------------------------------------------------------------------+
double AAI_Pip() { return (_Digits==3 || _Digits==5) ? 10*_Point : _Point; }

//+------------------------------------------------------------------+
//| Unified SL updater                                               |
//+------------------------------------------------------------------+
bool AAI_ApplyBEAndTrail(const ENUM_POSITION_TYPE side, const double entry_price, double &sl_io)
{
   // Do not manage exits if using fixed RR
   if(InpExit_FixedRR) return false;
   const double pip = AAI_Pip();
   const double bid = SymbolInfoDouble(_Symbol, SYMBOL_BID);
   const double ask = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
   const bool   is_long = (side==POSITION_TYPE_BUY);
   const double px     = is_long ? bid : ask;
   const double move_p = is_long ? (px - entry_price) : (entry_price - px);
   const double move_pips = move_p / pip;
   bool changed=false;
   
   // --- 1) Break-even snap (one-shot tighten; based on partial profit R multiple)
   double initial_risk_pips = 0;
   string comment = PositionGetString(POSITION_COMMENT);
   string parts[];
   if(StringSplit(comment, '|', parts) >= 6) {
       double sl_price = StringToDouble(parts[4]);
       initial_risk_pips = MathAbs(entry_price - sl_price) / PipSize();
   }
   if(InpPartial_R_multiple > 0 && move_pips >= initial_risk_pips * InpPartial_R_multiple)
   {
      double be_target = entry_price + (is_long ? +1 : -1) * InpBE_Offset_Points * _Point;
      if( (is_long && (sl_io < be_target)) || (!is_long && (sl_io > be_target)) )
      {
         sl_io = be_target;
         changed = true;
      }
   }

   // --- 2) Trailing (after start; never loosen; respects BE already set)
   if(InpTrail_Start_Pips > 0 && move_pips >= InpTrail_Start_Pips && InpTrail_Stop_Pips > 0)
   {
      double trail_target = px - (is_long ? InpTrail_Stop_Pips : -InpTrail_Stop_Pips) * pip;
      if( (is_long && (trail_target > sl_io)) || (!is_long && (trail_target < sl_io)) )
      {
         sl_io = trail_target;
         changed = true;
      }
   }
   return changed;
}


//+------------------------------------------------------------------+
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
   if(current_profit_pips >= initial_risk_pips * InpPartial_R_multiple)
   {
      ulong ticket = PositionGetInteger(POSITION_TICKET);
      double volume = PositionGetDouble(POSITION_VOLUME);
      double close_volume = volume * (InpPartial_Pct / 100.0);
      double lot_step = SymbolInfoDouble(symbolName, SYMBOL_VOLUME_STEP);
      close_volume = round(close_volume / lot_step) * lot_step;
      if(close_volume < lot_step) return;
      if(trade.PositionClosePartial(ticket, close_volume))
      {
          double be_sl_price = open_price + ((type == POSITION_TYPE_BUY) ? InpBE_Offset_Points * _Point : -InpBE_Offset_Points * _Point);
          if(trade.PositionModify(ticket, be_sl_price, PositionGetDouble(POSITION_TP)))
          {
             MqlTradeRequest req;
             MqlTradeResult res; ZeroMemory(req);
             req.action = TRADE_ACTION_MODIFY; req.position = ticket;
             req.sl = be_sl_price; req.tp = PositionGetDouble(POSITION_TP);
             req.comment = comment + "|P1";
             if(!OrderSend(req, res)) PrintFormat("%s Failed to send position modify request. Error: %d", EVT_PARTIAL, GetLastError());
          }
      }
   }
}

//+------------------------------------------------------------------+
//| Trailing Stop (Legacy - logic merged into AAI_ApplyBEAndTrail)   |
//+------------------------------------------------------------------+
void HandleTrailingStop(ulong ticket,long type,double openP,double currSL,double currPrice,bool overnight)
{
    // This function is kept for historical reference but is superseded by AAI_ApplyBEAndTrail
    return;
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
void JournalClosedPosition(ulong position_id)
{
   if(!HistorySelectByPosition(position_id)) return;

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
   string   bc_mode = EnumToString(InpBC_AlignMode);
   
   for(int i=0; i<HistoryDealsTotal(); i++)
   {
      ulong deal_ticket = HistoryDealGetTicket(i);
      profit += HistoryDealGetDouble(deal_ticket, DEAL_PROFIT) + HistoryDealGetDouble(deal_ticket, DEAL_COMMISSION) + HistoryDealGetDouble(deal_ticket, DEAL_SWAP);
      if(HistoryDealGetInteger(deal_ticket, DEAL_ENTRY) == DEAL_ENTRY_IN)
      {
         if(entry_price == 0)
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
      else
      {
         timestamp_close = (datetime)HistoryDealGetInteger(deal_ticket, DEAL_TIME);
         exit_price = HistoryDealGetDouble(deal_ticket, DEAL_PRICE);
      }
   }

   if(symbol == "") return;

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
                                 symbol, side, lots, entry_price, sl_price, tp_price, exit_price,
               
                                  profit, profit_points, rr, conf, reason, ze_strength, bc_mode);
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
