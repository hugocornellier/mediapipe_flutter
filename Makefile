SHELL := /bin/bash
DART_PACKAGES := packages/mediapipe-core tool/task_benchmarks
FLUTTER_PACKAGES := packages/mediapipe-task-vision packages/mediapipe-task-text packages/mediapipe-task-audio
ALL_PACKAGES := $(DART_PACKAGES) $(FLUTTER_PACKAGES)
# The gallery's pubspec is generated per target by tool/gallery_builder, so
# it is format-checked without package resolution
# and analyzed by the platform workflows after preparation.
GALLERY_SOURCES := lib test integration_test tool
# The generated pubspec (sdk ^3.12.0) may be absent when formatting, and
# unresolved files default to the newest language version, whose style differs.
GALLERY_FORMAT := dart format --language-version=3.12
ANALYZE_PACKAGES := $(ALL_PACKAGES)

.PHONY: get models analyze format check_format generate generate_text generate_vision test test_only test_core test_text test_vision test_vision_flutter ci

get:
	@for package in $(DART_PACKAGES); do (cd "$$package" && dart pub get) || exit $$?; done
	@for package in $(FLUTTER_PACKAGES); do (cd "$$package" && flutter pub get) || exit $$?; done

# Download versioned test/example models; no model is embedded in a package.
models:
	$(MAKE) models_text
	$(MAKE) models_audio
	cd packages/mediapipe-task-vision && dart tool/download_model.dart
	cd packages/mediapipe-task-vision && dart tool/download_face_landmarker.dart
	cd packages/mediapipe-task-vision && dart tool/download_object_detector.dart
	cd packages/mediapipe-task-vision && dart tool/download_image_tasks.dart
	cd packages/mediapipe-task-vision && dart tool/download_landmark_tasks.dart
	cd packages/mediapipe-task-vision && dart tool/download_segmenter_tasks.dart
	cd packages/mediapipe-task-vision && dart tool/download_interactive_segmenter.dart
	$(MAKE) models_embedding
	$(MAKE) models_proofreader
	$(MAKE) models_summarizer

analyze:
	@for package in $(ANALYZE_PACKAGES); do (cd "$$package" && dart analyze --fatal-infos) || exit $$?; done

format:
	@for package in $(ALL_PACKAGES); do (cd "$$package" && dart format .) || exit $$?; done
	@cd gallery && $(GALLERY_FORMAT) $(GALLERY_SOURCES)

check_format:
	@for package in $(ALL_PACKAGES); do (cd "$$package" && dart format --output=none --set-exit-if-changed .) || exit $$?; done
	@cd gallery && $(GALLERY_FORMAT) --output=none --set-exit-if-changed $(GALLERY_SOURCES)

# Regenerate against the checked-in headers, never a floating upstream checkout.
generate:
	$(MAKE) generate_text
	$(MAKE) generate_vision

# The text bindings are adapted from Google's wheel's ctypes definitions;
# the retired 2024 headers must not regenerate them.
generate_text:
	cd packages/mediapipe-task-text && dart test test/classic_text_abi_test.dart --reporter expanded

generate_vision:
	cd packages/mediapipe-task-vision && dart tool/generate_bindings.dart

test:
	$(MAKE) models
	$(MAKE) test_only

test_only:
	$(MAKE) test_core
	$(MAKE) test_text
	$(MAKE) test_audio
	$(MAKE) test_vision

test_core:
	cd packages/mediapipe-core && dart test --reporter expanded

test_text:
	cd packages/mediapipe-task-text && dart test --reporter expanded

.PHONY: test_audio models_audio test_audio_stream_bridge test_audio_web
models_audio:
	cd packages/mediapipe-task-audio && dart run tool/download_model.dart

test_audio:
	$(MAKE) test_audio_stream_bridge
	cd packages/mediapipe-task-audio && dart test --reporter expanded

# The audio stream's callback-copy bridge, its slots and their threads,
# under AddressSanitizer.
test_audio_stream_bridge:
	mkdir -p build/codex-tmp
	clang -Wall -Wextra -Werror -g -fsanitize=address -pthread packages/mediapipe-task-audio/native/audio_stream_bridge.c packages/mediapipe-task-audio/native/audio_stream_bridge_test.c -o build/codex-tmp/audio_stream_bridge_test
	build/codex-tmp/audio_stream_bridge_test

# The emulated stream and the decoders in Chrome, compiled to JavaScript and
# to WebAssembly.
test_audio_web:
	cd packages/mediapipe-task-audio && flutter test --platform chrome test/web --reporter expanded
	cd packages/mediapipe-task-audio && flutter test --platform chrome --wasm test/web --reporter expanded

# The C ABI sizes the vision bindings assume, against the vendored headers.
test_vision:
	clang++ -std=c++17 -fsyntax-only -Wall -Wextra -Werror -I packages/mediapipe-core/native/include packages/mediapipe-task-vision/tool/abi_check.cc
	cd packages/mediapipe-task-vision && dart test --reporter expanded --exclude-tags isolated
	cd packages/mediapipe-task-vision && dart test --reporter expanded --tags isolated

.PHONY: test_vision_web
test_vision_web:
	cd packages/mediapipe-task-vision && flutter test --platform chrome test/web --reporter expanded

test_vision_flutter:
	cd packages/mediapipe-task-vision && python3 tool/test_flutter_macos.py

.PHONY: models_text
models_text:
	cd packages/mediapipe-task-text && dart tool/download_classic_text.dart

.PHONY: models_embedding test_embedding_macos
models_embedding:
	cd packages/mediapipe-task-text && dart tool/download_embedding_gemma.dart

test_embedding_macos:
	cd packages/mediapipe-task-text && python3 -B tool/test_embedding_macos.py

# EmbeddingGemma, Proofreader and Summarizer against Google's wheel for this
# host, as the Linux and Windows CI runners test them.
.PHONY: test_modern_text
test_modern_text:
	python3 -B tool/test_modern_text.py

.PHONY: test_modern_task_matrix
test_modern_task_matrix:
	cd tool/task_benchmarks && dart pub get
	cd packages/mediapipe-task-text && dart tool/download_embedding_gemma.dart
	cd packages/mediapipe-task-text && dart tool/download_proofreader.dart
	cd packages/mediapipe-task-text && dart tool/download_summarizer.dart
	cd packages/mediapipe-task-vision && dart tool/download_interactive_segmenter.dart
	python3 -B tool/task_benchmarks/run_macos.py

.PHONY: models_proofreader test_text_stream_bridge
models_proofreader:
	cd packages/mediapipe-task-text && dart tool/download_proofreader.dart

test_text_stream_bridge:
	mkdir -p build/codex-tmp
	clang -Wall -Wextra -Werror -g -fsanitize=address -pthread packages/mediapipe-task-text/native/text_stream_bridge.c packages/mediapipe-task-text/native/text_stream_bridge_test.c -o build/codex-tmp/text_stream_bridge_test
	build/codex-tmp/text_stream_bridge_test

.PHONY: models_summarizer
models_summarizer:
	cd packages/mediapipe-task-text && dart tool/download_summarizer.dart

# Run sequentially even when make is invoked with -j.
ci:
	$(MAKE) get
	$(MAKE) models
	$(MAKE) analyze
	$(MAKE) check_format
	$(MAKE) test_only
	$(MAKE) test_vision_flutter
