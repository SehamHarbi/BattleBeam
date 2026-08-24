import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

class ConnectToHub extends StatefulWidget {
  const ConnectToHub({super.key});

  @override
  State<ConnectToHub> createState() => _ConnectToHubState();
}

// تمت إضافة WidgetsBindingObserver لتتبع دورة حياة التطبيق
class _ConnectToHubState extends State<ConnectToHub> with WidgetsBindingObserver {
  // عنوان الهب (Hub URL)
  final String hubPingUrl = 'http://192.168.4.1/api/ping';

  bool _isChecking = false;
  bool _isConnected = false;
  String? _errorMsg;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _checkHub(); //first hub connection check.
  }
  
// Re-checks the hub connection when the app returns to the Page.
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    super.didChangeAppLifecycleState(state);
    if (state == AppLifecycleState.resumed) {
      // يعيد التحقق من الاتصال 
      _checkHub();
    }
  }
  
 
  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }


  //  التحقق من الاتصال بالهب
  // Sends an HTTP ping request to verify that the hub is online and reachable.
 Future<void> _checkHub() async {
    setState(() {
      _isChecking = true;
      _isConnected = false;
      _errorMsg = null;
    });

    try {
  final client = HttpClient();// Creates an HTTP client to communicate with the hub over Wi-Fi.
  final request = await client
      .getUrl(Uri.parse(hubPingUrl))
      .timeout(const Duration(seconds: 5));
  final response = await request.close();

  if (response.statusCode == 200) {
    //  200 = connection successful
    setState(() {
      _isConnected = true;
      _errorMsg = null;
    });
  } else {
    setState(() {
      _isConnected = false;
      _errorMsg = 'Hub responded with ${response.statusCode}';
    });
  }

  client.close();
} catch (e) {
  
} finally {
  setState(() {
    _isChecking = false;
  });
}

  }
  @override
  Widget build(BuildContext context) {
    final jaro = GoogleFonts.jaro().fontFamily;
    
    // الألوان
    const Color disconnectedRed = Colors.redAccent;
    const Color connectedGreen = Colors.greenAccent;

    return Scaffold(
      backgroundColor: const Color(0xFF050827),
      appBar: AppBar(
        backgroundColor: const Color(0xFF050827),
        elevation: 0,
        iconTheme: const IconThemeData(color: Colors.white),
      ),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 24, 20, 16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              // Logo
              Transform.translate(
                offset: const Offset(0, -22),
                child: SizedBox(
                  width: 200,
                  height: 100,
                  child: Image.asset("assets/images/logo3.png"),
                ),
              ),
              const SizedBox(height: 20),

              // Title
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
                    Rect.fromLTWH(0, 0, bounds.width, bounds.height),
                  );
                },
                child: Text(
                  'CONNECT TO HUB',
                  style: TextStyle(
                    fontFamily: jaro,
                    fontSize: 32,
                    letterSpacing: 1.2,
                    height: 1.0,
                    color: Colors.white,
                  ),
                ),
              ),
              const SizedBox(height: 15),

              
              Container(
                width: double.infinity,
                padding: const EdgeInsets.fromLTRB(16, 30, 16, 30),
                decoration: BoxDecoration(
                  color: Colors.white.withOpacity(0.08),
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: Colors.white.withOpacity(0.12)),
                ),
                child: Column(
                  children: const [
                    _StepTile(
                      index: 1,
                      text: 'Open your device settings',
                      icon: Icons.settings_outlined,
                    ),
                    _DividerLine(),
                    _StepTile(
                      index: 2,
                      text: 'Open the Wi-Fi settings',
                      icon: Icons.wifi_outlined,
                    ),
                    _DividerLine(),
                    _StepTile(
                      index: 3,
                      text: "Find the network named 'BattleBeam'.",
                      icon: Icons.search_rounded,
                    ),
                    _DividerLine(),
                    _StepTile(
                      index: 4,
                      text: 'Connect to the network\n'
                          '• Password located under the hub',
                      icon: Icons.lock_open_rounded,
                    ),
                    _DividerLine(),
                    _StepTile(
                      index: 5,
                      text: 'After connecting, return to this app to continue',
                      icon: Icons.arrow_back_rounded,
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 25),

          // Displays the current connection status to the user.
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
          
                  Icon(
                    _isConnected ? Icons.check_circle : Icons.cancel,
                    color: _isConnected ? connectedGreen : disconnectedRed,
                    size: 18,
                  ),
                  const SizedBox(width: 6),
                 
                  Text(
                    _isChecking
                        ? 'Checking connection...'
                        : _isConnected
                            ? 'Connected to hub'
                            : 'Not connected to hub',
                    style: TextStyle(
                      color: _isConnected
                          ? connectedGreen
                          : (_isChecking
                              ? Colors.white70
                              : disconnectedRed),
                      fontSize: 13,
                      fontWeight: FontWeight.w500,
                      letterSpacing: 0.3,
                    ),
                  ),
                ],
              ),

             
              
              const SizedBox(height: 35),

              
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: const [
                  Icon(Icons.info_outline, color: Colors.white54, size: 18),
                  SizedBox(width: 8),
                  Flexible(
                    child: Text(
                      'Stay close to the hub for a stronger signal.',
                      style: TextStyle(color: Colors.white54, fontSize: 12.5),
                      textAlign: TextAlign.center,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 10),

              // Next button (مقفّل إذا مو متصل بالهب)
              Center(
                child: SizedBox(
                  width: 360,
                  height: 53,
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                   
                      gradient: _isConnected 
                          ? const LinearGradient(
                              colors: [
                                Color.fromARGB(255, 34, 86, 229),
                                Color.fromARGB(255, 178, 85, 255)
                              ],
                              begin: Alignment.centerLeft,
                              end: Alignment.centerRight,
                            )
                          : LinearGradient( 
                              colors: [
                                const Color.fromARGB(255, 34, 86, 229).withOpacity(0.3),
                                const Color.fromARGB(255, 178, 85, 255).withOpacity(0.3)
                              ],
                              begin: Alignment.centerLeft,
                              end: Alignment.centerRight,
                            ),
                      borderRadius: BorderRadius.circular(16),
                    ),
                    child: ElevatedButton(
                      onPressed: _isConnected && !_isChecking
                          ? () => Navigator.pushNamed(
                                context,
                                '/player_name',
                              )
                          : null,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.transparent,
                        disabledBackgroundColor: Colors.transparent,
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
                          color: Colors.white.withOpacity(
                            _isConnected && !_isChecking ? 1 : 0.35,
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
      ),
    );
  }
}

//icon and text
class _StepTile extends StatelessWidget {
  final int index;
  final String text;
  final IconData icon;
  const _StepTile({
    required this.index,
    required this.text,
    required this.icon,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        
        Container(
          width: 36,
          height: 36,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: const Color(0xFF1E8AF7),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Text(
            '$index',
            style: const TextStyle(
              color: Colors.white,
              fontWeight: FontWeight.w800,
            ),
          ),
        ),
        const SizedBox(width: 12),

        
        Expanded(
          child: Row(
            children: [
              Icon(icon, color: Colors.white70, size: 20),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  text,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 16,
                    height: 1.2,
                  ),
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
      padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 2),
      child: Divider(
        height: 1,
        color: Colors.white.withOpacity(0.12),
      ),
    );
  }
}