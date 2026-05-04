import 'package:flutter/material.dart';
import 'navigation_service.dart';
import 'trace_screen.dart';

class CsvTracesScreen extends StatefulWidget {
  final NavigationService navService;

  const CsvTracesScreen({
    super.key,
    required this.navService,
  });

  @override
  State<CsvTracesScreen> createState() => _CsvTracesScreenState();
}

class _CsvTracesScreenState extends State<CsvTracesScreen> {
  late Future<List<CsvTraceSession>> _futureSessions;

  @override
  void initState() {
    super.initState();
    _futureSessions = widget.navService.loadCsvTraceSessions();
  }

  Future<void> _refresh() async {
    setState(() {
      _futureSessions = widget.navService.loadCsvTraceSessions();
    });
    await _futureSessions;
  }

  String _fmtDate(DateTime d) {
    String two(int n) => n.toString().padLeft(2, '0');
    return '${d.year}-${two(d.month)}-${two(d.day)} ${two(d.hour)}:${two(d.minute)}:${two(d.second)}';
  }

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

