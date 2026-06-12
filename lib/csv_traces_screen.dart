import 'package:flutter/material.dart';
import 'navigation_service.dart';
import 'trace_screen.dart';

/// Ecran qui liste les sessions de traces GPS+IMU enregistrees sous forme de
/// fichiers CSV.
///
/// Chaque session detectee est affichee sous forme de carte cliquable
/// permettant d'ouvrir l'ecran de visualisation [TraceScreen] correspondant.
/// Widget de type [StatefulWidget] dont l'etat est gere par
/// [_CsvTracesScreenState].
// StatefulWidget : widget dont l'apparence peut changer au cours du temps.
// Il est immuable lui-meme (ses champs sont 'final'), mais il delegue son etat
// modifiable a une classe State separee (ici _CsvTracesScreenState).
class CsvTracesScreen extends StatefulWidget {
  /// Service de navigation injecte, utilise pour charger les sessions de
  /// traces CSV depuis le stockage de l'appareil.
  // 'final' : champ defini une seule fois, a la construction du widget.
  final NavigationService navService;

  /// Construit l'ecran.
  ///
  /// Prend en parametre le [navService] (obligatoire) servant a charger les
  /// sessions CSV, ainsi qu'une [key] optionnelle.
  const CsvTracesScreen({
    super.key,
    required this.navService,
  });

  /// Cree l'objet d'etat [_CsvTracesScreenState] associe a ce widget.
  ///
  /// Appele automatiquement par le framework Flutter lors de l'insertion du
  /// widget dans l'arbre.
  @override
  // createState() : appele par Flutter pour creer l'objet State qui contiendra
  // les donnees mutables et la methode build() de ce widget.
  State<CsvTracesScreen> createState() => _CsvTracesScreenState();
}

/// Etat associe a [CsvTracesScreen].
///
/// Gere le chargement asynchrone des sessions CSV, leur rafraichissement et la
/// construction de l'interface (liste des cartes de sessions).
class _CsvTracesScreenState extends State<CsvTracesScreen> {
  /// Future contenant la liste des sessions de traces CSV chargees.
  ///
  /// Reaffecte a chaque rafraichissement et consomme par le [FutureBuilder]
  /// dans [build] pour afficher l'etat de chargement, l'erreur ou la liste.
  // Future<T> : valeur disponible plus tard (resultat d'une operation async),
  // ici la liste des sessions chargee depuis le disque.
  // 'late' : la variable sera initialisee avant son premier usage (dans
  // initState), ce qui evite de la marquer comme nullable.
  late Future<List<CsvTraceSession>> _futureSessions;

  /// Initialise l'etat du widget.
  ///
  /// Ne prend pas de parametre et ne renvoie rien. Appele une seule fois par
  /// le framework Flutter a la creation de l'etat : declenche le premier
  /// chargement des sessions CSV via [NavigationService.loadCsvTraceSessions].
  @override
  // initState() : appele une seule fois a la creation de l'etat. Endroit idiomatique
  // pour lancer un chargement initial. Pas de async ici : on stocke le Future
  // sans l'attendre, c'est le FutureBuilder qui reagira a sa completion.
  void initState() {
    super.initState();
    // 'widget' donne acces a l'instance du StatefulWidget (et donc a navService).
    _futureSessions = widget.navService.loadCsvTraceSessions();
  }

  /// Recharge la liste des sessions de traces CSV.
  ///
  /// Ne prend pas de parametre. Relance le chargement via
  /// [NavigationService.loadCsvTraceSessions], met a jour l'interface via
  /// [setState], puis attend la fin du chargement. Renvoie un [Future] qui se
  /// resout une fois les donnees disponibles. Appele lors d'un appui sur le
  /// bouton de rafraichissement de l'[AppBar] et lors du geste de tir-pour-
  /// rafraichir du [RefreshIndicator].
  // 'async' marque une fonction asynchrone ; elle renvoie un Future.
  Future<void> _refresh() async {
    // setState() previent Flutter qu'un etat a change : il reconstruit (rappelle
    // build) le widget. Ici on remplace le Future, ce qui relance le FutureBuilder.
    setState(() {
      _futureSessions = widget.navService.loadCsvTraceSessions();
    });
    // 'await' met en pause la fonction jusqu'a la fin du Future (sans bloquer l'UI).
    await _futureSessions;
  }

  /// Formate une date/heure en chaine lisible.
  ///
  /// Prend en parametre la date [d] a formater. Renvoie une [String] au format
  /// `AAAA-MM-JJ HH:MM:SS`. Appele depuis [build] pour afficher la date de
  /// derniere modification de chaque session.
  String _fmtDate(DateTime d) {
    /// Convertit un entier [n] en chaine de deux caracteres, en ajoutant un
    /// zero a gauche si necessaire (ex. 5 -> "05").
    // Fonction locale (definie dans une autre fonction) ; '=>' est une syntaxe
    // courte pour une fonction qui ne fait que renvoyer une expression.
    String two(int n) => n.toString().padLeft(2, '0');
    // '${...}' : interpolation, insere la valeur d'une expression dans la chaine.
    return '${d.year}-${two(d.month)}-${two(d.day)} ${two(d.hour)}:${two(d.minute)}:${two(d.second)}';
  }

  /// Construit l'interface de l'ecran.
  ///
  /// Prend en parametre le [context] de construction. Renvoie un [Scaffold] au
  /// fond sombre comportant une [AppBar] titree « TRACES DEPUIS CSV » avec un
  /// bouton de rafraichissement, et un corps base sur un [FutureBuilder] qui,
  /// selon l'etat de [_futureSessions], affiche : un indicateur de chargement,
  /// un message d'erreur, un message « Aucun CSV de trace detecte. », ou la
  /// liste defilante des sessions sous forme de cartes cliquables. Chaque carte
  /// ouvre [TraceScreen] avec la trace IMU et GPS de la session correspondante.
  /// Appele par le framework Flutter a chaque (re)construction de l'ecran.
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0A0E1A),
      appBar: AppBar(
        backgroundColor: const Color(0xFF0D1220),
        foregroundColor: Colors.white,
        title: const Text(
          'TRACES DEPUIS CSV',
          style: TextStyle(
            fontSize: 14,
            letterSpacing: 2,
            fontWeight: FontWeight.w600,
          ),
        ),
        actions: [
          IconButton(
            onPressed: _refresh,
            icon: const Icon(Icons.refresh),
            tooltip: 'Rafraichir',
          ),
        ],
      ),
      // FutureBuilder : widget qui se reconstruit automatiquement selon l'etat
      // du Future fourni. Son 'builder' est rappele a chaque changement d'etat
      // (en attente -> termine), evitant de gerer le chargement manuellement.
      body: FutureBuilder<List<CsvTraceSession>>(
        future: _futureSessions,
        // 'snapshot' = instantane de l'etat actuel du Future (etat, donnees, erreur).
        builder: (context, snapshot) {
          // connectionState == waiting : le Future n'est pas encore termine.
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(
              child: CircularProgressIndicator(color: Color(0xFF00E5FF)),
            );
          }

          // hasError : le Future s'est termine par une exception.
          if (snapshot.hasError) {
            return Center(
              child: Padding(
                padding: const EdgeInsets.all(18),
                child: Text(
                  'Erreur de lecture CSV:\n${snapshot.error}',
                  textAlign: TextAlign.center,
                  style: const TextStyle(color: Colors.white70, fontSize: 13),
                ),
              ),
            );
          }

          // snapshot.data : valeur produite par le Future (peut etre null si pas
          // encore disponible). L'operateur '??' fournit une valeur de repli (ici
          // une liste vide) quand la partie de gauche est null.
          final sessions = snapshot.data ?? const <CsvTraceSession>[];
          if (sessions.isEmpty) {
            return const Center(
              child: Text(
                'Aucun CSV de trace detecte.',
                style: TextStyle(color: Colors.white54, fontSize: 14),
              ),
            );
          }

          return RefreshIndicator(
            onRefresh: _refresh,
            color: const Color(0xFF00E5FF),
            // ListView.separated : liste defilante performante qui ne construit
            // que les elements visibles a l'ecran (a la demande, via itemBuilder),
            // avec un separateur insere entre chaque element.
            child: ListView.separated(
              padding: const EdgeInsets.all(12),
              // itemCount : nombre total d'elements de la liste.
              itemCount: sessions.length,
              // '_' et '__' : parametres ignores (la signature les exige mais on
              // ne s'en sert pas). Ici un simple espace de 8px entre les cartes.
              separatorBuilder: (_, __) => const SizedBox(height: 8),
              // itemBuilder : appele pour construire chaque element a l'index 'i'.
              itemBuilder: (context, i) {
                final s = sessions[i];
                // InkWell : zone cliquable avec effet visuel d'ondulation au tap.
                return InkWell(
                  onTap: () {
                    // Navigator.push : empile un nouvel ecran par-dessus l'actuel
                    // (l'utilisateur pourra revenir en arriere). MaterialPageRoute
                    // construit cet ecran (TraceScreen) avec une transition standard.
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => TraceScreen(
                          trail: s.trail,
                          gpsTrail: s.gpsTrail,
                        ),
                      ),
                    );
                  },
                  borderRadius: BorderRadius.circular(12),
                  child: Ink(
                    decoration: BoxDecoration(
                      color: const Color(0xFF141B2D),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: const Color(0xFF1E293B)),
                    ),
                    child: Padding(
                      padding: const EdgeInsets.all(12),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              const Icon(
                                Icons.description_outlined,
                                color: Color(0xFF00E5FF),
                                size: 18,
                              ),
                              const SizedBox(width: 8),
                              Expanded(
                                child: Text(
                                  s.fileName,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(
                                    color: Colors.white,
                                    fontSize: 13,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 8),
                          Text(
                            _fmtDate(s.modifiedAt),
                            style: const TextStyle(
                              color: Colors.white54,
                              fontSize: 11,
                            ),
                          ),
                          const SizedBox(height: 8),
                          Wrap(
                            spacing: 8,
                            runSpacing: 6,
                            // _chip(...) : on appelle une methode qui renvoie un
                            // widget pour factoriser la construction des etiquettes.
                            children: [
                              _chip('Lignes: ${s.rowCount}'),
                              _chip('GPS: ${s.gpsTrail.length} pts'),
                              _chip('IMU: ${s.trail.length} pts'),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ),
                );
              },
            ),
          );
        },
      ),
    );
  }

  /// Construit une petite etiquette (« chip ») d'information.
  ///
  /// Prend en parametre le [text] a afficher. Renvoie un [Container] stylise
  /// (fond sombre, bords arrondis et bordure) contenant ce texte. Appele depuis
  /// [build] pour afficher les statistiques de chaque session : nombre de
  /// lignes du CSV, nombre de points GPS et nombre de points IMU.
  Widget _chip(String text) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: const Color(0xFF0D1220),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: const Color(0xFF1E293B)),
      ),
      child: Text(
        text,
        style: const TextStyle(
          color: Colors.white70,
          fontSize: 11,
        ),
      ),
    );
  }
}

