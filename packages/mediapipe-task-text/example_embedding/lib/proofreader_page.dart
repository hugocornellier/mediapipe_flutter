import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:mediapipe_flutter_text/text_proofreader.dart';

import 'token_budget_field.dart';
import 'task_support.dart';

class ProofreaderPage extends StatefulWidget {
  const ProofreaderPage({super.key});

  @override
  State<ProofreaderPage> createState() => _ProofreaderPageState();
}

class _ProofreaderPageState extends State<ProofreaderPage> {
  final _input = TextEditingController(
    text: 'She go to the store yesterday and buyed some apples.',
  );
  TextProofreader? _task;
  bool _busy = false;
  bool _streaming = true;
  int? _tokenBudget;
  int? _loadedTokenBudget;
  String? _output;
  String? _error;
  double? _elapsedMs;
  List<ProofreadingCorrection> _corrections = [];

  Future<TextProofreader> _load(int? tokenBudget) async {
    final file = File.fromUri(
      File(Platform.resolvedExecutable).parent.parent.uri.resolve(
        'Frameworks/App.framework/Resources/flutter_assets/assets/proofread_quant_200m.litertlm',
      ),
    );
    return TextProofreader.create(
      TextProofreaderOptions(modelPath: file.path, maxNumTokens: tokenBudget),
    );
  }

  Future<void> _proofread() async {
    final input = _input.text;
    final streaming = _streaming;
    final tokenBudget = _tokenBudget;
    setState(() {
      _busy = true;
      _output = null;
      _error = null;
      _elapsedMs = null;
      _corrections = [];
    });
    try {
      if (_loadedTokenBudget != tokenBudget) await _release();
      final task = _task ??= await _load(tokenBudget);
      _loadedTokenBudget = tokenBudget;
      if (!mounted) {
        await _release();
        return;
      }
      final watch = Stopwatch()..start();
      if (streaming) {
        final text = StringBuffer();
        await for (final update in task.proofreadStream(input)) {
          if (update.chunk case final chunk?) text.write(chunk);
          if (mounted) {
            setState(() {
              _output = text.toString();
              if (update.done) _corrections = update.corrections;
            });
          }
        }
      } else {
        final result = await task.proofread(input);
        if (mounted) {
          setState(() {
            _output = result.proofreadText;
            _corrections = result.corrections;
          });
        }
      }
      if (mounted) {
        setState(() => _elapsedMs = watch.elapsedMicroseconds / 1000);
      }
    } catch (error) {
      await _release();
      if (mounted) setState(() => _error = error.toString());
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _release() async {
    final task = _task;
    _task = null;
    try {
      await task?.dispose();
    } catch (error) {
      debugPrint('$error');
    }
  }

  @override
  void dispose() {
    unawaited(_release());
    _input.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Center(
    child: ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 800),
      child: ListView(
        key: const Key('proofreader-scroll'),
        padding: const EdgeInsets.all(32),
        children: [
          Text(
            'Polish your writing',
            style: Theme.of(context).textTheme.headlineMedium,
          ),
          const SizedBox(height: 8),
          const Text(
            'Proofreader 200M · Official MediaPipe pipeline · macOS CPU',
          ),
          const TaskSupport(task: TextTask.proofreader),
          const SizedBox(height: 28),
          TextField(
            key: const Key('proofreader-input'),
            controller: _input,
            enabled: !_busy,
            minLines: 3,
            maxLines: 8,
            decoration: const InputDecoration(
              labelText: 'Text to proofread',
              border: OutlineInputBorder(),
            ),
          ),
          TokenBudgetField(
            key: const Key('proofreader-token-budget'),
            value: _tokenBudget,
            onChanged: _busy
                ? null
                : (value) => setState(() {
                    _tokenBudget = value;
                    _output = null;
                    _corrections = [];
                    _error = null;
                  }),
          ),
          SwitchListTile(
            key: const Key('proofreader-streaming'),
            contentPadding: EdgeInsets.zero,
            title: const Text('Stream output'),
            value: _streaming,
            onChanged: _busy
                ? null
                : (value) => setState(() => _streaming = value),
          ),
          FilledButton(
            key: const Key('proofread-button'),
            onPressed: _busy ? null : _proofread,
            child: Text(_busy ? 'Proofreading…' : 'Proofread text'),
          ),
          if (_busy)
            const Padding(
              padding: EdgeInsets.only(top: 24),
              child: LinearProgressIndicator(),
            ),
          if (_output != null)
            Card(
              margin: const EdgeInsets.only(top: 24),
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Corrected text',
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                    const SizedBox(height: 12),
                    SelectableText(
                      _output!,
                      key: const Key('proofreader-output'),
                    ),
                    if (_elapsedMs != null)
                      Padding(
                        padding: const EdgeInsets.only(top: 16),
                        child: Text(
                          '${_elapsedMs!.toStringAsFixed(1)} ms · CPU',
                          key: const Key('proofreader-timing'),
                        ),
                      ),
                  ],
                ),
              ),
            ),
          if (_corrections.isNotEmpty) ...[
            const SizedBox(height: 24),
            Text('Edits', style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 8),
            const Text(
              'Insertions are green and underlined. Deletions are red and crossed out.',
            ),
            const SizedBox(height: 12),
            SelectableText.rich(
              TextSpan(
                children: [
                  for (final edit in _corrections)
                    TextSpan(
                      text: edit.text,
                      style: switch (edit.type) {
                        ProofreadingCorrectionType.same => null,
                        ProofreadingCorrectionType.insertion => const TextStyle(
                          color: Color(0xff18733b),
                          decoration: TextDecoration.underline,
                        ),
                        ProofreadingCorrectionType.deletion => const TextStyle(
                          color: Color(0xffb3261e),
                          decoration: TextDecoration.lineThrough,
                        ),
                      },
                    ),
                ],
              ),
              key: const Key('proofreader-edits'),
            ),
          ],
          if (_error != null)
            Padding(
              padding: const EdgeInsets.only(top: 24),
              child: SelectableText(
                _error!,
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
            ),
          const SizedBox(height: 24),
          const Text(
            'Review the corrections before using them. All text processing stays on this Mac.',
          ),
        ],
      ),
    ),
  );
}
