import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:web_socket_channel/web_socket_channel.dart';
import 'package:google_fonts/google_fonts.dart';

// ===== البيانات الأساسية =====
enum DeviceKind { gun, vest, app, unknown }

class HubDevice {
  final String id;
  final DeviceKind kind;   // gun / vest
  final String team;       // 'A' أو 'B'
  String name;
  int battery;             // 0..100
  bool online;             // متصل؟
  final String? claimedBy; // player_id (من الهب فقط، ما نعدله محلياً)

  HubDevice({
    required this.id,
    required this.kind,
    required this.team,
    required this.name,
    required this.battery,
    required this.online,
    this.claimedBy,
  });

  factory HubDevice.fromJson(Map<String, dynamic> j) {
    final k = (j['kind'] ?? '').toString().toLowerCase();
    DeviceKind kind;
    switch (k) {
      case 'gun':
        kind = DeviceKind.gun;
        break;
      case 'vest':
        kind = DeviceKind.vest;
        break;
      case 'app':
        kind = DeviceKind.app;
        break;
      default:
        kind = DeviceKind.unknown;
    }

    return HubDevice(
      id: j['id'].toString(),
      kind: kind,
      team: (j['team'] ?? 'A').toString().toUpperCase(),
      name: (j['name'] ?? '').toString(),
      battery: (j['battery'] is num) ? (j['battery'] as num).toInt() : 0,
      online: j['online'] == true || (j['status']?.toString() == 'enabled'),
      claimedBy: (j['claimed_by']?.toString().isEmpty ?? true)
          ? null
          : j['claimed_by'].toString(),
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'kind': () {
          switch (kind) {
            case DeviceKind.vest:
              return 'vest';
            case DeviceKind.gun:
              return 'gun';
            case DeviceKind.app:
              return 'app';
            default:
              return 'unknown';
          }
        }(),
        'team': team,
        'name': name,
        'battery': battery,
        'online': online,
        'claimed_by': claimedBy,
      };
}

// ===== الصفحة =====
class DevicePickerPage extends StatefulWidget {
  const DevicePickerPage({super.key});

  @override
  State<DevicePickerPage> createState() => _DevicePickerPageState();
}

class _DevicePickerPageState extends State<DevicePickerPage> {
  final bool useMock = false;

  WebSocketChannel? _ch;
  Timer? _pingTimer;

  // بيانات اللاعب
  late String myId;
  late String myName;
  String myTeam = 'A';

  final Map<String, HubDevice> _devices = {};
  String? _selectedGunId;
  String? _selectedVestId;

  bool _loading = false;
  bool _inited = false;

  @override
  void initState() {
    super.initState();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_inited) return;
    _inited = true;

    final args =
        ModalRoute.of(context)?.settings.arguments as Map<String, dynamic>?;
    final t = (args?['team'] as String?)?.toUpperCase();
    if (t == 'A' || t == 'B') myTeam = t!;
    final n = (args?['name'] as String?);
    myName = (n != null && n.trim().isNotEmpty) ? n.trim() : 'Player';

    _loadMe().then((_) => useMock ? _seedMock() : _connect());
  }

  Future<void> _loadMe() async {
    final p = await SharedPreferences.getInstance();
    myId = p.getString('player_id') ??
        DateTime.now().millisecondsSinceEpoch.toString();
    await p.setString('player_id', myId);

    // نحترم الاسم لو محفوظ من قبل
    final savedName = p.getString('player_name');
    if (savedName == null || savedName.isEmpty) {
      await p.setString('player_name', myName);
    } else {
      myName = savedName;
    }
  }

  // ===== Mock =====
  void _seedMock() {
    _devices.clear();
    for (var i = 1; i <= 2; i++) {
      _devices['GUN-A$i'] = HubDevice(
        id: 'GUN-A$i',
        kind: DeviceKind.gun,
        team: 'A',
        name: 'Gun A#$i',
        battery: 90,
        online: true,
      );
    }
    for (var i = 1; i <= 2; i++) {
      _devices['VEST-A$i'] = HubDevice(
        id: 'VEST-A$i',
        kind: DeviceKind.vest,
        team: 'A',
        name: 'Vest A#$i',
        battery: 80,
        online: true,
      );
    }
    setState(() => _loading = false);
  }

  // ===== WebSocket =====
  void _connect() {
    _ch = WebSocketChannel.connect(Uri.parse('ws://192.168.4.1/ws'));

    // نسجل كـ "picker" مو app عشان ما يظهر في اللوبي
    _ch!.sink.add(jsonEncode({
      'type': 'register',
      'deviceId': myId,
      'kind': 'picker',
      'team': myTeam,
      'name': myName,
    }));

    // نسمع الرسائل
    _ch!.stream.listen(
      (raw) {
        final msg = jsonDecode(raw);
        switch (msg['type']) {
          case 'devices':
            final list = (msg['items'] as List?) ?? [];
            _devices.clear(); // ← مهم: نفرغ القديم عشان ما يبقى شيء قديم
            for (final e in list) {
              final d = HubDevice.fromJson(Map<String, dynamic>.from(e));
              _devices[d.id] = d;
            }
            setState(() => _loading = false);
            break;

          case 'device_update':
          case 'device_state':
            final d = HubDevice.fromJson(
                Map<String, dynamic>.from(msg['device'] as Map));
            _devices[d.id] = d;

            // لو السلاح/السترة اللي اخترناها صارت محجوزة لشخص ثاني من الهب → نشيل اختيارنا
            if (_selectedGunId != null &&
                _selectedGunId == d.id &&
                d.claimedBy != null &&
                d.claimedBy != myId) {
              _selectedGunId = null;
            }
            if (_selectedVestId != null &&
                _selectedVestId == d.id &&
                d.claimedBy != null &&
                d.claimedBy != myId) {
              _selectedVestId = null;
            }
            setState(() {});
            break;

          case 'devices_list':
            final list2 = (msg['devices'] as List?) ?? [];
            _devices.clear();
            for (final e in list2) {
              final d = HubDevice.fromJson(Map<String, dynamic>.from(e));
              _devices[d.id] = d;
            }
            setState(() => _loading = false);
            break;
        }
      },
      onError: (e) {
        if (!mounted) return;
        setState(() => _loading = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('WS error: $e')),
        );
      },
      onDone: () {
        if (!mounted) return;
        _pingTimer?.cancel();
        setState(() => _loading = false);
      },
    );

    // نطلب الأجهزة
    _ch!.sink.add(jsonEncode({'type': 'get_devices'}));

    // ping دوري
    _pingTimer?.cancel();
    _pingTimer = Timer.periodic(const Duration(seconds: 5), (_) {
      _ch?.sink.add(jsonEncode({'type': 'ping', 'deviceId': myId}));
    });
  }

  // اختيار محلي (ما نمسّ claimedBy أبداً)
  void _toggleClaim(HubDevice d) {
    if (!d.online) return;

    final isTakenByOther =
        d.claimedBy != null && d.claimedBy!.isNotEmpty && d.claimedBy != myId;
    if (isTakenByOther) return; // محجوز من لاعب ثاني

    setState(() {
      if (d.kind == DeviceKind.gun) {
        if (_selectedGunId == d.id) {
          _selectedGunId = null;
        } else {
          _selectedGunId = d.id;
        }
      } else if (d.kind == DeviceKind.vest) {
        if (_selectedVestId == d.id) {
          _selectedVestId = null;
        } else {
          _selectedVestId = d.id;
        }
      }
    });
  }

  Future<void> _confirmAndContinue() async {
    if (_selectedGunId == null || _selectedVestId == null) return;

    if (!useMock) {
      _ch?.sink.add(jsonEncode({
        'type': 'player_ready',
        'player_id': myId,
        'gun_id': _selectedGunId,
        'vest_id': _selectedVestId,
      }));

      // نخزن رقم السترة في SharedPreferences عشان GamePage تستخدمه
      final p = await SharedPreferences.getInstance();
      await p.setString('my_vest_id', _selectedVestId!);
    }

    // ننتقل لصفحة اللوبي (روتها عندك /score)
    Navigator.pushReplacementNamed(
      context,
      '/score',
      arguments: {
        'team': myTeam,
        'name': myName,
      },
    );
  }

  @override
  void dispose() {
    _pingTimer?.cancel();
    _ch?.sink.close();
    super.dispose();
  }

  // ===== UI =====
  @override
  Widget build(BuildContext context) {
    final teamColor = myTeam == 'A'
        ? const Color.fromARGB(255, 215, 89, 254)
        : const Color.fromARGB(255, 43, 93, 229);

    final guns = _devices.values
        .where((d) => d.team == myTeam && d.kind == DeviceKind.gun && d.online)
        .toList();

    final vests = _devices.values
        .where((d) => d.team == myTeam && d.kind == DeviceKind.vest && d.online)
        .toList();

    return Scaffold(
      backgroundColor: const Color(0xFF050827),
      appBar: AppBar(
        backgroundColor: const Color(0xFF050827),
        elevation: 0,
        iconTheme: const IconThemeData(color: Colors.white),
        title: Row(
          children: [
            const Spacer(),
            _teamChip('TEAM $myTeam', teamColor),
          ],
        ),
      ),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
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
                  ).createShader(Rect.fromLTWH(0, 0, bounds.width, bounds.height));
                },
                child: Text(
                  'SELECT YOUR EQUIPMENT',
                  style: TextStyle(
                    fontFamily: GoogleFonts.jaro().fontFamily,
                    fontSize: 32,
                    letterSpacing: 1.2,
                    height: 1.0,
                    color: const Color.fromARGB(255, 255, 255, 255),
                  ),
                ),
              ),
              const SizedBox(height: 15),
              _sectionTitle('Guns'),
              const SizedBox(height: 8),
              if (guns.isEmpty)
                _empty('No guns online for Team $myTeam')
              else
                ...guns.map((d) => _deviceTile(d)),

              const SizedBox(height: 16),
              _sectionTitle('Vests'),
              const SizedBox(height: 8),
              if (vests.isEmpty)
                _empty('No vests online for Team $myTeam')
              else
                ...vests.map((d) => _deviceTile(d)),

              const Spacer(),

              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: const [
                  Icon(Icons.info_outline, color: Colors.white54, size: 18),
                  SizedBox(width: 8),
                  Flexible(
                    child: Text(
                      'Make sure the guns and vests you take are the same ones you selected in the app.',
                      style: TextStyle(
                        color: Colors.white54,
                        fontSize: 12.5,
                        height: 1.3,
                      ),
                      textAlign: TextAlign.start,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              _confirmButton(
                enabled: _selectedGunId != null && _selectedVestId != null,
                onTap: _confirmAndContinue,
              ),
              const SizedBox(height: 20),
            ],
          ),
        ),
      ),
    );
  }

  Widget _sectionTitle(String t) => Text(
        t,
        style: const TextStyle(
          color: Colors.white70,
          fontSize: 14,
          letterSpacing: .6,
          fontWeight: FontWeight.w700,
        ),
      );

  Widget _deviceTile(HubDevice d) {
    // هل هذا الجهاز محجوز من لاعب آخر (من الهب)؟
    final bool isTakenByOther =
        d.claimedBy != null && d.claimedBy!.isNotEmpty && d.claimedBy != myId;

    // هل أنا اخترته في هذه الصفحة؟
    final bool isMineSelected =
        (d.kind == DeviceKind.gun && _selectedGunId == d.id) ||
        (d.kind == DeviceKind.vest && _selectedVestId == d.id);

    const cyan = Color.fromARGB(255, 93, 152, 229);

    return Opacity(
      opacity: isTakenByOther ? .45 : 1,
      child: GestureDetector(
        onTap: isTakenByOther ? null : () => _toggleClaim(d),
        child: Container(
          margin: const EdgeInsets.only(bottom: 10),
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          decoration: BoxDecoration(
            color: const Color(0xFF091539),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: isMineSelected ? cyan : Colors.white24,
              width: 2,
            ),
            boxShadow: [
              if (isMineSelected)
                BoxShadow(
                  color: cyan.withOpacity(.25),
                  blurRadius: 12,
                  offset: const Offset(0, 6),
                ),
            ],
          ),
          child: Row(
            children: [
              _deviceIcon(d.kind),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      d.name.isEmpty
                          ? (d.kind == DeviceKind.gun ? 'Gun' : 'Vest')
                          : d.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.w800,
                        fontSize: 16,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      'ID: ${d.id}',
                      style: const TextStyle(
                        color: Colors.white60,
                        fontSize: 12,
                        letterSpacing: .2,
                      ),
                    ),
                  ],
                ),
              ),
              _selectDot(selected: isMineSelected),
            ],
          ),
        ),
      ),
    );
  }

  Widget _selectDot({required bool selected}) {
    const cyan = Color(0xFF63E0F5);
    return Container(
      width: 24,
      height: 24,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        border: Border.all(color: cyan, width: 3),
        color: selected ? cyan.withOpacity(.25) : Colors.transparent,
      ),
      child: selected
          ? Center(
              child: Container(
                width: 10,
                height: 10,
                decoration: const BoxDecoration(
                  shape: BoxShape.circle,
                  color: cyan,
                ),
              ),
            )
          : null,
    );
  }

  Widget _deviceIcon(DeviceKind kind) {
    final asset = kind == DeviceKind.gun
        ? 'assets/images/gun_icon.png'
        : 'assets/images/vest_icon.png';
    return SizedBox(
      width: 28,
      height: 28,
      child: Image.asset(
        asset,
        fit: BoxFit.contain,
        errorBuilder: (_, __, ___) => Icon(
          kind == DeviceKind.gun ? Icons.sports_kabaddi : Icons.shield,
          color: Colors.white,
          size: 24,
        ),
      ),
    );
  }

  Widget _teamChip(String text, Color color) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          color: color,
          borderRadius: BorderRadius.circular(16),
        ),
        child: Text(
          text,
          style: const TextStyle(
            color: Colors.white,
            fontWeight: FontWeight.w700,
          ),
        ),
      );

  Widget _empty(String t) => Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(vertical: 20),
        alignment: Alignment.centerLeft,
        child: Text(t, style: const TextStyle(color: Colors.white38)),
      );

  Widget _confirmButton({
    required bool enabled,
    required VoidCallback onTap,
  }) {
    return Align(
      alignment: Alignment.center,
      child: Opacity(
        opacity: enabled ? 1 : .5,
        child: GestureDetector(
          onTap: enabled ? onTap : null,
          child: Container(
            constraints: const BoxConstraints(maxWidth: 360),
            height: 53,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(16),
              gradient: const LinearGradient(
                colors: [Color(0xFF2256E5), Color(0xFFB255FF)],
                begin: Alignment.centerLeft,
                end: Alignment.centerRight,
              ),
            ),
            child: const Center(
              child: Text(
                'CONFIRM & CONTINUE',
                style: TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.bold,
                  letterSpacing: 0.8,
                  fontSize: 16,
                ),
                textAlign: TextAlign.center,
              ),
            ),
          ),
        ),
      ),
    );
  }
}



