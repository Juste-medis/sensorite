import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'navigation_screen.dart';

/// Point d'entrée de l'application Flutter de navigation GPS + IMU avec filtre de Kalman.
///
/// Ne prend aucun paramètre et ne renvoie rien.
/// Cette fonction :
/// - initialise la liaison entre Flutter et le moteur natif via [WidgetsFlutterBinding.ensureInitialized] ;
/// - verrouille l'orientation de l'écran en mode portrait ;
/// - configure le style de la barre système (transparente, icônes claires) ;
/// - lance l'application en montant le widget racine [IMUNavigatorApp].
///
/// Elle est appelée automatiquement par le moteur Dart/Flutter au démarrage de l'application.
void main() {
  // Initialise le pont entre Flutter et le code natif (iOS/Android).
  // Obligatoire avant tout appel à un plugin/API native dans main(), comme SystemChrome ci-dessous.
  WidgetsFlutterBinding.ensureInitialized();
  SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp]);
  SystemChrome.setSystemUIOverlayStyle(const SystemUiOverlayStyle(
    statusBarColor: Colors.transparent,
    statusBarIconBrightness: Brightness.light,
  ));
  // runApp démarre l'application Flutter et monte le widget passé en argument comme racine de l'arbre.
  // `const` : le widget est immuable, Flutter peut le réutiliser sans le reconstruire (optimisation).
  runApp(const IMUNavigatorApp());
}

/// Widget racine de l'application « IMU Navigator ».
///
/// Il s'agit d'un [StatelessWidget] : son contenu ne change pas au cours du temps.
/// Il configure le [MaterialApp] (titre, thème sombre, couleurs, police) et
/// définit l'écran d'accueil de l'application sur [NavigationScreen].
/// Il est instancié une seule fois par [main] lors du lancement de l'application.
// StatelessWidget : widget sans état interne, son apparence ne dépend que de sa configuration
// (contrairement à StatefulWidget qui, lui, peut se redessiner suite à un changement d'état interne).
class IMUNavigatorApp extends StatelessWidget {
  /// Construit le widget racine [IMUNavigatorApp].
  ///
  /// Le paramètre [key] est transmis au constructeur parent pour identifier
  /// le widget dans l'arbre de widgets. Ne renvoie pas de valeur (constructeur).
  // super.key : transmet la Key au widget parent. La Key sert à identifier ce widget
  // de façon unique dans l'arbre (utile à Flutter pour reconnaître les widgets entre deux reconstructions).
  const IMUNavigatorApp({super.key});

  /// Construit l'interface racine de l'application.
  ///
  /// Prend en paramètre le [context] fourni par le framework Flutter.
  /// Renvoie un [MaterialApp] configuré avec :
  /// - le titre « IMU Navigator » et la bannière de debug masquée ;
  /// - un thème sombre personnalisé (fond bleu nuit, couleurs primaire/secondaire,
  ///   police monospace, Material 3) ;
  /// - l'écran d'accueil [NavigationScreen].
  ///
  /// Cette méthode est appelée automatiquement par Flutter à chaque fois que
  /// le widget doit être (re)dessiné.
  // build() est appelée par Flutter pour construire l'UI ; elle est ré-exécutée à chaque redessin.
  // BuildContext = position de ce widget dans l'arbre des widgets (sert à accéder au thème, à la navigation, etc.).
  @override
  Widget build(BuildContext context) {
    // MaterialApp : widget racine qui apporte le design Material, la navigation et le thème global.
    return MaterialApp(
      title: 'IMU Navigator',
      debugShowCheckedModeBanner: false,
      // theme / ThemeData : définit l'apparence globale (couleurs, police...) héritée par tous les widgets enfants.
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
      // home : écran affiché au démarrage (la route par défaut '/').
      // (À noter : on pourrait aussi déclarer `routes:` pour mapper des noms de routes vers des écrans.)
      home: const NavigationScreen(),
    );
  }
}
