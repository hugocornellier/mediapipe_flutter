package dev.mediapipe.flutter.audio;

import android.content.Context;
import android.os.Handler;
import android.os.Looper;
import com.google.mediapipe.tasks.audio.audioclassifier.AudioClassifier;
import com.google.mediapipe.tasks.audio.audioclassifier.AudioClassifier.AudioClassifierOptions;
import com.google.mediapipe.tasks.audio.core.RunningMode;
import com.google.mediapipe.tasks.components.containers.AudioData;
import com.google.mediapipe.tasks.components.containers.AudioData.AudioDataFormat;
import com.google.mediapipe.tasks.components.containers.Category;
import com.google.mediapipe.tasks.components.containers.ClassificationResult;
import com.google.mediapipe.tasks.components.containers.Classifications;
import com.google.mediapipe.tasks.core.BaseOptions;
import io.flutter.embedding.engine.plugins.FlutterPlugin;
import io.flutter.plugin.common.MethodCall;
import io.flutter.plugin.common.MethodChannel;
import java.nio.ByteBuffer;
import java.util.ArrayList;
import java.util.HashMap;
import java.util.List;
import java.util.Map;
import java.util.concurrent.ExecutorService;
import java.util.concurrent.Executors;

// TODO: Share the worker thread, model buffers and channel handling with
// MediaPipeTextPlugin. See tool/SHARED_CODE.md at the repository root.
/**
 * Google's unmodified Audio Classifier (tasks-audio 1.0.0) for mediapipe_audio, on
 * clips. One worker thread creates, runs and closes every task; results travel in the JSON shape
 * of Google's JavaScript API, which the Dart package decodes on every platform.
 */
public final class MediaPipeAudioPlugin implements FlutterPlugin, MethodChannel.MethodCallHandler {
  private MethodChannel channel;
  private Context context;
  private ExecutorService worker;
  private final Handler main = new Handler(Looper.getMainLooper());
  // Only the worker touches these.
  private final Map<Integer, AudioClassifier> tasks = new HashMap<>();
  // Google's native task reads a direct model buffer in place, without a copy,
  // so each one is held here until its task is closed. A field that is only
  // written would not hold it: R8 removes such fields from release builds, the
  // buffer is collected, and inference reads freed memory.
  private final Map<Integer, ByteBuffer> modelBuffers = new HashMap<>();
  private int nextId;

  @Override public void onAttachedToEngine(FlutterPluginBinding binding) {
    context = binding.getApplicationContext();
    worker = Executors.newSingleThreadExecutor(r -> new Thread(r, "MediaPipe audio tasks"));
    channel = new MethodChannel(binding.getBinaryMessenger(), "mediapipe_audio/android");
    channel.setMethodCallHandler(this);
  }

  @Override public void onDetachedFromEngine(FlutterPluginBinding binding) {
    channel.setMethodCallHandler(null);
    worker.execute(() -> {
      for (AudioClassifier classifier : tasks.values()) classifier.close();
      tasks.clear();
      modelBuffers.clear();
    });
    worker.shutdown();
  }

  @Override public void onMethodCall(MethodCall call, MethodChannel.Result reply) {
    switch (call.method) {
      case "create": case "run": case "close": break;
      default: reply.notImplemented(); return;
    }
    worker.execute(() -> {
      try {
        Object value;
        switch (call.method) {
          case "create": value = create(call); break;
          case "run": value = classify(call); break;
          default: {
            int id = ((Number) call.argument("id")).intValue();
            AudioClassifier classifier = tasks.remove(id);
            try {
              if (classifier != null) classifier.close();
            } finally {
              modelBuffers.remove(id);
            }
            value = null;
          }
        }
        main.post(() -> reply.success(value));
      } catch (Exception | LinkageError error) {
        main.post(() -> reply.error("mediapipe", error.toString(), null));
      }
    });
  }

  private int create(MethodCall call) {
    BaseOptions.Builder base = BaseOptions.builder();
    byte[] bytes = call.argument("modelBytes");
    ByteBuffer model = null;
    if (bytes != null) {
      model = ByteBuffer.allocateDirect(bytes.length);
      model.put(bytes).rewind();
      base.setModelAssetBuffer(model);
    } else {
      base.setModelAssetPath(call.argument("modelPath"));
    }
    AudioClassifierOptions.Builder options = AudioClassifierOptions.builder()
        .setBaseOptions(base.build())
        .setRunningMode(RunningMode.AUDIO_CLIPS);
    if (call.hasArgument("maxResults")) {
      options.setMaxResults(((Number) call.argument("maxResults")).intValue());
    }
    if (call.hasArgument("scoreThreshold")) {
      options.setScoreThreshold(((Number) call.argument("scoreThreshold")).floatValue());
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
    int id = nextId++;
    tasks.put(id, AudioClassifier.createFromOptions(context, options.build()));
    if (model != null) modelBuffers.put(id, model);
    return id;
  }

  /** Classifies one mono clip; one result per chunk the model reads, in order. */
  private List<Object> classify(MethodCall call) {
    AudioClassifier classifier = tasks.get(((Number) call.argument("id")).intValue());
    if (classifier == null) throw new IllegalStateException("MediaPipe audio task is closed");
    float[] samples = call.argument("samples");
    float rate = ((Number) call.argument("sampleRate")).floatValue();
    AudioData audio = AudioData.create(
        AudioDataFormat.builder().setNumOfChannels(1).setSampleRate(rate).build(), samples.length);
    audio.load(samples);
    List<Object> chunks = new ArrayList<>();
    for (ClassificationResult chunk : classifier.classify(audio).classificationResults()) {
      List<Object> heads = new ArrayList<>();
      for (Classifications head : chunk.classifications()) {
        List<Object> categories = new ArrayList<>();
        for (Category category : head.categories()) {
          Map<String, Object> value = new HashMap<>();
          value.put("index", category.index());
          value.put("score", (double) category.score());
          value.put("categoryName", category.categoryName());
          value.put("displayName", category.displayName());
          categories.add(value);
        }
        Map<String, Object> value = new HashMap<>();
        value.put("categories", categories);
        value.put("headIndex", head.headIndex());
        value.put("headName", head.headName().orElse(""));
        heads.add(value);
      }
      Map<String, Object> value = new HashMap<>();
      value.put("classifications", heads);
      value.put("timestampMs", chunk.timestampMs().orElse(0L));
      chunks.add(value);
    }
    return chunks;
  }
}
