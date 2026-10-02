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
import com.google.mediapipe.tasks.text.textembedder.TextEmbedder.EmbeddingType;
import com.google.mediapipe.tasks.text.textembedder.TextEmbedder.TextEmbedderOptions;
import com.google.mediapipe.tasks.text.textembedder.TextEmbedder.TextFormatContext;
import com.google.mediapipe.tasks.text.textembedder.TextEmbedder.TextRole;
import com.google.mediapipe.tasks.text.textproofreader.TextProofreader;
import com.google.mediapipe.tasks.text.textproofreader.TextProofreader.TextProofreaderOptions;
import com.google.mediapipe.tasks.text.textproofreader.TextProofreaderResult;
import com.google.mediapipe.tasks.text.textproofreader.TextProofreaderStreamingResult;
import com.google.mediapipe.tasks.text.textsummarizer.TextSummarizer;
import com.google.mediapipe.tasks.text.textsummarizer.TextSummarizer.TextSummarizerOptions;
import com.google.mediapipe.tasks.text.textsummarizer.TextSummarizerResult;
import com.google.mediapipe.tasks.text.textsummarizer.TextSummarizerStreamingResult;
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

// TODO: Share the worker thread, model buffers and channel handling with
// MediaPipeAudioPlugin. See tool/SHARED_CODE.md at the repository root.
/**
 * Google's unmodified text tasks (tasks-text 1.0.0) for mediapipe_text. One worker
 * thread creates, runs and closes every task; results travel in the JSON shape of Google's
 * JavaScript API, which the Dart package decodes on every platform. The Proofreader and
 * Summarizer, which that API lacks, travel under the names of Google's Java getters, and
 * their streamed updates go back to Dart as {@code update} calls on the same channel.
 */
public final class MediaPipeTextPlugin implements FlutterPlugin, MethodChannel.MethodCallHandler {
  /** Runs one completed request from its method call. */
  private interface Runner {
    Map<String, Object> run(MethodCall call);
  }

  /** Starts one streamed request; its updates arrive through {@link #emit}. */
  private interface Streamer {
    void stream(String text, int request);
  }

  /** One official task and how to run it. Only the worker touches it. */
  private static final class Task {
    final AutoCloseable task;
    final Runner run;
    final Streamer stream;

    Task(AutoCloseable task, Runner run, Streamer stream) {
      this.task = task;
      this.run = run;
      this.stream = stream;
    }
  }

  private MethodChannel channel;
  private Context context;
  private ExecutorService worker;
  private final Handler main = new Handler(Looper.getMainLooper());
  private final Map<Integer, Task> tasks = new HashMap<>();
  // Google's native task reads a direct model buffer in place, without a copy,
  // so each one is held here until its task is closed. A field that is only
  // written would not hold it: R8 removes such fields from release builds, the
  // buffer is collected, and inference reads freed memory.
  private final Map<Integer, ByteBuffer> modelBuffers = new HashMap<>();
  private int nextId;

  @Override public void onAttachedToEngine(FlutterPluginBinding binding) {
    context = binding.getApplicationContext();
    worker = Executors.newSingleThreadExecutor(r -> new Thread(r, "MediaPipe text tasks"));
    channel = new MethodChannel(binding.getBinaryMessenger(), "mediapipe_text/android");
    channel.setMethodCallHandler(this);
  }

  @Override public void onDetachedFromEngine(FlutterPluginBinding binding) {
    channel.setMethodCallHandler(null);
    worker.execute(() -> {
      for (Task task : tasks.values()) close(task);
      tasks.clear();
      modelBuffers.clear();
    });
    worker.shutdown();
  }

  @Override public void onMethodCall(MethodCall call, MethodChannel.Result reply) {
    switch (call.method) {
      case "create": case "run": case "stream": case "close": break;
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
            value = task.run.run(call);
            break;
          }
          case "stream": {
            Task task = tasks.get(number(call, "id"));
            if (task == null) throw new IllegalStateException("MediaPipe text task is closed");
            if (task.stream == null) {
              throw new UnsupportedOperationException("MediaPipe text task does not stream");
            }
            task.stream.stream(call.argument("text"), number(call, "request"));
            value = null;
            break;
          }
          default: {
            int id = number(call, "id");
            Task task = tasks.remove(id);
            if (task != null) close(task);
            modelBuffers.remove(id);
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
    } else if (call.argument("modelPath") != null) {
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
            input -> classifications(classifier.classify(text(input)).classificationResult()),
            null);
        break;
      }
      case "text_embedder": {
        TextEmbedderOptions.Builder options = TextEmbedderOptions.builder()
            .setBaseOptions(base.build())
            .setL2Normalize(Boolean.TRUE.equals(call.argument("l2Normalize")))
            .setQuantize(Boolean.TRUE.equals(call.argument("quantize")));
        TextEmbedder embedder = TextEmbedder.createFromOptions(context, options.build());
        task = new Task(embedder, input -> {
          TextFormatContext format = formatContext(input.argument("formatContext"));
          return embeddings((format == null
              ? embedder.embed(text(input))
              : embedder.embed(text(input), format)).embeddingResult());
        }, null);
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
        task = new Task(detector, input -> {
          List<Object> languages = new ArrayList<>();
          for (LanguagePrediction prediction : detector.detect(text(input)).languagesAndScores()) {
            Map<String, Object> value = new HashMap<>();
            value.put("languageCode", prediction.languageCode());
            value.put("probability", (double) prediction.probability());
            languages.add(value);
          }
          Map<String, Object> result = new HashMap<>();
          result.put("languages", languages);
          return result;
        }, null);
        break;
      }
      case "text_proofreader": {
        // Google's generative options read the model from a file and take no
        // cache directory; the Dart side refuses bytes and a cache directory.
        TextProofreaderOptions.Builder options = TextProofreaderOptions.builder()
            .setModelPath(call.argument("modelPath"));
        if (call.argument("maxNumTokens") != null) {
          options.setMaxNumTokens(number(call, "maxNumTokens"));
        }
        TextProofreader proofreader = TextProofreader.createFromOptions(context, options.build());
        task = new Task(proofreader,
            input -> proofreaderResult(proofreader.proofread(text(input))),
            (text, request) -> {
              boolean[] finished = {false};
              proofreader.proofreadStreaming(text, new TextProofreader.ProofreaderResultCallback() {
                @Override public void onNext(TextProofreaderStreamingResult value) {
                  if (value.isDone()) finished[0] = true;
                  emit(request, proofreaderStreamResult(value), null);
                }

                @Override public void onError(Throwable error) {
                  finished[0] = true;
                  emit(request, null, error.toString());
                }

                // Google ends every stream here; the final update normally
                // said so already.
                @Override public void onDone() {
                  if (finished[0]) return;
                  finished[0] = true;
                  Map<String, Object> last = new HashMap<>();
                  last.put("chunk", null);
                  last.put("corrections", new ArrayList<>());
                  last.put("done", true);
                  emit(request, last, null);
                }
              });
            });
        break;
      }
      case "text_summarizer": {
        TextSummarizerOptions.Builder options = TextSummarizerOptions.builder()
            .setModelPath(call.argument("modelPath"))
            .setMode(TextSummarizerOptions.Mode.valueOf(call.argument("mode")));
        if (call.argument("maxNumTokens") != null) {
          options.setMaxNumTokens(number(call, "maxNumTokens"));
        }
        TextSummarizer summarizer = TextSummarizer.createFromOptions(context, options.build());
        task = new Task(summarizer,
            input -> summarizerResult(summarizer.summarize(text(input))),
            (text, request) -> {
              boolean[] finished = {false};
              summarizer.summarizeStreaming(text, new TextSummarizer.SummarizationResultCallback() {
                @Override public void onNext(TextSummarizerStreamingResult value) {
                  if (value.isDone()) finished[0] = true;
                  emit(request, summarizerStreamResult(value), null);
                }

                @Override public void onError(Throwable error) {
                  finished[0] = true;
                  emit(request, null, error.toString());
                }

                @Override public void onDone() {
                  if (finished[0]) return;
                  finished[0] = true;
                  Map<String, Object> last = new HashMap<>();
                  last.put("chunk", null);
                  last.put("done", true);
                  emit(request, last, null);
                }
              });
            });
        break;
      }
      default: throw new IllegalArgumentException("Unsupported MediaPipe text task: " + name);
    }
    int id = nextId++;
    tasks.put(id, task);
    if (model != null) modelBuffers.put(id, model);
    return id;
  }

  private static String text(MethodCall call) {
    String text = call.argument("text");
    if (text == null) throw new IllegalArgumentException("Supply text");
    return text;
  }

  /** Google's {@code TextFormatContext} from its JavaScript {@code TextFormatOptions} names. */
  private static TextFormatContext formatContext(Map<String, Object> options) {
    if (options == null) return null;
    TextFormatContext.Builder format = TextFormatContext.builder()
        .setTaskType(EmbeddingType.valueOf((String) options.get("type")))
        .setRole(TextRole.valueOf((String) options.getOrDefault("textRole", "QUERY")));
    if (options.get("title") != null) format.setTitle((String) options.get("title"));
    return format.build();
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

  /** Google's corrections, each typed by its enum name (SAME, INSERTION, DELETION). */
  private static List<Object> corrections(List<TextProofreaderResult.Correction> source) {
    List<Object> values = new ArrayList<>();
    if (source == null) return values;
    for (TextProofreaderResult.Correction correction : source) {
      Map<String, Object> value = new HashMap<>();
      value.put("type", correction.getType().name());
      value.put("text", correction.getText());
      values.add(value);
    }
    return values;
  }

  private static Map<String, Object> proofreaderResult(TextProofreaderResult source) {
    Map<String, Object> result = new HashMap<>();
    result.put("proofreadText", source.getProofreadText());
    result.put("corrections", corrections(source.getCorrections()));
    return result;
  }

  private static Map<String, Object> proofreaderStreamResult(
      TextProofreaderStreamingResult source) {
    Map<String, Object> result = new HashMap<>();
    result.put("chunk", source.getChunk());
    result.put("corrections", corrections(source.getCorrections()));
    result.put("done", source.isDone());
    return result;
  }

  private static Map<String, Object> summarizerResult(TextSummarizerResult source) {
    Map<String, Object> result = new HashMap<>();
    result.put("summary", source.getSummary());
    return result;
  }

  private static Map<String, Object> summarizerStreamResult(
      TextSummarizerStreamingResult source) {
    Map<String, Object> result = new HashMap<>();
    result.put("chunk", source.getChunk());
    result.put("done", source.isDone());
    return result;
  }

  /** Sends one streamed update, or Google's error, to Dart on the platform thread. */
  private void emit(int request, Map<String, Object> result, String error) {
    Map<String, Object> event = new HashMap<>();
    event.put("request", request);
    if (result != null) event.put("result", result);
    if (error != null) event.put("error", error);
    main.post(() -> channel.invokeMethod("update", event));
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
