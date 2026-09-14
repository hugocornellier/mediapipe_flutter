// Copyright 2014 The Flutter Authors. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

import 'dart:async';
import 'package:flutter/services.dart';
import 'package:example/keyboard_hider.dart';
import 'package:flutter/material.dart';
import 'package:mediapipe_flutter_text/mediapipe_flutter_text.dart';
import 'enumerate.dart';

class LanguageDetectionDemo extends StatefulWidget {
  const LanguageDetectionDemo({super.key, this.detector});

  final LanguageDetector? detector;

  @override
  State<LanguageDetectionDemo> createState() => _LanguageDetectionDemoState();
}

class _LanguageDetectionDemoState extends State<LanguageDetectionDemo>
    with AutomaticKeepAliveClientMixin<LanguageDetectionDemo> {
  final TextEditingController _controller = TextEditingController();
  late final Future<LanguageDetector> _task;
  String? _error;
  final results = <Widget>[];
  String? _isProcessing;

  @override
  void initState() {
    super.initState();
    _controller.text = 'Quiero agua, por favor';
    _task = _initDetector();
    unawaited(
      _task.then<void>(
        (_) {},
        onError: (Object error, StackTrace _) {
          if (mounted) setState(() => _error = error.toString());
        },
      ),
    );
  }

  Future<LanguageDetector> _initDetector() async {
    if (widget.detector != null) return widget.detector!;
    final bytes = await rootBundle.load('assets/language_detector.tflite');
    return LanguageDetector.create(
      LanguageDetectorOptions.fromAssetBuffer(
        bytes.buffer.asUint8List(bytes.offsetInBytes, bytes.lengthInBytes),
      ),
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    if (widget.detector == null) {
      unawaited(
        _task.then((task) => task.dispose()).catchError((Object error) {
          debugPrint('Closing LanguageDetector: $error');
        }),
      );
    }
    super.dispose();
  }

  void _prepareForDetection() {
    setState(() {
      _isProcessing = _controller.text;
      results.add(const CircularProgressIndicator.adaptive());
    });
  }

  Future<void> _detect() async {
    _prepareForDetection();
    try {
      final result = await (await _task).detect(_isProcessing!);
      if (mounted) _showDetectionResults(result);
    } catch (error) {
      if (mounted) {
        setState(() {
          results.last = Text(error.toString());
          _isProcessing = null;
        });
      }
    }
  }

  void _showDetectionResults(LanguageDetectorResult result) {
    setState(() {
      results.last = KeyboardHider(
        child: Card(
          key: Key('prediction-"$_isProcessing" ${results.length}'),
          margin: const EdgeInsets.all(10),
          child: Column(
            children: [
              Padding(
                padding: const EdgeInsets.all(10),
                child: Text(_isProcessing!),
              ),
              Padding(
                padding: const EdgeInsets.all(10.0),
                child: Wrap(
                  children: <Widget>[
                    ...result.predictions.enumerate<Widget>(
                      (prediction, index) => _languagePrediction(
                        prediction,
                        predictionColors[index],
                      ),
                      // Take first 4 because the model spits out dozens of
                      // astronomically low probability language predictions
                      max: predictionColors.length,
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      );
      _isProcessing = null;
    });
  }

  static final predictionColors = <Color>[
    Colors.blue[300]!,
    Colors.orange[300]!,
    Colors.green[300]!,
    Colors.red[300]!,
  ];

  Widget _languagePrediction(LanguagePrediction prediction, Color color) {
    return Padding(
      padding: const EdgeInsets.only(right: 8),
      child: Chip(
        label: Text(
          '${prediction.languageCode} :: '
          '${prediction.probability.roundTo(8)}',
        ),
        backgroundColor: color,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    return Scaffold(
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(16.0),
          child: SingleChildScrollView(
            child: Column(
              children: <Widget>[
                TextField(controller: _controller),
                if (_error != null) Text(_error!),
                ...results.reversed,
              ],
            ),
          ),
        ),
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: _isProcessing != null || _error != null ? null : _detect,
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
