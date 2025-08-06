//+------------------------------------------------------------------+
//|                        AlfredAI_Pane.mq5                         |
//|             v1.8.4 - Confidence Matrix Upgrade                   |
//|                                                                  |
//| Copyright 2024, RudiKai                                          |
//|                     https://github.com/RudiKai                   |
//+------------------------------------------------------------------+
#property strict
#property indicator_chart_window
#property indicator_plots 0 // Suppress "no indicator plot" warning
#property version "1.8.4" // UPGRADED: Version reflects Confidence Matrix upgrade

// --- Optional Inputs ---
input bool ShowDebugInfo = false;
// Toggle for displaying debug information
input bool EnableDebugLogging = false;
// Toggle for printing detailed data fetch logs to the Experts tab
input bool ShowZoneHeatmap = true;
// Toggle for the Zone Heatmap
input bool ShowMagnetProjection = true;
// Toggle for the Magnet Projection status
input bool ShowMultiTFMagnets = true;
// Toggle for the Multi-TF Magnet Summary
input bool ShowHUDActivitySection = true;
// Toggle for the HUD Zone Activity section
input bool ShowConfidenceMatrix = true;
// Toggle for the Confidence Matrix
input bool ShowTradeRecommendation = true; // Toggle for the Trade Recommendation
input bool ShowRiskModule = true;
// Toggle for the Risk & Positioning module
input bool ShowSessionModule = true;
// Toggle for the Session & Volatility module
input bool ShowNewsModule = true;
// Toggle for the Upcoming News module
input bool ShowEmotionalState = true;
// Toggle for the Emotional State module
input bool ShowAlertCenter = true;
// Toggle for the Alert Center module
input bool ShowPaneSettings = true;
// Toggle for the Pane Settings summary module

// --- Includes
#include <ChartObjects\ChartObjectsTxtControls.mqh>

// --- Enums for State Management
enum ENUM_BIAS { BIAS_BULL, BIAS_BEAR, BIAS_NEUTRAL };
enum ENUM_ZONE { ZONE_DEMAND, ZONE_SUPPLY, ZONE_NONE };
enum ENUM_ZONE_INTERACTION { INTERACTION_INSIDE_DEMAND, INTERACTION_INSIDE_SUPPLY, INTERACTION_NONE };
enum ENUM_TRADE_SIGNAL { SIGNAL_NONE, SIGNAL_BUY, SIGNAL_SELL };
enum ENUM_HEATMAP_STATUS { HEATMAP_NONE, HEATMAP_DEMAND, HEATMAP_SUPPLY };
enum ENUM_MAGNET_RELATION { RELATION_ABOVE, RELATION_BELOW, RELATION_AT };
// MODIFIED: ENUM_MATRIX_CONFIDENCE is no longer needed.
// enum ENUM_MATRIX_CONFIDENCE { CONFIDENCE_WEAK, CONFIDENCE_MEDIUM, CONFIDENCE_STRONG };
enum ENUM_VOLATILITY { VOLATILITY_LOW, VOLATILITY_MEDIUM, VOLATILITY_HIGH };
enum ENUM_NEWS_IMPACT { IMPACT_LOW, IMPACT_MEDIUM, IMPACT_HIGH };
enum ENUM_EMOTIONAL_STATE { STATE_CAUTIOUS, STATE_CONFIDENT, STATE_OVEREXTENDED, STATE_ANXIOUS, STATE_NEUTRAL };
enum ENUM_ALERT_STATUS { ALERT_NONE, ALERT_PARTIAL, ALERT_STRONG };

// --- Structs for Data Handling
struct LiveTradeData { bool trade_exists;
double entry, sl, tp; };
struct CompassData { ENUM_BIAS bias;
double confidence; };
// MODIFIED: MatrixRowData score is now an integer.
struct MatrixRowData { ENUM_BIAS bias; ENUM_ZONE zone; ENUM_MAGNET_RELATION magnet; int score; };
struct TradeRecommendation { ENUM_TRADE_SIGNAL action;
string reasoning; };
struct RiskModuleData { double risk_percent; double position_size; string rr_ratio; };
struct SessionData { string session_name; string session_overlap;
ENUM_VOLATILITY volatility; };
struct NewsEventData { string time; string currency; string event_name;
ENUM_NEWS_IMPACT impact; };
struct EmotionalStateData { ENUM_EMOTIONAL_STATE state;
string text; };
struct AlertData { ENUM_ALERT_STATUS status; string text; };
// --- Structs for Live Data Caching ---
struct CachedCompassData { ENUM_BIAS bias; double confidence; };
// MODIFIED: CachedSupDemData now holds all 6 buffers from SupDemCore v1.5
struct CachedSupDemData
{
   ENUM_ZONE zone;
   double magnet_level;
   double zone_p1;
   double zone_p2;
   // --- NEW from v1.5 ---
   double strength;
   double freshness;
   double volume;
   double liquidity;
};
struct CachedHUDData { bool zone_active; };
// --- Constants for Panel Layout
#define PANE_PREFIX "AlfredPane_"
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
// MODIFIED: Old matrix colors are no longer needed
// #define COLOR_MATRIX_STRONG (color)ColorToARGB(clrDarkGreen, 120)
// #define COLOR_MATRIX_MEDIUM (color)ColorToARGB(clrGoldenrod, 100)
// #define COLOR_MATRIX_WEAK (color)ColorToARGB(clrMaroon, 120)
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

// --- Font Sizes & Spacing
#define FONT_SIZE_NORMAL 8
#define FONT_SIZE_HEADER 9
#define FONT_SIZE_SIGNAL 10
#define FONT_SIZE_SIGNAL_ACTIVE 11
#define SPACING_MEDIUM 16
#define SPACING_LARGE 24
#define SPACING_SEPARATOR 12

// --- Indicator Handles & Globals
int hATR_current;
int atr_period = 14;
bool g_biases_expanded = true;
bool g_hud_expanded = true;
double g_pip_value;
string g_timeframe_strings[] = {"M1", "M5", "M15", "M30", "H1", "H4", "D1"};
ENUM_TIMEFRAMES g_timeframes[] = {PERIOD_M1, PERIOD_M5, PERIOD_M15, PERIOD_M30, PERIOD_H1, PERIOD_H4, PERIOD_D1};
// UPDATED: Expanded heatmap TFs
string g_heatmap_tf_strings[] = {"M15", "M30", "H1", "H2", "H4", "D1"};
ENUM_TIMEFRAMES g_heatmap_tfs[] = {PERIOD_M15, PERIOD_M30, PERIOD_H1, PERIOD_H2, PERIOD_H4, PERIOD_D1};
string g_magnet_summary_tf_strings[] = {"M15", "M30", "H1", "H2", "H4", "D1"};
ENUM_TIMEFRAMES g_magnet_summary_tfs[] = {PERIOD_M15, PERIOD_M30, PERIOD_H1, PERIOD_H2, PERIOD_H4, PERIOD_D1};
// --- UPGRADED: Confidence Matrix now uses more TFs as requested ---
string g_matrix_tf_strings[] = {"M15", "M30", "H1", "H2", "H4", "D1"};
ENUM_TIMEFRAMES g_matrix_tfs[] = {PERIOD_M15, PERIOD_M30, PERIOD_H1, PERIOD_H2, PERIOD_H4, PERIOD_D1};
string g_hud_tf_strings[] = {"M15", "H1", "H4", "D1"};
ENUM_TIMEFRAMES g_hud_tfs[] = {PERIOD_M15, PERIOD_H1, PERIOD_H4, PERIOD_D1};
// --- Live Data Caches ---
CachedCompassData g_compass_cache[7];
CachedSupDemData  g_supdem_cache[7];
CachedHUDData     g_hud_cache[7];


//+------------------------------------------------------------------+
//|                        LIVE DATA & CACHING FUNCTIONS             |
//+------------------------------------------------------------------+
// This function is called once per timer tick to update all external indicator data
void UpdateLiveDataCaches()
{
   if(EnableDebugLogging)
      Print("--- AlfredPane: Updating Live Data Caches ---");
// Get handles ONCE per update cycle for efficiency
   int hud_handle = iCustom(_Symbol, _Period, "AlfredHUD.ex5");
   for(int i = 0; i < ArraySize(g_timeframes); i++)
   {
      ENUM_TIMEFRAMES tf = g_timeframes[i];
      string tf_str = g_timeframe_strings[i];

      // --- Cache AlfredCompass Data (Bias & Confidence) via iCustom ---
      int compass_handle = iCustom(_Symbol, tf, "AlfredCompass.ex5");
      if(compass_handle != INVALID_HANDLE)
      {
         double bias_buffer[1], conf_buffer[1];
         if(CopyBuffer(compass_handle, 0, 0, 1, bias_buffer) > 0 && CopyBuffer(compass_handle, 1, 0, 1, conf_buffer) > 0)
         {
            if(bias_buffer[0] > 0.5)
               g_compass_cache[i].bias = BIAS_BULL;
            else if(bias_buffer[0] < -0.5)
               g_compass_cache[i].bias = BIAS_BEAR;
            else
               g_compass_cache[i].bias = BIAS_NEUTRAL;
            g_compass_cache[i].confidence = conf_buffer[0];
            // Confidence is already 0-100 from Compass
            if(EnableDebugLogging)
               PrintFormat("PaneCache: Compass %s -> Bias: %s, Conf: %.1f", tf_str, EnumToString(g_compass_cache[i].bias), g_compass_cache[i].confidence);
         }
         else
         {
            g_compass_cache[i].bias = BIAS_NEUTRAL;
            g_compass_cache[i].confidence = 0;
            if(EnableDebugLogging)
               PrintFormat("PaneCache: Compass %s -> FAILED to copy buffers", tf_str);
         }
      }
      else
      {
         g_compass_cache[i].bias = BIAS_NEUTRAL;
         g_compass_cache[i].confidence = 0;
         if(EnableDebugLogging)
            PrintFormat("PaneCache: Compass %s -> INVALID_HANDLE", tf_str);
      }

      // --- MODIFIED: Cache AlfredSupDemCore Data (all 6 buffers) via iCustom ---
      int supdem_handle = iCustom(_Symbol, tf, "AlfredSupDemCore.ex5");
      if(supdem_handle != INVALID_HANDLE)
      {
         // Buffers for all 6 data points from SupDemCore v1.5
         double zone_buffer[1], magnet_buffer[1], strength_buffer[1], fresh_buffer[1], volume_buffer[1], liq_buffer[1];
         // Reset cache for this TF
         g_supdem_cache[i].zone = ZONE_NONE;
         g_supdem_cache[i].magnet_level = 0.0;
         g_supdem_cache[i].strength = 0.0;
         g_supdem_cache[i].freshness = 0.0;
         g_supdem_cache[i].volume = 0.0;
         g_supdem_cache[i].liquidity = 0.0;
         // Buffer 0: ZoneStatus
         if(CopyBuffer(supdem_handle, 0, 0, 1, zone_buffer) > 0)
         {
            if(zone_buffer[0] > 0.5)
               g_supdem_cache[i].zone = ZONE_DEMAND;
            else if(zone_buffer[0] < -0.5)
               g_supdem_cache[i].zone = ZONE_SUPPLY;
         }
         // Buffer 1: MagnetLevel
         if(CopyBuffer(supdem_handle, 1, 0, 1, magnet_buffer) > 0)
         {
            g_supdem_cache[i].magnet_level = magnet_buffer[0];
         }
         // Buffer 2: ZoneStrength
         if(CopyBuffer(supdem_handle, 2, 0, 1, strength_buffer) > 0)
         {
            g_supdem_cache[i].strength = strength_buffer[0];
         }
         // Buffer 3: ZoneFreshness
         if(CopyBuffer(supdem_handle, 3, 0, 1, fresh_buffer) > 0)
         {
            g_supdem_cache[i].freshness = fresh_buffer[0];
         }
         // Buffer 4: ZoneVolume
         if(CopyBuffer(supdem_handle, 4, 0, 1, volume_buffer) > 0)
         {
            g_supdem_cache[i].volume = volume_buffer[0];
         }
         // Buffer 5: ZoneLiquidity
         if(CopyBuffer(supdem_handle, 5, 0, 1, liq_buffer) > 0)
         {
            g_supdem_cache[i].liquidity = liq_buffer[0];
         }

         if(EnableDebugLogging)
            PrintFormat("PaneCache: SupDem %s -> Zone: %s, Str:%.0f, Fr:%.0f, Vol:%.0f, Liq:%.0f",
                        tf_str, EnumToString(g_supdem_cache[i].zone),
                        g_supdem_cache[i].strength, g_supdem_cache[i].freshness,
                        g_supdem_cache[i].volume, g_supdem_cache[i].liquidity);
      }
      else
      {
         if(EnableDebugLogging)
            PrintFormat("PaneCache: SupDem %s -> INVALID_HANDLE", tf_str);
      }


      // --- Cache AlfredHUD Data (Zone Activity) ---
      if(hud_handle != INVALID_HANDLE)
      {
         // The buffer indices in AlfredHUD.ex5 are fixed:
         // 1: H4, 2: H2, 3: H1, 4: M30, 5: M15.
         // Buffer 0 is a dummy.
         int buffer_index = -1;
         if(tf == PERIOD_M15)
            buffer_index = 5;
         else if(tf == PERIOD_H1)
            buffer_index = 3;
         else if(tf == PERIOD_H4)
            buffer_index = 1;
         // Note: D1, H2, M30 etc. are not mapped here intentionally.
         if(buffer_index != -1)
         {
            double activity_buffer[1];
            if(CopyBuffer(hud_handle, buffer_index, 0, 1, activity_buffer) > 0)
            {
               g_hud_cache[i].zone_active = (activity_buffer[0] > 0.5);
               if(EnableDebugLogging)
                  PrintFormat("PaneCache: HUD %s -> Zone Active: %s (from buffer %d)", tf_str, g_hud_cache[i].zone_active ? "Yes" : "No", buffer_index);
            }
            else
            {
               g_hud_cache[i].zone_active = false;
               if(EnableDebugLogging)
                  PrintFormat("PaneCache: HUD %s -> FAILED to copy buffer %d", tf_str, buffer_index);
            }
         }
         else
         {
            g_hud_cache[i].zone_active = false;
            // Not a TF we track for HUD activity
         }
      }
      else
      {
         g_hud_cache[i].zone_active = false;
         if(i == 0 && EnableDebugLogging)
            PrintFormat("PaneCache: HUD -> INVALID_HANDLE");
         // Print only once
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
// --- LIVE DATA: Reads from cached values ---
CompassData GetCompassData(ENUM_TIMEFRAMES tf)
{
   CompassData data;
   int index = GetCacheIndex(tf);
   if(index != -1)
   {
      data.bias = g_compass_cache[index].bias;
      data.confidence = g_compass_cache[index].confidence;
   }
   else // Fallback if TF not in our main list
   {
      data.bias = BIAS_NEUTRAL;
      data.confidence = 0.0;
   }
   return data;
}

// NEW: Get full cached SupDem data
CachedSupDemData GetSupDemData(ENUM_TIMEFRAMES tf)
{
   CachedSupDemData data;
   int index = GetCacheIndex(tf);
   if(index != -1)
   {
      return g_supdem_cache[index];
   }
   // Return empty/default data if not found
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
   // Uses the live data function for the chart's current timeframe
   return GetMagnetLevelTF(_Period);
}

// --- LOGIC FUNCTIONS (Now use live data) ---
ENUM_TRADE_SIGNAL GetTradeSignal()
{
   // The final trade signal is now derived from the recommendation logic
   TradeRecommendation rec = GetTradeRecommendation();
   return rec.action;
}

ENUM_ZONE_INTERACTION GetCurrentZoneInteraction()
{
   ENUM_ZONE current_zone = GetZoneStatus(_Period);
   switch(current_zone)
   {
      case ZONE_DEMAND:
         return INTERACTION_INSIDE_DEMAND;
      case ZONE_SUPPLY:
         return INTERACTION_INSIDE_SUPPLY;
      default:
         return INTERACTION_NONE;
   }
}

ENUM_HEATMAP_STATUS GetZoneHeatmapStatus(ENUM_TIMEFRAMES tf)
{
   // This now uses the live zone status
   switch(GetZoneStatus(tf))
   {
      case ZONE_DEMAND:
         return HEATMAP_DEMAND;
      case ZONE_SUPPLY:
         return HEATMAP_SUPPLY;
      default:
         return HEATMAP_NONE;
   }
}

ENUM_MAGNET_RELATION GetMagnetProjectionRelation(double price, double magnet)
{
   if(price == 0 || magnet == 0)
      return RELATION_AT;
   // Avoid false signals on error
   double proximity = 5 * _Point;
   if(price > magnet + proximity)
      return RELATION_ABOVE;
   if(price < magnet - proximity)
      return RELATION_BELOW;
   return RELATION_AT;
}

ENUM_MAGNET_RELATION GetMagnetRelationTF(double price, double magnet)
{
   if(price == 0 || magnet == 0)
      return RELATION_AT;
   // Avoid false signals on error
   if(price > magnet)
      return RELATION_ABOVE;
   if(price < magnet)
      return RELATION_BELOW;
   return RELATION_AT;
}

// --- UPGRADED: Confidence Matrix logic now uses new scoring formula ---
MatrixRowData GetConfidenceMatrixRow(ENUM_TIMEFRAMES tf)
{
   MatrixRowData data;
   // Get static data from cache
   data.bias = GetCompassData(tf).bias;
   data.zone = GetZoneStatus(tf);
   double magnet_level = GetMagnetLevelTF(tf);
   data.magnet = GetMagnetRelationTF(SymbolInfoDouble(_Symbol, SYMBOL_BID), magnet_level);

   // --- Fetch live data from AlfredSupDemCore.ex5 for score calculation as requested ---
   double strength_raw = iCustom(_Symbol, tf, "AlfredSupDemCore.ex5", 2, 0); // Buffer 2
   double freshness_raw = iCustom(_Symbol, tf, "AlfredSupDemCore.ex5", 3, 0); // Buffer 3
   double volume_raw = iCustom(_Symbol, tf, "AlfredSupDemCore.ex5", 4, 0);    // Buffer 4
   double liquidity_raw = iCustom(_Symbol, tf, "AlfredSupDemCore.ex5", 5, 0); // Buffer 5

   int zoneStrength = (int)strength_raw;
   bool zoneFreshness = freshness_raw > 0.5; // Convert buffer value to boolean
   bool zoneVolume = volume_raw > 0.5;
   bool zoneLiquidity = liquidity_raw > 0.5;

   // Calculate new confidence score based on the requested formula
   data.score = zoneStrength * 2 + (zoneFreshness ? 3 : 0) + (zoneVolume ? 2 : 0) + (zoneLiquidity ? 3 : 0);
   
   return data;
}

// MODIFIED: Trade recommendation now uses the new numerical confidence score.
TradeRecommendation GetTradeRecommendation()
{
   TradeRecommendation rec;
   rec.action = SIGNAL_NONE;
   rec.reasoning = "Mixed Signals";
   
   #define STRONG_CONFIDENCE_THRESHOLD 10 // Define what constitutes a "strong" score

   int strong_bullish_tfs = 0;
   int strong_bearish_tfs = 0;
   // First pass: Count strong TFs based on the new score
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

   // Second pass: Generate signal and detailed reason
   if(strong_bullish_tfs >= 2)
   {
      rec.action = SIGNAL_BUY;
      rec.reasoning = "Strong Multi-TF Bullish Alignment"; // Default reason

      // Find best confirming zone
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
               // Prioritize liquidity
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
      rec.reasoning = "Strong Multi-TF Bearish Alignment"; // Default reason

      // Find best confirming zone
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


// --- MOCK/STATIC FUNCTIONS (Unchanged, as they are outside the scope of Compass/SupDem) ---
RiskModuleData GetRiskModuleData()
{
   RiskModuleData data;
   data.risk_percent = 1.0;
   data.position_size = 0.10;
   int rand_val = MathRand() % 3;
   switch(rand_val)
   {
      case 0:
         data.rr_ratio = "1 : 1.5";
         break;
      case 1:
         data.rr_ratio = "1 : 2.0";
         break;
      default:
         data.rr_ratio = "1 : 3.0";
         break;
   }
   return data;
}

SessionData GetSessionData()
{
   SessionData data;
   MqlDateTime dt;
   TimeCurrent(dt);
   int hour = dt.hour;
   if(hour >= 13 && hour < 16)
      data.session_name = "London / NY";
   else if(hour >= 8 && hour < 13)
      data.session_name = "London";
   else if(hour >= 16 && hour < 21)
      data.session_name = "New York";
   else if(hour >= 21 || hour < 6)
      data.session_name = "Sydney";
   else if(hour >= 6 && hour < 8)
      data.session_name = "Tokyo";
   else
      data.session_name = "Inter-Session";
   if(hour >= 13 && hour < 16)
      data.session_overlap = "NY + London";
   else
      data.session_overlap = "None";
   int rand_val = MathRand() % 3;
   switch(rand_val)
   {
      case 0:
         data.volatility = VOLATILITY_LOW;
         break;
      case 1:
         data.volatility = VOLATILITY_MEDIUM;
         break;
      default:
         data.volatility = VOLATILITY_HIGH;
         break;
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
      case 0:
         data.state = STATE_CONFIDENT;
         data.text = "Confident – Trend Aligned";
         break;
      case 1:
         data.state = STATE_CAUTIOUS;
         data.text = "Cautious – Awaiting Confirmation";
         break;
      case 2:
         data.state = STATE_OVEREXTENDED;
         data.text = "Overextended – Risk of Reversal";
         break;
      case 3:
         data.state = STATE_ANXIOUS;
         data.text = "Anxious – Overtrading Zone";
         break;
      default:
         data.state = STATE_NEUTRAL;
         data.text = "Neutral – Balanced Mindset";
         break;
   }
   return data;
}

// MODIFIED: Alert center now detects liquidity grabs and uses the new confidence score.
AlertData GetAlertCenterStatus()
{
   AlertData alert;
   // --- NEW: Check for liquidity grabs first, as they are high-priority ---
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

   // --- Original Logic, now using new score thresholds ---
   #define STRONG_CONFIDENCE_THRESHOLD 10
   #define MEDIUM_CONFIDENCE_THRESHOLD 5
   
   int strong_count = 0;
   int medium_count = 0;

   for(int i = 0; i < ArraySize(g_matrix_tfs); i++)
   {
      MatrixRowData row = GetConfidenceMatrixRow(g_matrix_tfs[i]);
      if(row.score >= STRONG_CONFIDENCE_THRESHOLD)
         strong_count++;
      else if(row.score >= MEDIUM_CONFIDENCE_THRESHOLD)
         medium_count++;
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
//|
// HELPER & CONVERSION FUNCTIONS                  |
//+------------------------------------------------------------------+
double CalculatePips(double p1, double p2)
{
   if(g_pip_value == 0 || p1 == 0 || p2 == 0)
      return 0;
   return MathAbs(p1 - p2) / g_pip_value;
}
string BiasToString(ENUM_BIAS b)
{
   switch(b)
   {
      case BIAS_BULL:
         return "BULL";
      case BIAS_BEAR:
         return "BEAR";
   }
   return "NEUTRAL";
}
color  BiasToColor(ENUM_BIAS b)
{
   switch(b)
   {
      case BIAS_BULL:
         return COLOR_BULL;
      case BIAS_BEAR:
         return COLOR_BEAR;
   }
   return COLOR_NEUTRAL_BIAS;
}
string ZoneToString(ENUM_ZONE z)
{
   switch(z)
   {
      case ZONE_DEMAND:
         return "Demand";
      case ZONE_SUPPLY:
         return "Supply";
   }
   return "None";
}
color  ZoneToColor(ENUM_ZONE z)
{
   switch(z)
   {
      case ZONE_DEMAND:
         return COLOR_DEMAND;
      case ZONE_SUPPLY:
         return COLOR_SUPPLY;
   }
   return COLOR_NA;
}
string SignalToString(ENUM_TRADE_SIGNAL s)
{
   switch(s)
   {
      case SIGNAL_BUY:
         return "BUY";
      case SIGNAL_SELL:
         return "SELL";
   }
   return "NO SIGNAL";
}
color  SignalToColor(ENUM_TRADE_SIGNAL s)
{
   switch(s)
   {
      case SIGNAL_BUY:
         return COLOR_BULL;
      case SIGNAL_SELL:
         return COLOR_BEAR;
   }
   return COLOR_NO_SIGNAL;
}
string ZoneInteractionToString(ENUM_ZONE_INTERACTION z)
{
   switch(z)
   {
      case INTERACTION_INSIDE_DEMAND:
         return "INSIDE DEMAND";
      case INTERACTION_INSIDE_SUPPLY:
         return "INSIDE SUPPLY";
   }
   return "NO ZONE INTERACTION";
}
color  ZoneInteractionToColor(ENUM_ZONE_INTERACTION z)
{
   switch(z)
   {
      case INTERACTION_INSIDE_DEMAND:
         return COLOR_DEMAND;
      case INTERACTION_INSIDE_SUPPLY:
         return COLOR_SUPPLY;
   }
   return COLOR_NA;
}
color  ZoneInteractionToHighlightColor(ENUM_ZONE_INTERACTION z)
{
   switch(z)
   {
      case INTERACTION_INSIDE_DEMAND:
         return COLOR_HIGHLIGHT_DEMAND;
      case INTERACTION_INSIDE_SUPPLY:
         return COLOR_HIGHLIGHT_SUPPLY;
   }
   return COLOR_HIGHLIGHT_NONE;
}
string HeatmapStatusToString(ENUM_HEATMAP_STATUS s)
{
   switch(s)
   {
      case HEATMAP_DEMAND:
         return "D";
      case HEATMAP_SUPPLY:
         return "S";
   }
   return "-";
}
color  HeatmapStatusToColor(ENUM_HEATMAP_STATUS s)
{
   switch(s)
   {
      case HEATMAP_DEMAND:
         return COLOR_DEMAND;
      case HEATMAP_SUPPLY:
         return COLOR_SUPPLY;
   }
   return COLOR_NA;
}
string MagnetRelationToString(ENUM_MAGNET_RELATION r)
{
   switch(r)
   {
      case RELATION_ABOVE:
         return "(Above)";
      case RELATION_BELOW:
         return "(Below)";
   }
   return "(At)";
}
color  MagnetRelationToColor(ENUM_MAGNET_RELATION r)
{
   switch(r)
   {
      case RELATION_ABOVE:
         return COLOR_BULL;
      case RELATION_BELOW:
         return COLOR_BEAR;
   }
   return COLOR_MAGNET_AT;
}
string MagnetRelationTFToString(ENUM_MAGNET_RELATION r)
{
   switch(r)
   {
      case RELATION_ABOVE:
         return "Above";
      case RELATION_BELOW:
         return "Below";
   }
   return "At";
}
color  MagnetRelationTFToColor(ENUM_MAGNET_RELATION r)
{
   switch(r)
   {
      case RELATION_ABOVE:
         return COLOR_BULL;
      case RELATION_BELOW:
         return COLOR_BEAR;
   }
   return COLOR_MAGNET_AT;
}

// --- UPGRADED: Helper function to return a color based on the new score rules ---
color GetConfidenceColor(int score)
{
   if(score >= 16) return (color)ColorToARGB(clrDodgerBlue, 120); // Blue for 16-20
   if(score >= 10) return (color)ColorToARGB(clrLimeGreen, 120);  // Green for 10-15
   if(score >= 5)  return (color)ColorToARGB(clrGoldenrod, 100);  // Yellow for 5-9
   return (color)ColorToARGB(clrOrangeRed, 120);                 // Red for 0-4
}

string RecoActionToString(ENUM_TRADE_SIGNAL s)
{
   switch(s)
   {
      case SIGNAL_BUY:
         return "BUY";
      case SIGNAL_SELL:
         return "SELL";
   }
   return "WAIT";
}
color RecoActionToColor(ENUM_TRADE_SIGNAL s)
{
   switch(s)
   {
      case SIGNAL_BUY:
         return COLOR_BULL;
      case SIGNAL_SELL:
         return COLOR_BEAR;
   }
   return COLOR_NO_SIGNAL;
}
string VolatilityToString(ENUM_VOLATILITY v)
{
   switch(v)
   {
      case VOLATILITY_LOW:
         return "Low";
      case VOLATILITY_MEDIUM:
         return "Medium";
   }
   return "High";
}
color VolatilityToColor(ENUM_VOLATILITY v)
{
   switch(v)
   {
      case VOLATILITY_LOW:
         return COLOR_BULL;
      case VOLATILITY_MEDIUM:
         return COLOR_MAGNET_AT;
   }
   return COLOR_BEAR;
}
color VolatilityToHighlightColor(ENUM_VOLATILITY v)
{
   switch(v)
   {
      case VOLATILITY_LOW:
         return COLOR_VOL_LOW_BG;
      case VOLATILITY_MEDIUM:
         return COLOR_VOL_MED_BG;
   }
   return COLOR_VOL_HIGH_BG;
}
string NewsImpactToString(ENUM_NEWS_IMPACT i)
{
   switch(i)
   {
      case IMPACT_LOW:
         return "LOW";
      case IMPACT_MEDIUM:
         return "MEDIUM";
   }
   return "HIGH";
}
color NewsImpactToColor(ENUM_NEWS_IMPACT i)
{
   switch(i)
   {
      case IMPACT_LOW:
         return COLOR_IMPACT_LOW;
      case IMPACT_MEDIUM:
         return COLOR_IMPACT_MEDIUM;
   }
   return COLOR_IMPACT_HIGH;
}
color EmotionalStateToColor(ENUM_EMOTIONAL_STATE s)
{
   switch(s)
   {
      case STATE_CAUTIOUS:
         return COLOR_STATE_CAUTIOUS;
      case STATE_CONFIDENT:
         return COLOR_STATE_CONFIDENT;
      case STATE_OVEREXTENDED:
         return COLOR_STATE_OVEREXTENDED;
      case STATE_ANXIOUS:
         return COLOR_STATE_ANXIOUS;
   }
   return COLOR_STATE_NEUTRAL;
}
color AlertStatusToColor(ENUM_ALERT_STATUS s)
{
   switch(s)
   {
      case ALERT_STRONG:
         return COLOR_ALERT_STRONG;
      case ALERT_PARTIAL:
         return COLOR_ALERT_PARTIAL;
   }
   return COLOR_ALERT_NONE;
}

// --- HELPERS FOR TF BIASES & ZONES ---
string GetBiasLabelFromZone(int zone_val)
{
   if (zone_val == 1) return "Bull";
   if (zone_val == -1) return "Bear";
   return "Neutral";
}

color GetBiasColorFromZone(int zone_val)
{
   if (zone_val == 1) return COLOR_BULL;
   if (zone_val == -1) return COLOR_BEAR;
   return COLOR_NEUTRAL_BIAS;
}

string GetMagnetRelationLabel(double current_price, double magnet_level)
{
    if (magnet_level == 0.0) return "N/A";
    // No magnet found
    double proximity = 5 * _Point;
    // Proximity threshold in points
    if (current_price > magnet_level + proximity) return "Above";
    if (current_price < magnet_level - proximity) return "Below";
    return "At";
}

color GetMagnetRelationColor(string relation)
{
    if (relation == "Above") return COLOR_BULL;
    if (relation == "Below") return COLOR_BEAR;
    if (relation == "At") return COLOR_MAGNET_AT;
    return COLOR_NA; // For "N/A"
}

// --- NEW HELPER FOR ZONE HEATMAP ---
color GetHeatColorForStrength(int strength)
{
   if(strength >= 8) return clrRed;
   if(strength >= 5) return clrOrange;
   if(strength >= 1) return clrGold;
   return clrSilver;
}


//+------------------------------------------------------------------+
//|
// UI DRAWING HELPERS                       |
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
   if(ObjectFind(0, o) < 0)
      return;
   ObjectSetString(0, o, OBJPROP_TEXT, t);
   if(c != clrNONE)
      ObjectSetInteger(0, o, OBJPROP_COLOR, c);
}
void DrawSeparator(string name, int &y_offset, int x_offset)
{
   CreateLabel(name, SEPARATOR_TEXT, x_offset, y_offset, COLOR_SEPARATOR);
   y_offset += SPACING_SEPARATOR;
}

//+------------------------------------------------------------------+
//|
// MAIN PANEL CREATION & UPDATE LOGIC                |
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
      int settings_x1 = x_col1;
      int settings_x2 = x_col1 + 110;

      CreateLabel("setting_matrix_prefix", "📊 Bias Matrix:", settings_x1, y_offset, COLOR_HEADER);
      CreateLabel("setting_matrix_value", "---", settings_x2, y_offset, COLOR_NA);
      y_offset += SPACING_MEDIUM;

      CreateLabel("setting_magnet_prefix", "📉 Magnet Summary:", settings_x1, y_offset, COLOR_HEADER);
      CreateLabel("setting_magnet_value", "---", settings_x2, y_offset, COLOR_NA);
      y_offset += SPACING_MEDIUM;

      CreateLabel("setting_heatmap_prefix", "📦 Zone Heatmap:", settings_x1, y_offset, COLOR_HEADER);
      CreateLabel("setting_heatmap_value", "---", settings_x2, y_offset, COLOR_NA);
      y_offset += SPACING_MEDIUM;
      CreateLabel("setting_hud_activity_prefix", "🛰️ HUD Activity:", settings_x1, y_offset, COLOR_HEADER);
      CreateLabel("setting_hud_activity_value", "---", settings_x2, y_offset, COLOR_NA);
      y_offset += SPACING_MEDIUM;
      CreateLabel("setting_reco_prefix", "🎯 Trade Signals:", settings_x1, y_offset, COLOR_HEADER);
      CreateLabel("setting_reco_value", "---", settings_x2, y_offset, COLOR_NA);
      y_offset += SPACING_MEDIUM;
      CreateLabel("setting_emotion_prefix", "🧠 Emotion Module:", settings_x1, y_offset, COLOR_HEADER);
      CreateLabel("setting_emotion_value", "---", settings_x2, y_offset, COLOR_NA);
      y_offset += SPACING_MEDIUM;
      CreateLabel("setting_alert_prefix", "🔔 Alert Center:", settings_x1, y_offset, COLOR_HEADER);
      CreateLabel("setting_alert_value", "---", settings_x2, y_offset, COLOR_NA);
      y_offset += SPACING_MEDIUM;

      DrawSeparator("sep_settings", y_offset, x_offset);
   }

   // --- TF Biases Section ---
   CreateLabel("biases_header", "TF Biases & Zones", x_col1, y_offset, COLOR_HEADER, FONT_SIZE_HEADER);
   CreateLabel("biases_toggle", g_biases_expanded ? "[-]" : "[+]", x_toggle, y_offset, COLOR_TOGGLE, FONT_SIZE_HEADER);
   y_offset += SPACING_MEDIUM;
   if(g_biases_expanded)
   {
      // Timeframes for this specific module
      string tf_bias_strings[] = {"M15", "M30", "H1", "H2", "H4", "D1"};
      // Column positions
      int x_col_tf = x_col1;
      int x_col_bias = x_col1 + 40;
      int x_col_zone = x_col1 + 95;
      int x_col_magnet = x_col1 + 160;
      for(int i = 0; i < ArraySize(tf_bias_strings); i++)
      {
         string tf = tf_bias_strings[i];
         CreateLabel("biases_" + tf + "_prefix", tf + ":", x_col_tf, y_offset, COLOR_HEADER);
         // Bias Label
         CreateLabel("biases_" + tf + "_value", "---", x_col_bias, y_offset, COLOR_NA);
         // Zone Label
         CreateLabel("zone_" + tf + "_value", "---", x_col_zone, y_offset, COLOR_NA);
         // Magnet Label
         CreateLabel("magnet_" + tf + "_value", "---", x_col_magnet, y_offset, COLOR_NA);
         y_offset += SPACING_MEDIUM;
      }
   }
   y_offset += SPACING_SEPARATOR - (g_biases_expanded ? SPACING_MEDIUM : 0);
   DrawSeparator("sep1", y_offset, x_offset);


   // --- MODIFIED: Zone Interaction Status Section with Quality Details ---
   CreateLabel("zone_interaction_header", "ZONE STATUS", x_col1, y_offset, COLOR_HEADER, FONT_SIZE_HEADER);
   y_offset += SPACING_MEDIUM;
   CreateRectangle("zone_interaction_highlight", x_col1 - 5, y_offset - 2, PANE_WIDTH - 20, 14, COLOR_HIGHLIGHT_NONE);
   CreateLabel("zone_interaction_status", "NO ZONE INTERACTION", x_col1, y_offset, COLOR_NA, FONT_SIZE_NORMAL);
   y_offset += SPACING_MEDIUM;
   // --- NEW: Zone Quality Details ---
   int x_qual_1 = x_col1 + 5;
   int x_qual_2 = x_col1 + 110;
   CreateLabel("zone_qual_str_prefix", "Strength:", x_qual_1, y_offset, COLOR_HEADER);
   CreateLabel("zone_qual_str_value", "N/A", x_qual_2, y_offset, COLOR_NA);
   y_offset += SPACING_MEDIUM;
   CreateLabel("zone_qual_fresh_prefix", "Fresh:", x_qual_1, y_offset, COLOR_HEADER);
   CreateLabel("zone_qual_fresh_value", "N/A", x_qual_2, y_offset, COLOR_NA);
   y_offset += SPACING_MEDIUM;
   CreateLabel("zone_qual_vol_prefix", "Volume:", x_qual_1, y_offset, COLOR_HEADER);
   CreateLabel("zone_qual_vol_value", "N/A", x_qual_2, y_offset, COLOR_NA);
   y_offset += SPACING_MEDIUM;
   CreateLabel("zone_qual_liq_prefix", "Liquidity Grab:", x_qual_1, y_offset, COLOR_HEADER);
   CreateLabel("zone_qual_liq_value", "N/A", x_qual_2, y_offset, COLOR_NA);
   y_offset += SPACING_MEDIUM;
   DrawSeparator("sep_zone", y_offset, x_offset);

   // --- Zone Heatmap Section (FIXED Layout) ---
   if(ShowZoneHeatmap)
   {
      CreateLabel("heatmap_header", "ZONE HEATMAP", x_col1, y_offset, COLOR_HEADER, FONT_SIZE_HEADER);
      y_offset += SPACING_MEDIUM;
      int heatmap_x = x_col1 + 10; // Adjusted starting position
      for(int i = 0; i < ArraySize(g_heatmap_tf_strings); i++)
      {
         string tf = g_heatmap_tf_strings[i];
         CreateLabel("heatmap_tf_" + tf, tf, heatmap_x, y_offset, COLOR_HEADER, FONT_SIZE_NORMAL, ANCHOR_CENTER);
         CreateLabel("heatmap_status_" + tf, "-", heatmap_x, y_offset + 12, COLOR_NA, FONT_SIZE_NORMAL, ANCHOR_CENTER);
         heatmap_x += 35; // Adjusted spacing for 6 TFs
      }
      y_offset += SPACING_LARGE;
      DrawSeparator("sep_heatmap", y_offset, x_offset);
   }

   // --- Magnet Projection Section
   if(ShowMagnetProjection)
   {
      CreateLabel("magnet_header", "MAGNET PROJECTION", x_col1, y_offset, COLOR_HEADER, FONT_SIZE_HEADER);
      y_offset += SPACING_MEDIUM;
      CreateLabel("magnet_level", "Magnet → ---", x_col1, y_offset, COLOR_NEUTRAL_TEXT, FONT_SIZE_NORMAL + 1);
      CreateLabel("magnet_relation", "(---)", x_col1 + 150, y_offset, COLOR_NA, FONT_SIZE_NORMAL);
      y_offset += SPACING_MEDIUM;
      DrawSeparator("sep_magnet", y_offset, x_offset);
   }

   // --- Multi-TF Magnet Summary Section
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
         CreateLabel("mtf_magnet_level_" + tf, "(---)", mtf_magnet_x3, y_offset, COLOR_NA);
         y_offset += SPACING_MEDIUM;
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

   // --- MODIFIED: Confidence Matrix Section
   if(ShowConfidenceMatrix)
   {
      CreateLabel("matrix_header", "CONFIDENCE MATRIX", x_col1, y_offset, COLOR_HEADER, FONT_SIZE_HEADER);
      y_offset += SPACING_MEDIUM;
      CreateLabel("matrix_hdr_tf", "TF", x_col1, y_offset, COLOR_HEADER);
      CreateLabel("matrix_hdr_bias", "Bias", x_col1 + 40, y_offset, COLOR_HEADER);
      CreateLabel("matrix_hdr_zone", "Zone", x_col1 + 100, y_offset, COLOR_HEADER);
      CreateLabel("matrix_hdr_score", "Score", x_col1 + 160, y_offset, COLOR_HEADER);
      // Changed "Magnet" to "Score"
      y_offset += SPACING_MEDIUM;
      // Loop now iterates over the newly expanded list of TFs
      for(int i = 0; i < ArraySize(g_matrix_tfs); i++)
      {
         string tf = g_matrix_tf_strings[i];
         CreateRectangle("matrix_bg_" + tf, x_col1 - 5, y_offset - 2, PANE_WIDTH - 20, 14, clrNONE);
         CreateLabel("matrix_tf_" + tf, tf, x_col1, y_offset, COLOR_NEUTRAL_TEXT);
         CreateLabel("matrix_bias_" + tf, "---", x_col1 + 40, y_offset, COLOR_NA);
         CreateLabel("matrix_zone_" + tf, "---", x_col1 + 100, y_offset, COLOR_NA);
         CreateLabel("matrix_magnet_" + tf, "---", x_col1 + 160, y_offset, COLOR_NA);
         // This will display the score
         y_offset += SPACING_MEDIUM;
      }
      DrawSeparator("sep_matrix", y_offset, x_offset);
   }

   // --- Trade Recommendation Section
   if(ShowTradeRecommendation)
   {
      CreateLabel("reco_header", "TRADE RECOMMENDATION", x_col1, y_offset, COLOR_HEADER, FONT_SIZE_HEADER);
      y_offset += SPACING_MEDIUM;
      CreateLabel("reco_action_prefix", "Action:", x_col1, y_offset, COLOR_HEADER);
      CreateLabel("reco_action_value", "WAIT", x_col1 + 70, y_offset, COLOR_NO_SIGNAL);
      y_offset += SPACING_MEDIUM;
      CreateLabel("reco_reason_prefix", "Reason:", x_col1, y_offset, COLOR_HEADER);
      CreateLabel("reco_reason_value", "---", x_col1 + 70, y_offset, COLOR_NEUTRAL_TEXT);
      y_offset += SPACING_MEDIUM;
      DrawSeparator("sep_reco", y_offset, x_offset);
   }

   // --- Risk & Positioning Section
   if(ShowRiskModule)
   {
      CreateLabel("risk_header", "RISK & POSITIONING", x_col1, y_offset, COLOR_HEADER, FONT_SIZE_HEADER);
      y_offset += SPACING_MEDIUM;
      CreateLabel("risk_pct_prefix", "Risk %:", x_col1, y_offset, COLOR_HEADER, FONT_SIZE_NORMAL);
      CreateLabel("risk_pct_value", "---", x_col2, y_offset, COLOR_NEUTRAL_TEXT, FONT_SIZE_NORMAL);
      y_offset += SPACING_MEDIUM;
      CreateLabel("risk_pos_size_prefix", "Position Size:", x_col1, y_offset, COLOR_HEADER, FONT_SIZE_NORMAL);
      CreateLabel("risk_pos_size_value", "---", x_col2, y_offset, COLOR_NEUTRAL_TEXT, FONT_SIZE_NORMAL);
      y_offset += SPACING_MEDIUM;
      CreateLabel("risk_rr_prefix", "RR Ratio:", x_col1, y_offset, COLOR_HEADER, FONT_SIZE_NORMAL);
      CreateLabel("risk_rr_value", "---", x_col2, y_offset, COLOR_NEUTRAL_TEXT, FONT_SIZE_NORMAL);
      y_offset += SPACING_MEDIUM;
      DrawSeparator("sep_risk", y_offset, x_offset);
   }

   // --- Session & Volatility Section
   if(ShowSessionModule)
   {
      CreateLabel("session_header", "SESSION & VOLATILITY", x_col1, y_offset, COLOR_HEADER, FONT_SIZE_HEADER);
      y_offset += SPACING_MEDIUM;
      CreateLabel("session_name_prefix", "Active Session:", x_col1, y_offset, COLOR_HEADER);
      CreateLabel("session_name_value", "---", x_col2, y_offset, COLOR_NEUTRAL_TEXT);
      y_offset += SPACING_MEDIUM;
      CreateLabel("session_overlap_prefix", "Session Overlap:", x_col1, y_offset, COLOR_HEADER);
      CreateLabel("session_overlap_value", "---", x_col2, y_offset, COLOR_NEUTRAL_TEXT);
      y_offset += SPACING_MEDIUM;
      CreateLabel("session_vol_prefix", "Volatility:", x_col1, y_offset, COLOR_HEADER);
      CreateRectangle("session_vol_bg", x_col2, y_offset - 2, 60, 14, clrNONE);
      CreateLabel("session_vol_value", "---", x_col2 + 4, y_offset, COLOR_NEUTRAL_TEXT);
      y_offset += SPACING_MEDIUM;
      DrawSeparator("sep_session", y_offset, x_offset);
   }

   // --- HUD Metrics Section
   CreateLabel("hud_header", "HUD Metrics", x_col1, y_offset, COLOR_HEADER, FONT_SIZE_HEADER);
   CreateLabel("hud_toggle", g_hud_expanded ? "[-]" : "[+]", x_toggle, y_offset, COLOR_TOGGLE, FONT_SIZE_HEADER);
   y_offset += SPACING_MEDIUM;
   if(g_hud_expanded)
   {
      CreateLabel("hud_spread", "Spread:", x_col1, y_offset, COLOR_HEADER);
      CreateLabel("hud_spread_val", "-", x_col2, y_offset, COLOR_NEUTRAL_TEXT);
      y_offset += SPACING_MEDIUM;
      CreateLabel("hud_atr", "ATR (" + IntegerToString(atr_period) + "):", x_col1, y_offset, COLOR_HEADER);
      CreateLabel("hud_atr_val", "-", x_col2, y_offset, COLOR_NEUTRAL_TEXT);
   }
   y_offset += SPACING_SEPARATOR - (g_hud_expanded ? SPACING_MEDIUM : 0);
   DrawSeparator("sep2", y_offset, x_offset);
   // --- Final Signal Section (Layout Refined) ---
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
   DrawSeparator("sep3", y_offset, x_offset);
   // --- Trade Info Section
   CreateLabel("trade_header", "Trade Info", x_col1, y_offset, COLOR_HEADER);
   y_offset += SPACING_MEDIUM;
   CreateLabel("trade_entry_prefix", "Entry:", x_col1, y_offset, COLOR_HEADER);
   CreateLabel("trade_entry_value", "-", x_col2, y_offset, COLOR_NEUTRAL_TEXT);
   y_offset += SPACING_MEDIUM;
   CreateLabel("trade_tp_prefix", "TP:", x_col1, y_offset, COLOR_HEADER);
   CreateLabel("trade_tp_value", "-", x_col2, y_offset, COLOR_NEUTRAL_TEXT);
   y_offset += SPACING_MEDIUM;
   CreateLabel("trade_sl_prefix", "SL:", x_col1, y_offset, COLOR_HEADER);
   CreateLabel("trade_sl_value", "-", x_col2, y_offset, COLOR_NEUTRAL_TEXT);
   y_offset += SPACING_MEDIUM;
   CreateLabel("trade_status_prefix", "Status:", x_col1, y_offset, COLOR_HEADER);
   CreateLabel("trade_status_value", "☐ No Trade", x_col2, y_offset, COLOR_NEUTRAL_TEXT);
   y_offset += SPACING_SEPARATOR;
   DrawSeparator("sep4", y_offset, x_offset);
   // --- Trade Signal Section
   CreateLabel("trade_signal_header", "TRADE SIGNAL", x_col1, y_offset, COLOR_HEADER, FONT_SIZE_HEADER);
   CreateLabel("trade_signal_status", "NO SIGNAL", x_col2, y_offset, COLOR_NO_SIGNAL, FONT_SIZE_SIGNAL);
   y_offset += SPACING_LARGE;
   // --- Footer & Debug Info ---
   CreateLabel("footer", "AlfredAI™ Pane · v1.8.4 · Built for Traders", PANE_X_POS + PANE_WIDTH - 10, y_offset, COLOR_FOOTER, FONT_SIZE_NORMAL - 1, ANCHOR_RIGHT);
   y_offset += SPACING_MEDIUM;
   if(ShowDebugInfo)
   {
      CreateLabel("debug_info", "---", x_offset, y_offset, COLOR_TEXT_DIM, FONT_SIZE_NORMAL - 1);
      y_offset += SPACING_MEDIUM;
   }

   // --- Background
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
   // --- Update Upcoming News
   if(ShowNewsModule)
   {
      NewsEventData news_items[];
      ArrayResize(news_items, MAX_NEWS_ITEMS);
      int news_count = GetUpcomingNews(news_items);

      for(int i = 0; i < MAX_NEWS_ITEMS; i++)
      {
         string idx = IntegerToString(i);
         if(i < news_count)
         {
            UpdateLabel("news_time_" + idx, news_items[i].time, COLOR_TEXT_DIM);
            UpdateLabel("news_curr_" + idx, news_items[i].currency, COLOR_NEUTRAL_TEXT);
            string event_obj = PANE_PREFIX + "news_curr_" + idx;
            ObjectSetString(0, event_obj, OBJPROP_FONT, "Arial Bold");
            UpdateLabel("news_event_" + idx, news_items[i].event_name, COLOR_NEUTRAL_TEXT);
            UpdateLabel("news_impact_" + idx, NewsImpactToString(news_items[i].impact), NewsImpactToColor(news_items[i].impact));
         }
         else
         {
            UpdateLabel("news_time_" + idx, "");
            UpdateLabel("news_curr_" + idx, "");
            UpdateLabel("news_event_" + idx, "");
            UpdateLabel("news_impact_" + idx, "");
         }
      }
   }

   // --- Update Emotional State
   if(ShowEmotionalState)
   {
      EmotionalStateData emotion_data = GetEmotionalState();
      UpdateLabel("emotion_indicator", "●", EmotionalStateToColor(emotion_data.state));
      UpdateLabel("emotion_text", emotion_data.text, COLOR_NEUTRAL_TEXT);
   }

   // --- Update Alert Center
   if(ShowAlertCenter)
   {
      AlertData alert_data = GetAlertCenterStatus();
      UpdateLabel("alert_status", alert_data.text, AlertStatusToColor(alert_data.status));
   }

   // --- Update Pane Settings
   if(ShowPaneSettings)
   {
      string on = "✅";
      string off = "❌";
      color on_c = COLOR_BULL;
      color off_c = COLOR_NO_SIGNAL;
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
      // Timeframes for this specific module
      string tf_bias_strings[] = {"M15", "M30", "H1", "H2", "H4", "D1"};
      ENUM_TIMEFRAMES tf_bias_enums[] = {PERIOD_M15, PERIOD_M30, PERIOD_H1, PERIOD_H2, PERIOD_H4, PERIOD_D1};
      double current_price = SymbolInfoDouble(_Symbol, SYMBOL_BID);
      for(int i = 0; i < ArraySize(tf_bias_strings); i++)
      {
         string tf_str = tf_bias_strings[i];
         ENUM_TIMEFRAMES tf_enum = tf_bias_enums[i];

         // Fetch data directly using iCustom for this specific module
         double raw_zone_val = iCustom(_Symbol, tf_enum, "AlfredSupDemCore.ex5", 0, 0);
         double magnet_level = iCustom(_Symbol, tf_enum, "AlfredSupDemCore.ex5", 1, 0);

         int zone_val = 0;
         // 1=Demand, -1=Supply, 0=None
         if(raw_zone_val > 0.5) zone_val = 1;
         else if(raw_zone_val < -0.5) zone_val = -1;

         // --- Update Bias ---
         UpdateLabel("biases_" + tf_str + "_value", GetBiasLabelFromZone(zone_val), GetBiasColorFromZone(zone_val));
         // --- Update Zone ---
         ENUM_ZONE zone_enum = ZONE_NONE;
         if(zone_val == 1) zone_enum = ZONE_DEMAND;
         else if(zone_val == -1) zone_enum = ZONE_SUPPLY;
         UpdateLabel("zone_" + tf_str + "_value", ZoneToString(zone_enum), ZoneToColor(zone_enum));
         // --- Update Magnet ---
         string magnet_text = GetMagnetRelationLabel(current_price, magnet_level);
         UpdateLabel("magnet_" + tf_str + "_value", magnet_text, GetMagnetRelationColor(magnet_text));
      }
   }


   // --- MODIFIED: Update Zone Interaction Status and Quality Details ---
   ENUM_ZONE_INTERACTION interaction = GetCurrentZoneInteraction();
   UpdateLabel("zone_interaction_status", ZoneInteractionToString(interaction), ZoneInteractionToColor(interaction));
   string highlight_obj = PANE_PREFIX + "zone_interaction_highlight";
   ObjectSetInteger(0, highlight_obj, OBJPROP_BGCOLOR, ZoneInteractionToHighlightColor(interaction));
   if(interaction != INTERACTION_NONE)
   {
      CachedSupDemData zone_data = GetSupDemData(_Period);
      string strength_text = StringFormat("%.0f/10", zone_data.strength);
      UpdateLabel("zone_qual_str_value", strength_text, COLOR_NEUTRAL_TEXT);

      string fresh_text = (zone_data.freshness > 0.5) ? "Yes" : "No";
      color fresh_color = (zone_data.freshness > 0.5) ?
      COLOR_BULL : COLOR_BEAR;
      UpdateLabel("zone_qual_fresh_value", fresh_text, fresh_color);

      string vol_text = (zone_data.volume > 0.5) ? "Yes" : "No";
      color vol_color = (zone_data.volume > 0.5) ? COLOR_BULL : COLOR_BEAR;
      UpdateLabel("zone_qual_vol_value", vol_text, vol_color);

      string liq_text = (zone_data.liquidity > 0.5) ?
      "CONFIRMED" : "No";
      color liq_color = (zone_data.liquidity > 0.5) ? clrLime : COLOR_BEAR;
      // Highlight liquidity grab
      UpdateLabel("zone_qual_liq_value", liq_text, liq_color);
      if(zone_data.liquidity > 0.5)
      {
         ObjectSetString(0, PANE_PREFIX + "zone_qual_liq_value", OBJPROP_FONT, "Arial Bold");
      }
      else
      {
         ObjectSetString(0, PANE_PREFIX + "zone_qual_liq_value", OBJPROP_FONT, "Arial");
      }
   }
   else
   {
      UpdateLabel("zone_qual_str_value", "N/A", COLOR_NA);
      UpdateLabel("zone_qual_fresh_value", "N/A", COLOR_NA);
      UpdateLabel("zone_qual_vol_value", "N/A", COLOR_NA);
      UpdateLabel("zone_qual_liq_value", "N/A", COLOR_NA);
      ObjectSetString(0, PANE_PREFIX + "zone_qual_liq_value", OBJPROP_FONT, "Arial");
   }


   // --- Update Zone Heatmap (FIXED) ---
   if(ShowZoneHeatmap)
   {
      for(int i = 0; i < ArraySize(g_heatmap_tfs); i++)
      {
         ENUM_TIMEFRAMES tf = g_heatmap_tfs[i];
         string tf_str = g_heatmap_tf_strings[i];

         // Fetch live strength score from SupDemCore
         double strength_score_raw = iCustom(_Symbol, tf, "AlfredSupDemCore.ex5", 2, 0);
         int strength_score = (int)MathRound(strength_score_raw);

         string heatmap_text;
         if(strength_score >= 8) heatmap_text = "🔥 " + IntegerToString(strength_score);
         else if(strength_score >= 5) heatmap_text = "🟧 " + IntegerToString(strength_score);
         else if(strength_score >= 1) heatmap_text = "🟨 " + IntegerToString(strength_score);
         else heatmap_text = "⚪ " + IntegerToString(strength_score);
         
         UpdateLabel("heatmap_status_" + tf_str, heatmap_text, GetHeatColorForStrength(strength_score));
      }
   }

   // --- Update Magnet Projection
   if(ShowMagnetProjection)
   {
      double magnet_level = GetMagnetProjectionLevel();
      double current_price = SymbolInfoDouble(_Symbol, SYMBOL_BID);
      ENUM_MAGNET_RELATION relation = GetMagnetProjectionRelation(current_price, magnet_level);

      string price_format = "%." + IntegerToString(_Digits) + "f";
      string level_text = (magnet_level == 0.0) ? "---" : StringFormat(price_format, magnet_level);
      UpdateLabel("magnet_level", "Magnet → " + level_text, COLOR_NEUTRAL_TEXT);
      UpdateLabel("magnet_relation", MagnetRelationToString(relation), MagnetRelationToColor(relation));
   }

   // --- Update Multi-TF Magnet Summary ---
   if(ShowMultiTFMagnets)
   {
      double current_price = SymbolInfoDouble(_Symbol, SYMBOL_BID);
      double proximity = 2 * _Point; // Proximity threshold in points

      for(int i = 0; i < ArraySize(g_magnet_summary_tfs); i++)
      {
         ENUM_TIMEFRAMES tf = g_magnet_summary_tfs[i];
         string tf_str = g_magnet_summary_tf_strings[i];

         // Fetch live magnet level from SupDemCore
         double magnet_level = iCustom(_Symbol, tf, "AlfredSupDemCore.ex5", 1, 0);
         string relation_text;
         color relation_color;

         if(magnet_level > 0.0)
         {
            if (current_price > magnet_level + proximity)
            {
               relation_text = "Above";
               relation_color = clrOrangeRed; // Soft Red
            }
            else if (current_price < magnet_level - proximity)
            {
               relation_text = "Below";
               relation_color = clrLimeGreen; // Soft Green
            }
            else
            {
               relation_text = "At Magnet";
               relation_color = clrGray; // Neutral Gray
            }
         }
         else
         {
             relation_text = "N/A";
             relation_color = COLOR_NA;
         }
         
         string price_format = "(%." + IntegerToString(_Digits) + "f)";
         string level_text = (magnet_level == 0.0) ? "(N/A)" : StringFormat(price_format, magnet_level);

         UpdateLabel("mtf_magnet_relation_" + tf_str, relation_text, relation_color);
         UpdateLabel("mtf_magnet_level_" + tf_str, level_text, relation_color);
      }
   }

   // --- Update HUD Zone Activity ---
   if(ShowHUDActivitySection)
   {
      for(int i = 0; i < ArraySize(g_hud_tfs); i++)
      {
         ENUM_TIMEFRAMES tf = g_hud_tfs[i];
         string tf_str = g_hud_tf_strings[i];

         // D1 data is not available from AlfredHUD.ex5
         if(tf == PERIOD_D1)
         {
            UpdateLabel("hud_activity_status_" + tf_str, "N/A", COLOR_NA);
            continue;
         }

         bool is_active = GetHUDZoneActivity(tf);
         string status_text = is_active ?
         "✅" : "❌";
         color status_color = is_active ? COLOR_BULL : COLOR_BEAR;

         UpdateLabel("hud_activity_status_" + tf_str, status_text, status_color);
      }
   }

   // --- MODIFIED: Update Confidence Matrix with new scoring and colors
   if(ShowConfidenceMatrix)
   {
      for(int i = 0; i < ArraySize(g_matrix_tfs); i++)
      {
         ENUM_TIMEFRAMES tf = g_matrix_tfs[i];
         string tf_str = g_matrix_tf_strings[i];
         MatrixRowData data = GetConfidenceMatrixRow(tf); // This now returns the new score

         UpdateLabel("matrix_bias_" + tf_str, BiasToString(data.bias), BiasToColor(data.bias));
         UpdateLabel("matrix_zone_" + tf_str, ZoneToString(data.zone), ZoneToColor(data.zone));
         // Update Magnet label to show the Score instead
         UpdateLabel("matrix_magnet_" + tf_str, IntegerToString(data.score), COLOR_NEUTRAL_TEXT);
         string bg_obj = PANE_PREFIX + "matrix_bg_" + tf_str;
         // Use new color function
         ObjectSetInteger(0, bg_obj, OBJPROP_BGCOLOR, GetConfidenceColor(data.score));
         // Update font style based on score
         string font_style = (data.score >= 10) ?
         "Arial Bold" : "Arial"; // Using 10 as threshold for "strong"
         ObjectSetString(0, PANE_PREFIX + "matrix_tf_" + tf_str, OBJPROP_FONT, font_style);
         ObjectSetString(0, PANE_PREFIX + "matrix_bias_" + tf_str, OBJPROP_FONT, font_style);
         ObjectSetString(0, PANE_PREFIX + "matrix_zone_" + tf_str, OBJPROP_FONT, font_style);
         ObjectSetString(0, PANE_PREFIX + "matrix_magnet_" + tf_str, OBJPROP_FONT, font_style); // This is now the score label
      }
   }

   // --- Update Trade Recommendation
   if(ShowTradeRecommendation)
   {
      TradeRecommendation rec = GetTradeRecommendation();
      UpdateLabel("reco_action_value", RecoActionToString(rec.action), RecoActionToColor(rec.action));
      UpdateLabel("reco_reason_value", rec.reasoning, COLOR_NEUTRAL_TEXT);
      string reco_obj = PANE_PREFIX + "reco_action_value";
      if(rec.action == SIGNAL_NONE)
         ObjectSetString(0, reco_obj, OBJPROP_FONT, "Arial Italic");
      else
         ObjectSetString(0, reco_obj, OBJPROP_FONT, "Arial Bold");
   }

   // --- Update Risk & Positioning
   if(ShowRiskModule)
   {
      RiskModuleData risk_data = GetRiskModuleData();
      UpdateLabel("risk_pct_value", StringFormat("%.1f%%", risk_data.risk_percent), COLOR_NEUTRAL_TEXT);
      UpdateLabel("risk_pos_size_value", StringFormat("%.2f lots", risk_data.position_size), COLOR_NEUTRAL_TEXT);
      UpdateLabel("risk_rr_value", risk_data.rr_ratio, COLOR_NEUTRAL_TEXT);
      string rr_obj = PANE_PREFIX + "risk_rr_value";
      ObjectSetString(0, rr_obj, OBJPROP_FONT, "Arial Bold");
   }

   // --- Update Session & Volatility
   if(ShowSessionModule)
   {
      SessionData s_data = GetSessionData();
      UpdateLabel("session_name_value", s_data.session_name, COLOR_SESSION);
      UpdateLabel("session_overlap_value", s_data.session_overlap, COLOR_NEUTRAL_TEXT);

      UpdateLabel("session_vol_value", VolatilityToString(s_data.volatility), VolatilityToColor(s_data.volatility));
      string vol_obj = PANE_PREFIX + "session_vol_value";
      ObjectSetString(0, vol_obj, OBJPROP_FONT, "Arial Bold");
      string vol_bg_obj = PANE_PREFIX + "session_vol_bg";
      ObjectSetInteger(0, vol_bg_obj, OBJPROP_BGCOLOR, VolatilityToHighlightColor(s_data.volatility));
   }

   // --- Update HUD Metrics
   if(g_hud_expanded)
   {
      long spread_points = SymbolInfoInteger(_Symbol, SYMBOL_SPREAD);
      UpdateLabel("hud_spread_val", IntegerToString(spread_points) + " pts", COLOR_NEUTRAL_TEXT);
      double atr_buffer[1];
      if(CopyBuffer(hATR_current, 0, 0, 1, atr_buffer) > 0)
      {
         UpdateLabel("hud_atr_val", DoubleToString(atr_buffer[0], _Digits), COLOR_NEUTRAL_TEXT);
      }
   }

   // --- Update Final Signal with Dynamic Confidence
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
   color conf_color = adjusted_conf > 70 ? COLOR_CONF_HIGH : adjusted_conf > 40 ?
   COLOR_CONF_MED : COLOR_CONF_LOW;
   UpdateLabel("signal_conf_percent", StringFormat("(%.0f%%)", adjusted_conf), conf_color);
   int bar_width = (int)(adjusted_conf / 100.0 * CONFIDENCE_BAR_MAX_WIDTH);
   string bar_name = PANE_PREFIX + "signal_conf_bar_fg";
   ObjectSetInteger(0, bar_name, OBJPROP_XSIZE, bar_width);
   ObjectSetInteger(0, bar_name, OBJPROP_BGCOLOR, conf_color);
   ObjectSetInteger(0, bar_name, OBJPROP_COLOR, conf_color);
   ENUM_ZONE h1_zone = GetZoneStatus(PERIOD_H1);
   UpdateLabel("magnet_zone_value", ZoneToString(h1_zone), ZoneToColor(h1_zone));
   // --- Update Trade Data (TP/SL lines removed)
   LiveTradeData trade_data = FetchTradeLevels();
   string price_format = "%." + IntegerToString(_Digits) + "f";
   if(trade_data.trade_exists)
   {
      UpdateLabel("trade_entry_value", StringFormat(price_format, trade_data.entry), COLOR_NEUTRAL_TEXT);
      double sl_pips = (trade_data.sl > 0) ? CalculatePips(trade_data.entry, trade_data.sl) : 0.0;
      double tp_pips = (trade_data.tp > 0) ?
      CalculatePips(trade_data.entry, trade_data.tp) : 0.0;
      string sl_text = (trade_data.sl > 0) ? StringFormat(price_format, trade_data.sl) + StringFormat(" (-%.1f p)", sl_pips) : "---";
      string tp_text = (trade_data.tp > 0) ? StringFormat(price_format, trade_data.tp) + StringFormat(" (+%.1f p)", tp_pips) : "---";
      UpdateLabel("trade_sl_value", sl_text, COLOR_BEAR);
      UpdateLabel("trade_tp_value", tp_text, COLOR_BULL);
      UpdateLabel("trade_status_value", "☑ Active", COLOR_BULL);
   }
   else
   {
      UpdateLabel("trade_entry_value", "---", COLOR_NEUTRAL_TEXT);
      UpdateLabel("trade_sl_value", "---", COLOR_NEUTRAL_TEXT);
      UpdateLabel("trade_tp_value", "---", COLOR_NEUTRAL_TEXT);
      UpdateLabel("trade_status_value", "☐ No Trade", COLOR_NEUTRAL_TEXT);
   }

   // --- Update Trade Signal with Enlarged Font
   ENUM_TRADE_SIGNAL signal = GetTradeSignal();
   string signal_obj = PANE_PREFIX + "trade_signal_status";
   ObjectSetString(0, signal_obj, OBJPROP_TEXT, SignalToString(signal));
   ObjectSetInteger(0, signal_obj, OBJPROP_COLOR, SignalToColor(signal));
   if(signal == SIGNAL_NONE)
   {
      ObjectSetString(0, signal_obj, OBJPROP_FONT, "Arial Italic");
      ObjectSetInteger(0, signal_obj, OBJPROP_FONTSIZE, FONT_SIZE_SIGNAL);
   }
   else
   {
      ObjectSetString(0, signal_obj, OBJPROP_FONT, "Arial Bold");
      ObjectSetInteger(0, signal_obj, OBJPROP_FONTSIZE, FONT_SIZE_SIGNAL_ACTIVE);
   }

   // --- Update Debug Info ---
   if(ShowDebugInfo)
   {
      int active_modules = 0;
      if(ShowZoneHeatmap)
         active_modules++;
      if(ShowMagnetProjection)
         active_modules++;
      if(ShowMultiTFMagnets)
         active_modules++;
      if(ShowHUDActivitySection)
         active_modules++;
      if(ShowConfidenceMatrix)
         active_modules++;
      if(ShowTradeRecommendation)
         active_modules++;
      if(ShowRiskModule)
         active_modules++;
      if(ShowSessionModule)
         active_modules++;
      if(ShowNewsModule)
         active_modules++;
      if(ShowEmotionalState)
         active_modules++;
      if(ShowAlertCenter)
         active_modules++;
      if(ShowPaneSettings)
         active_modules++;
      string debug_text = StringFormat("Modules Active: %d | %s · %s | Updated: %s",
                                       active_modules,
                                       _Symbol,
                                       EnumToString(_Period),
                                       TimeToString(TimeCurrent(), TIME_SECONDS));
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
//|
// Custom indicator initialization function                         |
//+------------------------------------------------------------------+
int OnInit()
{
   hATR_current = iATR(_Symbol, _Period, atr_period);
   g_pip_value = SymbolInfoDouble(_Symbol, SYMBOL_POINT);
   if(SymbolInfoInteger(_Symbol, SYMBOL_DIGITS) == 3 || SymbolInfoInteger(_Symbol, SYMBOL_DIGITS) == 5)
   {
      g_pip_value *= 10;
   }
   MathSrand((int)TimeCurrent());
   // Seed random generator

   // Initialize caches with default values
   for(int i = 0; i < ArraySize(g_timeframes); i++)
   {
      g_compass_cache[i].bias = BIAS_NEUTRAL;
      g_compass_cache[i].confidence = 0.0;
      g_supdem_cache[i].zone = ZONE_NONE;
      g_supdem_cache[i].magnet_level = 0.0;
      // NEW:
      g_supdem_cache[i].strength = 0.0;
      g_supdem_cache[i].freshness = 0.0;
      g_supdem_cache[i].volume = 0.0;
      g_supdem_cache[i].liquidity = 0.0;
      g_hud_cache[i].zone_active = false;
   }

   RedrawPanel();
   UpdateLiveDataCaches();
   // Initial data load to prevent "N/A" on first view
   UpdatePanel();
   EventSetTimer(1);
   // Set timer to 1-second intervals
   return(INIT_SUCCEEDED);
}

//+------------------------------------------------------------------+
//|
// Timer function to trigger updates                                |
//+------------------------------------------------------------------+
void OnTimer()
{
   UpdateLiveDataCaches(); // Fetch fresh data from indicators
   UpdatePanel();
   // Update the display with cached data
}

//+------------------------------------------------------------------+
//| Custom indicator iteration function (not used for timer updates) |
//+------------------------------------------------------------------+
int OnCalculate(const int rates_total, const int p, const int b, const double &price[])
{
   return(rates_total);
}

//+------------------------------------------------------------------+
//|
// Chart event function                                             |
//+------------------------------------------------------------------+
void OnChartEvent(const int id, const long &l, const double &d, const string &s)
{
   if(id == CHARTEVENT_OBJECT_CLICK)
   {
      bool changed = false;
      if(StringFind(s, PANE_PREFIX) == 0 && StringFind(s, "_toggle") > 0)
      {
         if(s == PANE_PREFIX + "biases_toggle")
            g_biases_expanded = !g_biases_expanded;
         else if(s == PANE_PREFIX + "hud_toggle")
            g_hud_expanded = !g_hud_expanded;
         changed = true;
      }
      if(changed)
         RedrawPanel();
   }
}

//+------------------------------------------------------------------+
//|
// Deinitialization function                                        |
//+------------------------------------------------------------------+
void OnDeinit(const int reason)
{
   EventKillTimer();
   IndicatorRelease(hATR_current);
   ObjectsDeleteAll(0, PANE_PREFIX);
   ChartRedraw();
}
//+------------------------------------------------------------------+
