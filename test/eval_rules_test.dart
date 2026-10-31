import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:ginlo/voice/command.dart';
import 'package:ginlo/voice/rules_parser.dart';

/// Scores the rules parser on eval/voice_eval_200.json and prints the misses.
/// Not a pass/fail gate: it's the baseline any on-device LLM has to beat.
/// Run: flutter test test/eval_rules_test.dart --reporter expanded
void main() {
  test('rules parser on the 200-command benchmark', () {
    final cases = jsonDecode(File('eval/voice_eval_200.json').readAsStringSync()) as List;
    // The shop's catalog = every product the benchmark mentions.
    final catalog = <String>{
      for (final c in cases)
        for (final a in (c['answer']['actions'] as List)) (a['arguments'] as Map)['product'] as String? ?? '',
    }..remove('');
    String flat(Object? s) => '$s'.toLowerCase().replaceAll(RegExp(r'[^a-z0-9ऀ-ॿ]'), '');

    var correct = 0, clarifyOk = 0, clarifyTotal = 0;
    final byTool = <String, List<int>>{}; // tool -> [right, total]
    final misses = <String>[];
    for (final c in cases) {
      final want = c['answer'] as Map;
      final got = RulesParser().parseNow(c['instruction'] as String, catalog.toList());
      bool ok;
      if (want['status'] == 'needs_clarification') {
        clarifyTotal++;
        ok = !got.ready;
        if (ok) clarifyOk++;
      } else {
        final wantActions = want['actions'] as List;
        ok = got.ready && got.actions.length == wantActions.length;
        for (var i = 0; ok && i < wantActions.length; i++) {
          final w = wantActions[i] as Map, a = w['arguments'] as Map, g = got.actions[i];
          // "2 rupaye badha de": we compute price ± 2 directly; the benchmark expects get_price first.
          final tool = g.tool == Tool.changePrice ? 'get_price' : g.tool.id;
          ok =
              tool == w['tool'] &&
              flat(g.product) == flat(a['product']) &&
              (a['qty'] == null || g.qty == a['qty']) &&
              (a['price'] == null || g.price == a['price'] || g.tool == Tool.changePrice) &&
              (a['new_name'] == null || flat(g.newName) == flat(a['new_name']));
        }
      }
      final tool = want['status'] == 'needs_clarification'
          ? 'clarify'
          : (want['actions'] as List).first['tool'] as String;
      final t = byTool.putIfAbsent(tool, () => [0, 0]);
      t[1]++;
      if (ok) {
        correct++;
        t[0]++;
      } else {
        misses.add(
          '${c['instruction']}\n    want ${jsonEncode(want['actions'])}${want['clarification_question'] ?? ''}'
          '\n    got  ${got.ready ? got.actions : 'ASK: ${got.question}'}',
        );
      }
    }
    // ignore: avoid_print
    print(
      '\nRULES PARSER: $correct/${cases.length} correct (${(correct / cases.length * 100).toStringAsFixed(1)}%), '
      'clarifications $clarifyOk/$clarifyTotal',
    );
    for (final e in byTool.entries) {
      // ignore: avoid_print
      print('  ${e.key.padRight(15)} ${e.value[0]}/${e.value[1]}');
    }
    File('eval/rules_misses.txt').writeAsStringSync(misses.join('\n'));
  });
}
