
import 'package:flutter/material.dart';
import 'package:flutter_application_2/pages/PlayerName.dart';
import 'package:flutter_application_2/pages/VictoryPage.dart';
import 'package:flutter_application_2/pages/gamep.dart';
import 'package:flutter_application_2/pages/ConnectToHub.dart';
import 'package:flutter_application_2/pages/DevicePickerPage.dart';
import 'package:flutter_application_2/pages/instruction.dart';
import 'package:flutter_application_2/pages/score.dart';
import 'package:flutter_application_2/pages/team.dart';
import 'package:flutter_application_2/pages/welcome.dart';


void main() {
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  // This widget is the root of your application.
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      initialRoute: "/",
      routes: {
         "/" :(context) => const Welcome(),
        //"/guid" :(context) => const Guide(),
        "/ConnectToHub" :(context) => const ConnectToHub(),
        "/player_name" :(context) => const PlayerNamePage(),
        "/team" :(context) =>   TeamPage(),
        "/DevicePickerPage" :(context) => const DevicePickerPage(),
        "/score" :(context) => const LobbyPage(),
        "/gamep" :(context) => const GamePage2(),
        "/VictoryPage" :(context) => const VictoryPage(),
        "/instructions" :(context) => const InstructionsPage(),
      },


       builder: (context, child) {
    final media = MediaQuery.of(context);
    return MediaQuery(
      data: media.copyWith(
        textScaler: const TextScaler.linear(1.0), // قفل تكبير النص للنظام
        boldText: false, // اختياري: تجاهل “نص عريض” من إعدادات الوصول
      ),
      child: child!,
    );
  },

    );
  }
}
