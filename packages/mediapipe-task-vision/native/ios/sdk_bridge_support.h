// Copyright 2026 The MediaPipe Authors. Licensed under Apache-2.0.
// Helpers the text and audio bridges share. Each bridge is its own translation
// unit because Google's Text and Audio frameworks ship identical copies of
// the common headers (MPPCategory.h and others) at separate paths, which one
// unit cannot import twice. Everything here is internal to each unit.
#ifndef MEDIAPIPE_FLUTTER_IOS_SDK_BRIDGE_SUPPORT_H_
#define MEDIAPIPE_FLUTTER_IOS_SDK_BRIDGE_SUPPORT_H_

#import <Foundation/Foundation.h>

#include <cstdlib>
#include <cstring>
#include <new>

#include "mediapipe/tasks/c/components/containers/category.h"
#include "mediapipe/tasks/c/components/processors/classifier_options.h"
#include "mediapipe/tasks/c/core/base_options.h"
#include "mediapipe/tasks/c/core/mp_status.h"

namespace {

inline MpStatus Fail(char **message, NSString *description,
                     MpStatus status = kMpInvalidArgument) {
  if (message) *message = strdup(description.UTF8String ?: "iOS SDK error");
  return status;
}

// The public SDK error codes follow absl::StatusCode, like the C API.
inline MpStatus SdkError(char **message, NSError *error) {
  const NSInteger code = error.code;
  return Fail(message, error.localizedDescription ?: @"MediaPipe iOS SDK failed",
              code > 0 && code <= 16 ? static_cast<MpStatus>(code) : kMpInternal);
}

template <typename T> T *Allocate(size_t count) {
  if (!count) return nullptr;
  T *result = static_cast<T *>(calloc(count, sizeof(T)));
  if (!result) throw std::bad_alloc();
  return result;
}

inline char *CopyString(NSString *value) {
  if (!value.length) return nullptr;
  char *result = strdup(value.UTF8String);
  if (!result) throw std::bad_alloc();
  return result;
}

// Google's iOS options take a model path only: bytes go to a private file
// that the task owns and removes when it closes.
inline NSString *ModelPath(const MpBaseOptions &base, NSString **temporary,
                           char **message) {
  if (base.delegate != MP_DELEGATE_CPU) {
    Fail(message, @"Google's iOS text and audio tasks run on the CPU only");
    return nil;
  }
  if (base.model_asset_buffer && base.model_asset_buffer_count) {
    NSString *path = [NSTemporaryDirectory() stringByAppendingPathComponent:
        [NSString stringWithFormat:@"mediapipe-%@.tflite", NSUUID.UUID.UUIDString]];
    NSError *error = nil;
    NSData *data = [NSData dataWithBytes:base.model_asset_buffer
                                  length:base.model_asset_buffer_count];
    if (![data writeToFile:path options:NSDataWritingAtomic error:&error]) {
      SdkError(message, error);
      return nil;
    }
    *temporary = path;
    return path;
  }
  if (base.model_asset_path) {
    return [NSString stringWithUTF8String:base.model_asset_path];
  }
  Fail(message, @"Supply a model path or model bytes");
  return nil;
}

inline void RemoveModel(NSString *path) {
  if (path) [NSFileManager.defaultManager removeItemAtPath:path error:nil];
}

inline NSArray<NSString *> *StringList(const char *const *values, uint32_t count) {
  NSMutableArray<NSString *> *result = [NSMutableArray array];
  for (uint32_t i = 0; i < count; ++i) {
    [result addObject:[NSString stringWithUTF8String:values[i]]];
  }
  return result;
}

// Text Classifier, Language Detector and Audio Classifier options share
// these properties with the C classifier options.
template <typename SdkOptions>
void ApplyClassifierOptions(SdkOptions *sdk, const MpClassifierOptions &source) {
  if (source.display_names_locale) {
    sdk.displayNamesLocale = [NSString stringWithUTF8String:source.display_names_locale];
  }
  sdk.maxResults = source.max_results;
  sdk.scoreThreshold = source.score_threshold;
  sdk.categoryAllowlist = StringList(source.category_allowlist, source.category_allowlist_count);
  sdk.categoryDenylist = StringList(source.category_denylist, source.category_denylist_count);
}

// The SDK base options for a CPU task, or nil with [message] set.
template <typename SdkOptions>
MpStatus ConfigureBase(SdkOptions *sdk, const MpBaseOptions &base, NSString **temporary,
                       char **message) {
  NSString *path = ModelPath(base, temporary, message);
  if (!path) return kMpInvalidArgument;
  sdk.baseOptions.modelAssetPath = path;
  sdk.baseOptions.delegate = MPPDelegateCPU;
  return kMpOk;
}

// Creates the SDK task and hands ownership of it and its model copy to C.
template <typename Handle, typename Task, typename SdkOptions>
MpStatus OwnTask(SdkOptions *sdk, NSString *temporary, Handle **out, char **message) {
  NSError *error = nil;
  Task *task = [[Task alloc] initWithOptions:sdk error:&error];
  if (!task) {
    RemoveModel(temporary);
    return SdkError(message, error);
  }
  auto *handle = new (std::nothrow) Handle{task, temporary};
  if (!handle) {
    RemoveModel(temporary);
    return Fail(message, @"Cannot allocate task", kMpResourceExhausted);
  }
  *out = handle;
  return kMpOk;
}

template <typename Handle> MpStatus CloseHandle(Handle *task) {
  @autoreleasepool {
    if (!task) return kMpOk;
    task->task = nil;
    RemoveModel(task->temporaryModel);
    delete task;
    return kMpOk;
  }
}

}  // namespace

#endif  // MEDIAPIPE_FLUTTER_IOS_SDK_BRIDGE_SUPPORT_H_
