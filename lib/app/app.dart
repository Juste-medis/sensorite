import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'theme/app_theme.dart';
import '../presentation/screens/home_screen.dart';
import '../presentation/viewmodels/recording_viewmodel.dart';
import '../presentation/viewmodels/settings_viewmodel.dart';

class MyApp extends StatelessWidget {
  const MyApp({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return Consumer<SettingsViewModel>(
      builder: (context, settingsViewModel, child) {
        return MaterialApp(
          title: 'Sensorite',
          debugShowCheckedModeBanner: false,
          theme: AppTheme.lightTheme,
          darkTheme: AppTheme.darkTheme,
          themeMode: settingsViewModel.darkMode
              ? ThemeMode.dark
              : ThemeMode.light,
          home: Consumer<RecordingViewModel>(
            builder: (context, viewModel, child) {
              WidgetsBinding.instance.addPostFrameCallback((_) {
                viewModel.initialize();
              });
              return const HomeScreen();
            },
          ),
        );
      },
    );
  }
}
