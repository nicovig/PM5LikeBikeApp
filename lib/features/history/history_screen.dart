import 'dart:math' as math;

import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:pm5_bike/core/metric_format.dart';
import 'package:pm5_bike/data/workout_session.dart';
import 'package:pm5_bike/features/app_providers.dart';
import 'package:pm5_bike/features/shared/pm5_colors.dart';

class HistoryScreen extends ConsumerWidget {
  const HistoryScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final history = ref.watch(historyProvider);
    return SafeArea(
      child: history.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (error, stackTrace) =>
            const Center(child: Text('Impossible de lire l’historique.')),
        data: (sessions) => RefreshIndicator(
          onRefresh: () async {
            ref.invalidate(historyProvider);
            await ref.read(historyProvider.future);
          },
          child: sessions.isEmpty
              ? ListView(
                  physics: const AlwaysScrollableScrollPhysics(),
                  children: const [
                    SizedBox(height: 120),
                    Center(child: Text('Aucune séance enregistrée.')),
                  ],
                )
              : ListView.separated(
                  physics: const AlwaysScrollableScrollPhysics(),
                  padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
                  itemCount: sessions.length + 1,
                  separatorBuilder: (context, index) =>
                      const SizedBox(height: 8),
                  itemBuilder: (context, index) {
                    if (index == 0) {
                      return const Padding(
                        padding: EdgeInsets.only(bottom: 8),
                        child: Text(
                          'Historique',
                          style: TextStyle(
                            fontSize: 28,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      );
                    }
                    final session = sessions[index - 1];
                    return _SessionTile(session: session);
                  },
                ),
        ),
      ),
    );
  }
}

class _SessionTile extends StatelessWidget {
  const _SessionTile({required this.session});

  final WorkoutSession session;

  @override
  Widget build(BuildContext context) {
    final date = DateFormat(
      'EEE d MMM yyyy · HH:mm',
      'fr_FR',
    ).format(session.startedAt);
    final summary = [
      formatDuration(session.elapsedSeconds),
      formatDistance(session.distanceMeters),
      '${formatWatts(session.averageWatts)} W',
      '${formatKcal(session.calories)} kcal',
    ].join(' · ');
    return Material(
      color: Pm5Colors.panel,
      borderRadius: BorderRadius.circular(14),
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: () {
          Navigator.of(context).push(
            MaterialPageRoute<void>(
              builder: (context) => SessionDetailScreen(session: session),
            ),
          );
        },
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(date, style: const TextStyle(color: Pm5Colors.muted)),
              const SizedBox(height: 6),
              Text(summary, style: const TextStyle(fontSize: 16)),
              const SizedBox(height: 4),
              Text(
                'Niveau ${session.level}',
                style: const TextStyle(color: Pm5Colors.muted, fontSize: 13),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class SessionDetailScreen extends ConsumerWidget {
  const SessionDetailScreen({super.key, required this.session});

  final WorkoutSession session;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Séance'),
        backgroundColor: Pm5Colors.background,
        actions: [
          IconButton(
            tooltip: 'Supprimer',
            onPressed: () => _delete(context, ref),
            icon: const Icon(Icons.delete_outline),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
        children: [
          Text(
            DateFormat(
              'EEEE d MMMM yyyy · HH:mm',
              'fr_FR',
            ).format(session.startedAt),
            style: const TextStyle(color: Pm5Colors.muted),
          ),
          const SizedBox(height: 16),
          _DetailLine('Durée', formatDuration(session.elapsedSeconds)),
          _DetailLine('Distance', formatDistance(session.distanceMeters)),
          _DetailLine(
            'Moyenne réelle',
            '${formatWatts(session.averageWatts)} W',
          ),
          _DetailLine(
            'Moyenne PM5',
            session.pm5AverageWatts == null
                ? '—'
                : '${formatWatts(session.pm5AverageWatts!)} W',
          ),
          _DetailLine('Calories', '${formatKcal(session.calories)} kcal'),
          _DetailLine(
            'Cadence moyenne',
            '${formatRpm(session.averageRpm)} rpm',
          ),
          _DetailLine('Niveau', '${session.level}'),
          if (session.hadOutOfRange)
            Padding(
              padding: const EdgeInsets.only(top: 12),
              child: Text(
                'Hors plage calibrée pendant ${session.outOfRangeSeconds.round()} s. Ces instants restent inclus dans les moyennes.',
                style: const TextStyle(color: Pm5Colors.warning),
              ),
            ),
          const SizedBox(height: 24),
          const Text(
            'Watts',
            style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 12),
          SizedBox(height: 240, child: _WattsChart(session: session)),
        ],
      ),
    );
  }

  Future<void> _delete(BuildContext context, WidgetRef ref) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Supprimer la séance'),
        content: const Text('Cette séance sera retirée de l’historique.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Annuler'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Supprimer'),
          ),
        ],
      ),
    );
    if (confirmed != true) {
      return;
    }
    await ref.read(historyProvider.notifier).delete(session.id);
    if (context.mounted) {
      Navigator.of(context).pop();
    }
  }
}

class _DetailLine extends StatelessWidget {
  const _DetailLine(this.label, this.value);

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        children: [
          Expanded(
            child: Text(label, style: const TextStyle(color: Pm5Colors.muted)),
          ),
          Text(value, style: const TextStyle(fontSize: 18)),
        ],
      ),
    );
  }
}

class _WattsChart extends StatelessWidget {
  const _WattsChart({required this.session});

  final WorkoutSession session;

  @override
  Widget build(BuildContext context) {
    if (session.samples.length < 2) {
      return const Center(child: Text('Pas assez de points pour une courbe.'));
    }
    var peak = 0.0;
    for (final sample in session.samples) {
      peak = math.max(peak, sample.watts);
    }
    final interval = math.max(1, session.elapsedSeconds / 4).toDouble();
    return LineChart(
      LineChartData(
        minY: 0,
        maxY: math.max(50, peak * 1.15).toDouble(),
        gridData: FlGridData(
          show: true,
          drawVerticalLine: false,
          getDrawingHorizontalLine: (value) =>
              const FlLine(color: Pm5Colors.line, strokeWidth: 1),
        ),
        borderData: FlBorderData(show: false),
        titlesData: FlTitlesData(
          topTitles: const AxisTitles(
            sideTitles: SideTitles(showTitles: false),
          ),
          rightTitles: const AxisTitles(
            sideTitles: SideTitles(showTitles: false),
          ),
          leftTitles: AxisTitles(
            sideTitles: SideTitles(
              showTitles: true,
              reservedSize: 36,
              getTitlesWidget: (value, meta) => Text(
                value.round().toString(),
                style: const TextStyle(color: Pm5Colors.muted, fontSize: 11),
              ),
            ),
          ),
          bottomTitles: AxisTitles(
            sideTitles: SideTitles(
              showTitles: true,
              reservedSize: 28,
              interval: interval,
              getTitlesWidget: (value, meta) => Text(
                _axisTime(value),
                style: const TextStyle(color: Pm5Colors.muted, fontSize: 11),
              ),
            ),
          ),
        ),
        lineBarsData: [
          LineChartBarData(
            spots: [
              for (final sample in session.samples)
                FlSpot(sample.elapsedSeconds, sample.watts),
            ],
            isCurved: false,
            color: Pm5Colors.text,
            barWidth: 2,
            dotData: const FlDotData(show: false),
          ),
        ],
      ),
    );
  }

  String _axisTime(double seconds) {
    final total = seconds.round();
    final minutes = total ~/ 60;
    final remain = total % 60;
    return '$minutes:${remain.toString().padLeft(2, '0')}';
  }
}
