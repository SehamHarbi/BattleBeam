import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

class InstructionsPage extends StatelessWidget {
  const InstructionsPage({super.key});

  @override
  Widget build(BuildContext context) {
    final jaro = GoogleFonts.jaro().fontFamily;

    return Scaffold(
      backgroundColor: const Color(0xFF050827),
      appBar: AppBar(
        backgroundColor: const Color(0xFF050827),
        elevation: 0,
        iconTheme: const IconThemeData(color: Colors.white),
        
      ),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 10, 20, 16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
Transform.translate(
  offset: const Offset(0, -10), 
  child: SizedBox(
    width: 200,
    height: 100,
    child: Image.asset("assets/images/logo3.png"),
  ),
),
const SizedBox(height: 20),

              ShaderMask(
                shaderCallback: (Rect bounds) {
                  return const LinearGradient(
                    colors: [Color.fromARGB(255, 43, 93, 229), Color.fromARGB(255, 178, 85, 255)],
                    begin: Alignment.centerLeft,
                    end: Alignment.centerRight,
                  ).createShader(Rect.fromLTWH(0, 0, bounds.width, bounds.height));
                },
            
              child: Text(
                'Read before you start',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontFamily: jaro,
                  
                  fontSize: 32,
                  color: const Color.fromARGB(255, 255, 255, 255),
                  letterSpacing: 1.1,
                ),
              ),
              ),
             const SizedBox(height: 8),

              // التعليمات
              Container(
                padding: const EdgeInsets.fromLTRB(18, 20, 18, 16),
                decoration: BoxDecoration(
                  color: Colors.white.withOpacity(0.08),
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: Colors.white.withOpacity(0.12)),
                ),
                child: Column(
                  children: const [
                    _InstructionItem(
                      icon: Icons.workspace_premium_rounded,
                      title: 'Leader selection',
                      text:
                          'The first player who connects to the hub becomes the leader',
                    ),
                    _DividerLine(),
                    _InstructionItem(
                      icon: Icons.sports_esports_rounded,
                      title: 'Leader responsibility',
                      text:
                          '• Sets the target score for the match\n'
                          '• Starts the match\n'
                          '• End the game even if the target score has not been reached ' ,
                    ),
                    _DividerLine(),
                    _InstructionItem(
                      icon: Icons.check_circle_outline_rounded,
                      title: 'Equipment match',
                      text:
                          'Make sure the gun and vest you selected in the app match the ones you are using in real life',
                    ),
                  ],
                ),
              ),

              
             const SizedBox(height: 76),


              // زر Next 
              Center(
                child: SizedBox(
                   width: 360,
                    height: 53,
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      gradient: const LinearGradient(
                        colors: [Color.fromARGB(255, 34, 86, 229), Color.fromARGB(255, 178, 85, 255)],
                        begin: Alignment.centerLeft,
                        end: Alignment.centerRight,
                      ),
                      borderRadius: BorderRadius.circular(16),
                    ),
                    child: ElevatedButton(
                      onPressed: () => Navigator.pushNamed(context, '/ConnectToHub'),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.transparent,
                        shadowColor: Colors.transparent,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(16),
                        ),
                      ),
                      child: Text(
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
            ],
          ),
        ),
      ),
    );
  }
}

class _InstructionItem extends StatelessWidget {
  final IconData icon;
  final String title;
  final String text;
  const _InstructionItem({
    required this.icon,
    required this.title,
    required this.text,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // أيقونة
        Container(
          width: 40,
          height: 40,
          margin: const EdgeInsets.only(top: 2),
          decoration: BoxDecoration(
            color: const Color(0xFF1E8AF7),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Icon(icon, color: Colors.white),
        ),
        const SizedBox(width: 12),

       
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: const TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.w800,
                  fontSize: 18,
                  height: 1.1,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                text,
                style: const TextStyle(
                  color: Colors.white70,
                  fontSize: 16,
                  height: 1.35,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _DividerLine extends StatelessWidget {
  const _DividerLine();
  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 14),
      child: Divider(height: 1, color: Colors.white.withOpacity(0.12)),
    );
  }
}
