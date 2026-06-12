// 'dart:io' donne accès au système de fichiers (File, Directory) et à la plateforme (Platform).
import 'dart:io';
// path_provider fournit les chemins des dossiers de l'app selon le téléphone (Android/iOS).
import 'package:path_provider/path_provider.dart';

/// Enregistrement d'un échantillon de données brutes à un instant donné.
///
/// Chaque instance capture, pour un même horodatage, les mesures brutes de la
/// centrale inertielle (accéléromètre [axRaw], [ayRaw], [azRaw] et gyroscope
/// [gxRaw], [gyRaw], [gzRaw]), l'état estimé par le filtre de Kalman (position
/// [estLat]/[estLon], vitesses [estVx]/[estVy], [speed], [heading],
/// [confidence], [uncertainty]) ainsi que la mesure GPS de référence
/// (« vérité-terrain ») lorsqu'elle est disponible ([gpsLat], [gpsLon],
/// [gpsSpeed], [gpsAccuracy]).
///
/// Ces enregistrements sont accumulés par [DataRecorder] puis exportés en CSV
/// afin de comparer après-coup la trajectoire estimée à la trajectoire GPS.
class RawDataRecord {
  /// Horodatage de l'échantillon, en millisecondes.
  final int timestampMs;
  /// Accélérations brutes mesurées par l'accéléromètre sur les axes X, Y et Z.
  final double axRaw, ayRaw, azRaw;

  /// Vitesses angulaires brutes mesurées par le gyroscope sur les axes X, Y et Z.
  final double gxRaw, gyRaw, gzRaw;

  /// Latitude et longitude estimées par le filtre de Kalman.
  final double estLat, estLon;

  /// Composantes Est/Nord de la vitesse estimée par le filtre de Kalman.
  final double estVx, estVy;

  /// Vitesse et cap (en degrés) estimés par le filtre de Kalman.
  final double speed, heading;

  /// Indice de confiance et incertitude associés à l'estimation du filtre.
  final double confidence, uncertainty;

  /// Mesures GPS de référence (vérité-terrain), nulles si aucune mesure GPS
  /// n'était disponible pour cet échantillon.
  // 'double?' (avec le '?') = type nullable : la valeur peut être un nombre OU null.
  final double? gpsLat, gpsLon, gpsSpeed, gpsAccuracy;

  /// Mode de fonctionnement courant de l'estimation (ex. GPS, inertiel).
  final String mode;

  /// Vrai si le système est considéré comme immobile à cet instant.
  final bool isStationary;

  /// Construit un enregistrement immuable à partir de toutes les mesures d'un
  /// même instant.
  ///
  /// Tous les champs sont requis sauf les mesures GPS ([gpsLat], [gpsLon],
  /// [gpsSpeed], [gpsAccuracy]) qui restent nulles lorsqu'aucune position GPS
  /// n'est disponible. Appelé par le code de capture des capteurs avant d'être
  /// transmis à [DataRecorder.addRecord].
  RawDataRecord({
    required this.timestampMs,
    required this.axRaw,
    required this.ayRaw,
    required this.azRaw,
    required this.gxRaw,
    required this.gyRaw,
    required this.gzRaw,
    required this.estLat,
    required this.estLon,
    required this.estVx,
    required this.estVy,
    required this.speed,
    required this.heading,
    required this.confidence,
    required this.uncertainty,
    this.gpsLat,
    this.gpsLon,
    this.gpsSpeed,
    this.gpsAccuracy,
    required this.mode,
    required this.isStationary,
  });

  /// Sérialise cet enregistrement en une ligne CSV.
  ///
  /// Ne prend aucun paramètre. Renvoie une [String] dont les valeurs sont
  /// séparées par des virgules, dans le même ordre que l'en-tête défini par
  /// [DataRecorder._csvHeader] ; les champs numériques sont formatés avec un
  /// nombre fixe de décimales et les mesures GPS absentes deviennent des
  /// champs vides. Appelé par [DataRecorder.exportCSV] pour chaque
  /// enregistrement.
  String toCsvRow() {
    // On crée une liste de valeurs, puis '.join(',')' (en bas) les colle en une seule
    // chaîne séparée par des virgules. 'toStringAsFixed(n)' formate un double avec n décimales.
    return [
      timestampMs,
      axRaw.toStringAsFixed(6),
      ayRaw.toStringAsFixed(6),
      azRaw.toStringAsFixed(6),
      gxRaw.toStringAsFixed(6),
      gyRaw.toStringAsFixed(6),
      gzRaw.toStringAsFixed(6),
      estLat.toStringAsFixed(8),
      estLon.toStringAsFixed(8),
      estVx.toStringAsFixed(5),
      estVy.toStringAsFixed(5),
      speed.toStringAsFixed(4),
      heading.toStringAsFixed(2),
      confidence.toStringAsFixed(4),
      uncertainty.toStringAsFixed(4),
      // '?.' = appel conditionnel : si gpsLat est null, on n'appelle pas la méthode et le résultat est null.
      // '?? ' = valeur par défaut : si la gauche est null, on prend la droite (ici une chaîne vide).
      gpsLat?.toStringAsFixed(8) ?? '',
      gpsLon?.toStringAsFixed(8) ?? '',
      gpsSpeed?.toStringAsFixed(4) ?? '',
      gpsAccuracy?.toStringAsFixed(2) ?? '',
      mode,
      isStationary ? '1' : '0',
    ].join(','); // colle tous les éléments de la liste en une seule ligne CSV.
  }
}

/// Outil d'enregistrement et d'export des données de capteurs.
///
/// Accumule en mémoire une session d'enregistrements [RawDataRecord]
/// (mesures IMU brutes, sorties du filtre de Kalman et mesures GPS de
/// référence), puis les exporte dans un fichier CSV. Sert d'outil de
/// validation : le CSV produit permet de comparer après-coup la trajectoire
/// estimée à la vérité-terrain fournie par le GPS.
class DataRecorder {
  /// Ligne d'en-tête du fichier CSV, décrivant l'ordre et le nom des colonnes
  /// produites par [RawDataRecord.toCsvRow].
  static const String _csvHeader =
      'timestamp_ms,'
      'ax_raw,ay_raw,az_raw,'
      'gx_raw,gy_raw,gz_raw,'
      'est_lat,est_lon,'
      'est_vx,est_vy,'
      'est_speed,est_heading,'
      'confidence,uncertainty,'
      'gps_lat,gps_lon,gps_speed,gps_accuracy,'
      'mode,is_stationary';

  /// Liste interne des enregistrements accumulés pendant la session courante.
  final List<RawDataRecord> _records = [];

  /// Indique si une session d'enregistrement est actuellement active.
  bool _isRecording = false;

  /// Instant de démarrage de la session courante, ou null si aucune session
  /// n'a été démarrée.
  // 'DateTime?' : objet date/heure pouvant être null tant qu'aucune session n'a démarré.
  DateTime? _sessionStart;

  /// Démarre une nouvelle session d'enregistrement.
  ///
  /// Ne prend aucun paramètre et ne renvoie rien. Vide les enregistrements
  /// précédents, active l'enregistrement et mémorise l'instant de départ.
  /// Appelé par l'interface lorsque l'utilisateur lance une capture.
  void startRecording() {
    _records.clear();
    _isRecording = true;
    _sessionStart = DateTime.now(); // DateTime.now() capture l'instant présent du téléphone.
  }

  /// Arrête la session d'enregistrement en cours.
  ///
  /// Ne prend aucun paramètre et ne renvoie rien. Désactive l'enregistrement
  /// sans effacer les données déjà collectées, qui restent disponibles pour
  /// l'export. Appelé par l'interface lorsque l'utilisateur arrête la capture.
  void stopRecording() {
    _isRecording = false;
  }

  /// Ajoute l'enregistrement [record] à la session courante.
  ///
  /// Prend en paramètre le [RawDataRecord] à mémoriser. Ne renvoie rien.
  /// L'ajout est ignoré si aucune session n'est active. Appelé à chaque
  /// nouvel échantillon de capteurs tant que l'enregistrement est en cours.
  void addRecord(RawDataRecord record) {
    if (!_isRecording) return;
    _records.add(record);
  }

  /// Renvoie le nombre d'enregistrements actuellement accumulés.
  ///
  /// Getter sans paramètre. Utilisé par l'interface pour afficher la
  /// progression de la capture.
  int get recordCount => _records.length;

  /// Indique si une session d'enregistrement est en cours.
  ///
  /// Getter sans paramètre renvoyant un booléen. Utilisé par l'interface pour
  /// connaître l'état de la capture.
  bool get isRecording => _isRecording;

  /// Renvoie la durée écoulée depuis le début de la session courante.
  ///
  /// Getter sans paramètre. Renvoie [Duration.zero] si aucune session n'a été
  /// démarrée. Utilisé par l'interface pour afficher le temps d'enregistrement.
  // '_sessionStart!' : le '!' affirme à Dart que la valeur n'est PAS null ici
  // (on l'a vérifié juste avant). 'difference' donne le temps écoulé entre deux dates.
  Duration get sessionDuration =>
      _sessionStart != null ? DateTime.now().difference(_sessionStart!) : Duration.zero;

  /// Détermine le répertoire dans lequel exporter le fichier CSV.
  ///
  /// Ne prend aucun paramètre. Renvoie un [Future] sur le [Directory] cible :
  /// le stockage externe sur Android lorsqu'il est disponible, sinon le
  /// répertoire des documents de l'application. Appelé par [exportCSV].
  // 'async' marque une fonction asynchrone : elle renvoie un 'Future' (une valeur
  // qui arrivera plus tard) et peut utiliser 'await' pour attendre une opération longue.
  Future<Directory> getExportDirectory() async {
    Directory? dir;
    // Platform.isAndroid : vrai si l'app tourne sur Android.
    if (Platform.isAndroid) {
      // 'await' met en pause jusqu'à obtenir le dossier de stockage externe (visible dans le gestionnaire de fichiers).
      dir = await getExternalStorageDirectory();
    }
    // '??=' : assigne seulement si 'dir' est null. getApplicationDocumentsDirectory()
    // renvoie un dossier privé à l'app (invisible pour l'utilisateur sans explorateur).
    dir ??= await getApplicationDocumentsDirectory();
    return dir;
  }

  /// Exporte tous les enregistrements de la session dans un fichier CSV.
  ///
  /// Prend en paramètre optionnel [sessionTag], un suffixe ajouté au nom du
  /// fichier pour identifier la session. Écrit l'en-tête [_csvHeader] puis une
  /// ligne par enregistrement (via [RawDataRecord.toCsvRow]) dans un fichier
  /// horodaté placé dans le répertoire renvoyé par [getExportDirectory].
  /// Renvoie un [Future] sur le chemin du fichier créé, ou null si aucun
  /// enregistrement n'est présent ou en cas d'erreur d'écriture. Appelé par
  /// l'interface lorsque l'utilisateur demande l'export des données.
  Future<String?> exportCSV({String sessionTag = ''}) async {
    if (_records.isEmpty) return null;

    try {
      // 'await' attend que le dossier cible soit déterminé avant de continuer.
      final dir = await getExportDirectory();

      final now = DateTime.now();
      final tag = sessionTag.isNotEmpty ? '_$sessionTag' : '';
      // '$now.year' insère une valeur dans la chaîne (interpolation). 'padLeft(2, '0')'
      // complète à gauche avec des zéros (ex. 9 -> "09") pour un nom de fichier propre.
      final filename =
          'imu_${now.year}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}'
          '_${now.hour.toString().padLeft(2, '0')}-${now.minute.toString().padLeft(2, '0')}-${now.second.toString().padLeft(2, '0')}$tag.csv';
      // 'File(...)' désigne un fichier à partir de son chemin (dossier + nom). Il n'est pas encore écrit.
      final file = File('${dir.path}/$filename');

      // StringBuffer : accumule du texte efficacement (plus rapide que concaténer des String).
      final buffer = StringBuffer();
      buffer.writeln(_csvHeader); // 'writeln' écrit la ligne puis un retour à la ligne.
      // Parcourt chaque enregistrement et ajoute sa ligne CSV au buffer.
      for (final record in _records) {
        buffer.writeln(record.toCsvRow());
      }

      // 'writeAsString' écrit réellement le contenu sur le disque du téléphone (opération asynchrone, d'où 'await').
      await file.writeAsString(buffer.toString());
      return file.path;
    } catch (e) {
      // En cas d'erreur (ex. permission refusée), on renvoie null plutôt que de planter.
      return null;
    }
  }

  /// Réinitialise le recorder.
  ///
  /// Ne prend aucun paramètre et ne renvoie rien. Vide tous les enregistrements
  /// accumulés et oublie l'instant de départ de session. Appelé par l'interface
  /// pour effacer les données, typiquement après un export ou avant une
  /// nouvelle capture.
  void clear() {
    _records.clear();
    _sessionStart = null;
  }
}
