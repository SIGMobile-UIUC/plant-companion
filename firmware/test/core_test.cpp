#include "../PlantCompanion/pc_core.h"
#include <cassert>
#include <cstdio>
#include <fstream>
#include <iostream>
#include <string>
#include <vector>

struct Memory:pc::BlockStore {
  std::vector<uint8_t> data;bool fail=false,tear=false,flushFail=false;
  explicit Memory(size_t n):data(n*pc::RECORD_BYTES){}
  bool read(size_t p,uint8_t* b,size_t n)override{if(p+n>data.size())return false;std::memcpy(b,data.data()+p,n);return true;}
  bool write(size_t p,const uint8_t* b,size_t n)override{if(fail)return false;std::memcpy(data.data()+p,b,tear?n/2:n);return !tear;}
  bool flush()override{return !flushFail;}
};
std::string hex(const uint8_t* b,size_t n){std::string s;const char* d="0123456789abcdef";while(n--){s+=d[*b>>4];s+=d[*b++&15];}return s;}
int main(int argc,char** argv){
  pc::Scheduler s;s.start(100);assert(!s.due(100));assert(!s.due(1200099));
  auto deadline=s.next(); // Manual sampling has no scheduler operation.
  assert(s.next()==deadline);assert(s.due(1200100));assert(s.next()==2400100);
  assert(s.due(6000100));assert(s.next()==7200100);
  s.start(UINT32_MAX-100);assert(!s.due(200));assert(s.due(1200000-101));
  pc::Scheduler reboot;reboot.start(10);assert(reboot.next()==1200010);
  pc::Calibration c;uint16_t value=0;assert(!c.percent(800,value));
  c={1800,500,1};assert(c.percent(1800,value)&&value==0);assert(c.percent(500,value)&&value==10000);
  assert(c.percent(1150,value)&&value==5000);assert(c.percent(2000,value)&&value==0);
  assert(!c.percent(0,value));assert(!c.percent(2500,value));
  auto cb=c.bytes();pc::Calibration restored;assert(restored.load(cb.data(),cb.size()));assert(restored.dry==1800);
  cb[4]^=1;assert(!restored.load(cb.data(),cb.size()));
  c={500,1800,2};assert(c.percent(1150,value)&&value==5000);
  c={1000,1020,3};assert(!c.valid());
  Memory memory(4);pc::History<4> h(memory);assert(h.recover());pc::Record r;r.boot=1;r.valid=14;r.temperature=2356;r.humidity=4567;r.milliLux=123456;
  assert(h.append(r));assert(r.sequence==1);const auto startup=r;
  r.kind=pc::SCHEDULED;assert(h.append(r));r.kind=pc::MANUAL;r.request=0xfedcba9876543210ULL;assert(h.append(r));
  pc::Record found;assert(h.request(r.request,pc::MANUAL,found)&&found.sequence==3);
  memory.fail=true;assert(!h.append(r));assert(h.newest()==3);memory.fail=false;
  assert(h.append(r));assert(h.append(r));assert(h.oldest()==2);
  bool gap=false;pc::Record rows[8];assert(h.batch(0,rows,8,gap)==4&&gap);
  memory.tear=true;assert(!h.append(r));memory.tear=false;
  pc::History<4> afterPowerLoss(memory);assert(afterPowerLoss.recover());assert(afterPowerLoss.newest()==5);
  assert(afterPowerLoss.get(5,found));assert(!afterPowerLoss.get(2,found)); // Torn overwritten slot rejected.
  assert(afterPowerLoss.batch(1,rows,8,gap)==3&&gap);
  memory.flushFail=true;assert(!afterPowerLoss.append(r));memory.flushFail=false;
  pc::History<4> afterUncertainFlush(memory);assert(afterUncertainFlush.recover());
  assert(afterUncertainFlush.newest()==6); // A durable CRC-valid uncertain write is safely recovered.
  auto encoded=pc::encode(startup);assert(encoded.size()==48);assert(pc::decode(encoded.data(),found));
  encoded[28]^=1;assert(!pc::decode(encoded.data(),found));
  pc::Command command{pc::FRESH,0xfedcba9876543210ULL,123,8},decoded;
  auto control=pc::encodeCommand(command);assert(pc::decodeCommand(control.data(),20,decoded));assert(decoded.token==command.token);
  control[10]^=1;assert(!pc::decodeCommand(control.data(),20,decoded));
  if(argc>1){
    std::ofstream out(argv[1]);auto record=startup;record.sequence=42;record.boot=7;record.uptime=1201;record.utc=0;record.kind=pc::MANUAL;record.request=command.token;
    record.valid=15;record.flags=1;record.moisture=5050;record.adc=1100;
    const auto bytes=pc::encode(record);control=pc::encodeCommand(command);
    out<<"{\n  \"record\": \""<<hex(bytes.data(),bytes.size())<<"\",\n  \"command\": \""<<hex(control.data(),20)<<"\",\n  \"chunks\": [";
    for(uint8_t i=0;i<6;i++){auto frame=pc::chunk(record,command.token,i);assert(frame.size()==20);out<<(i?",":"")<<"\""<<hex(frame.data(),20)<<"\"";}
    out<<"]\n}\n";
  }
  std::cout<<"PASS: production scheduler, calibration, durable history/recovery, request replay, CRC and 20-byte codec goldens\n";
}
