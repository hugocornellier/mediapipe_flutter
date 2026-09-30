// Copyright 2026 The MediaPipe Authors. Licensed under Apache-2.0.
// The 1.0.1 C API of Audio Classifier (audio clips), which
// mediapipe_flutter_audio binds, over Google's prebuilt Objective-C Tasks SDK.
// As for text, Google implements these classes in MediaPipeTasksCommon, which
// this adapter already links. No inference code lives here.
#import <MediaPipeTasksAudio/MediaPipeTasksAudio.h>

#include "sdk_bridge_support.h"

#include "mediapipe/tasks/c/audio/audio_classifier/audio_classifier.h"

struct MpAudioClassifierInternal {
  __strong MPPAudioClassifier *task;
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

void FreeClassifications(MpClassificationResult &result) {
  for (uint32_t i = 0; i < result.classifications_count; ++i) {
    MpClassifications &head = result.classifications[i];
    for (uint32_t j = 0; j < head.categories_count; ++j) {
      free(head.categories[j].category_name);
      free(head.categories[j].display_name);
    }
    free(head.categories);
    free(head.head_name);
  }
  free(result.classifications);
}

}  // namespace

extern "C" {

MpStatus MpAudioClassifierCreate(MpAudioClassifierOptions *options,
                                 MpAudioClassifierPtr *out, char **message) {
  @autoreleasepool {
    if (!options || !out) return Fail(message, @"Supply options and output");
    *out = nullptr;
    if (options->running_mode != kMpAudioRunningModeAudioClips) {
      return Fail(message, @"The Dart adapter classifies audio clips only", kMpUnimplemented);
    }
    NSString *temporary = nil;
    MPPAudioClassifierOptions *sdk = [MPPAudioClassifierOptions new];
    MpStatus status = ConfigureBase(sdk, options->base_options, &temporary, message);
    if (status != kMpOk) return status;
    sdk.runningMode = MPPAudioRunningModeAudioClips;
    ApplyClassifierOptions(sdk, options->classifier_options);
    return OwnTask<MpAudioClassifierInternal, MPPAudioClassifier>(sdk, temporary, out, message);
  }
}

MpStatus MpAudioClassifierClassify(MpAudioClassifierPtr task, const MpAudioData *audio,
                                   MpAudioClassifierResult *out, char **message) {
  @autoreleasepool {
    if (!task || !out) return Fail(message, @"Supply a task and result");
    *out = {};
    if (!audio || !audio->audio_data || audio->num_channels < 1 ||
        audio->audio_data_size % audio->num_channels) {
      return Fail(message, @"Audio must hold whole frames of interleaved samples");
    }
    // Interleaved samples, one frame per channel group, as the C API takes them.
    MPPAudioDataFormat *format =
        [[MPPAudioDataFormat alloc] initWithChannelCount:audio->num_channels
                                              sampleRate:audio->sample_rate];
    MPPAudioData *clip = [[MPPAudioData alloc]
        initWithFormat:format
           sampleCount:audio->audio_data_size / audio->num_channels];
    MPPFloatBuffer *buffer = [[MPPFloatBuffer alloc] initWithData:audio->audio_data
                                                           length:audio->audio_data_size];
    NSError *error = nil;
    if (![clip loadBuffer:buffer offset:0 length:audio->audio_data_size error:&error]) {
      return SdkError(message, error);
    }
    MPPAudioClassifierResult *result = [task->task classifyAudioClip:clip error:&error];
    if (!result) return SdkError(message, error);
    try {
      NSArray<MPPClassificationResult *> *chunks = result.classificationResults;
      out->results = Allocate<MpClassificationResult>(chunks.count);
      out->results_count = static_cast<int>(chunks.count);
      for (NSUInteger i = 0; i < chunks.count; ++i) {
        CopyClassifications(chunks[i], &out->results[i]);
      }
    } catch (const std::bad_alloc &) {
      MpAudioClassifierCloseResult(out);
      return Fail(message, @"Cannot copy task result", kMpResourceExhausted);
    }
    return kMpOk;
  }
}

void MpAudioClassifierCloseResult(MpAudioClassifierResult *result) {
  if (!result) return;
  for (int i = 0; i < result->results_count; ++i) {
    FreeClassifications(result->results[i]);
  }
  free(result->results);
  *result = {};
}

MpStatus MpAudioClassifierClose(MpAudioClassifierPtr task, char **message) {
  return CloseHandle(task);
}

}  // extern "C"
