// Copyright 2014 The Flutter Authors. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

import 'dart:async';
import 'package:flutter/services.dart';
import 'package:example/keyboard_hider.dart';
import 'package:flutter/material.dart';
import 'package:mediapipe_flutter_core/mediapipe_flutter_core.dart';
import 'package:mediapipe_flutter_text/mediapipe_flutter_text.dart';
import 'enumerate.dart';

class TextClassificationDemo extends StatefulWidget {
  const TextClassificationDemo({super.key, this.classifier});

  final TextClassifier? classifier;

  @override
  State<TextClassificationDemo> createState() => _TextClassificationDemoState();
}

class _TextClassificationDemoState extends State<TextClassificationDemo>
    with AutomaticKeepAliveClientMixin<TextClassificationDemo> {
  final TextEditingController _controller = TextEditingController();
  late final Future<TextClassifier> _task;
  String? _error;
  final results = <Widget>[];
  String? _isProcessing;

  @override
  void initState() {
    super.initState();
    _controller.text = 'Hello, world!';
    _task = _initClassifier();
    unawaited(
      _task.then<void>(
        (_) {},
        onError: (Object error, StackTrace _) {
          if (mounted) setState(() => _error = error.toString());
        },
      ),
    );
  }

  Future<TextClassifier> _initClassifier() async {
    if (widget.classifier != null) return widget.classifier!;
    final bytes = await rootBundle.load('assets/bert_classifier.tflite');
    return TextClassifier.create(
      TextClassifierOptions.fromAssetBuffer(
        bytes.buffer.asUint8List(bytes.offsetInBytes, bytes.lengthInBytes),
      ),
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    if (widget.classifier == null) {
      unawaited(
        _task.then((task) => task.dispose()).catchError((Object error) {
          debugPrint('Closing TextClassifier: $error');
        }),
      );
    }
    super.dispose();
  }

  void _prepareForClassification() {
    setState(() {
      _isProcessing = _controller.text;
      results.add(const CircularProgressIndicator.adaptive());
    });
  }

  void _showClassificationResults(TextClassifierResult result) {
    final categoryWidgets = <Widget>[];
    for (final classifications in result.classifications) {
      categoryWidgets.addAll(_textClassifications(classifications));
    }

    setState(() {
      results.last = KeyboardHider(
        child: Card(
          key: Key('Classification::"$_isProcessing" ${results.length}'),
          margin: const EdgeInsets.all(10),
          child: Column(
            children: [
              Padding(
                padding: const EdgeInsets.all(10),
                child: Text(_isProcessing!),
              ),
              Padding(
                padding: const EdgeInsets.all(10.0),
                child: Wrap(children: <Widget>[...categoryWidgets]),
              ),
            ],
          ),
        ),
      );
      _isProcessing = null;
    });
  }

  static final categoryColors = <Color>[
    Colors.blue[300]!,
    Colors.orange[300]!,
    Colors.green[300]!,
    Colors.red[300]!,
  ];

  List<Widget> _textClassifications(Classifications classifications) {
    return classifications.categories
        .enumerate<Widget>(
          (category, index) =>
              _textClassification(category, categoryColors[index]),
        )
        .toList();
  }

  Widget _textClassification(Category category, Color color) {
    return Padding(
      padding: const EdgeInsets.only(right: 8),
      child: Chip(
        label: Text(
          '${category.displayName ?? category.categoryName} :: '
          '${category.score.roundTo(4)}',
        ),
        backgroundColor: color,
      ),
    );
  }

  Future<void> _classify() async {
    _prepareForClassification();
    try {
      final result = await (await _task).classify(_isProcessing!);
      if (mounted) _showClassificationResults(result);
    } catch (error) {
      if (mounted) {
        setState(() {
          results.last = Text(error.toString());
          _isProcessing = null;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    return Scaffold(
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(16.0),
          child: Column(
            children: <Widget>[
              TextField(controller: _controller),
              if (_error != null) Text(_error!),
              ...results.reversed,
            ],
          ),
        ),
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: _isProcessing != null || _error != null ? null : _classify,
        child: const Icon(Icons.search),
      ),
    );
  }

  @override
  bool get wantKeepAlive => true;
}

extension on double {
  double roundTo(int decimalPlaces) =>
      double.parse(toStringAsFixed(decimalPlaces));
}
