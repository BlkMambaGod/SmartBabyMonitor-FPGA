#include <WiFi.h>
#include <esp_wifi.h>
#include <esp_now.h>

#define DEBUG
// #define DEBUGGING

// Data received via esp-now
struct package {
  uint32_t spo2;
  uint32_t heartRate;
  int16_t AcX;
  int16_t AcY; 
  int16_t AcZ; 
};

package data;


uint8_t msg = 0;
unsigned long start;

void setup() {
  // put your setup code here, to run once:
  // Initialize Serial Monitor
  Serial.begin(115200);
  Serial2.begin(115200, SERIAL_8N1, RX, TX);

  // Set device as a Wi-Fi Station
  WiFi.mode(WIFI_STA);
#ifdef DEBUGGING
  WiFi.STA.begin();
#endif //DEBUGGING

  // Init ESP-NOW
  if (esp_now_init() != ESP_OK) {
    Serial.println("Error initializing ESP-NOW");
    return;
  }

  // Once ESPNow is successfully Init, we will register for recv CB to
  // get recv packer info
  esp_now_register_recv_cb(esp_now_recv_cb_t(onDataRecv));

  start = millis();
}

void loop() {
  // put your main code here, to run repeatedly:
#ifdef DEBUGGING
  Serial.println("This works!");
  Serial.print("[RECEIVER] ESP32 Board MAC Address: ");
  readMacAddress();
  delay(1000);
#endif //DEBUGGING
  if (millis() - start > 500) {
    computing();
    Serial2.write(msg); // UART transmitter comm
    start = millis();
  }
}

// callback function that will be executed when data is received
void onDataRecv(const uint8_t* mac, const uint8_t* incomingData, int len) {
  memcpy(&data, incomingData, sizeof(data));
  Serial.print("Bytes received: ");
  Serial.println(len);
  Serial.print("SpO2: ");
  Serial.println(data.spo2);
  Serial.print("Heart rate: ");
  Serial.println(data.heartRate);
  Serial.print("AcX: ");
  Serial.println(data.AcX);
  Serial.print("AcY: ");
  Serial.println(data.AcY);
  Serial.print("AcZ: ");
  Serial.println(data.AcZ);
  Serial.println();
}

// Decision making
void computing() {
  if ((data.heartRate < 60) || (data.heartRate > 130) && (data.spo2 >= 75) && (data.spo2 <= 100))
    msg = 2;
  else
    if ((data.heartRate < 60) || (data.heartRate > 130) && (data.spo2 < 75) || (data.spo2 > 100))
      msg = 3;
    else
      if ((data.heartRate >= 60) && (data.heartRate <= 130) && (data.spo2 < 75))
        msg = 1;
      else
        msg = 0;
// #ifdef DEBUG
  Serial.print("msg = ");
  Serial.println(msg);
// #endif // DEBUG
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
#endif // DEBUGGING
