import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:mediapipe_flutter_text/text_summarizer.dart';

import 'token_budget_field.dart';
import 'task_support.dart';

class SummarizerPage extends StatefulWidget {
  const SummarizerPage({super.key});

  @override
  State<SummarizerPage> createState() => _SummarizerPageState();
}

class _SummarizerPageState extends State<SummarizerPage> {
  // Key points mode targets 3 to 5 bullets, so a five-sentence sample would
  // mostly be split into bullets. This one has enough detail to condense.
  final _input = TextEditingController(
    text:
        'The city of Riverton will launch a public bike-share program next '
        'spring, the transportation department announced on Tuesday. The first '
        'phase will include 400 bicycles and 50 docking stations spread across '
        'downtown, the university campus and the neighborhoods along the river. '
        "One in four bikes will have an electric motor to help riders on the city's "
        'steep hills. The program will cost about 3.5 million dollars to set up. '
        'A state clean-transportation grant awarded last year will cover most of '
        'that amount, and corporate sponsors will pay the rest. Riders will unlock '
        'bikes with a phone app or a transit card. A single ride will cost two '
        'dollars for the first thirty minutes, and an annual membership will cost '
        '90 dollars. Residents who receive public assistance will be able to buy '
        'a membership for five dollars a year. The idea has been debated for '
        'nearly a decade. An earlier proposal was abandoned in 2019 after business '
        'owners complained about losing parking spaces, so planners now intend to '
        'place most stations on wide sidewalks and in public plazas. Some '
        'residents remain skeptical. At a public hearing last month, several '
        'people worried about theft and vandalism, and others doubted that many '
        'people would ride up the hills. Officials said every bike will have GPS '
        'tracking, and the city will add eight miles of protected bike lanes '
        'before the launch. If the first phase succeeds, a second phase in 2028 '
        'could grow the network to 1,000 bikes and reach the eastern suburbs.',
  );
  TextSummarizer? _task;
  TextSummarizerMode _mode = TextSummarizerMode.keypoints;
  bool _busy = false;
  bool _streaming = true;
  int? _tokenBudget;
  int? _loadedTokenBudget;
  String? _output;
  String? _error;
  double? _elapsedMs;

  Future<TextSummarizer> _load(
    TextSummarizerMode mode,
    int? tokenBudget,
  ) async {
    final file = File.fromUri(
      File(Platform.resolvedExecutable).parent.parent.uri.resolve(
        'Frameworks/App.framework/Resources/flutter_assets/assets/summarization_quant_200m_2modes.litertlm',
      ),
    );
    return TextSummarizer.create(
      TextSummarizerOptions(
        modelPath: file.path,
        mode: mode,
        maxNumTokens: tokenBudget,
      ),
    );
  }

  Future<void> _summarize() async {
    final input = _input.text;
    final mode = _mode;
    final streaming = _streaming;
    final tokenBudget = _tokenBudget;
    setState(() {
      _busy = true;
      _output = null;
      _error = null;
      _elapsedMs = null;
    });
    try {
      if (_task?.mode != mode || _loadedTokenBudget != tokenBudget) {
        await _release();
      }
      final task = _task ??= await _load(mode, tokenBudget);
      _loadedTokenBudget = tokenBudget;
      if (!mounted) {
        await _release();
        return;
      }
      final watch = Stopwatch()..start();
      if (streaming) {
        final text = StringBuffer();
        await for (final update in task.summarizeStream(input)) {
          if (update.chunk case final chunk?) text.write(chunk);
          if (mounted) setState(() => _output = text.toString());
        }
      } else {
        final result = await task.summarize(input);
        if (mounted) setState(() => _output = result.summary);
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
        key: const Key('summarizer-scroll'),
        padding: const EdgeInsets.all(32),
        children: [
          Text(
            'Find the main points',
            style: Theme.of(context).textTheme.headlineMedium,
          ),
          const SizedBox(height: 8),
          const Text(
            'Summarizer 200M · Official MediaPipe pipeline · macOS CPU',
          ),
          const TaskSupport(task: TextTask.summarizer),
          const SizedBox(height: 24),
          SegmentedButton<TextSummarizerMode>(
            segments: const [
              ButtonSegment(
                value: TextSummarizerMode.tldr,
                label: Text('TL;DR'),
              ),
              ButtonSegment(
                value: TextSummarizerMode.keypoints,
                label: Text('Key points'),
              ),
            ],
            selected: {_mode},
            onSelectionChanged: _busy
                ? null
                : (values) => setState(() {
                    _mode = values.single;
                    _output = null;
                    _error = null;
                  }),
          ),
          const SizedBox(height: 20),
          TextField(
            key: const Key('summarizer-input'),
            controller: _input,
            enabled: !_busy,
            minLines: 4,
            maxLines: 10,
            decoration: const InputDecoration(
              labelText: 'Text to summarize',
              helperText:
                  'Key points returns about 3 to 5 bullets. A paragraph with only a few sentences has little to condense.',
              helperMaxLines: 2,
              border: OutlineInputBorder(),
            ),
          ),
          TokenBudgetField(
            key: const Key('summarizer-token-budget'),
            value: _tokenBudget,
            onChanged: _busy
                ? null
                : (value) => setState(() {
                    _tokenBudget = value;
                    _output = null;
                    _error = null;
                  }),
          ),
          SwitchListTile(
            key: const Key('summarizer-streaming'),
            contentPadding: EdgeInsets.zero,
            title: const Text('Stream output'),
            value: _streaming,
            onChanged: _busy
                ? null
                : (value) => setState(() => _streaming = value),
          ),
          FilledButton(
            key: const Key('summarize-button'),
            onPressed: _busy ? null : _summarize,
            child: Text(_busy ? 'Summarizing…' : 'Summarize text'),
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
                      'Summary',
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                    const SizedBox(height: 12),
                    SelectableText(
                      _output!,
                      key: const Key('summarizer-output'),
                    ),
                    if (_elapsedMs != null)
                      Padding(
                        padding: const EdgeInsets.only(top: 16),
                        child: Text(
                          '${_elapsedMs!.toStringAsFixed(1)} ms · CPU',
                          key: const Key('summarizer-timing'),
                        ),
                      ),
                  ],
                ),
              ),
            ),
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
            'Check the summary against the original text. All text processing stays on this Mac.',
          ),
        ],
      ),
    ),
  );
}
