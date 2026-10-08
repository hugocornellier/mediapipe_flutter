import 'dart:io';

import 'package:mediapipe_core/native_assets.dart';
import 'package:mediapipe_decision/mediapipe_decision.dart';

/// Downloads and verifies Google's Laya model for the native tests.
Future<void> main(List<String> args) async {
  final target = File(args.isEmpty ? 'models/laya_s256.task' : args.single);
  await downloadVerified(DecisionModels.layaS256, target);
  stdout.writeln('Verified ${target.path}');
}
