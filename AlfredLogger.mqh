//+------------------------------------------------------------------+
//| AlfredLogger.mqh — Phase-2 CSV Logger (no screenshots)           |
//+------------------------------------------------------------------+
#ifndef __ALFRED_LOGGER__
#define __ALFRED_LOGGER__

#include <AlfredSettings.mqh>

// returns trading session name by hour
string GetSessionName(datetime t)
{
   MqlDateTime dt;
   TimeToStruct(t, dt);
   int h = dt.hour;
   if(h <  8)  return "Asia";
   if(h < 16)  return "London";
   return        "NewYork";
}

class AlfredLogger
{
private:
   int   m_handle;
   bool  m_ready;

public:
   // constructor
   AlfredLogger() : m_handle(INVALID_HANDLE), m_ready(false) {}

   // open CSV & write header if new
   bool Init()
   {
      // respect the EA’s input flag
      if(!Alfred.logToFile)
         return false;

      // open (or create) the CSV file in the Tester’s Files folder
      m_handle = FileOpen(
         Alfred.logFilename,
         FILE_READ|FILE_WRITE|FILE_CSV|FILE_ANSI
      );
      if(m_handle < 0)
      {
         PrintFormat("AlfredLogger ▶ cannot open '%s', error %d",
                     Alfred.logFilename, GetLastError());
         return false;
      }

      // write header if file is empty
      if(FileSize(m_handle) == 0)
      {
         string hdr = "timestamp,symbol,tf,event,val1,val2";
         if(Alfred.logIncludeATR)     hdr += ",ATR14";
         if(Alfred.logIncludeSession) hdr += ",session";
         FileWriteString(m_handle, hdr + "\r\n");
      }

      // seek to end for appending
      FileSeek(m_handle, 0, SEEK_END);
      m_ready = true;
      return true;
   }

   // log one event line
   void LogEvent(
      datetime         t,
      string           symbol,
      ENUM_TIMEFRAMES  tf,
      string           tag,
      double           v1 = EMPTY_VALUE,
      double           v2 = EMPTY_VALUE
   )
   {
      if(!m_ready || !Alfred.logToFile)
         return;

      // build the CSV row
      string line = TimeToString(t, TIME_DATE|TIME_SECONDS) + ",";
             line += symbol + ",";
             line += EnumToString(tf) + ",";
             line += tag + ",";
             line += DoubleToString(v1, 8) + ",";
             line += DoubleToString(v2, 8);

      // optional ATR column
      if(Alfred.logIncludeATR)
      {
         double arr[];
         double atrVal = EMPTY_VALUE;
         int    hATR   = iATR(symbol, tf, 14);
         if(hATR != INVALID_HANDLE
            && CopyBuffer(hATR, 0, 1, 1, arr) == 1)
            atrVal = arr[0];
         if(hATR != INVALID_HANDLE)
            IndicatorRelease(hATR);

         line += "," + DoubleToString(atrVal, _Digits);
      }

      // optional session column
      if(Alfred.logIncludeSession)
         line += "," + GetSessionName(t);

      // write and flush
      FileWriteString(m_handle, line + "\r\n");
      FileFlush(m_handle);
   }

   // close file on deinit
   void Deinit()
   {
      if(m_ready)
      {
         FileClose(m_handle);
         m_ready = false;
      }
   }
};

#endif // __ALFRED_LOGGER__
