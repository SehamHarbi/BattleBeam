// game_page.dart
import 'dart:async'; // للـ Timer
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:web_socket_channel/web_socket_channel.dart';
import 'package:shared_preferences/shared_preferences.dart';

class GamePage extends StatefulWidget {
  const GamePage({super.key});

  @override
  State<GamePage> createState() => _GamePageState();
}

class _GamePageState extends State<GamePage> {
  late int targetScore;
  late List<String> teamAPlayers;
  late List<String> teamBPlayers;
  late int teamAScore;
  late int teamBScore;

  bool iAmLeader = false;

  String? winnerTeam; // 'A' or 'B'
  final String jaro = GoogleFonts.jaro().fontFamily ?? 'Jaro';

  // debug add-points buttons only (تقدرين تشيلينها لاحقًا)
  static const colorA = Color.fromARGB(255, 184, 93, 229);
  static const colorB = Color(0xFF2E86DE);

  // ===== WebSocket (ربط مباشر مع الهب) =====
  WebSocketChannel? _ch;
  bool _wsInited = false;

  // بيانات اللاعب (للتسجيل عند الهب)
  String myId = '';
  String myName = 'Player';
  String myTeam = 'A';

  // ===== منطق الـ Respawn =====
  bool isDead = false;        // هل اللاعب ميت حاليًا؟
  int respawnRemaining = 0;   // كم ثانية باقية للعودة؟
  Timer? _respawnTimer;       // مؤقّت العد التنازلي

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final args = (ModalRoute.of(context)!.settings.arguments as Map?) ?? {};

    iAmLeader   = (args['i_am_leader'] as bool?) ?? false;
    targetScore = _asInt(args['target_score'], fallback: 5);

    teamAPlayers = (args['team_a_players'] as List?)
            ?.map((e) => e.toString()).toList()
        ?? const ['Player 1','Player 2','Player 3'];

    teamBPlayers = (args['team_b_players'] as List?)
            ?.map((e) => e.toString()).toList()
        ?? const ['Player 4','Player 5','Player 6'];

    teamAScore = _asInt(args['team_a_score'], fallback: 0);
    teamBScore = _asInt(args['team_b_score'], fallback: 0);

    // خذ الاسم والفريق لو مرّوا مع النافجيت من اللوبّي/البيكر
    myName = (args['name'] as String?)?.trim().isNotEmpty == true
        ? (args['name'] as String)
        : myName;
    myTeam = (args['team'] as String?)?.toUpperCase() == 'B' ? 'B' : 'A';

    _checkWinner();

    // افتحي WS مرة واحدة فقط
    if (!_wsInited) {
      _wsInited = true;
      _prepareIdentityAndConnect();
    }
  }

  Future<void> _prepareIdentityAndConnect() async {
    // نحافظ على نفس player_id المستخدم في بقية الصفحات
    final p = await SharedPreferences.getInstance();
    myId = p.getString('player_id') ??
        DateTime.now().millisecondsSinceEpoch.toString();
    await p.setString('player_id', myId);

    if (p.getString('player_name') == null && myName.isNotEmpty) {
      await p.setString('player_name', myName);
    }

    _connectWs();
  }

  void _connectWs() {
    // مطابق للهَب: ws://192.168.4.1/ws
    _ch = WebSocketChannel.connect(Uri.parse('ws://192.168.4.1/ws'));

    // سجل التطبيق كـ app ليظهر كلاعب (اختياري هنا، لكنه مفيد للتماسك)
    _ch!.sink.add(jsonEncode({
      'type': 'register',
      'deviceId': myId,
      'kind': 'app',
      'team': myTeam,
      'name': myName,
    }));

    // اطلب لوحة السكور الحالية للمزامنة (لو دخلتي بنص اللعبة)
    _ch!.sink.add(jsonEncode({'type': 'get_score'}));

    _ch!.stream.listen((raw) {
      final msg = jsonDecode(raw);
      switch (msg['type']) {
        case 'score_update': {
          // {type:score_update, team:'A'/'B', delta:1}
          final t = (msg['team'] ?? '').toString().toUpperCase();
          final d = (msg['delta'] ?? 0) is num ? (msg['delta'] as num).toInt() : 0;
          if (d == 0) return;

          if (winnerTeam != null) return; // توقف بعد الفوز

          setState(() {
            if (t == 'A') {
              teamAScore += d;
            } else if (t == 'B') {
              teamBScore += d;
            }
          });
          _checkWinner();
          break;
        }

        case 'score_board': {
          // {type:score_board, team_a:int, team_b:int}
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

        // الهب يقول لك: انصبتِ
        // مثال: {type:'you_are_hit', player_id:'APP-123', respawn_seconds:10}
        case 'you_are_hit': {
          final pid  = (msg['player_id'] ?? '').toString();
          final secs = _asInt(msg['respawn_seconds'], fallback: 10);

          // لو الرسالة موجهة لهذا اللاعب
          if (pid.isEmpty || pid == myId) {
            _startRespawn(secs);
          }
          break;
        }

        case 'game_over': {
          // {type:game_over, winner:'A'/'B', final_score:int}
          final w = (msg['winner'] ?? '').toString().toUpperCase();
          if (w == 'A' || w == 'B') {
            if (!mounted) return;
            winnerTeam = w;
            _goToVictory();
          }
          break;
        }
      }
    }, onError: (_) {
      // تجاهل الأخطاء هنا (اختياري تعرضين SnackBar)
    });
  }

  // ===== منطق الـ Respawn =====
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
        setState(() {
          respawnRemaining--;
        });
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
      _goToVictory(); // <<< أهم سطر
    } else if (teamBScore >= targetScore) {
      setState(() => winnerTeam = 'B');
      _goToVictory(); // <<< أهم سطر
    }
  }

  void _goToVictory() {
    // تجنّب التنقّل بنفس فريم setState
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final winningScore = (winnerTeam == 'A') ? teamAScore : teamBScore;

      Navigator.pushReplacementNamed(
        context,
        '/VictoryPage',
        arguments: {
          'winner_team': winnerTeam,     // 'A' أو 'B'
          'final_score': winningScore,   // مثال: 20
          'i_am_leader': iAmLeader,      // عشان نتحكم بزر End Session
        },
      );
    });
  }

  // أزرار debug لزيادة النقاط أثناء التطوير (لو حابة تخلينها)
  void _incA() { if (winnerTeam != null) return; setState(() => teamAScore++); _checkWinner(); }
  void _incB() { if (winnerTeam != null) return; setState(() => teamBScore++); _checkWinner(); }

  void _endGame() {
    // الليدر يرسل للهب إنه ينهي اللعبة
    try {
      _ch?.sink.add(jsonEncode({'type': 'leader_end'}));
    } catch (_) {}
    // الهب بعدها يرسل game_over للجميع
  }

  @override
  void dispose() {
    // اغلاق WS و المؤقّت
    try { _ch?.sink.close(); } catch (_) {}
    _respawnTimer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF050827),
      body: Stack(
        children: [
          // ===== المحتوى الأساسي =====
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
                  const SizedBox(height: 15),

                  _TeamPanel(
                    title: 'Team A',
                    accent: const Color.fromARGB(255, 215, 89, 254),
                    score: teamAScore,
                    players: teamAPlayers,
                    jaro: jaro,
                    myName: myName,
                    isDead: isDead,
                  ),
                  const SizedBox(height: 15),
                  _TeamPanel(
                    title: 'Team B',
                    accent: const Color.fromARGB(255, 43, 93, 229),
                    score: teamBScore,
                    players: teamBPlayers,
                    jaro: jaro,
                    myName: myName,
                    isDead: isDead,
                  ),

                  const SizedBox(height: 16),

                  // أزرار زيادة نقاط للتجربة فقط
                  if (kDebugMode) ...[
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        ElevatedButton(
                          onPressed: winnerTeam != null ? null : _incA,
                          style: ElevatedButton.styleFrom(
                            backgroundColor: colorA,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12),
                            ),
                          ),
                          child: const Text(
                            '+ A',
                            style: TextStyle(color: Colors.white),
                          ),
                        ),
                        const SizedBox(width: 12),
                        ElevatedButton(
                          onPressed: winnerTeam != null ? null : _incB,
                          style: ElevatedButton.styleFrom(
                            backgroundColor: colorB,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12),
                            ),
                          ),
                          child: const Text(
                            '+ B',
                            style: TextStyle(color: Colors.white),
                          ),
                        ),
                      ],
                    ),
                  ],

                  const Spacer(),

                  // زر END GAME لليدر
                  if (iAmLeader)
                    GestureDetector(
                      onTap: _endGame,
                      child: Container(
                        width: double.infinity,
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
                ],
              ),
            ),
          ),

          // ===== Overlay: بانر الريسباون في نص الشاشة =====
          if (isDead)
            Container(
              // خلفية خفيفة شفافة على كامل الشاشة
              color: Colors.black.withOpacity(0.18),
              child: Center(
                child: Container(
                  width: MediaQuery.of(context).size.width * 0.80,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 22,
                    vertical: 26,
                  ),
                  decoration: BoxDecoration(
                    color: const Color.fromARGB(255, 29, 23, 23)
                        .withOpacity(0.55), // الخلفية الداكنة الشفافة اللي اخترتيها
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(
                      color: const Color.fromARGB(255, 255, 0, 179), // فوشي واضح
                      width: 3,
                    ),
                    boxShadow: [
                      BoxShadow(
                        color: const Color.fromARGB(255, 121, 3, 58)
                            .withOpacity(0.4),
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
  final String myName; // اسم اللاعب الحالي (من الجوال)
  final bool isDead;   // هل هو ميت الآن؟

  const _TeamPanel({
    required this.title,
    required this.score,
    required this.players,
    required this.accent,
    required this.jaro,
    required this.myName,
    required this.isDead,
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
                      // X حمراء تظهر فقط عند اللاعب الحالي لو هو ميت
                      if (players[i] == myName && isDead)
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






