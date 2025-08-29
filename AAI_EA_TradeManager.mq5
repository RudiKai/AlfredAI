//+------------------------------------------------------------------+
//|                     AAI_EA_TradeManager.mq5                      |
//|             v3.42 - Hardened Gates & Unified Modules             |
//|                                                                  |
//| (Takes trade signals from AAI_Indicator_SignalBrain)             |
//|                                                                  |
//| Copyright 2025, AlfredAI Project                                 |
//+------------------------------------------------------------------+
#property strict
#property version   "3.42"
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
#define DBG_SPD   "[DBG_SPD]"
#define DBG_OVER  "[DBG_OVER]"
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

// ===================== AAI UTILS (idempotent) =======================
#ifndef AAI_UTILS_DEFINED
#define AAI_UTILS_DEFINED
// Safe 1-value reader
inline bool AAI_ReadOne(const int handle, const int buf, const int shift, double &out)
{
   if(handle == INVALID_HANDLE){ out = 0.0; return false; }
   double tmp[1];
   if(CopyBuffer(handle, buf, shift, 1, tmp) == 1){ out = tmp[0]; return true; }
   out = 0.0; return false;
}

// ZE buffer auto-detect (prefers 0..10 scale, non-empty)
int AAI_ZE_AutoDetectBuffer(const int handle, const int shift)
{
   if(handle == INVALID_HANDLE) return 0;
   double tmp[1]; int best=0; double bestScore=-1.0;
   for(int b=0; b<8; ++b)
     if(CopyBuffer(handle, b, shift, 1, tmp) == 1)
     {
        const double v = tmp[0];
        double score = (v!=EMPTY_VALUE ? 0.0 : -1.0);
        if(v>=0.0 && v<=10.0) score += 2.0;
        if(v>0.0)             score += 0.5;
        if(score>bestScore){ bestScore=score; best=b; }
     }
   return best;
}

// Fallback for printing ZE gate nicely
string ZE_GateToStr(int gate)
{
   switch(gate){
      case 0: return "ZE_OFF";
      case 1: return "ZE_PREFERRED";
      case 2: return "ZE_REQUIRED";
   }
   return "ZE_?";
}
#endif


// HYBRID toggle + timeout
input bool InpHybrid_RequireApproval = true;
input int  InpHybrid_TimeoutSec      = 600;
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
input bool SB_PassThrough_UseBC      = true;
input int  SB_PassThrough_WarmupBars = 150;
input int  SB_PassThrough_FastMA     = 10;
input int  SB_PassThrough_SlowMA     = 30;
input int  SB_PassThrough_MinZoneStrength = 4;
input bool SB_PassThrough_EnableDebug = true;

//--- Risk Management Inputs ---
input group "Risk Management (M15 Baseline)"
input double   InpRiskPct           = 0.25;
input double   MinLotSize           = 0.01;
input double   MaxLotSize           = 10.0;
input int      InpSL_Buffer_Points  = 10;

//--- Trade Management Inputs ---
input group "Trade Management (M15 Baseline)"
input bool     PerBarDebounce       = true;
input uint     DuplicateGuardMs     = 300;
input int      CooldownAfterSLBars  = 2;
input int      MaxSlippagePoints    = 10;
input int      FridayCloseHour      = 22;
input bool     EnableLogging        = true;

//--- Session Inputs (idempotent) ---
#ifndef AAI_SESSION_INPUTS_DEFINED
#define AAI_SESSION_INPUTS_DEFINED
input bool SessionEnable = true;
input int  SessionStartHourServer = 9;   // server time
input int  SessionEndHourServer   = 23;  // server time
#endif

#ifndef AAI_HYBRID_INPUTS_DEFINED
#define AAI_HYBRID_INPUTS_DEFINED
// Auto-trading window (server time). Outside -> alerts only.
input string AutoHourRanges = "8-14,19-23";    // comma-separated hour ranges
// Day mask for auto-trading (server time): Sun=0..Sat=6
input bool AutoSun=false, AutoMon=true, AutoTue=true, AutoWed=false, AutoThu=true, AutoFri=true, AutoSat=false;

// Alert channels + throttle
input bool  HybridAlertPopup       = true;
input bool  HybridAlertPush        = true;     // requires terminal Push enabled
input bool  HybridAlertWriteIntent = true;     // write intent file under g_dir_intent
input int   HybridAlertThrottleSec = 60;       // min seconds between alerts for the same bar
#endif

//--- Adaptive Spread Inputs (idempotent) ---
#ifndef AAI_SPREAD_INPUTS_DEFINED
#define AAI_SPREAD_INPUTS_DEFINED
input int MaxSpreadPoints            = 30; // hard cap
input int SpreadMedianWindowTicks    = 120;
input int SpreadHeadroomPoints       = 5;  // allow median + headroom
#endif
////////////// 
#ifndef AAI_STR_TRIM_DEFINED
#define AAI_STR_TRIM_DEFINED
void AAI_Trim(string &s)
{
   StringTrimLeft(s);
   StringTrimRight(s);
}
#endif
//////////
//--- Exit Strategy Inputs (M15 Baseline) ---
input group "Exit Strategy"
input bool     InpExit_FixedRR        = true;
input double   InpFixed_RR            = 1.6;
input double   InpPartial_Pct         = 50.0;
input double   InpPartial_R_multiple  = 1.0;
input int      InpBE_Offset_Points    = 1;
input int      InpTrail_Start_Pips    = 22;
input int      InpTrail_Stop_Pips     = 10;

//--- Entry Filter Inputs (M15 Baseline) ---
input group "Entry Filters"
input int        InpMinConfidence        = 10;
input bool       InpOver_SoftWait        = true;
input int        InpMaxOverextPips       = 22;
input int        InpPullbackBarsMin      = 5;
input int        InpPullbackBarsMax      = 8;
input int        InpATR_MinPips          = 18;
input int        InpATR_MaxPips          = 40;
input int        OverextMAPeriod         = 12;

//--- Over-extension ATR Normalization (idempotent) ---
#ifndef AAI_OVER_INPUTS_DEFINED
#define AAI_OVER_INPUTS_DEFINED
input bool   OverextUseATR          = true;
input int    OverextATRPeriod       = 14;   // reuse if you already have ATR handle
input double OverextATR_Threshold   = 1.20; // dist/ATR in pips
#endif

//--- Confluence Module Inputs (M15 Baseline) ---
input group "Confluence Modules"
input ENUM_BC_ALIGN_MODE InpBC_AlignMode   = BC_PREFERRED;
input ENUM_ZE_GATE_MODE  InpZE_Gate        = ZE_PREFERRED;
input int        InpZE_MinStrength       = 4;
input int        InpZE_PrefBonus         = 3;
input int        InpZE_BufferIndexStrength = 0; // -1 for auto-detect
input int        InpZE_ReadShift         = 1;
input bool       ZE_TelemetryEnabled     = true;

//--- Journaling Inputs ---
input group "Journaling"
input bool     EnableJournaling     = true;
input string   JournalFileName      = "AlfredAI_Journal.csv";
input bool     JournalUseCommonFiles = true;

// ===================== AAI ZE GLOBALS (idempotent) =====================
#ifndef AAI_ZE_GLOBALS_DEFINED
#define AAI_ZE_GLOBALS_DEFINED
int g_ze_handle = INVALID_HANDLE;
int g_ze_buf_eff = 0;   // effective ZE buffer we read (auto or manual)
#endif

// ===================== AAI SMC GLOBALS (idempotent) ====================
#ifndef AAI_SMC_GLOBALS_DEFINED
#define AAI_SMC_GLOBALS_DEFINED
int g_smc_handle = INVALID_HANDLE;
enum SMCMode { SMC_OFF=0, SMC_PREFERRED=1, SMC_REQUIRED=2 };
input SMCMode InpSMC_Mode = SMC_PREFERRED;
input int     InpSMC_MinConfidence = 7;
input int     SMC_PREFERRED_BONUS = 1;
input bool    InpSMC_EnableDebug   = true;
// Pass-through to AAI_Indicator_SMC
input bool    SMC_UseFVG       = true;
input bool    SMC_UseOB        = true;
input bool    SMC_UseBOS       = true;
input int     SMC_WarmupBars   = 100;
input double  SMC_FVG_MinPips  = 1.0;
input int     SMC_OB_Lookback  = 20;
input int     SMC_BOS_Lookback = 50;
// Counter for TEST_SUMMARY
int g_blk_smc = 0;
#endif

// ===================== AAI SPREAD GLOBALS (idempotent) ================
#ifndef AAI_SPREAD_STATE_DEFINED
#define AAI_SPREAD_STATE_DEFINED
int  g_spr_buf[256];           // power-of-two ≥ window
int  g_spr_idx = 0;
int  g_spr_cnt = 0;
const int g_spr_cap = 256;
#endif

//--- Globals
CTrade    trade;
string    symbolName;
double    point;
static ulong g_logged_positions[];
int       g_logged_positions_total = 0;
static OverextArm g_ox;
// --- Persistent Indicator Handles ---
int sb_handle = INVALID_HANDLE;
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

// --- Block counters ---
int g_blk_conf = 0;
int g_blk_ze = 0;
int g_blk_bc = 0;
int g_blk_over = 0;
int g_blk_sess = 0;
int g_blk_spd = 0;
int g_blk_atr = 0;
int g_blk_cool = 0;
int g_blk_bar = 0;
int g_blk_no = 0;

// --- Once-per-bar stamps for block counters ---
datetime g_stamp_conf  = 0;
datetime g_stamp_ze    = 0;
datetime g_stamp_bc    = 0;
datetime g_stamp_over  = 0;
datetime g_stamp_sess  = 0;
datetime g_stamp_spd   = 0;
datetime g_stamp_atr   = 0;
datetime g_stamp_cool  = 0;
datetime g_stamp_bar   = 0;
datetime g_stamp_smc   = 0;
datetime g_stamp_none  = 0;

#ifndef AAI_HYBRID_STATE_DEFINED
#define AAI_HYBRID_STATE_DEFINED
bool g_auto_hour_mask[24];
datetime g_hyb_last_alert_bar = 0;
datetime g_hyb_last_alert_ts  = 0;
int g_blk_hyb = 0;            // count "alert-only" bars
datetime g_stamp_hyb = 0;     // once-per-bar stamp
#endif

bool g_test_summary_printed = false;


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
   int q=StringFind(json,"\"",p);
   if(q<0) return "";
   return StringSubstr(json, p, q-p);
}

#ifndef AAI_HYBRID_UTILS_DEFINED
#define AAI_HYBRID_UTILS_DEFINED
void AAI_ParseHourRanges(const string ranges, bool &mask[])
{
   ArrayInitialize(mask,false);
   string parts[]; int n=StringSplit(ranges, ',', parts);
   for(int i=0;i<n;i++){
      string p = parts[i];
AAI_Trim(p);
if(StringLen(p)==0) continue;
      int dash=StringFind(p,"-");
      if(dash<0){ int h=(int)StringToInteger(p)%24; if(h>=0) mask[h]=true; continue; }
      int a=(int)StringToInteger(StringSubstr(p,0,dash));
      int b=(int)StringToInteger(StringSubstr(p,dash+1));
      a=(a%24+24)%24; b=(b%24+24)%24;
      if(a<=b){ for(int h=a;h<=b;h++) mask[h]=true; }
      else    { for(int h=a;h<24;h++) mask[h]=true; for(int h=0;h<=b;h++) mask[h]=true; }
   }
}
bool AAI_HourDayAutoOK()
{
   MqlDateTime dt; TimeToStruct(TimeTradeServer(), dt);
   bool day_ok = ( (dt.day_of_week==0 && AutoSun) || (dt.day_of_week==1 && AutoMon) || (dt.day_of_week==2 && AutoTue) ||
                   (dt.day_of_week==3 && AutoWed) || (dt.day_of_week==4 && AutoThu) || (dt.day_of_week==5 && AutoFri) ||
                   (dt.day_of_week==6 && AutoSat) );
   bool hour_ok = g_auto_hour_mask[dt.hour];
   return (day_ok && hour_ok);
}
void AAI_RaiseHybridAlert(const string side, const double conf_eff, const double ze_strength,
                          const double smc_conf, const int spread_pts,
                          const double atr_pips, const double entry, const double sl, const double tp)
{
   // once-per-bar throttle
   if(g_lastBarTime==g_hyb_last_alert_bar)
   {
      if((TimeCurrent() - g_hyb_last_alert_ts) < HybridAlertThrottleSec) return;
   }
   g_hyb_last_alert_bar = g_lastBarTime;
   g_hyb_last_alert_ts  = TimeCurrent();

   string msg = StringFormat("[HYBRID_ALERT] %s %s conf=%.1f ZE=%.1f SMC=%.1f spr=%d atr=%.1fp @%.5f SL=%.5f TP=%.5f",
                              _Symbol, side, conf_eff, ze_strength, smc_conf, spread_pts, atr_pips, entry, sl, tp);
   if(HybridAlertPopup) Alert(msg);
   if(HybridAlertPush)  SendNotification(msg);

   if(HybridAlertWriteIntent)
   {
      // write a simple intent file for your existing hybrid workflow
      string fn = StringFormat("%s\\%s_%s_%I64d.txt", g_dir_intent, _Symbol, side, (long)g_lastBarTime);
      int h = FileOpen(fn, FILE_WRITE|FILE_TXT|FILE_ANSI);
      if(h!=INVALID_HANDLE){
         FileWrite(h, msg);
         FileClose(h);
      }
   }
}
#endif


//+------------------------------------------------------------------+
//| Centralized block counting and logging                           |
//+------------------------------------------------------------------+
void AAI_Block(const string reason)
{
   string r = reason;
   StringToLower(r);

   // choose target counter + stamp by reason
   if(StringFind(r, "over") == 0)
   {
      if(g_stamp_over != g_lastBarTime){ ++g_blk_over; g_stamp_over = g_lastBarTime; }
   }
   else if(r == "confidence")
   {
      if(g_stamp_conf != g_lastBarTime){ ++g_blk_conf; g_stamp_conf = g_lastBarTime; }
   }
   else if(r == "ze_gate")
   {
      if(g_stamp_ze != g_lastBarTime){ ++g_blk_ze; g_stamp_ze = g_lastBarTime; }
   }
   else if(r == "bc")
   {
      if(g_stamp_bc != g_lastBarTime){ ++g_blk_bc; g_stamp_bc = g_lastBarTime; }
   }
   else if(r == "session")
   {
      if(g_stamp_sess != g_lastBarTime){ ++g_blk_sess; g_stamp_sess = g_lastBarTime; }
   }
   else if(r == "spread")
   {
      if(g_stamp_spd != g_lastBarTime){ ++g_blk_spd; g_stamp_spd = g_lastBarTime; }
   }
   else if(r == "cooldown")
   {
      if(g_stamp_cool != g_lastBarTime){ ++g_blk_cool; g_stamp_cool = g_lastBarTime; }
   }
   else if(r == "same_bar")
   {
      if(g_stamp_bar != g_lastBarTime){ ++g_blk_bar; g_stamp_bar = g_lastBarTime; }
   }
   else if(r == "atr")
   {
      if(g_stamp_atr != g_lastBarTime){ ++g_blk_atr; g_stamp_atr = g_lastBarTime; }
   }
   else if(r == "smc")
   {
      if(g_stamp_smc != g_lastBarTime){ ++g_blk_smc; g_stamp_smc = g_lastBarTime; }
   }
   else if(r == "hybrid")
   {
      if(g_stamp_hyb != g_lastBarTime){ ++g_blk_hyb; g_stamp_hyb = g_lastBarTime; }
   }
   else
   {
      if(g_stamp_none != g_lastBarTime){ ++g_blk_no; g_stamp_none = g_lastBarTime; }
   }

   PrintFormat("%s reason=%s", AAI_BLOCK_LOG, reason);
}


//+------------------------------------------------------------------+
//| Compute effective confidence (ZE bonus first), return pass/fail  |
//+------------------------------------------------------------------+
bool AAI_ComputeConfidence(double sb_conf, bool ze_ok, double &conf_raw, double &conf_eff)
{
   conf_raw = sb_conf;
   conf_eff = conf_raw;

   if(InpZE_Gate == ZE_PREFERRED && ze_ok)
      conf_eff += InpZE_PrefBonus;
      
   bool gate_conf = (conf_eff >= InpMinConfidence);

   if(g_lastBarTime != g_last_suppress_log_time) // Avoid log spam
   {
      PrintFormat("[DBG_CONF] raw=%.1f ze_ok=%s bonus=%d eff=%.1f thr=%.1f",
                  conf_raw,
                  (ze_ok ? "T" : "F"),
                  (int)((InpZE_Gate == ZE_PREFERRED && ze_ok) ? InpZE_PrefBonus : 0),
                  conf_eff, (double)InpMinConfidence);
   }
   return gate_conf;
}

//+------------------------------------------------------------------+
//| Pip Math Helpers                                                 |
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

//+------------------------------------------------------------------+
//| Safe updater for ZoneEngine strength                             |
//+------------------------------------------------------------------+
void AAI_UpdateZE()
{
   g_ze_strength = 0.0; // Default to no strength
   bool ze_ok_read = AAI_ReadOne(g_ze_handle, g_ze_buf_eff, InpZE_ReadShift, g_ze_strength);
   
   if(ZE_TelemetryEnabled && g_lastBarTime != g_last_suppress_log_time)
   {
      string ts = TimeToString(iTime(_Symbol, (ENUM_TIMEFRAMES)SignalTimeframe, InpZE_ReadShift));
      PrintFormat("[DBG_ZE] t=%s strength=%.1f (read_ok=%s)", ts, g_ze_strength, ze_ok_read ? "T" : "F");
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
    g_blk_spd = 0; g_blk_cool = 0; g_blk_bar = 0; g_blk_no = 0; g_blk_atr = 0;
    g_blk_smc = 0; g_blk_hyb = 0;
}

void AAI_PrintTestSummaryOnce()
{
    if(g_test_summary_printed) return;
    g_test_summary_printed = true;
    PrintFormat("[TEST_SUMMARY] conf=%d ze=%d bc=%d over=%d sess=%d spd=%d cool=%d bar=%d smc=%d hyb=%d none=%d",
                g_blk_conf,g_blk_ze,g_blk_bc,g_blk_over,g_blk_sess,g_blk_spd,g_blk_cool,g_blk_bar,g_blk_smc,g_blk_hyb,g_blk_no);
}

//+------------------------------------------------------------------+
//| Expert initialization                                            |
//+------------------------------------------------------------------+
int OnInit()
{
   AAI_ResetBlockCounters();
   g_test_summary_printed = false;

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

   // ---- ZoneEngine handle + effective buffer ----
   if(g_ze_handle == INVALID_HANDLE)
      g_ze_handle = iCustom(_Symbol, SignalTimeframe, "AAI_Indicator_ZoneEngine");
   
   g_ze_buf_eff = (InpZE_BufferIndexStrength < 0
                  ? AAI_ZE_AutoDetectBuffer(g_ze_handle, InpZE_ReadShift)
                  : InpZE_BufferIndexStrength);
                  
   PrintFormat("[INIT] ZE gate=%s buf=%d shift=%d min=%.1f bonus=%d handle=%d",
               ZE_GateToStr((int)InpZE_Gate), g_ze_buf_eff, InpZE_ReadShift,
               (double)InpZE_MinStrength, InpZE_PrefBonus, g_ze_handle);

   // ---- SMC handle ----
   if(InpSMC_Mode != SMC_OFF && g_smc_handle == INVALID_HANDLE)
      g_smc_handle = iCustom(_Symbol, SignalTimeframe, "AAI_Indicator_SMC",
                             SMC_UseFVG, SMC_UseOB, SMC_UseBOS,
                             SMC_WarmupBars, SMC_FVG_MinPips, SMC_OB_Lookback, SMC_BOS_Lookback);

   if(sb_handle == INVALID_HANDLE){ Print("[ERR] SB iCustom handle invalid"); return(INIT_FAILED); }

   PrintFormat("%s EntryMode=%s", EVT_INIT, EnumToString(EntryMode));
   PrintFormat("%s EA→SB args: SafeTest=%c UseZE=%c UseBC=%c Warmup=%d | sb_handle=%d",
               EVT_INIT, SB_PassThrough_SafeTest ? 'T' : 'F', useZE ? 'T' : 'F',
               useBC ? 'T' : 'F', SB_PassThrough_WarmupBars, sb_handle);
               
   g_hATR = iATR(_Symbol, _Period, OverextATRPeriod);
   if(g_hATR == INVALID_HANDLE){ Print("[ERR] Failed to create ATR indicator handle"); return(INIT_FAILED); }

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

   AAI_ParseHourRanges(AutoHourRanges, g_auto_hour_mask);
if(EnableLogging){
   string hrs=""; int cnt=0;
   for(int h=0;h<24;++h){ if(g_auto_hour_mask[h]){ ++cnt; hrs += IntegerToString(h) + " "; } }
   PrintFormat("[HYBRID_INIT] AutoHourRanges='%s' hours_on=%d [%s]", AutoHourRanges, cnt, hrs);
}


   return(INIT_SUCCEEDED);
}


void OnTesterDeinit() { AAI_PrintTestSummaryOnce(); }

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
   if(g_smc_handle != INVALID_HANDLE) IndicatorRelease(g_smc_handle);
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

  string fn_rel = g_dir_intent + "\\intent_" + g_pending_id + ".json";
  string json = StringFormat(
    "{\"id\":\"%s\",\"symbol\":\"%s\",\"timeframe\":\"%s\",\"side\":\"%s\","
    "\"entry\":%.5f,\"sl\":%.5f,\"tp\":%.5f,\"volume\":%.2f,"
    "\"rr_target\":%.2f,\"conf_raw\":%.2f,\"conf_eff\":%.2f,\"ze_strength\":%.2f,"
    "\"created_ts\":\"%s\"}",
    g_pending_id, _Symbol, EnumToString(_Period), side,
    entry, sl, tp, volume, rr_target, conf_raw, conf_eff, ze_strength,
    TimeToString(TimeCurrent(), TIME_DATE|TIME_MINUTES)
  );
  
  if(WriteText(fn_rel, json))
  {
    string root = TerminalInfoString(TERMINAL_DATA_PATH) + "\\MQL5\\Files\\";
    PrintFormat("[HYBRID] intent written at: %s%s", root, fn_rel);
    string cmd_rel = g_dir_cmds + "\\cmd_" + g_pending_id + ".json";
    PrintFormat("[HYBRID] waiting for cmd at: %s%s", root, cmd_rel);
    return true;
  }
  return false;
}

//+------------------------------------------------------------------+
//| HYBRID: Execute order after approval                             |
//+------------------------------------------------------------------+
void PlaceOrderFromApproval()
{
    PrintFormat("[HYBRID] Executing approved trade. Side: %s, Vol: %.2f, Entry: Market, SL: %.5f, TP: %.5f",
                g_last_side, g_last_vol, g_last_sl, g_last_tp);
    trade.SetDeviationInPoints(MaxSlippagePoints);
    bool order_sent = false;
    
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

  if((TimeCurrent() - g_pending_ts) > InpHybrid_TimeoutSec){
    Print("[HYBRID] intent timeout, discarding: ", g_pending_id);
    g_pending_id = "";
    return;
  }

  string cmd_rel = g_dir_cmds + "\\cmd_" + g_pending_id + ".json";
  static string last_id_printed = "";
  if(last_id_printed != g_pending_id){
    string root = TerminalInfoString(TERMINAL_DATA_PATH) + "\\MQL5\\Files\\";
    PrintFormat("[HYBRID] polling cmd: %s%s", root, cmd_rel);
    last_id_printed = g_pending_id;
  }

  if(!FileIsExist(cmd_rel)) return;

  string s = ReadAll(cmd_rel);
  if(s==""){ FileDelete(cmd_rel); return; }

  string id     = JsonGetStr(s, "id");
  string action = JsonGetStr(s, "action"); 
  StringToLower(action);
  if(id != g_pending_id) return;

  if(action=="approve"){
    Print("[HYBRID] APPROVED: ", id);
    PlaceOrderFromApproval();
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
           
           if (closing_deal_type == DEAL_TYPE_SELL)
           {
               g_cool_until_buy = cooldown_end_time;
               PrintFormat("%s SL close side=BUY pause=%d bars until %s", EVT_COOLDOWN, CooldownAfterSLBars, TimeToString(g_cool_until_buy));
           }
           else if (closing_deal_type == DEAL_TYPE_BUY)
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
   
   // --- Update adaptive spread buffer ---
   int curSpr = (int)SymbolInfoInteger(_Symbol, SYMBOL_SPREAD); // in points
   g_spr_buf[g_spr_idx] = curSpr;
   g_spr_idx = (g_spr_idx + 1) & (g_spr_cap - 1);
   if(g_spr_cnt < g_spr_cap) g_spr_cnt++;

   if(PositionSelect(_Symbol))
   {
      MqlDateTime dt;
      TimeToStruct(TimeCurrent(), dt);
      ManageOpenPositions(dt, false); // IsTradingSession check is now inside CheckForNewTrades
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

   datetime bar_time = iTime(_Symbol, _Period, 0);
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

   AAI_ReadOne(sb_handle, SB_BUF_SIGNAL, readShift, sbSig_curr);
   if(!AAI_ReadOne(sb_handle, SB_BUF_SIGNAL, readShift + 1, sbSig_prev)) sbSig_prev = sbSig_curr;
   AAI_ReadOne(sb_handle, SB_BUF_CONF, readShift, sbConf);
   AAI_ReadOne(sb_handle, SB_BUF_REASON, readShift, sbReason);
   
   int direction = (sbSig_curr > 0) ? 1 : (sbSig_curr < 0 ? -1 : 0);

   // --- Session Gate (Server Time) ---
   bool sess_ok = true;
   if(SessionEnable)
   {
      MqlDateTime dt;
      TimeToStruct(TimeTradeServer(), dt);
      const int hh = dt.hour;
   
      // If start == end, treat as 24h window (optional)
      if(SessionStartHourServer == SessionEndHourServer)
         sess_ok = true;
      else
         sess_ok = (SessionStartHourServer <= SessionEndHourServer)
                 ? (hh >= SessionStartHourServer && hh < SessionEndHourServer)
                 : (hh >= SessionStartHourServer || hh < SessionEndHourServer);
   }
   if(!sess_ok) { AAI_Block("session"); return; }
   
   // --- Adaptive Spread Gate ---
   int curSpr = (int)SymbolInfoInteger(_Symbol, SYMBOL_SPREAD); // points
   int n = MathMin(SpreadMedianWindowTicks, g_spr_cnt);
   int lim = MaxSpreadPoints;
   if(n >= 9) // wait a few ticks for buffer to populate
   {
      static int tmp[256];
      for(int i=0;i<n;i++) tmp[i]=g_spr_buf[(g_spr_idx - 1 - i + g_spr_cap) & (g_spr_cap - 1)];

      // MQL5's ArraySort doesn't support sorting a sub-array.
      // To avoid heap allocation (dynamic arrays), we sort the first 'n' elements manually.
      // Insertion sort is efficient for the small 'n' values we expect here.
      for(int j=1; j<n; j++)
      {
         int key = tmp[j];
         int i = j-1;
         while(i>=0 && tmp[i]>key)
         {
            tmp[i+1] = tmp[i];
            i--;
         }
         tmp[i+1] = key;
      }
      
      int spr_med = tmp[n/2];
      lim = MathMax(MaxSpreadPoints, spr_med + SpreadHeadroomPoints);
   }
   bool spread_ok = (curSpr <= lim);
   if(!spread_ok) { AAI_Block("spread"); return; }

   AAI_UpdateZE();
   
   if(direction == 0) return;
   
   double atr_val=0, fast_ma_val=0, close_price=0;
   AAI_ReadOne(g_hATR, 0, readShift, atr_val);
   AAI_ReadOne(g_hOverextMA, 0, readShift, fast_ma_val);
   
   MqlRates rates[1];
   if(CopyRates(_Symbol, _Period, readShift, 1, rates) > 0) close_price = rates[0].close;
   
   const double pip = PipSize();
   
   if(InpZE_Gate == ZE_REQUIRED || InpZE_Gate == ZE_PREFERRED)
      g_ze_ok = (g_ze_strength >= InpZE_MinStrength);
   else
      g_ze_ok = true;
      
   double conf_raw = 0.0, conf_eff = 0.0;
   AAI_ComputeConfidence(sbConf, g_ze_ok, conf_raw, conf_eff);

   // --- SMC Gating & Bonus ---
   if(InpSMC_Mode != SMC_OFF)
   {
      double smc_sig=0.0, smc_conf=0.0, smc_reason=0.0;
      AAI_ReadOne(g_smc_handle, 0, SB_ReadShift, smc_sig);
      AAI_ReadOne(g_smc_handle, 1, SB_ReadShift, smc_conf);
      AAI_ReadOne(g_smc_handle, 2, SB_ReadShift, smc_reason);
      bool smc_align = ((smc_sig > 0 && sbSig_curr > 0) || (smc_sig < 0 && sbSig_curr < 0));
      if(InpSMC_Mode == SMC_REQUIRED)
      {
         bool smc_ok = smc_align && (smc_conf >= InpSMC_MinConfidence);
         if(!smc_ok)
         {
            if(InpSMC_EnableDebug)
               PrintFormat("[AAI_BLOCK] reason=smc sig=%.0f conf=%.1f min=%d", smc_sig, smc_conf, InpSMC_MinConfidence);
            AAI_Block("smc");
            return;
         }
      }
      else if(InpSMC_Mode == SMC_PREFERRED)
      {
         if(smc_align && smc_conf >= InpSMC_MinConfidence)
            conf_eff += SMC_PREFERRED_BONUS;
      }
   }
   
   if(conf_eff < InpMinConfidence) { AAI_Block("confidence"); return; }

   bool atr_min_ok = (InpATR_MinPips == 0) || ((atr_val / pip) >= InpATR_MinPips);
   bool atr_max_ok = (InpATR_MaxPips == 0) || ((atr_val / pip) <= InpATR_MaxPips);
   bool atr_ok = atr_min_ok && atr_max_ok;
   
   bool bc_ok = true;
   if (InpBC_AlignMode != BC_OFF && SB_PassThrough_UseBC) {
       double htf_bias = 0;
       if (AAI_ReadOne(bc_handle, BC_BUF_HTF_BIAS, readShift, htf_bias)) {
           bool is_aligned = ((direction > 0 && htf_bias > 0) || (direction < 0 && htf_bias < 0));
           if(InpBC_AlignMode == BC_REQUIRED && !is_aligned) bc_ok = false;
       }
   }

   // --- Over-extension Gate (ATR-Normalized or Pips) ---
   ENUM_OVEREXT_STATE over_state = OK;
   bool over_ok_flag = true;
   if (OverextUseATR) {
      double atr_pips = atr_val / pip;
      double dist_pips = MathAbs(close_price - fast_ma_val) / pip;
      double over_norm = (atr_pips > 0.0 ? dist_pips / atr_pips : 999.0);
      over_ok_flag = (over_norm <= OverextATR_Threshold);
      //if(EnableLogging) PrintFormat("[DBG_OVER] dist=%.1fp atr=%.1fp norm=%.2f thr=%.2f", dist_pips, atr_pips, over_norm, OverextATR_Threshold);
   } else {
      double over_p = (fast_ma_val > 0 && close_price > 0) ? MathAbs(close_price - fast_ma_val) / pip : 0.0;
      over_ok_flag = (over_p <= InpMaxOverextPips);
   }
   
   if(!InpOver_SoftWait) {
       if(!over_ok_flag) over_state = BLOCK;
   } else {
       if(g_ox.armed) {
           datetime bar_event_time = iTime(_Symbol, _Period, readShift);
           if(direction != g_ox.side || bar_event_time > g_ox.until) { 
               over_state = TIMEOUT;
               g_ox.armed = false; 
           } else if(over_ok_flag) {
               over_state = READY;
           } else { 
               g_ox.bars_waited++;
               over_state = ARMED; 
           }
       } else {
           if(over_ok_flag) {
               over_state = OK;
           } else {
               g_ox.armed = true;
               g_ox.side  = direction;
               g_ox.until = iTime(_Symbol, _Period, readShift) + InpPullbackBarsMax * PeriodSeconds();
               g_ox.bars_waited = 0;
               over_state = ARMED;
           }
       }
   }
   
   int secs = PeriodSeconds();
   datetime current_bar_time = iTime(_Symbol, _Period, readShift);
   datetime until = (direction > 0) ? g_cool_until_buy : g_cool_until_sell;
   int delta = (int)(until - current_bar_time);
   int bars_left = (delta <= 0 || secs <= 0) ? 0 : ( (delta + secs - 1) / secs );
   bool cool_ok = (bars_left == 0);
   
   bool perbar_ok = !PerBarDebounce || ((direction > 0) ? (g_last_entry_bar_buy != current_bar_time) : (g_last_entry_bar_sell != current_bar_time));

   if(g_lastBarTime != g_last_suppress_log_time)
   {
      PrintFormat("[DBG_GATES] t=%s sig_curr=%d conf=%.0f/%.0f over=%s bc=%s smc=%s ze_ok=%s",
               TimeToString(current_bar_time),
               (int)sbSig_curr, conf_raw, conf_eff,
               EnumToString(over_state),
               EnumToString(InpBC_AlignMode),
               EnumToString(InpSMC_Mode),
               g_ze_ok ? "T" : "F");
   }
            
   if(!atr_ok) { AAI_Block("atr"); return; }
   if(!bc_ok) { AAI_Block("bc"); return; }
   if(InpZE_Gate == ZE_REQUIRED && !g_ze_ok) { AAI_Block("ze_gate"); return; }
   
   if(over_state == BLOCK) { AAI_Block("overext_block"); return; }
   if(over_state == ARMED) { AAI_Block("overext_armed"); return; }
   if(over_state == TIMEOUT) { AAI_Block("overext_timeout"); return; }

   string trigger = "";
   bool is_edge = ((int)sbSig_curr != (int)sbSig_prev);
   if(EntryMode == FirstBarOrEdge && !g_bootstrap_done) trigger = "bootstrap";
   else if(InpOver_SoftWait && over_state == READY) trigger = "pullback";
   else if(is_edge) trigger = "edge";

   if(trigger == "") { AAI_Block("no_trigger"); return; }
   if(!cool_ok) { AAI_Block("cooldown"); return; }
   if(!perbar_ok) { AAI_Block("same_bar"); return; }

   if(!PositionSelect(_Symbol))
   {
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
   
   double atr_val_raw = 0;
   AAI_ReadOne(g_hATR, 0, 1, atr_val_raw);
   const double sl_dist = atr_val_raw + (InpSL_Buffer_Points * _Point);

   double entry = (signal > 0) ? t.ask : t.bid;
   entry = NormalizeDouble(entry, digs);

   ulong now_ms = GetTickCount64();
   datetime current_bar_time = iTime(_Symbol, _Period, 1);
   string hash_str = StringFormat("%I64d|%d|%.*f", (long)current_bar_time, signal, digs, entry);
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
   }
   else if(signal < 0){ 
      sl = NormalizeDouble(entry + sl_dist, digs);
      if(InpExit_FixedRR) tp = NormalizeDouble(entry - InpFixed_RR * (sl - entry), digs);
      else tp = 0;
   }

   if(g_lastBarTime != g_last_suppress_log_time)
   {
      PrintFormat("%s side=%s bid=%.5f ask=%.5f entry=%.5f pip=%.5f minStop=%.5f atr=%.5f buf=%dp sl=%.5f tp=%.5f",
                  DBG_STOPS, signal > 0 ? "BUY" : "SELL", t.bid, t.ask, entry, pip_size, min_stop_dist,
                  atr_val_raw, InpSL_Buffer_Points, sl, tp);
   }
               
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
   string comment = StringFormat("AAI|%.1f|%d|%d|%.1f|%.5f|%.5f",
                                 conf_raw, (int)conf_eff, reason_code, ze_strength, sl, tp);
                                 
   // --- HYBRID HOURS SWITCH ---
   bool auto_ok = AAI_HourDayAutoOK();
   if(!auto_ok)
   {
      // Gather a few stats for the alert
      double smc_conf=0.0; if(g_smc_handle!=INVALID_HANDLE) AAI_ReadOne(g_smc_handle, 1, SB_ReadShift, smc_conf);
   
      int spread_pts = (int)SymbolInfoInteger(_Symbol, SYMBOL_SPREAD);
   
      double atr_val[1]; double atr_pips=0.0;
      if(CopyBuffer(g_hATR,0,SB_ReadShift,1,atr_val)==1) atr_pips = atr_val[0]/_Point/10.0;
   
      AAI_RaiseHybridAlert(signal_str, conf_eff, ze_strength, smc_conf, spread_pts, atr_pips, entry, sl, tp);
   
      // Do NOT send order outside the auto window
      AAI_Block("hybrid");  // new reason; counted once per bar
      return false;
   }
   // --- END HYBRID HOURS SWITCH ---
   
   if(ExecutionMode == AutoExecute){
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
            return false;
         else
            return false;
      }
      
      g_last_send_sig_hash = sig_h;
      g_last_send_ms = now_ms;
      trade.SetDeviationInPoints(MaxSlippagePoints);
      bool order_sent = (signal > 0) ? trade.Buy(lots_to_trade, symbolName, 0, sl, tp, comment) : trade.Sell(lots_to_trade, symbolName, 0, sl, tp, comment);
      
      if(order_sent && (trade.ResultRetcode() == TRADE_RETCODE_DONE || trade.ResultRetcode() == TRADE_RETCODE_DONE_PARTIAL)){
         PrintFormat("%s Signal:%s → Executed %.2f lots @%.5f | SL:%.5f TP:%.5f", EVT_ENTRY, signal_str, trade.ResultVolume(), trade.ResultPrice(), sl, tp);
         if(signal > 0) g_last_entry_bar_buy = current_bar_time; else g_last_entry_bar_sell = current_bar_time;
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
   
   if(!InpExit_FixedRR) { 
      HandlePartialProfits();
      if(!PositionSelect(_Symbol)) return;
   }
   
   ulong ticket = PositionGetInteger(POSITION_TICKET);
   if(loc.day_of_week==FRIDAY && loc.hour>=FridayCloseHour) { trade.PositionClose(ticket); return; }

   ENUM_POSITION_TYPE side = (ENUM_POSITION_TYPE)PositionGetInteger(POSITION_TYPE);
   double entry = PositionGetDouble(POSITION_PRICE_OPEN);
   double sl    = PositionGetDouble(POSITION_SL);
   double tp    = PositionGetDouble(POSITION_TP);

   if(AAI_ApplyBEAndTrail(side, entry, sl))
   {
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
   if(InpExit_FixedRR) return false;
   
   const double pip = AAI_Pip();
   const double bid = SymbolInfoDouble(_Symbol, SYMBOL_BID);
   const double ask = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
   const bool   is_long = (side==POSITION_TYPE_BUY);
   const double px     = is_long ? bid : ask;
   const double move_p = is_long ? (px - entry_price) : (entry_price - px);
   const double move_pips = move_p / pip;
   bool changed=false;
   
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

   string parts[];
   if(StringSplit(comment, '|', parts) < 6) return;

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
//| Journaling Functions                                             |
//+------------------------------------------------------------------+
void JournalClosedPosition(ulong position_id)
{
   if(!HistorySelectByPosition(position_id)) return;

   datetime timestamp_close = 0;
   string   symbol          = "";
   string   side            = "";
   double   lots            = 0;
   double   entry_price     = 0;
   double   sl_price        = 0;
   double   tp_price        = 0;
   double   exit_price      = 0;
   double   profit          = 0;
   double   conf_raw        = 0;
   int      conf_eff        = 0;
   int      reason_code     = 0;
   double   ze_strength     = 0;
   string   bc_mode         = EnumToString(InpBC_AlignMode);
   
   for(int i=0; i<HistoryDealsTotal(); i++)
   {
      ulong deal_ticket = HistoryDealGetTicket(i);
      profit += HistoryDealGetDouble(deal_ticket, DEAL_PROFIT) + HistoryDealGetDouble(deal_ticket, DEAL_COMMISSION) + HistoryDealGetDouble(deal_ticket, DEAL_SWAP);
      
      if(HistoryDealGetInteger(deal_ticket, DEAL_ENTRY) == DEAL_ENTRY_IN)
      {
         if(entry_price == 0) 
         {
            symbol      = HistoryDealGetString(deal_ticket, DEAL_SYMBOL);
            side        = (HistoryDealGetInteger(deal_ticket, DEAL_TYPE) == DEAL_TYPE_BUY) ? "BUY" : "SELL";
            entry_price = HistoryDealGetDouble(deal_ticket, DEAL_PRICE);

            string comment = HistoryDealGetString(deal_ticket, DEAL_COMMENT);
            string parts[];
            if(StringSplit(comment, '|', parts) >= 7)
            {
               conf_raw    = StringToDouble(parts[1]);
               conf_eff    = (int)StringToInteger(parts[2]);
               reason_code = (int)StringToInteger(parts[3]);
               ze_strength = StringToDouble(parts[4]);
               sl_price    = StringToDouble(parts[5]);
               tp_price    = StringToDouble(parts[6]);
            }
         }
         lots += HistoryDealGetDouble(deal_ticket, DEAL_VOLUME);
      }
      else
      {
         timestamp_close = (datetime)HistoryDealGetInteger(deal_ticket, DEAL_TIME);
         exit_price      = HistoryDealGetDouble(deal_ticket, DEAL_PRICE);
      }
   }

   if(symbol == "") return;

   double profit_pips = 0;
   if(point > 0)
   {
       profit_pips = (exit_price - entry_price) * (side == "BUY" ? 1 : -1) / point;
   }

   double rr = 0;
   double risk_dist = MathAbs(entry_price - sl_price);
   if(risk_dist > 0)
   {
      double profit_dist_signed = (side == "BUY") ? (exit_price - entry_price) : (entry_price - exit_price);
      rr = profit_dist_signed / risk_dist;
   }
   
   int file_handle = FileOpen(JournalFileName, FILE_READ|FILE_WRITE|FILE_CSV|(JournalUseCommonFiles ? FILE_COMMON : 0), ';');
   if(file_handle != INVALID_HANDLE)
   {
      if(FileSize(file_handle) == 0)
      {
         FileWriteString(file_handle, "timestamp_close;symbol;side;lots;entry;sl;tp;exit;profit;profit_pips;rr;conf_raw;conf_eff;reason_code;ze_strength;bc_mode\n");
      }
      FileSeek(file_handle, 0, SEEK_END);

      string line = StringFormat("%s;%s;%s;%.2f;%.5f;%.5f;%.5f;%.5f;%.2f;%.1f;%.2f;%.1f;%d;%d;%.1f;%s\n",
                                 TimeToString(timestamp_close, TIME_DATE|TIME_SECONDS),
                                 symbol, side, lots, entry_price, sl_price, tp_price, exit_price,
                                 profit, profit_pips, rr, conf_raw, conf_eff, reason_code, ze_strength, bc_mode);
                                 
      FileWriteString(file_handle, line);
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

