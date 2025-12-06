#include <Wire.h> // I2C communication
// SpO2 and BPM libraries
#include <MAX30105.h>
#include <spo2_algorithm.h>
#include <math.h> // Math functions
#include <Adafruit_GFX.h> // OLED
#include <Adafruit_SSD1306.h> // OLED
#include <WiFi.h> //WiFi station
// libraries to implement esp-now
#include <esp_wifi.h>
#include <esp_now.h>

#define DEBUG
// #define DEBUGGING

// Receiver MAC Address
uint8_t broadcastAddress[] = {0xa0, 0xb7, 0x65, 0x25, 0x78, 0x9c};


// Devices' addresses
const int MPU   = 0x68; // MAX-30102
const int OLED  = 0x3C;

// Display sizes
const int SCREEN_WIDTH  = 128;
const int SCREEN_HEIGHT = 64; 

// Measurements
int16_t AcX, AcY, AcZ, Tmp, GyX, GyY, GyZ; // MPU-6050

// Calibration offset for MPU-6050
static int AcXcal = 0;
static int AcYcal = 0;
static int AcZcal = 0;



// Various variables and containers
uint32_t ir_samples[100];
uint32_t red_samples[100];
int8_t spo2Valid, hrValid;
const int SENSITIVITY = 16384; // LSB/g for ±2g FS (change if you set different FS)
int i = 0;

// Caluculated variables
int32_t spo2, heartRate; // MAX-30102


// Timing variables
const int DELAY = 6000;
unsigned long start;

// Display initialization
Adafruit_SSD1306 display(SCREEN_WIDTH, SCREEN_HEIGHT, &Wire, -1);

// MAX-30102 object
MAX30105 particleSensor;

// Data to send
struct package {
  uint32_t spo2;
  uint32_t heartRate;
  int16_t AcX;
  int16_t AcY; 
  int16_t AcZ; 
};
package data;

esp_now_peer_info_t peerInfo; // esp-now

void setup() {
  // put your setup code here, to run once:
  Serial.begin(9600);// Serial for debugging

  // Set device as a Wi-Fi Station
  WiFi.mode(WIFI_STA);

  // Init ESP-NOW
  if (esp_now_init() != ESP_OK) {
    Serial.println("Error initializing ESP-NOW");
    return;
  }
  
  // Once ESPNow is successfully Init, we will register for Send CB to
  // get the status of Trasnmitted packet
  esp_now_register_send_cb(esp_now_send_cb_t(onDataSent));

  // Register peer
  memcpy(peerInfo.peer_addr, broadcastAddress, 6);
  peerInfo.channel = 0;
  peerInfo.encrypt = false;

  // Add peer
  if (esp_now_add_peer(&peerInfo) != ESP_OK) {
    Serial.println("Failed to add peer");
    return;
  }

  Wire.begin(); // I2C set up

  //Display set up
  display.begin(SSD1306_SWITCHCAPVCC, OLED);
  display.clearDisplay();
  display.setTextSize(2); // value to be adjusted.
  display.setTextColor(WHITE);
  display.setCursor(30, 0);
  display.println("Vitals");
  display.display();

  // MPU-6050 wake up
  Wire.beginTransmission(MPU);
  Wire.write(0x6B);
  Wire.write(0);
  Wire.endTransmission(true);
  accel_calibrate(); // acceleration calibration

  // MAX-30102 initialization
  if(!particleSensor.begin(Wire, I2C_SPEED_FAST)) {
#ifdef DEBUGGING
    Serial.println("MAX-30102 not found. Check wiring!");
    WiFi.STA.begin();
#endif //DEBUGGING
    display.clearDisplay();
    display.setCursor(0, 16);
    display.print("NO DEVICE DETECTED");
    display.display();
    display.startscrollright(0, 16);
    while(1);
  }
  particleSensor.setup();
  particleSensor.setPulseAmplitudeRed(0x1F); // Red LED brightness
  particleSensor.setPulseAmplitudeIR(0x1F); // IR LED brightness

  // Display initialization
  displayReset();
  display.setCursor(0, 16);
  display.println("HR");
  display.setCursor(80, 16);
  display.println("SpO2");
  display.display();

  //Timing initialization
  start = millis();
}

void loop() {
  if (millis() - start < 500) {
    max_reader();
    displayText();
  }
  else
    if (millis() - start < 1000) {
      mpu_reader(AcX, AcY, AcZ, Tmp, GyX, GyY, GyZ);      
      sending_package();
    }
    else
      start = millis();
}

// Callback when data is sent
void onDataSent(const uint8_t* mac_addr, esp_now_send_status_t status) {
  Serial.print("\r\nLast Packet Send Status:\t");
  Serial.println(status == ESP_NOW_SEND_SUCCESS ? "Delivery Success" : "Delivery Fail");
}

// Sending info package
void sending_package() {
  // Setting values to send
  data.spo2 = spo2;
  data.heartRate = heartRate;
  data.AcX = AcX + AcXcal / SENSITIVITY;;
  data.AcY = AcY + AcYcal / SENSITIVITY;;
  data.AcZ = AcZ + AcZcal / SENSITIVITY;;

  // Send message via esp-now
  esp_err_t result = esp_now_send(broadcastAddress, (uint8_t*) &data, sizeof(data));

#ifdef DEBUG
  if (result == ESP_OK)
    Serial.println("Sent with success");
  else
    Serial.println("Error sending the data");
#endif //DEBUG
}

// Function to read from MPU-6050
void mpu_reader(int16_t& AcX, int16_t& AcY, int16_t& AcZ, int16_t& Tmp, 
                int16_t& GyX, int16_t& GyY, int16_t& GyZ) {
  Wire.beginTransmission(MPU);
  Wire.write(0x3B);
  Wire.endTransmission(false);
  // Request 14 bytes:
  // ACCEL_X, ACCEL_Y, ACCEL_Z (6 bytes)
  // TEMP (2 bytes)
  // GYRO_X, GYRO_Y, GYRO_Z (6 bytes)
  Wire.requestFrom(MPU, 14, true);

  // Read accelerometer values (high byte << 8 | low byte)
  AcX = Wire.read() << 8 | Wire.read();
  AcY = Wire.read() << 8 | Wire.read();
  AcZ = Wire.read() << 8 | Wire.read();

  // Read temperature
  Tmp = Wire.read() << 8 | Wire.read();

  // Read gyroscope values
  GyX = Wire.read() << 8 | Wire.read();
  GyY = Wire.read() << 8 | Wire.read();
  GyZ = Wire.read() << 8 | Wire.read();

  Wire.endTransmission(true); // ends transmission after a read

  // Printing values stored
#ifdef DEBUGGING
  Serial.println(AcX);
  Serial.println(AcY);
  Serial.println(AcZ);
  Serial.println(Tmp);
  Serial.println(GyX);
  Serial.println(GyY);
  Serial.println(GyZ);
#endif //DEBUGGING
}

// Function to read from MAX-30102
void max_reader() {
  for(int i = 0; i < 100; i++) {
    while (!particleSensor.available()) {
      particleSensor.check();
    }
    red_samples[i]  = particleSensor.getRed();
    ir_samples[i]   = particleSensor.getIR();

    particleSensor.nextSample(); // Move to next FIFO sample
  }

  maxim_heart_rate_and_oxygen_saturation(
    ir_samples,
    100,
    red_samples,
    &spo2,
    &spo2Valid,
    &heartRate,
    &hrValid
  );
#ifdef DEBUGGING
    if (hrValid) {
      Serial.print("Heart Rate: ");
      Serial.print(heartRate);
      Serial.println(" BPM");
    } else {
      Serial.println("Heart Rate not valid.");
    }

    if (spo2Valid) {
      Serial.print("SpO2: ");
      Serial.print(spo2);
      Serial.println(" %");
    } else {
      Serial.println("SpO2 not valid.");
    }

    delay(1000);
#endif //DEBUGGING
}

// Accelerometer calibration value
void accel_calibrate() {
  long sx = 0, sy = 0, sz = 0;
  for (int i = 0; i < 200; i++) {
    mpu_reader(AcX, AcY, AcZ, Tmp, GyX, GyY, GyZ);
    sx += AcX;
    sy += AcY;
    sz += AcZ;
  }
  AcXcal = - (sx / 200);
  AcYcal = - (sy / 200);
  AcZcal = sz / 200;
}

void displayText() { // display of the vitals values
  displayReset();
  display.setCursor(0, 16);
  display.println("HR");
  display.setCursor(80, 16);
  display.println("SpO2");
  display.display();

  if (hrValid) {
    display.setCursor(0, 32);
    display.println(heartRate); // Heart rate
  }
  else {
    display.setCursor(0, 32);
    display.println("N/A");
  }
  if (spo2Valid) {
    display.setCursor(80, 32);
    display.print(spo2); // SpO2
    display.println("%");
  }
  else {
    display.setCursor(80, 32);
    display.println("N/A");
  }
  display.display();
}

void displayReset() {
  display.clearDisplay();
  display.setTextSize(2); // value to be adjusted.
  display.setTextColor(WHITE);
  display.setCursor(30, 0);
  display.println("Vitals");
}

#ifdef DEBUGGING
void readMacAddress() {
  uint8_t baseMac[6];
  esp_err_t ret = esp_wifi_get_mac(WIFI_IF_STA, baseMac);
  if (ret == ESP_OK) {
    Serial.printf("%02x:%02x:%02x:%02x:%02x:%02x\n",
                  baseMac[0], baseMac[1], baseMac[2],
                  baseMac[3], baseMac[4], baseMac[5]);
  }
  else
    Serial.println("Failed to read MAC address");
}
#endif //DEBUGGING
