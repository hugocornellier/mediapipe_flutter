// Copyright 2026. Licensed under Apache-2.0 (see the repository LICENSE).
#ifndef MEDIAPIPE_FLUTTER_TEXT_STREAM_BRIDGE_H_
#define MEDIAPIPE_FLUTTER_TEXT_STREAM_BRIDGE_H_

#include <stdbool.h>

// Official mediapipe==1.0.1 Python ctypes layouts, text/text_proofreader.py.
// These are callback views owned by Google and valid only during the callback.
typedef struct {
  int type;
  const char* text;
} MpFlutterCorrectionView;

typedef struct {
  const char* chunk;
  int corrections_count;
  const MpFlutterCorrectionView* corrections;
  bool done;
} MpFlutterProofreaderStreamView;

typedef struct {
  const char* chunk;
  bool done;
} MpFlutterSummarizerStreamView;

// A deep copy owned by the Dart receiver, freed with MpFlutterTextEventFree.
typedef struct {
  char* text;
  int corrections_count;
  MpFlutterCorrectionView* corrections;
  char* error;
  int copy_error;  // 0: success, 1: allocation failure, 2: invalid native payload.
} MpFlutterTextEvent;

typedef void (*MpFlutterTextSink)(MpFlutterTextEvent*, bool terminal);
typedef struct MpFlutterTextStreamContext MpFlutterTextStreamContext;

MpFlutterTextStreamContext* MpFlutterTextStreamCreate(MpFlutterTextSink sink);
void MpFlutterTextStreamFree(MpFlutterTextStreamContext* context);
void MpFlutterTextEventFree(MpFlutterTextEvent* event);
void MpFlutterProofreaderCallback(void* context,
                                 const MpFlutterProofreaderStreamView* result,
                                 const char* error);
void MpFlutterSummarizerCallback(void* context,
                                const MpFlutterSummarizerStreamView* result,
                                const char* error);

#endif
