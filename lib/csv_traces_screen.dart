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
class CsvTracesScreen extends StatefulWidget {
  /// Service de navigation injecte, utilise pour charger les sessions de
  /// traces CSV depuis le stockage de l'appareil.
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
  late Future<List<CsvTraceSession>> _futureSessions;

  /// Initialise l'etat du widget.
  ///
  /// Ne prend pas de parametre et ne renvoie rien. Appele une seule fois par
  /// le framework Flutter a la creation de l'etat : declenche le premier
  /// chargement des sessions CSV via [NavigationService.loadCsvTraceSessions].
  @override
  void initState() {
    super.initState();
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
  Future<void> _refresh() async {
    setState(() {
      _futureSessions = widget.navService.loadCsvTraceSessions();
    });
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
    String two(int n) => n.toString().padLeft(2, '0');
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
      body: FutureBuilder<List<CsvTraceSession>>(
        future: _futureSessions,
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(
              child: CircularProgressIndicator(color: Color(0xFF00E5FF)),
            );
          }

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
            child: ListView.separated(
              padding: const EdgeInsets.all(12),
              itemCount: sessions.length,
              separatorBuilder: (_, __) => const SizedBox(height: 8),
              itemBuilder: (context, i) {
                final s = sessions[i];
                return InkWell(
                  onTap: () {
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

