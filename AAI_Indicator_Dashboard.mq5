//+------------------------------------------------------------------+
//|                   AAI_Indicator_Dashboard.mq5                    |
//|             v2.0 - Unified & Feature Complete                    |
//|        (Displays all data from the AAI indicator suite)          |
//|              Copyright 2025, AlfredAI Project                    |
//+------------------------------------------------------------------+
#property strict
#property indicator_chart_window
#property indicator_plots 0 // Suppress "no indicator plot" warning
#property version "2.0"

// --- Optional Inputs ---
input bool ShowAlfredBrainModule = true;        // Show AlfredBrain signal module
input bool ShowDebugInfo = false;               // Toggle for displaying debug information
input bool EnableDebugLogging = false;          // Toggle for printing detailed data fetch logs to the Experts tab
input bool ShowZoneHeatmap = true;              // Toggle for the Zone Heatmap
input bool ShowMagnetProjection = true;         // Toggle for the Magnet Projection status
input bool ShowMultiTFMagnets = true;           // Toggle for the Multi-TF Magnet Summary
input bool ShowHUDActivitySection = true;       // Toggle for the HUD Zone Activity section
input bool ShowConfidenceMatrix = true;         // Toggle for the Confidence Matrix
input bool ShowTradeRecommendation = true;      // Toggle for the Trade Recommendation
input bool ShowRiskModule = true;               // Toggle for the Risk & Positioning module
input bool ShowSessionModule = true;            // Toggle for the Session & Volatility module
input bool ShowNewsModule = true;               // Toggle for the Upcoming News module
input bool ShowEmotionalState = true;           // Toggle for the Emotional State module
input bool ShowAlertCenter = true;              // Toggle for the Alert Center module
input bool ShowPaneSettings = true;             // Toggle for the Pane Settings summary module
input bool ShowAlfredSays = true;               // Toggle for the "Alfred Says" module

// --- Includes
#include <ChartObjects\ChartObjectsTxtControls.mqh>
#include <AAI_Include_Settings.mqh> // UPDATED INCLUDE

// --- Enums for State Management
enum ENUM_BIAS { BIAS_BULL, BIAS_BEAR, BIAS_NEUTRAL };
enum ENUM_ZONE { ZONE_DEMAND, ZONE_SUPPLY, ZONE_NONE };
enum ENUM_ZONE_INTERACTION { INTERACTION_INSIDE_DEMAND, INTERACTION_INSIDE_SUPPLY, INTERACTION_NONE };
enum ENUM_TRADE_SIGNAL { SIGNAL_NONE, SIGNAL_BUY, SIGNAL_SELL };
enum ENUM_HEATMAP_STATUS { HEATMAP_NONE, HEATMAP_DEMAND, HEATMAP_SUPPLY };
enum ENUM_MAGNET_RELATION { RELATION_ABOVE, RELATION_BELOW, RELATION_AT };
enum ENUM_VOLATILITY { VOLATILITY_LOW, VOLATILITY_MEDIUM, VOLATILITY_HIGH };
enum ENUM_NEWS_IMPACT { IMPACT_LOW, IMPACT_MEDIUM, IMPACT_HIGH };
enum ENUM_EMOTIONAL_STATE { STATE_CAUTIOUS, STATE_CONFIDENT, STATE_OVEREXTENDED, STATE_ANXIOUS, STATE_NEUTRAL };
enum ENUM_ALERT_STATUS { ALERT_NONE, ALERT_PARTIAL, ALERT_STRONG };
enum ENUM_REASON_CODE
{
    REASON_NONE,
    REASON_BUY_LIQ_GRAB_ALIGNED,
    REASON_SELL_LIQ_GRAB_ALIGNED,
    REASON_NO_ZONE,
    REASON_LOW_ZONE_STRENGTH,
    REASON_BIAS_CONFLICT
};

// --- Structs for Data Handling
struct LiveTradeData { bool trade_exists; double entry, sl, tp; };
struct CompassData { ENUM_BIAS bias; double confidence; };
struct MatrixRowData { ENUM_BIAS bias; ENUM_ZONE zone; ENUM_MAGNET_RELATION magnet; int score; };
struct TradeRecommendation { ENUM_TRADE_SIGNAL action; string reasoning; };
struct RiskModuleData { double risk_percent; double position_size; string rr_ratio; };
struct SessionData { string session_name; string session_overlap; ENUM_VOLATILITY volatility; };
struct NewsEventData { string time; string currency; string event_name; ENUM_NEWS_IMPACT impact; };
struct EmotionalStateData { ENUM_EMOTIONAL_STATE state; string text; };
struct AlertData { ENUM_ALERT_STATUS status; string text; };
struct AlfredComment { string text; color clr; };

// --- Structs for Live Data Caching ---
struct CachedCompassData { ENUM_BIAS bias; double confidence; };
struct CachedSupDemData
{
   ENUM_ZONE zone;
   double magnet_level;
   double zone_p1;
   double zone_p2;
   double strength;
   double freshness;
   double volume;
   double liquidity;
};
struct CachedHUDData { bool zone_active; };
struct CachedBrainData
{
   ENUM_TRADE_SIGNAL signal;
   double confidence;
   ENUM_REASON_CODE reasonCode;
   int zoneTF;
};


// --- Constants for Panel Layout
#define PANE_PREFIX "AAI_Dashboard_"
#define PANE_WIDTH 230
#define PANE_X_POS 15
#define PANE_Y_POS 15
#define PANE_BG_COLOR clrDimGray
#define PANE_BG_OPACITY 210
#define CONFIDENCE_BAR_MAX_WIDTH 100
#define SEPARATOR_TEXT "───────────────"
#define MAX_NEWS_ITEMS 3

// --- Colors
#define COLOR_BULL clrLimeGreen
#define COLOR_BEAR clrOrangeRed
#define COLOR_NEUTRAL_TEXT clrWhite
#define COLOR_NEUTRAL_BIAS clrGoldenrod
#define COLOR_HEADER clrSilver
#define COLOR_TOGGLE clrLightGray
#define COLOR_DEMAND clrLimeGreen
#define COLOR_SUPPLY clrOrangeRed
#define COLOR_CONF_HIGH clrLimeGreen
#define COLOR_CONF_MED clrOrange
#define COLOR_CONF_LOW clrOrangeRed
#define COLOR_SEPARATOR clrGray
#define COLOR_NA clrGray
#define COLOR_NO_SIGNAL clrGray
#define COLOR_HIGHLIGHT_DEMAND (color)ColorToARGB(clrDarkGreen, 100)
#define COLOR_HIGHLIGHT_SUPPLY (color)ColorToARGB(clrMaroon, 100)
#define COLOR_HIGHLIGHT_NONE (color)ColorToARGB(clrGray, 50)
#define COLOR_MAGNET_AT clrGoldenrod
#define COLOR_TEXT_DIM clrSilver
#define COLOR_SESSION clrCyan
#define COLOR_VOL_HIGH_BG (color)ColorToARGB(clrMaroon, 80)
#define COLOR_VOL_MED_BG (color)ColorToARGB(clrGoldenrod, 80)
#define COLOR_VOL_LOW_BG (color)ColorToARGB(clrDarkGreen, 80)
#define COLOR_IMPACT_HIGH clrRed
#define COLOR_IMPACT_MEDIUM clrOrange
#define COLOR_IMPACT_LOW clrLimeGreen
#define COLOR_STATE_CAUTIOUS clrYellow
#define COLOR_STATE_CONFIDENT clrLimeGreen
#define COLOR_STATE_OVEREXTENDED clrRed
#define COLOR_STATE_ANXIOUS clrDodgerBlue
#define COLOR_STATE_NEUTRAL clrGray
#define COLOR_ALERT_STRONG clrLimeGreen
#define COLOR_ALERT_PARTIAL clrYellow
#define COLOR_ALERT_NONE clrGray
#define COLOR_FOOTER clrDarkGray
#define COLOR_ALFRED_CAUTION clrGoldenrod


// --- Font Sizes & Spacing
#define FONT_SIZE_NORMAL 8
#define FONT_SIZE_HEADER 9
#define FONT_SIZE_SIGNAL 10
#define FONT_SIZE_SIGNAL_ACTIVE 11
#define SPACING_MEDIUM 16
#define SPACING_LARGE 24
#define SPACING_SEPARATOR 12

// --- Indicator Handles & Globals
SAlfred Alfred; // Global settings instance
int hATR_current;
int atr_period = 14;
bool g_biases_expanded = true;
bool g_hud_expanded = true;
double g_pip_value;

string g_timeframe_strings[];
ENUM_TIMEFRAMES g_timeframes[];
string g_heatmap_tf_strings[];
ENUM_TIMEFRAMES g_heatmap_tfs[];
string g_magnet_summary_tf_strings[];
ENUM_TIMEFRAMES g_magnet_summary_tfs[];
string g_matrix_tf_strings[];
ENUM_TIMEFRAMES g_matrix_tfs[];
string g_hud_tf_strings[];
ENUM_TIMEFRAMES g_hud_tfs[];

// --- Live Data Caches ---
CachedCompassData g_compass_cache[7];
CachedSupDemData  g_supdem_cache[7];
CachedHUDData     g_hud_cache[7];
CachedBrainData   g_brain_cache;
string g_last_alfred_comment = "";


//+------------------------------------------------------------------+
//|                        LIVE DATA & CACHING FUNCTIONS             |
//+------------------------------------------------------------------+
void UpdateLiveDataCaches()
{
   if(EnableDebugLogging)
      Print("--- AAI Dashboard: Updating Live Data Caches ---");
      
   // --- Cache SignalBrain Data ---
   if(ShowAlfredBrainModule)
   {
      double brain_buffers[4]; // 0:Signal, 1:Confidence, 2:ReasonCode, 3:ZoneTF
      if(CopyBuffer(iCustom(_Symbol, _Period, "AAI_Indicator_SignalBrain.ex5"), 0, 0, 4, brain_buffers) >= 4)
      {
         g_brain_cache.signal = (ENUM_TRADE_SIGNAL)brain_buffers[0];
         g_brain_cache.confidence = brain_buffers[1];
         g_brain_cache.reasonCode = (ENUM_REASON_CODE)brain_buffers[2];
         g_brain_cache.zoneTF = (int)brain_buffers[3];
      }
   }
      
   // Get handles ONCE per update cycle for efficiency
   int hud_handle = iCustom(_Symbol, _Period, "AAI_Indicator_HUD.ex5");
   for(int i = 0; i < ArraySize(g_timeframes); i++)
   {
      ENUM_TIMEFRAMES tf = g_timeframes[i];
      string tf_str = g_timeframe_strings[i];

      // --- Cache BiasCompass Data ---
      int compass_handle = iCustom(_Symbol, tf, "AAI_Indicator_BiasCompass.ex5");
      if(compass_handle != INVALID_HANDLE)
      {
         double bias_buffer[1], conf_buffer[1];
         if(CopyBuffer(compass_handle, 0, 0, 1, bias_buffer) > 0 && CopyBuffer(compass_handle, 1, 0, 1, conf_buffer) > 0)
         {
            if(bias_buffer[0] > 0.5) g_compass_cache[i].bias = BIAS_BULL;
            else if(bias_buffer[0] < -0.5) g_compass_cache[i].bias = BIAS_BEAR;
            else g_compass_cache[i].bias = BIAS_NEUTRAL;
            g_compass_cache[i].confidence = conf_buffer[0];
         }
      }

      // --- Cache ZoneEngine Data ---
      int zone_engine_handle = iCustom(_Symbol, tf, "AAI_Indicator_ZoneEngine.ex5");
      if(zone_engine_handle != INVALID_HANDLE)
      {
         double zone_buffer[1], magnet_buffer[1], strength_buffer[1], fresh_buffer[1], volume_buffer[1], liq_buffer[1];
         g_supdem_cache[i].zone = ZONE_NONE;
         if(CopyBuffer(zone_engine_handle, 0, 0, 1, zone_buffer) > 0)
         {
            if(zone_buffer[0] > 0.5) g_supdem_cache[i].zone = ZONE_DEMAND;
            else if(zone_buffer[0] < -0.5) g_supdem_cache[i].zone = ZONE_SUPPLY;
         }
         if(CopyBuffer(zone_engine_handle, 1, 0, 1, magnet_buffer) > 0) g_supdem_cache[i].magnet_level = magnet_buffer[0];
         if(CopyBuffer(zone_engine_handle, 2, 0, 1, strength_buffer) > 0) g_supdem_cache[i].strength = strength_buffer[0];
         if(CopyBuffer(zone_engine_handle, 3, 0, 1, fresh_buffer) > 0) g_supdem_cache[i].freshness = fresh_buffer[0];
         if(CopyBuffer(zone_engine_handle, 4, 0, 1, volume_buffer) > 0) g_supdem_cache[i].volume = volume_buffer[0];
         if(CopyBuffer(zone_engine_handle, 5, 0, 1, liq_buffer) > 0) g_supdem_cache[i].liquidity = liq_buffer[0];
      }

      // --- Cache HUD Data ---
      if(hud_handle != INVALID_HANDLE)
      {
         int buffer_index = -1;
         if(tf == PERIOD_M15) buffer_index = 5;
         else if(tf == PERIOD_H1) buffer_index = 3;
         else if(tf == PERIOD_H4) buffer_index = 1;
         
         if(buffer_index != -1)
         {
            double activity_buffer[1];
            if(CopyBuffer(hud_handle, buffer_index, 0, 1, activity_buffer) > 0)
            {
               g_hud_cache[i].zone_active = (activity_buffer[0] > 0.5);
            }
         }
      }
   }
}


// Helper to get the correct cache index for a given timeframe
int GetCacheIndex(ENUM_TIMEFRAMES tf)
{
   for(int i = 0; i < ArraySize(g_timeframes); i++)
   {
      if(g_timeframes[i] == tf)
         return i;
   }
   return -1; // Not found
}


//+------------------------------------------------------------------+
//|                   LIVE & MOCK DATA FUNCTIONS                     |
//+------------------------------------------------------------------+
CompassData GetCompassData(ENUM_TIMEFRAMES tf)
{
   CompassData data;
   int index = GetCacheIndex(tf);
   if(index != -1)
   {
      data.bias = g_compass_cache[index].bias;
      data.confidence = g_compass_cache[index].confidence;
   }
   else
   {
      data.bias = BIAS_NEUTRAL;
      data.confidence = 0.0;
   }
   return data;
}

CachedSupDemData GetSupDemData(ENUM_TIMEFRAMES tf)
{
   CachedSupDemData data;
   int index = GetCacheIndex(tf);
   if(index != -1)
   {
      return g_supdem_cache[index];
   }
   data.zone = ZONE_NONE;
   data.magnet_level = 0.0;
   data.strength = 0.0;
   data.freshness = 0.0;
   data.volume = 0.0;
   data.liquidity = 0.0;
   return data;
}


ENUM_ZONE GetZoneStatus(ENUM_TIMEFRAMES tf)
{
   int index = GetCacheIndex(tf);
   if(index != -1)
   {
      return g_supdem_cache[index].zone;
   }
   return ZONE_NONE;
}

double GetMagnetLevelTF(ENUM_TIMEFRAMES tf)
{
   int index = GetCacheIndex(tf);
   if(index != -1)
   {
      return g_supdem_cache[index].magnet_level;
   }
   return 0.0;
}

bool GetHUDZoneActivity(ENUM_TIMEFRAMES tf)
{
   int index = GetCacheIndex(tf);
   if(index != -1)
   {
      return g_hud_cache[index].zone_active;
   }
   return false;
}

double GetMagnetProjectionLevel()
{
   return GetMagnetLevelTF(_Period);
}

ENUM_TRADE_SIGNAL GetTradeSignal()
{
   TradeRecommendation rec = GetTradeRecommendation();
   return rec.action;
}

ENUM_ZONE_INTERACTION GetCurrentZoneInteraction()
{
   ENUM_ZONE current_zone = GetZoneStatus(_Period);
   switch(current_zone)
   {
      case ZONE_DEMAND: return INTERACTION_INSIDE_DEMAND;
      case ZONE_SUPPLY: return INTERACTION_INSIDE_SUPPLY;
      default: return INTERACTION_NONE;
   }
}

ENUM_HEATMAP_STATUS GetZoneHeatmapStatus(ENUM_TIMEFRAMES tf)
{
   switch(GetZoneStatus(tf))
   {
      case ZONE_DEMAND: return HEATMAP_DEMAND;
      case ZONE_SUPPLY: return HEATMAP_SUPPLY;
      default: return HEATMAP_NONE;
   }
}

ENUM_MAGNET_RELATION GetMagnetProjectionRelation(double price, double magnet)
{
   if(price == 0 || magnet == 0) return RELATION_AT;
   double proximity = 5 * _Point;
   if(price > magnet + proximity) return RELATION_ABOVE;
   if(price < magnet - proximity) return RELATION_BELOW;
   return RELATION_AT;
}

ENUM_MAGNET_RELATION GetMagnetRelationTF(double price, double magnet)
{
   if(price == 0 || magnet == 0) return RELATION_AT;
   if(price > magnet) return RELATION_ABOVE;
   if(price < magnet) return RELATION_BELOW;
   return RELATION_AT;
}

MatrixRowData GetConfidenceMatrixRow(ENUM_TIMEFRAMES tf)
{
   MatrixRowData data;
   data.bias = GetCompassData(tf).bias;
   data.zone = GetZoneStatus(tf);
   double magnet_level = GetMagnetLevelTF(tf);
   data.magnet = GetMagnetRelationTF(SymbolInfoDouble(_Symbol, SYMBOL_BID), magnet_level);

   double strength_raw = iCustom(_Symbol, tf, "AAI_Indicator_ZoneEngine.ex5", 2, 0);
   double freshness_raw = iCustom(_Symbol, tf, "AAI_Indicator_ZoneEngine.ex5", 3, 0);
   double volume_raw = iCustom(_Symbol, tf, "AAI_Indicator_ZoneEngine.ex5", 4, 0);
   double liquidity_raw = iCustom(_Symbol, tf, "AAI_Indicator_ZoneEngine.ex5", 5, 0);

   int zoneStrength = (int)strength_raw;
   bool zoneFreshness = freshness_raw > 0.5;
   bool zoneVolume = volume_raw > 0.5;
   bool zoneLiquidity = liquidity_raw > 0.5;
   data.score = zoneStrength * 2 + (zoneFreshness ? 3 : 0) + (zoneVolume ? 2 : 0) + (zoneLiquidity ? 3 : 0);
   return data;
}

TradeRecommendation GetTradeRecommendation()
{
   TradeRecommendation rec;
   rec.action = SIGNAL_NONE;
   rec.reasoning = "Mixed Signals";
   
   #define STRONG_CONFIDENCE_THRESHOLD 10

   int strong_bullish_tfs = 0;
   int strong_bearish_tfs = 0;
   for(int i = 0; i < ArraySize(g_matrix_tfs); i++)
   {
      MatrixRowData row = GetConfidenceMatrixRow(g_matrix_tfs[i]);
      if(row.score >= STRONG_CONFIDENCE_THRESHOLD)
      {
         if(row.bias == BIAS_BULL)
            strong_bullish_tfs++;
         if(row.bias == BIAS_BEAR)
            strong_bearish_tfs++;
      }
   }

   if(strong_bullish_tfs >= 2)
   {
      rec.action = SIGNAL_BUY;
      rec.reasoning = "Strong Multi-TF Bullish Alignment";
      double best_score = -1;
      string best_reason = "";
      for(int i = 0; i < ArraySize(g_matrix_tfs); i++)
      {
         MatrixRowData row = GetConfidenceMatrixRow(g_matrix_tfs[i]);
         if(row.score >= STRONG_CONFIDENCE_THRESHOLD && row.bias == BIAS_BULL)
         {
            CachedSupDemData zone_data = GetSupDemData(g_matrix_tfs[i]);
            if(zone_data.zone == ZONE_DEMAND)
            {
               double current_score = zone_data.strength + (zone_data.liquidity > 0.5 ? 5 : 0);
               if(current_score > best_score)
               {
                  best_score = current_score;
                  best_reason = ". " + g_matrix_tf_strings[i] + " zone strength " + (string)zone_data.strength + "/10";
                  if(zone_data.liquidity > 0.5)
                     best_reason += " (Liq. Grab)";
               }
            }
         }
      }
      rec.reasoning += best_reason;
   }
   else if(strong_bearish_tfs >= 2)
   {
      rec.action = SIGNAL_SELL;
      rec.reasoning = "Strong Multi-TF Bearish Alignment";
      double best_score = -1;
      string best_reason = "";
      for(int i = 0; i < ArraySize(g_matrix_tfs); i++)
      {
         MatrixRowData row = GetConfidenceMatrixRow(g_matrix_tfs[i]);
         if(row.score >= STRONG_CONFIDENCE_THRESHOLD && row.bias == BIAS_BEAR)
         {
            CachedSupDemData zone_data = GetSupDemData(g_matrix_tfs[i]);
            if(zone_data.zone == ZONE_SUPPLY)
            {
               double current_score = zone_data.strength + (zone_data.liquidity > 0.5 ? 5 : 0);
               if(current_score > best_score)
               {
                  best_score = current_score;
                  best_reason = ". " + g_matrix_tf_strings[i] + " zone strength " + (string)zone_data.strength + "/10";
                  if(zone_data.liquidity > 0.5)
                     best_reason += " (Liq. Grab)";
               }
            }
         }
      }
      rec.reasoning += best_reason;
   }
   return rec;
}

AlfredComment GetAlfredComment()
{
    AlfredComment comment;
    comment.text = "Alfred is observing...";
    comment.clr = COLOR_TEXT_DIM;
    int bull_strong_count = 0;
    int bear_strong_count = 0;
    int total_score = 0;
    int total_tfs = ArraySize(g_matrix_tfs);
    for(int i = 0; i < total_tfs; i++)
    {
        MatrixRowData row = GetConfidenceMatrixRow(g_matrix_tfs[i]);
        total_score += row.score;
        if (row.score >= 10)
        {
            if (row.bias == BIAS_BULL) bull_strong_count++;
            else if (row.bias == BIAS_BEAR) bear_strong_count++;
        }
    }
    if (bull_strong_count >= 3 && bear_strong_count == 0)
    {
        comment.text = "Looks like a power move building. Watching upside.";
        comment.clr = COLOR_BULL;
        return comment;
    }
    if (bear_strong_count >= 3 && bull_strong_count == 0)
    {
        comment.text = "Momentum is heavy. Alfred sees potential drops.";
        comment.clr = COLOR_BEAR;
        return comment;
    }
    MatrixRowData d1_data = GetConfidenceMatrixRow(PERIOD_D1);
    MatrixRowData m15_data = GetConfidenceMatrixRow(PERIOD_M15);
    if (d1_data.bias != BIAS_NEUTRAL && m15_data.bias != BIAS_NEUTRAL && d1_data.bias != m15_data.bias)
    {
        comment.text = "Market's arguing. Sit tight or scalp the mess.";
        comment.clr = COLOR_ALFRED_CAUTION;
        return comment;
    }
    if (bull_strong_count == 0 && bear_strong_count == 0 && (total_score / total_tfs) < 5)
    {
        comment.text = "Momentum fading... don't get caught snoozing, boss.";
        comment.clr = clrSilver;
        return comment;
    }
    if (d1_data.score > 12)
    {
        if (d1_data.bias == BIAS_BULL)
        {
           comment.text = "Big players just turned. D1 bias is bullish.";
           comment.clr = COLOR_BULL;
           return comment;
        }
        else if (d1_data.bias == BIAS_BEAR)
        {
           comment.text = "The daily chart looks heavy. Bearish pressure on.";
           comment.clr = COLOR_BEAR;
           return comment;
        }
    }
    return comment;
}

RiskModuleData GetRiskModuleData()
{
   RiskModuleData data;
   data.risk_percent = 1.0;
   data.position_size = 0.10;
   int rand_val = MathRand() % 3;
   switch(rand_val)
   {
      case 0: data.rr_ratio = "1 : 1.5"; break;
      case 1: data.rr_ratio = "1 : 2.0"; break;
      default: data.rr_ratio = "1 : 3.0"; break;
   }
   return data;
}

SessionData GetSessionData()
{
   SessionData data;
   MqlDateTime dt;
   TimeCurrent(dt);
   int hour = dt.hour;
   if(hour >= 13 && hour < 16) data.session_name = "London / NY";
   else if(hour >= 8 && hour < 13) data.session_name = "London";
   else if(hour >= 16 && hour < 21) data.session_name = "New York";
   else if(hour >= 21 || hour < 6) data.session_name = "Sydney";
   else if(hour >= 6 && hour < 8) data.session_name = "Tokyo";
   else data.session_name = "Inter-Session";
   if(hour >= 13 && hour < 16) data.session_overlap = "NY + London";
   else data.session_overlap = "None";
   int rand_val = MathRand() % 3;
   switch(rand_val)
   {
      case 0: data.volatility = VOLATILITY_LOW; break;
      case 1: data.volatility = VOLATILITY_MEDIUM; break;
      default: data.volatility = VOLATILITY_HIGH; break;
   }
   return data;
}

int GetUpcomingNews(NewsEventData &news_array[])
{
   static NewsEventData all_news[] =
   {
      {"14:30", "USD", "Non-Farm Payrolls", IMPACT_HIGH},
      {"16:00", "EUR", "CPI YoY", IMPACT_MEDIUM},
      {"22:00", "NZD", "Official Cash Rate", IMPACT_HIGH},
      {"01:30", "AUD", "Retail Sales MoM", IMPACT_LOW}
   };
   int count = MathMin(MAX_NEWS_ITEMS, ArraySize(all_news));
   for(int i = 0; i < count; i++)
   {
      news_array[i] = all_news[i];
   }
   return count;
}

EmotionalStateData GetEmotionalState()
{
   EmotionalStateData data;
   long time_cycle = TimeCurrent() / 180;
   switch(time_cycle % 5)
   {
      case 0: data.state = STATE_CONFIDENT; data.text = "Confident – Trend Aligned"; break;
      case 1: data.state = STATE_CAUTIOUS; data.text = "Cautious – Awaiting Confirmation"; break;
      case 2: data.state = STATE_OVEREXTENDED; data.text = "Overextended – Risk of Reversal"; break;
      case 3: data.state = STATE_ANXIOUS; data.text = "Anxious – Overtrading Zone"; break;
      default: data.state = STATE_NEUTRAL; data.text = "Neutral – Balanced Mindset"; break;
   }
   return data;
}

AlertData GetAlertCenterStatus()
{
   AlertData alert;
   for(int i = 0; i < ArraySize(g_matrix_tfs); i++)
   {
      CachedSupDemData data = GetSupDemData(g_matrix_tfs[i]);
      if(data.liquidity > 0.5)
      {
         alert.status = ALERT_STRONG;
         alert.text = "🔥 Liquidity Grab Confirmed! (" + g_matrix_tf_strings[i] + ")";
         return alert;
      }
   }

   #define STRONG_CONFIDENCE_THRESHOLD_ALERT 10
   #define MEDIUM_CONFIDENCE_THRESHOLD_ALERT 5
   
   int strong_count = 0;
   int medium_count = 0;
   for(int i = 0; i < ArraySize(g_matrix_tfs); i++)
   {
      MatrixRowData row = GetConfidenceMatrixRow(g_matrix_tfs[i]);
      if(row.score >= STRONG_CONFIDENCE_THRESHOLD_ALERT) strong_count++;
      else if(row.score >= MEDIUM_CONFIDENCE_THRESHOLD_ALERT) medium_count++;
   }

   if(strong_count > 0)
   {
      alert.status = ALERT_STRONG;
      alert.text = "✅ STRONG ALIGNMENT — High-Conviction Setup";
   }
   else if(medium_count > 0)
   {
      alert.status = ALERT_PARTIAL;
      alert.text = "⚠️ Partial Alignment — Watch for Entry Trigger";
   }
   else
   {
      alert.status = ALERT_NONE;
      alert.text = "⏳ No Signal — Standby";
   }
   return alert;
}


LiveTradeData FetchTradeLevels()
{
   LiveTradeData data;
   data.trade_exists = false;
   for(int i = PositionsTotal() - 1; i >= 0; i--)
   {
      if(PositionGetString(POSITION_SYMBOL) == _Symbol)
      {
         data.trade_exists = true;
         data.entry = PositionGetDouble(POSITION_PRICE_OPEN);
         data.sl = PositionGetDouble(POSITION_SL);
         data.tp = PositionGetDouble(POSITION_TP);
         break;
      }
   }
   return data;
}


//+------------------------------------------------------------------+
//|                        HELPER & CONVERSION FUNCTIONS             |
//+------------------------------------------------------------------+
string ReasonCodeToString(ENUM_REASON_CODE code)
{
    switch(code)
    {
        case REASON_BUY_LIQ_GRAB_ALIGNED: return "Strong demand zone + HTF bias match + liquidity grab confirmed.";
        case REASON_SELL_LIQ_GRAB_ALIGNED: return "Strong supply zone + HTF bias match + liquidity grab confirmed.";
        case REASON_NO_ZONE: return "Price is not inside a valid zone.";
        case REASON_LOW_ZONE_STRENGTH: return "Active zone quality is too low.";
        case REASON_BIAS_CONFLICT: return "HTF & LTF biases are conflicting.";
        default: return "No valid setup at the moment. Standing by.";
    }
}

string PeriodMinutesToTFString(int minutes)
{
    if(minutes >= 1440) return "D"+IntegerToString(minutes/1440);
    if(minutes >= 60)   return "H"+IntegerToString(minutes/60);
    if(minutes > 0)     return "M"+IntegerToString(minutes);
    return "Chart";
}
double CalculatePips(double p1, double p2)
{
   if(g_pip_value == 0 || p1 == 0 || p2 == 0) return 0;
   return MathAbs(p1 - p2) / g_pip_value;
}
string BiasToString(ENUM_BIAS b){switch(b){case BIAS_BULL:return"BULL";case BIAS_BEAR:return"BEAR";}return"NEUTRAL";}
color  BiasToColor(ENUM_BIAS b){switch(b){case BIAS_BULL:return COLOR_BULL;case BIAS_BEAR:return COLOR_BEAR;}return COLOR_NEUTRAL_BIAS;}
string ZoneToString(ENUM_ZONE z){switch(z){case ZONE_DEMAND:return"Demand";case ZONE_SUPPLY:return"Supply";}return"None";}
color  ZoneToColor(ENUM_ZONE z){switch(z){case ZONE_DEMAND:return COLOR_DEMAND;case ZONE_SUPPLY:return COLOR_SUPPLY;}return COLOR_NA;}
string SignalToString(ENUM_TRADE_SIGNAL s){switch(s){case SIGNAL_BUY:return"BUY";case SIGNAL_SELL:return"SELL";}return"NO SIGNAL";}
color  SignalToColor(ENUM_TRADE_SIGNAL s){switch(s){case SIGNAL_BUY:return COLOR_BULL;case SIGNAL_SELL:return COLOR_BEAR;}return COLOR_NO_SIGNAL;}
string ZoneInteractionToString(ENUM_ZONE_INTERACTION z){switch(z){case INTERACTION_INSIDE_DEMAND:return"INSIDE DEMAND";case INTERACTION_INSIDE_SUPPLY:return"INSIDE SUPPLY";}return"NO ZONE INTERACTION";}
color  ZoneInteractionToColor(ENUM_ZONE_INTERACTION z){switch(z){case INTERACTION_INSIDE_DEMAND:return COLOR_DEMAND;case INTERACTION_INSIDE_SUPPLY:return COLOR_SUPPLY;}return COLOR_NA;}
color  ZoneInteractionToHighlightColor(ENUM_ZONE_INTERACTION z){switch(z){case INTERACTION_INSIDE_DEMAND:return COLOR_HIGHLIGHT_DEMAND;case INTERACTION_INSIDE_SUPPLY:return COLOR_HIGHLIGHT_SUPPLY;}return COLOR_HIGHLIGHT_NONE;}
string HeatmapStatusToString(ENUM_HEATMAP_STATUS s){switch(s){case HEATMAP_DEMAND:return"D";case HEATMAP_SUPPLY:return"S";}return"-";}
color  HeatmapStatusToColor(ENUM_HEATMAP_STATUS s){switch(s){case HEATMAP_DEMAND:return COLOR_DEMAND;case HEATMAP_SUPPLY:return COLOR_SUPPLY;}return COLOR_NA;}
string MagnetRelationToString(ENUM_MAGNET_RELATION r){switch(r){case RELATION_ABOVE:return"(Above)";case RELATION_BELOW:return"(Below)";}return"(At)";}
color  MagnetRelationToColor(ENUM_MAGNET_RELATION r){switch(r){case RELATION_ABOVE:return COLOR_BULL;case RELATION_BELOW:return COLOR_BEAR;}return COLOR_MAGNET_AT;}
string MagnetRelationTFToString(ENUM_MAGNET_RELATION r){switch(r){case RELATION_ABOVE:return"Above";case RELATION_BELOW:return"Below";}return"At";}
color  MagnetRelationTFToColor(ENUM_MAGNET_RELATION r){switch(r){case RELATION_ABOVE:return COLOR_BULL;case RELATION_BELOW:return COLOR_BEAR;}return COLOR_MAGNET_AT;}
color GetConfidenceColor(int score){if(score>=16)return(color)ColorToARGB(clrDodgerBlue,120);if(score>=10)return(color)ColorToARGB(clrLimeGreen,120);if(score>=5)return(color)ColorToARGB(clrGoldenrod,100);return(color)ColorToARGB(clrOrangeRed,120);}
string RecoActionToString(ENUM_TRADE_SIGNAL s){switch(s){case SIGNAL_BUY:return"BUY";case SIGNAL_SELL:return"SELL";}return"WAIT";}
color RecoActionToColor(ENUM_TRADE_SIGNAL s){switch(s){case SIGNAL_BUY:return COLOR_BULL;case SIGNAL_SELL:return COLOR_BEAR;}return COLOR_NO_SIGNAL;}
string VolatilityToString(ENUM_VOLATILITY v){switch(v){case VOLATILITY_LOW:return"Low";case VOLATILITY_MEDIUM:return"Medium";}return"High";}
color VolatilityToColor(ENUM_VOLATILITY v){switch(v){case VOLATILITY_LOW:return COLOR_BULL;case VOLATILITY_MEDIUM:return COLOR_MAGNET_AT;}return COLOR_BEAR;}
color VolatilityToHighlightColor(ENUM_VOLATILITY v){switch(v){case VOLATILITY_LOW:return COLOR_VOL_LOW_BG;case VOLATILITY_MEDIUM:return COLOR_VOL_MED_BG;}return COLOR_VOL_HIGH_BG;}
string NewsImpactToString(ENUM_NEWS_IMPACT i){switch(i){case IMPACT_LOW:return"LOW";case IMPACT_MEDIUM:return"MEDIUM";}return"HIGH";}
color NewsImpactToColor(ENUM_NEWS_IMPACT i){switch(i){case IMPACT_LOW:return COLOR_IMPACT_LOW;case IMPACT_MEDIUM:return COLOR_IMPACT_MEDIUM;}return COLOR_IMPACT_HIGH;}
color EmotionalStateToColor(ENUM_EMOTIONAL_STATE s){switch(s){case STATE_CAUTIOUS:return COLOR_STATE_CAUTIOUS;case STATE_CONFIDENT:return COLOR_STATE_CONFIDENT;case STATE_OVEREXTENDED:return COLOR_STATE_OVEREXTENDED;case STATE_ANXIOUS:return COLOR_STATE_ANXIOUS;}return COLOR_STATE_NEUTRAL;}
color AlertStatusToColor(ENUM_ALERT_STATUS s){switch(s){case ALERT_STRONG:return COLOR_ALERT_STRONG;case ALERT_PARTIAL:return COLOR_ALERT_PARTIAL;}return COLOR_ALERT_NONE;}
string GetBiasLabelFromZone(int zone_val){if(zone_val==1)return"Bull";if(zone_val==-1)return"Bear";return"Neutral";}
color GetBiasColorFromZone(int zone_val){if(zone_val==1)return COLOR_BULL;if(zone_val==-1)return COLOR_BEAR;return COLOR_NEUTRAL_BIAS;}
string GetMagnetRelationLabel(double current_price,double magnet_level){if(magnet_level==0.0)return"N/A";double proximity=5*_Point;if(current_price>magnet_level+proximity)return"Above";if(current_price<magnet_level-proximity)return"Below";return"At";}
color GetMagnetRelationColor(string relation){if(relation=="Above")return COLOR_BULL;if(relation=="Below")return COLOR_BEAR;if(relation=="At")return COLOR_MAGNET_AT;return COLOR_NA;}
color GetHeatColorForStrength(int strength){if(strength>=8)return clrRed;if(strength>=5)return clrOrange;if(strength>=1)return clrGold;return clrSilver;}


//+------------------------------------------------------------------+
//|                        UI DRAWING HELPERS                        |
//+------------------------------------------------------------------+
void CreateLabel(string n, string t, int x, int y, color c, int fs = FONT_SIZE_NORMAL, ENUM_ANCHOR_POINT a = ANCHOR_LEFT)
{
   string o = PANE_PREFIX + n;
   ObjectCreate(0, o, OBJ_LABEL, 0, 0, 0);
   ObjectSetString(0, o, OBJPROP_TEXT, t);
   ObjectSetInteger(0, o, OBJPROP_XDISTANCE, x);
   ObjectSetInteger(0, o, OBJPROP_YDISTANCE, y);
   ObjectSetInteger(0, o, OBJPROP_COLOR, c);
   ObjectSetInteger(0, o, OBJPROP_FONTSIZE, fs);
   ObjectSetString(0, o, OBJPROP_FONT, "Arial");
   ObjectSetInteger(0, o, OBJPROP_ANCHOR, a);
   ObjectSetInteger(0, o, OBJPROP_BACK, false);
   ObjectSetInteger(0, o, OBJPROP_CORNER, 0);
}
void CreateRectangle(string n, int x, int y, int w, int h, color c, ENUM_BORDER_TYPE b = BORDER_FLAT)
{
   string o = PANE_PREFIX + n;
   ObjectCreate(0, o, OBJ_RECTANGLE_LABEL, 0, 0, 0);
   ObjectSetInteger(0, o, OBJPROP_XDISTANCE, x);
   ObjectSetInteger(0, o, OBJPROP_YDISTANCE, y);
   ObjectSetInteger(0, o, OBJPROP_XSIZE, w);
   ObjectSetInteger(0, o, OBJPROP_YSIZE, h);
   ObjectSetInteger(0, o, OBJPROP_BGCOLOR, c);
   ObjectSetInteger(0, o, OBJPROP_COLOR, c);
   ObjectSetInteger(0, o, OBJPROP_BORDER_TYPE, b);
   ObjectSetInteger(0, o, OBJPROP_BACK, true);
   ObjectSetInteger(0, o, OBJPROP_CORNER, 0);
}
void UpdateLabel(string n, string t, color c = clrNONE)
{
   string o = PANE_PREFIX + n;
   if(ObjectFind(0, o) < 0) return;
   ObjectSetString(0, o, OBJPROP_TEXT, t);
   if(c != clrNONE) ObjectSetInteger(0, o, OBJPROP_COLOR, c);
}
void DrawSeparator(string name, int &y_offset, int x_offset)
{
   CreateLabel(name, SEPARATOR_TEXT, x_offset, y_offset, COLOR_SEPARATOR);
   y_offset += SPACING_SEPARATOR;
}

//+------------------------------------------------------------------+
//|                 MAIN PANEL CREATION & UPDATE LOGIC               |
//+------------------------------------------------------------------+
void CreatePanel()
{
   int x_offset = PANE_X_POS + 10;
   int y_offset = PANE_Y_POS + 10;
   int x_col1 = x_offset;
   int x_col2 = x_offset + 120;
   int x_toggle = PANE_X_POS + PANE_WIDTH - 20;
   CreateLabel("symbol_header", _Symbol, x_offset, y_offset, COLOR_HEADER, 10);
   y_offset += SPACING_LARGE;

   // --- Alfred Signal Section ---
   if(ShowAlfredBrainModule)
   {
      CreateLabel("brain_header", "📈 Alfred Signal", x_col1, y_offset, COLOR_HEADER, FONT_SIZE_HEADER);
      CreateLabel("brain_signal_value", "---", x_col1 + 95, y_offset, COLOR_NA, FONT_SIZE_HEADER + 1);
      y_offset += SPACING_MEDIUM;
      CreateLabel("brain_confidence_value", "🔹 Confidence: -- / 20", x_col1, y_offset, COLOR_TEXT_DIM);
      y_offset += SPACING_MEDIUM;
      CreateLabel("brain_setup_type_value", "🧱 Setup Type: ---", x_col1, y_offset, COLOR_TEXT_DIM);
      y_offset += SPACING_MEDIUM;
      CreateLabel("brain_reasoning_header", "🧠 Alfred Says:", x_col1, y_offset, COLOR_TEXT_DIM);
      y_offset += SPACING_MEDIUM;
      CreateLabel("brain_reasoning_value", "...", x_col1 + 5, y_offset, COLOR_NEUTRAL_TEXT, FONT_SIZE_NORMAL);
      y_offset += SPACING_LARGE;
      DrawSeparator("sep_brain", y_offset, x_offset);
   }

   // --- Upcoming News Section
   if(ShowNewsModule)
   {
      CreateLabel("news_header", "⚠️ UPCOMING NEWS", x_col1, y_offset, COLOR_HEADER, FONT_SIZE_HEADER);
      y_offset += SPACING_MEDIUM;
      for(int i = 0; i < MAX_NEWS_ITEMS; i++)
      {
         string idx = IntegerToString(i);
         CreateLabel("news_time_" + idx, "", x_col1, y_offset, COLOR_TEXT_DIM);
         CreateLabel("news_curr_" + idx, "", x_col1 + 40, y_offset, COLOR_NEUTRAL_TEXT);
         CreateLabel("news_event_" + idx, "", x_col1 + 75, y_offset, COLOR_NEUTRAL_TEXT);
         CreateLabel("news_impact_" + idx, "", x_col1 + 180, y_offset, COLOR_NEUTRAL_TEXT, FONT_SIZE_NORMAL, ANCHOR_RIGHT);
         y_offset += SPACING_MEDIUM;
      }
      DrawSeparator("sep_news", y_offset, x_offset);
   }

   // --- Emotional State Section
   if(ShowEmotionalState)
   {
      CreateLabel("emotion_header", "🧠 EMOTIONAL STATE", x_col1, y_offset, COLOR_HEADER, FONT_SIZE_HEADER);
      y_offset += SPACING_MEDIUM;
      CreateLabel("emotion_indicator", "●", x_col1, y_offset, COLOR_STATE_NEUTRAL, FONT_SIZE_HEADER);
      CreateLabel("emotion_text", "---", x_col1 + 15, y_offset, COLOR_NEUTRAL_TEXT);
      y_offset += SPACING_MEDIUM;
      DrawSeparator("sep_emotion", y_offset, x_offset);
   }

   // --- Alert Center Section
   if(ShowAlertCenter)
   {
      CreateLabel("alert_header", "🚨 ALERT CENTER", x_col1, y_offset, COLOR_HEADER, FONT_SIZE_HEADER);
      y_offset += SPACING_MEDIUM;
      CreateLabel("alert_status", "---", x_col1, y_offset, COLOR_NA, FONT_SIZE_NORMAL);
      y_offset += SPACING_MEDIUM;
      DrawSeparator("sep_alert", y_offset, x_offset);
   }

   // --- Pane Settings Section
   if(ShowPaneSettings)
   {
      CreateLabel("settings_header", "⚙️ PANE SETTINGS", x_col1, y_offset, COLOR_HEADER, FONT_SIZE_HEADER);
      y_offset += SPACING_MEDIUM;
      int settings_x1 = x_col1, settings_x2 = x_col1 + 110;
      CreateLabel("setting_matrix_prefix", "📊 Bias Matrix:", settings_x1, y_offset, COLOR_HEADER);
      CreateLabel("setting_matrix_value", "---", settings_x2, y_offset, COLOR_NA); y_offset += SPACING_MEDIUM;
      CreateLabel("setting_magnet_prefix", "📉 Magnet Summary:", settings_x1, y_offset, COLOR_HEADER); CreateLabel("setting_magnet_value", "---", settings_x2, y_offset, COLOR_NA);
      y_offset += SPACING_MEDIUM;
      CreateLabel("setting_heatmap_prefix", "📦 Zone Heatmap:", settings_x1, y_offset, COLOR_HEADER); CreateLabel("setting_heatmap_value", "---", settings_x2, y_offset, COLOR_NA); y_offset += SPACING_MEDIUM;
      CreateLabel("setting_hud_activity_prefix", "🛰️ HUD Activity:", settings_x1, y_offset, COLOR_HEADER); CreateLabel("setting_hud_activity_value", "---", settings_x2, y_offset, COLOR_NA); y_offset += SPACING_MEDIUM;
      CreateLabel("setting_reco_prefix", "🎯 Trade Signals:", settings_x1, y_offset, COLOR_HEADER); CreateLabel("setting_reco_value", "---", settings_x2, y_offset, COLOR_NA); y_offset += SPACING_MEDIUM;
      CreateLabel("setting_emotion_prefix", "🧠 Emotion Module:", settings_x1, y_offset, COLOR_HEADER); CreateLabel("setting_emotion_value", "---", settings_x2, y_offset, COLOR_NA); y_offset += SPACING_MEDIUM;
      CreateLabel("setting_alert_prefix", "🔔 Alert Center:", settings_x1, y_offset, COLOR_HEADER); CreateLabel("setting_alert_value", "---", settings_x2, y_offset, COLOR_NA); y_offset += SPACING_MEDIUM;
      DrawSeparator("sep_settings", y_offset, x_offset);
   }

   // --- TF Biases Section ---
   CreateLabel("biases_header", "TF Biases & Zones", x_col1, y_offset, COLOR_HEADER, FONT_SIZE_HEADER);
   CreateLabel("biases_toggle", g_biases_expanded ? "[-]" : "[+]", x_toggle, y_offset, COLOR_TOGGLE, FONT_SIZE_HEADER); y_offset += SPACING_MEDIUM;
   if(g_biases_expanded)
   {
      string tf_bias_strings[] = {"M15", "M30", "H1", "H2", "H4", "D1"};
      int x_col_tf = x_col1, x_col_bias = x_col1 + 40, x_col_zone = x_col1 + 95, x_col_magnet = x_col1 + 160;
      for(int i = 0; i < ArraySize(tf_bias_strings); i++)
      {
         string tf = tf_bias_strings[i];
         CreateLabel("biases_" + tf + "_prefix", tf + ":", x_col_tf, y_offset, COLOR_HEADER);
         CreateLabel("biases_" + tf + "_value", "---", x_col_bias, y_offset, COLOR_NA);
         CreateLabel("zone_" + tf + "_value", "---", x_col_zone, y_offset, COLOR_NA);
         CreateLabel("magnet_" + tf + "_value", "---", x_col_magnet, y_offset, COLOR_NA);
         y_offset += SPACING_MEDIUM;
      }
   }
   y_offset += SPACING_SEPARATOR - (g_biases_expanded ? SPACING_MEDIUM : 0);
   DrawSeparator("sep1", y_offset, x_offset);

   // --- Zone Interaction Status Section ---
   CreateLabel("zone_interaction_header", "ZONE STATUS", x_col1, y_offset, COLOR_HEADER, FONT_SIZE_HEADER);
   y_offset += SPACING_MEDIUM;
   CreateRectangle("zone_interaction_highlight", x_col1 - 5, y_offset - 2, PANE_WIDTH - 20, 14, COLOR_HIGHLIGHT_NONE);
   CreateLabel("zone_interaction_status", "NO ZONE INTERACTION", x_col1, y_offset, COLOR_NA, FONT_SIZE_NORMAL); y_offset += SPACING_MEDIUM;
   int x_qual_1 = x_col1 + 5, x_qual_2 = x_col1 + 110;
   CreateLabel("zone_qual_str_prefix", "Strength:", x_qual_1, y_offset, COLOR_HEADER);
   CreateLabel("zone_qual_str_value", "N/A", x_qual_2, y_offset, COLOR_NA); y_offset += SPACING_MEDIUM;
   CreateLabel("zone_qual_fresh_prefix", "Fresh:", x_qual_1, y_offset, COLOR_HEADER); CreateLabel("zone_qual_fresh_value", "N/A", x_qual_2, y_offset, COLOR_NA);
   y_offset += SPACING_MEDIUM;
   CreateLabel("zone_qual_vol_prefix", "Volume:", x_qual_1, y_offset, COLOR_HEADER); CreateLabel("zone_qual_vol_value", "N/A", x_qual_2, y_offset, COLOR_NA); y_offset += SPACING_MEDIUM;
   CreateLabel("zone_qual_liq_prefix", "Liquidity Grab:", x_qual_1, y_offset, COLOR_HEADER); CreateLabel("zone_qual_liq_value", "N/A", x_qual_2, y_offset, COLOR_NA); y_offset += SPACING_MEDIUM;
   DrawSeparator("sep_zone", y_offset, x_offset);
   
   // --- Zone Heatmap Section ---
   if(ShowZoneHeatmap)
   {
      CreateLabel("heatmap_header", "ZONE HEATMAP", x_col1, y_offset, COLOR_HEADER, FONT_SIZE_HEADER);
      y_offset += SPACING_MEDIUM;
      int heatmap_x = x_col1 + 10;
      for(int i = 0; i < ArraySize(g_heatmap_tf_strings); i++)
      {
         string tf = g_heatmap_tf_strings[i];
         CreateLabel("heatmap_tf_" + tf, tf, heatmap_x, y_offset, COLOR_HEADER, FONT_SIZE_NORMAL, ANCHOR_CENTER);
         CreateLabel("heatmap_status_" + tf, "-", heatmap_x, y_offset + 12, COLOR_NA, FONT_SIZE_NORMAL, ANCHOR_CENTER);
         heatmap_x += 35;
      }
      y_offset += SPACING_LARGE;
      DrawSeparator("sep_heatmap", y_offset, x_offset);
   }

   // --- Magnet Projection Section ---
   if(ShowMagnetProjection)
   {
      CreateLabel("magnet_header", "MAGNET PROJECTION", x_col1, y_offset, COLOR_HEADER, FONT_SIZE_HEADER);
      y_offset += SPACING_MEDIUM;
      CreateLabel("magnet_level", "Magnet → ---", x_col1, y_offset, COLOR_NEUTRAL_TEXT, FONT_SIZE_NORMAL + 1);
      CreateLabel("magnet_relation", "(---)", x_col1 + 150, y_offset, COLOR_NA, FONT_SIZE_NORMAL);
      y_offset += SPACING_MEDIUM;
      DrawSeparator("sep_magnet", y_offset, x_offset);
   }

   // --- Multi-TF Magnet Summary Section ---
   if(ShowMultiTFMagnets)
   {
      CreateLabel("mtf_magnet_header", "MULTI-TF MAGNETS", x_col1, y_offset, COLOR_HEADER, FONT_SIZE_HEADER);
      y_offset += SPACING_MEDIUM;
      int mtf_magnet_x1 = x_col1, mtf_magnet_x2 = x_col1 + 70, mtf_magnet_x3 = x_col1 + 140;
      for(int i = 0; i < ArraySize(g_magnet_summary_tfs); i++)
      {
         string tf = g_magnet_summary_tf_strings[i];
         CreateLabel("mtf_magnet_tf_" + tf, tf + " →", mtf_magnet_x1, y_offset, COLOR_HEADER);
         CreateLabel("mtf_magnet_relation_" + tf, "---", mtf_magnet_x2, y_offset, COLOR_NA);
         CreateLabel("mtf_magnet_level_" + tf, "(---)", mtf_magnet_x3, y_offset, COLOR_NA); y_offset += SPACING_MEDIUM;
      }
      DrawSeparator("sep_mtf_magnet", y_offset, x_offset);
   }

   // --- HUD Zone Activity Section ---
   if(ShowHUDActivitySection)
   {
      CreateLabel("hud_activity_header", "HUD ZONE ACTIVITY", x_col1, y_offset, COLOR_HEADER, FONT_SIZE_HEADER);
      y_offset += SPACING_MEDIUM;
      int hud_activity_x = x_col1 + 20;
      for(int i = 0; i < ArraySize(g_hud_tf_strings); i++)
      {
         string tf = g_hud_tf_strings[i];
         CreateLabel("hud_activity_tf_" + tf, tf, hud_activity_x, y_offset, COLOR_HEADER, FONT_SIZE_NORMAL, ANCHOR_CENTER);
         CreateLabel("hud_activity_status_" + tf, "N/A", hud_activity_x, y_offset + 12, COLOR_NA, FONT_SIZE_NORMAL + 2, ANCHOR_CENTER);
         hud_activity_x += 45;
      }
      y_offset += SPACING_LARGE;
      DrawSeparator("sep_hud_activity", y_offset, x_offset);
   }

   // --- Confidence Matrix Section ---
   if(ShowConfidenceMatrix)
   {
      CreateLabel("matrix_header", "CONFIDENCE MATRIX", x_col1, y_offset, COLOR_HEADER, FONT_SIZE_HEADER);
      y_offset += SPACING_MEDIUM;
      CreateLabel("matrix_hdr_tf", "TF", x_col1, y_offset, COLOR_HEADER); CreateLabel("matrix_hdr_bias", "Bias", x_col1 + 40, y_offset, COLOR_HEADER);
      CreateLabel("matrix_hdr_zone", "Zone", x_col1 + 100, y_offset, COLOR_HEADER); CreateLabel("matrix_hdr_score", "Score", x_col1 + 160, y_offset, COLOR_HEADER); y_offset += SPACING_MEDIUM;
      for(int i = 0; i < ArraySize(g_matrix_tfs); i++)
      {
         string tf = g_matrix_tf_strings[i];
         CreateRectangle("matrix_bg_" + tf, x_col1 - 5, y_offset - 2, PANE_WIDTH - 20, 14, clrNONE);
         CreateLabel("matrix_tf_" + tf, tf, x_col1, y_offset, COLOR_NEUTRAL_TEXT); CreateLabel("matrix_bias_" + tf, "---", x_col1 + 40, y_offset, COLOR_NA);
         CreateLabel("matrix_zone_" + tf, "---", x_col1 + 100, y_offset, COLOR_NA); CreateLabel("matrix_magnet_" + tf, "---", x_col1 + 160, y_offset, COLOR_NA);
         y_offset += SPACING_MEDIUM;
      }
      DrawSeparator("sep_matrix", y_offset, x_offset);
   }
   
   // --- MERGED: Final Signal Section (from Stable v1.8.3) ---
   CreateLabel("signal_header", "Final Signal (H1)", x_col1, y_offset, COLOR_HEADER, FONT_SIZE_HEADER);
   y_offset += SPACING_MEDIUM;
   CreateLabel("signal_dir_prefix", "Signal:", x_col1, y_offset, COLOR_HEADER);
   CreateLabel("signal_dir_value", "N/A", x_col2, y_offset, COLOR_NA);
   y_offset += SPACING_MEDIUM;
   CreateLabel("signal_conf_prefix", "Confidence:", x_col1, y_offset, COLOR_HEADER);
   CreateLabel("signal_conf_percent", "(0%)", x_col2, y_offset, COLOR_NEUTRAL_TEXT);
   y_offset += SPACING_MEDIUM;
   CreateRectangle("signal_conf_bar_bg", x_col2, y_offset, CONFIDENCE_BAR_MAX_WIDTH, 10, clrGray);
   CreateRectangle("signal_conf_bar_fg", x_col2, y_offset, 0, 10, clrNONE);
   y_offset += SPACING_MEDIUM;
   CreateLabel("magnet_zone_prefix", "Magnet Zone:", x_col1, y_offset, COLOR_HEADER);
   CreateLabel("magnet_zone_value", "N/A", x_col2, y_offset, COLOR_NA);
   y_offset += SPACING_SEPARATOR;
   DrawSeparator("sep_final_signal", y_offset, x_offset);


   // --- Trade Recommendation Section ---
   if(ShowTradeRecommendation)
   {
      CreateLabel("reco_header", "TRADE RECOMMENDATION", x_col1, y_offset, COLOR_HEADER, FONT_SIZE_HEADER);
      y_offset += SPACING_MEDIUM;
      CreateLabel("reco_action_prefix", "Action:", x_col1, y_offset, COLOR_HEADER); CreateLabel("reco_action_value", "WAIT", x_col1 + 70, y_offset, COLOR_NO_SIGNAL); y_offset += SPACING_MEDIUM;
      CreateLabel("reco_reason_prefix", "Reason:", x_col1, y_offset, COLOR_HEADER); CreateLabel("reco_reason_value", "---", x_col1 + 70, y_offset, COLOR_NEUTRAL_TEXT); y_offset += SPACING_MEDIUM;
      DrawSeparator("sep_reco", y_offset, x_offset);
   }

   // --- Risk & Positioning Section ---
   if(ShowRiskModule)
   {
      CreateLabel("risk_header", "RISK & POSITIONING", x_col1, y_offset, COLOR_HEADER, FONT_SIZE_HEADER);
      y_offset += SPACING_MEDIUM;
      CreateLabel("risk_pct_prefix", "Risk %:", x_col1, y_offset, COLOR_HEADER, FONT_SIZE_NORMAL); CreateLabel("risk_pct_value", "---", x_col2, y_offset, COLOR_NEUTRAL_TEXT, FONT_SIZE_NORMAL); y_offset += SPACING_MEDIUM;
      CreateLabel("risk_pos_size_prefix", "Position Size:", x_col1, y_offset, COLOR_HEADER, FONT_SIZE_NORMAL); CreateLabel("risk_pos_size_value", "---", x_col2, y_offset, COLOR_NEUTRAL_TEXT, FONT_SIZE_NORMAL); y_offset += SPACING_MEDIUM;
      CreateLabel("risk_rr_prefix", "RR Ratio:", x_col1, y_offset, COLOR_HEADER, FONT_SIZE_NORMAL); CreateLabel("risk_rr_value", "---", x_col2, y_offset, COLOR_NEUTRAL_TEXT, FONT_SIZE_NORMAL); y_offset += SPACING_MEDIUM;
      DrawSeparator("sep_risk", y_offset, x_offset);
   }

   // --- Session & Volatility Section ---
   if(ShowSessionModule)
   {
      CreateLabel("session_header", "SESSION & VOLATILITY", x_col1, y_offset, COLOR_HEADER, FONT_SIZE_HEADER);
      y_offset += SPACING_MEDIUM;
      CreateLabel("session_name_prefix", "Active Session:", x_col1, y_offset, COLOR_HEADER); CreateLabel("session_name_value", "---", x_col2, y_offset, COLOR_NEUTRAL_TEXT); y_offset += SPACING_MEDIUM;
      CreateLabel("session_overlap_prefix", "Session Overlap:", x_col1, y_offset, COLOR_HEADER); CreateLabel("session_overlap_value", "---", x_col2, y_offset, COLOR_NEUTRAL_TEXT); y_offset += SPACING_MEDIUM;
      CreateLabel("session_vol_prefix", "Volatility:", x_col1, y_offset, COLOR_HEADER);
      CreateRectangle("session_vol_bg", x_col2, y_offset - 2, 60, 14, clrNONE); CreateLabel("session_vol_value", "---", x_col2 + 4, y_offset, COLOR_NEUTRAL_TEXT); y_offset += SPACING_MEDIUM;
      DrawSeparator("sep_session", y_offset, x_offset);
   }

   // --- Trade Info Section ---
   CreateLabel("trade_header", "Trade Info", x_col1, y_offset, COLOR_HEADER);
   y_offset += SPACING_MEDIUM;
   CreateLabel("trade_entry_prefix", "Entry:", x_col1, y_offset, COLOR_HEADER); CreateLabel("trade_entry_value", "-", x_col2, y_offset, COLOR_NEUTRAL_TEXT); y_offset += SPACING_MEDIUM;
   CreateLabel("trade_tp_prefix", "TP:", x_col1, y_offset, COLOR_HEADER); CreateLabel("trade_tp_value", "-", x_col2, y_offset, COLOR_NEUTRAL_TEXT); y_offset += SPACING_MEDIUM;
   CreateLabel("trade_sl_prefix", "SL:", x_col1, y_offset, COLOR_HEADER);
   CreateLabel("trade_sl_value", "-", x_col2, y_offset, COLOR_NEUTRAL_TEXT); y_offset += SPACING_MEDIUM;
   CreateLabel("trade_status_prefix", "Status:", x_col1, y_offset, COLOR_HEADER); CreateLabel("trade_status_value", "☐ No Trade", x_col2, y_offset, COLOR_NEUTRAL_TEXT);
   y_offset += SPACING_SEPARATOR;
   DrawSeparator("sep4", y_offset, x_offset);

   // --- Trade Signal Section ---
   CreateLabel("trade_signal_header", "TRADE SIGNAL", x_col1, y_offset, COLOR_HEADER, FONT_SIZE_HEADER);
   CreateLabel("trade_signal_status", "NO SIGNAL", x_col2, y_offset, COLOR_NO_SIGNAL, FONT_SIZE_SIGNAL);
   y_offset += SPACING_LARGE;
   DrawSeparator("sep_final", y_offset, x_offset);
   
   // --- Alfred Says Section ---
   if(ShowAlfredSays)
   {
      CreateLabel("alfred_says_header", "🗣️ ALFRED SAYS", x_col1, y_offset, COLOR_HEADER, FONT_SIZE_HEADER);
      y_offset += SPACING_MEDIUM;
      CreateLabel("alfred_says_comment", "...", x_col1, y_offset, COLOR_TEXT_DIM, FONT_SIZE_NORMAL);
      y_offset += SPACING_LARGE;
   }

   // --- Footer & Debug Info ---
   CreateLabel("footer", "AlfredAI™ Pane · v2.0 · Built for Traders", PANE_X_POS + PANE_WIDTH - 10, y_offset, COLOR_FOOTER, FONT_SIZE_NORMAL - 1, ANCHOR_RIGHT);
   y_offset += SPACING_MEDIUM;
   if(ShowDebugInfo)
   {
      CreateLabel("debug_info", "---", x_offset, y_offset, COLOR_TEXT_DIM, FONT_SIZE_NORMAL - 1);
      y_offset += SPACING_MEDIUM;
   }

   // --- Background ---
   string bg_name = PANE_PREFIX + "background";
   ObjectCreate(0, bg_name, OBJ_RECTANGLE_LABEL, 0, 0, 0);
   ObjectSetInteger(0, bg_name, OBJPROP_XDISTANCE, PANE_X_POS);
   ObjectSetInteger(0, bg_name, OBJPROP_YDISTANCE, PANE_Y_POS);
   ObjectSetInteger(0, bg_name, OBJPROP_XSIZE, PANE_WIDTH);
   ObjectSetInteger(0, bg_name, OBJPROP_YSIZE, y_offset - PANE_Y_POS);
   ObjectSetInteger(0, bg_name, OBJPROP_BACK, true);
   ObjectSetInteger(0, bg_name, OBJPROP_BORDER_TYPE, BORDER_FLAT);
   ObjectSetInteger(0, bg_name, OBJPROP_COLOR, clrNONE);
   color bg_color_opacity = (color)ColorToARGB(PANE_BG_COLOR, PANE_BG_OPACITY);
   ObjectSetInteger(0, bg_name, OBJPROP_BGCOLOR, bg_color_opacity);
}

//+------------------------------------------------------------------+
//| UpdatePanel - Main display refresh logic.                        |
//+------------------------------------------------------------------+
void UpdatePanel()
{
   // --- Update Alfred Signal Section ---
   if(ShowAlfredBrainModule)
   {
       ENUM_TRADE_SIGNAL signal = g_brain_cache.signal;
       if(signal == SIGNAL_NONE)
       {
           UpdateLabel("brain_signal_value", "None", COLOR_NO_SIGNAL);
           UpdateLabel("brain_confidence_value", "🔹 Confidence: -- / 20", COLOR_TEXT_DIM);
           UpdateLabel("brain_setup_type_value", "🧱 Setup Type: ---", COLOR_TEXT_DIM);
           UpdateLabel("brain_reasoning_value", ReasonCodeToString(g_brain_cache.reasonCode), COLOR_TEXT_DIM);
       }
       else
       {
           string signal_text = (signal == SIGNAL_BUY) ? "BUY" : "SELL";
           UpdateLabel("brain_signal_value", signal_text, SignalToColor(signal));
           string conf_text = StringFormat("🔹 Confidence: %.0f / 20", g_brain_cache.confidence);
           UpdateLabel("brain_confidence_value", conf_text, COLOR_NEUTRAL_TEXT);
           ENUM_ZONE zone_type = GetZoneStatus(_Period);
           string zone_tf_str = PeriodMinutesToTFString(g_brain_cache.zoneTF);
           string setup_type_text = StringFormat("🧱 Setup Type: Reversal (%s %s Zone)", zone_tf_str, ZoneToString(zone_type));
           UpdateLabel("brain_setup_type_value", setup_type_text, COLOR_NEUTRAL_TEXT);
           UpdateLabel("brain_reasoning_value", ReasonCodeToString(g_brain_cache.reasonCode), COLOR_NEUTRAL_TEXT);
       }
   }

   // --- Update Upcoming News ---
   if(ShowNewsModule)
   {
      NewsEventData news_items[];
      ArrayResize(news_items, MAX_NEWS_ITEMS); int news_count = GetUpcomingNews(news_items);
      for(int i = 0; i < MAX_NEWS_ITEMS; i++)
      {
         string idx = IntegerToString(i);
         if(i < news_count)
         {
            UpdateLabel("news_time_" + idx, news_items[i].time, COLOR_TEXT_DIM); UpdateLabel("news_curr_" + idx, news_items[i].currency, COLOR_NEUTRAL_TEXT);
            ObjectSetString(0, PANE_PREFIX + "news_curr_" + idx, OBJPROP_FONT, "Arial Bold"); UpdateLabel("news_event_" + idx, news_items[i].event_name, COLOR_NEUTRAL_TEXT); UpdateLabel("news_impact_" + idx, NewsImpactToString(news_items[i].impact), NewsImpactToColor(news_items[i].impact));
         }
         else
         {
            UpdateLabel("news_time_" + idx, ""); UpdateLabel("news_curr_" + idx, ""); UpdateLabel("news_event_" + idx, ""); UpdateLabel("news_impact_" + idx, "");
         }
      }
   }

   // --- Update Emotional State ---
   if(ShowEmotionalState) { EmotionalStateData emotion_data = GetEmotionalState(); UpdateLabel("emotion_indicator", "●", EmotionalStateToColor(emotion_data.state)); UpdateLabel("emotion_text", emotion_data.text, COLOR_NEUTRAL_TEXT); }

   // --- Update Alert Center ---
   if(ShowAlertCenter) { AlertData alert_data = GetAlertCenterStatus(); UpdateLabel("alert_status", alert_data.text, AlertStatusToColor(alert_data.status)); }

   // --- Update Pane Settings ---
   if(ShowPaneSettings)
   {
      string on = "✅", off = "❌";
      color on_c = COLOR_BULL, off_c = COLOR_NO_SIGNAL;
      UpdateLabel("setting_matrix_value", ShowConfidenceMatrix ? on : off, ShowConfidenceMatrix ? on_c : off_c);
      UpdateLabel("setting_magnet_value", ShowMultiTFMagnets ? on : off, ShowMultiTFMagnets ? on_c : off_c);
      UpdateLabel("setting_heatmap_value", ShowZoneHeatmap ? on : off, ShowZoneHeatmap ? on_c : off_c);
      UpdateLabel("setting_hud_activity_value", ShowHUDActivitySection ? on : off, ShowHUDActivitySection ? on_c : off_c);
      UpdateLabel("setting_reco_value", ShowTradeRecommendation ? on : off, ShowTradeRecommendation ? on_c : off_c);
      UpdateLabel("setting_emotion_value", ShowEmotionalState ? on : off, ShowEmotionalState ? on_c : off_c);
      UpdateLabel("setting_alert_value", ShowAlertCenter ? on : off, ShowAlertCenter ? on_c : off_c);
   }

   // --- Update TF Biases & Zones ---
   if(g_biases_expanded)
   {
      string tf_bias_strings[] = {"M15", "M30", "H1", "H2", "H4", "D1"};
      ENUM_TIMEFRAMES tf_bias_enums[] = {PERIOD_M15, PERIOD_M30, PERIOD_H1, PERIOD_H2, PERIOD_H4, PERIOD_D1}; double current_price = SymbolInfoDouble(_Symbol, SYMBOL_BID);
      for(int i = 0; i < ArraySize(tf_bias_strings); i++)
      {
         string tf_str = tf_bias_strings[i]; ENUM_TIMEFRAMES tf_enum = tf_bias_enums[i];
         double raw_zone_val = iCustom(_Symbol, tf_enum, "AAI_Indicator_ZoneEngine.ex5", 0, 0); double magnet_level = iCustom(_Symbol, tf_enum, "AAI_Indicator_ZoneEngine.ex5", 1, 0); int zone_val = 0;
         if(raw_zone_val > 0.5) zone_val = 1; else if(raw_zone_val < -0.5) zone_val = -1; UpdateLabel("biases_" + tf_str + "_value", GetBiasLabelFromZone(zone_val), GetBiasColorFromZone(zone_val));
         ENUM_ZONE zone_enum = ZONE_NONE; if(zone_val == 1) zone_enum = ZONE_DEMAND; else if(zone_val == -1) zone_enum = ZONE_SUPPLY;
         UpdateLabel("zone_" + tf_str + "_value", ZoneToString(zone_enum), ZoneToColor(zone_enum));
         string magnet_text = GetMagnetRelationLabel(current_price, magnet_level); UpdateLabel("magnet_" + tf_str + "_value", magnet_text, GetMagnetRelationColor(magnet_text));
      }
   }

   // --- Update Zone Interaction Status ---
   ENUM_ZONE_INTERACTION interaction = GetCurrentZoneInteraction();
   UpdateLabel("zone_interaction_status", ZoneInteractionToString(interaction), ZoneInteractionToColor(interaction));
   ObjectSetInteger(0, PANE_PREFIX + "zone_interaction_highlight", OBJPROP_BGCOLOR, ZoneInteractionToHighlightColor(interaction));
   if(interaction != INTERACTION_NONE)
   {
      CachedSupDemData zone_data = GetSupDemData(_Period);
      UpdateLabel("zone_qual_str_value", StringFormat("%.0f/10", zone_data.strength), COLOR_NEUTRAL_TEXT);
      string fresh_text = (zone_data.freshness > 0.5) ? "Yes" : "No"; color fresh_color = (zone_data.freshness > 0.5) ? COLOR_BULL : COLOR_BEAR;
      UpdateLabel("zone_qual_fresh_value", fresh_text, fresh_color);
      string vol_text = (zone_data.volume > 0.5) ? "Yes" : "No"; color vol_color = (zone_data.volume > 0.5) ? COLOR_BULL : COLOR_BEAR;
      UpdateLabel("zone_qual_liq_value", (zone_data.liquidity > 0.5) ? "CONFIRMED" : "No", (zone_data.liquidity > 0.5) ? clrLime : COLOR_BEAR);
      ObjectSetString(0, PANE_PREFIX + "zone_qual_liq_value", OBJPROP_FONT, (zone_data.liquidity > 0.5) ? "Arial Bold" : "Arial");
   }
   else
   {
      UpdateLabel("zone_qual_str_value", "N/A", COLOR_NA); UpdateLabel("zone_qual_fresh_value", "N/A", COLOR_NA); UpdateLabel("zone_qual_vol_value", "N/A", COLOR_NA); UpdateLabel("zone_qual_liq_value", "N/A", COLOR_NA);
      ObjectSetString(0, PANE_PREFIX + "zone_qual_liq_value", OBJPROP_FONT, "Arial");
   }

   // --- Update Zone Heatmap ---
   if(ShowZoneHeatmap)
   {
      for(int i = 0; i < ArraySize(g_heatmap_tfs); i++)
      {
         ENUM_TIMEFRAMES tf = g_heatmap_tfs[i];
         string tf_str = g_heatmap_tf_strings[i]; int strength_score = (int)MathRound(iCustom(_Symbol, tf, "AAI_Indicator_ZoneEngine.ex5", 2, 0)); string heatmap_text;
         if(strength_score >= 8) heatmap_text = "🔥 " + IntegerToString(strength_score); else if(strength_score >= 5) heatmap_text = "🟧 " + IntegerToString(strength_score);
         else if(strength_score >= 1) heatmap_text = "🟨 " + IntegerToString(strength_score); else heatmap_text = "⚪ " + IntegerToString(strength_score);
         UpdateLabel("heatmap_status_" + tf_str, heatmap_text, GetHeatColorForStrength(strength_score));
      }
   }

   // --- Update Magnet Projection ---
   if(ShowMagnetProjection)
   {
      double magnet_level = GetMagnetProjectionLevel();
      double current_price = SymbolInfoDouble(_Symbol, SYMBOL_BID); ENUM_MAGNET_RELATION relation = GetMagnetProjectionRelation(current_price, magnet_level);
      string level_text = (magnet_level == 0.0) ? "---" : StringFormat("%." + IntegerToString(_Digits) + "f", magnet_level);
      UpdateLabel("magnet_level", "Magnet → " + level_text, COLOR_NEUTRAL_TEXT);
      UpdateLabel("magnet_relation", MagnetRelationToString(relation), MagnetRelationToColor(relation));
   }

   // --- Update Multi-TF Magnet Summary ---
   if(ShowMultiTFMagnets)
   {
      double current_price = SymbolInfoDouble(_Symbol, SYMBOL_BID);
      double proximity = 2 * _Point; for(int i = 0; i < ArraySize(g_magnet_summary_tfs); i++)
      {
         ENUM_TIMEFRAMES tf = g_magnet_summary_tfs[i];
         string tf_str = g_magnet_summary_tf_strings[i]; double magnet_level = iCustom(_Symbol, tf, "AAI_Indicator_ZoneEngine.ex5", 1, 0); string relation_text; color relation_color;
         if(magnet_level > 0.0)
         {
            if (current_price > magnet_level + proximity) { relation_text = "Above"; relation_color = clrOrangeRed; }
            else if (current_price < magnet_level - proximity) { relation_text = "Below"; relation_color = clrLimeGreen; }
            else { relation_text = "At Magnet"; relation_color = clrGray; }
         }
         else { relation_text = "N/A"; relation_color = COLOR_NA; }
         string level_text = (magnet_level == 0.0) ? "(N/A)" : StringFormat("(%." + IntegerToString(_Digits) + "f)", magnet_level);
         UpdateLabel("mtf_magnet_relation_" + tf_str, relation_text, relation_color); UpdateLabel("mtf_magnet_level_" + tf_str, level_text, relation_color);
      }
   }

   // --- Update HUD Zone Activity ---
   if(ShowHUDActivitySection)
   {
      for(int i = 0; i < ArraySize(g_hud_tfs); i++)
      {
         ENUM_TIMEFRAMES tf = g_hud_tfs[i];
         string tf_str = g_hud_tf_strings[i];
         if(tf == PERIOD_D1) { UpdateLabel("hud_activity_status_" + tf_str, "N/A", COLOR_NA); continue; }
         bool is_active = GetHUDZoneActivity(tf);
         string status_text = is_active ? "✅" : "❌"; color status_color = is_active ? COLOR_BULL : COLOR_BEAR;
         UpdateLabel("hud_activity_status_" + tf_str, status_text, status_color);
      }
   }

   // --- Update Confidence Matrix ---
   if(ShowConfidenceMatrix)
   {
      for(int i = 0; i < ArraySize(g_matrix_tfs); i++)
      {
         ENUM_TIMEFRAMES tf = g_matrix_tfs[i];
         string tf_str = g_matrix_tf_strings[i]; MatrixRowData data = GetConfidenceMatrixRow(tf); UpdateLabel("matrix_bias_" + tf_str, BiasToString(data.bias), BiasToColor(data.bias)); UpdateLabel("matrix_zone_" + tf_str, ZoneToString(data.zone), ZoneToColor(data.zone));
         UpdateLabel("matrix_magnet_" + tf_str, IntegerToString(data.score), COLOR_NEUTRAL_TEXT);
         ObjectSetInteger(0, PANE_PREFIX + "matrix_bg_" + tf_str, OBJPROP_BGCOLOR, GetConfidenceColor(data.score));
         string font_style = (data.score >= 10) ? "Arial Bold" : "Arial";
         ObjectSetString(0, PANE_PREFIX + "matrix_tf_" + tf_str, OBJPROP_FONT, font_style); ObjectSetString(0, PANE_PREFIX + "matrix_bias_" + tf_str, OBJPROP_FONT, font_style);
         ObjectSetString(0, PANE_PREFIX + "matrix_zone_" + tf_str, OBJPROP_FONT, font_style); ObjectSetString(0, PANE_PREFIX + "matrix_magnet_" + tf_str, OBJPROP_FONT, font_style);
      }
   }
   
   // --- MERGED: Update Final Signal (H1) with Dynamic Confidence (from Stable v1.8.3) ---
   CompassData h1_compass = GetCompassData(PERIOD_H1);
   UpdateLabel("signal_dir_value", BiasToString(h1_compass.bias), BiasToColor(h1_compass.bias));
   double base_conf = h1_compass.confidence;
   double adjusted_conf = base_conf;
   if(interaction == INTERACTION_INSIDE_DEMAND && h1_compass.bias == BIAS_BULL)
   {
      adjusted_conf += 5;
   }
   if(interaction == INTERACTION_INSIDE_SUPPLY && h1_compass.bias == BIAS_BEAR)
   {
      adjusted_conf += 5;
   }
   adjusted_conf = MathMin(100, adjusted_conf);
   color conf_color = adjusted_conf > 70 ? COLOR_CONF_HIGH : adjusted_conf > 40 ? COLOR_CONF_MED : COLOR_CONF_LOW;
   UpdateLabel("signal_conf_percent", StringFormat("(%.0f%%)", adjusted_conf), conf_color);
   int bar_width = (int)(adjusted_conf / 100.0 * CONFIDENCE_BAR_MAX_WIDTH);
   string bar_name = PANE_PREFIX + "signal_conf_bar_fg";
   ObjectSetInteger(0, bar_name, OBJPROP_XSIZE, bar_width);
   ObjectSetInteger(0, bar_name, OBJPROP_BGCOLOR, conf_color);
   ObjectSetInteger(0, bar_name, OBJPROP_COLOR, conf_color);
   ENUM_ZONE h1_zone = GetZoneStatus(PERIOD_H1);
   UpdateLabel("magnet_zone_value", ZoneToString(h1_zone), ZoneToColor(h1_zone));

   // --- Update Trade Recommendation ---
   if(ShowTradeRecommendation)
   {
      TradeRecommendation rec = GetTradeRecommendation();
      UpdateLabel("reco_action_value", RecoActionToString(rec.action), RecoActionToColor(rec.action)); UpdateLabel("reco_reason_value", rec.reasoning, COLOR_NEUTRAL_TEXT);
      string reco_obj = PANE_PREFIX + "reco_action_value";
      ObjectSetString(0, reco_obj, OBJPROP_FONT, (rec.action == SIGNAL_NONE) ? "Arial Italic" : "Arial Bold");
   }

   // --- Update Risk & Positioning ---
   if(ShowRiskModule)
   {
      RiskModuleData risk_data = GetRiskModuleData();
      UpdateLabel("risk_pct_value", StringFormat("%.1f%%", risk_data.risk_percent), COLOR_NEUTRAL_TEXT); UpdateLabel("risk_pos_size_value", StringFormat("%.2f lots", risk_data.position_size), COLOR_NEUTRAL_TEXT); UpdateLabel("risk_rr_value", risk_data.rr_ratio, COLOR_NEUTRAL_TEXT);
      ObjectSetString(0, PANE_PREFIX + "risk_rr_value", OBJPROP_FONT, "Arial Bold");
   }

   // --- Update Session & Volatility ---
   if(ShowSessionModule)
   {
      SessionData s_data = GetSessionData();
      UpdateLabel("session_name_value", s_data.session_name, COLOR_SESSION); UpdateLabel("session_overlap_value", s_data.session_overlap, COLOR_NEUTRAL_TEXT);
      UpdateLabel("session_vol_value", VolatilityToString(s_data.volatility), VolatilityToColor(s_data.volatility));
      ObjectSetString(0, PANE_PREFIX + "session_vol_value", OBJPROP_FONT, "Arial Bold");
      ObjectSetInteger(0, PANE_PREFIX + "session_vol_bg", OBJPROP_BGCOLOR, VolatilityToHighlightColor(s_data.volatility));
   }

   // --- Update Trade Data ---
   LiveTradeData trade_data = FetchTradeLevels();
   string price_format = "%." + IntegerToString(_Digits) + "f";
   if(trade_data.trade_exists)
   {
      UpdateLabel("trade_entry_value", StringFormat(price_format, trade_data.entry), COLOR_NEUTRAL_TEXT);
      double sl_pips = (trade_data.sl > 0) ? CalculatePips(trade_data.entry, trade_data.sl) : 0.0; double tp_pips = (trade_data.tp > 0) ? CalculatePips(trade_data.entry, trade_data.tp) : 0.0;
      string sl_text = (trade_data.sl > 0) ? StringFormat(price_format, trade_data.sl) + StringFormat(" (-%.1f p)", sl_pips) : "---";
      string tp_text = (trade_data.tp > 0) ? StringFormat(price_format, trade_data.tp) + StringFormat(" (+%.1f p)", tp_pips) : "---";
      UpdateLabel("trade_sl_value", sl_text, COLOR_BEAR);
      UpdateLabel("trade_tp_value", tp_text, COLOR_BULL);
      UpdateLabel("trade_status_value", "☑ Active", COLOR_BULL);
   }
   else
   {
      UpdateLabel("trade_entry_value", "---", COLOR_NEUTRAL_TEXT); UpdateLabel("trade_sl_value", "---", COLOR_NEUTRAL_TEXT);
      UpdateLabel("trade_tp_value", "---", COLOR_NEUTRAL_TEXT); UpdateLabel("trade_status_value", "☐ No Trade", COLOR_NEUTRAL_TEXT);
   }

   // --- Update Final Trade Signal (from Recommendation) ---
   ENUM_TRADE_SIGNAL signal = GetTradeSignal();
   string signal_obj = PANE_PREFIX + "trade_signal_status"; ObjectSetString(0, signal_obj, OBJPROP_TEXT, SignalToString(signal)); ObjectSetInteger(0, signal_obj, OBJPROP_COLOR, SignalToColor(signal));
   ObjectSetString(0, signal_obj, OBJPROP_FONT, (signal == SIGNAL_NONE) ? "Arial Italic" : "Arial Bold");
   ObjectSetInteger(0, signal_obj, OBJPROP_FONTSIZE, (signal == SIGNAL_NONE) ? FONT_SIZE_SIGNAL : FONT_SIZE_SIGNAL_ACTIVE);
   
   // --- Update Alfred Says ---
   if(ShowAlfredSays)
   {
      AlfredComment alfred_comment = GetAlfredComment();
      if(alfred_comment.text != g_last_alfred_comment)
      {
         UpdateLabel("alfred_says_comment", alfred_comment.text, alfred_comment.clr);
         g_last_alfred_comment = alfred_comment.text;
      }
   }

   // --- Update Debug Info ---
   if(ShowDebugInfo)
   {
      int active_modules = 0;
      if(ShowZoneHeatmap) active_modules++; if(ShowMagnetProjection) active_modules++; if(ShowMultiTFMagnets) active_modules++; if(ShowHUDActivitySection) active_modules++; if(ShowConfidenceMatrix) active_modules++; if(ShowTradeRecommendation) active_modules++; if(ShowRiskModule) active_modules++; if(ShowSessionModule) active_modules++; if(ShowNewsModule) active_modules++; if(ShowEmotionalState) active_modules++;
      if(ShowAlertCenter) active_modules++; if(ShowPaneSettings) active_modules++;
      string debug_text = StringFormat("Modules Active: %d | %s · %s | Updated: %s", active_modules, _Symbol, EnumToString(_Period), TimeToString(TimeCurrent(), TIME_SECONDS));
      UpdateLabel("debug_info", debug_text);
   }

   ChartRedraw();
}

//+------------------------------------------------------------------+
//| Redraws the entire panel after a state change                    |
//+------------------------------------------------------------------+
void RedrawPanel()
{
   ObjectsDeleteAll(0, PANE_PREFIX);
   CreatePanel();
   UpdatePanel();
   ChartRedraw();
}

//+------------------------------------------------------------------+
//|                        Custom indicator initialization function  |
//+------------------------------------------------------------------+
int OnInit()
{
    // FIX: Initialize global arrays inside OnInit
    ArrayResize(g_timeframe_strings, 7);
    g_timeframe_strings[0] = "M1"; g_timeframe_strings[1] = "M5"; g_timeframe_strings[2] = "M15"; g_timeframe_strings[3] = "M30";
    g_timeframe_strings[4] = "H1"; g_timeframe_strings[5] = "H4"; g_timeframe_strings[6] = "D1";

    ArrayResize(g_timeframes, 7);
    g_timeframes[0] = PERIOD_M1; g_timeframes[1] = PERIOD_M5; g_timeframes[2] = PERIOD_M15; g_timeframes[3] = PERIOD_M30;
    g_timeframes[4] = PERIOD_H1; g_timeframes[5] = PERIOD_H4; g_timeframes[6] = PERIOD_D1;

    ArrayResize(g_heatmap_tf_strings, 6);
    g_heatmap_tf_strings[0] = "M15"; g_heatmap_tf_strings[1] = "M30"; g_heatmap_tf_strings[2] = "H1";
    g_heatmap_tf_strings[3] = "H2"; g_heatmap_tf_strings[4] = "H4"; g_heatmap_tf_strings[5] = "D1";

    ArrayResize(g_heatmap_tfs, 6);
    g_heatmap_tfs[0] = PERIOD_M15; g_heatmap_tfs[1] = PERIOD_M30; g_heatmap_tfs[2] = PERIOD_H1;
    g_heatmap_tfs[3] = PERIOD_H2; g_heatmap_tfs[4] = PERIOD_H4; g_heatmap_tfs[5] = PERIOD_D1;

    ArrayResize(g_magnet_summary_tf_strings, 6);
    g_magnet_summary_tf_strings[0] = "M15"; g_magnet_summary_tf_strings[1] = "M30"; g_magnet_summary_tf_strings[2] = "H1";
    g_magnet_summary_tf_strings[3] = "H2"; g_magnet_summary_tf_strings[4] = "H4"; g_magnet_summary_tf_strings[5] = "D1";

    ArrayResize(g_magnet_summary_tfs, 6);
    g_magnet_summary_tfs[0] = PERIOD_M15; g_magnet_summary_tfs[1] = PERIOD_M30; g_magnet_summary_tfs[2] = PERIOD_H1;
    g_magnet_summary_tfs[3] = PERIOD_H2; g_magnet_summary_tfs[4] = PERIOD_H4; g_magnet_summary_tfs[5] = PERIOD_D1;

    ArrayResize(g_matrix_tf_strings, 6);
    g_matrix_tf_strings[0] = "M15"; g_matrix_tf_strings[1] = "M30"; g_matrix_tf_strings[2] = "H1";
    g_matrix_tf_strings[3] = "H2"; g_matrix_tf_strings[4] = "H4"; g_matrix_tf_strings[5] = "D1";
    
    ArrayResize(g_matrix_tfs, 6);
    g_matrix_tfs[0] = PERIOD_M15; g_matrix_tfs[1] = PERIOD_M30; g_matrix_tfs[2] = PERIOD_H1;
    g_matrix_tfs[3] = PERIOD_H2; g_matrix_tfs[4] = PERIOD_H4; g_matrix_tfs[5] = PERIOD_D1;

    ArrayResize(g_hud_tf_strings, 4);
    g_hud_tf_strings[0] = "M15"; g_hud_tf_strings[1] = "H1"; g_hud_tf_strings[2] = "H4"; g_hud_tf_strings[3] = "D1";

    ArrayResize(g_hud_tfs, 4);
    g_hud_tfs[0] = PERIOD_M15; g_hud_tfs[1] = PERIOD_H1; g_hud_tfs[2] = PERIOD_H4; g_hud_tfs[3] = PERIOD_D1;

   hATR_current = iATR(_Symbol, _Period, atr_period);
   g_pip_value = SymbolInfoDouble(_Symbol, SYMBOL_POINT);
   if(SymbolInfoInteger(_Symbol, SYMBOL_DIGITS) == 3 || SymbolInfoInteger(_Symbol, SYMBOL_DIGITS) == 5) g_pip_value *= 10;
   MathSrand((int)TimeCurrent());
   // Initialize caches with default values
   for(int i = 0; i < ArraySize(g_timeframes); i++)
   {
      g_compass_cache[i].bias = BIAS_NEUTRAL;
      g_compass_cache[i].confidence = 0.0;
      g_supdem_cache[i].zone = ZONE_NONE; g_supdem_cache[i].magnet_level = 0.0; g_supdem_cache[i].strength = 0.0; g_supdem_cache[i].freshness = 0.0; g_supdem_cache[i].volume = 0.0;
      g_supdem_cache[i].liquidity = 0.0;
      g_hud_cache[i].zone_active = false;
   }
   
   g_brain_cache.signal = SIGNAL_NONE;
   g_brain_cache.confidence = 0;
   g_brain_cache.reasonCode = REASON_NONE;
   g_brain_cache.zoneTF = 0;


   RedrawPanel();
   UpdateLiveDataCaches(); // Initial data load to prevent "N/A" on first view
   UpdatePanel();
   EventSetTimer(1); // Set timer to 1-second intervals
   return(INIT_SUCCEEDED);
}

//+------------------------------------------------------------------+
//|                        Timer function to trigger updates         |
//+------------------------------------------------------------------+
void OnTimer()
{
   UpdateLiveDataCaches(); // Fetch fresh data from indicators
   UpdatePanel(); // Update the display with cached data
}

//+------------------------------------------------------------------+
//| Custom indicator iteration function (not used for timer updates) |
//+------------------------------------------------------------------+
int OnCalculate(const int rates_total, const int p, const int b, const double &price[])
{
   return(rates_total);
}

//+------------------------------------------------------------------+
//|                        Chart event function                      |
//+------------------------------------------------------------------+
void OnChartEvent(const int id, const long &l, const double &d, const string &s)
{
   if(id == CHARTEVENT_OBJECT_CLICK)
   {
      bool changed = false;
      if(StringFind(s, PANE_PREFIX) == 0 && StringFind(s, "_toggle") > 0)
      {
         if(s == PANE_PREFIX + "biases_toggle") g_biases_expanded = !g_biases_expanded;
         changed = true;
      }
      if(changed) RedrawPanel();
   }
}

//+------------------------------------------------------------------+
//|                        Deinitialization function                 |
//+------------------------------------------------------------------+
void OnDeinit(const int reason)
{
   EventKillTimer();
   IndicatorRelease(hATR_current);
   ObjectsDeleteAll(0, PANE_PREFIX);
   ChartRedraw();
}
//+------------------------------------------------------------------+
