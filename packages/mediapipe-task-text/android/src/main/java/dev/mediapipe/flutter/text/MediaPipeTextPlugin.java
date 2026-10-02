package dev.mediapipe.flutter.text;

import android.content.Context;
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
import dev.mediapipe.flutter.core.TaskHost;
import dev.mediapipe.flutter.core.TaskJson;
import io.flutter.embedding.engine.plugins.FlutterPlugin;
import io.flutter.plugin.common.MethodCall;
import java.util.ArrayList;
import java.util.HashMap;
import java.util.List;
import java.util.Map;
import java.util.Set;

/**
 * Google's unmodified text tasks (tasks-text 1.0.0) for mediapipe_text. Core's {@link TaskHost}
 * creates, runs and closes every task on one worker thread; results travel in the JSON shape of
 * Google's JavaScript API, which the Dart package decodes on every platform. The Proofreader and
 * Summarizer, which that API lacks, travel under the names of Google's Java getters, and their
 * streamed updates go back to Dart as {@code update} calls on the same channel.
 */
public final class MediaPipeTextPlugin implements FlutterPlugin {
  /** Runs one completed request from its method call. */
  private interface Runner {
    Map<String, Object> run(MethodCall call);
  }

  /** Starts one streamed request; its updates arrive through {@link TaskHost#emit}. */
  private interface Streamer {
    void stream(String text, int request);
  }

  private Context context;
  private TaskHost host;

  @Override public void onAttachedToEngine(FlutterPluginBinding binding) {
    context = binding.getApplicationContext();
    host = new TaskHost(binding.getBinaryMessenger(), "mediapipe_text/android",
        "MediaPipe text tasks", this::create, Set.of("run"), null);
  }

  @Override public void onDetachedFromEngine(FlutterPluginBinding binding) {
    host.detach();
  }

  private static TaskHost.Task task(AutoCloseable task, Runner run, Streamer stream) {
    return new TaskHost.Task() {
      @Override public Object call(String method, MethodCall call) {
        return run.run(call);
      }

      @Override public void stream(MethodCall call, int request) {
        if (stream == null) throw new UnsupportedOperationException("MediaPipe task does not stream");
        stream.stream(text(call), request);
      }

      @Override public void close() {
        try {
          task.close();
        } catch (Exception ignored) {
          // Closing is best effort; the task is gone either way.
        }
      }
    };
  }

  private TaskHost.Task create(MethodCall call, TaskHost.Model model) {
    BaseOptions.Builder base = BaseOptions.builder();
    if (model.bytes() != null) {
      base.setModelAssetBuffer(model.direct());
    } else if (model.path() != null) {
      base.setModelAssetPath(model.path());
    }
    String name = call.argument("task");
    switch (name == null ? "" : name) {
      case "text_classifier": {
        TextClassifierOptions.Builder options =
            TextClassifierOptions.builder().setBaseOptions(base.build());
        if (call.hasArgument("displayNamesLocale")) {
          options.setDisplayNamesLocale(call.argument("displayNamesLocale"));
        }
        if (call.hasArgument("maxResults")) {
          options.setMaxResults(TaskHost.number(call, "maxResults"));
        }
        if (call.hasArgument("scoreThreshold")) {
          options.setScoreThreshold(TaskHost.decimal(call, "scoreThreshold"));
        }
        if (call.hasArgument("categoryAllowlist")) {
          options.setCategoryAllowlist(call.argument("categoryAllowlist"));
        }
        if (call.hasArgument("categoryDenylist")) {
          options.setCategoryDenylist(call.argument("categoryDenylist"));
        }
        TextClassifier classifier = TextClassifier.createFromOptions(context, options.build());
        return task(classifier,
            input -> TaskJson.classifications(classifier.classify(text(input)).classificationResult()),
            null);
      }
      case "text_embedder": {
        TextEmbedderOptions.Builder options = TextEmbedderOptions.builder()
            .setBaseOptions(base.build())
            .setL2Normalize(Boolean.TRUE.equals(call.argument("l2Normalize")))
            .setQuantize(Boolean.TRUE.equals(call.argument("quantize")));
        TextEmbedder embedder = TextEmbedder.createFromOptions(context, options.build());
        return task(embedder, input -> {
          TextFormatContext format = formatContext(input.argument("formatContext"));
          return TaskJson.embeddings((format == null
              ? embedder.embed(text(input))
              : embedder.embed(text(input), format)).embeddingResult());
        }, null);
      }
      case "language_detector": {
        LanguageDetectorOptions.Builder options =
            LanguageDetectorOptions.builder().setBaseOptions(base.build());
        if (call.hasArgument("displayNamesLocale")) {
          options.setDisplayNamesLocale(call.argument("displayNamesLocale"));
        }
        if (call.hasArgument("maxResults")) {
          options.setMaxResults(TaskHost.number(call, "maxResults"));
        }
        if (call.hasArgument("scoreThreshold")) {
          options.setScoreThreshold(TaskHost.decimal(call, "scoreThreshold"));
        }
        if (call.hasArgument("categoryAllowlist")) {
          options.setCategoryAllowlist(call.argument("categoryAllowlist"));
        }
        if (call.hasArgument("categoryDenylist")) {
          options.setCategoryDenylist(call.argument("categoryDenylist"));
        }
        LanguageDetector detector = LanguageDetector.createFromOptions(context, options.build());
        return task(detector, input -> {
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
      }
      case "text_proofreader": {
        // Google's generative options read the model from a file and take no
        // cache directory; the Dart side refuses bytes and a cache directory.
        TextProofreaderOptions.Builder options = TextProofreaderOptions.builder()
            .setModelPath(model.path());
        if (call.argument("maxNumTokens") != null) {
          options.setMaxNumTokens(TaskHost.number(call, "maxNumTokens"));
        }
        TextProofreader proofreader = TextProofreader.createFromOptions(context, options.build());
        return task(proofreader,
            input -> proofreaderResult(proofreader.proofread(text(input))),
            (text, request) -> {
              boolean[] finished = {false};
              proofreader.proofreadStreaming(text, new TextProofreader.ProofreaderResultCallback() {
                @Override public void onNext(TextProofreaderStreamingResult value) {
                  if (value.isDone()) finished[0] = true;
                  host.emit(request, proofreaderStreamResult(value), null);
                }

                @Override public void onError(Throwable error) {
                  finished[0] = true;
                  host.emit(request, null, error.toString());
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
                  host.emit(request, last, null);
                }
              });
            });
      }
      case "text_summarizer": {
        TextSummarizerOptions.Builder options = TextSummarizerOptions.builder()
            .setModelPath(model.path())
            .setMode(TextSummarizerOptions.Mode.valueOf(call.argument("mode")));
        if (call.argument("maxNumTokens") != null) {
          options.setMaxNumTokens(TaskHost.number(call, "maxNumTokens"));
        }
        TextSummarizer summarizer = TextSummarizer.createFromOptions(context, options.build());
        return task(summarizer,
            input -> summarizerResult(summarizer.summarize(text(input))),
            (text, request) -> {
              boolean[] finished = {false};
              summarizer.summarizeStreaming(text, new TextSummarizer.SummarizationResultCallback() {
                @Override public void onNext(TextSummarizerStreamingResult value) {
                  if (value.isDone()) finished[0] = true;
                  host.emit(request, summarizerStreamResult(value), null);
                }

                @Override public void onError(Throwable error) {
                  finished[0] = true;
                  host.emit(request, null, error.toString());
                }

                @Override public void onDone() {
                  if (finished[0]) return;
                  finished[0] = true;
                  Map<String, Object> last = new HashMap<>();
                  last.put("chunk", null);
                  last.put("done", true);
                  host.emit(request, last, null);
                }
              });
            });
      }
      default: throw new IllegalArgumentException("Unsupported MediaPipe text task: " + name);
    }
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
}
