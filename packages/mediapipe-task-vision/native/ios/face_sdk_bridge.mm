// Copyright 2026 The MediaPipe Authors. Licensed under Apache-2.0.
// Adapt the existing Dart C ABI to Google's prebuilt Objective-C Tasks SDK for
// Face Detector, Face Landmarker, Hand Landmarker, Pose Landmarker, Gesture
// Recognizer, Holistic Landmarker, Object Detector, Image Classifier, Image
// Embedder, Image Segmenter and both Interactive Segmenters. This file
// contains no
// inference, tracking, or model postprocessing code.
#import <Accelerate/Accelerate.h>
#import <MediaPipeTasksVision/MediaPipeTasksVision.h>
#import <UIKit/UIKit.h>

#include <cstring>
#include <new>

#include "mediapipe/tasks/c/vision/face_detector/face_detector.h"
#include "mediapipe/tasks/c/vision/face_landmarker/face_landmarker.h"
#include "mediapipe/tasks/c/vision/gesture_recognizer/gesture_recognizer.h"
#include "mediapipe/tasks/c/vision/hand_landmarker/hand_landmarker.h"
#include "mediapipe/tasks/c/vision/holistic_landmarker/holistic_landmarker.h"
#include "mediapipe/tasks/c/vision/image_classifier/image_classifier.h"
#include "mediapipe/tasks/c/vision/image_embedder/image_embedder.h"
#include "mediapipe/tasks/c/vision/image_segmenter/image_segmenter.h"
#include "mediapipe/tasks/c/vision/interactive_segmenter_legacy/interactive_segmenter_legacy.h"
#include "mediapipe/tasks/c/vision/object_detector/object_detector.h"
#include "mediapipe/tasks/c/vision/pose_landmarker/pose_landmarker.h"
#include "mediapipe/tasks/c/vision/core/image_processing_options.h"
#include "mediapipe/tasks/c/components/containers/category.h"
#include "mediapipe/tasks/c/components/containers/keypoint.h"

// A camera or file image in a pixel buffer, or a segmentation mask: one
// channel of float32 confidences or uint8 categories, owned here.
struct MpImageInternal {
  CVPixelBufferRef pixels;
  void *mask = nullptr;
  int maskWidth = 0;
  int maskHeight = 0;
  int maskDepth = 0;
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

struct MpPoseLandmarkerInternal {
  __strong MPPPoseLandmarker *task;
  __strong NSString *temporaryModel;
  bool cpu = true;
};

struct MpGestureRecognizerInternal {
  __strong MPPGestureRecognizer *task;
  __strong NSString *temporaryModel;
};

struct MpHolisticLandmarkerInternal {
  __strong MPPHolisticLandmarker *task;
  __strong NSString *temporaryModel;
  bool cpu = true;
};

struct MpObjectDetectorInternal {
  __strong MPPObjectDetector *task;
  __strong NSString *temporaryModel;
};

struct MpImageClassifierInternal {
  __strong MPPImageClassifier *task;
  __strong NSString *temporaryModel;
};

struct MpImageEmbedderInternal {
  __strong MPPImageEmbedder *task;
  __strong NSString *temporaryModel;
};

struct MpImageSegmenterInternal {
  __strong MPPImageSegmenter *task;
  __strong NSString *temporaryModel;
};

struct MpInteractiveSegmenterLegacyInternal {
  __strong MPPInteractiveSegmenterLegacy *task;
  __strong NSString *temporaryModel;
};

// Google's stateful MagicTouch session: one image, then stroke histories.
struct MpIosInteractiveSegmenterInternal {
  __strong MPPInteractiveSegmenter *task;
  __strong NSString *temporaryModel;
  __strong MPPImage *image = nil;
};

// The stroke layout of the 1.0.1 C API that the desktop Interactive
// Segmenter binds (interactive_segmenter_bindings.dart).
struct MpIosStrokePoint {
  float x;
  float y;
};
struct MpIosStroke {
  int32_t brush_mode;
  MpIosStrokePoint *points;
  uint32_t points_count;
  bool is_completed;
};
struct MpIosStrokes {
  MpIosStroke *strokes;
  uint32_t strokes_count;
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

// Google's iOS Holistic Landmarker accepts only upright images, so the pixels
// themselves turn, in the direction the orientation above gives other tasks.
// The copy is autoreleased: it outlives the request inside Detect's pool.
MPPImage *UprightSdkImage(MpImagePtr image, const MpImageProcessingOptions *options,
                          char **message) {
  const int rotation = options ? (options->rotation_degrees % 360 + 360) % 360 : 0;
  if (!image || rotation == 0 || rotation % 90 || options->has_region_of_interest) {
    return SdkImage(image, options, message);
  }
  CVPixelBufferRef source = image->pixels;
  const size_t width = CVPixelBufferGetWidth(source);
  const size_t height = CVPixelBufferGetHeight(source);
  const bool quarter = rotation != 180;
  CVPixelBufferRef turned = nullptr;
  NSDictionary *attributes = @{(id)kCVPixelBufferIOSurfacePropertiesKey: @{},
                               (id)kCVPixelBufferMetalCompatibilityKey: @YES};
  if (CVPixelBufferCreate(kCFAllocatorDefault, quarter ? height : width,
          quarter ? width : height, kCVPixelFormatType_32BGRA,
          (__bridge CFDictionaryRef)attributes, &turned) != kCVReturnSuccess) {
    Fail(message, @"Cannot allocate a rotated image", kMpResourceExhausted);
    return nil;
  }
  CFAutorelease(turned);
  if (CVPixelBufferLockBaseAddress(source, kCVPixelBufferLock_ReadOnly) != kCVReturnSuccess) {
    Fail(message, @"Cannot lock image", kMpInternal);
    return nil;
  }
  if (CVPixelBufferLockBaseAddress(turned, 0) != kCVReturnSuccess) {
    CVPixelBufferUnlockBaseAddress(source, kCVPixelBufferLock_ReadOnly);
    Fail(message, @"Cannot lock image", kMpInternal);
    return nil;
  }
  vImage_Buffer from{CVPixelBufferGetBaseAddress(source), height, width,
                     CVPixelBufferGetBytesPerRow(source)};
  vImage_Buffer to{CVPixelBufferGetBaseAddress(turned), CVPixelBufferGetHeight(turned),
                   CVPixelBufferGetWidth(turned), CVPixelBufferGetBytesPerRow(turned)};
  const uint8_t turn = rotation == 90 ? kRotate90DegreesClockwise
                       : rotation == 180 ? kRotate180DegreesClockwise
                                         : kRotate270DegreesClockwise;
  const Pixel_8888 black = {0, 0, 0, 255};
  const vImage_Error rotated = vImageRotate90_ARGB8888(&from, &to, turn, black, kvImageNoFlags);
  CVPixelBufferUnlockBaseAddress(turned, 0);
  CVPixelBufferUnlockBaseAddress(source, kCVPixelBufferLock_ReadOnly);
  if (rotated != kvImageNoError) {
    Fail(message, @"Cannot rotate image", kMpInternal);
    return nil;
  }
  NSError *error = nil;
  MPPImage *result = [[MPPImage alloc] initWithPixelBuffer:turned
                                               orientation:UIImageOrientationUp error:&error];
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

// Copies [width] x [height] single-channel values of [depth] bytes into an
// owned C mask, turned by [rotation] from an upright copy back into the
// caller's frame (see UprightSdkImage); 0 copies as is.
MpImagePtr OwnedMask(const uint8_t *from, int width, int height, int depth, int rotation) {
  if (!from || width < 1 || height < 1) return nullptr;
  const size_t bytes = static_cast<size_t>(width) * height * depth;
  auto *to = Allocate<uint8_t>(bytes);
  auto *image = new (std::nothrow) MpImageInternal{};
  if (!image) {
    free(to);
    throw std::bad_alloc();
  }
  const bool quarter = rotation == 90 || rotation == 270;
  image->mask = to;
  image->maskWidth = quarter ? height : width;
  image->maskHeight = quarter ? width : height;
  image->maskDepth = depth;
  if (!quarter && rotation != 180) {
    memcpy(to, from, bytes);
    return image;
  }
  for (int y = 0; y < image->maskHeight; ++y) {
    for (int x = 0; x < image->maskWidth; ++x) {
      // Where the caller's pixel (x, y) sits in the upright mask.
      int ux = x, uy = y;
      if (rotation == 90) { ux = width - 1 - y; uy = x; }
      if (rotation == 180) { ux = width - 1 - x; uy = height - 1 - y; }
      if (rotation == 270) { ux = y; uy = height - 1 - x; }
      memcpy(to + (static_cast<size_t>(y) * image->maskWidth + x) * depth,
             from + (static_cast<size_t>(uy) * width + ux) * depth, depth);
    }
  }
  return image;
}

MpImagePtr CopyMask(MPPMask *mask) {
  if (!mask) return nullptr;
  const bool floats = mask.dataType == MPPMaskDataTypeFloat32;
  return OwnedMask(floats ? reinterpret_cast<const uint8_t *>(mask.float32Data) : mask.uint8Data,
                   static_cast<int>(mask.width), static_cast<int>(mask.height), floats ? 4 : 1, 0);
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

void CopyPoseLandmarker(MPPPoseLandmarkerResult *source, MpPoseLandmarkerResult *out) {
  CopyLandmarkLists<MPPNormalizedLandmark, MpNormalizedLandmark>(
      source.landmarks, &out->pose_landmarks, &out->pose_landmarks_count);
  CopyLandmarkLists<MPPLandmark, MpLandmark>(
      source.worldLandmarks, &out->pose_world_landmarks, &out->pose_world_landmarks_count);
  out->segmentation_masks = Allocate<MpImagePtr>(source.segmentationMasks.count);
  out->segmentation_masks_count = static_cast<uint32_t>(source.segmentationMasks.count);
  for (NSUInteger i = 0; i < source.segmentationMasks.count; ++i) {
    out->segmentation_masks[i] = CopyMask(source.segmentationMasks[i]);
  }
}

// Image Segmenter's and Interactive Segmenter Legacy's results share fields.
template <typename SdkResult>
void CopySegmenter(SdkResult *source, MpImageSegmenterResult *out) {
  out->confidence_masks = Allocate<MpImagePtr>(source.confidenceMasks.count);
  out->confidence_masks_count = static_cast<uint32_t>(source.confidenceMasks.count);
  for (NSUInteger i = 0; i < source.confidenceMasks.count; ++i) {
    out->confidence_masks[i] = CopyMask(source.confidenceMasks[i]);
  }
  out->has_category_mask = source.categoryMask != nil;
  out->category_mask = CopyMask(source.categoryMask);
  out->quality_scores = Allocate<float>(source.qualityScores.count);
  out->quality_scores_count = static_cast<uint32_t>(source.qualityScores.count);
  for (NSUInteger i = 0; i < source.qualityScores.count; ++i) {
    out->quality_scores[i] = source.qualityScores[i].floatValue;
  }
}

void CopyGestureRecognizer(MPPGestureRecognizerResult *source, MpGestureRecognizerResult *out) {
  out->gestures = Allocate<MpCategories>(source.gestures.count);
  out->gestures_count = static_cast<uint32_t>(source.gestures.count);
  for (NSUInteger i = 0; i < source.gestures.count; ++i) {
    CopyCategories(source.gestures[i], &out->gestures[i]);
  }
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

// Holistic reports one subject, so each part is a single list, possibly empty.
template <typename SdkPoint, typename Point, typename List>
void CopyLandmarkList(NSArray<SdkPoint *> *source, List *out) {
  List *lists = nullptr;
  uint32_t count = 0;
  CopyLandmarkLists<SdkPoint, Point>(@[ source ?: @[] ], &lists, &count);
  *out = lists[0];
  free(lists);
}

template <typename List> void FreeLandmarkList(List &list) {
  for (uint32_t j = 0; j < list.landmarks_count; ++j) free(list.landmarks[j].name);
  free(list.landmarks);
  list = {};
}

void CopyHolisticLandmarker(MPPHolisticLandmarkerResult *source, MpHolisticLandmarkerResult *out) {
  CopyLandmarkList<MPPNormalizedLandmark, MpNormalizedLandmark>(source.faceLandmarks, &out->face_landmarks);
  CopyLandmarkList<MPPNormalizedLandmark, MpNormalizedLandmark>(source.poseLandmarks, &out->pose_landmarks);
  CopyLandmarkList<MPPLandmark, MpLandmark>(source.poseWorldLandmarks, &out->pose_world_landmarks);
  CopyLandmarkList<MPPNormalizedLandmark, MpNormalizedLandmark>(source.leftHandLandmarks, &out->left_hand_landmarks);
  CopyLandmarkList<MPPNormalizedLandmark, MpNormalizedLandmark>(source.rightHandLandmarks, &out->right_hand_landmarks);
  CopyLandmarkList<MPPLandmark, MpLandmark>(source.leftHandWorldLandmarks, &out->left_hand_world_landmarks);
  CopyLandmarkList<MPPLandmark, MpLandmark>(source.rightHandWorldLandmarks, &out->right_hand_world_landmarks);
  CopyCategories(source.faceBlendshapes.categories ?: @[], &out->face_blendshapes);
  out->pose_segmentation_mask = CopyMask(source.poseSegmentationMask);
}

// Google's 1.0.1 iOS SDK copies a CPU pose mask as its first width x height
// floats, ignoring the padding MediaPipe gives each row of a CPU image frame
// (16-byte aligned), so each row after the first shifts further
// (upstream-issues.md UP-018). Lays the copied floats back out at the padded
// stride; the few values past the SDK's copy, lost with it, repeat the row
// above. Rows start at or after where they belong, so this works front to
// back in place.
void RepairPaddedRows(MpImagePtr mask) {
  if (!mask || !mask->mask || mask->maskDepth != 4) return;
  const int width = mask->maskWidth, height = mask->maskHeight;
  const int stride = (width + 3) / 4 * 4;
  if (stride == width) return;
  auto *values = static_cast<float *>(mask->mask);
  const size_t count = static_cast<size_t>(width) * height;
  for (int y = 0; y < height; ++y) {
    for (int x = 0; x < width; ++x) {
      const size_t from = static_cast<size_t>(y) * stride + x;
      values[static_cast<size_t>(y) * width + x] =
          from < count ? values[from] : values[static_cast<size_t>(y - 1) * width + x];
    }
  }
}

MpStatus RepairPoseMasks(MpStatus status, MpPoseLandmarkerPtr task, MpPoseLandmarkerResult *out) {
  if (status != kMpOk || !task->cpu) return status;
  for (uint32_t i = 0; i < out->segmentation_masks_count; ++i) {
    RepairPaddedRows(out->segmentation_masks[i]);
  }
  return status;
}

// Holistic ran on an upright copy (UprightSdkImage), so its points are turned
// back into the caller's pixels, as Google's other tasks report them: image
// points about the image centre, world points about the origin.
template <typename List> void Unrotate(List &list, int rotation, float center) {
  for (uint32_t i = 0; i < list.landmarks_count; ++i) {
    auto &point = list.landmarks[i];
    const float u = point.x - center, v = point.y - center;
    const float x = rotation == 90 ? v : rotation == 180 ? -u : -v;
    const float y = rotation == 90 ? -u : rotation == 180 ? -v : u;
    point.x = x + center;
    point.y = y + center;
  }
}

MpStatus UnrotateHolistic(MpStatus status, MpHolisticLandmarkerPtr task,
                          const MpImageProcessingOptions *options,
                          MpHolisticLandmarkerResult *out, char **message) {
  if (status == kMpOk && task->cpu) RepairPaddedRows(out->pose_segmentation_mask);
  const int rotation = options ? (options->rotation_degrees % 360 + 360) % 360 : 0;
  if (status != kMpOk || rotation == 0) return status;
  for (auto *list : {&out->face_landmarks, &out->pose_landmarks,
                     &out->left_hand_landmarks, &out->right_hand_landmarks}) {
    Unrotate(*list, rotation, 0.5f);
  }
  for (auto *list : {&out->pose_world_landmarks, &out->left_hand_world_landmarks,
                     &out->right_hand_world_landmarks}) {
    Unrotate(*list, rotation, 0.0f);
  }
  // Masks, like points, are reported in the caller's frame.
  if (MpImagePtr upright = out->pose_segmentation_mask) {
    out->pose_segmentation_mask = nullptr;
    try {
      out->pose_segmentation_mask =
          OwnedMask(static_cast<const uint8_t *>(upright->mask), upright->maskWidth,
                    upright->maskHeight, upright->maskDepth, rotation);
    } catch (const std::bad_alloc &) {
      MpImageFree(upright);
      MpHolisticLandmarkerCloseResult(out);
      return Fail(message, @"Cannot copy task result", kMpResourceExhausted);
    }
    MpImageFree(upright);
  }
  return status;
}

// Face and Object Detector results share Google's MPPDetection list and the
// C MpDetectionResult.
template <typename SdkResult>
void CopyDetector(SdkResult *source, MpDetectionResult *out) {
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
                void (*copy)(SdkResult *, Result *), void (*close)(Result *),
                MPPImage *(*convert)(MpImagePtr, const MpImageProcessingOptions *,
                                     char **) = SdkImage) {
  @autoreleasepool {
    if (!task || !out) return Fail(message, @"Supply a task and result");
    *out = {};
    MPPImage *input = convert(image, options, message);
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

// Gesture Recognizer names its calls recognize rather than detect.
template <typename Handle>
MpStatus Recognize(Handle *task, MpImagePtr image, const MpImageProcessingOptions *options,
                   bool video, int64_t timestamp, MpGestureRecognizerResult *out, char **message) {
  @autoreleasepool {
    if (!task || !out) return Fail(message, @"Supply a task and result");
    *out = {};
    MPPImage *input = SdkImage(image, options, message);
    if (!input) return kMpInvalidArgument;
    NSError *error = nil;
    MPPGestureRecognizerResult *result = video
        ? [task->task recognizeVideoFrame:input timestampInMilliseconds:timestamp error:&error]
        : [task->task recognizeImage:input error:&error];
    if (!result) return SdkError(message, error);
    try { CopyGestureRecognizer(result, out); }
    catch (const std::bad_alloc &) {
      MpGestureRecognizerCloseResult(out);
      return Fail(message, @"Cannot copy task result", kMpResourceExhausted);
    }
    return kMpOk;
  }
}

// Classifier limits for canned or custom gestures; nil leaves Google's defaults.
MPPClassifierOptions *SdkClassifier(const MpClassifierOptions &source) {
  MPPClassifierOptions *options = [MPPClassifierOptions new];
  if (source.display_names_locale) {
    options.displayNamesLocale = [NSString stringWithUTF8String:source.display_names_locale];
  }
  options.maxResults = source.max_results;
  options.scoreThreshold = source.score_threshold;
  NSMutableArray<NSString *> *allow = [NSMutableArray array];
  for (uint32_t i = 0; i < source.category_allowlist_count; ++i) {
    [allow addObject:[NSString stringWithUTF8String:source.category_allowlist[i]]];
  }
  NSMutableArray<NSString *> *deny = [NSMutableArray array];
  for (uint32_t i = 0; i < source.category_denylist_count; ++i) {
    [deny addObject:[NSString stringWithUTF8String:source.category_denylist[i]]];
  }
  options.categoryAllowlist = allow;
  options.categoryDenylist = deny;
  return options;
}

void CopyClassifier(MPPImageClassifierResult *source, MpImageClassifierResult *out) {
  NSArray<MPPClassifications *> *heads = source.classificationResult.classifications;
  out->classifications = Allocate<MpClassifications>(heads.count);
  out->classifications_count = static_cast<uint32_t>(heads.count);
  for (NSUInteger i = 0; i < heads.count; ++i) {
    auto &target = out->classifications[i];
    target.head_index = static_cast<int>(heads[i].headIndex);
    target.head_name = CopyString(heads[i].headName);
    MpCategories categories{};
    CopyCategories(heads[i].categories, &categories);
    target.categories = categories.categories;
    target.categories_count = categories.categories_count;
  }
  out->has_timestamp_ms = false;
}

void CopyEmbedder(MPPImageEmbedderResult *source, ImageEmbedderResult *out) {
  NSArray<MPPEmbedding *> *heads = source.embeddingResult.embeddings;
  out->embeddings = Allocate<MpEmbedding>(heads.count);
  out->embeddings_count = static_cast<uint32_t>(heads.count);
  for (NSUInteger i = 0; i < heads.count; ++i) {
    MPPEmbedding *head = heads[i];
    auto &target = out->embeddings[i];
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
        target.quantized_embedding[j] = static_cast<char>(head.quantizedEmbedding[j].unsignedCharValue);
      }
    }
  }
  out->has_timestamp_ms = false;
}

// Image Classifier and Image Embedder take a region of interest, which
// Google's API takes as a normalized rectangle beside the image.
template <typename SdkResult, typename Result, typename Handle>
MpStatus WithRegion(Handle *task, MpImagePtr image, const MpImageProcessingOptions *options,
                    bool video, int64_t timestamp, Result *out, char **message,
                    SdkResult *(^run)(MPPImage *, bool, CGRect, NSError **),
                    void (*copy)(SdkResult *, Result *), void (*close)(Result *)) {
  @autoreleasepool {
    if (!task || !out) return Fail(message, @"Supply a task and result");
    *out = {};
    MpImageProcessingOptions rotation = options ? *options : MpImageProcessingOptions{};
    rotation.has_region_of_interest = 0;
    MPPImage *input = SdkImage(image, &rotation, message);
    if (!input) return kMpInvalidArgument;
    const bool region = options && options->has_region_of_interest;
    CGRect roi = CGRectZero;
    if (region) {
      const MpRectF &r = options->region_of_interest;
      roi = CGRectMake(r.left, r.top, r.right - r.left, r.bottom - r.top);
    }
    NSError *error = nil;
    SdkResult *result = run(input, region, roi, &error);
    if (!result) return SdkError(message, error);
    try { copy(result, out); }
    catch (const std::bad_alloc &) {
      close(out);
      return Fail(message, @"Cannot copy task result", kMpResourceExhausted);
    }
    return kMpOk;
  }
}

template <typename Handle>
MpStatus Classify(Handle *task, MpImagePtr image, const MpImageProcessingOptions *options,
                  bool video, int64_t timestamp, MpImageClassifierResult *out, char **message) {
  MPPImageClassifier *sdk = task ? task->task : nil;
  return WithRegion<MPPImageClassifierResult>(task, image, options, video, timestamp, out, message,
      ^MPPImageClassifierResult *(MPPImage *input, bool region, CGRect roi, NSError **error) {
        if (region) {
          return video ? [sdk classifyVideoFrame:input timestampInMilliseconds:timestamp
                                   regionOfInterest:roi error:error]
                       : [sdk classifyImage:input regionOfInterest:roi error:error];
        }
        return video ? [sdk classifyVideoFrame:input timestampInMilliseconds:timestamp error:error]
                     : [sdk classifyImage:input error:error];
      },
      CopyClassifier, MpImageClassifierCloseResult);
}

template <typename Handle>
MpStatus Embed(Handle *task, MpImagePtr image, const MpImageProcessingOptions *options,
               bool video, int64_t timestamp, ImageEmbedderResult *out, char **message) {
  MPPImageEmbedder *sdk = task ? task->task : nil;
  return WithRegion<MPPImageEmbedderResult>(task, image, options, video, timestamp, out, message,
      ^MPPImageEmbedderResult *(MPPImage *input, bool region, CGRect roi, NSError **error) {
        if (region) {
          return video ? [sdk embedVideoFrame:input timestampInMilliseconds:timestamp
                                regionOfInterest:roi error:error]
                       : [sdk embedImage:input regionOfInterest:roi error:error];
        }
        return video ? [sdk embedVideoFrame:input timestampInMilliseconds:timestamp error:error]
                     : [sdk embedImage:input error:error];
      },
      CopyEmbedder, MpImageEmbedderCloseResult);
}

// Object Detector and Image Classifier share the classifier-style options.
template <typename SdkOptions>
void ApplyClassifierLimits(SdkOptions *sdk, const char *locale, int maxResults,
                           float threshold, const char **allow, uint32_t allowCount,
                           const char **deny, uint32_t denyCount) {
  MpClassifierOptions limits{locale, maxResults, threshold, allow, allowCount, deny, denyCount};
  MPPClassifierOptions *options = SdkClassifier(limits);
  if (options.displayNamesLocale) sdk.displayNamesLocale = options.displayNamesLocale;
  sdk.maxResults = options.maxResults;
  sdk.scoreThreshold = options.scoreThreshold;
  sdk.categoryAllowlist = options.categoryAllowlist;
  sdk.categoryDenylist = options.categoryDenylist;
}

// Image Segmenter names its calls segment rather than detect.
template <typename Handle>
MpStatus Segment(Handle *task, MpImagePtr image, const MpImageProcessingOptions *options,
                 bool video, int64_t timestamp, MpImageSegmenterResult *out, char **message) {
  @autoreleasepool {
    if (!task || !out) return Fail(message, @"Supply a task and result");
    *out = {};
    MPPImage *input = SdkImage(image, options, message);
    if (!input) return kMpInvalidArgument;
    NSError *error = nil;
    MPPImageSegmenterResult *result = video
        ? [task->task segmentVideoFrame:input timestampInMilliseconds:timestamp error:&error]
        : [task->task segmentImage:input error:&error];
    if (!result) return SdkError(message, error);
    try { CopySegmenter<MPPImageSegmenterResult>(result, out); }
    catch (const std::bad_alloc &) {
      MpImageSegmenterCloseResult(out);
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
  if (!image) return;
  if (image->pixels) CVPixelBufferRelease(image->pixels);
  free(image->mask);
  delete image;
}
int MpImageGetWidth(MpImagePtr image) {
  if (!image) return 0;
  return image->mask ? image->maskWidth : static_cast<int>(CVPixelBufferGetWidth(image->pixels));
}
int MpImageGetHeight(MpImagePtr image) {
  if (!image) return 0;
  return image->mask ? image->maskHeight : static_cast<int>(CVPixelBufferGetHeight(image->pixels));
}
// Masks are the only images Dart reads back; they are single-channel and
// tightly packed.
bool MpImageIsContiguous(MpImagePtr image) { return image != nullptr; }
int MpImageGetChannels(MpImagePtr image) { return image && image->mask ? 1 : 4; }
int MpImageGetByteDepth(MpImagePtr image) { return image && image->mask ? image->maskDepth : 1; }
MpStatus MpImageDataUint8(MpImagePtr image, const uint8_t **out, char **message) {
  if (!image || !image->mask || image->maskDepth != 1 || !out) {
    return Fail(message, @"Not a uint8 mask");
  }
  *out = static_cast<const uint8_t *>(image->mask);
  return kMpOk;
}
MpStatus MpImageDataFloat32(MpImagePtr image, const float **out, char **message) {
  if (!image || !image->mask || image->maskDepth != 4 || !out) {
    return Fail(message, @"Not a float32 mask");
  }
  *out = static_cast<const float *>(image->mask);
  return kMpOk;
}
MpStatus MpImageGetValueFloat32(MpImagePtr image, int *pos, int pos_size, float *out,
    char **message) {
  const float *data = nullptr;
  MpStatus status = MpImageDataFloat32(image, &data, message);
  if (status != kMpOk) return status;
  if (!pos || pos_size != 2 || pos[0] < 0 || pos[1] < 0 || pos[0] >= image->maskHeight ||
      pos[1] >= image->maskWidth) {
    return Fail(message, @"Mask position out of range");
  }
  *out = data[pos[0] * image->maskWidth + pos[1]];
  return kMpOk;
}
void MpStringListFree(MpStringList *list) {
  if (!list) return;
  for (int i = 0; i < list->num_strings; ++i) free(list->strings[i]);
  free(list->strings);
  *list = {};
}

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
                                       CopyDetector<MPPFaceDetectorResult>, MpFaceDetectorCloseResult);
}
MpStatus MpFaceDetectorDetectForVideo(MpFaceDetectorPtr task, MpImagePtr image,
    const MpImageProcessingOptions *options, int64_t timestamp, MpFaceDetectorResult *out, char **message) {
  return Detect<MPPFaceDetectorResult>(task, image, options, true, timestamp, out, message,
                                       CopyDetector<MPPFaceDetectorResult>, MpFaceDetectorCloseResult);
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
MpStatus MpPoseLandmarkerCreate(MpPoseLandmarkerOptions *options,
    MpPoseLandmarkerPtr *out, char **message) {
  @autoreleasepool {
    if (!options || !out) return Fail(message, @"Supply options and output");
    *out = nullptr;
    NSString *temporary = nil;
    MPPPoseLandmarkerOptions *sdk = [MPPPoseLandmarkerOptions new];
    MpStatus status = Configure(sdk, options->base_options, options->running_mode, &temporary, message);
    if (status != kMpOk) return status;
    sdk.numPoses = options->num_poses;
    sdk.minPoseDetectionConfidence = options->min_pose_detection_confidence;
    sdk.minPosePresenceConfidence = options->min_pose_presence_confidence;
    sdk.minTrackingConfidence = options->min_tracking_confidence;
    sdk.shouldOutputSegmentationMasks = options->output_segmentation_masks;
    status = Own<MpPoseLandmarkerInternal, MPPPoseLandmarker>(sdk, temporary, out, message);
    if (status == kMpOk) (*out)->cpu = options->base_options.delegate != MP_DELEGATE_GPU;
    return status;
  }
}

void MpPoseLandmarkerCloseResult(MpPoseLandmarkerResult *result) {
  if (!result) return;
  FreeLandmarkLists(result->pose_landmarks, result->pose_landmarks_count);
  FreeLandmarkLists(result->pose_world_landmarks, result->pose_world_landmarks_count);
  for (uint32_t i = 0; i < result->segmentation_masks_count; ++i) {
    MpImageFree(result->segmentation_masks[i]);
  }
  free(result->segmentation_masks);
  *result = {};
}

MpStatus MpPoseLandmarkerDetectImage(MpPoseLandmarkerPtr task, MpImagePtr image,
    const MpImageProcessingOptions *options, MpPoseLandmarkerResult *out, char **message) {
  return RepairPoseMasks(
      Detect<MPPPoseLandmarkerResult>(task, image, options, false, 0, out, message,
                                      CopyPoseLandmarker, MpPoseLandmarkerCloseResult),
      task, out);
}
MpStatus MpPoseLandmarkerDetectForVideo(MpPoseLandmarkerPtr task, MpImagePtr image,
    const MpImageProcessingOptions *options, int64_t timestamp, MpPoseLandmarkerResult *out, char **message) {
  return RepairPoseMasks(
      Detect<MPPPoseLandmarkerResult>(task, image, options, true, timestamp, out, message,
                                      CopyPoseLandmarker, MpPoseLandmarkerCloseResult),
      task, out);
}
MpStatus MpPoseLandmarkerClose(MpPoseLandmarkerPtr task, char **message) {
  return CloseTask(task);
}

MpStatus MpGestureRecognizerCreate(const MpGestureRecognizerOptions *options,
    MpGestureRecognizerPtr *out, char **message) {
  @autoreleasepool {
    if (!options || !out) return Fail(message, @"Supply options and output");
    *out = nullptr;
    NSString *temporary = nil;
    MPPGestureRecognizerOptions *sdk = [MPPGestureRecognizerOptions new];
    MpStatus status = Configure(sdk, options->base_options, options->running_mode, &temporary, message);
    if (status != kMpOk) return status;
    sdk.numHands = options->num_hands;
    sdk.minHandDetectionConfidence = options->min_hand_detection_confidence;
    sdk.minHandPresenceConfidence = options->min_hand_presence_confidence;
    sdk.minTrackingConfidence = options->min_tracking_confidence;
    sdk.cannedGesturesClassifierOptions = SdkClassifier(options->canned_gestures_classifier_options);
    sdk.customGesturesClassifierOptions = SdkClassifier(options->custom_gestures_classifier_options);
    return Own<MpGestureRecognizerInternal, MPPGestureRecognizer>(sdk, temporary, out, message);
  }
}

void MpGestureRecognizerCloseResult(MpGestureRecognizerResult *result) {
  if (!result) return;
  for (uint32_t i = 0; i < result->gestures_count; ++i) FreeCategories(result->gestures[i]);
  free(result->gestures);
  for (uint32_t i = 0; i < result->handedness_count; ++i) FreeCategories(result->handedness[i]);
  free(result->handedness);
  FreeLandmarkLists(result->hand_landmarks, result->hand_landmarks_count);
  FreeLandmarkLists(result->hand_world_landmarks, result->hand_world_landmarks_count);
  *result = {};
}

MpStatus MpGestureRecognizerRecognizeImage(MpGestureRecognizerPtr task, MpImagePtr image,
    const MpImageProcessingOptions *options, MpGestureRecognizerResult *out, char **message) {
  return Recognize(task, image, options, false, 0, out, message);
}
MpStatus MpGestureRecognizerRecognizeForVideo(MpGestureRecognizerPtr task, MpImagePtr image,
    const MpImageProcessingOptions *options, int64_t timestamp, MpGestureRecognizerResult *out,
    char **message) {
  return Recognize(task, image, options, true, timestamp, out, message);
}
MpStatus MpGestureRecognizerClose(MpGestureRecognizerPtr task, char **message) {
  return CloseTask(task);
}

MpStatus MpHolisticLandmarkerCreate(MpHolisticLandmarkerOptions *options,
    MpHolisticLandmarkerPtr *out, char **message) {
  @autoreleasepool {
    if (!options || !out) return Fail(message, @"Supply options and output");
    *out = nullptr;
    NSString *temporary = nil;
    MPPHolisticLandmarkerOptions *sdk = [MPPHolisticLandmarkerOptions new];
    MpStatus status = Configure(sdk, options->base_options, options->running_mode, &temporary, message);
    if (status != kMpOk) return status;
    sdk.minFaceDetectionConfidence = options->min_face_detection_confidence;
    sdk.minFaceSuppressionThreshold = options->min_face_suppression_threshold;
    sdk.minFacePresenceConfidence = options->min_face_presence_confidence;
    sdk.minHandLandmarksConfidence = options->min_hand_landmarks_confidence;
    sdk.minPoseDetectionConfidence = options->min_pose_detection_confidence;
    sdk.minPoseSuppressionThreshold = options->min_pose_suppression_threshold;
    sdk.minPosePresenceConfidence = options->min_pose_presence_confidence;
    sdk.outputFaceBlendshapes = options->output_face_blendshapes;
    sdk.outputPoseSegmentationMasks = options->output_pose_segmentation_masks;
    status = Own<MpHolisticLandmarkerInternal, MPPHolisticLandmarker>(sdk, temporary, out, message);
    if (status == kMpOk) (*out)->cpu = options->base_options.delegate != MP_DELEGATE_GPU;
    return status;
  }
}

void MpHolisticLandmarkerCloseResult(MpHolisticLandmarkerResult *result) {
  if (!result) return;
  FreeLandmarkList(result->face_landmarks);
  FreeLandmarkList(result->pose_landmarks);
  FreeLandmarkList(result->pose_world_landmarks);
  FreeLandmarkList(result->left_hand_landmarks);
  FreeLandmarkList(result->right_hand_landmarks);
  FreeLandmarkList(result->left_hand_world_landmarks);
  FreeLandmarkList(result->right_hand_world_landmarks);
  FreeCategories(result->face_blendshapes);
  MpImageFree(result->pose_segmentation_mask);
  *result = {};
}

MpStatus MpHolisticLandmarkerDetectImage(MpHolisticLandmarkerPtr task, MpImagePtr image,
    const MpImageProcessingOptions *options, MpHolisticLandmarkerResult *out, char **message) {
  return UnrotateHolistic(
      Detect<MPPHolisticLandmarkerResult>(task, image, options, false, 0, out, message,
                                          CopyHolisticLandmarker, MpHolisticLandmarkerCloseResult,
                                          UprightSdkImage),
      task, options, out, message);
}
MpStatus MpHolisticLandmarkerDetectForVideo(MpHolisticLandmarkerPtr task, MpImagePtr image,
    const MpImageProcessingOptions *options, int64_t timestamp, MpHolisticLandmarkerResult *out,
    char **message) {
  return UnrotateHolistic(
      Detect<MPPHolisticLandmarkerResult>(task, image, options, true, timestamp, out, message,
                                          CopyHolisticLandmarker, MpHolisticLandmarkerCloseResult,
                                          UprightSdkImage),
      task, options, out, message);
}
MpStatus MpHolisticLandmarkerClose(MpHolisticLandmarkerPtr task, char **message) {
  return CloseTask(task);
}
MpStatus MpObjectDetectorCreate(MpObjectDetectorOptions *options,
    MpObjectDetectorPtr *out, char **message) {
  @autoreleasepool {
    if (!options || !out) return Fail(message, @"Supply options and output");
    *out = nullptr;
    NSString *temporary = nil;
    MPPObjectDetectorOptions *sdk = [MPPObjectDetectorOptions new];
    MpStatus status = Configure(sdk, options->base_options, options->running_mode, &temporary, message);
    if (status != kMpOk) return status;
    ApplyClassifierLimits(sdk, options->display_names_locale, options->max_results,
                          options->score_threshold, options->category_allowlist,
                          options->category_allowlist_count, options->category_denylist,
                          options->category_denylist_count);
    return Own<MpObjectDetectorInternal, MPPObjectDetector>(sdk, temporary, out, message);
  }
}

void MpObjectDetectorCloseResult(MpObjectDetectorResult *result) {
  MpFaceDetectorCloseResult(result);
}

MpStatus MpObjectDetectorDetectImage(MpObjectDetectorPtr task, MpImagePtr image,
    const MpImageProcessingOptions *options, MpObjectDetectorResult *out, char **message) {
  return Detect<MPPObjectDetectorResult>(task, image, options, false, 0, out, message,
                                         CopyDetector<MPPObjectDetectorResult>,
                                         MpObjectDetectorCloseResult);
}
MpStatus MpObjectDetectorDetectForVideo(MpObjectDetectorPtr task, MpImagePtr image,
    const MpImageProcessingOptions *options, int64_t timestamp, MpObjectDetectorResult *out,
    char **message) {
  return Detect<MPPObjectDetectorResult>(task, image, options, true, timestamp, out, message,
                                         CopyDetector<MPPObjectDetectorResult>,
                                         MpObjectDetectorCloseResult);
}
MpStatus MpObjectDetectorClose(MpObjectDetectorPtr task, char **message) {
  return CloseTask(task);
}

MpStatus MpImageClassifierCreate(MpImageClassifierOptions *options,
    MpImageClassifierPtr *out, char **message) {
  @autoreleasepool {
    if (!options || !out) return Fail(message, @"Supply options and output");
    *out = nullptr;
    NSString *temporary = nil;
    MPPImageClassifierOptions *sdk = [MPPImageClassifierOptions new];
    MpStatus status = Configure(sdk, options->base_options, options->running_mode, &temporary, message);
    if (status != kMpOk) return status;
    const MpClassifierOptions &c = options->classifier_options;
    ApplyClassifierLimits(sdk, c.display_names_locale, c.max_results, c.score_threshold,
                          c.category_allowlist, c.category_allowlist_count,
                          c.category_denylist, c.category_denylist_count);
    return Own<MpImageClassifierInternal, MPPImageClassifier>(sdk, temporary, out, message);
  }
}

void MpImageClassifierCloseResult(MpImageClassifierResult *result) {
  if (!result) return;
  for (uint32_t i = 0; i < result->classifications_count; ++i) {
    auto &head = result->classifications[i];
    MpCategories categories{head.categories, head.categories_count};
    FreeCategories(categories);
    free(head.head_name);
  }
  free(result->classifications);
  *result = {};
}

MpStatus MpImageClassifierClassifyImage(MpImageClassifierPtr task, MpImagePtr image,
    const MpImageProcessingOptions *options, MpImageClassifierResult *out, char **message) {
  return Classify(task, image, options, false, 0, out, message);
}
MpStatus MpImageClassifierClassifyForVideo(MpImageClassifierPtr task, MpImagePtr image,
    const MpImageProcessingOptions *options, int64_t timestamp, MpImageClassifierResult *out,
    char **message) {
  return Classify(task, image, options, true, timestamp, out, message);
}
MpStatus MpImageClassifierClose(MpImageClassifierPtr task, char **message) {
  return CloseTask(task);
}
MpStatus MpImageEmbedderCreate(ImageEmbedderOptions *options, MpImageEmbedderPtr *out,
    char **message) {
  @autoreleasepool {
    if (!options || !out) return Fail(message, @"Supply options and output");
    *out = nullptr;
    NSString *temporary = nil;
    MPPImageEmbedderOptions *sdk = [MPPImageEmbedderOptions new];
    MpStatus status = Configure(sdk, options->base_options, options->running_mode, &temporary, message);
    if (status != kMpOk) return status;
    sdk.l2Normalize = options->embedder_options.l2_normalize;
    sdk.quantize = options->embedder_options.quantize;
    return Own<MpImageEmbedderInternal, MPPImageEmbedder>(sdk, temporary, out, message);
  }
}

void MpImageEmbedderCloseResult(ImageEmbedderResult *result) {
  if (!result) return;
  for (uint32_t i = 0; i < result->embeddings_count; ++i) {
    free(result->embeddings[i].float_embedding);
    free(result->embeddings[i].quantized_embedding);
    free(result->embeddings[i].head_name);
  }
  free(result->embeddings);
  *result = {};
}

MpStatus MpImageEmbedderEmbedImage(MpImageEmbedderPtr task, MpImagePtr image,
    const MpImageProcessingOptions *options, ImageEmbedderResult *out, char **message) {
  return Embed(task, image, options, false, 0, out, message);
}
MpStatus MpImageEmbedderEmbedForVideo(MpImageEmbedderPtr task, MpImagePtr image,
    const MpImageProcessingOptions *options, int64_t timestamp, ImageEmbedderResult *out,
    char **message) {
  return Embed(task, image, options, true, timestamp, out, message);
}
MpStatus MpImageEmbedderClose(MpImageEmbedderPtr task, char **message) {
  return CloseTask(task);
}
MpStatus MpImageSegmenterCreate(MpImageSegmenterOptions *options, MpImageSegmenterPtr *out,
    char **message) {
  @autoreleasepool {
    if (!options || !out) return Fail(message, @"Supply options and output");
    *out = nullptr;
    NSString *temporary = nil;
    MPPImageSegmenterOptions *sdk = [MPPImageSegmenterOptions new];
    MpStatus status = Configure(sdk, options->base_options, options->running_mode, &temporary, message);
    if (status != kMpOk) return status;
    if (options->display_names_locale && *options->display_names_locale) {
      sdk.displayNamesLocale = [NSString stringWithUTF8String:options->display_names_locale];
    }
    sdk.shouldOutputConfidenceMasks = options->output_confidence_masks;
    sdk.shouldOutputCategoryMask = options->output_category_mask;
    return Own<MpImageSegmenterInternal, MPPImageSegmenter>(sdk, temporary, out, message);
  }
}

MpStatus MpImageSegmenterGetLabels(MpImageSegmenterPtr task, MpStringList *list, char **message) {
  @autoreleasepool {
    if (!task || !list) return Fail(message, @"Supply a task and list");
    NSArray<NSString *> *labels = task->task.labels ?: @[];
    list->strings = Allocate<char *>(labels.count);
    list->num_strings = static_cast<int>(labels.count);
    for (NSUInteger i = 0; i < labels.count; ++i) list->strings[i] = CopyString(labels[i]);
    return kMpOk;
  }
}

void MpImageSegmenterCloseResult(MpImageSegmenterResult *result) {
  if (!result) return;
  for (uint32_t i = 0; i < result->confidence_masks_count; ++i) {
    MpImageFree(result->confidence_masks[i]);
  }
  free(result->confidence_masks);
  MpImageFree(result->category_mask);
  free(result->quality_scores);
  *result = {};
}

MpStatus MpImageSegmenterSegmentImage(MpImageSegmenterPtr task, MpImagePtr image,
    const MpImageProcessingOptions *options, MpImageSegmenterResult *out, char **message) {
  return Segment(task, image, options, false, 0, out, message);
}
MpStatus MpImageSegmenterSegmentForVideo(MpImageSegmenterPtr task, MpImagePtr image,
    const MpImageProcessingOptions *options, int64_t timestamp, MpImageSegmenterResult *out,
    char **message) {
  return Segment(task, image, options, true, timestamp, out, message);
}
MpStatus MpImageSegmenterClose(MpImageSegmenterPtr task, char **message) {
  return CloseTask(task);
}
// The keypoint, or the scribble's points, normalized to the input image.
static MPPNormalizedKeypoint *SdkKeypoint(const MpNormalizedKeypoint &point) {
  return [[MPPNormalizedKeypoint alloc] initWithLocation:CGPointMake(point.x, point.y)
                                                   label:nil
                                                   score:0];
}

MpStatus MpInteractiveSegmenterLegacyCreate(MpInteractiveSegmenterLegacyOptions *options,
    MpInteractiveSegmenterLegacyPtr *out, char **message) {
  @autoreleasepool {
    if (!options || !out) return Fail(message, @"Supply options and output");
    *out = nullptr;
    NSString *temporary = nil;
    MPPInteractiveSegmenterLegacyOptions *sdk = [MPPInteractiveSegmenterLegacyOptions new];
    // The task has no running mode: it segments single images only.
    NSString *path = ModelPath(options->base_options, &temporary, message);
    if (!path) return kMpInvalidArgument;
    sdk.baseOptions.modelAssetPath = path;
    sdk.baseOptions.delegate =
        options->base_options.delegate == MP_DELEGATE_GPU ? MPPDelegateGPU : MPPDelegateCPU;
    sdk.shouldOutputConfidenceMasks = options->output_confidence_masks;
    sdk.shouldOutputCategoryMask = options->output_category_mask;
    return Own<MpInteractiveSegmenterLegacyInternal, MPPInteractiveSegmenterLegacy>(
        sdk, temporary, out, message);
  }
}

MpStatus MpInteractiveSegmenterLegacySegmentImage(MpInteractiveSegmenterLegacyPtr task,
    MpImagePtr image, const MpRegionOfInterest *roi, const MpImageProcessingOptions *options,
    MpImageSegmenterResult *out, char **message) {
  @autoreleasepool {
    if (!task || !out || !roi) return Fail(message, @"Supply a task, region and result");
    *out = {};
    MPPRegionOfInterest *region = nil;
    if (roi->format == MP_REGION_OF_INTEREST_FORMAT_KEYPOINT && roi->keypoint) {
      region = [[MPPRegionOfInterest alloc] initWithNormalizedKeyPoint:SdkKeypoint(*roi->keypoint)];
    } else if (roi->format == MP_REGION_OF_INTEREST_FORMAT_SCRIBBLE && roi->scribble) {
      NSMutableArray<MPPNormalizedKeypoint *> *points = [NSMutableArray array];
      for (uint32_t i = 0; i < roi->scribble_count; ++i) {
        [points addObject:SdkKeypoint(roi->scribble[i])];
      }
      region = [[MPPRegionOfInterest alloc] initWithScribbles:points];
    } else {
      return Fail(message, @"Supply a keypoint or a scribble");
    }
    MPPImage *input = SdkImage(image, options, message);
    if (!input) return kMpInvalidArgument;
    NSError *error = nil;
    MPPInteractiveSegmenterLegacyResult *result =
        [task->task segmentImage:input regionOfInterest:region error:&error];
    if (!result) return SdkError(message, error);
    try { CopySegmenter<MPPInteractiveSegmenterLegacyResult>(result, out); }
    catch (const std::bad_alloc &) {
      MpImageSegmenterCloseResult(out);
      return Fail(message, @"Cannot copy task result", kMpResourceExhausted);
    }
    return kMpOk;
  }
}

void MpInteractiveSegmenterLegacyCloseResult(MpImageSegmenterResult *result) {
  MpImageSegmenterCloseResult(result);
}

MpStatus MpInteractiveSegmenterLegacyClose(MpInteractiveSegmenterLegacyPtr task, char **message) {
  return CloseTask(task);
}
// Copies the single-channel mask image Google's stateful segmenter returns
// into an owned float32 mask, row by row from its pixel buffer.
static MpImagePtr MaskFromSdkImage(MPPImage *mask, char **message) {
  CVPixelBufferRef pixels = mask.pixelBuffer;
  if (!pixels) {
    Fail(message, [NSString stringWithFormat:@"Unexpected mask image source %ld",
                                             static_cast<long>(mask.imageSourceType)]);
    return nullptr;
  }
  const OSType format = CVPixelBufferGetPixelFormatType(pixels);
  if (format != kCVPixelFormatType_OneComponent32Float && format != kCVPixelFormatType_OneComponent8) {
    Fail(message, [NSString stringWithFormat:@"Unexpected mask pixel format %u",
                                             static_cast<unsigned>(format)]);
    return nullptr;
  }
  const int width = static_cast<int>(CVPixelBufferGetWidth(pixels));
  const int height = static_cast<int>(CVPixelBufferGetHeight(pixels));
  CVPixelBufferLockBaseAddress(pixels, kCVPixelBufferLock_ReadOnly);
  const auto *base = static_cast<const uint8_t *>(CVPixelBufferGetBaseAddress(pixels));
  const size_t stride = CVPixelBufferGetBytesPerRow(pixels);
  float *values = nullptr;
  try {
    values = Allocate<float>(static_cast<size_t>(width) * height);
  } catch (const std::bad_alloc &) {
    CVPixelBufferUnlockBaseAddress(pixels, kCVPixelBufferLock_ReadOnly);
    Fail(message, @"Cannot copy task result", kMpResourceExhausted);
    return nullptr;
  }
  for (int y = 0; y < height; ++y) {
    const uint8_t *row = base + y * stride;
    for (int x = 0; x < width; ++x) {
      values[static_cast<size_t>(y) * width + x] =
          format == kCVPixelFormatType_OneComponent32Float
              ? reinterpret_cast<const float *>(row)[x]
              : row[x] / 255.0f;
    }
  }
  CVPixelBufferUnlockBaseAddress(pixels, kCVPixelBufferLock_ReadOnly);
  MpImagePtr owned = nullptr;
  try {
    owned = OwnedMask(reinterpret_cast<const uint8_t *>(values), width, height, 4, 0);
  } catch (const std::bad_alloc &) {
    Fail(message, @"Cannot copy task result", kMpResourceExhausted);
  }
  free(values);
  return owned;
}

MP_EXPORT MpStatus MpIosInteractiveSegmenterCreate(const MpBaseOptions *base, void **out, char **message) {
  @autoreleasepool {
    if (!base || !out) return Fail(message, @"Supply options and output");
    *out = nullptr;
    NSString *temporary = nil;
    NSString *path = ModelPath(*base, &temporary, message);
    if (!path) return kMpInvalidArgument;
    MPPInteractiveSegmenterOptions *sdk = [MPPInteractiveSegmenterOptions new];
    sdk.baseOptions.modelAssetPath = path;
    sdk.baseOptions.delegate = base->delegate == MP_DELEGATE_GPU ? MPPDelegateGPU : MPPDelegateCPU;
    MpIosInteractiveSegmenterInternal *handle = nullptr;
    MpStatus status = Own<MpIosInteractiveSegmenterInternal, MPPInteractiveSegmenter>(
        sdk, temporary, &handle, message);
    *out = handle;
    return status;
  }
}

MP_EXPORT MpStatus MpIosInteractiveSegmenterSetImage(void *task, MpImagePtr image, char **message) {
  @autoreleasepool {
    auto *session = static_cast<MpIosInteractiveSegmenterInternal *>(task);
    if (!session) return Fail(message, @"Supply a task");
    MPPImage *input = SdkImage(image, nullptr, message);
    if (!input) return kMpInvalidArgument;
    NSError *error = nil;
    if (![session->task setImage:input error:&error]) return SdkError(message, error);
    session->image = input;
    return kMpOk;
  }
}

MP_EXPORT MpStatus MpIosInteractiveSegmenterSegment(void *task, const MpIosStrokes *strokes, MpImagePtr *out,
    char **message) {
  @autoreleasepool {
    auto *session = static_cast<MpIosInteractiveSegmenterInternal *>(task);
    if (!session || !strokes || !out) return Fail(message, @"Supply a task, strokes and output");
    *out = nullptr;
    NSMutableArray<MPPStroke *> *history = [NSMutableArray array];
    for (uint32_t i = 0; i < strokes->strokes_count; ++i) {
      const MpIosStroke &stroke = strokes->strokes[i];
      if (stroke.brush_mode < 1 || stroke.brush_mode > 3) {
        return Fail(message, @"Unknown brush mode");
      }
      NSMutableArray<MPPNormalizedKeypoint *> *points = [NSMutableArray array];
      for (uint32_t j = 0; j < stroke.points_count; ++j) {
        [points addObject:[[MPPNormalizedKeypoint alloc]
                              initWithLocation:CGPointMake(stroke.points[j].x, stroke.points[j].y)
                                         label:nil
                                         score:0]];
      }
      [history addObject:[[MPPStroke alloc] initWithPoints:points
                                                 brushMode:static_cast<MPPBrushMode>(stroke.brush_mode)
                                               isCompleted:stroke.is_completed]];
    }
    NSError *error = nil;
    MPPImage *mask = [session->task segment:history error:&error];
    if (!mask) return SdkError(message, error);
    *out = MaskFromSdkImage(mask, message);
    return *out ? kMpOk : kMpInternal;
  }
}

MP_EXPORT MpStatus MpIosInteractiveSegmenterClose(void *task, char **message) {
  return CloseTask(static_cast<MpIosInteractiveSegmenterInternal *>(task));
}
}  // extern C
