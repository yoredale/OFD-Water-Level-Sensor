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

// Define GPS Timeout
#define GPS_TIMEOUT 240

//////////////////////////////////////////////
uint8_t socket = SOCKET0;
//////////////////////////////////////////////

// Device parameters for Back-End registration
////////////////////////////////////////////////////////////
char DEVICE_EUI[]  = "3b3940c71a6bdc59";
char APP_EUI[] = "7268cd245c2ea59f";
char APP_KEY[] = "1f3905f11c8c295ece8777dc8bba9eac";
////////////////////////////////////////////////////////////

// Define port to use in Back-End: from 1 to 223
uint8_t PORT = 3;

// variable
uint8_t error;
uint8_t error_config = 0;
uint8_t error_code = 0;

timestamp_t   time;
unsigned long time_sync;
unsigned long sample_time;
uint16_t sensor_value;
float current;
char moteID[] = "OFD1";
char sensor_message[8];
char data[17];




// This uses the GPS to set the RTC and record the time it happened

bool setTime()
{
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
    // Turn RTC off again.
    RTC.OFF();
    return true;
  }
  else
  { 
    return false;
  }
}

//
// Read the sensor value from the 4-20mA board and store it
// in sensor_value

void readSensor()
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
    current = currentLoopBoard.readCurrent(CHANNEL1);
    current = current;
    delay(100);
  }
  else
  {
    sensor_value = -1;
    current = -1;
  }
  USB.println(current);
  USB.println(sensor_value);
  //
  // Sets the 12V switch OFF
  currentLoopBoard.OFF(SUPPLY12V);
  delay(100);

  // Turn off the 4-20mA board
  currentLoopBoard.OFF(SUPPLY5V);
  delay(100);
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
  // Waspmote doesn't define a generic INT sensor value or a value
  // for the 4 to 20 mA sensor. I can't be bothered to define a new sensor type
  // so we'll use SENSOR_RAM, which is 2 byte INT sensor type with ID 61
  // 
  frame.addSensor(SENSOR_RAM, (sensor_value) );
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


void setup()
{
  // put your setup code here, to run once:

  //
  // Set the time from the GPS.
//  bool time_set = false;
//  while (!time_set)
//  {
//    time_set = setTime();
//  }

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
  frame.setID(moteID);
}


int writeDataToFile ()
{
  char data[26];
  char convert[5];
  // Break Epoch time into UTC time
  RTC.breakTimeAbsolute( sample_time, &time );
  sprintf(convert, "%d", time.year);
  strcat(data, convert);
  strcat(data, "-");
  sprintf(convert, "%d", time.month);
  strcat(data, convert);
  strcat(data, "-");
  sprintf(convert, "%d", time.date);
  strcat(data, convert);
  strcat(data, " ");
  sprintf(convert, "%d", time.hour);
  strcat(data, convert);
  strcat(data, ":"),
  sprintf(convert, "%d", time.minute);
  strcat(data, convert);
  strcat(data, ":");
  sprintf(convert, "%d", time.second);
  strcat(data, convert);
  strcat(data, ", ");
  sprintf(convert, "%d", sensor_value);
  strcat(data, convert);
  // Turn on the SD card
  SD.ON();
  int err = 0;
  char path[8];
  sprintf(path, "%d", time.year);
  char filename[3];
  sprintf(filename, "%d", time.month);
  if (SD.goRoot())
  {
    if (!SD.isDir(path))
    {
      err = err + SD.mkdir(path);
    }
    strcat(path, "/");
    strcat(path,filename);
    if (!SD.isFile(path)) 
    {
      err = err + SD.create(path);
    }
    err = err + SD.appendln(path, data);
  }
  else
  {
    return 1;
  }
  return err;
}

void loop()
{
  // put your main code here, to run repeatedly:

  //
  // Check the current time, if it's been more than a week resync with the GPS.
  RTC.ON();
  sample_time = RTC.getEpochTime();
  //
  // Set the interrrupt alarm for 10 minutes
  RTC.setAlarm1("00:00:10:00",RTC_OFFSET,RTC_ALM1_MODE2);
  RTC.OFF();
//  if (sample_time > (time_sync + 604800))
//  {
//    bool time_set = false;
//    while (!time_set)
//    {
//      time_set = setTime();
//    }
//    RTC.ON();
//    sample_time = RTC.getEpochTime();
//    RTC.OFF();
//  }
  //
  // Read the sensor
  readSensor();
  //
  // Build the frame to send
  buildFrame();
  //
  // Write the sensor reading to the SD card
  writeDataToFile ();
  //
  // Send the frame over LoRaWAN
  sendFrame();
  //
  // Put Waspmote to sleep.
  PWR.sleep(ALL_OFF);
  if( intFlag & RTC_INT )
  {
    intFlag &= ~(RTC_INT); // Clear flag
    Utils.blinkLEDs(1000); // Blinking LEDs
    Utils.blinkLEDs(1000); // Blinking LEDs
  } 
}
