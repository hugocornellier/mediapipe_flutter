import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:mediapipe_flutter_text/embedding_gemma.dart';

import 'proofreader_page.dart';
import 'summarizer_page.dart';
import 'task_support.dart';

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
  (bool, bool)? _loadedConfiguration;
  bool _normalize = false;
  bool _quantize = false;
  EmbeddingTaskType _taskType = EmbeddingTaskType.semanticSimilarity;
  TextRole _firstRole = TextRole.query;
  TextRole _secondRole = TextRole.query;
  final _firstTitle = TextEditingController();
  final _secondTitle = TextEditingController();
  bool _busy = false;
  String? _error;
  double? _similarity;
  double? _elapsedMs;
  TextEmbedding? _firstEmbedding;
  TextEmbedding? _secondEmbedding;

  Future<EmbeddingGemma> _load() async {
    // A packaged macOS app can mmap the bundled file without copying 184 MB
    // through Dart. flutter_tester uses rootBundle instead of an app bundle.
    final file = File.fromUri(
      File(Platform.resolvedExecutable).parent.parent.uri.resolve(
        'Frameworks/App.framework/Resources/flutter_assets/assets/embedding_gemma.task',
      ),
    );
    if (await file.exists()) {
      return EmbeddingGemma.create(
        EmbeddingGemmaOptions(
          modelPath: file.path,
          l2Normalize: _normalize,
          quantize: _quantize,
        ),
      );
    }
    final data = await rootBundle.load('assets/embedding_gemma.task');
    return EmbeddingGemma.create(
      EmbeddingGemmaOptions(
        l2Normalize: _normalize,
        quantize: _quantize,
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
      _firstEmbedding = null;
      _secondEmbedding = null;
    });
    try {
      if (_loadedConfiguration != (_normalize, _quantize)) await _release();
      final task = _task ??= await _load();
      _loadedConfiguration = (_normalize, _quantize);
      if (!mounted) {
        await _release();
        return;
      }
      final watch = Stopwatch()..start();
      final results = await Future.wait([
        task.embed(
          first,
          context: TextFormatContext(
            taskType: _taskType,
            role: _firstRole,
            title: _firstTitle.text.isEmpty ? null : _firstTitle.text,
          ),
        ),
        task.embed(
          second,
          context: TextFormatContext(
            taskType: _taskType,
            role: _secondRole,
            title: _secondTitle.text.isEmpty ? null : _secondTitle.text,
          ),
        ),
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
          _firstEmbedding = results[0].embeddings.single;
          _secondEmbedding = results[1].embeddings.single;
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
    _firstTitle.dispose();
    _secondTitle.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    body: Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 800),
        child: ListView(
          key: const Key('embedding-scroll'),
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
            ExpansionTile(
              subtitle: const TaskSupport(task: TextTask.embeddingGemma),
              key: const Key('embedding-settings'),
              title: const Text('Embedding settings'),
              children: [
                DropdownButtonFormField<EmbeddingTaskType>(
                  key: const Key('embedding-format'),
                  initialValue: _taskType,
                  decoration: const InputDecoration(labelText: 'Task format'),
                  items: [
                    for (final type in EmbeddingTaskType.values)
                      DropdownMenuItem(
                        value: type,
                        child: Text(_taskLabels[type]!),
                      ),
                  ],
                  onChanged: _busy
                      ? null
                      : (value) => _changeSettings(() {
                          _taskType = value!;
                          if (value == EmbeddingTaskType.retrievalDocument) {
                            _firstRole = _secondRole = TextRole.document;
                          } else {
                            _firstRole = TextRole.query;
                            _secondRole =
                                value == EmbeddingTaskType.retrievalQuery
                                ? TextRole.document
                                : TextRole.query;
                          }
                        }),
                ),
                SwitchListTile(
                  key: const Key('embedding-normalize'),
                  title: const Text('L2 normalization'),
                  value: _normalize,
                  onChanged: _busy
                      ? null
                      : (value) => _changeSettings(() => _normalize = value),
                ),
                SwitchListTile(
                  key: const Key('embedding-quantize'),
                  title: const Text('Quantized output (int8)'),
                  value: _quantize,
                  onChanged: _busy
                      ? null
                      : (value) => _changeSettings(() => _quantize = value),
                ),
                _formatInput(
                  'First',
                  _firstRole,
                  _firstTitle,
                  (value) => _changeSettings(() => _firstRole = value),
                ),
                _formatInput(
                  'Second',
                  _secondRole,
                  _secondTitle,
                  (value) => _changeSettings(() => _secondRole = value),
                ),
                const SizedBox(height: 16),
              ],
            ),
            const SizedBox(height: 20),
            TextField(
              key: const Key('first-sentence'),
              controller: _first,
              enabled: !_busy,
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
              enabled: !_busy,
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
                        '768 ${_quantize ? 'int8' : 'float32'} values per sentence · ${_elapsedMs!.toStringAsFixed(1)} ms for both',
                      ),
                    ],
                  ),
                ),
              ),
            if (_firstEmbedding != null && _secondEmbedding != null)
              Card(
                margin: const EdgeInsets.only(top: 12),
                child: ExpansionTile(
                  key: const Key('embedding-vectors'),
                  title: const Text('Embeddings'),
                  subtitle: Text(
                    'Two 768-value ${_quantize ? 'int8' : 'float32'} vectors',
                  ),
                  children: [
                    _EmbeddingVector(
                      label: 'First sentence',
                      embedding: _firstEmbedding!,
                    ),
                    _EmbeddingVector(
                      label: 'Second sentence',
                      embedding: _secondEmbedding!,
                    ),
                  ],
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

  void _changeSettings(VoidCallback change) => setState(() {
    change();
    _similarity = null;
    _firstEmbedding = null;
    _secondEmbedding = null;
    _error = null;
  });

  Widget _formatInput(
    String name,
    TextRole role,
    TextEditingController title,
    ValueChanged<TextRole> onRoleChanged,
  ) => Column(
    children: [
      Row(
        children: [
          Text('$name input role'),
          const SizedBox(width: 16),
          SegmentedButton<TextRole>(
            key: Key('embedding-${name.toLowerCase()}-role'),
            segments: const [
              ButtonSegment(value: TextRole.query, label: Text('Query')),
              ButtonSegment(value: TextRole.document, label: Text('Document')),
            ],
            selected: {role},
            onSelectionChanged: _busy
                ? null
                : (values) => onRoleChanged(values.single),
          ),
        ],
      ),
      if (role == TextRole.document)
        TextField(
          key: Key('embedding-${name.toLowerCase()}-title'),
          controller: title,
          enabled: !_busy,
          onChanged: (_) => _changeSettings(() {}),
          decoration: InputDecoration(
            labelText: '$name document title (optional)',
          ),
        ),
      const SizedBox(height: 12),
    ],
  );
}

const _taskLabels = {
  EmbeddingTaskType.retrievalDocument: 'Retrieval document',
  EmbeddingTaskType.retrievalQuery: 'Retrieval query',
  EmbeddingTaskType.semanticSimilarity: 'Semantic similarity',
  EmbeddingTaskType.classification: 'Classification',
  EmbeddingTaskType.clustering: 'Clustering',
  EmbeddingTaskType.questionAnswering: 'Question answering',
  EmbeddingTaskType.factChecking: 'Fact checking',
  EmbeddingTaskType.codeRetrieval: 'Code retrieval',
};

class _EmbeddingVector extends StatelessWidget {
  const _EmbeddingVector({required this.label, required this.embedding});

  final String label;
  final TextEmbedding embedding;

  @override
  Widget build(BuildContext context) {
    final List<num> values =
        embedding.floatValues?.toList() ??
        [for (final byte in embedding.quantizedValues!) byte.toSigned(8)];
    final encoded = jsonEncode(values);
    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 8, 24, 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 8),
          SizedBox(
            height: 120,
            child: SingleChildScrollView(child: SelectableText(encoded)),
          ),
          Align(
            alignment: Alignment.centerRight,
            child: TextButton.icon(
              onPressed: () async {
                await Clipboard.setData(ClipboardData(text: encoded));
                if (context.mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text('$label embedding copied')),
                  );
                }
              },
              icon: const Icon(Icons.copy),
              label: Text('Copy $label vector'),
            ),
          ),
        ],
      ),
    );
  }
}
