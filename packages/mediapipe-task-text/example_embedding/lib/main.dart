import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:mediapipe_flutter_text/embedding_gemma.dart';

import 'proofreader_page.dart';
import 'summarizer_page.dart';

void main() => runApp(const EmbeddingDemo());

class EmbeddingDemo extends StatelessWidget {
  const EmbeddingDemo({super.key});

  @override
  Widget build(BuildContext context) => MaterialApp(
    debugShowCheckedModeBanner: false,
    theme: ThemeData(colorSchemeSeed: Colors.indigo, useMaterial3: true),
    home: DefaultTabController(
      length: 3,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('MediaPipe text'),
          bottom: const TabBar(
            tabs: [
              Tab(text: 'Sentence similarity'),
              Tab(text: 'Proofreader'),
              Tab(text: 'Summarizer'),
            ],
          ),
        ),
        body: const TabBarView(
          children: [SimilarityPage(), ProofreaderPage(), SummarizerPage()],
        ),
      ),
    ),
  );
}

class SimilarityPage extends StatefulWidget {
  const SimilarityPage({super.key});

  @override
  State<SimilarityPage> createState() => _SimilarityPageState();
}

class _SimilarityPageState extends State<SimilarityPage> {
  final _first = TextEditingController(text: 'A cat is sleeping on the sofa.');
  final _second = TextEditingController(
    text: 'A kitten is resting on a couch.',
  );
  EmbeddingGemma? _task;
  bool _busy = false;
  String? _error;
  double? _similarity;
  double? _elapsedMs;

  Future<EmbeddingGemma> _load() async {
    // A packaged macOS app can mmap the bundled file without copying 184 MB
    // through Dart. flutter_tester uses rootBundle instead of an app bundle.
    final file = File.fromUri(
      File(Platform.resolvedExecutable).parent.parent.uri.resolve(
        'Frameworks/App.framework/Resources/flutter_assets/assets/embedding_gemma.task',
      ),
    );
    if (await file.exists()) {
      return EmbeddingGemma.create(EmbeddingGemmaOptions(modelPath: file.path));
    }
    final data = await rootBundle.load('assets/embedding_gemma.task');
    return EmbeddingGemma.create(
      EmbeddingGemmaOptions(
        modelBytes: data.buffer.asUint8List(
          data.offsetInBytes,
          data.lengthInBytes,
        ),
      ),
    );
  }

  Future<void> _compare() async {
    final first = _first.text;
    final second = _second.text;
    setState(() {
      _busy = true;
      _error = null;
      _similarity = null;
    });
    try {
      final task = _task ??= await _load();
      if (!mounted) {
        await _release();
        return;
      }
      final context = TextFormatContext(
        taskType: EmbeddingTaskType.semanticSimilarity,
      );
      final watch = Stopwatch()..start();
      final results = await Future.wait([
        task.embed(first, context: context),
        task.embed(second, context: context),
      ]);
      final elapsed = watch.elapsedMicroseconds / 1000;
      final similarity = TextEmbedding.cosineSimilarity(
        results[0].embeddings.single,
        results[1].embeddings.single,
      );
      if (mounted) {
        setState(() {
          _similarity = similarity;
          _elapsedMs = elapsed;
        });
      }
    } catch (error) {
      await _release();
      if (mounted) {
        setState(() {
          _error = error.toString();
        });
      }
    } finally {
      if (mounted) {
        setState(() {
          _busy = false;
        });
      }
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
    _first.dispose();
    _second.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    body: Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 800),
        child: ListView(
          padding: const EdgeInsets.all(32),
          children: [
            Text(
              'Compare meaning',
              style: Theme.of(context).textTheme.headlineMedium,
            ),
            const SizedBox(height: 8),
            const Text(
              'EmbeddingGemma 300M · Official MediaPipe pipeline · macOS CPU',
            ),
            const SizedBox(height: 28),
            TextField(
              key: const Key('first-sentence'),
              controller: _first,
              minLines: 2,
              maxLines: 4,
              decoration: const InputDecoration(
                labelText: 'First sentence',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 20),
            TextField(
              key: const Key('second-sentence'),
              controller: _second,
              minLines: 2,
              maxLines: 4,
              decoration: const InputDecoration(
                labelText: 'Second sentence',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 24),
            FilledButton(
              onPressed: _busy ? null : _compare,
              child: Text(_busy ? 'Comparing…' : 'Compare sentences'),
            ),
            if (_busy)
              const Padding(
                padding: EdgeInsets.only(top: 24),
                child: LinearProgressIndicator(),
              ),
            if (_similarity != null)
              Card(
                margin: const EdgeInsets.only(top: 24),
                child: Padding(
                  padding: const EdgeInsets.all(24),
                  child: Column(
                    children: [
                      const Text('Cosine similarity'),
                      Text(
                        _similarity!.toStringAsFixed(4),
                        key: const Key('similarity-score'),
                        style: Theme.of(context).textTheme.displaySmall,
                      ),
                      const SizedBox(height: 8),
                      Text(
                        '768 values per sentence · ${_elapsedMs!.toStringAsFixed(1)} ms for both',
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
              'Higher scores indicate more similar meaning. The model supports up to 512 tokens per input, including its task prompt.',
            ),
          ],
        ),
      ),
    ),
  );
}
