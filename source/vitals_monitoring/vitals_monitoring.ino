#include <Wire.h> // I2C communication
// SpO2 and BPM libraries
#include <MAX30105.h>
#include <spo2_algorithm.h>
#include <math.h> // Math functions
#include <Adafruit_GFX.h> // OLED
#include <Adafruit_SSD1306.h> // OLED

#define DEBUGGING

// Devices' addresses
const int MPU   = 0x68; // MAX-30102
const int OLED  = 0x3C;

// Display sizes
const int SCREEN_WIDTH  = 128;
const int SCREEN_HEIGHT = 64; 

// Measurements
int16_t AcX, AcY, AcZ, Tmp, GyX, GyY, GyZ; // MPU-6050

// Calibration offset for MPU-6050
const int AcXcal = -950;
const int AcYcal = -300;
const int AcZcal = 0;
const int tcal   = -1600;
const int GyXcal = 480;
const int GyYcal = 170;
const int GyZcal = 210;

// Various variables and containers
uint32_t ir_samples[100];
uint32_t red_samples[100];
int8_t spo2Valid, hrValid;
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

void setup() {
  // put your setup code here, to run once:
  Serial.begin(9600);// Serial for debugging
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

  // MAX-30102 initialization
  if(!particleSensor.begin(Wire, I2C_SPEED_FAST)) {
#ifdef DEBUGGING
    Serial.println("MAX-30102 not found. Check wiring!");
#endif //DEBUGGING
    display.setCursor(0, 16);
    display.print("NO DEVICE DETECTED");
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
  // put your main code here, to run repeatedly:
  // if (millis() - start < DELAY / 2)
  //   max_reader(ir, red);
  // else
  //   if (millis() - start < DELAY)
  //     mpu_reader(AcX, AcY, AcZ, Tmp, GyX, GyY, GyZ);
  
#ifdef DEBUGGING
  max_reader();
  // mpu_reader(AcX, AcY, AcZ, Tmp, GyX, GyY, GyZ);
  delay(1000);
  // display.startscrollright(0, 7);
  displayText();
#endif // DEBUGGING
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
  Serial.println(AcX);
  Serial.println(AcY);
  Serial.println(AcZ);
  Serial.println(Tmp);
  Serial.println(GyX);
  Serial.println(GyY);
  Serial.println(GyZ);
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

// Calculation real values
void max_values() {

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
