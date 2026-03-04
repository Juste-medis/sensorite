import 'dart:core';

class TimestampHelper {
  /// Timestamp actuel en millisecondes
  static int nowMillis() => DateTime.now().millisecondsSinceEpoch;

  /// Timestamp actuel en microsecondes (pour plus de précision)
  static int nowMicros() => DateTime.now().microsecondsSinceEpoch;

  /// DateTime actuel
  static DateTime now() => DateTime.now();

  /// Format pour nom de fichier
  static String formattedForFilename() {
    final now = DateTime.now();
    return '${now.year}${_twoDigits(now.month)}${_twoDigits(now.day)}_'
        '${_twoDigits(now.hour)}${_twoDigits(now.minute)}${_twoDigits(now.second)}';
  }

  /// Format lisible
  static String formattedReadable(DateTime dateTime) {
    return '${_twoDigits(dateTime.day)}/${_twoDigits(dateTime.month)}/${dateTime.year} '
        '${_twoDigits(dateTime.hour)}:${_twoDigits(dateTime.minute)}:${_twoDigits(dateTime.second)}';
  }

  static String _twoDigits(int n) => n.toString().padLeft(2, '0');
}
