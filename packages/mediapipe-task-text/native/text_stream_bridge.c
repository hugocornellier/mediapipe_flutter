// Copyright 2026. Licensed under Apache-2.0 (see the repository LICENSE).
#include "text_stream_bridge.h"

#include <stddef.h>
#include <stdlib.h>
#include <string.h>

struct MpFlutterTextStreamContext {
  MpFlutterTextSink sink;
};

MpFlutterTextStreamContext* MpFlutterTextStreamCreate(MpFlutterTextSink sink) {
  if (!sink) return NULL;
  MpFlutterTextStreamContext* context = malloc(sizeof(*context));
  if (context) context->sink = sink;
  return context;
}

void MpFlutterTextStreamFree(MpFlutterTextStreamContext* context) {
  free(context);
}

void MpFlutterTextEventFree(MpFlutterTextEvent* event) {
  if (!event) return;
  free(event->text);
  free(event->error);
  if (event->corrections) {
    for (int i = 0; i < event->corrections_count; ++i) {
      free((void*)event->corrections[i].text);
    }
  }
  free(event->corrections);
  free(event);
}

static char* copy_string(const char* value, MpFlutterTextEvent* event) {
  if (!value) return NULL;
  char* copy = strdup(value);
  if (!copy) event->copy_error = 1;
  return copy;
}

void MpFlutterProofreaderCallback(void* userdata,
                                 const MpFlutterProofreaderStreamView* result,
                                 const char* error) {
  // Read the sink before notifying Dart. After notification, this callback
  // never touches context or event again: a terminal receiver may free them.
  MpFlutterTextSink sink = ((MpFlutterTextStreamContext*)userdata)->sink;
  const bool terminal = error != NULL || result == NULL || result->done;
  MpFlutterTextEvent* event = calloc(1, sizeof(*event));
  if (event) {
    event->error = copy_string(error, event);
    if (!error && !result) event->copy_error = 2;
    if (result && !error) {
      event->text = copy_string(result->chunk, event);
      if (result->corrections_count < 0 ||
          (result->corrections_count > 0 && !result->corrections)) {
        event->copy_error = 2;
      } else if (result->corrections_count > 0) {
        event->corrections = calloc((size_t)result->corrections_count,
                                    sizeof(*event->corrections));
        if (!event->corrections) {
          event->copy_error = 1;
        } else {
          event->corrections_count = result->corrections_count;
          for (int i = 0; i < result->corrections_count; ++i) {
            event->corrections[i].type = result->corrections[i].type;
            event->corrections[i].text = copy_string(result->corrections[i].text, event);
          }
        }
      }
    }
  }
  // NativeCallable.listener queues this owned pointer to the Dart worker.
  // Even allocation failure preserves the terminal flag, so the worker can
  // drain the native request before releasing the callback/context.
  sink(event, terminal);
}

void MpFlutterSummarizerCallback(void* userdata,
                                const MpFlutterSummarizerStreamView* result,
                                const char* error) {
  // Map Google's simpler callback view onto the same owned event protocol.
  // This stack view is copied synchronously before this function returns.
  if (result) {
    const MpFlutterProofreaderStreamView view = {
        result->chunk, 0, NULL, result->done};
    MpFlutterProofreaderCallback(userdata, &view, error);
  } else {
    MpFlutterProofreaderCallback(userdata, NULL, error);
  }
}
