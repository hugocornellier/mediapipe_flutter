// Copyright 2026 The MediaPipe Authors. Licensed under Apache-2.0.
// Adapt the existing Dart C ABI to Google's prebuilt Objective-C Tasks SDK.
// This file contains no inference, tracking, or model postprocessing code.
#import <MediaPipeTasksVision/MediaPipeTasksVision.h>
#import <UIKit/UIKit.h>

#include <cstring>
#include <new>

#include "mediapipe/tasks/c/vision/face_detector/face_detector.h"
#include "mediapipe/tasks/c/vision/face_landmarker/face_landmarker.h"
#include "mediapipe/tasks/c/vision/core/image_processing_options.h"
#include "mediapipe/tasks/c/components/containers/category.h"
#include "mediapipe/tasks/c/components/containers/keypoint.h"

struct MpImageInternal {
  CVPixelBufferRef pixels;
};

struct MpFaceLandmarkerInternal {
  __strong MPPFaceLandmarker *task;
  __strong NSString *temporaryModel;
};

struct MpFaceDetectorInternal {
  __strong MPPFaceDetector *task;
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
    Fail(message, @"Face tasks do not support a region of interest");
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
                       MpImagePtr *out, char **message) {
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
  CVReturn status = CVPixelBufferCreate(kCFAllocatorDefault, width, height,
      kCVPixelFormatType_32BGRA, (__bridge CFDictionaryRef)attributes, &pixels);
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

void CopyLandmarker(MPPFaceLandmarkerResult *source, MpFaceLandmarkerResult *out) {
  out->face_landmarks = Allocate<MpNormalizedLandmarks>(source.faceLandmarks.count);
  out->face_landmarks_count = static_cast<uint32_t>(source.faceLandmarks.count);
  for (NSUInteger i = 0; i < source.faceLandmarks.count; ++i) {
    NSArray<MPPNormalizedLandmark *> *face = source.faceLandmarks[i];
    auto &target = out->face_landmarks[i];
    target.landmarks = Allocate<MpNormalizedLandmark>(face.count);
    target.landmarks_count = static_cast<uint32_t>(face.count);
    for (NSUInteger j = 0; j < face.count; ++j) {
      MPPNormalizedLandmark *landmark = face[j];
      target.landmarks[j].x = landmark.x;
      target.landmarks[j].y = landmark.y;
      target.landmarks[j].z = landmark.z;
      target.landmarks[j].has_visibility = landmark.visibility != nil;
      target.landmarks[j].visibility = landmark.visibility.floatValue;
      target.landmarks[j].has_presence = landmark.presence != nil;
      target.landmarks[j].presence = landmark.presence.floatValue;
    }
  }
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
}  // namespace

extern "C" {
MP_EXPORT int MpIosSdkVersion() { return 10001; }
MP_EXPORT void MpErrorFree(char *message) { free(message); }

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
    if (options->running_mode != MP_RUNNING_MODE_IMAGE && options->running_mode != MP_RUNNING_MODE_VIDEO) {
      return Fail(message, @"The Dart adapter supports IMAGE and VIDEO only", kMpUnimplemented);
    }
    NSString *temporary = nil;
    NSString *path = ModelPath(options->base_options, &temporary, message);
    if (!path) return kMpInvalidArgument;
    MPPFaceLandmarkerOptions *sdk = [MPPFaceLandmarkerOptions new];
    sdk.baseOptions.modelAssetPath = path;
    sdk.baseOptions.delegate = options->base_options.delegate == MP_DELEGATE_GPU ? MPPDelegateGPU : MPPDelegateCPU;
    sdk.runningMode = options->running_mode == MP_RUNNING_MODE_VIDEO ? MPPRunningModeVideo : MPPRunningModeImage;
    sdk.numFaces = options->num_faces;
    sdk.minFaceDetectionConfidence = options->min_face_detection_confidence;
    sdk.minFacePresenceConfidence = options->min_face_presence_confidence;
    sdk.minTrackingConfidence = options->min_tracking_confidence;
    sdk.outputFaceBlendshapes = options->output_face_blendshapes;
    sdk.outputFacialTransformationMatrixes = options->output_facial_transformation_matrixes;
    NSError *error = nil;
    MPPFaceLandmarker *task = [[MPPFaceLandmarker alloc] initWithOptions:sdk error:&error];
    if (!task) { RemoveModel(temporary); return SdkError(message, error); }
    auto *handle = new (std::nothrow) MpFaceLandmarkerInternal{task, temporary};
    if (!handle) { RemoveModel(temporary); return Fail(message, @"Cannot allocate task", kMpResourceExhausted); }
    *out = handle;
    return kMpOk;
  }
}

void MpFaceLandmarkerCloseResult(MpFaceLandmarkerResult *result) {
  if (!result) return;
  for (uint32_t i = 0; i < result->face_landmarks_count; ++i) {
    for (uint32_t j = 0; j < result->face_landmarks[i].landmarks_count; ++j) free(result->face_landmarks[i].landmarks[j].name);
    free(result->face_landmarks[i].landmarks);
  }
  for (uint32_t i = 0; i < result->face_blendshapes_count; ++i) FreeCategories(result->face_blendshapes[i]);
  for (uint32_t i = 0; i < result->facial_transformation_matrixes_count; ++i) free(result->facial_transformation_matrixes[i].data);
  free(result->face_landmarks);
  free(result->face_blendshapes);
  free(result->facial_transformation_matrixes);
  *result = {};
}

static MpStatus DetectLandmarker(MpFaceLandmarkerPtr task, MpImagePtr image,
    const MpImageProcessingOptions *options, bool video, int64_t timestamp,
    MpFaceLandmarkerResult *out, char **message) {
  @autoreleasepool {
    if (!task || !out) return Fail(message, @"Supply a task and result");
    *out = {};
    MPPImage *input = SdkImage(image, options, message);
    if (!input) return kMpInvalidArgument;
    NSError *error = nil;
    MPPFaceLandmarkerResult *result = video
        ? [task->task detectVideoFrame:input timestampInMilliseconds:timestamp error:&error]
        : [task->task detectImage:input error:&error];
    if (!result) return SdkError(message, error);
    try { CopyLandmarker(result, out); }
    catch (const std::bad_alloc &) {
      MpFaceLandmarkerCloseResult(out);
      return Fail(message, @"Cannot copy task result", kMpResourceExhausted);
    }
    return kMpOk;
  }
}

MpStatus MpFaceLandmarkerDetectImage(MpFaceLandmarkerPtr task, MpImagePtr image,
    const MpImageProcessingOptions *options, MpFaceLandmarkerResult *out, char **message) {
  return DetectLandmarker(task, image, options, false, 0, out, message);
}
MpStatus MpFaceLandmarkerDetectForVideo(MpFaceLandmarkerPtr task, MpImagePtr image,
    const MpImageProcessingOptions *options, int64_t timestamp, MpFaceLandmarkerResult *out, char **message) {
  return DetectLandmarker(task, image, options, true, timestamp, out, message);
}
MpStatus MpFaceLandmarkerClose(MpFaceLandmarkerPtr task, char **message) {
  @autoreleasepool {
    if (!task) return kMpOk;
    task->task = nil;
    RemoveModel(task->temporaryModel);
    delete task;
    return kMpOk;
  }
}

MpStatus MpFaceDetectorCreate(MpFaceDetectorOptions *options, MpFaceDetectorPtr *out, char **message) {
  @autoreleasepool {
    if (!options || !out) return Fail(message, @"Supply options and output");
    *out = nullptr;
    if (options->running_mode != MP_RUNNING_MODE_IMAGE && options->running_mode != MP_RUNNING_MODE_VIDEO) {
      return Fail(message, @"The Dart adapter supports IMAGE and VIDEO only", kMpUnimplemented);
    }
    NSString *temporary = nil;
    NSString *path = ModelPath(options->base_options, &temporary, message);
    if (!path) return kMpInvalidArgument;
    MPPFaceDetectorOptions *sdk = [MPPFaceDetectorOptions new];
    sdk.baseOptions.modelAssetPath = path;
    sdk.baseOptions.delegate = options->base_options.delegate == MP_DELEGATE_GPU ? MPPDelegateGPU : MPPDelegateCPU;
    sdk.runningMode = options->running_mode == MP_RUNNING_MODE_VIDEO ? MPPRunningModeVideo : MPPRunningModeImage;
    sdk.minDetectionConfidence = options->min_detection_confidence;
    sdk.minSuppressionThreshold = options->min_suppression_threshold;
    NSError *error = nil;
    MPPFaceDetector *task = [[MPPFaceDetector alloc] initWithOptions:sdk error:&error];
    if (!task) { RemoveModel(temporary); return SdkError(message, error); }
    auto *handle = new (std::nothrow) MpFaceDetectorInternal{task, temporary};
    if (!handle) { RemoveModel(temporary); return Fail(message, @"Cannot allocate task", kMpResourceExhausted); }
    *out = handle;
    return kMpOk;
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

static MpStatus DetectDetector(MpFaceDetectorPtr task, MpImagePtr image,
    const MpImageProcessingOptions *options, bool video, int64_t timestamp,
    MpFaceDetectorResult *out, char **message) {
  @autoreleasepool {
    if (!task || !out) return Fail(message, @"Supply a task and result");
    *out = {};
    MPPImage *input = SdkImage(image, options, message);
    if (!input) return kMpInvalidArgument;
    NSError *error = nil;
    MPPFaceDetectorResult *result = video
        ? [task->task detectVideoFrame:input timestampInMilliseconds:timestamp error:&error]
        : [task->task detectImage:input error:&error];
    if (!result) return SdkError(message, error);
    try { CopyDetector(result, out); }
    catch (const std::bad_alloc &) {
      MpFaceDetectorCloseResult(out);
      return Fail(message, @"Cannot copy task result", kMpResourceExhausted);
    }
    return kMpOk;
  }
}
MpStatus MpFaceDetectorDetectImage(MpFaceDetectorPtr task, MpImagePtr image,
    const MpImageProcessingOptions *options, MpFaceDetectorResult *out, char **message) {
  return DetectDetector(task, image, options, false, 0, out, message);
}
MpStatus MpFaceDetectorDetectForVideo(MpFaceDetectorPtr task, MpImagePtr image,
    const MpImageProcessingOptions *options, int64_t timestamp, MpFaceDetectorResult *out, char **message) {
  return DetectDetector(task, image, options, true, timestamp, out, message);
}
MpStatus MpFaceDetectorClose(MpFaceDetectorPtr task, char **message) {
  @autoreleasepool {
    if (!task) return kMpOk;
    task->task = nil;
    RemoveModel(task->temporaryModel);
    delete task;
    return kMpOk;
  }
}
}  // extern C
