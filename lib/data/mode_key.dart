// ignore_for_file: non_constant_identifier_names, prefer_typing_uninitialized_variables

import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:nb_utils/nb_utils.dart';
import 'package:sensorite/core/utils/utls.dart';

StreamSubscription? subscription;

void startInternetListening({bool forceRestart = false}) {
  if (kIsWeb) {
    Sks.isNetworkAvailable = true;
  }
  if (subscription != null) {
    if (!forceRestart) return;
    subscription!.cancel();
    subscription = null;
  }
  myprint("Connectivity changed: $subscription");

  subscription = Connectivity().onConnectivityChanged.listen(
    (List<ConnectivityResult> result) {
      if (result.isNotEmpty && result.first != ConnectivityResult.none) {
        if (!Sks.isNetworkAvailable) {
          Sks.isNetworkAvailable = true;
          // OfflineStorageService.syncOfflineDatas();
        }
      } else {
        Sks.isNetworkAvailable = false;
      }
    },
    onError: (_) {
      Sks.isNetworkAvailable = false;
    },
    cancelOnError: false,
  );
}

void stopListening() {
  subscription?.cancel();
}

class Sks {
  static dynamic Function() createAnswer = () async {};
  static dynamic Function() closeCall = () async {};
  static Future<void> Function() savereviewStep = () async {};
  static List<VoidCallback> overlayentriesClosers = [];
  static Map ldImages = {};
  static bool isNetworkAvailable = false;
}
