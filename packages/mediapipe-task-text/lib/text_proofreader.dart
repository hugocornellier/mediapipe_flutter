/// Google's official Proofread 200M pipeline with safe streaming callbacks.
library;

export 'src/interface/text_proofreader_types.dart';
export 'src/interface/text_proofreader_stub.dart'
    if (dart.library.io) 'src/io/text_proofreader.dart';
