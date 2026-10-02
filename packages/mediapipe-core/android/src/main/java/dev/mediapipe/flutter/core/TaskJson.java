package dev.mediapipe.flutter.core;

import com.google.mediapipe.tasks.components.containers.Category;
import com.google.mediapipe.tasks.components.containers.ClassificationResult;
import com.google.mediapipe.tasks.components.containers.Classifications;
import com.google.mediapipe.tasks.components.containers.Embedding;
import com.google.mediapipe.tasks.components.containers.EmbeddingResult;
import java.util.ArrayList;
import java.util.HashMap;
import java.util.List;
import java.util.Map;
import java.util.Optional;

/**
 * Google's shared result containers in the JSON shape of its JavaScript API, which the Dart
 * packages decode on every platform.
 */
public final class TaskJson {
  private TaskJson() {}

  /** A classification result: every head's categories and the request's timestamp. */
  public static Map<String, Object> classifications(ClassificationResult source) {
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

  /** An embedding result: every head's float or quantized vector. */
  public static Map<String, Object> embeddings(EmbeddingResult source) {
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

  /** Google's optional stamp, or null where the runtime gave none. */
  public static Long timestamp(Optional<Long> value) {
    return value.orElse(null);
  }
}
