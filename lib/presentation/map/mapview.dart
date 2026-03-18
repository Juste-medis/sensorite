import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:location/location.dart' as loc;
import 'package:permission_handler/permission_handler.dart';
import 'package:sensorite/core/utils/utls.dart';
import 'package:sensorite/presentation/map/marker.dart';

class OSMFlutterMap extends StatefulWidget {
  const OSMFlutterMap({super.key});

  @override
  State<OSMFlutterMap> createState() => _OSMFlutterMapState();
}

class _OSMFlutterMapState extends State<OSMFlutterMap> {
  final MapController _mapController = MapController();
  final loc.Location _location = loc.Location();

  loc.LocationData? _currentLocation;
  StreamSubscription<loc.LocationData>? _locationSub;
  bool _hasCentered = false;

  @override
  void initState() {
    super.initState();
    _startRealtimeLocation();
  }

  @override
  void dispose() {
    _locationSub?.cancel();
    super.dispose();
  }

  Future<void> _startRealtimeLocation() async {
    final firstLocation = await getLocationCoordinates();
    if (!mounted) return;

    if (firstLocation != null) {
      setState(() => _currentLocation = firstLocation);
    }

    _locationSub = _location.onLocationChanged.listen((
      loc.LocationData currentLocation,
    ) {
      if (!mounted) return;
      if (currentLocation.latitude == null || currentLocation.longitude == null)
        return;

      setState(() {
        _currentLocation = currentLocation;
      });
      myprint(
        "Location updated: ${currentLocation.latitude}, ${currentLocation.longitude}, heading: ${currentLocation.heading}",
      );
      final currentPoint = LatLng(
        currentLocation.latitude!,
        currentLocation.longitude!,
      );

      // Recentre la carte une seule fois au premier fix
      if (!_hasCentered) {
        _mapController.move(currentPoint, 18);
        _hasCentered = true;
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final lat = _currentLocation?.latitude;
    final lng = _currentLocation?.longitude;
    final heading = _currentLocation?.heading ?? 0.0;

    return FlutterMap(
      mapController: _mapController,
      options: MapOptions(
        initialCenter: LatLng(lat ?? 0.0, lng ?? 0.0),
        initialZoom: 20,
      ),
      children: [
        TileLayer(
          urlTemplate: 'http://82.29.175.22:8080/tile/{z}/{x}/{y}.png',
          userAgentPackageName: 'com.sensorite.map.sensorite',
        ),
        if (lat != null && lng != null)
          MarkerLayer(
            markers: [
              Marker(
                point: LatLng(lat, lng),
                width: 20,
                height: 20,
                child: RealtimeUserMarker(heading: heading),
              ),
            ],
          ),
      ],
    );
  }
}

Future<loc.LocationData?> getLocationCoordinates() async {
  loc.Location location = loc.Location();
  try {
    bool serviceEnabled = await location.serviceEnabled();
    if (!serviceEnabled) {
      serviceEnabled = await location.requestService();
      if (!serviceEnabled) {
        throw Exception("Location services are disabled.");
      }
    }

    final coordinates = await location.getLocation();
    return coordinates;
  } catch (e) {
    if (e is PlatformException) {
      loc.PermissionStatus permissionGranted = await location.hasPermission();

      if (e.code == "PERMISSION_DENIED_NEVER_ASK") {
        await openAppSettings();
        throw Exception("Permission denied forever. Redirected to settings.");
      } else if (permissionGranted == loc.PermissionStatus.denied) {
        permissionGranted = await location.requestPermission();
        if (permissionGranted != loc.PermissionStatus.granted) {
          throw Exception("Location permission denied.");
        }
      }
    }

    return null;
  }
}
