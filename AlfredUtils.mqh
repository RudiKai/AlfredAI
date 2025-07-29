//+------------------------------------------------------------------+
//| AlfredUtils.mqh – Shared Helpers                                  |
//+------------------------------------------------------------------+
#property once

#include <AlfredSettings.mqh>

//–– Get multi-TF magnet strength
double   GetTFMagnet(const MQLRates &rates[], ENUM_TIMEFRAMES tf, int period);

//–– Compute compass bias from slope
int      GetCompassBias(const MQLRates &rates[], int lookback);

//–– Determine zone proximity
double   GetZoneProximity(const Zone &zone, double price);

#include <AlfredSupDemCore.mqh>
