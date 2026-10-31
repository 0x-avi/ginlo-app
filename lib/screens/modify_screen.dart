import 'package:flutter/material.dart';
import 'package:speech_to_text/speech_to_text.dart';

import '../data/db.dart';
import '../ui/theme.dart';
import '../voice/catalog_actions.dart';
import '../voice/command.dart';
import '../voice/rules_parser.dart';

/// One line in the conversation.
class _Msg {
  final bool fromUser;
  final String text;
  Proposal? pending; // a change waiting for yes / no (null once answered)
  _Msg(this.fromUser, this.text, {this.pending});
}

/// Modify tab: change the catalog by typing or speaking, e.g. "Maggi ke teen packet bache hain",
/// "Coke ka rate chaalis kar de", "पारले जी का स्टॉक कितना है?".
/// Every change is shown first ("Set Maggi stock: 12 → 3?") and only happens after yes/haan;
/// no/nahi cancels it. Questions are answered straight away.
class ModifyScreen extends StatefulWidget {
  const ModifyScreen({super.key});

  @override
  State<ModifyScreen> createState() => _ModifyScreenState();
}

class _ModifyScreenState extends State<ModifyScreen> {
  final CommandParser _parser = RulesParser(keepUnknownNames: true); // an on-device LLM can replace this
  final _msgs = <_Msg>[
    _Msg(
      false,
      'Type or tap 🎤 and say what changed, e.g. "Maggi ke teen packet bache hain" or '
      '"Coke ka rate chaalis kar de". I\'ll show the change first and do it only when you say yes.',
    ),
  ];
  final _input = TextEditingController();
  final _scroll = ScrollController();
  final _speech = SpeechToText();
  bool _listening = false, _hindi = false;
  String? _askedFor; // the user's sentence we asked a follow-up question about

  void _say(String text, {Proposal? pending}) {
    setState(() => _msgs.add(_Msg(false, text, pending: pending)));
    _scrollDown();
  }

  void _scrollDown() => WidgetsBinding.instance.addPostFrameCallback((_) {
    if (_scroll.hasClients) {
      _scroll.animateTo(
        _scroll.position.maxScrollExtent,
        duration: const Duration(milliseconds: 200),
        curve: Curves.easeOut,
      );
    }
  });

  _Msg? get _waiting {
    for (final m in _msgs.reversed) {
      if (m.pending != null) return m;
    }
    return null;
  }

  Future<void> _send(String raw) async {
    final text = raw.trim();
    if (text.isEmpty) return;
    _input.clear();
    setState(() => _msgs.add(_Msg(true, text)));
    _scrollDown();

    // Answering a pending change? yes/haan applies it, no/nahi cancels it.
    final waiting = _waiting;
    if (waiting != null) {
      final answer = yesNo(text);
      if (answer != null) return _decide(waiting, answer);
      setState(() => waiting.pending = null); // something else was said: drop the old proposal
    }

    final db = await AppDb.open();
    final products = await db.products();
    // A reply to our question ("Kaunsa soap?" -> "Lux") completes the earlier sentence.
    final sentence = _askedFor == null ? text : '$_askedFor $text';
    final parsed = await _parser.parse(sentence, [for (final p in products) p.name]);
    if (!parsed.ready) {
      _askedFor = sentence;
      return _say(parsed.question ?? 'Samjha nahi, phir se bataiye?');
    }
    _askedFor = null;
    for (final c in parsed.actions) {
      final pr = propose(c, products);
      _say(pr.text, pending: pr.needsConfirm && pr.canApply ? pr : null);
    }
  }

  Future<void> _decide(_Msg m, bool yes) async {
    final pr = m.pending!;
    setState(() => m.pending = null);
    if (!yes) return _say('Theek hai, kuch nahi badla. Kya karna hai?');
    final result = await apply(pr, await AppDb.open());
    _say(result);
  }

  Future<void> _mic() async {
    if (_listening) {
      await _speech.stop();
      setState(() => _listening = false);
      return;
    }
    final ok = await _speech.initialize(
      onStatus: (s) {
        if (s == 'done' || s == 'notListening') setState(() => _listening = false);
      },
    );
    if (!ok) return _say('Speech recognition isn\'t available on this phone. Please type instead.');
    setState(() => _listening = true);
    await _speech.listen(
      listenOptions: SpeechListenOptions(localeId: _hindi ? 'hi_IN' : 'en_IN', partialResults: true),
      onResult: (r) {
        _input.text = r.recognizedWords; // show what's heard while speaking
        if (r.finalResult) {
          setState(() => _listening = false);
          _send(r.recognizedWords);
        }
      },
    );
  }

  @override
  void dispose() {
    _speech.stop();
    _input.dispose();
    _scroll.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: const GinloHeader(),
      body: Column(
        children: [
          Expanded(
            child: ListView.builder(
              controller: _scroll,
              padding: const EdgeInsets.all(12),
              itemCount: _msgs.length,
              itemBuilder: (context, i) => _Bubble(msg: _msgs[i], onDecide: (yes) => _decide(_msgs[i], yes)),
            ),
          ),
          SafeArea(
            top: false,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(12, 4, 12, 8),
              child: Row(
                children: [
                  // Speech language: English (en-IN, also catches Hinglish) or Hindi (Devanagari).
                  TextButton(onPressed: () => setState(() => _hindi = !_hindi), child: Text(_hindi ? 'हिं' : 'EN')),
                  Expanded(
                    child: TextField(
                      controller: _input,
                      textInputAction: TextInputAction.send,
                      onSubmitted: _send,
                      decoration: InputDecoration(
                        hintText: _listening ? 'Listening…' : 'Type or speak a change',
                        filled: true,
                        fillColor: Colors.white,
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(24),
                          borderSide: BorderSide.none,
                        ),
                        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                        suffixIcon: IconButton(icon: const Icon(Icons.send), onPressed: () => _send(_input.text)),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  FloatingActionButton(
                    heroTag: 'mic',
                    mini: true,
                    backgroundColor: _listening ? GinloColors.down : GinloColors.blue,
                    foregroundColor: Colors.white,
                    onPressed: _mic,
                    child: Icon(_listening ? Icons.stop : Icons.mic),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _Bubble extends StatelessWidget {
  const _Bubble({required this.msg, required this.onDecide});
  final _Msg msg;
  final void Function(bool yes) onDecide;

  @override
  Widget build(BuildContext context) {
    final user = msg.fromUser;
    return Align(
      alignment: user ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        constraints: BoxConstraints(maxWidth: MediaQuery.sizeOf(context).width * 0.8),
        margin: const EdgeInsets.symmetric(vertical: 4),
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: user ? GinloColors.blue : Colors.white,
          borderRadius: BorderRadius.circular(16),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(msg.text, style: TextStyle(color: user ? Colors.white : GinloColors.ink, fontSize: 15)),
            if (msg.pending != null) ...[
              const SizedBox(height: 8),
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  FilledButton(onPressed: () => onDecide(true), child: const Text('Yes, haan')),
                  const SizedBox(width: 8),
                  OutlinedButton(onPressed: () => onDecide(false), child: const Text('No, nahi')),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }
}
