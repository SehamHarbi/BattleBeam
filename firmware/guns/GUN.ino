// Gun (ESP32) 

#include <Arduino.h>
#include <WiFi.h>
#include <WebSocketsClient.h>
#include <ArduinoJson.h>
#include <IRremote.hpp> 
#include "driver/ledc.h" 

// --- Wi-Fi / Hub ---
const char* WIFI_SSID = "BattleBeam";
const char* WIFI_PASS = "battle1234";
const char* HUB_IP = "192.168.4.1";
const uint16_t HUB_PORT = 80;
const char* HUB_PATH = "/ws";

// --- Identity ---
String DEVICE_ID = "GUN-02";
String KIND = "gun";
String TEAM = "A";

// --- Pins  ---
const int TRIGGER_PIN = 18; 
const int IR_PIN = 32; 
const int LED_PIN = 2; 

// --- IR NEC Code ---
const uint32_t NEC_CODE_TO_SEND = 0x00BF06F9;
const int IR_REPS = 2; // عدد مرات تكرار إرسال الكود لزيادة الموثوقية
const int IR_WAIT_MS = 20;  

// --- Timing / debounce ---
const unsigned DEBOUNCE_MS = 20;
const unsigned REFIRE_MS = 200;
unsigned long lastDebounceTime = 0;
unsigned long lastTriggerAt = 0;
unsigned long lastPingAt = 0;
unsigned long lastRegisterAt = 0; 

// --- Button state  ---
int rawState = HIGH, stableState = HIGH, lastStableState = HIGH;

// --- Disable state  ---
bool disabled = false;
unsigned long reEnableAt = 0;

// --- WebSocket ---
WebSocketsClient webSocket;

// --- IR Sender Object ---
#define SEND_IR_PIN IR_PIN

// --- WS helpers (Register, Ping, ShotFired) ---
void sendRegister() {
  DynamicJsonDocument doc(256);
  doc["type"] = "register"; doc["deviceId"] = DEVICE_ID; doc["kind"] = KIND;
  doc["team"] = TEAM; doc["ts"] = millis();
  String out; serializeJson(doc, out); webSocket.sendTXT(out);
  Serial.println("[GUN] Sent register");
}
void sendPing() {
  DynamicJsonDocument doc(128);
  doc["type"] = "ping"; doc["deviceId"] = DEVICE_ID;
  String out; serializeJson(doc, out); webSocket.sendTXT(out);
}
void sendShotFired() {
  DynamicJsonDocument doc(192);
  doc["type"] = "shot_fired"; doc["deviceId"] = DEVICE_ID;
  doc["team"] = TEAM; doc["ts"] = millis();
  String out; serializeJson(doc, out); webSocket.sendTXT(out);
  Serial.println("[GUN] Sent shot_fired");
}

// --- Handle Hub cmds ---
void handleCmd(JsonObject doc) {
  String cmd = doc["cmd"] | "";
  String target = doc["deviceId"] | "";
  int ms = 0;
  if (doc.containsKey("ms")) ms = doc["ms"].as<int>();
  if (doc.containsKey("secs")) ms = doc["secs"].as<int>() * 1000;

  if (target != DEVICE_ID && target != "ALL") return;

  if (cmd == "disable" || cmd == "disable_gun" || cmd == "disable_player") {
    if (ms <= 0) ms = 10000;
    disabled = true;
    reEnableAt = millis() + (unsigned long)ms;
    digitalWrite(LED_PIN, HIGH);
    Serial.printf("[GUN] CMD: %s for %d ms (disabled=1)\n", cmd.c_str(), ms);
  }
  else if (cmd == "enable") {
    disabled = false;
    reEnableAt = 0;
    digitalWrite(LED_PIN, LOW);
    Serial.println("[GUN] CMD: enable (disabled=0)");
  }
  else if (cmd == "set_team") {
    String t = doc["team"] | "";
    if (t == "A" || t == "B") {
      TEAM = t;
      Serial.printf("[GUN] Team set to %s\n", TEAM.c_str());
      sendRegister(); 
    }
  }
}

// --- WS event  ---
void webSocketEvent(WStype_t type, uint8_t * payload, size_t length) {
  if (type == WStype_CONNECTED) {
    Serial.println("[GUN] WS connected");
    sendRegister();
  } else if (type == WStype_DISCONNECTED) {
    Serial.println("[GUN] WS disconnected");
  } else if (type == WStype_TEXT) {
    DynamicJsonDocument d(1024);
    if (deserializeJson(d, payload, length)) {
      Serial.println("[GUN] WS JSON parse failed");
      return;
    }
    String t = d["type"] | "";
    if (t == "cmd") handleCmd(d.as<JsonObject>());
  }
}

// --- IR shot  ---
void fireShot() {
  if (disabled) {
    Serial.println("[GUN] FIRE blocked (disabled)");
    return;
  }
  
  
  for (int k = 0; k < IR_REPS; k++) { 
    IrSender.sendNEC(NEC_CODE_TO_SEND, 32); 
    delay(IR_WAIT_MS);
  }
}

void setupLEDC() {
  
}

void setup() {
  Serial.begin(115200);
  delay(50);
  Serial.println();
  Serial.println("[GUN] Starting (NEC Code 194 Mode)...");

  pinMode(TRIGGER_PIN, INPUT_PULLUP);
  pinMode(LED_PIN, OUTPUT);
  digitalWrite(LED_PIN, LOW);

  
  IrSender.begin(SEND_IR_PIN); 

  // WiFi
  WiFi.mode(WIFI_STA);
  WiFi.begin(WIFI_SSID, WIFI_PASS);
  Serial.printf("[GUN] Connecting to WiFi %s", WIFI_SSID);
  unsigned long t0 = millis();
  while (WiFi.status() != WL_CONNECTED) {
    delay(250); Serial.print(".");
    if (millis() - t0 > 12000) break;
  }
  Serial.println();
  Serial.print("[GUN] IP: "); Serial.println(WiFi.localIP());

  // WebSocket
  webSocket.begin(HUB_IP, HUB_PORT, HUB_PATH);
  webSocket.onEvent(webSocketEvent);
  webSocket.setReconnectInterval(2000);
}

void loop() {
  webSocket.loop();

  
  if (webSocket.isConnected() && millis() - lastRegisterAt > 7000) {
    lastRegisterAt = millis();
    sendRegister();
  }

  // ping كل 5 ثواني
  if (millis() - lastPingAt > 5000) {
    lastPingAt = millis();
    if (webSocket.isConnected()) sendPing();
  }

  // auto re-enable
  if (disabled && millis() >= reEnableAt) {
    disabled = false;
    reEnableAt = 0;
    digitalWrite(LED_PIN, LOW);
    Serial.println("[GUN] Re-enabled after timeout");
  }

  int reading = digitalRead(TRIGGER_PIN); 
  if (reading != rawState) {
    rawState = reading;
    lastDebounceTime = millis();
  }

  if ((millis() - lastDebounceTime) > DEBOUNCE_MS) {
    if (stableState != rawState) {
      lastStableState = stableState;
      stableState = rawState;

      // ضغط الزناد
      if (lastStableState == HIGH && stableState == LOW) {
        unsigned long now = millis();

        if (!disabled && (now - lastTriggerAt >= REFIRE_MS)) {
          
          if (webSocket.isConnected()) sendShotFired();

          digitalWrite(LED_PIN, HIGH);
          fireShot(); 
          digitalWrite(LED_PIN, LOW);

          lastTriggerAt = now;
        } else {
          if (disabled) Serial.println("[GUN] Press ignored: disabled");
          else Serial.println("[GUN] Press ignored: REFIRE guard");
        }
      }
    }
  }

  delay(2);
}