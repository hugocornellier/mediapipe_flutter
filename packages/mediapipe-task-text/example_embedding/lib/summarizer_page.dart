import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:mediapipe_flutter_text/text_summarizer.dart';

class SummarizerPage extends StatefulWidget {
  const SummarizerPage({super.key});

  @override
  State<SummarizerPage> createState() => _SummarizerPageState();
}

class _SummarizerPageState extends State<SummarizerPage> {
  final _input = TextEditingController(
    text:
        'The team met on Monday to plan the next app release. Maya will finish '
        'the camera interface by Thursday. Leo will investigate the startup crash and '
        'send a fix for review on Wednesday. Testing begins on Friday, and the release '
        'is scheduled for the following Tuesday if no critical bugs remain. The team '
        'decided to postpone the new settings screen until the next release.',
  );
  TextSummarizer? _task;
  TextSummarizerMode _mode = TextSummarizerMode.keypoints;
  bool _busy = false;
  bool _streaming = true;
  String? _output;
  String? _error;
  double? _elapsedMs;

  Future<TextSummarizer> _load(TextSummarizerMode mode) async {
    final file = File.fromUri(
      File(Platform.resolvedExecutable).parent.parent.uri.resolve(
        'Frameworks/App.framework/Resources/flutter_assets/assets/summarization_quant_200m_2modes.litertlm',
      ),
    );
    return TextSummarizer.create(
      TextSummarizerOptions(modelPath: file.path, mode: mode),
    );
  }

  Future<void> _summarize() async {
    final input = _input.text;
    final mode = _mode;
    final streaming = _streaming;
    setState(() {
      _busy = true;
      _output = null;
      _error = null;
      _elapsedMs = null;
    });
    try {
      if (_task?.mode != mode) await _release();
      final task = _task ??= await _load(mode);
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
                : (values) => setState(() => _mode = values.single),
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
              border: OutlineInputBorder(),
            ),
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
