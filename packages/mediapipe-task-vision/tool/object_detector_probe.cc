// Runs the object detector against a library, outside any Dart process.
#include <cstdio>
#include <cstring>
#include "mediapipe/tasks/c/components/containers/category.h"
#include "mediapipe/tasks/c/vision/object_detector/object_detector.h"

int main(int argc, char** argv) {
  if (argc < 3) return 64;
  const bool gpu = argc > 3 && std::strcmp(argv[3], "gpu") == 0;
  MpObjectDetectorOptions options{};
  options.base_options.model_asset_path = argv[1];
  options.base_options.file_descriptor = -1;
  options.base_options.delegate = gpu ? MP_DELEGATE_GPU : MP_DELEGATE_CPU;
  options.base_options.host_system = MP_HOST_SYSTEM_MAC;
  options.running_mode = MP_RUNNING_MODE_IMAGE;
  options.max_results = 5;
  options.score_threshold = 0.3f;
  MpObjectDetectorPtr task = nullptr;
  char* error = nullptr;
  if (MpObjectDetectorCreate(&options, &task, &error) != kMpOk) {
    std::printf("create failed: %s\n", error ? error : "?");
    return 1;
  }
  // Every image argument runs through the same task, as the test does.
  for (int i = 2; i < argc; i++) {
    if (!std::strcmp(argv[i], "cpu") || !std::strcmp(argv[i], "gpu")) continue;
    MpImagePtr image = nullptr;
    if (MpImageCreateFromFile(argv[i], &image, &error) != kMpOk) {
      std::printf("image failed: %s\n", error ? error : "?");
      return 1;
    }
    MpObjectDetectorResult result{};
    std::printf("detecting %s ...\n", argv[i]);
    std::fflush(stdout);
    if (MpObjectDetectorDetectImage(task, image, nullptr, &result, &error) !=
        kMpOk) {
      std::printf("detect failed: %s\n", error ? error : "?");
      return 1;
    }
    std::printf("  %u detection(s)\n", result.detections_count);
    for (uint32_t d = 0; d < result.detections_count; d++) {
      const MpDetection& det = result.detections[d];
      std::printf("    box=(%d,%d,%d,%d)", det.bounding_box.left,
                  det.bounding_box.top, det.bounding_box.right,
                  det.bounding_box.bottom);
      if (det.categories_count > 0) {
        std::printf(" %s %.6f",
                    det.categories[0].category_name
                        ? det.categories[0].category_name
                        : "?",
                    det.categories[0].score);
      }
      std::printf("\n");
    }
    std::fflush(stdout);
    MpObjectDetectorCloseResult(&result);
    MpImageFree(image);
  }
  MpObjectDetectorClose(task, &error);
  std::printf("OK\n");
  return 0;
}
