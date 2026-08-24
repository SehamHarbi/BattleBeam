import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:web_socket_channel/web_socket_channel.dart';
import 'package:google_fonts/google_fonts.dart';

class LobbyPage extends StatefulWidget {
  const LobbyPage({super.key});
  @override
  State<LobbyPage> createState() => _LobbyPageState();
}

class _LobbyPageState extends State<LobbyPage> {
  WebSocketChannel? _ch;
  Timer? _pingTimer;

  // بيانات اللاعب
  String myId = '';
  String myName = 'Player';
  String myTeam = 'A';

  // من الهب
  String? leaderId;
  final List<_Player> players = [];

  // إعدادات الليدر
  int targetScore = 5;

  // تحكم بالتنقل
  bool _seenInitialBoard = false;
  bool _waitingForGame   = false;
  bool _haveDevices      = false;   // عندنا قائمة لاعبين؟
  bool _gameIsActive     = false;   // الهب أعلن بدء القيم؟

  bool get iAmLeader => leaderId != null && leaderId == myId;

  // 🔹 شرط بدء القيم:
  // - لازم أكون ليدر
  // - لازم عدد اللاعبين >= 2
  // - لازم يكون فيه لاعب واحد على الأقل من الفريق الثاني
  bool get canStartGame {
    if (!iAmLeader) return false;

    // 1) على الأقل لاعبين
    if (players.length < 2) return false;

    // 2) هل فيه لاعب من فريق مختلف غيري؟
    final hasOpponent = players.any(
      (p) => p.id != myId && p.team != myTeam,
    );

    return hasOpponent;
  }

  @override
  void initState() {
    super.initState();
    _loadMe().then((_) => _connect());
  }

  Future<void> _loadMe() async {
    final p = await SharedPreferences.getInstance();
    myId   = p.getString('player_id') ??
        DateTime.now().millisecondsSinceEpoch.toString();
    await p.setString('player_id', myId);

    myName = p.getString('player_name') ?? 'Player';
    myTeam = (p.getString('player_team') ?? 'A').toUpperCase();
  }

  void _connect() {
    _ch = WebSocketChannel.connect(Uri.parse('ws://192.168.4.1/ws'));

    // سجل كـ app
    _ch!.sink.add(jsonEncode({
      'type': 'register',
      'deviceId': myId,
      'kind': 'app',
      'team': myTeam,
      'name': myName,
    }));

    // اطلب الأجهزة لعرض اللاعبين
    _ch!.sink.add(jsonEncode({'type': 'get_devices'}));

    // ping دوري عشان ما نطلع Offline
    _pingTimer?.cancel();
    _pingTimer = Timer.periodic(const Duration(seconds: 5), (_) {
      try {
        _ch?.sink.add(jsonEncode({
          'type': 'ping',
          'deviceId': myId,
        }));
      } catch (_) {}
    });

    _ch!.stream.listen((raw) {
      final msg = jsonDecode(raw);

      switch (msg['type']) {
        // =================== الأجهزة ===================
        case 'devices': {
          final list = (msg['items'] as List?) ?? [];
          final nextPlayers = <_Player>[];

          String? hubLeader = (msg['leader'] ?? '').toString();
          if (hubLeader.isEmpty) hubLeader = null;

          for (final e in list) {
            final kind = (e['kind'] ?? '').toString();
            final online = e['online'] == true;
            if (kind == 'app' && online) {
              nextPlayers.add(_Player(
                id: (e['id'] ?? '').toString(),
                name: (e['name'] ?? 'Player').toString(),
                team: (e['team'] ?? 'A').toString().toUpperCase(),
              ));
            }
          }

          nextPlayers.sort((a, b) => a.id.compareTo(b.id));

          players
            ..clear()
            ..addAll(nextPlayers);

          _haveDevices = players.isNotEmpty;

          leaderId = hubLeader;
          if (leaderId == null ||
              !players.any((p) => p.id == leaderId)) {
            leaderId = players.isNotEmpty ? players.first.id : null;
          }

          setState(() {});
          break;
        }

        // =================== تغيير target score ===================
        case 'target_score': {
          final t = msg['value'];
          if (t is num) {
            setState(() {
              targetScore = t.toInt();
            });
          }
          break;
        }

        // =================== game_active (من الهب) ===================
        case 'game_active': {
          setState(() {
            _gameIsActive = true;
            final t = msg['target_score'];
            if (t is num) targetScore = t.toInt();
          });
          break;
        }

        // =================== لوحة السكور ===================
        case 'score_board': {
          final a = (msg['team_a'] ?? 0) is num
              ? (msg['team_a'] as num).toInt()
              : 0;
          final b = (msg['team_b'] ?? 0) is num
              ? (msg['team_b'] as num).toInt()
              : 0;

          // تجاهل أول لوحة سكّور بعد الاتصال
          if (!_seenInitialBoard) {
            _seenInitialBoard = true;
            break;
          }

          // لو ما عندنا أجهزة (ما عرفنا اللاعبين/الليدر) لا ندخل
          if (!_haveDevices) break;

          // ننتقل لو:
          // 1) الليدر ضغط START (_waitingForGame = true)
          // 2) أو أي لاعب بعد ما الهب أعلن game_active
          final shouldEnter = _waitingForGame || _gameIsActive;
          if (!shouldEnter) break;

          final teamA = players
              .where((p) => p.team == 'A')
              .map((p) => p.name)
              .toList();
          final teamB = players
              .where((p) => p.team == 'B')
              .map((p) => p.name)
              .toList();

          if (!mounted) return;
          Navigator.pushReplacementNamed(
            context,
            '/gamep',
            arguments: {
              'name': myName,
              'team': myTeam,
              'i_am_leader': iAmLeader,
              'match_id': 'live',
              'initial_score': 0,
              'target_score': targetScore,
              'team_a_players': teamA,
              'team_b_players': teamB,
              'team_a_score': a,
              'team_b_score': b,
            },
          );
          break;
        }

        // =================== نهاية القيم ===================
        case 'game_over': {
          final winner = (msg['winner'] ?? '').toString();
          final finalScore = (msg['final_score'] ?? 0) is num
              ? (msg['final_score'] as num).toInt()
              : 0;

          if (!mounted) return;
          Navigator.pushReplacementNamed(
            context,
            '/VictoryPage',
            arguments: {
              'winner_team': winner,
              'final_score': finalScore,
              'i_am_leader': iAmLeader,
            },
          );
          break;
        }
      }
    });
  }

  @override
  void dispose() {
    _pingTimer?.cancel();
    _ch?.sink.close();
    super.dispose();
  }

  void _startGame() {
     // Prevent starting the game if conditions are not met
    if (!canStartGame) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'You need at least one opponent player to start the game.',
          ),
        ),
      );
      return;
    }
// Mark the leader as waiting for the game to begin
    _waitingForGame = true; 
   // Send start command to the Hub via WebSocket
    _ch?.sink.add(jsonEncode({
      'type': 'leader_start',
      'target_score': targetScore,
      'initial_score': 0,
    }));
  }

  Color _teamColor(String t) =>
      t == 'B'
          ? const Color.fromARGB(255, 43, 93, 229)
          : const Color.fromARGB(255, 215, 89, 254);

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF050827),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 16),
          child: Column(
            children: [
              const SizedBox(height: 10),
              ShaderMask(
                shaderCallback: (Rect bounds) {
                  return const LinearGradient(
                    colors: [
                      Color.fromARGB(255, 43, 93, 229),
                      Color.fromARGB(255, 178, 85, 255)
                    ],
                    begin: Alignment.centerLeft,
                    end: Alignment.centerRight,
                  ).createShader(
                      Rect.fromLTWH(0, 0, bounds.width, bounds.height));
                },
                child: Text(
                  'LOBBY',
                  style: TextStyle(
                    fontFamily: GoogleFonts.jaro().fontFamily,
                    fontSize: 33,
                    letterSpacing: 1.2,
                    height: 1.0,
                    color: const Color.fromARGB(255, 255, 255, 255),
                  ),
                ),
              ),
              const SizedBox(height: 30),
              Text(
                iAmLeader
                    ? 'You are the Leader'
                    : 'Waiting for the leader to start…',
                style: const TextStyle(color: Colors.white70, fontSize: 16),
              ),
              const SizedBox(height: 16),

              if (iAmLeader) ...[
                Text(
                  'Set Target Score',
                  style: TextStyle(
                    fontSize: 27,
                    fontFamily: GoogleFonts.jaro().fontFamily,
                    color: Colors.white,
                    letterSpacing: 1.3,
                  ),
                ),
                const SizedBox(height: 14),
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    _roundBtn(
                      onTap: () {
                        setState(() {
                          if (targetScore > 1) targetScore--;
                        });
                        _ch?.sink.add(jsonEncode({
                          'type': 'set_target',
                          'value': targetScore,
                        }));
                      },
                      child: const Text(
                        '-',
                        style: TextStyle(color: Colors.white, fontSize: 28),
                      ),
                    ),
                    const SizedBox(width: 26),
                    Text(
                      '$targetScore',
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 56,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                    const SizedBox(width: 26),
                    _roundBtn(
                      onTap: () {
                        setState(() => targetScore++);
                        _ch?.sink.add(jsonEncode({
                          'type': 'set_target',
                          'value': targetScore,
                        }));
                      },
                      child: const Text(
                        '+',
                        style: TextStyle(color: Colors.white, fontSize: 28),
                      ),
                    ),
                  ],
                ),
              ] else ...[
                const Text(
                  'Leader will set the target score',
                  style: TextStyle(
                    fontSize: 18,
                    color: Colors.white60,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 10),
                Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 12, vertical: 8),
                  decoration: BoxDecoration(
                    color: Colors.white.withOpacity(.06),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: Colors.white24, width: .8),
                  ),
                  child: Text(
                    'Target Score: $targetScore',
                    style: const TextStyle(
                        color: Colors.white70, fontSize: 14),
                  ),
                ),
              ],

              const SizedBox(height: 18),
              Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  'Connected Players (${players.length})',
                  style: const TextStyle(
                      color: Colors.white70, fontSize: 14),
                ),
              ),
              const SizedBox(height: 8),

              Expanded(
                child: players.isEmpty
                    ? const Center(
                        child: Text(
                          'No players yet…',
                          style: TextStyle(color: Colors.white38),
                        ),
                      )
                    : ListView.separated(
                        itemCount: players.length,
                        separatorBuilder: (_, __) =>
                            const SizedBox(height: 8),
                        itemBuilder: (_, i) {
                          final p = players[i];
                          final isLeaderBadge = (leaderId == p.id);
                          final isMe = (p.id == myId);
                          return _playerTile(p, isLeaderBadge, isMe);
                        },
                      ),
              ),

              const SizedBox(height: 10),

              Opacity(
                opacity: canStartGame ? 1 : .5,
                child: GestureDetector(
                  onTap: canStartGame ? _startGame : null,
                  child: Container(
                    width: 360,
                    height: 53,
                    padding:
                        const EdgeInsets.symmetric(vertical: 14),
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
                    child: const Text(
                      'START GAME',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 27),
            ],
          ),
        ),
      ),
    );
  }

  Widget _roundBtn({VoidCallback? onTap, required Widget child}) {
    final enabled = onTap != null;
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        width: 56,
        height: 56,
        decoration: BoxDecoration(
          color:
              enabled ? const Color(0xFF2B2F46) : const Color(0xFF1C2035),
          borderRadius: BorderRadius.circular(16),
        ),
        alignment: Alignment.center,
        child: child,
      ),
    );
  }

  Widget _playerTile(_Player p, bool isLeaderBadge, bool isMe) {
    return Container(
      padding:
          const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: const Color(0xFF07162A),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: Colors.white24, width: .8),
      ),
      child: Row(
        children: [
          _teamPill('TEAM ${p.team}', _teamColor(p.team)),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              isMe ? '${p.name} (you)' : p.name,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 16,
                fontWeight: FontWeight.w600,
                letterSpacing: .2,
              ),
            ),
          ),
          if (isLeaderBadge) ...[
            const SizedBox(width: 8),
            const Icon(Icons.workspace_premium,
                color: Colors.amber, size: 18),
          ],
        ],
      ),
    );
  }

  Widget _teamPill(String text, Color color) {
    return Container(
      padding:
          const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(14),
      ),
      child: Text(
        text,
        style: const TextStyle(
          color: Colors.white,
          fontWeight: FontWeight.w700,
          fontSize: 12,
          letterSpacing: .4,
        ),
      ),
    );
  }
}

class _Player {
  final String id;
  final String name;
  final String team;
  _Player({required this.id, required this.name, required this.team});
}



