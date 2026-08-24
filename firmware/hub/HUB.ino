// BattleBeam Hub (ESP32) — SoftAP + REST + Async WebSocket
// Friendly Fire + Time Matching (shot_fired ↔ hit) using HUB time only
// + Restore State for reconnect (players map)
// + END GAME (leader_end) => game_over only (no reset)
// + END SESSION (leader_end_session / end_session) => full reset + session_ended
// - SoftAP:  SSID "BattleBeam" / PASS "battle1234"
// - REST:    GET http://192.168.4.1/api/ping  => {"ok":true}
// - WS:      ws://192.168.4.1/ws

#include <WiFi.h>
#include <AsyncTCP.h>
#include <ESPAsyncWebServer.h>
#include <ArduinoJson.h>
#include <map>
#include <vector>

const char* AP_SSID = "BattleBeam";
const char* AP_PASS = "battle1234";

AsyncWebServer server(80);
AsyncWebSocket ws("/ws");

// ======= نموذج الجهاز =======
struct Device {
  String id;
  String kind;     // "gun" / "vest" / "app" / ...
  String team;     // "A" / "B"
  String name;
  bool   online     = false;
  uint32_t lastSeen = 0;

  // منطق اللعبة
  bool   alive          = true;   // للسترة
  uint32_t respawnUntil  = 0;     // للسترة
  uint32_t disabledUntil = 0;     // للمسدس

  // ترتيب تسجيل الـ app عشان نختار الليدر
  uint32_t regOrder = 0;         
  // حجز الجهاز للاعب معيّن (app id)
  String claimedBy;
};

std::map<String, Device> devices;

// ======= حالة اللاعب  =======
struct PlayerState {
  String id;         
  String name;
  String team;
  String gunId;
  String vestId;
  bool   alive = true;
  uint32_t respawnUntil = 0;
  bool   online = true;
  int    score = 0;   
};

std::map<String, PlayerState> players;

// ======= ربط السترة مع اللاعب =======
std::map<String, String> vestToPlayer;   // key = vestId,   value = player_id
std::map<String, String> playerToGun;    // key = playerId, value = gun_id

// ======= سكور + حالة القيم =======
int scoreA = 0, scoreB = 0;
int targetScore = 5;
bool sessionActive = false;   


const uint32_t GUN_DISABLE_MS      = 10000; 
const uint32_t VEST_RESPAWN_MS     = 10000;
const uint32_t OFFLINE_TIMEOUT_MS  = 10000;

// ======= منطق الليدر =======
String   leaderAppId = "";    
uint32_t nextAppOrder = 1;    // لترتيب تسجيل  

void broadcastDevices();
void broadcastScoreBoard();
void broadcastGameOver(const char* winner, int finalScore);

// ===== ربط للأجهزة (أسلحة + سترات) =====
void clearClaimsAndMappings() {
  vestToPlayer.clear();
  playerToGun.clear();

  for (auto &kv : devices) {
    Device &d = kv.second;
    if (d.kind == "gun" || d.kind == "vest") {
      d.claimedBy     = "";
      d.alive         = true;
      d.respawnUntil  = 0;
      d.disabledUntil = 0;
    }
  }
  broadcastDevices();
}




void resetAppsForNewSession() {
  leaderAppId  = "";
  nextAppOrder = 1;

  for (auto &kv : devices) {
    Device &d = kv.second;
    if (d.kind == "app") {
      d.name      = "";
      d.team      = "";
      d.claimedBy = "";
      d.regOrder  = 0;
      
    }
  }
  broadcastDevices();
}

// ======= اختيار الليدر =======
void recomputeLeaderIfNeeded() {
  if (leaderAppId.length() && devices.count(leaderAppId)) {
    Device &d = devices[leaderAppId];
    if (d.kind == "app" && d.online) return;
  }

  uint32_t bestOrder = 0xFFFFFFFF;
  String bestId = "";

  for (auto &kv : devices) {
    Device &d = kv.second;
    if (d.kind == "app" && d.online && d.regOrder > 0 && d.regOrder < bestOrder) {
      bestOrder = d.regOrder;
      bestId    = d.id;
    }
  }

  leaderAppId = bestId;
  if (leaderAppId.length()) {
    Serial.printf("[HUB] Leader now: %s\n", leaderAppId.c_str());
  } else {
    Serial.println("[HUB] No leader app.");
  }
}

// ======= عرض الأجهزة =======
void sendDevicesTo(AsyncWebSocketClient* client) {
  DynamicJsonDocument doc(4096);
  doc["type"]   = "devices";
  doc["leader"] = leaderAppId;

  JsonArray arr = doc.createNestedArray("items");
  for (auto &kv : devices) {
    JsonObject o = arr.createNestedObject();
    o["id"]         = kv.second.id;
    o["kind"]       = kv.second.kind;
    o["team"]       = kv.second.team;
    o["name"]       = kv.second.name;
    o["online"]     = kv.second.online;
    o["alive"]      = kv.second.alive;
    o["claimed_by"] = kv.second.claimedBy;
  }

  String out; serializeJson(doc, out);
  if (client) client->text(out); else ws.textAll(out);
}
void broadcastDevices(){ sendDevicesTo(nullptr); }

// ======= بثّ السكور =======
void broadcastScoreUpdate(const char* team, int delta){
  DynamicJsonDocument d(256);
  d["type"]="score_update"; d["team"]=team; d["delta"]=delta;
  String out; serializeJson(d,out); ws.textAll(out);
}

void broadcastScoreBoard(){
  DynamicJsonDocument d(256);
  d["type"]="score_board"; d["team_a"]=scoreA; d["team_b"]=scoreB;
  String out; serializeJson(d,out); ws.textAll(out);
}

void broadcastGameOver(const char* winner, int finalScore){
  DynamicJsonDocument d(256);
  d["type"]="game_over"; d["winner"]=winner; d["final_score"]=finalScore;
  String out; serializeJson(d,out); ws.textAll(out);
}

// ======= RESTORE STATE  =======
void sendRestoreStateTo(AsyncWebSocketClient* client, const String& playerId) {
  if (!client) return;
  auto pit = players.find(playerId);
  if (pit == players.end()) return;

  PlayerState &p = pit->second;
  p.online = true;

  DynamicJsonDocument rs(512);
  rs["type"] = "restore_state";
  rs["player_id"] = p.id;
  rs["name"] = p.name;
  rs["team"] = p.team;
  rs["alive"] = p.alive;
  rs["player_score"] = p.score;
  rs["session_active"] = sessionActive;
  rs["score_a"] = scoreA;
  rs["score_b"] = scoreB;

  uint32_t nowMs = millis();
  uint32_t remain = 0;
  if (!p.alive && p.respawnUntil > nowMs) {
    remain = p.respawnUntil - nowMs;
  }
  rs["respawn_ms_left"] = remain;
  rs["gun_id"] = p.gunId;
  rs["vest_id"] = p.vestId;

  String outRs; serializeJson(rs, outRs);
  client->text(outRs);

  Serial.printf("[HUB] restore_state sent to %s (remain=%lu)\n",
                playerId.c_str(), (unsigned long)remain);
}

// ======= END GAME =======
void finishGameOnly(const char* winner) {
  int finalScore = (winner[0] == 'A') ? scoreA : scoreB;

  Serial.printf("[HUB] finishGameOnly winner=%s final=%d\n", winner, finalScore);

  broadcastGameOver(winner, finalScore);

  // وقف احتساب النقاط بعد نهاية القيم
  sessionActive = false;

  
}

// ======= END SESSION =======
void endSessionAndResetAll() {
  Serial.println("[HUB] END SESSION -> full reset");

 // Stop the active session
  sessionActive = false;

  // Reset team scores
  scoreA = 0;
  scoreB = 0;
  broadcastScoreBoard();

  // Release all claimed devices and clear mappings
  clearClaimsAndMappings();

  // Remove stored player states to prevent restoring old session data
  players.clear();

  // Notify all applications that the session has ended
  DynamicJsonDocument d(128);
  d["type"] = "session_ended";
  String out; serializeJson(d, out);
  ws.textAll(out);

  broadcastDevices();
}

// ======= أوامر للأجهزة (vest/gun) =======
void sendCmdToDevice(const String& deviceId, const char* cmd, uint32_t ms=0){
  DynamicJsonDocument d(256);
  d["type"]="cmd"; d["cmd"]=cmd; d["deviceId"]=deviceId;
  if (ms) d["ms"]=ms;
  String out; serializeJson(d,out); ws.textAll(out);
}


struct Shot { String gun; String team; uint32_t ts; };
std::vector<Shot> lastShots;
const uint32_t SHOT_WINDOW_KEEP_MS = 500;
const uint32_t MATCH_WINDOW_MS     = 300;

void recordShot(const String& gun, const String& team, uint32_t ts){
  lastShots.push_back({gun, team, ts});
  uint32_t now = millis();
  auto it = lastShots.begin();
  while (it != lastShots.end()){
    if ((int32_t)(now - it->ts) > (int32_t)SHOT_WINDOW_KEEP_MS) it = lastShots.erase(it);
    else ++it;
  }
}

int findNearestOppositeShot(uint32_t tHit, const String& victimTeam){
  int best = -1; uint32_t bestDiff = 0xFFFFFFFF;
  for (int i=0;i<(int)lastShots.size();++i){
    if (lastShots[i].team == victimTeam) continue;
    uint32_t d = (tHit > lastShots[i].ts) ? (tHit - lastShots[i].ts) : (lastShots[i].ts - tHit);
    if (d <= MATCH_WINDOW_MS && d < bestDiff){ best=i; bestDiff=d; }
  }
  return best;
}

// ======= إضافة نقطة =======
void addPointForTeam(const String& team){
  if (!sessionActive) return;

  if (team=="A"){ scoreA++; broadcastScoreUpdate("A",1); }
  else if (team=="B"){ scoreB++; broadcastScoreUpdate("B",1); }
  else return;

  broadcastScoreBoard();

  // لو وصل أحد للتارقت ينهي القيم  
  if (scoreA >= targetScore) {
    finishGameOnly("A");
  } else if (scoreB >= targetScore) {
    finishGameOnly("B");
  }
}

// ======= معالجة رسائل WS =======
void handleMsg(const String& msg, AsyncWebSocketClient* client=nullptr){
  DynamicJsonDocument doc(1024);
  auto err = deserializeJson(doc, msg);
  if (err){ Serial.printf("[HUB] JSON error: %s\n", err.c_str()); return; }

  String type = doc["type"] | "";

  // ===== register =====
  if (type == "register"){
    String id   = doc["deviceId"]|""; 
    String kind = doc["kind"]    |"unknown";
    String team = doc["team"]    |"";     
    String name = doc["name"]    |""; 

    if (id.length()){
      uint32_t now = millis();

      auto it = devices.find(id);
      if (it == devices.end()) {
        Device d;
        d.id    = id;
        d.kind  = kind;
        d.team  = team;
        d.name  = name;
        d.online    = true;
        d.lastSeen  = now;
        d.alive     = true;
        d.respawnUntil  = 0;
        d.disabledUntil = 0;
        d.regOrder      = 0;
        d.claimedBy     = "";

        if (kind == "app") {
          d.regOrder = nextAppOrder++;
          Serial.printf("[HUB] APP REGISTER (new): %s (order=%lu)\n",
                        id.c_str(), (unsigned long)d.regOrder);
        }

        devices[id] = d;
      } else {
        Device &d = it->second;
        d.kind    = kind;
        d.team    = team;
        d.name    = name;
        d.online  = true;
        d.lastSeen= now;

        if (kind == "app" && d.regOrder == 0) {
          d.regOrder = nextAppOrder++;
          Serial.printf("[HUB] APP REGISTER (existing): %s (order=%lu)\n",
                        id.c_str(), (unsigned long)d.regOrder);
        }
      }

      Serial.printf("[HUB] Registered: %s (%s) team=%s name=%s\n",
        id.c_str(), kind.c_str(), team.c_str(), name.c_str());

      if (kind == "app") {
        
        auto pit = players.find(id);
        if (pit != players.end()) {
          if (name.length()) pit->second.name = name;
          if (team.length()) pit->second.team = team;
          pit->second.online = true;
        }

        recomputeLeaderIfNeeded();

        // restore_state إذا اللاعب معروف عندنا
        if (client) {
          sendRestoreStateTo(client, id);
        }
      }

      broadcastDevices();

      
      if (client){
        DynamicJsonDocument dscore(256);
        dscore["type"]="score_board"; 
        dscore["team_a"]=scoreA; 
        dscore["team_b"]=scoreB;
        String out; serializeJson(dscore,out); 
        client->text(out);
      }
    }
  }

  // ===== ping =====
  else if (type == "ping"){
    String id = doc["deviceId"]|"";
    if (id.length() && devices.count(id)){
      bool wasOnline = devices[id].online;
      devices[id].lastSeen = millis();
      devices[id].online   = true;

      if (!wasOnline) {
        if (devices[id].kind == "app") {
          recomputeLeaderIfNeeded();
          auto pit = players.find(id);
          if (pit != players.end()) pit->second.online = true;
        }
        broadcastDevices();
      }
    }
  }

  else if (type == "get_devices"){ sendDevicesTo(client); }

  else if (type == "get_score"){
    DynamicJsonDocument d(256);
    d["type"]="score_board"; d["team_a"]=scoreA; d["team_b"]=scoreB;
    String out; serializeJson(d,out); if (client) client->text(out);
  }

  // ===== start_session / leader_start =====
  else if (type == "leader_start" || type == "start_session"){
    sessionActive = true;

    int t = doc["target_score"] | targetScore;
    if (t < 1) t = 1;
    targetScore = t;

    // نبدأ قيم جديد: صفّر السكور فقط
    scoreA = 0;
    scoreB = 0;

    // نرجع حالة الأجهزة 
    for (auto &kv:devices){
      kv.second.alive = true;
      kv.second.respawnUntil  = 0;
      kv.second.disabledUntil = 0;
    }

    // نرجع حالة اللاعبين)
    for (auto &kv : players) {
      kv.second.alive = true;
      kv.second.respawnUntil = 0;
      kv.second.score = 0;
    }

    Serial.printf("[HUB] Session start, target=%d\n", targetScore);

    {
      DynamicJsonDocument g(256);
      g["type"] = "game_active";
      g["target_score"] = targetScore;
      String out; serializeJson(g, out);
      ws.textAll(out);
    }

    broadcastScoreBoard();
    broadcastDevices();
  }

  // ===== END GAME =====
  else if (type == "leader_end") {
    const char* winner = "A";
    if (scoreB > scoreA) winner = "B";

    Serial.println("[HUB] Leader requested END GAME -> game_over only.");
    finishGameOnly(winner);
  }

  // ===== END SESSION  =====
  else if (type == "leader_end_session" || type == "end_session") {
    Serial.println("[HUB] Leader requested END SESSION -> full reset.");
    endSessionAndResetAll();
  }

  else if (type == "set_target"){
    int t = doc["value"] | targetScore;
    if (t < 1) t = 1;
    targetScore = t;

    DynamicJsonDocument d(128);
    d["type"]="target_score";
    d["value"]=targetScore;
    String out; serializeJson(d,out);
    ws.textAll(out);
  }

  else if (type == "reset_score"){ 
    scoreA = 0; scoreB = 0;
    broadcastScoreBoard();
  }

  // ===== player_ready =====
  else if (type == "player_ready") {
    String playerId = doc["player_id"] | "";
    String gunId    = doc["gun_id"]    | "";
    String vestId   = doc["vest_id"]   | "";

    Serial.printf("[HUB] player_ready: player=%s gun=%s vest=%s\n",
                  playerId.c_str(), gunId.c_str(), vestId.c_str());

    if (!playerId.length()) return;

    if (gunId.length() && devices.count(gunId)) {
      Device &g = devices[gunId];
      if (g.claimedBy.isEmpty()) g.claimedBy = playerId;
      playerToGun[playerId] = gunId;
    }

    if (vestId.length() && devices.count(vestId)) {
      Device &v = devices[vestId];
      if (v.claimedBy.isEmpty()) v.claimedBy = playerId;
    }

    if (vestId.length()) vestToPlayer[vestId] = playerId;

    
    {
      auto pit = players.find(playerId);

      if (pit == players.end()) {
        PlayerState p;
        p.id = playerId;
        if (devices.count(playerId)) {
          p.name = devices[playerId].name;
          p.team = devices[playerId].team;
        }
        p.gunId  = gunId;
        p.vestId = vestId;
        p.alive  = true;
        p.respawnUntil = 0;
        p.online = true;
        p.score  = 0;
        players[playerId] = p;
      } else {
        PlayerState &p = pit->second;
        p.gunId  = gunId;
        p.vestId = vestId;
        p.online = true;
        if (devices.count(playerId)) {
          if (devices[playerId].team.length()) p.team = devices[playerId].team;
          if (devices[playerId].name.length()) p.name = devices[playerId].name;
        }
      }
    }

    broadcastDevices();
  }

  // ===== shot_fired =====
  else if (type == "shot_fired"){
    String gun  = doc["deviceId"] | "";
    String team = doc["team"]     | "";
    uint32_t ts = millis();
    if (gun.length()){
      if (team.isEmpty() && devices.count(gun)) team = devices[gun].team;
      recordShot(gun, team, ts);
    }
  }

  // ===== hit =====
  else if (type == "hit"){
    String vestId = doc["vestId"] | "";
    String byGun  = doc["byGun"]  | "";
    String teamVictim  = String((const char*)(doc["teamVictim"]  | ""));
    String teamShooter = String((const char*)(doc["teamShooter"] | ""));
    uint32_t tHit      = millis();

    if (!devices.count(vestId)) return;
    Device &vest = devices[vestId];

    if (teamVictim.isEmpty()) teamVictim = vest.team;

    Device* gunPtr = nullptr;

    if (byGun.length() && devices.count(byGun)) {
      gunPtr = &devices[byGun];
      if (teamShooter.isEmpty()) teamShooter = gunPtr->team;
    } else {
      int idx = findNearestOppositeShot(tHit, teamVictim);
      if (idx >= 0){
        byGun = lastShots[idx].gun;
        teamShooter = lastShots[idx].team;
        if (devices.count(byGun)) gunPtr = &devices[byGun];
      }
    }

    uint32_t now = millis();

    // لو السترة في الرسبون تتجاهل
    if (!vest.alive && now < vest.respawnUntil) return;

    // Friendly fire
    bool isFriendly = (teamVictim.length() && teamShooter.length() && teamVictim == teamShooter);
    if (isFriendly) return;

    //  (فلترة إشارات وهمية)
    if (!gunPtr) return;

    
    vest.alive = false;
    vest.respawnUntil = now + VEST_RESPAWN_MS;
    sendCmdToDevice(vestId, "you_are_hit", VEST_RESPAWN_MS);

    
    String playerId  = "";
    String playerName = "";
    if (vestToPlayer.count(vestId)) {
      playerId = vestToPlayer[vestId];
      if (devices.count(playerId)) playerName = devices[playerId].name;
    }

    
    if (playerId.length()) {
      auto pit = players.find(playerId);
      if (pit != players.end()) {
        pit->second.alive = false;
        pit->second.respawnUntil = vest.respawnUntil;
      }
    }

    // تعطيل مسدس 
    if (playerId.length() && playerToGun.count(playerId)) {
      String victimGunId = playerToGun[playerId];
      if (devices.count(victimGunId)) {
        Device &vg = devices[victimGunId];
        vg.disabledUntil = now + VEST_RESPAWN_MS;
        sendCmdToDevice(vg.id, "disable", VEST_RESPAWN_MS);
      }
    }

    // نقطة لفريق 
    if (teamShooter=="A" || teamShooter=="B") addPointForTeam(teamShooter);

    
    if (playerId.length()) {
      DynamicJsonDocument appMsg(256);
      appMsg["type"] = "you_are_hit";
      appMsg["player_id"] = playerId;
      appMsg["player_name"] = playerName;
      appMsg["respawn_seconds"] = VEST_RESPAWN_MS / 1000;
      String out; serializeJson(appMsg, out);
      ws.textAll(out);
    }

    broadcastDevices();
  }

  else {
    Serial.printf("[HUB] Unknown message type: %s\n", type.c_str());
  }
}

// ======= WebSocket events =======
void onWsEvent(AsyncWebSocket * serverObj, AsyncWebSocketClient * client,
               AwsEventType type, void * arg, uint8_t * data, size_t len){
  if (type == WS_EVT_CONNECT){
    Serial.printf("[WS] Client %u connected\n", client->id());
    sendDevicesTo(client);

    DynamicJsonDocument d(256);
    d["type"]="score_board"; d["team_a"]=scoreA; d["team_b"]=scoreB;
    String out; serializeJson(d,out); client->text(out);
  }
  else if (type == WS_EVT_DISCONNECT){
    Serial.printf("[WS] Client %u disconnected\n", client->id());
  }
  else if (type == WS_EVT_DATA){
    String msg; msg.reserve(len);
    for (size_t i=0;i<len;++i) msg += (char)data[i];

    bool isPing = (msg.indexOf("\"type\":\"ping\"") >= 0);
    if (!isPing){
      Serial.print("[WS] Recv: ");
      Serial.println(msg);
    }
    handleMsg(msg, client);
  }
}

void setup(){
  Serial.begin(115200);
  delay(50);

  WiFi.mode(WIFI_AP);
  WiFi.softAP(AP_SSID, AP_PASS, 1, 0, 8);

  Serial.print("[HUB] AP IP: ");
  Serial.println(WiFi.softAPIP());

  server.on("/api/ping", HTTP_GET, [](AsyncWebServerRequest *req){
    req->send(200, "application/json", "{\"ok\":true}");
  });

  ws.onEvent(onWsEvent);
  server.addHandler(&ws);
  server.begin();

  Serial.println("[HUB] Server started (REST + WS)");
}

void loop(){
  static uint32_t tick = 0;
  uint32_t now = millis();

  
  if (now - tick > 2000){
    tick = now;
    bool changed=false;
    bool appsChanged=false;

    for (auto &kv : devices){
      Device &d = kv.second;
      if (d.online && (now - d.lastSeen > OFFLINE_TIMEOUT_MS)){
        d.online = false; changed = true;
        if (d.kind == "app") {
          appsChanged = true;
          auto pit = players.find(d.id);
          if (pit != players.end()) pit->second.online = false;
        }
        Serial.printf("[HUB] Device %s timed out -> offline\n", d.id.c_str());
      }
    }

    if (appsChanged) recomputeLeaderIfNeeded();
    if (changed) broadcastDevices();
  }

 
  for (auto &kv : devices){
    Device &d = kv.second;

    if (d.kind=="gun" && d.disabledUntil && now >= d.disabledUntil){
      d.disabledUntil = 0;
      sendCmdToDevice(d.id, "enable");
      Serial.printf("[HUB] Gun %s enabled\n", d.id.c_str());
    }

    if (d.kind=="vest" && !d.alive && d.respawnUntil && now >= d.respawnUntil){
      d.alive = true;
      d.respawnUntil = 0;
      sendCmdToDevice(d.id, "revive");
      Serial.printf("[HUB] Vest %s revived\n", d.id.c_str());
      broadcastDevices();

      // PlayerState 
      if (vestToPlayer.count(d.id)) {
        String pid = vestToPlayer[d.id];
        auto pit = players.find(pid);
        if (pit != players.end()) {
          pit->second.alive = true;
          pit->second.respawnUntil = 0;
        }
      }
    }
  }

  delay(10);
}


