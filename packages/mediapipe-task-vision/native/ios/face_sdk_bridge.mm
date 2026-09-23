// Copyright 2026 The MediaPipe Authors. Licensed under Apache-2.0.
// Adapt the existing Dart C ABI to Google's prebuilt Objective-C Tasks SDK for
// Face Detector, Face Landmarker and Hand Landmarker. This file contains no
// inference, tracking, or model postprocessing code.
#import <MediaPipeTasksVision/MediaPipeTasksVision.h>
#import <UIKit/UIKit.h>

#include <cstring>
#include <new>

#include "mediapipe/tasks/c/vision/face_detector/face_detector.h"
#include "mediapipe/tasks/c/vision/face_landmarker/face_landmarker.h"
#include "mediapipe/tasks/c/vision/hand_landmarker/hand_landmarker.h"
#include "mediapipe/tasks/c/vision/core/image_processing_options.h"
#include "mediapipe/tasks/c/components/containers/category.h"
#include "mediapipe/tasks/c/components/containers/keypoint.h"

struct MpImageInternal {
  CVPixelBufferRef pixels;
};

// One pool per task owner, never a shared mutable frame or a global cache.
struct MpIosPixelBufferPoolInternal {
  CVPixelBufferPoolRef pool = nullptr;
  int width = 0;
  int height = 0;
};

struct MpFaceLandmarkerInternal {
  __strong MPPFaceLandmarker *task;
  __strong NSString *temporaryModel;
};

struct MpFaceDetectorInternal {
  __strong MPPFaceDetector *task;
  __strong NSString *temporaryModel;
};

struct MpHandLandmarkerInternal {
  __strong MPPHandLandmarker *task;
  __strong NSString *temporaryModel;
};

namespace {
MpStatus Fail(char **message, NSString *description,
              MpStatus status = kMpInvalidArgument) {
  if (message) *message = strdup(description.UTF8String ?: "iOS SDK error");
  return status;
}

MpStatus SdkError(char **message, NSError *error) {
  // The public SDK error codes follow absl::StatusCode, like the C API.
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

char *CopyString(NSString *value) {
  if (!value.length) return nullptr;
  char *result = strdup(value.UTF8String);
  if (!result) throw std::bad_alloc();
  return result;
}

NSString *ModelPath(const MpBaseOptions &base, NSString **temporary,
                    char **message) {
  if (base.delegate != MP_DELEGATE_CPU && base.delegate != MP_DELEGATE_GPU) {
    Fail(message, @"The iOS SDK supports CPU and GPU delegates only");
    return nil;
  }
  if (base.model_asset_buffer && base.model_asset_buffer_count) {
    NSString *path = [NSTemporaryDirectory() stringByAppendingPathComponent:
        [NSString stringWithFormat:@"mediapipe-%@.task", NSUUID.UUID.UUIDString]];
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

void RemoveModel(NSString *path) {
  if (path) [NSFileManager.defaultManager removeItemAtPath:path error:nil];
}

MPPImage *SdkImage(MpImagePtr image, const MpImageProcessingOptions *options,
                   char **message) {
  if (!image) {
    Fail(message, @"Image must not be null");
    return nil;
  }
  if (options && options->has_region_of_interest) {
    Fail(message, @"These tasks do not support a region of interest");
    return nil;
  }
  int rotation = options ? options->rotation_degrees : 0;
  if (rotation % 90) {
    Fail(message, @"Rotation must be a multiple of 90 degrees");
    return nil;
  }
  rotation = (rotation % 360 + 360) % 360;
  // iOS's task runner uses the original pixels plus a rotated normalized
  // rectangle. Its orientation enum describes how to display those pixels.
  // UIImageOrientationRight maps to 3*pi/2, like C's -pi/2 for rotation 90.
  UIImageOrientation orientation = UIImageOrientationUp;
  if (rotation == 90) orientation = UIImageOrientationRight;
  if (rotation == 180) orientation = UIImageOrientationDown;
  if (rotation == 270) orientation = UIImageOrientationLeft;
  NSError *error = nil;
  MPPImage *result = [[MPPImage alloc] initWithPixelBuffer:image->pixels
                                            orientation:orientation error:&error];
  if (!result) SdkError(message, error);
  return result;
}

MpStatus CreatePixels(int width, int height, int stride, const uint8_t *data,
                       size_t length, int channels, bool bgra,
                       MpImagePtr *out, char **message,
                       MpIosPixelBufferPoolInternal *storage = nullptr) {
  if (!out || !data || width <= 0 || height <= 0 ||
      width > INT_MAX / channels || stride < width * channels ||
      length < static_cast<size_t>(stride) * (height - 1) + width * channels) {
    return Fail(message, @"Invalid pixel dimensions, stride, or buffer length");
  }
  *out = nullptr;
  CVPixelBufferRef pixels = nullptr;
  NSDictionary *attributes = @{
    (id)kCVPixelBufferIOSurfacePropertiesKey: @{},
    (id)kCVPixelBufferMetalCompatibilityKey: @YES,
  };
  CVReturn status;
  if (storage) {
    if (!storage->pool || storage->width != width || storage->height != height) {
      NSMutableDictionary *poolAttributes = [attributes mutableCopy];
      poolAttributes[(id)kCVPixelBufferWidthKey] = @(width);
      poolAttributes[(id)kCVPixelBufferHeightKey] = @(height);
      poolAttributes[(id)kCVPixelBufferPixelFormatTypeKey] = @(kCVPixelFormatType_32BGRA);
      CVPixelBufferPoolRef pool = nullptr;
      status = CVPixelBufferPoolCreate(kCFAllocatorDefault, nullptr,
          (__bridge CFDictionaryRef)poolAttributes, &pool);
      if (status != kCVReturnSuccess) {
        return Fail(message, @"Could not allocate an iOS pixel-buffer pool", kMpResourceExhausted);
      }
      if (storage->pool) CVPixelBufferPoolRelease(storage->pool);
      storage->pool = pool;
      storage->width = width;
      storage->height = height;
    }
    // Core Video reuses only buffers whose clients have released them. A task
    // retaining an earlier frame cannot observe a subsequent frame overwrite.
    status = CVPixelBufferPoolCreatePixelBuffer(kCFAllocatorDefault, storage->pool, &pixels);
  } else {
    status = CVPixelBufferCreate(kCFAllocatorDefault, width, height,
        kCVPixelFormatType_32BGRA, (__bridge CFDictionaryRef)attributes, &pixels);
  }
  if (status != kCVReturnSuccess) {
    return Fail(message, @"Could not allocate an iOS pixel buffer", kMpResourceExhausted);
  }
  status = CVPixelBufferLockBaseAddress(pixels, 0);
  if (status != kCVReturnSuccess) {
    CVPixelBufferRelease(pixels);
    return Fail(message, @"Could not lock an iOS pixel buffer", kMpInternal);
  }
  auto *destination = static_cast<uint8_t *>(CVPixelBufferGetBaseAddress(pixels));
  const size_t targetStride = CVPixelBufferGetBytesPerRow(pixels);
  for (int y = 0; y < height; ++y) {
    const uint8_t *source = data + static_cast<size_t>(y) * stride;
    uint8_t *target = destination + static_cast<size_t>(y) * targetStride;
    if (bgra) {
      memcpy(target, source, static_cast<size_t>(width) * 4);
    } else {
      for (int x = 0; x < width; ++x) {
        target[x * 4] = source[x * channels + 2];
        target[x * 4 + 1] = source[x * channels + 1];
        target[x * 4 + 2] = source[x * channels];
        target[x * 4 + 3] = channels == 4 ? source[x * channels + 3] : 255;
      }
    }
  }
  CVPixelBufferUnlockBaseAddress(pixels, 0);
  auto *image = new (std::nothrow) MpImageInternal{pixels};
  if (!image) {
    CVPixelBufferRelease(pixels);
    return Fail(message, @"Could not allocate an image handle", kMpResourceExhausted);
  }
  *out = image;
  return kMpOk;
}

void CopyCategories(NSArray<MPPCategory *> *source, MpCategories *out) {
  out->categories = Allocate<MpCategory>(source.count);
  out->categories_count = static_cast<uint32_t>(source.count);
  for (NSUInteger i = 0; i < source.count; ++i) {
    MPPCategory *category = source[i];
    out->categories[i].index = static_cast<int>(category.index);
    out->categories[i].score = category.score;
    out->categories[i].category_name = CopyString(category.categoryName);
    out->categories[i].display_name = CopyString(category.displayName);
  }
}

void FreeCategories(MpCategories &value) {
  for (uint32_t i = 0; i < value.categories_count; ++i) {
    free(value.categories[i].category_name);
    free(value.categories[i].display_name);
  }
  free(value.categories);
}

// Copies one landmark list per subject, normalized or world, into C storage.
template <typename SdkPoint, typename Point, typename List>
void CopyLandmarkLists(NSArray<NSArray<SdkPoint *> *> *source, List **out,
                       uint32_t *count) {
  *out = Allocate<List>(source.count);
  *count = static_cast<uint32_t>(source.count);
  for (NSUInteger i = 0; i < source.count; ++i) {
    NSArray<SdkPoint *> *points = source[i];
    auto &target = (*out)[i];
    target.landmarks = Allocate<Point>(points.count);
    target.landmarks_count = static_cast<uint32_t>(points.count);
    for (NSUInteger j = 0; j < points.count; ++j) {
      SdkPoint *landmark = points[j];
      target.landmarks[j].x = landmark.x;
      target.landmarks[j].y = landmark.y;
      target.landmarks[j].z = landmark.z;
      target.landmarks[j].has_visibility = landmark.visibility != nil;
      target.landmarks[j].visibility = landmark.visibility.floatValue;
      target.landmarks[j].has_presence = landmark.presence != nil;
      target.landmarks[j].presence = landmark.presence.floatValue;
    }
  }
}

template <typename List> void FreeLandmarkLists(List *lists, uint32_t count) {
  for (uint32_t i = 0; i < count; ++i) {
    for (uint32_t j = 0; j < lists[i].landmarks_count; ++j) free(lists[i].landmarks[j].name);
    free(lists[i].landmarks);
  }
  free(lists);
}

void CopyLandmarker(MPPFaceLandmarkerResult *source, MpFaceLandmarkerResult *out) {
  CopyLandmarkLists<MPPNormalizedLandmark, MpNormalizedLandmark>(
      source.faceLandmarks, &out->face_landmarks, &out->face_landmarks_count);
  out->face_blendshapes = Allocate<MpCategories>(source.faceBlendshapes.count);
  out->face_blendshapes_count = static_cast<uint32_t>(source.faceBlendshapes.count);
  for (NSUInteger i = 0; i < source.faceBlendshapes.count; ++i) {
    CopyCategories(source.faceBlendshapes[i].categories, &out->face_blendshapes[i]);
  }
  out->facial_transformation_matrixes = Allocate<MpMatrix>(source.facialTransformationMatrixes.count);
  out->facial_transformation_matrixes_count = static_cast<uint32_t>(source.facialTransformationMatrixes.count);
  for (NSUInteger i = 0; i < source.facialTransformationMatrixes.count; ++i) {
    MPPTransformMatrix *matrix = source.facialTransformationMatrixes[i];
    auto &target = out->facial_transformation_matrixes[i];
    target.rows = static_cast<uint32_t>(matrix.rows);
    target.cols = static_cast<uint32_t>(matrix.columns);
    target.data = Allocate<float>(matrix.rows * matrix.columns);
    for (NSUInteger row = 0; row < matrix.rows; ++row) {
      for (NSUInteger column = 0; column < matrix.columns; ++column) {
        target.data[column * matrix.rows + row] = [matrix valueAtRow:row column:column];
      }
    }
  }
}

void CopyHandLandmarker(MPPHandLandmarkerResult *source, MpHandLandmarkerResult *out) {
  out->handedness = Allocate<MpCategories>(source.handedness.count);
  out->handedness_count = static_cast<uint32_t>(source.handedness.count);
  for (NSUInteger i = 0; i < source.handedness.count; ++i) {
    CopyCategories(source.handedness[i], &out->handedness[i]);
  }
  CopyLandmarkLists<MPPNormalizedLandmark, MpNormalizedLandmark>(
      source.landmarks, &out->hand_landmarks, &out->hand_landmarks_count);
  CopyLandmarkLists<MPPLandmark, MpLandmark>(
      source.worldLandmarks, &out->hand_world_landmarks, &out->hand_world_landmarks_count);
}

void CopyDetector(MPPFaceDetectorResult *source, MpFaceDetectorResult *out) {
  out->detections = Allocate<MpDetection>(source.detections.count);
  out->detections_count = static_cast<uint32_t>(source.detections.count);
  for (NSUInteger i = 0; i < source.detections.count; ++i) {
    MPPDetection *detection = source.detections[i];
    auto &target = out->detections[i];
    MpCategories categories{};
    // Attach before copying strings so cleanup also owns a partial result.
    target.categories = Allocate<MpCategory>(detection.categories.count);
    target.categories_count = static_cast<uint32_t>(detection.categories.count);
    categories.categories = target.categories;
    categories.categories_count = target.categories_count;
    for (NSUInteger j = 0; j < detection.categories.count; ++j) {
      MPPCategory *category = detection.categories[j];
      categories.categories[j].index = static_cast<int>(category.index);
      categories.categories[j].score = category.score;
      categories.categories[j].category_name = CopyString(category.categoryName);
      categories.categories[j].display_name = CopyString(category.displayName);
    }
    const CGRect box = detection.boundingBox;
    target.bounding_box.left = static_cast<int>(CGRectGetMinX(box));
    target.bounding_box.top = static_cast<int>(CGRectGetMinY(box));
    target.bounding_box.right = static_cast<int>(CGRectGetMaxX(box));
    target.bounding_box.bottom = static_cast<int>(CGRectGetMaxY(box));
    target.keypoints = Allocate<MpNormalizedKeypoint>(detection.keypoints.count);
    target.keypoints_count = static_cast<uint32_t>(detection.keypoints.count);
    for (NSUInteger j = 0; j < detection.keypoints.count; ++j) {
      MPPNormalizedKeypoint *keypoint = detection.keypoints[j];
      target.keypoints[j].x = keypoint.location.x;
      target.keypoints[j].y = keypoint.location.y;
      target.keypoints[j].label = CopyString(keypoint.label);
      // The Objective-C API represents an absent keypoint score as zero.
      target.keypoints[j].has_score = keypoint.score != 0;
      target.keypoints[j].score = keypoint.score;
    }
  }
}
// Applies the model, delegate and running mode every task shares.
template <typename SdkOptions>
MpStatus Configure(SdkOptions *sdk, const MpBaseOptions &base, MpRunningMode mode,
                   NSString **temporary, char **message) {
  if (mode != MP_RUNNING_MODE_IMAGE && mode != MP_RUNNING_MODE_VIDEO) {
    return Fail(message, @"The Dart adapter supports IMAGE and VIDEO only", kMpUnimplemented);
  }
  NSString *path = ModelPath(base, temporary, message);
  if (!path) return kMpInvalidArgument;
  sdk.baseOptions.modelAssetPath = path;
  sdk.baseOptions.delegate = base.delegate == MP_DELEGATE_GPU ? MPPDelegateGPU : MPPDelegateCPU;
  sdk.runningMode = mode == MP_RUNNING_MODE_VIDEO ? MPPRunningModeVideo : MPPRunningModeImage;
  return kMpOk;
}

// Creates the SDK task and hands ownership of it and its model copy to C.
template <typename Handle, typename Task, typename SdkOptions>
MpStatus Own(SdkOptions *sdk, NSString *temporary, Handle **out, char **message) {
  NSError *error = nil;
  Task *task = [[Task alloc] initWithOptions:sdk error:&error];
  if (!task) { RemoveModel(temporary); return SdkError(message, error); }
  auto *handle = new (std::nothrow) Handle{task, temporary};
  if (!handle) { RemoveModel(temporary); return Fail(message, @"Cannot allocate task", kMpResourceExhausted); }
  *out = handle;
  return kMpOk;
}

// Runs one IMAGE or VIDEO request and copies the SDK result into C storage.
template <typename SdkResult, typename Handle, typename Result>
MpStatus Detect(Handle *task, MpImagePtr image, const MpImageProcessingOptions *options,
                bool video, int64_t timestamp, Result *out, char **message,
                void (*copy)(SdkResult *, Result *), void (*close)(Result *)) {
  @autoreleasepool {
    if (!task || !out) return Fail(message, @"Supply a task and result");
    *out = {};
    MPPImage *input = SdkImage(image, options, message);
    if (!input) return kMpInvalidArgument;
    NSError *error = nil;
    SdkResult *result = video
        ? [task->task detectVideoFrame:input timestampInMilliseconds:timestamp error:&error]
        : [task->task detectImage:input error:&error];
    if (!result) return SdkError(message, error);
    try { copy(result, out); }
    catch (const std::bad_alloc &) {
      close(out);
      return Fail(message, @"Cannot copy task result", kMpResourceExhausted);
    }
    return kMpOk;
  }
}

template <typename Handle> MpStatus CloseTask(Handle *task) {
  @autoreleasepool {
    if (!task) return kMpOk;
    task->task = nil;
    RemoveModel(task->temporaryModel);
    delete task;
    return kMpOk;
  }
}
}  // namespace

extern "C" {
MP_EXPORT int MpIosSdkVersion() { return 10001; }
MP_EXPORT void MpErrorFree(char *message) { free(message); }

MP_EXPORT MpIosPixelBufferPoolInternal *MpIosPixelBufferPoolCreate() {
  return new (std::nothrow) MpIosPixelBufferPoolInternal;
}

MP_EXPORT void MpIosPixelBufferPoolFree(MpIosPixelBufferPoolInternal *storage) {
  if (!storage) return;
  if (storage->pool) CVPixelBufferPoolRelease(storage->pool);
  delete storage;
}

MP_EXPORT MpStatus MpIosImageCreateFromBgraDataWithPool(
    MpIosPixelBufferPoolInternal *storage, int width, int height, int stride,
    const uint8_t *data, size_t length, MpImagePtr *out, char **message) {
  @autoreleasepool {
    if (!storage) return Fail(message, @"Pixel-buffer pool must not be null");
    return CreatePixels(width, height, stride, data, length, 4, true, out, message, storage);
  }
}

MP_EXPORT MpStatus MpIosImageCreateFromBgraData(
    int width, int height, int stride, const uint8_t *data, size_t length,
    MpImagePtr *out, char **message) {
  @autoreleasepool {
    return CreatePixels(width, height, stride, data, length, 4, true, out, message);
  }
}

MpStatus MpImageCreateFromUint8Data(MpImageFormat format, int width, int height,
    const uint8_t *data, int length, MpImagePtr *out, char **message) {
  @autoreleasepool {
    const int channels = format == kMpImageFormatSrgb ? 3 : 4;
    if ((format != kMpImageFormatSrgb && format != kMpImageFormatSrgba) ||
        length < 0 || width > INT_MAX / channels) {
      return Fail(message, @"Only RGB and RGBA images are supported");
    }
    return CreatePixels(width, height, width * channels, data, length,
                        channels, false, out, message);
  }
}

MpStatus MpImageCreateFromFile(const char *filename, MpImagePtr *out, char **message) {
  @autoreleasepool {
    if (!filename || !out) return Fail(message, @"Supply an image path and output");
    *out = nullptr;
    UIImage *image = [UIImage imageWithContentsOfFile:[NSString stringWithUTF8String:filename]];
    CGImageRef cgImage = image.CGImage;
    if (!cgImage) return Fail(message, @"Cannot decode image file", kMpNotFound);
    size_t width = CGImageGetWidth(cgImage), height = CGImageGetHeight(cgImage);
    if (width > INT_MAX / 4 || height > INT_MAX) return Fail(message, @"Image too large");
    CVPixelBufferRef pixels = nullptr;
    NSDictionary *attributes = @{(id)kCVPixelBufferIOSurfacePropertiesKey: @{},
                                 (id)kCVPixelBufferMetalCompatibilityKey: @YES};
    if (CVPixelBufferCreate(kCFAllocatorDefault, width, height, kCVPixelFormatType_32BGRA,
        (__bridge CFDictionaryRef)attributes, &pixels) != kCVReturnSuccess) {
      return Fail(message, @"Cannot allocate image", kMpResourceExhausted);
    }
    if (CVPixelBufferLockBaseAddress(pixels, 0) != kCVReturnSuccess) {
      CVPixelBufferRelease(pixels);
      return Fail(message, @"Cannot lock image", kMpInternal);
    }
    CGColorSpaceRef color = CGColorSpaceCreateDeviceRGB();
    CGContextRef context = CGBitmapContextCreate(CVPixelBufferGetBaseAddress(pixels),
        width, height, 8, CVPixelBufferGetBytesPerRow(pixels), color,
        kCGBitmapByteOrder32Little | kCGImageAlphaPremultipliedFirst);
    CGColorSpaceRelease(color);
    if (!context) {
      CVPixelBufferUnlockBaseAddress(pixels, 0);
      CVPixelBufferRelease(pixels);
      return Fail(message, @"Cannot decode image pixels", kMpInternal);
    }
    CGContextDrawImage(context, CGRectMake(0, 0, width, height), cgImage);
    CGContextRelease(context);
    CVPixelBufferUnlockBaseAddress(pixels, 0);
    auto *handle = new (std::nothrow) MpImageInternal{pixels};
    if (!handle) {
      CVPixelBufferRelease(pixels);
      return Fail(message, @"Cannot allocate image handle", kMpResourceExhausted);
    }
    *out = handle;
    return kMpOk;
  }
}

void MpImageFree(MpImagePtr image) {
  if (image) { CVPixelBufferRelease(image->pixels); delete image; }
}
int MpImageGetWidth(MpImagePtr image) { return image ? static_cast<int>(CVPixelBufferGetWidth(image->pixels)) : 0; }
int MpImageGetHeight(MpImagePtr image) { return image ? static_cast<int>(CVPixelBufferGetHeight(image->pixels)) : 0; }

MpStatus MpFaceLandmarkerCreate(MpFaceLandmarkerOptions *options,
    MpFaceLandmarkerPtr *out, char **message) {
  @autoreleasepool {
    if (!options || !out) return Fail(message, @"Supply options and output");
    *out = nullptr;
    NSString *temporary = nil;
    MPPFaceLandmarkerOptions *sdk = [MPPFaceLandmarkerOptions new];
    MpStatus status = Configure(sdk, options->base_options, options->running_mode, &temporary, message);
    if (status != kMpOk) return status;
    sdk.numFaces = options->num_faces;
    sdk.minFaceDetectionConfidence = options->min_face_detection_confidence;
    sdk.minFacePresenceConfidence = options->min_face_presence_confidence;
    sdk.minTrackingConfidence = options->min_tracking_confidence;
    sdk.outputFaceBlendshapes = options->output_face_blendshapes;
    sdk.outputFacialTransformationMatrixes = options->output_facial_transformation_matrixes;
    return Own<MpFaceLandmarkerInternal, MPPFaceLandmarker>(sdk, temporary, out, message);
  }
}

void MpFaceLandmarkerCloseResult(MpFaceLandmarkerResult *result) {
  if (!result) return;
  FreeLandmarkLists(result->face_landmarks, result->face_landmarks_count);
  for (uint32_t i = 0; i < result->face_blendshapes_count; ++i) FreeCategories(result->face_blendshapes[i]);
  for (uint32_t i = 0; i < result->facial_transformation_matrixes_count; ++i) free(result->facial_transformation_matrixes[i].data);
  free(result->face_blendshapes);
  free(result->facial_transformation_matrixes);
  *result = {};
}

MpStatus MpFaceLandmarkerDetectImage(MpFaceLandmarkerPtr task, MpImagePtr image,
    const MpImageProcessingOptions *options, MpFaceLandmarkerResult *out, char **message) {
  return Detect<MPPFaceLandmarkerResult>(task, image, options, false, 0, out, message,
                                         CopyLandmarker, MpFaceLandmarkerCloseResult);
}
MpStatus MpFaceLandmarkerDetectForVideo(MpFaceLandmarkerPtr task, MpImagePtr image,
    const MpImageProcessingOptions *options, int64_t timestamp, MpFaceLandmarkerResult *out, char **message) {
  return Detect<MPPFaceLandmarkerResult>(task, image, options, true, timestamp, out, message,
                                         CopyLandmarker, MpFaceLandmarkerCloseResult);
}
MpStatus MpFaceLandmarkerClose(MpFaceLandmarkerPtr task, char **message) {
  return CloseTask(task);
}

MpStatus MpFaceDetectorCreate(MpFaceDetectorOptions *options, MpFaceDetectorPtr *out, char **message) {
  @autoreleasepool {
    if (!options || !out) return Fail(message, @"Supply options and output");
    *out = nullptr;
    NSString *temporary = nil;
    MPPFaceDetectorOptions *sdk = [MPPFaceDetectorOptions new];
    MpStatus status = Configure(sdk, options->base_options, options->running_mode, &temporary, message);
    if (status != kMpOk) return status;
    sdk.minDetectionConfidence = options->min_detection_confidence;
    sdk.minSuppressionThreshold = options->min_suppression_threshold;
    return Own<MpFaceDetectorInternal, MPPFaceDetector>(sdk, temporary, out, message);
  }
}

void MpFaceDetectorCloseResult(MpFaceDetectorResult *result) {
  if (!result) return;
  for (uint32_t i = 0; i < result->detections_count; ++i) {
    auto &value = result->detections[i];
    MpCategories categories{value.categories, value.categories_count};
    FreeCategories(categories);
    for (uint32_t j = 0; j < value.keypoints_count; ++j) free(value.keypoints[j].label);
    free(value.keypoints);
  }
  free(result->detections);
  *result = {};
}

MpStatus MpFaceDetectorDetectImage(MpFaceDetectorPtr task, MpImagePtr image,
    const MpImageProcessingOptions *options, MpFaceDetectorResult *out, char **message) {
  return Detect<MPPFaceDetectorResult>(task, image, options, false, 0, out, message,
                                       CopyDetector, MpFaceDetectorCloseResult);
}
MpStatus MpFaceDetectorDetectForVideo(MpFaceDetectorPtr task, MpImagePtr image,
    const MpImageProcessingOptions *options, int64_t timestamp, MpFaceDetectorResult *out, char **message) {
  return Detect<MPPFaceDetectorResult>(task, image, options, true, timestamp, out, message,
                                       CopyDetector, MpFaceDetectorCloseResult);
}
MpStatus MpFaceDetectorClose(MpFaceDetectorPtr task, char **message) {
  return CloseTask(task);
}

MpStatus MpHandLandmarkerCreate(MpHandLandmarkerOptions *options,
    MpHandLandmarkerPtr *out, char **message) {
  @autoreleasepool {
    if (!options || !out) return Fail(message, @"Supply options and output");
    *out = nullptr;
    NSString *temporary = nil;
    MPPHandLandmarkerOptions *sdk = [MPPHandLandmarkerOptions new];
    MpStatus status = Configure(sdk, options->base_options, options->running_mode, &temporary, message);
    if (status != kMpOk) return status;
    sdk.numHands = options->num_hands;
    sdk.minHandDetectionConfidence = options->min_hand_detection_confidence;
    sdk.minHandPresenceConfidence = options->min_hand_presence_confidence;
    sdk.minTrackingConfidence = options->min_tracking_confidence;
    return Own<MpHandLandmarkerInternal, MPPHandLandmarker>(sdk, temporary, out, message);
  }
}

void MpHandLandmarkerCloseResult(MpHandLandmarkerResult *result) {
  if (!result) return;
  for (uint32_t i = 0; i < result->handedness_count; ++i) FreeCategories(result->handedness[i]);
  free(result->handedness);
  FreeLandmarkLists(result->hand_landmarks, result->hand_landmarks_count);
  FreeLandmarkLists(result->hand_world_landmarks, result->hand_world_landmarks_count);
  *result = {};
}

MpStatus MpHandLandmarkerDetectImage(MpHandLandmarkerPtr task, MpImagePtr image,
    const MpImageProcessingOptions *options, MpHandLandmarkerResult *out, char **message) {
  return Detect<MPPHandLandmarkerResult>(task, image, options, false, 0, out, message,
                                         CopyHandLandmarker, MpHandLandmarkerCloseResult);
}
MpStatus MpHandLandmarkerDetectForVideo(MpHandLandmarkerPtr task, MpImagePtr image,
    const MpImageProcessingOptions *options, int64_t timestamp, MpHandLandmarkerResult *out, char **message) {
  return Detect<MPPHandLandmarkerResult>(task, image, options, true, timestamp, out, message,
                                         CopyHandLandmarker, MpHandLandmarkerCloseResult);
}
MpStatus MpHandLandmarkerClose(MpHandLandmarkerPtr task, char **message) {
  return CloseTask(task);
}
}  // extern C
