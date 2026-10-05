package dev.mediapipe.flutter.audio;

import android.content.Context;
import com.google.mediapipe.tasks.audio.audioclassifier.AudioClassifier;
import com.google.mediapipe.tasks.audio.audioclassifier.AudioClassifier.AudioClassifierOptions;
import com.google.mediapipe.tasks.audio.audioclassifier.AudioClassifierResult;
import com.google.mediapipe.tasks.audio.core.RunningMode;
import com.google.mediapipe.tasks.components.containers.AudioData;
import com.google.mediapipe.tasks.components.containers.AudioData.AudioDataFormat;
import com.google.mediapipe.tasks.components.containers.ClassificationResult;
import com.google.mediapipe.tasks.core.BaseOptions;
import dev.mediapipe.flutter.core.TaskHost;
import dev.mediapipe.flutter.core.TaskJson;
import io.flutter.embedding.engine.plugins.FlutterPlugin;
import io.flutter.plugin.common.MethodCall;
import java.util.ArrayList;
import java.util.List;
import java.util.Map;
import java.util.Set;

/**
 * Google's unmodified Audio Classifier (tasks-audio 1.0.0) for mediapipe_audio, on clips or on
 * an audio stream. Core's {@link TaskHost} creates, runs and closes every task on one worker
 * thread; results travel in the JSON shape of Google's JavaScript API, which the Dart package
 * decodes on every platform. A stream's results arrive as {@code update} calls tagged with the
 * request the Dart side chose when it created the task.
 */
public final class MediaPipeAudioPlugin implements FlutterPlugin {
  private Context context;
  private TaskHost host;

  @Override public void onAttachedToEngine(FlutterPluginBinding binding) {
    context = binding.getApplicationContext();
    host = new TaskHost(binding.getBinaryMessenger(), "mediapipe_audio/android",
        "MediaPipe audio tasks", this::create, Set.of("run", "send"), null);
  }

  @Override public void onDetachedFromEngine(FlutterPluginBinding binding) {
    host.detach();
  }

  private TaskHost.Task create(MethodCall call, TaskHost.Model model) {
    BaseOptions.Builder base = BaseOptions.builder();
    if (model.bytes() != null) {
      base.setModelAssetBuffer(model.direct());
    } else {
      base.setModelAssetPath(model.path());
    }
    boolean stream = "AUDIO_STREAM".equals(call.argument("runningMode"));
    AudioClassifierOptions.Builder options = AudioClassifierOptions.builder()
        .setBaseOptions(base.build())
        .setRunningMode(stream ? RunningMode.AUDIO_STREAM : RunningMode.AUDIO_CLIPS);
    if (stream) {
      // Google requires the listener in stream mode. It runs on one of
      // MediaPipe's threads; emit posts each result to the platform thread,
      // so a result of the close reaches Dart before the reply to the close.
      int request = TaskHost.number(call, "request");
      options.setResultListener(result -> host.emit(request, streamResult(result), null));
      options.setErrorListener(error -> host.emit(request, null, error.toString()));
    }
    if (call.hasArgument("maxResults")) {
      options.setMaxResults(TaskHost.number(call, "maxResults"));
    }
    if (call.hasArgument("scoreThreshold")) {
      options.setScoreThreshold(TaskHost.decimal(call, "scoreThreshold"));
    }
    if (call.hasArgument("displayNamesLocale")) {
      options.setDisplayNamesLocale(call.argument("displayNamesLocale"));
    }
    if (call.hasArgument("categoryAllowlist")) {
      options.setCategoryAllowlist(call.argument("categoryAllowlist"));
    }
    if (call.hasArgument("categoryDenylist")) {
      options.setCategoryDenylist(call.argument("categoryDenylist"));
    }
    AudioClassifier classifier = AudioClassifier.createFromOptions(context, options.build());
    return new TaskHost.Task() {
      @Override public Object call(String method, MethodCall request) {
        if (method.equals("send")) {
          send(classifier, request);
          return null;
        }
        return classify(classifier, request);
      }

      // In stream mode Google's close flushes the tail and waits for its
      // result, which the listener has emitted by the time this returns.
      @Override public void close() {
        classifier.close();
      }
    };
  }

  /** Classifies one mono clip; one result per chunk the model reads, in order. */
  private static List<Object> classify(AudioClassifier classifier, MethodCall call) {
    float[] samples = call.argument("samples");
    float rate = TaskHost.decimal(call, "sampleRate");
    AudioData audio = AudioData.create(
        AudioDataFormat.builder().setNumOfChannels(1).setSampleRate(rate).build(), samples.length);
    audio.load(samples);
    List<Object> chunks = new ArrayList<>();
    for (ClassificationResult chunk : classifier.classify(audio).classificationResults()) {
      Map<String, Object> value = TaskJson.classifications(chunk);
      // Google's audio chunks are always stamped; a missing stamp reads as 0.
      value.put("timestampMs", chunk.timestampMs().orElse(0L));
      chunks.add(value);
    }
    return chunks;
  }

  /**
   * Hands one block of a stream to Google: its interleaved samples, as many channels as the
   * block has (Google mixes them down for a mono model), at its rate and timestamp.
   */
  private static void send(AudioClassifier classifier, MethodCall call) {
    float[] samples = call.argument("samples");
    int channels = TaskHost.number(call, "channels");
    AudioData audio = AudioData.create(
        AudioDataFormat.builder()
            .setNumOfChannels(channels)
            .setSampleRate(TaskHost.decimal(call, "sampleRate"))
            .build(),
        samples.length / channels);
    audio.load(samples);
    classifier.classifyAsync(audio, TaskHost.wholeNumber(call, "timestampMs"));
  }

  /**
   * One window's result: its one classification result, stamped with the time Google gives the
   * result, which for the tail its close flushes is Google's sentinel rather than a time.
   */
  private static Map<String, Object> streamResult(AudioClassifierResult result) {
    Map<String, Object> value = TaskJson.classifications(result.classificationResults().get(0));
    value.put("timestampMs", result.timestampMs());
    return value;
  }
}
