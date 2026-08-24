// موديلات الرسائل + toJson/fromJson + validation
// lib/core/protocol/messages.dart
import 'dart:convert';
import 'protocol.dart';

/// فائدة: validate presence
void _require(Map m, List<String> keys){
  for (final k in keys) {
    if (!m.containsKey(k)) {
      throw FormatException("Missing key '$k' in ${m[Keys.type]}");
    }
  }
}

/// =======
/// طلبات من التطبيق إلى الهب
/// =======

class RegisterMobile {
  final String uuid;
  final String playerName;
  final String team; // "A" | "B"
  RegisterMobile({required this.uuid, required this.playerName, required this.team});

  Map<String,dynamic> toJson() => {
    Keys.type: MsgType.registerMobile,
    Keys.uuid: uuid,
    Keys.playerName: playerName,
    Keys.team: team,
  };
}

class SelectDevice {
  final String uuid;
  final DeviceKind kind;
  final String deviceId;
  SelectDevice({required this.uuid, required this.kind, required this.deviceId});

  Map<String,dynamic> toJson() => {
    Keys.type: MsgType.selectDevice,
    Keys.uuid: uuid,
    Keys.deviceKind: kind.name, // "gun" / "vest"
    Keys.deviceId: deviceId,
  };
}

class ClaimLeader {
  final String uuid;
  ClaimLeader(this.uuid);
  Map<String,dynamic> toJson() => {
    Keys.type: MsgType.claimLeader,
    Keys.uuid: uuid,
  };
}

class SetRules {
  final int targetScore;
  final int timeLimitSec;
  SetRules({required this.targetScore, this.timeLimitSec = 0});
  Map<String,dynamic> toJson() => {
    Keys.type: MsgType.setRules,
    Keys.targetScore: targetScore,
    Keys.timeLimitSec: timeLimitSec,
  };
}

class StartGame {
  Map<String,dynamic> toJson() => { Keys.type: MsgType.startGame };
}

class Ping {
  final String uuid;
  Ping(this.uuid);
  Map<String,dynamic> toJson() => { Keys.type: MsgType.ping, Keys.uuid: uuid };
}

/// =======
/// ردود/أحداث من الهب إلى التطبيق
/// =======

class DeviceItem {
  final String id;
  final DeviceKind kind;
  final String team;
  final String status; // enabled|disabled
  DeviceItem({required this.id, required this.kind, required this.team, required this.status});

  factory DeviceItem.fromJson(Map m){
    _require(m, ["id","kind","team","status"]);
    final kindStr = m["kind"].toString();
    final dk = (kindStr == "gun") ? DeviceKind.gun : DeviceKind.vest;
    return DeviceItem(
      id: m["id"], kind: dk, team: m["team"], status: m["status"]
    );
  }

  Map<String,dynamic> toJson() => {
    "id": id, "kind": kind.name, "team": team, "status": status
  };
}

class DevicesList {
  final List<DeviceItem> devices;
  DevicesList(this.devices);

  factory DevicesList.fromJson(Map m){
    _require(m, [Keys.devices]);
    final list = (m[Keys.devices] as List? ?? []);
    return DevicesList(list.map((e)=> DeviceItem.fromJson(Map<String,dynamic>.from(e))).toList());
  }
}

class LeaderAssigned {
  final String leaderUuid;
  LeaderAssigned(this.leaderUuid);

  factory LeaderAssigned.fromJson(Map m){
    _require(m, [Keys.leaderUuid]);
    return LeaderAssigned(m[Keys.leaderUuid]);
  }
}

class HitNotification {
  final String victimDeviceId;
  final String victimTeam;
  final String shooterDeviceId;
  final String shooterTeam;
  final String timestamp;

  HitNotification({
    required this.victimDeviceId,
    required this.victimTeam,
    required this.shooterDeviceId,
    required this.shooterTeam,
    required this.timestamp,
  });

  factory HitNotification.fromJson(Map m){
    _require(m, [Keys.victimDeviceId, Keys.victimTeam, Keys.shooterDeviceId, Keys.shooterTeam, Keys.timestamp]);
    return HitNotification(
      victimDeviceId: m[Keys.victimDeviceId],
      victimTeam:     m[Keys.victimTeam],
      shooterDeviceId:m[Keys.shooterDeviceId],
      shooterTeam:    m[Keys.shooterTeam],
      timestamp:      m[Keys.timestamp],
    );
  }
}

class DisableDevice {
  final String deviceId;
  final int durationSeconds;
  DisableDevice(this.deviceId, this.durationSeconds);

  factory DisableDevice.fromJson(Map m){
    _require(m, [Keys.deviceId, Keys.durationSeconds]);
    return DisableDevice(m[Keys.deviceId], m[Keys.durationSeconds]);
  }
}

class DeviceState {
  final DeviceItem device;
  DeviceState(this.device);

  factory DeviceState.fromJson(Map m){
    _require(m, ["device"]);
    return DeviceState(DeviceItem.fromJson(Map<String,dynamic>.from(m["device"])));
  }
}

class GameStarted {
  final int targetScore;
  final int timeLimitSec;
  GameStarted({required this.targetScore, required this.timeLimitSec});

  factory GameStarted.fromJson(Map m){
    _require(m, [Keys.rules]);
    final r = Map<String,dynamic>.from(m[Keys.rules]);
    _require(r, [Keys.targetScore, Keys.timeLimitSec]);
    return GameStarted(targetScore: r[Keys.targetScore], timeLimitSec: r[Keys.timeLimitSec]);
  }
}

class ScoreUpdate {
  final int scoreA;
  final int scoreB;
  final String? lastEvent;
  ScoreUpdate({required this.scoreA, required this.scoreB, this.lastEvent});

  factory ScoreUpdate.fromJson(Map m){
    _require(m, [Keys.score]);
    final s = Map<String,dynamic>.from(m[Keys.score]);
    final a = (s["A"] ?? 0) as int;
    final b = (s["B"] ?? 0) as int;
    return ScoreUpdate(scoreA: a, scoreB: b, lastEvent: m["last_event"]?.toString());
  }
}

class GameOver {
  final String winnerTeam;
  final int scoreA;
  final int scoreB;
  GameOver({required this.winnerTeam, required this.scoreA, required this.scoreB});

  factory GameOver.fromJson(Map m){
    _require(m, [Keys.winnerTeam, Keys.score]);
    final s = Map<String,dynamic>.from(m[Keys.score]);
    final a = (s["A"] ?? 0) as int;
    final b = (s["B"] ?? 0) as int;
    return GameOver(winnerTeam: m[Keys.winnerTeam], scoreA: a, scoreB: b);
  }
}

/// =======
/// مُفسِّر رسائل الهب العامة (incoming)
/// يرجّع خريطة فيها { kind: "...", data: object } لسهولة المعالجة في HubClient
/// =======
Map<String,dynamic> parseHubMessage(dynamic payload){
  // payload: String JSON
  Map<String,dynamic> m;
  try { m = jsonDecode(payload); }
  catch (_){ throw FormatException("Invalid JSON from hub"); }

  final t = m[Keys.type]?.toString() ?? "";
  switch (t) {
    case MsgType.devicesList:
      return {"kind": MsgType.devicesList, "data": DevicesList.fromJson(m)};
    case MsgType.leaderAssigned:
      return {"kind": MsgType.leaderAssigned, "data": LeaderAssigned.fromJson(m)};
    case MsgType.hitNotification:
      return {"kind": MsgType.hitNotification, "data": HitNotification.fromJson(m)};
    case MsgType.disableDevice:
      return {"kind": MsgType.disableDevice, "data": DisableDevice.fromJson(m)};
    case MsgType.deviceState:
      return {"kind": MsgType.deviceState, "data": DeviceState.fromJson(m)};
    case MsgType.gameStarted:
      return {"kind": MsgType.gameStarted, "data": GameStarted.fromJson(m)};
    case MsgType.scoreUpdate:
      return {"kind": MsgType.scoreUpdate, "data": ScoreUpdate.fromJson(m)};
    case MsgType.gameOver:
      return {"kind": MsgType.gameOver, "data": GameOver.fromJson(m)};
    default:
      // لو نوع غير معروف، رجّع الخريطة نفسها بدون parsing
      return {"kind": t.isEmpty ? "unknown" : t, "data": m};
  }
}
