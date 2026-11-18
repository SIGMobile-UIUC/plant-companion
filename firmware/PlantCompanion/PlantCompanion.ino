// Production XIAO ESP32-C3 firmware. Wire protocol: docs/ble-protocol.md.
// No sleep, battery measurement, power-switch control or physical sync button.
#include <Arduino.h>
#include <Wire.h>
#include <Adafruit_SHT4x.h>
#include <Adafruit_VEML7700.h>
#include <BLEDevice.h>
#include <BLEServer.h>
#include <BLEUtils.h>
#include <LittleFS.h>
#include <Preferences.h>
#include <esp_timer.h>
#include <atomic>
#include "pc_core.h"
struct Soil {float mv;uint8_t rails;};
Soil readSoil(); // Explicit prototype avoids Arduino's generated type ordering.

constexpr int SOIL_PIN=3,SDA_PIN=6,SCL_PIN=7;
constexpr const char* SERVICE="d1a10000-7c2f-4a9d-a6b4-36b51743c301";
constexpr const char* INFO="d1a10001-7c2f-4a9d-a6b4-36b51743c301";
constexpr const char* CONTROL="d1a10002-7c2f-4a9d-a6b4-36b51743c301";
constexpr const char* DATA="d1a10003-7c2f-4a9d-a6b4-36b51743c301";
Preferences prefs;
Adafruit_SHT4x sht;
Adafruit_VEML7700 lightSensor;
BLEServer* server=nullptr;
BLECharacteristic *infoChar=nullptr,*dataChar=nullptr;
std::atomic<bool> subscribed{false};
uint8_t hardwareId[6]{};
uint32_t streamId=0,bootId=0,lastAck=0;
bool storageReady=false,shtReady=false,lightReady=false,anchored=false,live=false;
int64_t utcOffset=0;
pc::Calibration calibration,pendingCalibration;
pc::Scheduler schedule;
pc::Record currentAnchor;
uint32_t lastManual=0;bool hadManual=false;
std::atomic<bool> restartAdvertising{false};
portMUX_TYPE queueMux=portMUX_INITIALIZER_UNLOCKED;
std::array<std::array<uint8_t,20>,4> controls{};
uint8_t queueRead=0,queueWrite=0,queueCount=0;
std::atomic<bool> malformedControl{false};

struct FlashStore:pc::BlockStore {
  File file;
  bool read(size_t offset,uint8_t* out,size_t n)override{return file && file.seek(16+offset) && file.read(out,n)==n;}
  bool write(size_t offset,const uint8_t* in,size_t n)override{return file && file.seek(16+offset) && file.write(in,n)==n;}
  bool flush()override{if(!file)return false;file.flush();return true;}
} flash;
pc::History<> history(flash);
struct Transfer {
  bool active=false;uint64_t token=0;uint8_t count=0,index=0,part=0,flags=0;
  uint32_t cursor=0,newest=0,nextSend=0;pc::Record records[pc::BATCH_LIMIT];
} transfer;

uint32_t uptime(){return uint32_t(esp_timer_get_time()/1000000LL);}
bool responds(uint8_t address){Wire.beginTransmission(address);return Wire.endTransmission()==0;}
void updateInfo(){
  if(!infoChar)return;uint8_t b[20]{};b[0]=pc::VERSION;
  b[1]=uint8_t(7 | (calibration.valid()?8:0) | (storageReady?0:16));
  memcpy(b+2,hardwareId,6);pc::put32(b+8,streamId);pc::put32(b+12,history.oldest());pc::put32(b+16,history.newest());infoChar->setValue(b,20);
}
void error(uint64_t token,pc::Error code,uint32_t detail=0){
  Serial.printf("PC ERROR code=%u detail=%lu\n",unsigned(code),(unsigned long)detail);
  if(!server || !server->getConnectedCount() || !subscribed.load())return;
  uint8_t b[20]{};b[0]=pc::VERSION;b[1]=3;pc::put64(b+2,token);b[10]=code;pc::put32(b+12,detail);dataChar->setValue(b,20);dataChar->notify();
}
bool openHistory(){
  bool mounted=LittleFS.begin(false);
  if(!mounted && !prefs.getBool("fsAttempted",false)){
    // Only the first installation may initialize an unformatted partition.
    // Mark this BEFORE formatting: subsequent mount failures never auto-erase.
    if(prefs.putBool("fsAttempted",true)!=1)return false;
    mounted=LittleFS.begin(true);
  }
  if(!mounted){Serial.println("PC STORAGE mount failed; retained flash is not auto-formatted");return false;}
  if(!prefs.getBool("fsAttempted",false))prefs.putBool("fsAttempted",true);
  uint8_t header[16]{};memcpy(header,"PC01",4);pc::put16(header+4,pc::CAPACITY);pc::put16(header+6,pc::RECORD_BYTES);pc::put32(header+8,streamId);pc::put32(header+12,pc::crc32(header,12));
  if(!LittleFS.exists("/history.bin")){
    File fresh=LittleFS.open("/history.bin","w");if(!fresh)return false;
    bool ok=fresh.write(header,16)==16;uint8_t zero[512]{};
    for(size_t left=pc::CAPACITY*pc::RECORD_BYTES;left && ok;){const auto n=std::min(left,sizeof(zero));ok=fresh.write(zero,n)==n;left-=n;}
    fresh.flush();fresh.close();if(!ok)return false;
  }
  flash.file=LittleFS.open("/history.bin","r+");uint8_t check[16]{};
  if(!flash.file || flash.file.size()!=16+pc::CAPACITY*pc::RECORD_BYTES || flash.file.read(check,16)!=16 || memcmp(check,header,16)!=0){Serial.println("PC STORAGE header mismatch; refusing to overwrite");return false;}
  return history.recover();
}
Soil readSoil(){uint32_t sum=0;uint8_t rails=0;for(int i=0;i<32;i++){const auto mv=analogReadMilliVolts(SOIL_PIN);sum+=mv;if(mv<20 || mv>2400)rails++;delay(2);}return {sum/32.f,rails};}
void probeSensors(){
  if(!responds(0x44))shtReady=false;
  if(!shtReady && responds(0x44)){shtReady=sht.begin(&Wire);if(shtReady){sht.setPrecision(SHT4X_HIGH_PRECISION);sht.setHeater(SHT4X_NO_HEATER);}}
  if(!responds(0x10))lightReady=false;
  if(!lightReady && responds(0x10)){lightReady=lightSensor.begin(&Wire);if(lightReady){lightSensor.setGain(VEML7700_GAIN_1_8);lightSensor.setIntegrationTime(VEML7700_IT_100MS);delay(150);}}
}
pc::Record measure(uint8_t kind,uint64_t token){
  probeSensors();pc::Record r;r.kind=kind;r.boot=bootId;r.uptime=uptime();r.request=token;
  if(anchored)r.utc=uint32_t(utcOffset+r.uptime);
  if(shtReady){sensors_event_t h{},t{};if(sht.getEvent(&h,&t)){
    if(isfinite(t.temperature) && t.temperature>=-40 && t.temperature<=125){r.temperature=int16_t(lroundf(t.temperature*100));r.valid|=2;}
    if(isfinite(h.relative_humidity) && h.relative_humidity>=0 && h.relative_humidity<=100){r.humidity=uint16_t(lroundf(h.relative_humidity*100));r.valid|=4;}
  }else shtReady=false;}
  // readLux()/readALS() return a numeric register value without an I2C error
  // result in VEML7700 2.1.6. Read ALS register 0x04 with checked byte count;
  // 0 is valid darkness, never a fabricated fallback for an I2C failure.
  if(lightReady){
    // Allow a full configured 100ms integration after the command/startup
    // path, so Refresh also observes a newly integrated light measurement.
    delay(110);Wire.beginTransmission(0x10);Wire.write(0x04);
    if(Wire.endTransmission(false)==0 && Wire.requestFrom(uint8_t(0x10),uint8_t(2))==2){
      const uint16_t raw=uint16_t(Wire.read()) | uint16_t(Wire.read())<<8;
      if(raw!=0xffff){r.milliLux=uint32_t(lroundf(raw*0.4608f*1000.f));r.valid|=8;}
      else Serial.println("PC VEML7700 saturated; lux unavailable");
    }else{lightReady=false;Serial.println("PC VEML7700 I2C read failed; lux unavailable");}
  }
  const auto soil=readSoil();r.adc=uint16_t(lroundf(soil.mv));if(calibration.valid())r.flags|=1;
  if(soil.rails>=24)r.flags|=2;
  if(soil.rails<24 && calibration.percent(soil.mv,r.moisture))r.valid|=1;
  return r;
}
void printRecord(const pc::Record& r,const char* source){
  Serial.printf("PC SAMPLE source=%s seq=%lu boot=%lu uptime=%lu utc=%lu valid=0x%02X BLE=%s\n",source,(unsigned long)r.sequence,(unsigned long)r.boot,(unsigned long)r.uptime,(unsigned long)r.utc,r.valid,server&&server->getConnectedCount()?"connected":"advertising");
  Serial.printf("SHT40 temperature=%s%.2fC humidity=%s%.2f%% | VEML7700 lux=%s%.3f\n",r.valid&2?"":"UNAVAILABLE ",r.temperature/100.f,r.valid&4?"":"UNAVAILABLE ",r.humidity/100.f,r.valid&8?"":"UNAVAILABLE ",r.milliLux/1000.f);
  Serial.printf("SOIL ADC=%u mV estimated_probe_output=%u mV (2x divider estimate ONLY), moisture=%s%.2f%% calibration=%s\n",r.adc,2u*r.adc,r.valid&1?"":"UNAVAILABLE ",r.moisture/100.f,calibration.valid()?"saved":"not calibrated");
  if(r.flags&2)Serial.println("PC SOIL rail warning: check power, D1 signal and existing two-10k soil divider");
  Serial.printf("PC SCHEDULE next_ms=%lu remaining_ms=%lu interval_ms=%lu\n",(unsigned long)schedule.next(),(unsigned long)(schedule.next()-millis()),(unsigned long)pc::INTERVAL_MS);
}
bool sample(uint8_t kind,uint64_t token,pc::Record& r){
  if(!storageReady)return false;r=measure(kind,token);
  if(!history.append(r)){storageReady=false;updateInfo();Serial.println("PC STORAGE commit failed; no fresh success published");return false;}
  updateInfo();printRecord(r,kind==pc::STARTUP?"startup":kind==pc::SCHEDULED?"scheduled":"manual");return true;
}
void startTransfer(uint64_t token,const pc::Record* records,uint8_t count,uint32_t cursor,bool gap){
  transfer={};transfer.active=true;transfer.token=token;transfer.count=count;transfer.cursor=cursor;transfer.newest=history.newest();
  transfer.flags=uint8_t((gap?1:0)|((count && records[count-1].sequence<history.newest())?2:0));
  for(uint8_t i=0;i<count;i++)transfer.records[i]=records[i];transfer.nextSend=millis();
}
void handle(const pc::Command& c){
  if(c.op==pc::ACK){lastAck=std::max(lastAck,std::min(c.a,history.newest()));Serial.printf("PC ACK cursor=%lu (advisory; records retained)\n",(unsigned long)lastAck);return;}
  if(transfer.active){error(c.token,pc::BUSY);return;}
  if(c.op==pc::HELLO){startTransfer(c.token,nullptr,0,c.a,false);return;}
  if(!storageReady){error(c.token,pc::STORAGE);return;}
  if(c.op==pc::HISTORY){pc::Record rows[pc::BATCH_LIMIT];bool gap=false;const auto n=history.batch(c.a,rows,std::min<uint32_t>(c.b?c.b:pc::BATCH_LIMIT,pc::BATCH_LIMIT),gap);startTransfer(c.token,rows,uint8_t(n),c.a,gap);return;}
  pc::Record r;
  if(c.op==pc::LATEST){if(!history.latest(r)){startTransfer(c.token,nullptr,0,c.a,false);return;}startTransfer(c.token,&r,1,c.a,false);return;}
  if(c.op==pc::TIME){
    if(c.a<1577836800u || c.a>4102444800u){error(c.token,pc::MALFORMED);return;}
    // One anchor per boot, not one every foreground poll. This preserves ring
    // capacity for measurements; the phone can re-import this same anchor.
    if(anchored){startTransfer(c.token,&currentAnchor,1,0,false);return;}
    if(!history.request(c.token,pc::ANCHOR,r)){
      r.kind=pc::ANCHOR;r.boot=bootId;r.uptime=uptime();r.utc=c.a;r.request=c.token;
      if(!history.append(r)){storageReady=false;updateInfo();error(c.token,pc::STORAGE);return;}
    }
    utcOffset=int64_t(r.utc)-r.uptime;anchored=true;currentAnchor=r;updateInfo();startTransfer(c.token,&r,1,0,false);return;
  }
  if(c.op==pc::FRESH){
    if(!c.token){error(c.token,pc::MALFORMED);return;}
    if(history.request(c.token,pc::MANUAL,r)){startTransfer(c.token,&r,1,0,false);return;}
    if(hadManual && uint32_t(millis()-lastManual)<pc::MANUAL_COOLDOWN_MS){error(c.token,pc::BUSY,pc::MANUAL_COOLDOWN_MS-uint32_t(millis()-lastManual));return;}
    if(!sample(pc::MANUAL,c.token,r)){error(c.token,pc::STORAGE);return;}
    hadManual=true;lastManual=millis();startTransfer(c.token,&r,1,0,false);
  }
}
class Connections:public BLEServerCallbacks {
  void onDisconnect(BLEServer*)override{subscribed.store(false);restartAdvertising.store(true);}
};
class Subscriptions:public BLECharacteristicCallbacks {
  void onSubscribe(BLECharacteristic*,ble_gap_conn_desc*,uint16_t value)override{subscribed.store((value&1)!=0);}
};
class Controls:public BLECharacteristicCallbacks {
  void onWrite(BLECharacteristic* c)override{
    const auto value=c->getValue();if(value.length()!=20){malformedControl.store(true);return;}
    portENTER_CRITICAL(&queueMux);
    if(queueCount<controls.size()){memcpy(controls[queueWrite].data(),value.c_str(),20);queueWrite=(queueWrite+1)%controls.size();queueCount++;}
    else malformedControl.store(true);
    portEXIT_CRITICAL(&queueMux);
  }
};
void serialCommand(String line){
  line.trim();if(line=="help"){Serial.println("status | sample | adc | live on | live off | cal show | cal dry [ADC_mV] | cal wet [ADC_mV] | cal save");return;}
  if(line=="status" || line=="cal show"){
    Serial.printf("PC DEVICE name=PlantComp-%02X%02X%02X id=%02x%02x%02x%02x%02x%02x stream=%lu boot=%lu protocol=1 storage=%s oldest=%lu newest=%lu ack=%lu\n",hardwareId[3],hardwareId[4],hardwareId[5],hardwareId[0],hardwareId[1],hardwareId[2],hardwareId[3],hardwareId[4],hardwareId[5],(unsigned long)streamId,(unsigned long)bootId,storageReady?"ready":"ERROR",(unsigned long)history.oldest(),(unsigned long)history.newest(),(unsigned long)lastAck);
    Serial.printf("PC CAL saved=%s dry=%u wet=%u revision=%lu pending_dry=%u pending_wet=%u (all ADC-side mV)\n",calibration.valid()?"yes":"no",calibration.dry,calibration.wet,(unsigned long)calibration.revision,pendingCalibration.dry,pendingCalibration.wet);return;
  }
  if(line=="live on" || line=="live off"){live=line=="live on";Serial.println(live?"PC LIVE diagnostic only; no history records":"PC LIVE off");return;}
  if(line=="adc"){const auto r=readSoil();Serial.printf("PC ADC mean=%.1f mV rail_samples=%u/32 estimated_probe=%.1f mV\n",r.mv,r.rails,r.mv*2);return;}
  if(line=="sample"){pc::Record r;sample(pc::MANUAL,0,r);return;}
  if(line=="cal save"){
    const auto soil=readSoil();if(!pendingCalibration.valid() || soil.rails>=24 || soil.mv<20 || soil.mv>2400){Serial.println("PC CAL REJECTED: endpoints need >=50mV separation and valid 20..2400mV; check wiring/rails");return;}
    pendingCalibration.revision=calibration.revision+1;const auto b=pendingCalibration.bytes();
    if(prefs.putBytes("cal",b.data(),b.size())!=b.size()){Serial.println("PC CAL save FAILED");return;}
    calibration=pendingCalibration;updateInfo();Serial.println("PC CAL SAVED (survives power cycle)");return;
  }
  if(line=="cal dry" || line=="cal wet" || line.startsWith("cal dry ") || line.startsWith("cal wet ")){
    const bool dry=line.startsWith("cal dry");const int split=line.indexOf(' ',4);
    float mv;
    if(split>=0){char* end=nullptr;mv=strtof(line.c_str()+split+1,&end);if(!end || *end || !isfinite(mv)){Serial.println("PC CAL invalid numeric ADC mV");return;}}
    else {const auto soil=readSoil();if(soil.rails>=24){Serial.println("PC CAL rail reading REJECTED; check wiring");return;}mv=soil.mv;}
    if(mv<20 || mv>2400){Serial.println("PC CAL endpoint outside usable ADC range");return;}
    if(dry)pendingCalibration.dry=uint16_t(lroundf(mv));else pendingCalibration.wet=uint16_t(lroundf(mv));
    Serial.printf("PC CAL pending %s=%u ADC mV; use cal save when both references are ready\n",dry?"dry":"wet",dry?pendingCalibration.dry:pendingCalibration.wet);return;
  }
  if(line.length())Serial.println("PC unknown command; type help");
}
void setup(){
  Serial.begin(115200);const auto serialStart=millis();while(!Serial && uint32_t(millis()-serialStart)<2500)delay(10);
  Serial.println("\nPlant Companion production v1; SDA=D4/GPIO6 SCL=D5/GPIO7 soil=D1/GPIO3");
  if(!prefs.begin("plantcomp",false)){Serial.println("PC NVS unavailable; cannot safely record");return;}
  const uint64_t mac=ESP.getEfuseMac();for(int i=0;i<6;i++)hardwareId[i]=uint8_t(mac>>(8*i));
  streamId=prefs.getUInt("stream",0);if(!streamId){streamId=esp_random();if(!streamId)streamId=1;if(prefs.putUInt("stream",streamId)!=4)return;}
  bootId=prefs.getUInt("boot",0)+1;if(!bootId || prefs.putUInt("boot",bootId)!=4){Serial.println("PC boot identity persistence FAILED");return;}
  uint8_t cal[16]{};if(prefs.getBytesLength("cal")==16 && prefs.getBytes("cal",cal,16)==16)calibration.load(cal,16);pendingCalibration=calibration;
  storageReady=openHistory();
  Wire.begin(SDA_PIN,SCL_PIN);Wire.setClock(100000);Wire.setTimeOut(50);
  analogReadResolution(12);analogSetPinAttenuation(SOIL_PIN,ADC_11db);pinMode(SOIL_PIN,INPUT);
  char name[24];snprintf(name,sizeof(name),"PlantComp-%02X%02X%02X",hardwareId[3],hardwareId[4],hardwareId[5]);BLEDevice::init(name);
  server=BLEDevice::createServer();server->setCallbacks(new Connections());auto* service=server->createService(SERVICE);
  infoChar=service->createCharacteristic(INFO,BLECharacteristic::PROPERTY_READ);
  auto* control=service->createCharacteristic(CONTROL,BLECharacteristic::PROPERTY_WRITE);control->setCallbacks(new Controls());
  dataChar=service->createCharacteristic(DATA,BLECharacteristic::PROPERTY_NOTIFY);dataChar->setCallbacks(new Subscriptions());
  updateInfo();service->start();auto* advertising=BLEDevice::getAdvertising();advertising->addServiceUUID(SERVICE);advertising->setScanResponse(true);advertising->start();
  Serial.printf("PC BLE advertising %s production service=%s\n",name,SERVICE);
  schedule.start(millis());pc::Record r;sample(pc::STARTUP,0,r);serialCommand("status");
}
void loop(){
  if(!server){delay(100);return;}
  if(restartAdvertising.exchange(false)){transfer.active=false;portENTER_CRITICAL(&queueMux);queueCount=0;queueRead=queueWrite=0;portEXIT_CRITICAL(&queueMux);BLEDevice::startAdvertising();Serial.println("PC BLE disconnected; advertising restarted");}
  if(malformedControl.exchange(false))Serial.println("PC CONTROL malformed/queue-full; command discarded (client may retry)");
  std::array<uint8_t,20> bytes{};bool has=false;
  portENTER_CRITICAL(&queueMux);if(queueCount){bytes=controls[queueRead];queueRead=(queueRead+1)%controls.size();queueCount--;has=true;}portEXIT_CRITICAL(&queueMux);
  if(has){pc::Command c;if(pc::decodeCommand(bytes.data(),bytes.size(),c))handle(c);else error(pc::u64(bytes.data()+2),pc::MALFORMED);}
  if(transfer.active && server->getConnectedCount() && subscribed.load() && int32_t(millis()-transfer.nextSend)>=0){
    if(transfer.index<transfer.count){const auto frame=pc::chunk(transfer.records[transfer.index],transfer.token,transfer.part++);dataChar->setValue(frame.data(),frame.size());dataChar->notify();if(transfer.part==6){transfer.part=0;transfer.index++;}}
    else{uint8_t end[20]{};end[0]=pc::VERSION;end[1]=2;pc::put64(end+2,transfer.token);end[10]=transfer.count;end[11]=transfer.flags;pc::put32(end+12,transfer.count?transfer.records[transfer.count-1].sequence:transfer.cursor);pc::put32(end+16,transfer.newest);dataChar->setValue(end,20);dataChar->notify();transfer.active=false;}
    transfer.nextSend=millis()+20;
  }
  if(schedule.due(millis())){pc::Record r;sample(pc::SCHEDULED,0,r);}
  static String line;while(Serial.available()){const char c=char(Serial.read());if(c=='\n'){serialCommand(line);line="";}else if(c!='\r'){if(line.length()<80)line+=c;else line="";}}
  static uint32_t lastLive=0;if(live && uint32_t(millis()-lastLive)>=2000){lastLive=millis();printRecord(measure(pc::MANUAL,0),"diagnostic-not-stored");}
  delay(2);
}
