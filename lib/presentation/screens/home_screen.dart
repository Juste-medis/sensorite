import 'package:flutter/material.dart';
import 'package:location/location.dart' as loc;
import 'package:nb_utils/nb_utils.dart';
import 'package:sensorite/core/models/sensor_data.dart';
import 'package:sensorite/core/utils/utls.dart';
import 'package:sensorite/presentation/map/mapview.dart';
import 'settings_screen.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({Key? key}) : super(key: key);

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  loc.LocationData? _latestLocation;
  SensorData? _latestSensorData;

  void _handleRealtimeData(loc.LocationData location, SensorData? sensorData) {
    if (!mounted) return;
    setState(() {
      _latestLocation = location;
      _latestSensorData = sensorData;
    });
  }

  String _fmt(double? value, {int digits = 6}) {
    if (value == null) return '--';
    return value.toStringAsFixed(digits);
  }

  @override
  Widget build(BuildContext context) {
    final location = _latestLocation;
    final sensor = _latestSensorData;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Sensorite'),
        actions: [
          IconButton(
            icon: const Icon(Icons.settings_outlined),
            onPressed: () => Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const SettingsScreen()),
            ),
          ),
        ],
      ),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              flex: 5,
              child: SizedBox.expand(
                child: OSMFlutterMap(onRealtimeData: _handleRealtimeData),
              ),
            ),
            const SizedBox(height: 10),
            Expanded(
              flex: 2,
              child: Container(
                width: double.infinity,
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Theme.of(
                    context,
                  ).colorScheme.surfaceContainerHighest.withOpacity(0.35),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: SingleChildScrollView(
                  child: DefaultTextStyle(
                    style: Theme.of(context).textTheme.bodyMedium!,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Coordonnées (temps réel)',
                          style: Theme.of(context).textTheme.titleSmall,
                        ),
                        Text('Lat: ${_fmt(location?.latitude)}'),
                        Text('Lng: ${_fmt(location?.longitude)}'),
                        Text('Heading: ${_fmt(location?.heading, digits: 2)}°'),
                        Text('Speed: ${_fmt(location?.speed, digits: 2)} m/s'),
                        const SizedBox(height: 10),
                        Text(
                          'SensorData (temps réel)',
                          style: Theme.of(context).textTheme.titleSmall,
                        ),
                        Text(
                          'Timestamp: ${sensor?.timestamp.toIso8601String() ?? '--'}',
                        ),
                        Text(
                          'Accel: x=${_fmt(sensor?.accelX, digits: 3)}, y=${_fmt(sensor?.accelY, digits: 3)}, z=${_fmt(sensor?.accelZ, digits: 3)}',
                        ),
                        Text(
                          'Gyro: x=${_fmt(sensor?.gyroX, digits: 3)}, y=${_fmt(sensor?.gyroY, digits: 3)}, z=${_fmt(sensor?.gyroZ, digits: 3)}',
                        ),
                        50.height,
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
