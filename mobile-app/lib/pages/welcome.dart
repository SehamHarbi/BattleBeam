import 'dart:ui' as Colors;
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

class Welcome extends StatelessWidget {
  const Welcome({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
        body: Container(
          height: double.infinity,
          width: double.infinity,
          color: const Color.fromARGB(255, 3, 1, 39),
          
          child: Stack(
            children: [
              SizedBox(
                width: double.infinity,
                child: Column(
                  children: [
                    SizedBox(
                      height: 150,
                    ),

                    Text("WELCOME TO", style: TextStyle(fontSize: 25,fontWeight: FontWeight.w500 ,  color: const Colors.Color.fromARGB(255, 248, 248, 248)),),
                    SizedBox(
                      height: 10,
                    ),
                    ShaderMask(
  shaderCallback: (bounds) => const LinearGradient(
    colors: [
      Colors.Color.fromARGB(255, 34, 86, 229), 
      Colors.Color.fromARGB(255, 124, 37, 238),
      Colors.Color.fromARGB(255, 247, 75, 222), 
    ],
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
  ).createShader(Rect.fromLTWH(0, 0, bounds.width, bounds.height)),
  child: Text(
    "BATTLEBEAM",
    style: TextStyle(
      fontSize: 60,
      fontWeight: FontWeight.w500,
      fontFamily:GoogleFonts.jaro().fontFamily,
      letterSpacing: 2,
      color: Colors.Color(0xFFFFFFFF),
    ),
  ),
),
                    SizedBox(
                      height: 15,
                    ),
                    Image.asset("assets/images/logo3.png", width: 290,),
                    
                    SizedBox(
                      height: 155,
                    ),


 Container(
  width: 360,
  height: 53,
  decoration: BoxDecoration(
    borderRadius: BorderRadius.circular(16),
    gradient: const LinearGradient(
      colors: [
        Colors.Color.fromARGB(255, 34, 86, 229), 
        Colors.Color.fromARGB(255, 178, 85, 255), 
      ],
      begin: Alignment.centerLeft,
      end: Alignment.centerRight,
    ),
  ),
  child: ElevatedButton(
    onPressed: () {
      Navigator.pushNamed(context, "/instructions");
    },
    style: ElevatedButton.styleFrom(
      backgroundColor: Colors.Color(0x00000000),
      shadowColor: Colors.Color(0x00000000),  
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
      ),
    ),
    child: Text(
      "GET STARTED",
      style: TextStyle(
        fontSize: 18,
        fontWeight: FontWeight.bold,
        
        color: Colors.Color.fromARGB(255, 233, 235, 235),
      ),
    ),
  ),
),

                  ],
                ),
              ),
            ],
          ),
        ),
      );
  }
}