// BattleBeam Vest (ESP8266) — Final Code (Optimized for Weak Signals & Stability)

#include <Arduino.h>
#include <ESP8266WiFi.h>
#include <WebSocketsClient.h>
#include <ArduinoJson.h>

// ===== Wi-Fi / Hub =====
const char* WIFI_SSID = "BattleBeam";
const char* WIFI_PASS = "battle1234";
const char* HUB_HOST = "192.168.4.1";
const uint16_t HUB_PORT = 80;
const char* HUB_PATH = "/ws";

// ===== Identity / Pins / Shared State =====
String DEVICE_ID = "VEST-01";
String KIND = "vest";
String TEAM = "A";

// Optional hints for hub
String BY_GUN_HINT = "";
String SHOOTER_TEAM = "";

// ===== Pins =====
const uint8_t TSOP_A_PIN = D2;
const uint8_t TSOP_B_PIN = D5;
const uint8_t HIT_LED = LED_BUILTIN;

// LED polarity helpers
const bool LED_ACTIVE_LOW = true;
inline void ledOn() { digitalWrite(HIT_LED, LED_ACTIVE_LOW ? LOW : HIGH); }
inline void ledOff() { digitalWrite(HIT_LED, LED_ACTIVE_LOW ? HIGH : LOW ); }

// ===== Filters (FINAL CONFIG) =====
const unsigned FILTER_WINDOW_MS = 70;
const unsigned MIN_PULSES_FOR_HIT = 3; // 🚀 عتبة منخفضة للاستجابة لكود NEC 194
const unsigned LED_ON_MS = 200;

// === Global hit merge ===
// ⬅️ تم رفعه إلى 500ms لضمان تسجيل طلقة واحدة فقط لكل ضغطة زناد
const unsigned HIT_COOLDOWN_MS = 500;
unsigned long lastHitGlobal = 0;

// ===== Shared state (A) & (B) =====
volatile unsigned pulseCountA = 0; volatile unsigned long windowEndA = 0; unsigned long lastHitA = 0; unsigned long hitsA = 0;
volatile unsigned pulseCountB = 0; volatile unsigned long windowEndB = 0; unsigned long lastHitB = 0; unsigned long hitsB = 0;

// LED timeout
unsigned long ledOffAt = 0;

// ===== Disable/Respawn window =====
bool disabled = false;
unsigned long reEnableAt = 0;

// ===== WebSocket =====
WebSocketsClient ws;
unsigned long lastPingAt = 0;

// ====== ISRs (No changes) ======
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

// ====== Hub messaging / Apply cmd ======
void sendRegister() {
  DynamicJsonDocument doc(256);
  doc["type"] = "register"; doc["deviceId"] = DEVICE_ID; doc["kind"] = KIND;
  doc["team"] = TEAM; doc["ts"] = millis();
  String out; serializeJson(doc, out); ws.sendTXT(out);
  Serial.println(F("[VEST] Sent register"));
}
void sendPing() {
  DynamicJsonDocument doc(128);
  doc["type"] = "ping"; doc["deviceId"] = DEVICE_ID;
  String out; serializeJson(doc, out); ws.sendTXT(out);
}
void sendHit(const char* side, unsigned pulses) {
  if (disabled) {
    Serial.println(F("[VEST] Hit ignored (disabled)"));
  } else {
    // ⬅️ شرط إضافي لضمان أن WS متصل قبل محاولة الإرسال
    if (!ws.isConnected()) { 
      Serial.println(F("[VEST] WARN: WS not connected, hit NOT sent."));
      ledOn(); ledOffAt = millis() + LED_ON_MS; // نضيء LED محلياً حتى لو فشل الإرسال
      return; 
    }
    
    DynamicJsonDocument doc(384);
    doc["type"] = "hit"; doc["vestId"] = DEVICE_ID;
    doc["teamVictim"] = TEAM;
    if (BY_GUN_HINT.length()) doc["byGun"] = BY_GUN_HINT;
    if (SHOOTER_TEAM.length()) doc["teamShooter"] = SHOOTER_TEAM;
    doc["meta"] = String("side=") + side + ", pulses=" + pulses;
    String out; serializeJson(doc, out); ws.sendTXT(out);
    Serial.printf("[VEST] Sent hit: %s | pulses=%u\n", side, pulses);
  }
}

void applyDisableMs(unsigned long ms) {
  if (ms == 0) {
    disabled = false; reEnableAt = 0; ledOff();
  } else {
    disabled = true; reEnableAt = millis() + ms; ledOn();
  }
  Serial.printf("[VEST] Disabled=%d for %lu ms\n", disabled?1:0, ms);
}

void handleCmd(JsonObject obj) {
  String cmd = obj["cmd"] | "";
  String target = obj["deviceId"] | "";
  unsigned long ms = 0;
  if (obj.containsKey("ms")) ms = obj["ms"].as<unsigned long>();
  if (obj.containsKey("secs")) ms = obj["secs"].as<unsigned long>() * 1000UL;

  if (target != DEVICE_ID && target != "ALL") return;

  if (cmd == "you_are_hit" || cmd == "mark_hit" || cmd == "disable_player" || cmd == "disable") {
    if (ms == 0) ms = 10000;
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

// ====== WS events (No changes) ======
void onWsEvent(WStype_t type, uint8_t * payload, size_t len) {
  if (type == WStype_CONNECTED) {
    Serial.println(F("[VEST] WS Connected")); sendRegister();
  } else if (type == WStype_DISCONNECTED) {
    Serial.println(F("[VEST] WS Disconnected"));
  } else if (type == WStype_TEXT) {
    DynamicJsonDocument d(512);
    if (deserializeJson(d, payload, len)) return;
    String t = d["type"] | "";
    if (t == "cmd") handleCmd(d.as<JsonObject>());
  }
}

// ====== Setup / Loop (MODIFIED) ======
void setup() {
  Serial.begin(115200);
  delay(20);
  Serial.println();
  Serial.println(F("BattleBeam Dual-TSOP Vest (ESP8266) starting..."));

  pinMode(TSOP_A_PIN, INPUT);
  pinMode(TSOP_B_PIN, INPUT);
  pinMode(HIT_LED, OUTPUT);
  ledOff();

  // ❌ تم التعليق: لا نربط المقاطعات هنا لتجنب مشاكل ISR أثناء اتصال Wi-Fi 
  // attachInterrupt(digitalPinToInterrupt(TSOP_A_PIN), isrA, FALLING);
  // attachInterrupt(digitalPinToInterrupt(TSOP_B_PIN), isrB, FALLING);

  // Wi-Fi
  WiFi.mode(WIFI_STA);
  WiFi.begin(WIFI_SSID, WIFI_PASS);
  WiFi.setSleepMode(WIFI_NONE_SLEEP);
  Serial.printf("[VEST] Connecting to WiFi %s", WIFI_SSID);
  unsigned long t0 = millis();
  while (WiFi.status() != WL_CONNECTED) {
    delay(250); Serial.print(".");
    if (millis() - t0 > 12000) break;
  }
  Serial.println();
  Serial.print(F("[VEST] IP: ")); Serial.println(WiFi.localIP());
  
  // ⬅️ تفعيل المستشعرات بعد استقرار Wi-Fi لحل مشكلة عدم الاستجابة للطلقات الأولى
  Serial.println(F("[VEST] Attaching ISRs..."));
  attachInterrupt(digitalPinToInterrupt(TSOP_A_PIN), isrA, FALLING);
  attachInterrupt(digitalPinToInterrupt(TSOP_B_PIN), isrB, FALLING);

  // WebSocket
  ws.begin(HUB_HOST, HUB_PORT, HUB_PATH);
  ws.onEvent(onWsEvent);
  ws.setReconnectInterval(2000);
  ws.enableHeartbeat(15000, 3000, 2);
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

    // نستخدم التهدئة العالمية لدمج الطلقات (500ms)
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

    // نستخدم التهدئة العالمية لدمج الطلقات (500ms)
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