// Checks the real upstream C ABI and inference before packaging a build.
#include <cstdio>
#include "mediapipe/tasks/c/vision/face_detector/face_detector.h"
#include "mediapipe/tasks/c/components/containers/category.h"
#include "mediapipe/tasks/c/components/containers/keypoint.h"
#include "mediapipe/tasks/c/vision/core/image_processing_options.h"

static_assert(sizeof(MpStatus) == 4);
static_assert(sizeof(MpImageFormat) == 4);
static_assert(sizeof(MpRunningMode) == 4);
static_assert(sizeof(MpBaseOptions) == 72);
static_assert(sizeof(MpFaceDetectorOptions) == 96);
static_assert(sizeof(MpDetectionResult) == 16);
static_assert(sizeof(MpDetection) == 48);
static_assert(sizeof(MpCategory) == 24);
static_assert(sizeof(MpNormalizedKeypoint) == 24);
static_assert(sizeof(MpImageProcessingOptions) == 24);

int main(int argc, char** argv) {
  if (argc != 3) return 64;
  MpFaceDetectorOptions options{};
  options.base_options.model_asset_path = argv[1];
  options.base_options.file_descriptor = -1;
  options.running_mode = MP_RUNNING_MODE_IMAGE;
  options.min_detection_confidence = 0.5;
  options.min_suppression_threshold = 0.3;
  MpFaceDetectorPtr task = nullptr;
  MpImagePtr image = nullptr;
  MpFaceDetectorResult result{};
  char* error = nullptr;
  auto status = MpFaceDetectorCreate(&options, &task, &error);
  if (status == kMpOk) status = MpImageCreateFromFile(argv[2], &image, &error);
  if (status == kMpOk) {
    status = MpFaceDetectorDetectImage(task, image, nullptr, &result, &error);
  }
  const bool valid = status == kMpOk && result.detections_count == 1 &&
      result.detections[0].keypoints_count == 6;
  if (error) {
    std::fprintf(stderr, "%s\n", error);
    MpErrorFree(error);
    error = nullptr;
  }
  MpFaceDetectorCloseResult(&result);
  if (image) MpImageFree(image);
  if (task) {
    const auto close_status = MpFaceDetectorClose(task, &error);
    if (error) MpErrorFree(error);
    if (close_status != kMpOk) return 1;
  }
  if (!valid) return 1;
  std::puts("Native ABI and portrait inference passed.");
}
