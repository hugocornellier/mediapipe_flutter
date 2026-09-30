// Copyright 2026 The MediaPipe Authors. Licensed under Apache-2.0.
// The 1.0.1 C API of Text Classifier, Text Embedder and Language Detector,
// which mediapipe_flutter_text binds, over Google's prebuilt Objective-C
// Tasks SDK. Google implements these classes in MediaPipeTasksCommon, which
// this adapter already links for the vision tasks, so every task in the app
// shares one copy of Google's task graphs. No inference code lives here.
#import <MediaPipeTasksText/MediaPipeTasksText.h>

#include "sdk_bridge_support.h"

#include "mediapipe/tasks/c/text/language_detector/language_detector.h"
#include "mediapipe/tasks/c/text/text_classifier/text_classifier.h"
#include "mediapipe/tasks/c/text/text_embedder/text_embedder.h"

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

namespace {

void CopyClassifications(MPPClassificationResult *source, MpClassificationResult *out) {
  NSArray<MPPClassifications *> *heads = source.classifications;
  out->classifications = Allocate<MpClassifications>(heads.count);
  out->classifications_count = static_cast<uint32_t>(heads.count);
  for (NSUInteger i = 0; i < heads.count; ++i) {
    MpClassifications &head = out->classifications[i];
    head.head_index = static_cast<int>(heads[i].headIndex);
    head.head_name = CopyString(heads[i].headName);
    NSArray<MPPCategory *> *categories = heads[i].categories;
    head.categories = Allocate<MpCategory>(categories.count);
    head.categories_count = static_cast<uint32_t>(categories.count);
    for (NSUInteger j = 0; j < categories.count; ++j) {
      head.categories[j].index = static_cast<int>(categories[j].index);
      head.categories[j].score = categories[j].score;
      head.categories[j].category_name = CopyString(categories[j].categoryName);
      head.categories[j].display_name = CopyString(categories[j].displayName);
    }
  }
  out->timestamp_ms = source.timestampInMilliseconds;
  out->has_timestamp_ms = true;
}

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

}  // extern "C"
