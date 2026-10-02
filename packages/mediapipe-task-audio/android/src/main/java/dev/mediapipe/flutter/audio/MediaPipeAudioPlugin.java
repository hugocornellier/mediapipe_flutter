package dev.mediapipe.flutter.audio;

import android.content.Context;
import com.google.mediapipe.tasks.audio.audioclassifier.AudioClassifier;
import com.google.mediapipe.tasks.audio.audioclassifier.AudioClassifier.AudioClassifierOptions;
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
 * Google's unmodified Audio Classifier (tasks-audio 1.0.0) for mediapipe_audio, on clips.
 * Core's {@link TaskHost} creates, runs and closes every task on one worker thread; results
 * travel in the JSON shape of Google's JavaScript API, which the Dart package decodes on every
 * platform.
 */
public final class MediaPipeAudioPlugin implements FlutterPlugin {
  private Context context;
  private TaskHost host;

  @Override public void onAttachedToEngine(FlutterPluginBinding binding) {
    context = binding.getApplicationContext();
    host = new TaskHost(binding.getBinaryMessenger(), "mediapipe_audio/android",
        "MediaPipe audio tasks", this::create, Set.of("run"), null);
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
    AudioClassifierOptions.Builder options = AudioClassifierOptions.builder()
        .setBaseOptions(base.build())
        .setRunningMode(RunningMode.AUDIO_CLIPS);
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
        return classify(classifier, request);
      }

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
}
