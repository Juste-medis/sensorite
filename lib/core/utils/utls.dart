// ignore_for_file: inference_failure_on_untyped_parameter, non_constant_identifier_names, avoid_print, type_annotate_public_apis

import 'dart:async';
import 'dart:developer';
import 'dart:io';
import 'dart:math';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'dart:convert';

import 'package:flutter/gestures.dart';
import 'package:intl/intl.dart';

import 'package:permission_handler/permission_handler.dart';
import 'package:path/path.dart' as p;

import 'package:flutter/services.dart'
    show Clipboard, ClipboardData, rootBundle;
import 'package:path_provider/path_provider.dart';

import 'package:nb_utils/nb_utils.dart';

InputDecoration inputDecoration(
  BuildContext context, {
  String? labelText,
  String? hintText,
  Widget? prefixIcon,
  Widget? suffixIcon,
  Color? fillColor,
  double borderRadius = 8.0,
  bool isDense = true,
  bool floatingLabel = true,
  EdgeInsetsGeometry? contentPadding,
  Color? focusedBorderColor,
  String? errorText,
  int? errorMaxLines,
}) {
  final theme = Theme.of(context);
  final isDark = theme.brightness == Brightness.dark;

  // Default colors
  final defaultFillColor = isDark
      ? theme.colorScheme.surfaceContainerHighest.withOpacity(0.5)
      : gray.withOpacity(0.1);

  final defaultFocusColor = theme.colorScheme.primary;
  final defaultErrorColor = theme.colorScheme.error;
  //thee text color is set with labelStyle and hintStyle
  return InputDecoration(
    // Content
    labelText: labelText,
    hintText: hintText,
    alignLabelWithHint: true,
    floatingLabelBehavior: floatingLabel
        ? FloatingLabelBehavior.auto
        : FloatingLabelBehavior.never,

    // Icons
    prefixIcon: prefixIcon,
    suffixIcon: suffixIcon,
    prefixIconConstraints: const BoxConstraints(minWidth: 40, maxHeight: 24),
    suffixIconConstraints: const BoxConstraints(minWidth: 40, maxHeight: 24),

    // Layout
    isDense: isDense,
    contentPadding:
        contentPadding ??
        const EdgeInsets.symmetric(horizontal: 16, vertical: 18),

    // Borders
    border: OutlineInputBorder(
      borderRadius: BorderRadius.circular(borderRadius),
      borderSide: BorderSide.none,
    ),
    enabledBorder: OutlineInputBorder(
      borderRadius: BorderRadius.circular(borderRadius),
      borderSide: BorderSide.none,
    ),
    focusedBorder: OutlineInputBorder(
      borderRadius: BorderRadius.circular(borderRadius),
      borderSide: BorderSide(
        color: focusedBorderColor ?? defaultFocusColor,
        width: 1.5,
      ),
    ),
    errorBorder: OutlineInputBorder(
      borderRadius: BorderRadius.circular(borderRadius),
      borderSide: BorderSide(color: defaultErrorColor, width: 1.0),
    ),
    focusedErrorBorder: OutlineInputBorder(
      borderRadius: BorderRadius.circular(borderRadius),
      borderSide: BorderSide(color: defaultErrorColor, width: 1.5),
    ),

    // Colors
    filled: true,
    fillColor: fillColor ?? defaultFillColor,
    hoverColor: theme.colorScheme.primary.withOpacity(0.05),

    // Label styles
    labelStyle: theme.textTheme.bodyMedium?.copyWith(
      color: theme.colorScheme.onSurface.withOpacity(0.6),
    ),
    hintStyle: theme.textTheme.bodyMedium?.copyWith(
      color: theme.colorScheme.onSurface.withOpacity(0.4),
    ),
    floatingLabelStyle: theme.textTheme.bodyMedium?.copyWith(
      color: focusedBorderColor ?? defaultFocusColor,
    ),

    // Error handling
    errorText: errorText,
    errorMaxLines: errorMaxLines ?? 2,
    errorStyle: theme.textTheme.bodySmall?.copyWith(color: defaultErrorColor),
  );
}

InputDecoration inputDecoration2(
  BuildContext context, {
  Widget? prefixIcon,
  String? labelText,
  double? borderRadius,
}) {
  return InputDecoration(
    contentPadding: const EdgeInsets.only(
      left: 12,
      bottom: 10,
      top: 10,
      right: 10,
    ),
    labelText: labelText,
    labelStyle: secondaryTextStyle(),
    alignLabelWithHint: true,
    prefixIcon: prefixIcon,
    enabledBorder: OutlineInputBorder(
      borderRadius: borderRadius != null
          ? radius(borderRadius)
          : BorderRadius.circular(8.0),
      borderSide: const BorderSide(color: Colors.grey, width: 2),
    ),
    focusedErrorBorder: OutlineInputBorder(
      borderRadius: borderRadius != null
          ? radius(borderRadius)
          : BorderRadius.circular(8.0),
      borderSide: const BorderSide(color: Colors.grey, width: 2),
    ),
    errorBorder: OutlineInputBorder(
      borderRadius: borderRadius != null
          ? radius(borderRadius)
          : BorderRadius.circular(8.0),
      borderSide: const BorderSide(color: Colors.red, width: 2),
    ),
    errorMaxLines: 2,
    errorStyle: primaryTextStyle(color: Colors.red, size: 12),
    focusedBorder: OutlineInputBorder(
      borderRadius: borderRadius != null
          ? radius(borderRadius)
          : BorderRadius.circular(8.0),
      borderSide: const BorderSide(color: Colors.grey, width: 2),
    ),
    filled: true,
    fillColor: Colors.white,
    hintStyle: const TextStyle(color: Colors.grey, fontSize: 16.0),
    border: OutlineInputBorder(
      borderRadius: BorderRadius.circular(8.0),
      borderSide: const BorderSide(width: 20),
    ),
  );
}

// String parseHtmlString(String? htmlString) {
//   return parse(parse(htmlString).body!.text).documentElement!.text;
// }

String formatDate(
  String? dateTime, {
  String format = "dd/MM/yyyy",
  bool isFromMicrosecondsSinceEpoch = false,
}) {
  if (isFromMicrosecondsSinceEpoch) {
    return DateFormat(format, "fr_FR").format(
      DateTime.fromMicrosecondsSinceEpoch(dateTime.validate().toInt() * 1000),
    );
  } else {
    return DateFormat(
      format,
      "fr_FR",
    ).format(DateTime.parse(dateTime.validate()));
  }
}

String formatPassDate(
  String? dateTime, {
  String format = "dd/MM/yyyy",
  bool isFromMicrosecondsSinceEpoch = false,
}) {
  // Il y a 5 minutes/sec/jours/heures/mois/ans
  if (isFromMicrosecondsSinceEpoch) {
    return DateFormat(format, "fr_FR").format(
      DateTime.fromMicrosecondsSinceEpoch(dateTime.validate().toInt() * 1000),
    );
  } else {
    DateTime tempDate = DateTime.parse(dateTime.validate());
    Duration diff = DateTime.now().difference(tempDate);

    if (diff.inSeconds < 60) {
      return 'Il y a ${diff.inSeconds} seconde${diff.inSeconds > 1 ? 's' : ''}';
    } else if (diff.inMinutes < 60) {
      return 'Il y a ${diff.inMinutes} minute${diff.inMinutes > 1 ? 's' : ''}';
    } else if (diff.inHours < 24) {
      return 'Il y a ${diff.inHours} heure${diff.inHours > 1 ? 's' : ''}';
    } else {
      return formatDate(dateTime, format: format);
    }
  }
}

int getAge(DateTime selecteddate) {
  return ((DateTime.now().difference(selecteddate).inDays) / 365.2425)
      .truncate();
}

String getEllipsisText(String text, {int maxLength = 15}) {
  if (text.length > maxLength) {
    return '${text.substring(0, maxLength)}...';
  } else {
    return text;
  }
}

final _random = Random();

Map<String, dynamic> parseJwt(String token) {
  final parts = token.split('.');
  if (parts.length != 3) {
    throw Exception('invalid token');
  }

  final payload = _decodeBase64(parts[1]);
  final payloadMap = json.decode(payload);
  if (payloadMap is! Map<String, dynamic>) {
    throw Exception('invalid payload');
  }

  return payloadMap;
}

String formatTimedecount(int seconds) {
  final minutes = (seconds ~/ 60).toString().padLeft(2, '0');
  final secs = (seconds % 60).toString().padLeft(2, '0');
  return '$minutes:$secs';
}

String _decodeBase64(String str) {
  String output = str.replaceAll('-', '+').replaceAll('_', '/');

  switch (output.length % 4) {
    case 0:
      break;
    case 2:
      output += '==';
      break;
    case 3:
      output += '=';
      break;
    default:
      throw Exception('Illegal base64url string!"');
  }

  return utf8.decode(base64Url.decode(output));
}

/// Generates a positive random integer uniformly distributed on the range
/// from [min], inclusive, to [max], exclusive.
int my_Random(int min, int max) => min + _random.nextInt(max - min);

// Random string generator
String getRandomString(int length) {
  const chars =
      'abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789';
  final rand = Random();
  return List.generate(
    length,
    (index) => chars[rand.nextInt(chars.length)],
  ).join();
}

// Random address example
String getRandomAddress() {
  if (kReleaseMode) return "";
  List<String> streets = ['Main St', 'Highway Rd', 'Palm Ave', 'Elm St'];
  int number = Random().nextInt(999) + 1;
  String street = streets[Random().nextInt(streets.length)];
  return '$number $street';
}

// Random date (e.g., between 2010 and 2025)
String? getRandomDate() {
  if (kReleaseMode) return null;

  final random = Random();
  int year = 2010 + random.nextInt(16); // 2010–2025
  int month = 1 + random.nextInt(12);
  int day = 1 + random.nextInt(28); // avoid invalid dates
  return DateFormat('dd/MM/yyyy').format(DateTime(year, month, day)).toString();
}

double my_DoubleRandom(int min, int max) => min + _random.nextDouble() * max;

//bb is the bounding box, (ix,iy) are its top-left coordinates,
//and (ax,ay) its bottom-right coordinates. p is the point and (x,y)
//its coordinates.
//bbox = min Longitude , min Latitude , max Longitude , max Latitude
//[1.86735, -1.93359, 3.43099, 9.257474]

double generateBorderRadius() => Random().nextDouble() * 64;
double generateMargin() => Random().nextDouble() * 64;
Color generateColor() => Color(0xFFFFFFFF & Random().nextInt(0xFFFFFFFF));

// Function to check if it's an image
bool isImage(String extension) {
  // You can expand this list as needed
  return ['.jpg', '.jpeg', '.png', '.gif', '.bmp', '.webp'].contains(extension);
}

// Function to check if it's a video
bool isVideo(String extension) {
  // You can expand this list as needed
  return ['.mp4', '.mov', '.avi', '.mkv', '.flv', '.webm'].contains(extension);
}

void simulateScreenTap() {
  try {
    GestureBinding.instance.handlePointerEvent(
      const PointerDownEvent(position: Offset(0, 0)),
    );
    GestureBinding.instance.handlePointerEvent(
      const PointerUpEvent(position: Offset(0, 0)),
    );
  } catch (e) {
    my_print_err("simulateRightCenterTap error: $e");
  }
}

void simulateScreenBottomRightTap(BuildContext context) {
  try {
    Size screenSize = MediaQuery.of(context).size;
    Offset bottomRight = Offset(screenSize.width - 1, screenSize.height - 1);
    GestureBinding.instance.handlePointerEvent(
      PointerDownEvent(position: bottomRight),
    );
    GestureBinding.instance.handlePointerEvent(
      PointerUpEvent(position: bottomRight),
    );
  } catch (e) {
    my_print_err("simulateRightCenterTap error: $e");
  }
}

void simulateRightCenterTap(BuildContext context) {
  try {
    // Get the screen size
    Size screenSize = MediaQuery.of(context).size;

    // Calculate the right center position
    Offset rightCenter = Offset(screenSize.width - 1, screenSize.height / 2);

    // Simulate the PointerDown event at the right center
    GestureBinding.instance.handlePointerEvent(
      PointerDownEvent(position: rightCenter),
    );

    // Simulate the PointerUp event at the right center
    GestureBinding.instance.handlePointerEvent(
      PointerUpEvent(position: rightCenter),
    );
  } catch (e) {
    my_print_err("simulateRightCenterTap error: $e");
  }
}

String getmesssageDate(String? date) {
  if (date == null || date.isEmpty) return "";

  DateTime messageDate = DateTime.parse(date);
  DateTime today = DateTime.now();

  if (messageDate.year == today.year &&
      messageDate.month == today.month &&
      messageDate.day == today.day) {
    // Retourner uniquement l'heure si c'est aujourd'hui
    return DateFormat.jm('en_US').format(messageDate);
  } else {
    // Retourner la date complète sinon
    return DateFormat.yMMMd('en_US').add_jm().format(messageDate);
  }
}

K? getRelativeKey<K, V>(Map<K, V> map, K key, int offset) {
  List<K> keys = map.keys.toList();
  int index = keys.indexOf(key);

  int targetIndex = index + offset;
  if (targetIndex >= 0 && targetIndex < keys.length) {
    return keys[targetIndex];
  }
  return null; // Return null if no valid key at the relative position
}

T? getNextElement<T>(List<T> list, int index) {
  return (index >= 0 && index < list.length - 1) ? list[index + 1] : null;
}

T? getPrevElement<T>(List<T> list, int index) {
  if ((index - 1) < 0) {
    return list[0];
  }
  return (index >= 0) ? list[index - 1] : null;
}

void my_print(var ______________________) {
  //print('\x1B[32m${StackTrace.current}\x1B[0m');
  print('\x1B[32m$______________________\x1B[0m');
}

void my_print_err(var text) {
  print('\x1B[33m$text\x1B[0m');
}

void my_inspect(var text) {
  // print('\x1B[32m${StackTrace.current}\x1B[0m');
  if (kIsWeb) {
    myprint3(text.toString());
    return;
  }
  try {
    if (isAndroid || isIOS) {
      writeToFile('inspect_log.txt', text.toString(), append: true);
      // alse the stack trace if exists
      writeToFile(
        'inspect_log.txt',
        text.stackTrace?.toString() ?? '',
        append: true,
      );
    }
  } catch (e) {
    e;
  }

  inspect(text);
}

void writeToFile(String fileName, String content, {bool append = false}) async {
  if (kIsWeb) {
    return;
  }
  final directory = await getExternalStorageDirectory();
  final filePath = p.join(directory!.path, fileName);
  final file = File(filePath);
  // Always end with a newline
  final data = '$content\n\n\n';

  if (append) {
    await file.writeAsString(data, mode: FileMode.append);
  } else {
    await file.writeAsString(data);
  }
}

//bb is the bounding box, (ix,iy) are its top-left coordinates,
//and (ax,ay) its bottom-right coordinates. p is the point and (x,y)
//its coordinates.
//bbox = min Longitude , min Latitude , max Longitude , max Latitude
//[1.86735, -1.93359, 3.43099, 9.257474]

String generateRandomStrings(int length) {
  const chars =
      'abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789';
  Random rnd = Random();

  return String.fromCharCodes(
    Iterable.generate(
      length,
      (_) => chars.codeUnitAt(rnd.nextInt(chars.length)),
    ),
  );
}

int countVideos(List<String> privates) {
  return privates.where((item) => item.startsWith("fed")).length;
}

String getPlatform() {
  if (isAndroid) {
    return "android";
  } else if (isIOS) {
    return "ios";
  } else {
    return "web";
  }
}

int countImages(List<String> privates) {
  return privates.where((item) => !item.startsWith("fed")).length;
}

void myprint(var text) {
  print('\x1B[33m---------------------------------------\x1B[0m');
  print('\x1B[33m$text\x1B[0m');
  print('\x1B[33m---------------------------------------\x1B[0m');
}

void myprint3(var text) {
  //en vert
  print('\x1B[32m---------------------------------------\x1B[0m');
  print('\x1B[32m$text\x1B[0m');
  print('\x1B[32m---------------------------------------\x1B[0m');
}

bool isVideofed(String text) {
  return text.contains("fed");
}

void myprintnet(var text) {
  print('\x1B[35m$text\x1B[0m');
}

void myprint2(var text) {
  print('\x1B[37m$text\x1B[0m');
}

class ReceivedNotification {
  ReceivedNotification({
    required this.id,
    required this.title,
    required this.body,
    required this.payload,
  });

  final int id;
  final String? title;
  final String? body;
  final String? payload;
}

String? requiredforminput(value, lang) {
  if (value == null || value.isEmpty) {
    return lang;
  }
  return null;
}

String? validateEmail(value, lang, lang2) {
  if (value == null || value.isEmpty) {
    return lang; // Message for empty email
  }
  if (!RegExp(r'^[^@]+@[^@]+\.[^@]+').hasMatch(value)) {
    return lang2; // Message for invalid email format
  }
  return null;
}

String? checkpassword(value, lang, lang2) {
  if (value == null || value.isEmpty) {
    // return 'Please enter your first name';
    return lang;
  }
  if (value.length < 6) return lang2;

  return null;
}

String getReviewExplicitName(String type, {bool reverse = false}) {
  if (reverse) {
    return type != "exit" ? "sortant" : "entran";
  }
  return type == "exit" ? "sortant" : "entran";
}

Future<bool> _ensureStoragePermission() async {
  if (Platform.isAndroid) {
    if (await Permission.manageExternalStorage.isGranted) {
      return true;
    }

    final status = await Permission.manageExternalStorage.request();
    if (status.isGranted) {
      return true;
    } else {
      // Redirige vers les paramètres si refus
      await openAppSettings();
      return false;
    }
  }
  return true;
}
