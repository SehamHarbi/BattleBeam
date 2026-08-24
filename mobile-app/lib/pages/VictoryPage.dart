// victory_page.dart
import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:audioplayers/audioplayers.dart';
import 'package:web_socket_channel/web_socket_channel.dart';
import 'package:shared_preferences/shared_preferences.dart';

class VictoryPage extends StatefulWidget {
  const VictoryPage({super.key});

  @override
  State<VictoryPage> createState() => _VictoryPageState();
}

class _VictoryPageState extends State<VictoryPage> {
  final AudioPlayer _player = AudioPlayer();

  WebSocketChannel? _ch;
  StreamSubscription? _wsSub;
  Timer? _pingTimer;

  String myId = '';
  String myName = 'Player';
  String myTeam = 'A';

  bool _ending = false;
  Timer? _fallbackTimer;

  @override
  void initState() {
    super.initState();
    _playWinSound();
    _initWs();
  }

  Future<void> _playWinSound() async {
    try {
      await _player.stop();
      await _player.play(AssetSource('sounds/win.mp3'));
    } catch (_) {}
  }

  Future<void> _initWs() async {
    final p = await SharedPreferences.getInstance();

    // ✅ UUID ثابت (ما ينمسح)
    myId = p.getString('player_id') ??
        DateTime.now().millisecondsSinceEpoch.toString();
    await p.setString('player_id', myId);

    // (اختياري) قراءة اسم/تيم لو موجودين
    myName = p.getString('player_name') ?? myName;
    myTeam = (p.getString('player_team') ?? myTeam).toUpperCase();
    myTeam = (myTeam == 'B') ? 'B' : 'A';

    _connectWs();
  }

  void _connectWs() {
    _ch = WebSocketChannel.connect(Uri.parse('ws://192.168.4.1/ws'));

    _safeSend({
      'type': 'register',
      'deviceId': myId,
      'kind': 'app',
      'team': myTeam,
      'name': myName,
    });

    _pingTimer?.cancel();
    _pingTimer = Timer.periodic(const Duration(seconds: 5), (_) {
      _safeSend({'type': 'ping', 'deviceId': myId});
    });

    _wsSub?.cancel();
    _wsSub = _ch!.stream.listen((raw) async {
      dynamic msg;
      try {
        msg = jsonDecode(raw);
      } catch (_) {
        return;
      }

      final type = (msg['type'] ?? '').toString();

      if (type == 'session_ended') {
        // ✅ هنا نسوي "fresh start" للتطبيق (بدون مسح player_id)
        await _wipeLocalSessionKeepId();

        if (!mounted) return;
        _fallbackTimer?.cancel();
        Navigator.pushNamedAndRemoveUntil(context, '/', (r) => false);
      }
    }, onError: (_) {
      // لو ضغط END SESSION وما وصل رد
      if (_ending) _startFallback();
    }, onDone: () {
      if (_ending) _startFallback();
    });
  }

  void _safeSend(Map<String, dynamic> data) {
    try {
      _ch?.sink.add(jsonEncode(data));
    } catch (_) {}
  }

  void _startFallback() {
    _fallbackTimer?.cancel();
    _fallbackTimer = Timer(const Duration(seconds: 3), () async {
      // حتى بالفولباك نسوي مسح محلي (نفس المطلوب)
      await _wipeLocalSessionKeepId();
      if (!mounted) return;
      Navigator.pushNamedAndRemoveUntil(context, '/', (r) => false);
    });
  }

  /// ✅ يمسح كل شي "جلسة" من الجهاز ويخلي player_id (UUID)
  Future<void> _wipeLocalSessionKeepId() async {
    final p = await SharedPreferences.getInstance();
    final keepId = p.getString('player_id');

    // امسحي أي مفاتيح تخص الجلسة عندكم (زيدي/عدلي حسب مفاتيحكم)
    await p.remove('player_name');
    await p.remove('player_team');
    await p.remove('selected_team');
    await p.remove('selected_gun_id');
    await p.remove('selected_vest_id');
    await p.remove('gun_id');
    await p.remove('vest_id');
    await p.remove('i_am_leader');
    await p.remove('leader_id');
    await p.remove('target_score');
    await p.remove('game_active');
    await p.remove('session_active');
    await p.remove('team_a_score');
    await p.remove('team_b_score');

    // رجّعي الـ UUID
    if (keepId != null && keepId.isNotEmpty) {
      await p.setString('player_id', keepId);
    }
  }

  void _endSessionFromAnyPlayer() {
    if (_ending) return;
    setState(() => _ending = true);

    // ✅ أي لاعب يقدر ينهي السيشن
    _safeSend({'type': 'end_session'});

    // لو ما وصل session_ended لا نعلق
    _startFallback();
  }

  @override
  void dispose() {
    try {
      _wsSub?.cancel();
      _pingTimer?.cancel();
      _fallbackTimer?.cancel();
      _ch?.sink.close();
    } catch (_) {}
    _player.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final args = (ModalRoute.of(context)!.settings.arguments as Map?) ?? {};
    final String winnerTeam = (args['winner_team'] ?? 'A').toString().toUpperCase();

    final String jaro = GoogleFonts.jaro().fontFamily ?? 'Jaro';
    final Color accent = (winnerTeam == 'A')
        ? const Color.fromARGB(255, 215, 89, 254)
        : const Color.fromARGB(255, 43, 93, 229);

    return Scaffold(
      backgroundColor: const Color(0xFF050827),
      body: SafeArea(
        child: Center(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 24),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const SizedBox(height: 15),
                SizedBox(
                  width: 200,
                  height: 100,
                  child: Image.asset("assets/images/logo3.png"),
                ),

                const SizedBox(height: 170),

                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 10),
                  decoration: BoxDecoration(
                    color: accent.withOpacity(.15),
                    borderRadius: BorderRadius.circular(12),
                    boxShadow: [
                      BoxShadow(color: accent.withOpacity(.35), blurRadius: 20)
                    ],
                  ),
                  child: Text(
                    'VICTORY',
                    style: TextStyle(
                      fontFamily: jaro,
                      fontSize: 44,
                      color: accent,
                      letterSpacing: 4,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                ),

                const SizedBox(height: 22),

                Text(
                  'TEAM $winnerTeam WINS!',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontFamily: jaro,
                    fontSize: 40,
                    color: Colors.white,
                    fontWeight: FontWeight.w900,
                    letterSpacing: 1.2,
                    shadows: [
                      Shadow(color: accent.withOpacity(.7), blurRadius: 18, offset: const Offset(0, 2)),
                      Shadow(color: Colors.black.withOpacity(.4), blurRadius: 8, offset: const Offset(0, 2)),
                    ],
                  ),
                ),

                const SizedBox(height: 210),

                GestureDetector(
                  onTap: _endSessionFromAnyPlayer,
                  child: Opacity(
                    opacity: _ending ? 0.65 : 1,
                    child: Container(
                      width: 360,
                      height: 53,
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(16),
                        gradient: const LinearGradient(
                          colors: [
                            Color.fromARGB(255, 34, 86, 229),
                            Color.fromARGB(255, 178, 85, 255)
                          ],
                          begin: Alignment.bottomLeft,
                          end: Alignment.topRight,
                        ),
                      ),
                      alignment: Alignment.center,
                      child: Text(
                        _ending ? 'ENDING...' : 'END SESSION',
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                          letterSpacing: .6,
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}



