// game_page.dart
// صفحة عرض السكور أثناء اللعب + منطق الـ Respawn (YOU ARE OUT)
// + دعم restore_state بدون أي بانرات اتصال
// + دعم reconnect تلقائي عند قطع الواي فاي/WS
// + END GAME يرجع يشتغل بعد الرجوع (reset _endRequested)

import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:web_socket_channel/web_socket_channel.dart';
import 'package:shared_preferences/shared_preferences.dart';

class GamePage2 extends StatefulWidget {
  const GamePage2({super.key});

  @override
  State<GamePage2> createState() => _GamePage2State();
}

class _GamePage2State extends State<GamePage2> {
  // عدد النقاط المطلوب للفوز (تيجي من صفحة اللوبّي)
  late int targetScore;

  // أسماء اللاعبين لكل فريق (تيجي من اللوبّي)
  late List<String> teamAPlayers;
  late List<String> teamBPlayers;

  // السكور الحالي لكل فريق
  late int teamAScore;
  late int teamBScore;

  // هل أنا الليدر ولا لا؟ (تيجي من اللوبّي)
  bool iAmLeader = false;

  // مين الفريق الفايز لما تنتهي القيم ('A' أو 'B')
  String? winnerTeam;

  // خط Jaro من Google Fonts
  final String jaro = GoogleFonts.jaro().fontFamily ?? 'Jaro';

  // ===== WebSocket (الربط مع الهب) =====
  WebSocketChannel? _ch;
  bool _wsInited = false; // عشان ما نفتح WS أكثر من مرة بالغلط
  Timer? _pingTimer; // لإرسال ping دوري للهَب

  // ===== Reconnect =====
  Timer? _reconnectTimer;
  int _reconnectAttempts = 0;
  bool _isReconnecting = false;

  // بيانات اللاعب (للـ register مع الهب)
  String myId = '';
  String myName = 'Player';
  String myTeam = 'A';

  // ===== حالة اللاعب الخاصة به (من restore_state) =====
  bool sessionActive = true; // هل في جلسة شغّالة
  int myScore = 0; // سكور اللاعب الفردي
  String? myGunId; // المسدس المرتبط
  String? myVestId; // السترة المرتبطة

  // ===== منطق الـ Respawn (الموت المؤقت) =====
  bool isDead = false; // هل اللاعب ميت حاليًا؟ (لهذا الجوال)
  int respawnRemaining = 0; // عدد الثواني المتبقية للعودة للحياة
  Timer? _respawnTimer; // المؤقّت اللي ينقص العداد كل ثانية

  // لاعبين ميتين حاليًا (بالاسم) عشان X تطلع عند الكل
  final Set<String> deadPlayers = {};

  // عشان ما يضغط END GAME أكثر من مرّة
  bool _endRequested = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();

    final args = (ModalRoute.of(context)!.settings.arguments as Map?) ?? {};

    iAmLeader = (args['i_am_leader'] as bool?) ?? false;
    targetScore = _asInt(args['target_score'], fallback: 5);

    teamAPlayers = (args['team_a_players'] as List?)
            ?.map((e) => e.toString())
            .toList() ??
        const ['Player 1', 'Player 2', 'Player 3'];

    teamBPlayers = (args['team_b_players'] as List?)
            ?.map((e) => e.toString())
            .toList() ??
        const ['Player 4', 'Player 5', 'Player 6'];

    teamAScore = _asInt(args['team_a_score'], fallback: 0);
    teamBScore = _asInt(args['team_b_score'], fallback: 0);

    myName = (args['name'] as String?)?.trim().isNotEmpty == true
        ? (args['name'] as String)
        : myName;
    myTeam = (args['team'] as String?)?.toUpperCase() == 'B' ? 'B' : 'A';

    _checkWinner();

    if (!_wsInited) {
      _wsInited = true;
      _prepareIdentityAndConnect();
    }
  }

  Future<void> _prepareIdentityAndConnect() async {
    final p = await SharedPreferences.getInstance();

    myId =
        p.getString('player_id') ?? DateTime.now().millisecondsSinceEpoch.toString();
    await p.setString('player_id', myId);

    if (p.getString('player_name') == null && myName.isNotEmpty) {
      await p.setString('player_name', myName);
    }

    await p.setString('player_team', myTeam);

    _connectWs();
  }

  void _safeSend(Map<String, dynamic> obj) {
    try {
      _ch?.sink.add(jsonEncode(obj));
    } catch (_) {
      // إذا فشل الإرسال غالبًا القناة مقفولة → حاول reconnect
      _scheduleReconnect();
    }
  }

  void _connectWs() {
    // اقفل القديم لو موجود (مهم عشان ما يصير WS ثاني)
    try {
      _ch?.sink.close();
    } catch (_) {}
    _ch = null;

    _ch = WebSocketChannel.connect(Uri.parse('ws://192.168.4.1/ws'));

    // بمجرد ما نرجع اتصال: خلي زر END GAME يرجع يشتغل
    _endRequested = false;

    // register
    _safeSend({
      'type': 'register',
      'deviceId': myId,
      'kind': 'app',
      'team': myTeam,
      'name': myName,
    });

    // اطلب السكور الحالي
    _safeSend({'type': 'get_score'});

    // (اختياري مفيد) اطلب الأجهزة لو عندكم صفحة تربط أسلحة/سترات
    _safeSend({'type': 'get_devices'});

    // ping دوري
    _pingTimer?.cancel();
    _pingTimer = Timer.periodic(const Duration(seconds: 5), (_) {
      _safeSend({'type': 'ping', 'deviceId': myId});
    });

    // اسمع الرسائل
    _ch!.stream.listen((raw) {
      final msg = jsonDecode(raw);

      switch (msg['type']) {
        case 'score_update':
          {
            final t = (msg['team'] ?? '').toString().toUpperCase();
            final d = (msg['delta'] ?? 0) is num ? (msg['delta'] as num).toInt() : 0;
            if (d == 0) return;
            if (winnerTeam != null) return;

            setState(() {
              if (t == 'A') teamAScore += d;
              if (t == 'B') teamBScore += d;
            });
            _checkWinner();
            break;
          }

        case 'score_board':
          {
            final a = (msg['team_a'] ?? teamAScore) is num
                ? (msg['team_a'] as num).toInt()
                : teamAScore;
            final b = (msg['team_b'] ?? teamBScore) is num
                ? (msg['team_b'] as num).toInt()
                : teamBScore;

            if (winnerTeam != null) return;

            setState(() {
              teamAScore = a;
              teamBScore = b;
            });
            _checkWinner();
            break;
          }

        case 'you_are_hit':
          {
            final pid = (msg['player_id'] ?? '').toString();
            final secs = _asInt(msg['respawn_seconds'], fallback: 10);
            final pName = (msg['player_name'] ?? '').toString();

            if (pName.isNotEmpty) {
              setState(() => deadPlayers.add(pName));
              Timer(Duration(seconds: secs), () {
                if (!mounted) return;
                setState(() => deadPlayers.remove(pName));
              });
            }

            if (pid.isEmpty || pid == myId) {
              _startRespawn(secs);
            }
            break;
          }

        case 'restore_state':
          {
            final pid = (msg['player_id'] ?? '').toString();
            if (pid.isNotEmpty && pid != myId) break;

            final bool alive = msg['alive'] == true;
            final int msLeft = _asInt(msg['respawn_ms_left'], fallback: 0);
            final bool sessActive = msg['session_active'] == true;

            setState(() {
              sessionActive = sessActive;

              myTeam = (msg['team'] ?? myTeam).toString();
              myScore = _asInt(msg['player_score'], fallback: 0);

              myGunId = (msg['gun_id'] ?? myGunId)?.toString();
              myVestId = (msg['vest_id'] ?? myVestId)?.toString();

              teamAScore = _asInt(msg['score_a'], fallback: teamAScore);
              teamBScore = _asInt(msg['score_b'], fallback: teamBScore);
            });

            if (!alive && msLeft > 0) {
              final secs = (msLeft / 1000).ceil();
              _startRespawn(secs);
            } else {
              setState(() {
                isDead = false;
                respawnRemaining = 0;
              });
            }

            _checkWinner();
            break;
          }

        case 'game_over':
          {
            final w = (msg['winner'] ?? '').toString().toUpperCase();
            if (w == 'A' || w == 'B') {
              if (!mounted) return;
              setState(() => winnerTeam = w);
              _goToVictory();
            }
            break;
          }

        // لو عندكم session_ended سابقًا في المشروع
        case 'session_ended':
          {
            if (!mounted) return;
            WidgetsBinding.instance.addPostFrameCallback((_) {
              Navigator.pushNamedAndRemoveUntil(context, '/', (r) => false);
            });
            break;
          }
      }
    }, onError: (_) {
      _scheduleReconnect();
    }, onDone: () {
      _scheduleReconnect();
    });
  }

  void _scheduleReconnect() {
    if (!mounted) return;
    if (_isReconnecting) return;
    _isReconnecting = true;

    _reconnectTimer?.cancel();

    // backoff بسيط: 1s, 2s, 3s ... لحد 5s
    _reconnectAttempts++;
    final waitSeconds = _reconnectAttempts.clamp(1, 5);

    _reconnectTimer = Timer(Duration(seconds: waitSeconds), () {
      if (!mounted) return;

      // لا نغيّر UI ولا نطلع بانر… بس نعيد الاتصال
      _isReconnecting = false;
      _connectWs();
    });
  }

  void _startRespawn(int seconds) {
    _respawnTimer?.cancel();

    setState(() {
      isDead = true;
      respawnRemaining = seconds;
    });

    _respawnTimer = Timer.periodic(const Duration(seconds: 1), (t) {
      if (!mounted) {
        t.cancel();
        return;
      }

      if (respawnRemaining <= 1) {
        t.cancel();
        setState(() {
          isDead = false;
          respawnRemaining = 0;
        });
      } else {
        setState(() => respawnRemaining--);
      }
    });
  }

  int _asInt(dynamic v, {int fallback = 0}) {
    if (v is int) return v;
    if (v is num) return v.toInt();
    if (v is String) return int.tryParse(v) ?? fallback;
    return fallback;
  }

  void _checkWinner() {
    if (winnerTeam != null) return;

    if (teamAScore >= targetScore) {
      setState(() => winnerTeam = 'A');
      _goToVictory();
    } else if (teamBScore >= targetScore) {
      setState(() => winnerTeam = 'B');
      _goToVictory();
    }
  }

  void _goToVictory() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final winningScore = (winnerTeam == 'A') ? teamAScore : teamBScore;

      Navigator.pushReplacementNamed(
        context,
        '/VictoryPage',
        arguments: {
          'winner_team': winnerTeam,
          'final_score': winningScore,
          'i_am_leader': iAmLeader,
        },
      );
    });
  }

  void _endGame() {
    if (_endRequested) return;
    _endRequested = true;

    // إذا القناة طايحة، _safeSend بيرجع يسوي reconnect
    _safeSend({'type': 'leader_end'});

    // لا نسوي Navigator هنا
  }

  @override
  void dispose() {
    _reconnectTimer?.cancel();
    _pingTimer?.cancel();
    _respawnTimer?.cancel();
    try {
      _ch?.sink.close();
    } catch (_) {}
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF050827),
      body: Stack(
        children: [
          SafeArea(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(20, 16, 20, 12),
              child: Column(
                children: [
                  SizedBox(
                    width: 300,
                    height: 100,
                    child: Image.asset('assets/images/logoB.png'),
                  ),
                  const SizedBox(height: 6),

                  Text(
                    'Target Score: $targetScore',
                    style: const TextStyle(
                      color: Colors.white70,
                      fontSize: 14,
                    ),
                  ),
                  const SizedBox(height: 70),

                  _TeamPanel(
                    title: 'Team A',
                    accent: const Color.fromARGB(255, 215, 89, 254),
                    score: teamAScore,
                    players: teamAPlayers,
                    jaro: jaro,
                    deadPlayers: deadPlayers,
                  ),
                  const SizedBox(height: 15),

                  _TeamPanel(
                    title: 'Team B',
                    accent: const Color.fromARGB(255, 43, 93, 229),
                    score: teamBScore,
                    players: teamBPlayers,
                    jaro: jaro,
                    deadPlayers: deadPlayers,
                  ),

                  const SizedBox(height: 155),

                  if (iAmLeader)
                    GestureDetector(
                      onTap: _endRequested ? null : _endGame,
                      child: Opacity(
                        opacity: _endRequested ? 0.6 : 1,
                        child: Container(
                          width: 360,
                          height: 53,
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(16),
                            gradient: const LinearGradient(
                              colors: [
                                Color.fromARGB(255, 34, 86, 229),
                                Color.fromARGB(255, 178, 85, 255),
                              ],
                              begin: Alignment.centerLeft,
                              end: Alignment.centerRight,
                            ),
                          ),
                          alignment: Alignment.center,
                          child: const Text(
                            'END GAME',
                            style: TextStyle(
                              color: Colors.white,
                              fontSize: 16,
                              fontWeight: FontWeight.bold,
                              letterSpacing: 0.8,
                            ),
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ),

          if (isDead)
            Container(
              color: Colors.black.withOpacity(0.18),
              child: Center(
                child: Container(
                  width: MediaQuery.of(context).size.width * 0.80,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 22,
                    vertical: 26,
                  ),
                  decoration: BoxDecoration(
                    color: const Color.fromARGB(255, 29, 23, 23).withOpacity(0.55),
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(
                      color: const Color.fromARGB(255, 255, 0, 179),
                      width: 3,
                    ),
                    boxShadow: [
                      BoxShadow(
                        color: const Color.fromARGB(255, 121, 3, 58).withOpacity(0.4),
                        blurRadius: 18,
                        spreadRadius: 2,
                        offset: const Offset(0, 4),
                      ),
                    ],
                  ),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        'YOU ARE OUT',
                        style: TextStyle(
                          color: const Color.fromARGB(255, 255, 0, 179),
                          fontSize: 22,
                          letterSpacing: 1.2,
                          fontWeight: FontWeight.w900,
                          fontFamily: jaro,
                        ),
                        textAlign: TextAlign.center,
                      ),
                      const SizedBox(height: 10),
                      Text(
                        'Respawn in $respawnRemaining seconds',
                        style: const TextStyle(
                          color: Colors.white70,
                          fontSize: 16,
                          fontWeight: FontWeight.w500,
                        ),
                        textAlign: TextAlign.center,
                      ),
                    ],
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _TeamPanel extends StatelessWidget {
  final String title;
  final int score;
  final List<String> players;
  final Color accent;
  final String jaro;
  final Set<String> deadPlayers;

  const _TeamPanel({
    required this.title,
    required this.score,
    required this.players,
    required this.accent,
    required this.jaro,
    required this.deadPlayers,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(14, 14, 14, 16),
      decoration: BoxDecoration(
        color: const Color(0x00121d2f).withOpacity(0.35),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: accent.withOpacity(.6), width: 1.4),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(.25),
            blurRadius: 14,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Column(
        children: [
          Row(
            children: [
              Text(
                title,
                style: TextStyle(
                  fontFamily: jaro,
                  fontSize: 26,
                  color: accent,
                  height: 1,
                ),
              ),
              const Spacer(),
              Container(
                width: 46,
                height: 46,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  border: Border.all(color: accent, width: 3),
                ),
                alignment: Alignment.center,
                child: Text(
                  '$score',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 18,
                    fontFamily: jaro,
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
            decoration: BoxDecoration(
              color: Colors.white.withOpacity(0.05),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: accent.withOpacity(.35), width: 1),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: List.generate(
                players.length,
                (i) => Padding(
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  child: Row(
                    children: [
                      Expanded(
                        child: Text(
                          '${i + 1}- ${players[i]}',
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 16,
                            height: 1.2,
                          ),
                        ),
                      ),
                      const SizedBox(width: 6),
                      if (deadPlayers.contains(players[i]))
                        const Icon(
                          Icons.close,
                          color: Colors.red,
                          size: 22,
                        ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}


