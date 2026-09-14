SHELL := /bin/bash
DART_PACKAGES := packages/mediapipe-core packages/mediapipe-task-text packages/mediapipe-task-genai packages/mediapipe-task-vision tool/builder
FLUTTER_PACKAGES := packages/mediapipe-task-text/example packages/mediapipe-task-text/example_embedding packages/mediapipe-task-genai/example packages/mediapipe-task-vision/example packages/mediapipe-task-vision/example_segmenter
ALL_PACKAGES := $(DART_PACKAGES) $(FLUTTER_PACKAGES)
VISION_NATIVE_ARGS ?=

.PHONY: get models native_vision release_vision analyze format check_format generate generate_core generate_text generate_genai generate_vision test test_only test_core test_text test_vision test_vision_flutter test_vision_prebuilt test_examples build_text build_vision_camera example_text example_vision ci headers sdks

get:
	@for package in $(DART_PACKAGES); do (cd "$$package" && dart pub get) || exit $$?; done
	@for package in $(FLUTTER_PACKAGES); do (cd "$$package" && flutter pub get) || exit $$?; done

# Download versioned test/example models; no model is embedded in a package.
models:
	cd tool/builder && dart bin/main.dart model -m textclassification
	cd tool/builder && dart bin/main.dart model -m textembedding
	cd tool/builder && dart bin/main.dart model -m languagedetection
	cd packages/mediapipe-task-vision && dart tool/download_model.dart
	cd packages/mediapipe-task-vision && dart tool/download_face_landmarker.dart
	cd packages/mediapipe-task-vision && python3 -B tool/prepare_face_example.py
	cd packages/mediapipe-task-vision && dart tool/download_interactive_segmenter.dart
	cd packages/mediapipe-task-vision && python3 -B tool/prepare_segmenter_example.py
	$(MAKE) models_embedding

# Optional maintainer build; consumers download the pinned prebuilt runtime.
native_vision:
	cd packages/mediapipe-task-vision && python3 tool/build_native.py $(VISION_NATIVE_ARGS)
	cd packages/mediapipe-task-vision && python3 tool/build_native.py --task face_landmarker $(VISION_NATIVE_ARGS)

# Prepare a reviewable public archive from an already tested native build.
release_vision:
	cd packages/mediapipe-task-vision && python3 tool/prepare_native_release.py
	cd packages/mediapipe-task-vision && python3 tool/prepare_native_release.py --task face_landmarker

analyze:
	@for package in $(ALL_PACKAGES); do (cd "$$package" && dart analyze --fatal-infos) || exit $$?; done

format:
	@for package in $(ALL_PACKAGES); do (cd "$$package" && dart format .) || exit $$?; done

check_format:
	@for package in $(ALL_PACKAGES); do (cd "$$package" && dart format --output=none --set-exit-if-changed .) || exit $$?; done

# Regenerate against the checked-in headers, never a floating upstream checkout.
generate:
	$(MAKE) generate_core
	$(MAKE) generate_text
	$(MAKE) generate_genai
	$(MAKE) generate_vision

generate_core:
	cd packages/mediapipe-core && dart run ffigen --config=ffigen.yaml

generate_text:
	cd packages/mediapipe-task-text && dart run ffigen --config=ffigen.yaml

generate_genai:
	cd packages/mediapipe-task-genai && dart run ffigen --config=ffigen.yaml

generate_vision:
	cd packages/mediapipe-task-vision && dart tool/generate_bindings.dart
	cd packages/mediapipe-task-vision && dart tool/generate_bindings.dart ffigen_face_landmarker.yaml

test:
	$(MAKE) models
	$(MAKE) test_only

test_only:
	$(MAKE) test_core
	$(MAKE) test_text
	$(MAKE) test_vision
	$(MAKE) test_examples

test_core:
	cd packages/mediapipe-core && dart test --reporter expanded

test_text:
	cd packages/mediapipe-task-text && dart test --reporter expanded

test_vision:
	cd packages/mediapipe-task-vision && dart test --reporter expanded

test_vision_flutter:
	cd packages/mediapipe-task-vision && python3 tool/test_flutter_macos.py

test_vision_prebuilt:
	cd packages/mediapipe-task-vision && python3 tool/test_prebuilt_macos.py

# Opt-in hardware soak; never runs on a hosted CI runner.
.PHONY: test_vision_camera_soak
test_vision_camera_soak:
	cd packages/mediapipe-task-vision && python3 tool/test_camera_soak.py

# GenAI example tests cover Dart state only; they do not validate LLM inference.
test_examples:
	cd packages/mediapipe-task-text/example && flutter test --reporter expanded
	cd packages/mediapipe-task-text/example_embedding && dart test --reporter expanded
	cd packages/mediapipe-task-genai/example && flutter test --reporter expanded
	cd packages/mediapipe-task-vision/example && flutter test --reporter expanded
	cd packages/mediapipe-task-vision/example_segmenter && flutter test --reporter expanded

build_text:
	cd packages/mediapipe-task-text/example && flutter build macos --debug

build_vision_camera:
	cd packages/mediapipe-task-vision/example && flutter build macos --release

.PHONY: example_segmenter build_segmenter test_segmenter_prebuilt
example_segmenter:
	cd packages/mediapipe-task-vision && dart tool/download_interactive_segmenter.dart
	cd packages/mediapipe-task-vision && python3 -B tool/prepare_segmenter_example.py
	cd packages/mediapipe-task-vision/example_segmenter && flutter run -d macos --release

build_segmenter:
	cd packages/mediapipe-task-vision/example_segmenter && flutter build macos --release

test_segmenter_prebuilt:
	cd packages/mediapipe-task-vision && python3 -B tool/test_segmenter_macos.py

example_vision:
	cd packages/mediapipe-task-vision && dart tool/download_model.dart
	cd packages/mediapipe-task-vision && dart tool/download_face_landmarker.dart
	cd packages/mediapipe-task-vision && python3 -B tool/prepare_face_example.py
	cd packages/mediapipe-task-vision/example && flutter run -d macos --release

.PHONY: native_vision_ios_simulator test_vision_ios_simulator
native_vision_ios_simulator:
	cd packages/mediapipe-task-vision && python3 -B tool/build_ios_simulator.py

test_vision_ios_simulator:
	cd packages/mediapipe-task-vision && python3 -B tool/test_ios_simulator.py

example_text:
	cd packages/mediapipe-task-text/example && flutter run -d macos

.PHONY: models_embedding example_embedding test_embedding_macos
models_embedding:
	cd packages/mediapipe-task-text && dart tool/download_embedding_gemma.dart
	mkdir -p packages/mediapipe-task-text/example_embedding/assets
	cp packages/mediapipe-task-text/models/embedding_gemma.task packages/mediapipe-task-text/example_embedding/assets/embedding_gemma.task

example_embedding: models_embedding
	cd packages/mediapipe-task-text/example_embedding && flutter run -d macos --release

test_embedding_macos:
	cd packages/mediapipe-task-text && python3 -B tool/test_embedding_macos.py

# Run sequentially even when make is invoked with -j.
ci:
	$(MAKE) get
	$(MAKE) models
	$(MAKE) native_vision
	$(MAKE) analyze
	$(MAKE) check_format
	$(MAKE) test_only
	$(MAKE) build_text
	$(MAKE) build_vision_camera
	$(MAKE) build_segmenter
	$(MAKE) test_vision_flutter

# Maintainer tools: review headers, ABI, URLs and checksums as one runtime update.
headers:
	cd tool/builder && dart bin/main.dart headers

# Writes candidate manifests; never overwrites the reviewed runtime pins.
sdks:
	cd tool/builder && dart bin/main.dart sdks
