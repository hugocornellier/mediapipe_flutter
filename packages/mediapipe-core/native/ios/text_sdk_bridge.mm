// Copyright 2026 The MediaPipe Authors. Licensed under Apache-2.0.
// The 1.0.1 C API of Text Classifier, Text Embedder, Language Detector,
// Proofreader and Summarizer, which mediapipe_text binds, over Google's
// prebuilt Objective-C Tasks SDK. Google implements these classes in MediaPipeTasksCommon, which
// this adapter already links for the vision tasks, so every task in the app
// shares one copy of Google's task graphs. No inference code lives here.
#import <MediaPipeTasksText/MediaPipeTasksText.h>

#include "sdk_bridge_support.h"

#include "mediapipe/tasks/c/text/language_detector/language_detector.h"
#include "mediapipe/tasks/c/text/text_classifier/text_classifier.h"
#include "mediapipe/tasks/c/text/text_embedder/text_embedder.h"

// The Proofreader and Summarizer C ABI of Google's desktop runtime, which
// publishes no header for these two tasks (so, unlike the functions Google's
// headers declare MP_EXPORT, these definitions carry the attribute
// themselves: the adapter is built with hidden visibility): the layouts are its Python ctypes
// definitions (mediapipe==1.0.1 text/text_proofreader.py and
// text/text_summarizer.py), the same ones mediapipe_text's bindings and
// text_stream_bridge.h declare. Google's iOS SDK offers the same operations
// as Objective-C classes, so the Dart FFI code is identical on every native
// target.
struct MpTextProofreaderOptions {
  MpBaseOptions base_options;
  int32_t max_num_tokens;
  const char *cache_dir;
};
struct MpCorrection { int32_t type; const char *text; };
struct MpTextProofreaderResult {
  const char *proofread_text;
  int32_t corrections_count;
  MpCorrection *corrections;
};
struct MpTextProofreaderStreamResult {
  const char *chunk;
  int32_t corrections_count;
  const MpCorrection *corrections;
  bool done;
};
using MpTextProofreaderCallback = void (*)(
    void *, const MpTextProofreaderStreamResult *, const char *);

struct MpTextSummarizerOptions {
  MpBaseOptions base_options;
  int32_t mode;
  int32_t max_num_tokens;
  const char *cache_dir;
};
struct MpTextSummarizerResult { const char *summary; };
struct MpTextSummarizerStreamResult { const char *chunk; bool done; };
using MpTextSummarizerCallback = void (*)(
    void *, const MpTextSummarizerStreamResult *, const char *);

struct MpTextClassifierInternal {
  __strong MPPTextClassifier *task;
  __strong NSString *temporaryModel;
};

struct MpTextEmbedderInternal {
  __strong MPPTextEmbedder *task;
  __strong NSString *temporaryModel;
};

struct MpLanguageDetectorInternal {
  __strong MPPLanguageDetector *task;
  __strong NSString *temporaryModel;
};

struct MpTextProofreaderInternal {
  __strong MPPTextProofreader *task;
  __strong NSString *temporaryModel;
};

struct MpTextSummarizerInternal {
  __strong MPPTextSummarizer *task;
  __strong NSString *temporaryModel;
};

namespace {

void CopyEmbeddings(MPPEmbeddingResult *source, MpEmbeddingResult *out) {
  NSArray<MPPEmbedding *> *heads = source.embeddings;
  out->embeddings = Allocate<MpEmbedding>(heads.count);
  out->embeddings_count = static_cast<uint32_t>(heads.count);
  for (NSUInteger i = 0; i < heads.count; ++i) {
    MPPEmbedding *head = heads[i];
    MpEmbedding &target = out->embeddings[i];
    target.head_index = static_cast<int>(head.headIndex);
    target.head_name = CopyString(head.headName);
    if (head.floatEmbedding) {
      target.values_count = static_cast<uint32_t>(head.floatEmbedding.count);
      target.float_embedding = Allocate<float>(head.floatEmbedding.count);
      for (NSUInteger j = 0; j < head.floatEmbedding.count; ++j) {
        target.float_embedding[j] = head.floatEmbedding[j].floatValue;
      }
    } else {
      // Google's API lists the scalar-quantized bytes as unsigned values.
      target.values_count = static_cast<uint32_t>(head.quantizedEmbedding.count);
      target.quantized_embedding = Allocate<char>(head.quantizedEmbedding.count);
      for (NSUInteger j = 0; j < head.quantizedEmbedding.count; ++j) {
        target.quantized_embedding[j] =
            static_cast<char>(head.quantizedEmbedding[j].unsignedCharValue);
      }
    }
  }
  out->timestamp_ms = source.timestampInMilliseconds;
  out->has_timestamp_ms = true;
}

NSString *Text(const char *utf8, char **message) {
  if (!utf8) {
    Fail(message, @"Text must not be null");
    return nil;
  }
  NSString *text = [NSString stringWithUTF8String:utf8];
  if (!text) Fail(message, @"Text must be valid UTF-8");
  return text;
}

// Google's Objective-C roles count from 0; the C API's from 1.
MPPTextFormatContext *FormatContext(const MpTextEmbedderFormatContext *source) {
  if (!source) return nil;
  MPPTextFormatContext *context = [MPPTextFormatContext new];
  context.embeddingType = static_cast<MPPEmbeddingType>(source->task_type);
  if (source->title) context.title = [NSString stringWithUTF8String:source->title];
  context.textRole = source->role == MP_TEXT_EMBEDDER_ROLE_DOCUMENT ? MPPTextRoleDocument
                                                                    : MPPTextRoleQuery;
  return context;
}

// Google's 1.0.1 iOS Proofreader and Summarizer hand back their generated
// text decoded as Mac Roman: the UTF-8 bytes of "café" arrive as "caf√©"
// (upstream-issues.md UP-035). Mac Roman assigns a character to every byte,
// so encoding the text back yields the original bytes, read here as UTF-8.
// Text that is already valid UTF-8, including plain ASCII, is left as it is:
// its Mac Roman bytes are either the same text or not valid UTF-8.
NSString *GenerativeText(NSString *source) {
  if (!source) return nil;
  NSData *bytes = [source dataUsingEncoding:NSMacOSRomanStringEncoding
                     allowLossyConversion:NO];
  if (!bytes) return source;
  NSString *repaired = [[NSString alloc] initWithData:bytes encoding:NSUTF8StringEncoding];
  return repaired ? repaired : source;
}

void CopyCorrections(NSArray<MPPCorrection *> *source, int32_t *count,
                     MpCorrection **out) {
  *count = static_cast<int32_t>(source.count);
  *out = Allocate<MpCorrection>(source.count);
  for (NSUInteger i = 0; i < source.count; ++i) {
    (*out)[i].type = static_cast<int32_t>(source[i].type);
    (*out)[i].text = CopyString(GenerativeText(source[i].text));
  }
}

void FreeCorrections(MpCorrection *values, int32_t count) {
  for (int32_t i = 0; i < count; ++i) free(const_cast<char *>(values[i].text));
  free(values);
}

}  // namespace

extern "C" {

MpStatus MpTextClassifierCreate(MpTextClassifierOptions *options, MpTextClassifierPtr *out,
                                char **message) {
  @autoreleasepool {
    if (!options || !out) return Fail(message, @"Supply options and output");
    *out = nullptr;
    NSString *temporary = nil;
    MPPTextClassifierOptions *sdk = [MPPTextClassifierOptions new];
    MpStatus status = ConfigureBase(sdk, options->base_options, &temporary, message);
    if (status != kMpOk) return status;
    ApplyClassifierOptions(sdk, options->classifier_options);
    return OwnTask<MpTextClassifierInternal, MPPTextClassifier>(sdk, temporary, out, message);
  }
}

MpStatus MpTextClassifierClassify(MpTextClassifierPtr task, const char *utf8,
                                  MpTextClassifierResult *out, char **message) {
  @autoreleasepool {
    if (!task || !out) return Fail(message, @"Supply a task and result");
    *out = {};
    NSString *text = Text(utf8, message);
    if (!text) return kMpInvalidArgument;
    NSError *error = nil;
    MPPTextClassifierResult *result = [task->task classifyText:text error:&error];
    if (!result) return SdkError(message, error);
    try {
      CopyClassifications(result.classificationResult, out);
    } catch (const std::bad_alloc &) {
      MpTextClassifierCloseResult(out);
      return Fail(message, @"Cannot copy task result", kMpResourceExhausted);
    }
    return kMpOk;
  }
}

void MpTextClassifierCloseResult(MpTextClassifierResult *result) {
  if (!result) return;
  for (uint32_t i = 0; i < result->classifications_count; ++i) {
    MpClassifications &head = result->classifications[i];
    for (uint32_t j = 0; j < head.categories_count; ++j) {
      free(head.categories[j].category_name);
      free(head.categories[j].display_name);
    }
    free(head.categories);
    free(head.head_name);
  }
  free(result->classifications);
  *result = {};
}

MpStatus MpTextClassifierClose(MpTextClassifierPtr task, char **message) {
  return CloseHandle(task);
}

MpStatus MpTextEmbedderCreate(MpTextEmbedderOptions *options, MpTextEmbedderPtr *out,
                              char **message) {
  @autoreleasepool {
    if (!options || !out) return Fail(message, @"Supply options and output");
    *out = nullptr;
    NSString *temporary = nil;
    MPPTextEmbedderOptions *sdk = [MPPTextEmbedderOptions new];
    MpStatus status = ConfigureBase(sdk, options->base_options, &temporary, message);
    if (status != kMpOk) return status;
    sdk.l2Normalize = options->embedder_options.l2_normalize;
    sdk.quantize = options->embedder_options.quantize;
    return OwnTask<MpTextEmbedderInternal, MPPTextEmbedder>(sdk, temporary, out, message);
  }
}

MpStatus MpTextEmbedderEmbed(MpTextEmbedderPtr task, const char *utf8,
                             const MpTextEmbedderFormatContext *context,
                             MpTextEmbedderResult *out, char **message) {
  @autoreleasepool {
    if (!task || !out) return Fail(message, @"Supply a task and result");
    *out = {};
    NSString *text = Text(utf8, message);
    if (!text) return kMpInvalidArgument;
    NSError *error = nil;
    MPPTextEmbedderResult *result =
        context ? [task->task embedText:text textFormatContext:FormatContext(context) error:&error]
                : [task->task embedText:text error:&error];
    if (!result) return SdkError(message, error);
    try {
      CopyEmbeddings(result.embeddingResult, out);
    } catch (const std::bad_alloc &) {
      MpTextEmbedderCloseResult(out);
      return Fail(message, @"Cannot copy task result", kMpResourceExhausted);
    }
    return kMpOk;
  }
}

void MpTextEmbedderCloseResult(MpTextEmbedderResult *result) {
  if (!result) return;
  for (uint32_t i = 0; i < result->embeddings_count; ++i) {
    free(result->embeddings[i].float_embedding);
    free(result->embeddings[i].quantized_embedding);
    free(result->embeddings[i].head_name);
  }
  free(result->embeddings);
  *result = {};
}

MpStatus MpTextEmbedderClose(MpTextEmbedderPtr task, char **message) {
  return CloseHandle(task);
}

MpStatus MpLanguageDetectorCreate(MpLanguageDetectorOptions *options, MpLanguageDetectorPtr *out,
                                  char **message) {
  @autoreleasepool {
    if (!options || !out) return Fail(message, @"Supply options and output");
    *out = nullptr;
    NSString *temporary = nil;
    MPPLanguageDetectorOptions *sdk = [MPPLanguageDetectorOptions new];
    MpStatus status = ConfigureBase(sdk, options->base_options, &temporary, message);
    if (status != kMpOk) return status;
    ApplyClassifierOptions(sdk, options->classifier_options);
    return OwnTask<MpLanguageDetectorInternal, MPPLanguageDetector>(sdk, temporary, out, message);
  }
}

MpStatus MpLanguageDetectorDetect(MpLanguageDetectorPtr task, const char *utf8,
                                  MpLanguageDetectorResult *out, char **message) {
  @autoreleasepool {
    if (!task || !out) return Fail(message, @"Supply a task and result");
    *out = {};
    NSString *text = Text(utf8, message);
    if (!text) return kMpInvalidArgument;
    NSError *error = nil;
    MPPLanguageDetectorResult *result = [task->task detectText:text error:&error];
    if (!result) return SdkError(message, error);
    try {
      NSArray<MPPLanguagePrediction *> *predictions = result.languagePredictions;
      out->predictions = Allocate<MpLanguageDetectorPrediction>(predictions.count);
      out->predictions_count = static_cast<uint32_t>(predictions.count);
      for (NSUInteger i = 0; i < predictions.count; ++i) {
        out->predictions[i].language_code = CopyString(predictions[i].languageCode);
        out->predictions[i].probability = predictions[i].probability;
      }
    } catch (const std::bad_alloc &) {
      MpLanguageDetectorCloseResult(out);
      return Fail(message, @"Cannot copy task result", kMpResourceExhausted);
    }
    return kMpOk;
  }
}

void MpLanguageDetectorCloseResult(MpLanguageDetectorResult *result) {
  if (!result) return;
  for (uint32_t i = 0; i < result->predictions_count; ++i) {
    free(result->predictions[i].language_code);
  }
  free(result->predictions);
  *result = {};
}

MpStatus MpLanguageDetectorClose(MpLanguageDetectorPtr task, char **message) {
  return CloseHandle(task);
}

MP_EXPORT MpStatus MpTextProofreaderCreate(MpTextProofreaderOptions *options,
                                 MpTextProofreaderInternal **out,
                                 char **message) {
  @autoreleasepool {
    if (!options || !out) return Fail(message, @"Supply options and output");
    *out = nullptr;
    NSString *temporary = nil;
    MPPTextProofreaderOptions *sdk = [MPPTextProofreaderOptions new];
    MpStatus status = ConfigureBase(sdk, options->base_options, &temporary, message);
    if (status != kMpOk) return status;
    sdk.maxNumTokens = options->max_num_tokens;
    if (options->cache_dir) {
      sdk.cacheDir = [NSString stringWithUTF8String:options->cache_dir];
    }
    return OwnTask<MpTextProofreaderInternal, MPPTextProofreader>(
        sdk, temporary, out, message);
  }
}

MP_EXPORT MpStatus MpTextProofreaderProofread(MpTextProofreaderInternal *task,
                                    const char *utf8,
                                    MpTextProofreaderResult **out,
                                    char **message) {
  @autoreleasepool {
    if (!task || !out) return Fail(message, @"Supply a task and result");
    *out = nullptr;
    NSString *text = Text(utf8, message);
    if (!text) return kMpInvalidArgument;
    NSError *error = nil;
    MPPTextProofreaderResult *source = [task->task proofreadText:text error:&error];
    if (!source) return SdkError(message, error);
    auto *result = Allocate<MpTextProofreaderResult>(1);
    try {
      result->proofread_text = CopyString(GenerativeText(source.proofreadText));
      CopyCorrections(source.corrections, &result->corrections_count,
                      &result->corrections);
    } catch (const std::bad_alloc &) {
      free(const_cast<char *>(result->proofread_text));
      FreeCorrections(result->corrections, result->corrections_count);
      free(result);
      return Fail(message, @"Cannot copy task result", kMpResourceExhausted);
    }
    *out = result;
    return kMpOk;
  }
}

MP_EXPORT MpStatus MpTextProofreaderProofreadStreaming(
    MpTextProofreaderInternal *task, const char *utf8,
    MpTextProofreaderCallback callback, void *context, char **message) {
  @autoreleasepool {
    if (!task || !callback) return Fail(message, @"Supply a task and callback");
    NSString *text = Text(utf8, message);
    if (!text) return kMpInvalidArgument;
    NSError *error = nil;
    BOOL started = [task->task proofreadStreamingWithText:text
        completionHandler:^(MPPTextProofreaderStreamResult *result, NSError *streamError) {
          @autoreleasepool {
            if (streamError) {
              callback(context, nullptr, streamError.localizedDescription.UTF8String);
              return;
            }
            MpTextProofreaderStreamResult view = {};
            view.chunk = GenerativeText(result.chunk).UTF8String;
            view.done = result.done;
            NSMutableData *storage = nil;
            if (result.corrections.count) {
              storage = [NSMutableData dataWithLength:
                  result.corrections.count * sizeof(MpCorrection)];
              auto *values = static_cast<MpCorrection *>(storage.mutableBytes);
              for (NSUInteger i = 0; i < result.corrections.count; ++i) {
                values[i].type = static_cast<int32_t>(result.corrections[i].type);
                values[i].text = GenerativeText(result.corrections[i].text).UTF8String;
              }
              view.corrections = values;
              view.corrections_count = static_cast<int32_t>(result.corrections.count);
            }
            callback(context, &view, nullptr);
          }
        } error:&error];
    return started ? kMpOk : SdkError(message, error);
  }
}

MP_EXPORT void MpTextProofreaderCloseResult(MpTextProofreaderResult *result) {
  if (!result) return;
  free(const_cast<char *>(result->proofread_text));
  FreeCorrections(result->corrections, result->corrections_count);
  free(result);
}

MP_EXPORT MpStatus MpTextProofreaderClose(MpTextProofreaderInternal *task, char **message) {
  @autoreleasepool {
    if (!task) return kMpOk;
    NSError *error = nil;
    if (![task->task closeWithError:&error]) return SdkError(message, error);
    return CloseHandle(task);
  }
}

MP_EXPORT MpStatus MpTextSummarizerCreate(MpTextSummarizerOptions *options,
                                MpTextSummarizerInternal **out,
                                char **message) {
  @autoreleasepool {
    if (!options || !out) return Fail(message, @"Supply options and output");
    *out = nullptr;
    NSString *temporary = nil;
    MPPTextSummarizerOptions *sdk = [MPPTextSummarizerOptions new];
    MpStatus status = ConfigureBase(sdk, options->base_options, &temporary, message);
    if (status != kMpOk) return status;
    sdk.mode = static_cast<MPPTextSummarizerMode>(options->mode);
    sdk.maxNumTokens = options->max_num_tokens;
    if (options->cache_dir) sdk.cacheDir = [NSString stringWithUTF8String:options->cache_dir];
    return OwnTask<MpTextSummarizerInternal, MPPTextSummarizer>(
        sdk, temporary, out, message);
  }
}

MP_EXPORT MpStatus MpTextSummarizerSummarize(MpTextSummarizerInternal *task,
                                   const char *utf8,
                                   MpTextSummarizerResult *out,
                                   char **message) {
  @autoreleasepool {
    if (!task || !out) return Fail(message, @"Supply a task and result");
    *out = {};
    NSString *text = Text(utf8, message);
    if (!text) return kMpInvalidArgument;
    NSError *error = nil;
    MPPTextSummarizerResult *source = [task->task summarizeText:text error:&error];
    if (!source) return SdkError(message, error);
    try {
      out->summary = CopyString(GenerativeText(source.summary));
    } catch (const std::bad_alloc &) {
      return Fail(message, @"Cannot copy task result", kMpResourceExhausted);
    }
    return kMpOk;
  }
}

MP_EXPORT MpStatus MpTextSummarizerSummarizeStreaming(
    MpTextSummarizerInternal *task, const char *utf8,
    MpTextSummarizerCallback callback, void *context, char **message) {
  @autoreleasepool {
    if (!task || !callback) return Fail(message, @"Supply a task and callback");
    NSString *text = Text(utf8, message);
    if (!text) return kMpInvalidArgument;
    NSError *error = nil;
    BOOL started = [task->task summarizeStreamingWithText:text
        completionHandler:^(MPPTextSummarizerStreamResult *result, NSError *streamError) {
          @autoreleasepool {
            if (streamError) {
              callback(context, nullptr, streamError.localizedDescription.UTF8String);
              return;
            }
            MpTextSummarizerStreamResult view = {
                GenerativeText(result.chunk).UTF8String, static_cast<bool>(result.done)};
            callback(context, &view, nullptr);
          }
        } error:&error];
    return started ? kMpOk : SdkError(message, error);
  }
}

MP_EXPORT void MpTextSummarizerCloseResult(MpTextSummarizerResult *result) {
  if (!result) return;
  free(const_cast<char *>(result->summary));
  *result = {};
}

MP_EXPORT MpStatus MpTextSummarizerClose(MpTextSummarizerInternal *task, char **message) {
  @autoreleasepool {
    if (!task) return kMpOk;
    NSError *error = nil;
    if (![task->task closeWithError:&error]) return SdkError(message, error);
    return CloseHandle(task);
  }
}

}  // extern "C"
