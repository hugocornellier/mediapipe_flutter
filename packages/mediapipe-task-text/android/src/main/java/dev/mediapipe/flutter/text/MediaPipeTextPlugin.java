package dev.mediapipe.flutter.text;

import android.content.Context;
import android.os.Handler;
import android.os.Looper;
import com.google.mediapipe.tasks.components.containers.Category;
import com.google.mediapipe.tasks.components.containers.ClassificationResult;
import com.google.mediapipe.tasks.components.containers.Classifications;
import com.google.mediapipe.tasks.components.containers.Embedding;
import com.google.mediapipe.tasks.components.containers.EmbeddingResult;
import com.google.mediapipe.tasks.core.BaseOptions;
import com.google.mediapipe.tasks.text.languagedetector.LanguageDetector;
import com.google.mediapipe.tasks.text.languagedetector.LanguageDetector.LanguageDetectorOptions;
import com.google.mediapipe.tasks.text.languagedetector.LanguagePrediction;
import com.google.mediapipe.tasks.text.textclassifier.TextClassifier;
import com.google.mediapipe.tasks.text.textclassifier.TextClassifier.TextClassifierOptions;
import com.google.mediapipe.tasks.text.textembedder.TextEmbedder;
import com.google.mediapipe.tasks.text.textembedder.TextEmbedder.TextEmbedderOptions;
import io.flutter.embedding.engine.plugins.FlutterPlugin;
import io.flutter.plugin.common.MethodCall;
import io.flutter.plugin.common.MethodChannel;
import java.nio.ByteBuffer;
import java.util.ArrayList;
import java.util.HashMap;
import java.util.List;
import java.util.Map;
import java.util.Optional;
import java.util.concurrent.ExecutorService;
import java.util.concurrent.Executors;
import java.util.function.Function;

/**
 * Google's unmodified text tasks (tasks-text 1.0.0) for mediapipe_flutter_text. One worker
 * thread creates, runs and closes every task; results travel in the JSON shape of Google's
 * JavaScript API, which the Dart package decodes on every platform.
 */
public final class MediaPipeTextPlugin implements FlutterPlugin, MethodChannel.MethodCallHandler {
  /** One official task and the model buffer it reads. Only the worker touches it. */
  private static final class Task {
    final AutoCloseable task;
    final Function<String, Map<String, Object>> run;
    final ByteBuffer model;

    Task(AutoCloseable task, Function<String, Map<String, Object>> run, ByteBuffer model) {
      this.task = task;
      this.run = run;
      this.model = model;
    }
  }

  private MethodChannel channel;
  private Context context;
  private ExecutorService worker;
  private final Handler main = new Handler(Looper.getMainLooper());
  private final Map<Integer, Task> tasks = new HashMap<>();
  private int nextId;

  @Override public void onAttachedToEngine(FlutterPluginBinding binding) {
    context = binding.getApplicationContext();
    worker = Executors.newSingleThreadExecutor(r -> new Thread(r, "MediaPipe text tasks"));
    channel = new MethodChannel(binding.getBinaryMessenger(), "mediapipe_flutter_text/android");
    channel.setMethodCallHandler(this);
  }

  @Override public void onDetachedFromEngine(FlutterPluginBinding binding) {
    channel.setMethodCallHandler(null);
    worker.execute(() -> {
      for (Task task : tasks.values()) close(task);
      tasks.clear();
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
          case "run": {
            Task task = tasks.get(number(call, "id"));
            if (task == null) throw new IllegalStateException("MediaPipe text task is closed");
            value = task.run.apply(call.argument("text"));
            break;
          }
          default: {
            Task task = tasks.remove(number(call, "id"));
            if (task != null) close(task);
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
    String name = call.argument("task");
    Task task;
    switch (name == null ? "" : name) {
      case "text_classifier": {
        TextClassifierOptions.Builder options =
            TextClassifierOptions.builder().setBaseOptions(base.build());
        if (call.hasArgument("displayNamesLocale")) {
          options.setDisplayNamesLocale(call.argument("displayNamesLocale"));
        }
        if (call.hasArgument("maxResults")) options.setMaxResults(number(call, "maxResults"));
        if (call.hasArgument("scoreThreshold")) {
          options.setScoreThreshold(decimal(call, "scoreThreshold"));
        }
        if (call.hasArgument("categoryAllowlist")) {
          options.setCategoryAllowlist(call.argument("categoryAllowlist"));
        }
        if (call.hasArgument("categoryDenylist")) {
          options.setCategoryDenylist(call.argument("categoryDenylist"));
        }
        TextClassifier classifier = TextClassifier.createFromOptions(context, options.build());
        task = new Task(classifier,
            text -> classifications(classifier.classify(text).classificationResult()), model);
        break;
      }
      case "text_embedder": {
        TextEmbedderOptions.Builder options = TextEmbedderOptions.builder()
            .setBaseOptions(base.build())
            .setL2Normalize(Boolean.TRUE.equals(call.argument("l2Normalize")))
            .setQuantize(Boolean.TRUE.equals(call.argument("quantize")));
        TextEmbedder embedder = TextEmbedder.createFromOptions(context, options.build());
        task = new Task(embedder, text -> embeddings(embedder.embed(text).embeddingResult()), model);
        break;
      }
      case "language_detector": {
        LanguageDetectorOptions.Builder options =
            LanguageDetectorOptions.builder().setBaseOptions(base.build());
        if (call.hasArgument("displayNamesLocale")) {
          options.setDisplayNamesLocale(call.argument("displayNamesLocale"));
        }
        if (call.hasArgument("maxResults")) options.setMaxResults(number(call, "maxResults"));
        if (call.hasArgument("scoreThreshold")) {
          options.setScoreThreshold(decimal(call, "scoreThreshold"));
        }
        if (call.hasArgument("categoryAllowlist")) {
          options.setCategoryAllowlist(call.argument("categoryAllowlist"));
        }
        if (call.hasArgument("categoryDenylist")) {
          options.setCategoryDenylist(call.argument("categoryDenylist"));
        }
        LanguageDetector detector = LanguageDetector.createFromOptions(context, options.build());
        task = new Task(detector, text -> {
          List<Object> languages = new ArrayList<>();
          for (LanguagePrediction prediction : detector.detect(text).languagesAndScores()) {
            Map<String, Object> value = new HashMap<>();
            value.put("languageCode", prediction.languageCode());
            value.put("probability", (double) prediction.probability());
            languages.add(value);
          }
          Map<String, Object> result = new HashMap<>();
          result.put("languages", languages);
          return result;
        }, model);
        break;
      }
      default: throw new IllegalArgumentException("Unsupported MediaPipe text task: " + name);
    }
    int id = nextId++;
    tasks.put(id, task);
    return id;
  }

  /** A classification result as Google's JavaScript API shapes it. */
  static Map<String, Object> classifications(ClassificationResult source) {
    List<Object> heads = new ArrayList<>();
    for (Classifications head : source.classifications()) {
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
    Map<String, Object> result = new HashMap<>();
    result.put("classifications", heads);
    result.put("timestampMs", timestamp(source.timestampMs()));
    return result;
  }

  private static Map<String, Object> embeddings(EmbeddingResult source) {
    List<Object> embeddings = new ArrayList<>();
    for (Embedding embedding : source.embeddings()) {
      Map<String, Object> value = new HashMap<>();
      float[] floats = embedding.floatEmbedding();
      if (floats != null && floats.length > 0) {
        value.put("floatEmbedding", floats);
      } else {
        // Unsigned bytes, as the JavaScript API's Uint8Array holds them.
        byte[] quantized = embedding.quantizedEmbedding();
        int[] values = new int[quantized.length];
        for (int i = 0; i < quantized.length; i++) values[i] = quantized[i] & 0xff;
        value.put("quantizedEmbedding", values);
      }
      value.put("headIndex", embedding.headIndex());
      value.put("headName", embedding.headName().orElse(""));
      embeddings.add(value);
    }
    Map<String, Object> result = new HashMap<>();
    result.put("embeddings", embeddings);
    result.put("timestampMs", timestamp(source.timestampMs()));
    return result;
  }

  private static Long timestamp(Optional<Long> value) {
    return value.orElse(null);
  }

  private static int number(MethodCall call, String key) {
    return ((Number) call.argument(key)).intValue();
  }

  private static float decimal(MethodCall call, String key) {
    return ((Number) call.argument(key)).floatValue();
  }

  private static void close(Task task) {
    try {
      task.task.close();
    } catch (Exception ignored) {
      // Closing is best effort; the task is gone either way.
    }
  }
}
