import 'package:flutter/material.dart';

import '../dev/perf_log.dart';

/// Dev-only: average time per frame for every model setup that has run (Bill, Learn, Lab).
class LogsView extends StatelessWidget {
  const LogsView({super.key});

  @override
  Widget build(BuildContext context) {
    final log = PerfLog.instance;
    // Rebuilds whenever a new frame is recorded.
    return ListenableBuilder(
      listenable: log,
      builder: (context, _) {
        if (log.stats.isEmpty) {
          return const Center(child: Text('Run a model on Bill, Learn or the Lab; its timings show up here.'));
        }
        return ListView(
          padding: const EdgeInsets.all(12),
          children: [
            Align(
              alignment: Alignment.centerRight,
              child: TextButton.icon(
                onPressed: log.clear,
                icon: const Icon(Icons.delete_outline),
                label: const Text('Clear'),
              ),
            ),
            for (final e in log.stats.entries) _ModelCard(e.key, e.value),
          ],
        );
      },
    );
  }
}

class _ModelCard extends StatelessWidget {
  const _ModelCard(this.model, this.s);
  final String model;
  final ModelStats s;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    String ms(double v) => '${v.toStringAsFixed(0)} ms';
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(model, style: t.titleMedium),
            const SizedBox(height: 4),
            Text('${ms(s.avgWall)} per frame · ${(1000 / s.avgWall).toStringAsFixed(1)} fps', style: t.headlineSmall),
            Text(
              '${s.frames} frames · fastest ${s.minWall} ms · slowest ${s.maxWall} ms · '
              '${s.avgBoxes.toStringAsFixed(1)} boxes/frame',
            ),
            const Divider(),
            _row('Prepare (YUV→RGB, rotate, letterbox)', ms(s.avgPre)),
            _row('Model (TFLite inference)', ms(s.avgInfer)),
            _row('Boxes (decode + NMS)', ms(s.avgPost)),
            if (s.embedCount > 0)
              _row(
                'Embed (${(s.embedCount / s.frames).toStringAsFixed(1)} crops, '
                '${s.embedPerCrop.toStringAsFixed(0)} ms each)',
                ms(s.avgEmbed),
              ),
            _row('Overhead (isolate start, copying)', ms(s.avgWall - s.avgPre - s.avgInfer - s.avgPost - s.avgEmbed)),
          ],
        ),
      ),
    );
  }

  Widget _row(String label, String value) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 2),
    child: Row(
      children: [
        Expanded(child: Text(label)),
        Text(value),
      ],
    ),
  );
}
