import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:web_socket_channel/web_socket_channel.dart';

class PlayerInfoPage extends StatefulWidget {
  const PlayerInfoPage({super.key});

  @override
  State<PlayerInfoPage> createState() => _PlayerInfoPageState();
}

class _PlayerInfoPageState extends State<PlayerInfoPage> {
  WebSocketChannel? _channel;

  // سيتم تهيئتها عند قراءة arguments قبل أول build
  late String playerName;
  late String team;       // 'A' أو 'B'
  late bool isLeader;

  int initialScore = 0;

  bool _inited = false;   // لمنع التهيئة أكثر من مرة

  @override// تشتغل بعد ما تكون البيانات وصلت فعلاً من الصفحة السابقة،
  void didChangeDependencies() { // تُستدعى قبل build
    super.didChangeDependencies();
    if (_inited) return;

    final args = ModalRoute.of(context)?.settings.arguments as Map<String, dynamic>?;

    playerName = (args?['name'] as String? ?? 'Player').trim();
    team       = (args?['team'] as String? ?? 'A').trim().toUpperCase();
    isLeader   = args?['isLeader'] == true;

    _connectHub(); // افتح الاتصال بعد ما جهزت القيم
    _inited = true;
  }

  void _connectHub() {
    // غيّري العنوان لعنوان الهب الحقيقي
    final uri = Uri.parse('ws://192.168.4.1:8080/ws');
    _channel = WebSocketChannel.connect(uri);

    _channel!.stream.listen(
      (raw) {
        final msg = jsonDecode(raw);
        final type = msg['type'];

        if (type == 'game_start') {
          final matchId = msg['match_id']?.toString() ?? 'match';
          final initial = msg['initial_score'] is num
              ? (msg['initial_score'] as num).toInt()
              : 0;

          if (!mounted) return;
          Navigator.pushReplacementNamed(
            context,
            '/game', // <-- غيّريه لمسار صفحة اللعب عندك
            arguments: {
              'name': playerName,
              'team': team,
              'match_id': matchId,
              'initial_score': initial,
            },
          );
        }
      },
      onError: (e) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Hub connection error: $e')),
        );
      },
    );

    // تسجيل حضور اختياري
    _channel!.sink.add(jsonEncode({
      'type': 'player_hello',
      'name': playerName,
      'team': team,
    }));
  }

  @override
  void dispose() {
    _channel?.sink.close();
    super.dispose();
  }

  // إرسال "Start" من جهاز الليدر
  void _sendStart() {
    final msg = {
      'type': 'leader_start',
      'initial_score': initialScore,
    };
    _channel?.sink.add(jsonEncode(msg));

    // للديبق فقط: محاكاة وصول game_start لو ما فيه هب شغال
    if (kDebugMode) {
      Future.delayed(const Duration(milliseconds: 300), () {
        final fake = jsonEncode({
          'type': 'game_start',
          'match_id': 'debug-match',
          'initial_score': initialScore,
        });
        _channel?.sink.add(fake);
      });
    }
  }

  Color _teamColor(String t) {
    return t == 'B'
        ? const Color(0xFFE34B4B)   // أحمر لفريق B
        : const Color(0xFF2E86DE);  // أزرق لفريق A
  }

  @override
  Widget build(BuildContext context) {
    final tColor = _teamColor(team);


    return Scaffold(
      backgroundColor: const Color.fromARGB(255, 3, 1, 39),
      appBar: AppBar(
        backgroundColor: const Color.fromARGB(255, 3, 1, 39),
        iconTheme: const IconThemeData(color: Colors.white),
      ),
      body: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(
          children: [
            // بطاقة معلومات اللاعب
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: const Color.fromARGB(255, 12, 22, 45),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: Colors.white24),
              ),
              child: Row(
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                    decoration: BoxDecoration(
                      color: tColor,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Text(
                      'TEAM $team',
                      style: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      playerName,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 22,
                        color: Colors.white,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                  if (isLeader)
                    const Padding(
                      padding: EdgeInsets.only(left: 8),
                      child: Icon(Icons.workspace_premium, color: Colors.amber),
                    ),
                ],
              ),
            ),

            const SizedBox(height: 24),

            // وضع اللاعب: انتظار الليدر
            if (!isLeader) ...[
              const Text(
                'Wait for the leader to set the score and start the game…',
                textAlign: TextAlign.center,
                style: TextStyle(color: Colors.white70, fontSize: 16),
              ),
              const SizedBox(height: 18),
              const CircularProgressIndicator.adaptive(),
              const Spacer(),
              if (kDebugMode)
                TextButton(
                  onPressed: () {
                    // محاكاة بدء اللعبة للديبق
                    final fake = jsonEncode({
                      'type': 'game_start',
                      'match_id': 'debug-match',
                      'initial_score': 0,
                    });
                    _channel?.sink.add(fake);
                  },
                  child: const Text(
                    'Simulate START (debug)',
                    style: TextStyle(color: Colors.white70),
                  ),
                ),
            ],

            // وضع الليدر: اختيار السكور والبدء
            if (isLeader) ...[
              const Text(
                'إعدادات الليدر',
                style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  const Text('السكور الابتدائي: ',
                      style: TextStyle(color: Colors.white70)),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Slider(
                      min: 0,
                      max: 100,
                      divisions: 20,
                      label: '$initialScore',
                      value: initialScore.toDouble(),
                      onChanged: (v) => setState(() => initialScore = v.round()),
                    ),
                  ),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                    decoration: BoxDecoration(
                      color: Colors.white10,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text('$initialScore',
                        style: const TextStyle(color: Colors.white)),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: _sendStart,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color.fromARGB(255, 6, 57, 108),
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                  child: const Text('Start for All',
                      style: TextStyle(color: Colors.white)),
                ),
              ),
              const Spacer(),
            ],
          ],
        ),
      ),
    );
  }
}
