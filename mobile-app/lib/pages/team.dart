import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../OLD/services/hub_client.dart';//------

class TeamPage extends StatefulWidget {
  const TeamPage({super.key});

  @override
  State<TeamPage> createState() => _TeamPageState();
}

class _TeamPageState extends State<TeamPage> {
  String? selectedTeam;

//-----------
  Future<void> _connectThenGo({
    required String playerName,
    required String teamCode,
  }) async {
    try {
      // يتصل بالهب ويرسل اسم اللاعب والفريق
      await HubClient.I.connect(
        name: playerName,
        teamCode: teamCode,
        tryClaimLeader: true, // أول متصل يصير ليدر
      );

      if (!mounted) return;

      // ينتقل لصفحة اختيار الأجهزة (DevicePickerPage)
      Navigator.pushNamed(
        context,
        '/DevicePickerPage',
        arguments: {
          'name': playerName,
          'team': teamCode, 
        },
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Connection failed: $e')),
      );
    }
  }

//----------
  @override
  Widget build(BuildContext context) {
    final args =
        ModalRoute.of(context)!.settings.arguments as Map<String, dynamic>?;
    final playerName = (args?['name'] as String?) ?? '';

    return Scaffold(
      backgroundColor: const Color.fromARGB(255, 3, 1, 39),
      appBar: AppBar(
        backgroundColor: const Color.fromARGB(255, 3, 1, 39),
        iconTheme: const IconThemeData(color: Colors.white),
      ),
      body: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          children: [
            Transform.translate(
              offset: const Offset(0, -22),
              child: SizedBox(
                width: 220,
                height: 105,
                child: Image.asset("assets/images/logo3.png"),
              ),
            ),
            const SizedBox(height: 60),
            Text(
              "Hello $playerName ",
              style: TextStyle(
                fontSize: 18,
                color: const Color.fromARGB(255, 166, 189, 237),
                fontFamily: GoogleFonts.jaro().fontFamily,
              ),
            ),
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
                "Choose Team",
                style: TextStyle(
                  fontSize: 34,
                  color: const Color.fromARGB(255, 255, 255, 255),
                  fontFamily: GoogleFonts.jaro().fontFamily,
                ),
              ),
            ),
            const SizedBox(height: 15),

           
            TeamChoiceButton(
              team: 'A',
              label: "Team A",
              selected: selectedTeam == 'A',
              onTap: () => setState(() => selectedTeam = 'A'),
            ),
            const SizedBox(height: 30),

           
            TeamChoiceButton(
              team: 'B',
              label: "Team B",
              selected: selectedTeam == 'B',
              onTap: () => setState(() => selectedTeam = 'B'),
            ),

            const SizedBox(height: 180),

            // زر Next يفعّل بعد الاختيار
            Center(
              child: Opacity(
                opacity: selectedTeam == null ? 0.5 : 1,
                child: AbsorbPointer(
                  absorbing: selectedTeam == null,
                  child: SizedBox(
                    width: 360,
                    height: 53,
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        gradient: const LinearGradient(
                          colors: [
                            Color.fromARGB(255, 34, 86, 229),
                            Color(0xFFB255FF)
                          ],
                          begin: Alignment.centerLeft,
                          end: Alignment.centerRight,
                        ),
                        borderRadius: BorderRadius.circular(16),
                      ),
                      child: ElevatedButton(
                        // داخل onPressed لزر NEXT في TeamPage
onPressed: () async {
  final args = ModalRoute.of(context)!.settings.arguments as Map<String, dynamic>?;
  final playerName = (args?['name'] as String?) ?? '';

  // حفظ الفريق باستخدام SharedPreferences
  final p = await SharedPreferences.getInstance();
  await p.setString('player_team', selectedTeam ?? 'A');

  Navigator.pushNamed(
    context,
    '/DevicePickerPage',
    arguments: {
      'name': playerName,
      'team': selectedTeam,
    },
  );
},

                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.transparent,
                          shadowColor: Colors.transparent,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(16),
                          ),
                        ),
                        child: const Text(
                          'NEXT',
                          style: TextStyle(
                            fontWeight: FontWeight.bold,
                            letterSpacing: 1.2,
                            fontSize: 17,
                            color: Colors.white,
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class TeamChoiceButton extends StatelessWidget {
  final String team;     
  final String label;
  final bool selected;
  final VoidCallback onTap;

  const TeamChoiceButton({
    super.key,
    required this.team,
    required this.label,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final bool isTeamA = team == 'A';

    
    final Color bg = selected
        ? (isTeamA
            ? const Color.fromARGB(255, 215, 89, 254)   
            : const Color.fromARGB(255, 34, 86, 229))  
        : const Color.fromARGB(255, 166, 189, 237);

    final Color border = selected
        ? Colors.white.withOpacity(.85)
        : Colors.white.withOpacity(.25);

    return SizedBox(
      width: double.infinity,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 18),
          decoration: BoxDecoration(
            color: bg,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: border, width: 3),
            boxShadow: selected
                ? [
                    BoxShadow(
                      color: bg.withOpacity(0.35),
                      blurRadius: 16,
                      spreadRadius: 1,
                      offset: const Offset(0, 6),
                    ),
                  ]
                : [],
          ),
          alignment: Alignment.center,
          child: Text(
            label,
            style: const TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.w700,
              color: Colors.white,
            ),
          ),
        ),
      ),
    );
  }
}


