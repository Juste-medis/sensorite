import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'navigation_screen.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp]);
  SystemChrome.setSystemUIOverlayStyle(const SystemUiOverlayStyle(
    statusBarColor: Colors.transparent,
    statusBarIconBrightness: Brightness.light,
  ));
  runApp(const IMUNavigatorApp());
}

class IMUNavigatorApp extends StatelessWidget {
  const IMUNavigatorApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'IMU Navigator',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        brightness: Brightness.dark,
        scaffoldBackgroundColor: const Color(0xFF0A0E1A),
        primaryColor: const Color(0xFF00E5FF),
        colorScheme: const ColorScheme.dark(
          primary: Color(0xFF00E5FF),
          secondary: Color(0xFFFF6B35),
          surface: Color(0xFF141B2D),
          error: Color(0xFFFF4757),
        ),
        fontFamily: 'monospace',
        useMaterial3: true,
      ),
      home: const NavigationScreen(),
    );
  }
}
