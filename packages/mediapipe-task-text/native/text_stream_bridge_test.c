// Exercise the foreign-thread ownership boundary under AddressSanitizer.
#include "text_stream_bridge.h"
#include <assert.h>
#include <pthread.h>
#include <stdlib.h>
#include <string.h>

static MpFlutterTextEvent* received;
static bool finished;

static void sink(MpFlutterTextEvent* event, bool terminal) {
  assert(!received);
  received = event;
  finished = terminal;
}

static void* deliver(void* context) {
  char* text = strdup("café ☕");
  char* edit = strdup("received");
  MpFlutterCorrectionView corrections[] = {{1, edit}, {0, NULL}};
  MpFlutterProofreaderStreamView view = {text, 2, corrections, false};
  MpFlutterProofreaderCallback(context, &view, NULL);
  // Google may reuse/free these immediately on return. The receiver runs later.
  memset(text, 'x', strlen(text));
  memset(edit, 'x', strlen(edit));
  free(text);
  free(edit);
  memset(corrections, 0, sizeof(corrections));
  return NULL;
}

static void release(void) {
  MpFlutterTextEventFree(received);
  received = NULL;
}

int main(void) {
  assert(!MpFlutterTextStreamCreate(NULL));
  MpFlutterTextStreamContext* context = MpFlutterTextStreamCreate(sink);
  assert(context);
  pthread_t thread;
  assert(pthread_create(&thread, NULL, deliver, context) == 0);
  assert(pthread_join(thread, NULL) == 0);
  assert(received && !finished && received->copy_error == 0);
  assert(strcmp(received->text, "café ☕") == 0);
  assert(received->corrections_count == 2);
  assert(received->corrections[0].type == 1);
  assert(strcmp(received->corrections[0].text, "received") == 0);
  assert(received->corrections[1].text == NULL);
  release();

  MpFlutterProofreaderStreamView terminal = {NULL, 0, NULL, true};
  MpFlutterProofreaderCallback(context, &terminal, NULL);
  assert(finished && received->copy_error == 0 && !received->text);
  release();
  char error[] = "native failure";
  MpFlutterProofreaderCallback(context, NULL, error);
  memset(error, 'x', sizeof(error));
  assert(finished && strcmp(received->error, "native failure") == 0);
  release();
  MpFlutterProofreaderCallback(context, NULL, NULL);
  assert(finished && received->copy_error == 2);
  release();
  terminal.corrections_count = 1;
  MpFlutterProofreaderCallback(context, &terminal, NULL);
  assert(finished && received->copy_error == 2);
  release();
  terminal.corrections_count = -1;
  MpFlutterProofreaderCallback(context, &terminal, NULL);
  assert(finished && received->copy_error == 2);
  release();
  MpFlutterTextStreamFree(context);
  MpFlutterTextEventFree(NULL);
  return 0;
}
