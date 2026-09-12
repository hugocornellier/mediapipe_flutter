#include <cassert>
#include <cstdio>
#include "mediapipe/tasks/c/vision/face_landmarker/face_landmarker.h"

static_assert(sizeof(MpFaceLandmarkerOptions) == 104);
static_assert(sizeof(MpFaceLandmarkerResult) == 48);
static_assert(sizeof(MpNormalizedLandmark) == 40);
static_assert(sizeof(MpNormalizedLandmarks) == 16);
static_assert(sizeof(MpMatrix) == 16);

int main(int argc, char** argv) {
  assert(argc == 3);
  char* error = nullptr;
  auto check = [&](MpStatus status) {
    if (status != kMpOk) fprintf(stderr, "%s\n", error ? error : "Native failure");
    assert(status == kMpOk);
  };
  MpFaceLandmarkerOptions options{};
  options.base_options.model_asset_path = argv[1];
  options.base_options.file_descriptor = -1;
  options.base_options.delegate = MP_DELEGATE_CPU;
  options.base_options.host_system = MP_HOST_SYSTEM_MAC;
  options.running_mode = MP_RUNNING_MODE_IMAGE;
  options.output_face_blendshapes = true;
  options.output_facial_transformation_matrixes = true;
  MpFaceLandmarkerPtr task = nullptr;
  check(MpFaceLandmarkerCreate(&options, &task, &error));
  MpImagePtr image = nullptr;
  check(MpImageCreateFromFile(argv[2], &image, &error));
  MpFaceLandmarkerResult result{};
  check(MpFaceLandmarkerDetectImage(task, image, nullptr, &result, &error));
  assert(result.face_landmarks_count == 1);
  assert(result.face_landmarks[0].landmarks_count == 478);
  assert(result.face_blendshapes_count == 1);
  assert(result.face_blendshapes[0].categories_count == 52);
  assert(result.facial_transformation_matrixes_count == 1);
  assert(result.facial_transformation_matrixes[0].rows == 4);
  assert(result.facial_transformation_matrixes[0].cols == 4);
  MpFaceLandmarkerCloseResult(&result);
  MpImageFree(image);
  check(MpFaceLandmarkerClose(task, &error));
  puts("Official Face Landmarker ABI: 478 landmarks, 52 blendshapes, 4x4 matrix.");
}
