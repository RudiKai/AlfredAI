//+------------------------------------------------------------------+
//| AlfredSettings.mqh — Central Config                              |
//+------------------------------------------------------------------+
#ifndef __ALFRED_SETTINGS__
#define __ALFRED_SETTINGS__

struct AlfredSettings
{
   // Display
   int   fontSize;
   int   corner;
   int   xOffset;
   int   yOffset;

   // Behavior
   bool  showZoneWarning;
   bool  enableAlerts;
   bool  enablePane;
   bool  enableHUD;
   bool  enableCompass;

   // AlertCenter
   bool  enableAlertCenter;
   bool  alertStrongBiasAligned;
   bool  alertDivergence;
   bool  alertZoneEntry;
   bool  alertBiasFlip;
   int   alertConfidenceThreshold;

   // Risk & SL/TP
   double atrMultiplierSL;
   double atrMultiplierTP;

   // Notifications
   bool  sendTelegram;
   bool  sendWhatsApp;

   // Expansion
   int   alertSensitivity;
   int   zoneProximityThreshold;

   // HUD Layout
   bool  enableHUDDiagnostics;
   int   hudCorner;
   int   hudXOffset;
   int   hudYOffset;

   // SupDemCore
   int    supdemZoneLookback;
   int    supdemZoneDurationBars;
   double supdemMinImpulseMovePips;
   color  supdemDemandColorHTF;
   color  supdemDemandColorLTF;
   color  supdemSupplyColorHTF;
   color  supdemSupplyColorLTF;
   int    supdemRefreshRateSeconds;
   bool   supdemEnableBreakoutRemoval;
   bool   supdemRequireBodyClose;
   bool   supdemEnableTimeDecay;
   int    supdemTimeDecayBars;
   bool   supdemEnableMagnetForecast;

   // Compass Layout
   int   compassYOffset;

   // Logging (Phase 2)
   bool   logToFile;
   string logFilename;
   bool   logIncludeATR;
   bool   logIncludeSession;
   bool   logEnableScreenshots;
   string screenshotFolder;
   int    screenshotWidth;
   int    screenshotHeight;
};

// global config
AlfredSettings Alfred;

#endif // __ALFRED_SETTINGS__
