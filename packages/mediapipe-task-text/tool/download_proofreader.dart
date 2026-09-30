import 'dart:io';

import 'package:mediapipe_core/native_assets.dart';
import 'package:mediapipe_text/mediapipe_text.dart';

Future<void> main(List<String> args) async {
  final target = File(
    args.isEmpty ? 'models/proofread_quant_200m.litertlm' : args.single,
  );
  await downloadVerified(TextModels.proofreader, target);
  stdout.writeln('Verified ${target.path}');
}
