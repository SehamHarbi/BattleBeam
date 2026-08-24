// ===============================
// BattleBeam Vest (ESP8266 / NodeMCU) — Dual TSOP + WebSocket
// With global cooldown to merge hits from both sensors
// Compatible with Hub cmds: you_are_hit/revive + disable/enable
// ===============================

#include <Arduino.h>
#include <ESP8266WiFi.h>
#include <WebSocketsClient.h>
#include <ArduinoJson.h>

// ===== Wi-Fi / Hub =====
const char* WIFI_SSID = "BattleBeam";
const char* WIFI_PASS = "battle1234";
const char* HUB_HOST  = "192.168.4.1";
const uint16_t HUB_PORT = 80;
const char* HUB_PATH  = "/ws";

// ===== Identity =====
String DEVICE_ID = "VEST-02";
String KIND      = "vest";
String TEAM      = "B";

// Optional hints for hub
String BY_GUN_HINT  = "";
String SHOOTER_TEAM = "";

// ===== Pins =====
const uint8_t TSOP_A_PIN = D2;
const uint8_t TSOP_B_PIN = D5;
const uint8_t HIT_LED    = LED_BUILTIN;

// LED polarity helpers
const bool LED_ACTIVE_LOW = true;
inline void ledOn()  { digitalWrite(HIT_LED, LED_ACTIVE_LOW ? LOW  : HIGH); }
inline void ledOff() { digitalWrite(HIT_LED, LED_ACTIVE_LOW ? HIGH : LOW ); }

// ===== Filters (tuned) =====
const unsigned FILTER_WINDOW_MS   = 70;//12
const unsigned MIN_PULSES_FOR_HIT = 10;//6
const unsigned LED_ON_MS          = 200;

// === Global hit merge ===
const unsigned HIT_COOLDOWN_MS    = 150;
unsigned long lastHitGlobal = 0;

// ===== Shared state (A) =====
volatile unsigned pulseCountA = 0;
volatile unsigned long windowEndA = 0;
unsigned long lastHitA = 0;
unsigned long hitsA = 0;

// ===== Shared state (B) =====
volatile unsigned pulseCountB = 0;
volatile unsigned long windowEndB = 0;
unsigned long lastHitB = 0;
unsigned long hitsB = 0;

// LED timeout
unsigned long ledOffAt = 0;

// ===== Disable/Respawn window =====
bool disabled = false;             // "ميتة" أثناء الريسباون
unsigned long reEnableAt = 0;      // نهاية التعطيل

// ===== WebSocket =====
WebSocketsClient ws;
unsigned long lastPingAt = 0;

// ====== ISRs ======
ICACHE_RAM_ATTR void isrA() {
  unsigned long now = millis();
  if (now >= windowEndA) { pulseCountA = 0; windowEndA = now + FILTER_WINDOW_MS; }
  pulseCountA++;
}
ICACHE_RAM_ATTR void isrB() {
  unsigned long now = millis();
  if (now >= windowEndB) { pulseCountB = 0; windowEndB = now + FILTER_WINDOW_MS; }
  pulseCountB++;
}

// ====== Hub messaging ======
void sendRegister() {
  DynamicJsonDocument doc(256);
  doc["type"]     = "register";
  doc["deviceId"] = DEVICE_ID;
  doc["kind"]     = KIND;
  doc["team"]     = TEAM;
  doc["ts"] = millis();
  String out; serializeJson(doc, out);
  ws.sendTXT(out);
  Serial.println(F("[VEST] Sent register"));
}
void sendPing() {
  DynamicJsonDocument doc(128);
  doc["type"]     = "ping";
  doc["deviceId"] = DEVICE_ID;
  String out; serializeJson(doc, out);
  ws.sendTXT(out);
}
void sendHit(const char* side, unsigned pulses) {
  if (disabled) {
    Serial.println(F("[VEST] Hit ignored (disabled)"));
  } else {
    DynamicJsonDocument doc(384);
    doc["type"]        = "hit";
    doc["vestId"]      = DEVICE_ID;
    doc["teamVictim"]  = TEAM;
    if (BY_GUN_HINT.length())  doc["byGun"]       = BY_GUN_HINT;
    if (SHOOTER_TEAM.length()) doc["teamShooter"] = SHOOTER_TEAM;
    doc["meta"] = String("side=") + side + ", pulses=" + pulses;
    String out; serializeJson(doc, out);
    ws.sendTXT(out);
    Serial.printf("[VEST] Sent hit: %s | pulses=%u\n", side, pulses);
  }
}

// ====== Apply cmd from Hub ======
// ملاحظة: الهب يرسل عادة you_are_hit(ms) ثم لاحقاً revive.
// وندعم أيضاً disable/enable العامة.
void applyDisableMs(unsigned long ms) {
  if (ms == 0) {
    disabled = false;
    reEnableAt = 0;
    ledOff();
  } else {
    disabled = true;
    reEnableAt = millis() + ms;
    ledOn();
  }
  Serial.printf("[VEST] Disabled=%d for %lu ms\n", disabled?1:0, ms);
}

void handleCmd(JsonObject obj) {
  String cmd    = obj["cmd"]      | "";
  String target = obj["deviceId"] | "";
  // نقبل ms أو secs (للتوافق)
  unsigned long ms = 0;
  if (obj.containsKey("ms"))   ms = obj["ms"].as<unsigned long>();
  if (obj.containsKey("secs")) ms = obj["secs"].as<unsigned long>() * 1000UL;

  if (target != DEVICE_ID && target != "ALL") return;

  if (cmd == "you_are_hit" || cmd == "mark_hit" || cmd == "disable_player" || cmd == "disable") {
    if (ms == 0) ms = 10000;   // افتراضي 10s لو ما وصل وقت
    applyDisableMs(ms);
  }
  else if (cmd == "revive" || cmd == "enable") {
    applyDisableMs(0);
  }
  else if (cmd == "set_team") {
    String t = obj["team"] | "";
    if (t == "A" || t == "B") {
      TEAM = t; Serial.printf("[VEST] Team set to %s\n", TEAM.c_str());
    }
  }
}

// ====== WS events ======
void onWsEvent(WStype_t type, uint8_t * payload, size_t len) {
  if (type == WStype_CONNECTED) {
    Serial.println(F("[VEST] WS Connected"));
    sendRegister();
  } else if (type == WStype_DISCONNECTED) {
    Serial.println(F("[VEST] WS Disconnected"));
  } else if (type == WStype_TEXT) {
    DynamicJsonDocument d(512);
    if (deserializeJson(d, payload, len)) return;
    String t = d["type"] | "";
    if (t == "cmd") handleCmd(d.as<JsonObject>());
  }
}

// ====== Setup / Loop ======
void setup() {
  Serial.begin(115200);
  delay(20);
  Serial.println();
  Serial.println(F("BattleBeam Dual-TSOP Vest (ESP8266) starting..."));

  pinMode(TSOP_A_PIN, INPUT);
  pinMode(TSOP_B_PIN, INPUT);
  pinMode(HIT_LED, OUTPUT);
  ledOff();

  attachInterrupt(digitalPinToInterrupt(TSOP_A_PIN), isrA, FALLING);
  attachInterrupt(digitalPinToInterrupt(TSOP_B_PIN), isrB, FALLING);

  // Wi-Fi
  WiFi.mode(WIFI_STA);
  WiFi.begin(WIFI_SSID, WIFI_PASS);
  WiFi.setSleepMode(WIFI_NONE_SLEEP);     // يقلّل تأخير الشبكة
  Serial.printf("[VEST] Connecting to WiFi %s", WIFI_SSID);
  unsigned long t0 = millis();
  while (WiFi.status() != WL_CONNECTED) {
    delay(250); Serial.print(".");
    if (millis() - t0 > 12000) break;
  }
  Serial.println();
  Serial.print(F("[VEST] IP: ")); Serial.println(WiFi.localIP());

  // WebSocket
  ws.begin(HUB_HOST, HUB_PORT, HUB_PATH);
  ws.onEvent(onWsEvent);
  ws.setReconnectInterval(2000);
  ws.enableHeartbeat(15000, 3000, 2);     // يحافظ على الاتصال
}

void loop() {
  ws.loop();

  // Ping every 5s
  if (millis() - lastPingAt > 5000) {
    lastPingAt = millis();
    if (WiFi.status() == WL_CONNECTED) sendPing();
  }

  // Re-enable after disable timeout (انتهى الريسباون)
  if (disabled && millis() >= reEnableAt) {
    applyDisableMs(0);
    Serial.println(F("[VEST] Re-enabled after timeout"));
  }

  unsigned long now = millis();

  // === Process sensor A ===
  if (windowEndA && now >= windowEndA) {
    noInterrupts();
    unsigned pc = pulseCountA; pulseCountA = 0; windowEndA = 0;
    interrupts();

    if (pc >= MIN_PULSES_FOR_HIT && (now - lastHitGlobal) > HIT_COOLDOWN_MS) {
      lastHitA = now; hitsA++;
      lastHitGlobal = now;
      Serial.print(F("HIT LEFT  | pulses=")); Serial.println(pc);
      if (!disabled) {
        ledOn(); ledOffAt = now + LED_ON_MS;
        sendHit("LEFT", pc);
      } else {
        Serial.println(F("[VEST] (ignored due to disabled)"));
      }
    }
  }

  // === Process sensor B ===
  if (windowEndB && now >= windowEndB) {
    noInterrupts();
    unsigned pc = pulseCountB; pulseCountB = 0; windowEndB = 0;
    interrupts();

    if (pc >= MIN_PULSES_FOR_HIT && (now - lastHitGlobal) > HIT_COOLDOWN_MS) {
      lastHitB = now; hitsB++;
      lastHitGlobal = now;
      Serial.print(F("HIT RIGHT | pulses=")); Serial.println(pc);
      if (!disabled) {
        ledOn(); ledOffAt = now + LED_ON_MS;
        sendHit("RIGHT", pc);
      } else {
        Serial.println(F("[VEST] (ignored due to disabled)"));
      }
    }
  }

  // === Turn LED off after timeout ===
  if (ledOffAt && now >= ledOffAt) {
    ledOff(); ledOffAt = 0;
  }

  delay(2);
}
