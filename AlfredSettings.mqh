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
};

// global instance
AlfredSettings Alfred;

#endif
