#pragma once
// Portable production logic, shared verbatim with the executable host tests.
#include <array>
#include <algorithm>
#include <cmath>
#include <cstddef>
#include <cstdint>
#include <cstring>

namespace pc {
constexpr uint8_t VERSION = 1;
constexpr size_t RECORD_BYTES = 48, FRAME_BYTES = 20, CAPACITY = 1024;
constexpr uint32_t INTERVAL_MS = 20u * 60u * 1000u;
constexpr uint32_t MANUAL_COOLDOWN_MS = 5000;
constexpr uint8_t BATCH_LIMIT = 8;
enum Kind : uint8_t { STARTUP = 1, SCHEDULED = 2, MANUAL = 3, ANCHOR = 4 };
enum Op : uint8_t { HELLO = 0, HISTORY = 1, LATEST = 2, FRESH = 3, TIME = 4, ACK = 5 };
enum Error : uint8_t { MALFORMED = 1, BUSY = 2, STORAGE = 3, INCOMPATIBLE = 4, NOT_FOUND = 5 };
inline uint16_t u16(const uint8_t* p) { return uint16_t(p[0]) | uint16_t(p[1]) << 8; }
inline uint32_t u32(const uint8_t* p) { return uint32_t(u16(p)) | uint32_t(u16(p + 2)) << 16; }
inline uint64_t u64(const uint8_t* p) { return uint64_t(u32(p)) | uint64_t(u32(p + 4)) << 32; }
inline void put16(uint8_t* p, uint16_t v) { p[0] = v; p[1] = v >> 8; }
inline void put32(uint8_t* p, uint32_t v) { put16(p, v); put16(p + 2, v >> 16); }
inline void put64(uint8_t* p, uint64_t v) { put32(p, v); put32(p + 4, v >> 32); }
inline uint32_t crc32(const uint8_t* p, size_t n) {
  uint32_t c = 0xffffffffu;
  while (n--) { c ^= *p++; for (int b = 0; b < 8; ++b) c = (c >> 1) ^ (0xedb88320u & (0u - (c & 1u))); }
  return ~c;
}
inline uint16_t crc16(const uint8_t* p, size_t n) {
  uint16_t c = 0xffff;
  while (n--) { c ^= uint16_t(*p++) << 8; for (int b = 0; b < 8; ++b) c = (c & 0x8000) ? (c << 1) ^ 0x1021 : c << 1; }
  return c;
}
struct Record {
  uint8_t kind = STARTUP, valid = 0, flags = 0;
  uint32_t sequence = 0, boot = 0, uptime = 0, utc = 0;
  uint64_t request = 0;
  uint16_t moisture = 0xffff;
  int16_t temperature = INT16_MIN;
  uint16_t humidity = 0xffff, adc = 0;
  uint32_t milliLux = 0xffffffffu;
};
using Bytes = std::array<uint8_t, RECORD_BYTES>;
inline Bytes encode(const Record& r) {
  Bytes b{}; b[0] = VERSION; b[1] = r.kind; b[2] = r.valid; b[3] = r.flags;
  put32(b.data()+4,r.sequence); put32(b.data()+8,r.boot); put32(b.data()+12,r.uptime); put32(b.data()+16,r.utc);
  put64(b.data()+20,r.request); put16(b.data()+28,r.moisture); put16(b.data()+30,uint16_t(r.temperature));
  put16(b.data()+32,r.humidity); put16(b.data()+34,r.adc); put32(b.data()+36,r.milliLux);
  put32(b.data()+44,crc32(b.data(),44)); return b;
}
inline bool decode(const uint8_t* b, Record& r) {
  if (b[0] != VERSION || b[1] < STARTUP || b[1] > ANCHOR || (b[2] & ~15u) || (b[3] & ~3u) || !u32(b+4) || !u32(b+8) ||
      u32(b+40) != 0 || crc32(b,44) != u32(b+44)) return false;
  r.kind=b[1]; r.valid=b[2]; r.flags=b[3]; r.sequence=u32(b+4); r.boot=u32(b+8);
  r.uptime=u32(b+12); r.utc=u32(b+16); r.request=u64(b+20); r.moisture=u16(b+28);
  r.temperature=int16_t(u16(b+30)); r.humidity=u16(b+32); r.adc=u16(b+34); r.milliLux=u32(b+36);
  if ((r.valid & 1) && r.moisture > 10000) return false;
  if ((r.valid & 2) && (r.temperature < -4000 || r.temperature > 12500)) return false;
  if ((r.valid & 4) && r.humidity > 10000) return false;
  if ((r.valid & 8) && r.milliLux == 0xffffffffu) return false;
  if (!(r.valid & 1) && r.moisture != 0xffff) return false;
  if (!(r.valid & 2) && r.temperature != INT16_MIN) return false;
  if (!(r.valid & 4) && r.humidity != 0xffff) return false;
  if (!(r.valid & 8) && r.milliLux != 0xffffffffu) return false;
  return r.kind != ANCHOR || (r.valid == 0 && r.utc != 0);
}
struct Command { uint8_t op = HELLO; uint64_t token = 0; uint32_t a = 0, b = 0; };
inline std::array<uint8_t,20> encodeCommand(const Command& c) {
  std::array<uint8_t,20> b{}; b[0]=VERSION;b[1]=c.op;put64(b.data()+2,c.token);
  put32(b.data()+10,c.a);put32(b.data()+14,c.b);put16(b.data()+18,crc16(b.data(),18));return b;
}
inline bool decodeCommand(const uint8_t* b,size_t n,Command& c) {
  if(n!=20 || b[0]!=VERSION || b[1]>ACK || crc16(b,18)!=u16(b+18))return false;
  c.op=b[1];c.token=u64(b+2);c.a=u32(b+10);c.b=u32(b+14);return true;
}
inline std::array<uint8_t,20> chunk(const Record& r,uint64_t token,uint8_t index) {
  std::array<uint8_t,20> b{};b[0]=VERSION;b[1]=1;b[2]=index;b[3]=6;
  put32(b.data()+4,uint32_t(token));put32(b.data()+8,r.sequence);
  const auto bytes=encode(r);if(index<6)std::memcpy(b.data()+12,bytes.data()+index*8,8);return b;
}
class Scheduler {
 public:
  void start(uint32_t now){next_=now+INTERVAL_MS;}
  bool due(uint32_t now){
    if(int32_t(now-next_)<0)return false;
    next_ += ((now-next_)/INTERVAL_MS+1)*INTERVAL_MS;return true;
  }
  uint32_t next() const{return next_;}
 private: uint32_t next_=0;
};
struct Calibration {
  uint16_t dry=0,wet=0;uint32_t revision=0;
  bool valid()const{return dry>=20 && dry<=2400 && wet>=20 && wet<=2400 && std::abs(int(dry)-int(wet))>=50;}
  bool percent(float adc,uint16_t& out)const{
    if(!valid() || !std::isfinite(adc) || adc<20 || adc>2400)return false;
    const float value=10000.f*(adc-float(dry))/(float(wet)-float(dry));
    out=uint16_t(std::lround(std::max(0.f,std::min(10000.f,value))));return true;
  }
  std::array<uint8_t,16> bytes()const{
    std::array<uint8_t,16>b{};put32(b.data(),0x314c4143);put16(b.data()+4,dry);put16(b.data()+6,wet);
    put32(b.data()+8,revision);put32(b.data()+12,crc32(b.data(),12));return b;
  }
  bool load(const uint8_t* b,size_t n){
    if(n!=16 || u32(b)!=0x314c4143 || crc32(b,12)!=u32(b+12))return false;
    Calibration c;c.dry=u16(b+4);c.wet=u16(b+6);c.revision=u32(b+8);if(!c.valid())return false;*this=c;return true;
  }
};
// Storage implementation must flush before success. A CRC-protected slot is
// the commit record: no independently updated head pointer can get ahead of it.
struct BlockStore {
  virtual bool read(size_t offset,uint8_t* out,size_t n)=0;
  virtual bool write(size_t offset,const uint8_t* in,size_t n)=0;
  virtual bool flush()=0;
  virtual ~BlockStore()=default;
};
template<size_t N=CAPACITY> class History {
 public:
  explicit History(BlockStore& store):store_(store){}
  bool recover(){
    newest_=0;present_.fill(false);
    for(size_t i=0;i<N;++i){Bytes bytes{};if(!store_.read(i*RECORD_BYTES,bytes.data(),bytes.size()))return false;
      Record r;if(decode(bytes.data(),r) && r.sequence%N==i){records_[i]=r;present_[i]=true;newest_=std::max(newest_,r.sequence);}}
    return true;
  }
  uint32_t newest()const{return newest_;}
  uint32_t oldest()const{uint32_t min=UINT32_MAX;for(size_t i=0;i<N;++i)if(present_[i])min=std::min(min,records_[i].sequence);return min==UINT32_MAX?0:min;}
  bool get(uint32_t seq,Record& r)const{const size_t i=seq%N;if(!present_[i] || records_[i].sequence!=seq)return false;r=records_[i];return true;}
  bool latest(Record& out)const{
    for(uint32_t s=newest_,left=uint32_t(N);s && left;--s,--left)if(get(s,out)&&out.kind!=ANCHOR)return true;
    return false;
  }
  bool request(uint64_t token,uint8_t kind,Record& r)const{
    if(!token)return false;for(size_t i=0;i<N;++i)if(present_[i]&&records_[i].kind==kind&&records_[i].request==token){r=records_[i];return true;}return false;
  }
  bool append(Record& r){
    if(newest_==UINT32_MAX)return false;r.sequence=newest_+1;const auto b=encode(r);const size_t slot=r.sequence%N;
    present_[slot]=false;
    if(!store_.write(slot*RECORD_BYTES,b.data(),b.size()) || !store_.flush())return false;
    Bytes check{};Record validated;
    if(!store_.read(slot*RECORD_BYTES,check.data(),check.size()) || !decode(check.data(),validated) || check!=b)return false;
    records_[slot]=r;present_[slot]=true;newest_=r.sequence;return true;
  }
  size_t batch(uint32_t cursor,Record* out,size_t limit,bool& gap)const{
    const auto first=oldest();gap=first && cursor < first-1;size_t n=0;
    uint32_t start=std::max(first,cursor==UINT32_MAX?UINT32_MAX:cursor+1);
    for(uint32_t s=start;s && s<=newest_ && n<limit;++s){Record r;if(get(s,r))out[n++]=r;else gap=true;}
    return n;
  }
 private:
  BlockStore& store_;std::array<Record,N>records_{};std::array<bool,N>present_{};uint32_t newest_=0;
};
} // namespace pc
