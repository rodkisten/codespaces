package main

import (
 "container/list"
 "encoding/json"
 "sync"
 "time"
)

const memoryLimit = 16 << 20 // 16 MiB
type memoryEntry struct {
 key string
 payload []byte
 saved time.Time
}
type memoryCache struct {
 mu sync.Mutex
 used int
 items map[string]*list.Element
 order *list.List
}
var hotCache = &memoryCache{items:make(map[string]*list.Element),order:list.New()}

func (c *memoryCache) get(key string, target any, ttl time.Duration)(bool,bool) {
 c.mu.Lock()
 element:=c.items[key]
 if element==nil {c.mu.Unlock();return false,false}
 c.order.MoveToFront(element)
 entry:=element.Value.(*memoryEntry)
 payload:=append([]byte(nil),entry.payload...)
 saved:=entry.saved
 c.mu.Unlock()
 if json.Unmarshal(payload,target)!=nil {return false,false}
 return true,time.Since(saved)>ttl
}
func (c *memoryCache) put(key string, value any) {
 payload,err:=json.Marshal(value)
 if err!=nil||len(payload)>memoryLimit {return}
 c.mu.Lock()
 defer c.mu.Unlock()
 if old:=c.items[key];old!=nil {
  c.used-=len(old.Value.(*memoryEntry).payload)
  c.order.Remove(old)
  delete(c.items,key)
 }
 entry:=&memoryEntry{key:key,payload:payload,saved:time.Now()}
 c.items[key]=c.order.PushFront(entry)
 c.used+=len(payload)
 for c.used>memoryLimit {
  oldest:=c.order.Back()
  if oldest==nil {break}
  victim:=oldest.Value.(*memoryEntry)
  c.used-=len(victim.payload)
  delete(c.items,victim.key)
  c.order.Remove(oldest)
 }
}
