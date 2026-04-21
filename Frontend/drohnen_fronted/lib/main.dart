import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'screens/ip_entry_screen.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  // Erzwinge Querformat für die Drohnen-Steuerung
  SystemChrome.setPreferredOrientations([
    DeviceOrientation.landscapeRight,
    DeviceOrientation.landscapeLeft,
  ]).then((_) {
    runApp(const RoboMasterApp());
  });
}

class RoboMasterApp extends StatelessWidget {
  const RoboMasterApp({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'RoboMaster TT Control',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        brightness: Brightness.dark,
        primarySwatch: Colors.blue,
        scaffoldBackgroundColor: Colors.black,
        fontFamily: 'Roboto',
      ),
      home: const IpEntryScreen(),
    );
  }
}
