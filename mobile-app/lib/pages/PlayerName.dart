import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:shared_preferences/shared_preferences.dart';

class PlayerNamePage extends StatefulWidget {
  const PlayerNamePage({super.key});

 @override
  State<PlayerNamePage> createState() => _PlayerNamePageState();
}

class _PlayerNamePageState extends State<PlayerNamePage> {
  final TextEditingController nameController = TextEditingController();
  bool isNameEntered = false;

 @override
  void initState() {
    super.initState();
    nameController.addListener(() {
      setState(() {
        isNameEntered = nameController.text.trim().isNotEmpty;
      });
    });
  }
  
  @override
  void dispose() {
    nameController.dispose();
    super.dispose();
  }
//-------------------------------------------------------
    @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        backgroundColor: const Color.fromARGB(255, 3, 1, 39),
        iconTheme: const IconThemeData(
          color: Color.fromARGB(255, 248, 248, 248),
        ),
      ),
      body: Container(
        height: double.infinity,
        width: double.infinity,
        color: const Color.fromARGB(255, 3, 1, 39),
        child: Column(
          children: [
       Transform.translate(
  offset: const Offset(0, 15), 
  child: SizedBox(
    width: 200,
    height: 100,
    child: Image.asset("assets/images/logo3.png"),
  ),
)
,
const SizedBox(height: 120),
 ShaderMask(
                shaderCallback: (Rect bounds) {
                  return const LinearGradient(
                    colors: [Color.fromARGB(255, 43, 93, 229), Color.fromARGB(255, 178, 85, 255)],
                    begin: Alignment.centerLeft,
                    end: Alignment.centerRight,
                  ).createShader(Rect.fromLTWH(0, 0, bounds.width, bounds.height));
                },
            child: Text(
              "Enter Your Name",
              style: TextStyle(
                fontSize: 40,
                fontWeight: FontWeight.w500,
                fontFamily: GoogleFonts.jaro().fontFamily,
                color: const Color.fromARGB(255, 255, 255, 255),
              ),
            ),
    ),
            const SizedBox(height: 20),

            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 40),

              child: TextField(
                controller: nameController,
                decoration: InputDecoration(
                  filled: true,
                  fillColor: const Color.fromARGB(255, 166, 189, 237),
                  hintText: "Player Name",
                  hintStyle: const TextStyle(
                    color: Color.fromARGB(255, 41, 32, 97),
                    fontSize: 16,
                  ),
                  prefixIcon: const Icon(Icons.person_outline_outlined),
                  contentPadding:
                      const EdgeInsets.symmetric(horizontal: 15, vertical: 15),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(40),
                  ),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(40),
                    borderSide: const BorderSide(
                      color: Color.fromARGB(255, 12, 79, 107),
                    ),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(40),
                    borderSide: const BorderSide(
                      color: Color.fromARGB(255, 105, 190, 227),
                      width: 3,
                    ),
                  ),
                ),
              ),
            ),

            const SizedBox(height: 285),

Opacity(
  opacity: isNameEntered ? 1 : 0.5,
  child: AbsorbPointer(
    absorbing: !isNameEntered, // يمنع الضغط إذا ما في اسم
    child: Center(
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
           
onPressed: () async {
  final typedName = nameController.text.trim();

  // حفظ الاسم باستخدام SharedPreferences
  final p = await SharedPreferences.getInstance();
  await p.setString('player_name', typedName);

  Navigator.pushNamed(
    context,
    "/team",
    arguments: {"name": typedName},
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
)
         
          ],
        ),
      ),
    );
  }
}





