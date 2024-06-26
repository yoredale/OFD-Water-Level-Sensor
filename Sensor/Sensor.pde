/*
    ------ Waspmote Pro Code Example --------

    Explanation: This is the basic Code for Waspmote Pro

    Copyright (C) 2016 Libelium Comunicaciones Distribuidas S.L.
    http://www.libelium.com

    This program is free software: you can redistribute it and/or modify
    it under the terms of the GNU General Public License as published by
    the Free Software Foundation, either version 3 of the License, or
    (at your option) any later version.

    This program is distributed in the hope that it will be useful,
    but WITHOUT ANY WARRANTY; without even the implied warranty of
    MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
    GNU General Public License for more details.

    You should have received a copy of the GNU General Public License
    along with this program.  If not, see <http://www.gnu.org/licenses/>.
*/

// Put your libraries here (#include ...)
#include <WaspGPS.h>
#include <currentLoop.h>
#include <WaspFrame.h>
#include <WaspLoRaWAN.h>

// Include the configuration file
#include "Sensor.h"


// Define GPS Timeout
#define GPS_TIMEOUT 240

//////////////////////////////////////////////
uint8_t socket = SOCKET0;
//////////////////////////////////////////////

// Define port to use in Back-End: from 1 to 223
uint8_t PORT = 3;

// variable
uint8_t error;
uint8_t error_config = 0;
uint8_t sd_error = 0;
uint8_t ts_error = 1;

timestamp_t   time;
unsigned long time_sync = 0;
unsigned long sample_time;
uint16_t sensor_value;
char sensor_message[8];
char data[17];




// This uses the GPS to set the RTC and record the time it happened

uint8_t setTime()
{
  RTC.ON();
  USB.println(RTC.getTime());
  RTC.OFF();
  bool gps_status;
  
  // set GPS ON  
  GPS.ON();

  bool status = false;
  //////////////////////////////////////////////////////
  // 1. wait for GPS signal for specific time
  //////////////////////////////////////////////////////
  status = GPS.waitForSignal(GPS_TIMEOUT);

  //////////////////////////////////////////////////////
  // 2. if GPS is connected then set Time and Date to RTC
  //////////////////////////////////////////////////////
  if( status == true )
  {    
  // set RTC ON
    RTC.ON();
  // set time in RTC from GPS time (GMT time)
    GPS.setTimeFromGPS();
    // Update time_sync
    time_sync = RTC.getEpochTime();
    USB.println(RTC.getTime());
    // Turn RTC off again.
    RTC.OFF();
    //
    // Time synced succesfully, clear the ts_error code
    ts_error = 0;
  }
  else
  {
    if (time_sync == 0)
      {
      	 //
	       // time sync has never succeeded RTC has never synced
	       ts_error = 1;
      }
    else
      {
	       //
	       // time sync has succeeded in the past but not this time
	       // RTC is likely only slightly out. Add 25 hours to time_sync
         // so it doesn't attempt it again until tomorrow + 1 hour.
         time_sync = time_sync + 86400;
	       ts_error = 2;
      }
  }
  GPS.OFF();
  return ts_error;
}



//
// Read the sensor value from the 4-20mA board and store it
// in sensor_value

uint8_t readSensor()
{
  // Sets the 5V switch ON
  currentLoopBoard.ON(SUPPLY5V);
  delay(100);

  // Sets the 12V switch ON
  currentLoopBoard.ON(SUPPLY12V);
  delay(2000);
  if (currentLoopBoard.isConnected(CHANNEL1))
  {
    // Read the sensor
    sensor_value =  currentLoopBoard.readChannel(CHANNEL1);
    delay(100);
     //
    // Sets the 12V switch OFF
    currentLoopBoard.OFF(SUPPLY12V);
    delay(100);

    // Turn off the 4-20mA board
    currentLoopBoard.OFF(SUPPLY5V);
  }
  else
  {
     //
    // Sets the 12V switch OFF
    currentLoopBoard.OFF(SUPPLY12V);
    delay(100);

    // Turn off the 4-20mA board
    currentLoopBoard.OFF(SUPPLY5V);
    sensor_value = 0;
    return 1;
  }
  USB.println(sensor_value);
  return 0;
}



//
// build a data frame with sensor_value and the battery level
// ready to transmit.

void buildFrame()
{
  // Create new frame (BINARY)
  frame.createFrame(BINARY);
  // set frame fields (Battery sensor - uint8_t)
  frame.addSensor(SENSOR_BAT, PWR.getBatteryLevel());
  //
  // Waspmote doesn't define a sensor type for the current loop value
  // It does define one for the current loop current reading.
  // We've defined a custom sensor type in WaspFrameConstantsv15.h
  // for the current loop value. ID 200
  frame.addSensor(SENSOR_SWCC_CLOOP, (sensor_value) );
  //
  // If we have an SD card error, add an SD_ERR, ID 201
  if (sd_error > 0)
  {
    frame.addSensor(SENSOR_SWCC_SD_ERR, sd_error);
  }
  // If we have a time sync error (eg GPS not syncing), add a TS_ERR, ID 202 
  if (ts_error > 0)
  {
    frame.addSensor(SENSOR_SWCC_TS_ERR, ts_error);
  }
  
  
  // frame.addSensor(SENSOR_CU, current);
  // Print frame
  frame.showFrame();
}


void sendFrame()
{
  
  //////////////////////////////////////////////
  // 2. Switch on
  //////////////////////////////////////////////

  error = LoRaWAN.ON(socket);

  // Check status
  if ( error == 0 )
  {
    USB.println(F("2. Switch ON OK"));
  }
  else
  {
    USB.print(F("2. Switch ON error = "));
    USB.println(error, DEC);
  }


  //////////////////////////////////////////////
  // 3. Join network
  //////////////////////////////////////////////

  error = LoRaWAN.joinABP();

  // Check status
  if ( error == 0 )
  {
    USB.println(F("3. Join network OK"));

    error = LoRaWAN.getMaxPayload();

    if (error == 0)
    {
      //////////////////////////////////////////////
      // 4. Generate tiny frame
      //////////////////////////////////////////////

      USB.print(F("4.1. LoRaWAN maximum payload: "));
      USB.println(LoRaWAN._maxPayload, DEC);

      // set maximum payload
      frame.setTinyLength(LoRaWAN._maxPayload);

      boolean end = false;
      uint8_t pending_fields = 0;

      while (end == false)
      {
        pending_fields = frame.generateTinyFrame();

        USB.print(F("4.2. Tiny frame generated:"));
        USB.printHexln(frame.bufferTiny, frame.lengthTiny);


        //////////////////////////////////////////////
        // 5. Send confirmed packet
        //////////////////////////////////////////////

        USB.println(F("5. LoRaWAN confirmed sending..."));
        error = LoRaWAN.sendConfirmed( PORT, frame.bufferTiny, frame.lengthTiny);

        // Error messages:
        /*
          '6' : Module hasn't joined a network
          '5' : Sending error
          '4' : Error with data length
          '2' : Module didn't response
          '1' : Module communication error
        */
        // Check status
        if (error == 0)
        {
          USB.println(F("5.1. LoRaWAN send packet OK"));
          if (LoRaWAN._dataReceived == true)
          {
            USB.print(F("  There's data on port number: "));
            USB.print(LoRaWAN._port, DEC);
            USB.print(F("\r\n  Data: "));
            USB.println(LoRaWAN._data);
          }
        }
        else
        {
          USB.print(F("5.1. LoRaWAN send packet error = "));
          USB.println(error, DEC);
        }

        if (pending_fields > 0)
        {
          end = false;
          delay(10000);
        }
        else
        {
          end = true;
        }
      }
    }
    else
    {
      USB.println(F("4. LoRaWAN error getting the maximum payload"));
    }
  }
  else
  {
    USB.print(F("2. Join network error = "));
    USB.println(error, DEC);
  }


  //////////////////////////////////////////////
  // 6. Switch off
  //////////////////////////////////////////////

  error = LoRaWAN.OFF(socket);

  // Check status
  if ( error == 0 )
  {
    USB.println(F("6. Switch OFF OK"));
  }
  else
  {
    USB.print(F("6. Switch OFF error = "));
    USB.println(error, DEC);
  }
}



uint8_t joinOTAA()
{
   //
  // Set up module join OTAA.
  USB.ON();

  USB.println(F("------------------------------------"));
  USB.println(F("Module configuration"));
  USB.println(F("------------------------------------\n"));


  //////////////////////////////////////////////
  // 1. Switch on
  //////////////////////////////////////////////

  error = LoRaWAN.ON(socket);

  // Check status
  if ( error == 0 )
  {
    USB.println(F("1. Switch ON OK"));
  }
  else
  {
    USB.print(F("1. Switch ON error = "));
    USB.println(error, DEC);
    error_config = 1;
  }


  //////////////////////////////////////////////
  // 2. Change data rate
  //////////////////////////////////////////////

  error = LoRaWAN.setDataRate(3);

  // Check status
  if ( error == 0 )
  {
    USB.println(F("2. Data rate set OK"));
  }
  else
  {
    USB.print(F("2. Data rate set error= "));
    USB.println(error, DEC);
    error_config = 2;
  }


  //////////////////////////////////////////////
  // 3. Set Device EUI
  //////////////////////////////////////////////

  error = LoRaWAN.setDeviceEUI(DEVICE_EUI);

  // Check status
  if ( error == 0 )
  {
    USB.println(F("3. Device EUI set OK"));
  }
  else
  {
    USB.print(F("3. Device EUI set error = "));
    USB.println(error, DEC);
    error_config = 3;
  }

  //////////////////////////////////////////////
  // 4. Set Application EUI
  //////////////////////////////////////////////

  error = LoRaWAN.setAppEUI(APP_EUI);

  // Check status
  if ( error == 0 )
  {
    USB.println(F("4. Application EUI set OK"));
  }
  else
  {
    USB.print(F("4. Application EUI set error = "));
    USB.println(error, DEC);
    error_config = 4;
  }

  //////////////////////////////////////////////
  // 5. Set Application Session Key
  //////////////////////////////////////////////

  error = LoRaWAN.setAppKey(APP_KEY);

  // Check status
  if ( error == 0 )
  {
    USB.println(F("5. Application Key set OK"));
  }
  else
  {
    USB.print(F("5. Application Key set error = "));
    USB.println(error, DEC);
    error_config = 5;
  }

  /////////////////////////////////////////////////
  // 6. Join OTAA to negotiate keys with the server
  /////////////////////////////////////////////////

  error = LoRaWAN.joinOTAA();

  // Check status
  if ( error == 0 )
  {
    USB.println(F("6. Join network OK"));
  }
  else
  {
    USB.print(F("6. Join network error = "));
    USB.println(error, DEC);
    error_config = 6;
  }


  //////////////////////////////////////////////
  // 7. Save configuration
  //////////////////////////////////////////////

  error = LoRaWAN.saveConfig();

  // Check status
  if ( error == 0 )
  {
    USB.println(F("7. Save configuration OK"));
  }
  else
  {
    USB.print(F("7. Save configuration error = "));
    USB.println(error, DEC);
    error_config = 7;
  }

  //////////////////////////////////////////////
  // 8. Switch off
  //////////////////////////////////////////////

  error = LoRaWAN.OFF(socket);

  // Check status
  if ( error == 0 )
  {
    USB.println(F("8. Switch OFF OK"));
  }
  else
  {
    USB.print(F("8. Switch OFF error = "));
    USB.println(error, DEC);
    error_config = 8;
  }
  
  if (error_config == 0) {
    USB.println(F("\n---------------------------------------------------------------"));
    USB.println(F("Module configured"));
    USB.println(F("After joining through OTAA, the module and the network exchanged "));
    USB.println(F("the Network Session Key and the Application Session Key which "));
    USB.println(F("are needed to perform communications. After that, 'ABP mode' is used"));
    USB.println(F("to join the network and send messages after powering on the module"));
    USB.println(F("---------------------------------------------------------------\n"));
    USB.println();
  }
  else {
    USB.println(F("\n---------------------------------------------------------------"));
    USB.println(F("Module not configured"));
    USB.println(F("Check OTTA parameters and reestart the code."));
    USB.println(F("If you continue executing the code, frames will not be sent."));
    USB.println(F("\n---------------------------------------------------------------"));
  }
  // set the Waspmote ID
}





uint8_t writeDataToFile ()
{
  uint8_t sd_answer;
  // uint8_t flag;
  char file_data[21] = "";
  char convert[6] = "";
  // Generate UTC ISO 8601 time record from the timestamp.
  sprintf(convert, "20%d", time.year);
  strcat(file_data, convert);
  strcat(file_data, "-");
  if (sprintf(convert, "%d", time.month) == 1)
  {
    sprintf(convert, "0%d", time.month);
  }
  strcat(file_data, convert);
  strcat(file_data, "-");
  if (sprintf(convert, "%d", time.date) == 1)
  {
    sprintf(convert, "0%d", time.date);
  }
  strcat(file_data, convert);
  strcat(file_data, "T");
  if (sprintf(convert, "%d", time.hour) == 1)
  {
    sprintf(convert, "0%d", time.hour);
  }
  strcat(file_data, convert);
  strcat(file_data, ":");
  if (sprintf(convert, "%d", time.minute) == 1)
  {
    sprintf(convert, "0%d", time.minute);
  }
  strcat(file_data, convert);
  strcat(file_data, ":");
  if (sprintf(convert, "%d", time.second) == 1)
  {
    sprintf(convert, "0%d", time.second);
  }
  strcat(file_data, convert);
  strcat(file_data, "Z");
  sprintf(convert, "%d\n", sensor_value);
  // Print the data line
  USB.print(file_data);
  USB.print(", ");
  USB.println(convert);

  // Turn on the SD card
  SD.ON();
  // check if there was any problem with the initialisation
  if (SD.flag > 0)
  {
    USB.print ("The SD card failed to initialise, SD.flag is currently: ");
    USB.println(SD.flag);
    SD.OFF();
    return SD.flag;
  }
  sd_answer = SD.isSD();
  if (sd_answer == 0)
    {
      // Card not Present
      SD.OFF();
      return SD.flag;
    }
  //
  // Card is present, so continue
  // Set the filename for the data file.
  // we set a new file for each month
  // aka 24-04
  char filename[6] = "";
  if (time.month < 10)
  {
    sprintf(filename, "%d-0%d", time.year, time.month);
  }
  else
  {
    sprintf(filename, "%d-%d", time.year, time.month);
  }
  USB.print("File Name: ");
  USB.println(filename);
  sd_answer = SD.goRoot();
  if (sd_answer == 1)
  {
    USB.println("Got root directory");
  }
  else
  {
    // Changing to the root directory failed
    USB.println("Failed to get root directory");
    SD.OFF();
    return SD.flag;
  }
  //
  // Check if the file exists
  sd_answer = SD.isFile(filename);
  if (sd_answer == 1)
  {
    USB.println("File exists");    
  }
  else
  {
    USB.println("File does not exist");
    //
    // The file doesn't exist, so create it.
    sd_answer = SD.create(filename);
    if (sd_answer == 1)
    {
      USB.println("File created");
    }
    else
    {
      // file creation failed, return 4
      USB.println("File creation failed");
      SD.OFF();
     return SD.flag;
    }
  }
  //
  // If we've got this far, either the file
  // already existed, or we've just succesfully
  // created it.
  sd_answer = SD.append(filename, file_data, 20);
  if (sd_answer == 1)
  {
    USB.println("File append 1 succeded");
  }
  else
  {
    // append to file failed, return 5
    USB.println("File append 1 failed");
    SD.OFF();
    return SD.flag;
  }
  sd_answer = SD.append(filename, ", ", 2);
  if (sd_answer == 1)
  {
    USB.println("File append 2 succeded");
  }
  else
  {
    // append to file failed, return 5
    USB.println("File append 2 failed");
    SD.OFF();
    return SD.flag;
  }
  sd_answer = SD.appendln(filename, convert);
  if (sd_answer == 1)
  {
    USB.println ("File append 3 succeded");
  }
  else
  {
    // append to file failed, return 5
    USB.println("File append 3 failed");
    SD.OFF();
    return SD.flag;
  }
  // Write succeeded, return 0
  USB.println("File appends all succeeded");
  SD.OFF();
  return SD.flag;
  //return 0;
}



void setup()
{
  RTC.ON();
  RTC.setWatchdog(10);
  RTC.OFF();
  // put your setup code here, to run once:

  // Perform LoRaWAN OTAA join
  joinOTAA();
  
  frame.setID(moteID);
}



void loop()
{
  // put your main code here, to run repeatedly:

  //
  // Check the current time, if it's been more than a 4 weeks resync with the GPS.
  RTC.ON();
  sample_time = RTC.getEpochTime();
 // Break Epoch time into UTC time
  RTC.breakTimeAbsolute( sample_time, &time );
  RTC.OFF();
 

  //
  // Read the sensor
  readSensor();
  //
  // Write the sensor reading to the SD card
  sd_error = writeDataToFile ();
  //
  // Build the frame to send
  buildFrame();
  //
  // Send the frame over LoRaWAN
  sendFrame();
  switch (error)
  {
   case 5:
     // Sending failed, try once more
     sendFrame();
     break;
   case 6:
     // Module not joined, try to join again, then resend the data
     joinOTAA();
     sendFrame();
     break;
   default:
     // Carry on if it succeded or the problem was data length or the module not working
     // if the module is not working there's not much we can do about it other than store
     // the data locally.
     break;
  }
  //
  // Set the interrrupt alarm for 10 minutes, divide the
  // current minutes past the hour by 10 to get the number
  // of tens of minutes past the hour, then set the alarm
  // to the next 10 minute. This should result in waking
  // up every 10 minutes without needing to account for the
  // time the code takes to run in each wakeup cycle.
  //  int ten_mins = time.minutes  / 10;
  //
  // Clear the watchdog before resetting it.
  RTC.unSetWatchdog();
  switch (time.minute / 10)
    {
    case 0: // Set alarm for 10 past the hour
      
      //
      // Check if the RTC needs syncronising. Putting this check here
      // means this is only attempted once per hour, limiting the
      // drain from the battery if GPS is failing.
      //
      // If it's been more than 4 weeks since the last syncronisation,
      // then syncronise the clock to the GPS.
      if (sample_time > (time_sync +  2419200))
      {
        RTC.ON();
        RTC.setWatchdog(6);
        RTC.OFF();
        setTime();
        //
        // We need to check if the GPS time sync has taken us beyond the next wakeup time,
        // otherwise it won't wake up again for another hour. This only happens if we first turn on
        // the waspmote between the hour and 10 past.
        RTC.ON();
        RTC.unSetWatchdog();
        sample_time = RTC.getEpochTime();
        RTC.OFF();
        RTC.breakTimeAbsolute( sample_time, &time );       
        if (time.minute >= 10)
        {
          RTC.setAlarm1("00:00:20:00",RTC_ABSOLUTE,RTC_ALM1_MODE4);
          RTC.setAlarm2("00:00:23",RTC_ABSOLUTE,RTC_ALM1_MODE4);
        }
        else
        {
          //
          // If we haven't updated the time then set the alarm for 10 past.
          RTC.setAlarm1("00:00:10:00",RTC_ABSOLUTE,RTC_ALM1_MODE4);
          RTC.setAlarm2("00:00:13",RTC_ABSOLUTE,RTC_ALM1_MODE4);
        }
      }
      else
      {
        RTC.setAlarm1("00:00:10:00",RTC_ABSOLUTE,RTC_ALM1_MODE4);
        RTC.setAlarm2("00:00:13",RTC_ABSOLUTE,RTC_ALM1_MODE4);
      }
      break;
  
    case 1: // Set alarm for 20 past the hour
      RTC.setAlarm1("00:00:20:00",RTC_ABSOLUTE,RTC_ALM1_MODE4);
      RTC.setAlarm2("00:00:23",RTC_ABSOLUTE,RTC_ALM1_MODE4);
      break;

    case 2: // Set alarm for half past the hour
      RTC.setAlarm1("00:00:30:00",RTC_ABSOLUTE,RTC_ALM1_MODE4);
      RTC.setAlarm2("00:00:33",RTC_ABSOLUTE,RTC_ALM1_MODE4);
      break;
      
    case 3: // Set alarm for 20 to the hour
      RTC.setAlarm1("00:00:40:00",RTC_ABSOLUTE,RTC_ALM1_MODE4);
      RTC.setAlarm2("00:00:43",RTC_ABSOLUTE,RTC_ALM1_MODE4);
      break;

    case 4: // Set alarm to 10 to the hour
      RTC.setAlarm1("00:00:50:00",RTC_ABSOLUTE,RTC_ALM1_MODE4);
      RTC.setAlarm2("00:00:53",RTC_ABSOLUTE,RTC_ALM1_MODE4);
      break;

    case 5: // set alarm for the hour
      RTC.setAlarm1("00:00:00:00",RTC_ABSOLUTE,RTC_ALM1_MODE4);
      RTC.setAlarm2("00:00:03",RTC_ABSOLUTE,RTC_ALM1_MODE4);
      break;

    default: // this should never happen... set alarm for 10 minutes
      RTC.setAlarm1("00:00:10:00",RTC_OFFSET,RTC_ALM1_MODE2);
      RTC.setAlarm2("00:00:23",RTC_ABSOLUTE,RTC_ALM1_MODE2);
      break;
    }
  //
  // Put Waspmote to sleep.
  USB.print("Going to sleep until: ");
  USB.println(RTC.getAlarm1());
  PWR.sleep(ALL_OFF);
  if( intFlag & RTC_INT )
  {
    intFlag &= ~(RTC_INT); // Clear flag
    Utils.blinkGreenLED(500);
  } 
}
