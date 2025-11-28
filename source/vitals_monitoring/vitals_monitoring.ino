#include <Wire.h> // I2C communication
#include <math.h> // Math functions
#include <Adafruit_GFX.h> // OLED
#include <Adafruit_SSD1306.h> // OLED

// Devices' addresses
const int MPU   = 0x68; // MPU-6050
const int MAX   = 0x57; // MAX-30102
const int OLED  = 0x3C;

// Display sizes
const int SCREEN_WIDTH  = 128;
const int SCREEN_HEIGHT = 64; 

// Measurements
int16_t AcX, AcY, AcZ, Tmp, GyX, GyY, GyZ; // MPU-6050
uint32_t ir, red; // MAX-30102 

// Calibration offset for MPU-6050
const int AcXcal = -950;
const int AcYcal = -300;
const int AcZcal = 0;
const int tcal   = -1600;
const int GyXcal = 480;
const int GyYcal = 170;
const int GyZcal = 210;

// Timing variables
const int DELAY = 6000;
unsigned long start;

// Display initialization
Adafruit_SSD1306 display(SCREEN_WIDTH, SCREEN_HEIGHT, &Wire, -1);

void setup() {
  // put your setup code here, to run once:
  Wire.begin(); // I2C set up

  // MPU-6050 wake up
  Wire.beginTransmission(MPU);
  Wire.write(0x6B);
  Wire.write(0);
  Wire.endTransmission(true);

  // MAX-30102 wake up
  Wire.beginTransmission(MAX);
  Wire.write(0x09);
  Wire.write(0x03); // SpO2 mode that output both SpO2 and HR
  Wire.endTransmission(true);
  
  //Display set up
  display.begin(SSD1306_SWITCHCAPVCC, OLED);
  display.clearDisplay();
  display.setTextSize(2); // value to be adjusted.
  display.setTextColor(WHITE);
  display.setCursor(10, 10);
  display.println("Subscribe");
  display.display();

  //Timing initialization
  start = millis();

  // Serial for debugging
  Serial.begin(9600);
}

void loop() {
  // put your main code here, to run repeatedly:
  if (millis() - start < DELAY / 2)
    max_reader(ir, red);
  else
    if (millis() - start < DELAY)
      mpu_reader(AcX, AcY, AcZ, Tmp, GyX, GyY, GyZ);
  
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
}

// Function to read from MAX-30102
void max_reader(uint32_t& ir, uint32_t& red) {
  Wire.beginTransmission(MAX);
  Wire.write(0x07); // FIFO register
  Wire.endTransmission(false);

  Wire.requestFrom(MAX, 6, true);
  ir  = Wire.read() << 16 | Wire.read() << 8 | Wire.read();
  red = Wire.read() << 16 | Wire.read() << 8 | Wire.read();

  ir  &= 0x3FFFF;
  red &= 0x3FFFF;
}
