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

   // AlertCenter settings
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

   // Future expansion
   int   alertSensitivity;
   int   zoneProximityThreshold;

   // HUD-specific layout
   bool  enableHUDDiagnostics;
   int   hudCorner;
   int   hudXOffset;
   int   hudYOffset;

   // SupDemCore settings
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

   // Compass-specific layout
   int   compassYOffset;
};

// global instance
AlfredSettings Alfred;

#endif
