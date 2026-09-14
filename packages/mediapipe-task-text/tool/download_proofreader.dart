import 'dart:io';

import 'package:mediapipe_flutter_core/native_assets.dart';
import 'package:mediapipe_flutter_text/models.dart';

Future<void> main(List<String> args) async {
  final target = File(
    args.isEmpty ? 'models/proofread_quant_200m.litertlm' : args.single,
  );
  await downloadVerified(proofreaderModel, target);
  stdout.writeln('Verified ${target.path}');
}
