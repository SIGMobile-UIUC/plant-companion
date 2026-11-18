// XIAO ESP32-C3 diagnostic sketch. Targets Espressif Arduino core 3.x.
// Libraries: Adafruit SHT4x, Adafruit VEML7700 (install dependencies).
// SDA=D4/GPIO6, SCL=D5/GPIO7, soil=D1/GPIO3 via two 10k resistors.
// Custom BLE diagnostic service; not an implementation of the app protocol.
#include <Arduino.h>
#include <Wire.h>
#include <Adafruit_SHT4x.h>
#include <Adafruit_VEML7700.h>
#include <BLEDevice.h>
#include <BLEServer.h>
#include <BLEUtils.h>
#include <BLE2902.h>
#include <atomic>
#include <math.h>

constexpr int SOIL_PIN = 3; // GPIO3 = D1, NOT GPIO1
constexpr int SDA_PIN = 6;  // GPIO6 = D4
constexpr int SCL_PIN = 7;  // GPIO7 = D5
constexpr float SOIL_DIVIDER = 2.0f; // two equal 10k resistors
const char *SERVICE_UUID = "7b410000-6a5d-4d78-9f62-173a34b04001";
Adafruit_SHT4x sht;
Adafruit_VEML7700 light;
BLEServer *server;
BLECharacteristic *tempChar, *humidityChar, *luxChar, *soilChar;
std::atomic<bool> restartAdvertising{false};
bool shtReady = false, lightReady = false;

class ServerCallbacks : public BLEServerCallbacks {
  void onDisconnect(BLEServer *) override {
    restartAdvertising.store(true);
  }
};

bool responds(uint8_t address) {
  Wire.beginTransmission(address);
  return Wire.endTransmission() == 0;
}

BLECharacteristic *makeCharacteristic(BLEService *service, const char *uuid) {
  auto *c = service->createCharacteristic(uuid,
      BLECharacteristic::PROPERTY_READ | BLECharacteristic::PROPERTY_NOTIFY);
  c->addDescriptor(new BLE2902());
  c->setValue("WAIT");
  return c;
}

// Each ASCII value fits the default BLE 20-byte notification payload.
void publish(BLECharacteristic *c, const char *label, float value, int decimals) {
  char text[21];
  if (isfinite(value)) snprintf(text, sizeof(text), "%s=%.*f", label, decimals, value);
  else snprintf(text, sizeof(text), "%s=ERR", label);
  c->setValue(text);
  if (server->getConnectedCount() > 0) c->notify();
}

void setup() {
  Serial.begin(115200);
  // Bounded wait: battery-only boot must work without a USB host.
  unsigned long start = millis();
  while (!Serial && millis() - start < 2500) delay(10);
  Serial.println("\nPlant Companion: sensors + BLE test");
  Wire.begin(SDA_PIN, SCL_PIN);
  Wire.setClock(100000);
  Wire.setTimeOut(50);
  Serial.println("I2C scan: expect 0x10 (light), 0x44 (temperature/humidity)");
  for (uint8_t address = 1; address < 127; ++address) {
    if (responds(address)) Serial.printf("  Found 0x%02X\n", address);
  }
  analogReadResolution(12);
  analogSetPinAttenuation(SOIL_PIN, ADC_11db);
  pinMode(SOIL_PIN, INPUT);

  BLEDevice::init("PlantComp-Test");
  server = BLEDevice::createServer();
  server->setCallbacks(new ServerCallbacks());
  auto *service = server->createService(SERVICE_UUID);
  tempChar = makeCharacteristic(service, "7b410001-6a5d-4d78-9f62-173a34b04001");
  humidityChar = makeCharacteristic(service, "7b410002-6a5d-4d78-9f62-173a34b04001");
  luxChar = makeCharacteristic(service, "7b410003-6a5d-4d78-9f62-173a34b04001");
  soilChar = makeCharacteristic(service, "7b410004-6a5d-4d78-9f62-173a34b04001");
  service->start();
  auto *advertising = BLEDevice::getAdvertising();
  advertising->addServiceUUID(SERVICE_UUID);
  advertising->setScanResponse(true);
  advertising->start();
  Serial.println("BLE advertising: PlantComp-Test");
}

void loop() {
  if (restartAdvertising.exchange(false)) {
    delay(100);
    BLEDevice::startAdvertising();
    Serial.println("BLE disconnected; advertising restarted");
  }
  static unsigned long lastSample = 0;
  if (millis() - lastSample < 2000) { delay(10); return; }
  lastSample = millis();

  // Failed or missing I2C sensors do not stop soil measurements or BLE.
  if (!responds(0x44)) shtReady = false;
  if (!shtReady && responds(0x44)) {
    shtReady = sht.begin(&Wire);
    if (shtReady) {
      sht.setPrecision(SHT4X_HIGH_PRECISION);
      sht.setHeater(SHT4X_NO_HEATER);
    }
  }
  if (!responds(0x10)) lightReady = false;
  if (!lightReady && responds(0x10)) {
    lightReady = light.begin(&Wire);
    if (lightReady) {
      light.setGain(VEML7700_GAIN_1_8);
      light.setIntegrationTime(VEML7700_IT_100MS);
      delay(150);
    }
  }
  float tempC = NAN, humidity = NAN, lux = NAN;
  if (shtReady) {
    sensors_event_t h, t;
    if (sht.getEvent(&h, &t)) { tempC = t.temperature; humidity = h.relative_humidity; }
    else shtReady = false;
  }
  if (lightReady) lux = light.readLux();

  uint32_t sum = 0;
  for (int i = 0; i < 32; ++i) { sum += analogReadMilliVolts(SOIL_PIN); delay(2); }
  float adcMv = sum / 32.0f;
  float sensorMv = adcMv * SOIL_DIVIDER;
  Serial.printf("\nBLE: %s\n", server->getConnectedCount() ? "CONNECTED" : "advertising");
  if (isfinite(tempC)) Serial.printf("SHT40: %.2f C / %.2f F | humidity %.1f %%\n", tempC, tempC * 1.8f + 32, humidity);
  else Serial.println("SHT40: ERROR / missing (check power, SDA, SCL)");
  if (isfinite(lux)) Serial.printf("Light: %.1f lux\n", lux);
  else Serial.println("VEML7700: ERROR / missing (check power, SDA, SCL)");
  Serial.printf("Soil: D1 %.0f mV | estimated sensor output %.0f mV\n", adcMv, sensorMv);
  if (adcMv < 20) Serial.println("Soil near zero: check sensor power/signal; unplugged probe also reads near zero.");
  if (adcMv > 2400) Serial.println("ADC near limit: check divider and wiring.");
  publish(tempChar, "T_C", tempC, 2);
  publish(humidityChar, "RH_pct", humidity, 1);
  publish(luxChar, "Lux", lux, 1);
  publish(soilChar, "Soil_mV", sensorMv, 0);
}
