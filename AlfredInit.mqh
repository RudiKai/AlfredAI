//+------------------------------------------------------------------+
//| AlfredInit.mqh — Initialize AlfredSettings                       |
//+------------------------------------------------------------------+
#ifndef __ALFRED_INIT__
#define __ALFRED_INIT__

#include <AlfredSettings.mqh>

void InitAlfredDefaults()
{
   // Display
   Alfred.fontSize               = 10;
   Alfred.corner                 = CORNER_RIGHT_UPPER;
   Alfred.xOffset                = 220;
   Alfred.yOffset                = 20;

   // Behavior
   Alfred.showZoneWarning        = true;
   Alfred.enableAlerts           = true;
   Alfred.enablePane             = true;
   Alfred.enableHUD              = true;
   Alfred.enableCompass          = true;

   // AlertCenter defaults
   Alfred.enableAlertCenter           = true;
   Alfred.alertStrongBiasAligned      = true;
   Alfred.alertDivergence             = true;
   Alfred.alertZoneEntry              = true;
   Alfred.alertBiasFlip               = true;
   Alfred.alertConfidenceThreshold    = 85;

   // Risk & SL/TP
   Alfred.atrMultiplierSL        = 1.5;
   Alfred.atrMultiplierTP        = 2.0;

   // Notifications
   Alfred.sendTelegram           = true;
   Alfred.sendWhatsApp           = false;

   // Future expansion
   Alfred.alertSensitivity       = 3;
   Alfred.zoneProximityThreshold = 20;

   // HUD-specific defaults
   Alfred.enableHUDDiagnostics   = false;
   Alfred.hudCorner              = CORNER_LEFT_UPPER;
   Alfred.hudXOffset             = 10;
   Alfred.hudYOffset             = 20;

   // SupDemCore defaults
   Alfred.supdemZoneLookback           = 50;
   Alfred.supdemZoneDurationBars       = 15;
   Alfred.supdemMinImpulseMovePips     = 20.0;
   Alfred.supdemDemandColorHTF         = clrNavy;
   Alfred.supdemDemandColorLTF         = clrLime;
   Alfred.supdemSupplyColorHTF         = clrIndigo;
   Alfred.supdemSupplyColorLTF         = clrRed;
   Alfred.supdemRefreshRateSeconds     = 5;
   Alfred.supdemEnableBreakoutRemoval  = true;
   Alfred.supdemRequireBodyClose       = true;
   Alfred.supdemEnableTimeDecay        = true;
   Alfred.supdemTimeDecayBars          = 60;
   Alfred.supdemEnableMagnetForecast   = true;

   // Compass-specific defaults
   Alfred.compassYOffset              = 20;
}

#endif
