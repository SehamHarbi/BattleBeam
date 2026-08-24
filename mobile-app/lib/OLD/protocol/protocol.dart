 // ثوابت وأنواع الرسائل + مفاتيح JSON
 // lib/core/protocol/protocol.dart
class MsgType {
  static const registerMobile = "register_mobile";
  static const selectDevice   = "select_device";
  static const claimLeader    = "claim_leader";
  static const setRules       = "set_rules";
  static const startGame      = "start_game";
  static const ping           = "ping";

  static const devicesList    = "devices_list";
  static const leaderAssigned = "leader_assigned";
  static const hitNotification= "hit_notification";
  static const disableDevice  = "disable_device";
  static const deviceState    = "device_state";
  static const scoreUpdate    = "score_update";
  static const gameStarted    = "game_started";
  static const gameOver       = "game_over";
}

class Keys {
  static const type      = "type";
  static const uuid      = "uuid";
  static const playerName= "player_name";
  static const team      = "team";

  static const deviceKind= "device_kind"; // gun | vest
  static const deviceId  = "device_id";
  static const devices   = "devices";
  static const status    = "status";      // enabled | disabled

  static const targetScore   = "target_score";
  static const timeLimitSec  = "time_limit_sec";

  static const leaderUuid    = "leader_uuid";

  static const victimDeviceId = "victim_device_id";
  static const victimTeam     = "victim_team";
  static const shooterDeviceId= "shooter_device_id";
  static const shooterTeam    = "shooter_team";
  static const timestamp      = "timestamp";

  static const durationSeconds= "duration_seconds";
  static const remaining      = "remaining";

  static const score          = "score"; // {"A":int,"B":int}
  static const rules          = "rules";
  static const winnerTeam     = "winner_team";
}

enum DeviceKind { gun, vest }
