import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'theme/app_theme.dart';
import '../presentation/screens/home_screen.dart';
import '../presentation/viewmodels/recording_viewmodel.dart';

class MyApp extends StatelessWidget {
  const MyApp({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Tunnel IMU',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.lightTheme,
      home: Consumer<RecordingViewModel>(
        builder: (context, viewModel, child) {
          // Optionnel : initialiser le ViewModel au démarrage
          WidgetsBinding.instance.addPostFrameCallback((_) {
            viewModel.initialize();
          });
          return const HomeScreen();
        },
      ),
    );
  }
}
