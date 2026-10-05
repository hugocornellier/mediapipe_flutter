// Copyright 2026 The MediaPipe Authors. Licensed under Apache-2.0.
// The 1.0.1 C API of Audio Classifier, in its audio clips and audio stream
// modes, which mediapipe_audio binds, over Google's prebuilt Objective-C
// Tasks SDK. As for text, Google implements these classes in
// MediaPipeTasksCommon, which this adapter already links. No inference code
// lives here.
#import <MediaPipeTasksAudio/MediaPipeTasksAudio.h>

#include "sdk_bridge_support.h"

#include "mediapipe/tasks/c/audio/audio_classifier/audio_classifier.h"

// Hands each of the SDK's stream results to the C API's result callback.
@interface MPFlutterAudioStreamDelegate : NSObject <MPPAudioClassifierStreamDelegate>
- (instancetype)initWithCallback:(MpAudioClassifierOptions::result_callback_fn)callback;
@end

struct MpAudioClassifierInternal {
  __strong MPPAudioClassifier *task;
  __strong NSString *temporaryModel;
  // A stream's delegate, which the SDK holds only weakly, and the private
  // serial queue the SDK calls it on.
  __strong MPFlutterAudioStreamDelegate *delegate = nil;
  __strong dispatch_queue_t callbackQueue = nil;
};

namespace {

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

// The C API's audio data as the SDK's in [out], its interleaved samples
// copied in.
MpStatus SdkAudio(const MpAudioData *audio, MPPAudioData **out, char **message) {
  if (!audio || !audio->audio_data || audio->num_channels < 1 ||
      audio->audio_data_size % audio->num_channels) {
    return Fail(message, @"Audio must hold whole frames of interleaved samples");
  }
  // Interleaved samples, one frame per channel group, as the C API takes them.
  MPPAudioDataFormat *format =
      [[MPPAudioDataFormat alloc] initWithChannelCount:audio->num_channels
                                            sampleRate:audio->sample_rate];
  MPPAudioData *data = [[MPPAudioData alloc]
      initWithFormat:format
         sampleCount:audio->audio_data_size / audio->num_channels];
  MPPFloatBuffer *buffer = [[MPPFloatBuffer alloc] initWithData:audio->audio_data
                                                         length:audio->audio_data_size];
  NSError *error = nil;
  if (![data loadBuffer:buffer offset:0 length:audio->audio_data_size error:&error]) {
    return SdkError(message, error);
  }
  *out = data;
  return kMpOk;
}

}  // namespace

@implementation MPFlutterAudioStreamDelegate {
  MpAudioClassifierOptions::result_callback_fn _callback;
}

- (instancetype)initWithCallback:(MpAudioClassifierOptions::result_callback_fn)callback {
  self = [super init];
  if (self) _callback = callback;
  return self;
}

// On the SDK's private serial queue, one result at a time, in order. The C
// API calls back with one result, freed when the callback returns, or with a
// status and no result; its callback has no room for the error's message, so
// the message goes to the log.
- (void)audioClassifier:(MPPAudioClassifier *)classifier
    didFinishClassificationWithResult:(MPPAudioClassifierResult *)result
              timestampInMilliseconds:(NSInteger)timestampInMilliseconds
                                error:(NSError *)error {
  MPPClassificationResult *window = result.classificationResults.firstObject;
  if (error || !window) {
    NSLog(@"MediaPipe audio stream failed: %@",
          error ? error.localizedDescription : @"a result without a window");
    const NSInteger code = error.code;
    _callback(code > 0 && code <= 16 ? static_cast<MpStatus>(code) : kMpInternal, nullptr);
    return;
  }
  MpAudioClassifierResult copy = {};
  try {
    copy.results = Allocate<MpClassificationResult>(1);
    copy.results_count = 1;
    CopyClassifications(window, &copy.results[0]);
  } catch (const std::bad_alloc &) {
    MpAudioClassifierCloseResult(&copy);
    _callback(kMpResourceExhausted, nullptr);
    return;
  }
  // The SDK's own stamp: the packet's time in milliseconds, which for the
  // tail its close flushes is Google's sentinel, as on every platform.
  copy.results[0].timestamp_ms = timestampInMilliseconds;
  _callback(kMpOk, &copy);
  MpAudioClassifierCloseResult(&copy);
}

@end

extern "C" {

MpStatus MpAudioClassifierCreate(MpAudioClassifierOptions *options,
                                 MpAudioClassifierPtr *out, char **message) {
  @autoreleasepool {
    if (!options || !out) return Fail(message, @"Supply options and output");
    *out = nullptr;
    const bool stream = options->running_mode == kMpAudioRunningModeAudioStream;
    if (!stream && options->running_mode != kMpAudioRunningModeAudioClips) {
      return Fail(message, @"Unknown audio running mode");
    }
    if (stream != (options->result_callback != nullptr)) {
      return Fail(message, stream ? @"Audio stream mode needs a result callback"
                                  : @"Audio clips mode takes no result callback");
    }
    NSString *temporary = nil;
    MPPAudioClassifierOptions *sdk = [MPPAudioClassifierOptions new];
    MpStatus status = ConfigureBase(sdk, options->base_options, &temporary, message);
    if (status != kMpOk) return status;
    sdk.runningMode = stream ? MPPAudioRunningModeAudioStream : MPPAudioRunningModeAudioClips;
    MPFlutterAudioStreamDelegate *delegate =
        stream ? [[MPFlutterAudioStreamDelegate alloc] initWithCallback:options->result_callback]
               : nil;
    sdk.audioClassifierStreamDelegate = delegate;
    ApplyClassifierOptions(sdk, options->classifier_options);
    status = OwnTask<MpAudioClassifierInternal, MPPAudioClassifier>(sdk, temporary, out, message);
    if (status != kMpOk || !stream) return status;
    (*out)->delegate = delegate;
    // closeWithError: returns before the SDK's private serial queue has run
    // the last delegate calls, and the SDK's public API cannot wait for them,
    // so the close waits on that queue. The SDK keeps it in an instance
    // variable, which key-value coding reads (upstream-issues.md UP-040;
    // proven on the simulator with SDK 1.0.1).
    id queue = nil;
    @try {
      queue = [(*out)->task valueForKey:@"_callbackQueue"];
    } @catch (NSException *exception) {
      NSLog(@"MediaPipe audio stream: %@", exception.reason);
    }
    if (![queue isKindOfClass:NSClassFromString(@"OS_dispatch_queue")]) {
      CloseHandle(*out);
      *out = nullptr;
      return Fail(message,
                  @"This iOS SDK hides the queue its audio stream results wait on, so the stream "
                  @"could not deliver its last results",
                  kMpUnimplemented);
    }
    (*out)->callbackQueue = (dispatch_queue_t)queue;
    return kMpOk;
  }
}

MpStatus MpAudioClassifierClassify(MpAudioClassifierPtr task, const MpAudioData *audio,
                                   MpAudioClassifierResult *out, char **message) {
  @autoreleasepool {
    if (!task || !out) return Fail(message, @"Supply a task and result");
    *out = {};
    MPPAudioData *clip = nil;
    const MpStatus status = SdkAudio(audio, &clip, message);
    if (status != kMpOk) return status;
    NSError *error = nil;
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

// Copies the block's samples into the SDK's audio data, so the caller may
// free them when this returns.
MpStatus MpAudioClassifierClassifyAsync(MpAudioClassifierPtr task, const MpAudioData *audio,
                                        int64_t timestamp_ms, char **message) {
  @autoreleasepool {
    if (!task) return Fail(message, @"Supply a task");
    MPPAudioData *block = nil;
    const MpStatus status = SdkAudio(audio, &block, message);
    if (status != kMpOk) return status;
    NSError *error = nil;
    if (![task->task classifyAsyncAudioBlock:block
                     timestampInMilliseconds:static_cast<NSInteger>(timestamp_ms)
                                       error:&error]) {
      return SdkError(message, error);
    }
    return kMpOk;
  }
}

MpStatus MpAudioClassifierClose(MpAudioClassifierPtr task, char **message) {
  @autoreleasepool {
    MpStatus status = kMpOk;
    if (task && task->callbackQueue) {
      // The SDK's close flushes the tail and waits for its graph, whose last
      // results are then queued for the delegate; an empty block on the
      // same serial queue runs after the last of them.
      NSError *error = nil;
      if (![task->task closeWithError:&error]) status = SdkError(message, error);
      dispatch_sync(task->callbackQueue, ^{
                    });
    }
    // The handle goes even when the SDK's close failed: its graph is done
    // either way, and nothing could close it again.
    CloseHandle(task);
    return status;
  }
}

}  // extern "C"
