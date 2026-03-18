import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:sensorite/presentation/viewmodels/visualize_viewmodel.dart';
import 'app.dart';
import 'presentation/viewmodels/recording_viewmodel.dart';
import 'presentation/viewmodels/settings_viewmodel.dart';

void main() {
  runApp(
    MultiProvider(
      providers: [
        ChangeNotifierProvider(create: (_) => RecordingViewModel()),
        ChangeNotifierProvider(create: (_) => SettingsViewModel()),
        ChangeNotifierProvider(create: (_) => VisualizeViewModel()),
      ],
      child: const MyApp(),
    ),
  );
}
