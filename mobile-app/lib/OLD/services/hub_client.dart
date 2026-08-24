// lib/core/services/hub_client.dart
import 'dart:async';
import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:uuid/uuid.dart';
import 'package:web_socket_channel/io.dart';

import '../protocol/protocol.dart';
import '../protocol/messages.dart';

class HubClient {
  // غيّري عنوان الهب
  static const String hubUrl = "ws://192.168.4.1:80/ws";

  HubClient._();
  static final HubClient I = HubClient._();

  IOWebSocketChannel? _ch;
  Timer? _pingTimer;

  // player/session
  String? uuid;
  String playerName = "";
  String team = ""; // "A" or "B"
  String? leaderUuid;

  // cache
  List<DeviceItem> devices = [];

  // events للـ UI
  final _events = StreamController<Map<String,dynamic>>.broadcast();
  Stream<Map<String,dynamic>> get events => _events.stream;
  bool get isConnected => _ch != null;
  bool get isLeader => leaderUuid != null && leaderUuid == uuid;

  Future<void> connect({required String name, required String teamCode, bool tryClaimLeader = true}) async {
    playerName = name;
    team = teamCode;

    final prefs = await SharedPreferences.getInstance();
    uuid = prefs.getString('mobile_uuid') ?? const Uuid().v4();
    await prefs.setString('mobile_uuid', uuid!);

    _ch = IOWebSocketChannel.connect(Uri.parse(hubUrl));
    _ch!.stream.listen(_onMessage, onDone: _onDone, onError: _onError);

    // register_mobile
    final reg = RegisterMobile(uuid: uuid!, playerName: playerName, team: team);
    _send(reg.toJson());

    // حاول يطالب القيادة (أول واحد)
    if (tryClaimLeader) {
      Future.delayed(const Duration(milliseconds: 500), (){
        _send(ClaimLeader(uuid!).toJson());
      });
    }

    _startPing();
  }

  void _startPing(){
    _pingTimer?.cancel();
    _pingTimer = Timer.periodic(const Duration(seconds: 10), (_){
      _send(Ping(uuid!).toJson());
    });
  }

  void disconnect(){
    _pingTimer?.cancel();
    _pingTimer = null;
    _ch?.sink.close();
    _ch = null;
  }

  void selectGun(String deviceId){
    _send(SelectDevice(uuid: uuid!, kind: DeviceKind.gun, deviceId: deviceId).toJson());
  }
  void selectVest(String deviceId){
    _send(SelectDevice(uuid: uuid!, kind: DeviceKind.vest, deviceId: deviceId).toJson());
  }

  void setRulesAndStart({required int targetScore, int timeLimitSec = 0}){
    if (!isLeader) return;
    _send(SetRules(targetScore: targetScore, timeLimitSec: timeLimitSec).toJson());
    _send(StartGame().toJson());
  }

  void _send(Map<String,dynamic> json){
    _ch?.sink.add(jsonEncode(json));
  }

  // استقبال
  void _onMessage(dynamic payload){
    Map<String,dynamic> parsed;
    try {
      parsed = parseHubMessage(payload);
    } catch (e) {
      _events.add({ "type":"parse_error", "error": e.toString(), "raw": payload });
      return;
    }

    final kind = parsed["kind"];
    final data = parsed["data"];

    switch (kind) {
      case MsgType.devicesList:
        devices = (data as DevicesList).devices;
        _events.add({ "type": MsgType.devicesList, "devices": devices });
        break;

      case MsgType.leaderAssigned:
        leaderUuid = (data as LeaderAssigned).leaderUuid;
        _events.add({ "type": MsgType.leaderAssigned, "leader_uuid": leaderUuid });
        break;

      case MsgType.disableDevice:
      case MsgType.deviceState:
      case MsgType.hitNotification:
      case MsgType.gameStarted:
      case MsgType.scoreUpdate:
      case MsgType.gameOver:
        // مرر كما هو (حول لفورمات مبسطة للـ UI إذا حبيتي)
        _events.add({ "type": kind, "data": data });
        break;

      default:
        _events.add({ "type": "unknown", "raw": data });
    }
  }

  void _onDone(){ _events.add({ "type": "ws_closed" }); }
  void _onError(e){ _events.add({ "type": "ws_error", "error": e.toString() }); }
}
