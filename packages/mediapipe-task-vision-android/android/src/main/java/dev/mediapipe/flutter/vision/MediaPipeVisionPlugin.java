package dev.mediapipe.flutter.vision;

import android.content.Context;
import android.graphics.Bitmap;
import android.graphics.BitmapFactory;
import android.graphics.Matrix;
import android.os.Handler;
import android.os.Looper;
import androidx.exifinterface.media.ExifInterface;
import com.google.mediapipe.framework.image.BitmapImageBuilder;
import com.google.mediapipe.framework.image.MPImage;
import com.google.mediapipe.tasks.components.containers.Category;
import com.google.mediapipe.tasks.components.containers.Landmark;
import com.google.mediapipe.tasks.components.containers.NormalizedLandmark;
import com.google.mediapipe.tasks.core.BaseOptions;
import com.google.mediapipe.tasks.core.Delegate;
import com.google.mediapipe.tasks.vision.core.ImageProcessingOptions;
import com.google.mediapipe.tasks.vision.core.RunningMode;
import com.google.mediapipe.tasks.vision.facelandmarker.FaceLandmarker;
import com.google.mediapipe.tasks.vision.facelandmarker.FaceLandmarkerResult;
import com.google.mediapipe.tasks.vision.handlandmarker.HandLandmarker;
import com.google.mediapipe.tasks.vision.handlandmarker.HandLandmarkerResult;
import io.flutter.embedding.engine.plugins.FlutterPlugin;
import io.flutter.plugin.common.MethodCall;
import io.flutter.plugin.common.MethodChannel;
import java.nio.ByteBuffer;
import java.util.ArrayList;
import java.util.Arrays;
import java.util.HashMap;
import java.util.List;
import java.util.Map;
import java.util.Optional;
import java.util.concurrent.ExecutorService;
import java.util.concurrent.Executors;

/** Google's unmodified task graphs, serialized on the thread owning their GPU contexts. */
public final class MediaPipeVisionPlugin implements FlutterPlugin, MethodChannel.MethodCallHandler {
  /** One official task. Only the worker thread creates, runs and closes it. */
  private interface Task extends AutoCloseable {
    /** Runs one image; [timestamp] is null in IMAGE mode. Copies the result. */
    Map<String, Object> detect(MPImage image, ImageProcessingOptions processing, Long timestamp);

    @Override void close();
  }

  private MethodChannel channel;
  private Context context;
  private ExecutorService worker;
  private final Handler main = new Handler(Looper.getMainLooper());
  // Only the worker accesses tasks, including create and close.
  private final Map<Integer, Task> tasks = new HashMap<>();
  private final Map<Integer, ByteBuffer> modelBuffers = new HashMap<>();
  private int nextId;

  @Override public void onAttachedToEngine(FlutterPluginBinding binding) {
    context = binding.getApplicationContext();
    worker = Executors.newSingleThreadExecutor(r -> new Thread(r, "MediaPipe vision tasks"));
    channel = new MethodChannel(binding.getBinaryMessenger(), "mediapipe_flutter_vision/android");
    channel.setMethodCallHandler(this);
  }

  @Override public void onDetachedFromEngine(FlutterPluginBinding binding) {
    channel.setMethodCallHandler(null);
    worker.execute(() -> {
      for (Task task : tasks.values()) {
        try { task.close(); } catch (RuntimeException ignored) { }
      }
      tasks.clear();
      modelBuffers.clear();
    });
    worker.shutdown();
  }

  @Override public void onMethodCall(MethodCall call, MethodChannel.Result reply) {
    if (!Arrays.asList("create", "detect", "close").contains(call.method)) {
      reply.notImplemented();
      return;
    }
    worker.execute(() -> {
      try {
        Object value;
        switch (call.method) {
          case "create": value = create(call); break;
          case "detect": value = detect(call); break;
          default:
            int id = number(call, "id").intValue();
            Task task = tasks.remove(id);
            try { if (task != null) task.close(); }
            finally { modelBuffers.remove(id); }
            value = null;
        }
        main.post(() -> reply.success(value));
      } catch (Exception | LinkageError error) {
        main.post(() -> reply.error("mediapipe", error.toString(), null));
      }
    });
  }

  private int create(MethodCall call) {
    BaseOptions.Builder base = BaseOptions.builder();
    byte[] model = call.argument("modelBytes");
    ByteBuffer buffer = null;
    if (model != null) {
      buffer = ByteBuffer.allocateDirect(model.length);
      buffer.put(model).rewind();
      base.setModelAssetBuffer(buffer);
    } else {
      base.setModelAssetPath(call.argument("modelPath"));
    }
    String delegate = call.argument("delegate");
    if (!"cpu".equals(delegate) && !"gpu".equals(delegate)) {
      throw new IllegalArgumentException("Unknown delegate: " + delegate);
    }
    // GPU initialization failures propagate; never silently substitute CPU.
    base.setDelegate("gpu".equals(delegate) ? Delegate.GPU : Delegate.CPU);
    RunningMode mode = "video".equals(call.argument("mode")) ? RunningMode.VIDEO : RunningMode.IMAGE;
    String name = call.argument("task");
    Task task;
    switch (name == null ? "" : name) {
      case "face_landmarker": task = face(base.build(), mode, call); break;
      case "hand_landmarker": task = hand(base.build(), mode, call); break;
      default: throw new IllegalArgumentException("Unsupported task: " + name);
    }
    int id = nextId++;
    tasks.put(id, task);
    // Retain direct model storage for the task's entire native lifetime.
    if (buffer != null) modelBuffers.put(id, buffer);
    return id;
  }

  private Task face(BaseOptions base, RunningMode mode, MethodCall call) {
    FaceLandmarker task = FaceLandmarker.createFromOptions(context,
        FaceLandmarker.FaceLandmarkerOptions.builder()
            .setBaseOptions(base)
            .setRunningMode(mode)
            .setNumFaces(number(call, "numFaces").intValue())
            .setMinFaceDetectionConfidence(number(call, "detectionConfidence").floatValue())
            .setMinFacePresenceConfidence(number(call, "presenceConfidence").floatValue())
            .setMinTrackingConfidence(number(call, "trackingConfidence").floatValue())
            .setOutputFaceBlendshapes(Boolean.TRUE.equals(call.argument("blendshapes")))
            .setOutputFacialTransformationMatrixes(Boolean.TRUE.equals(call.argument("matrices")))
            .build());
    return new Task() {
      @Override public Map<String, Object> detect(MPImage image, ImageProcessingOptions processing,
          Long timestamp) {
        FaceLandmarkerResult result = timestamp == null ? task.detect(image, processing)
            : task.detectForVideo(image, processing, timestamp);
        Map<String, Object> copied = new HashMap<>();
        pack(result.faceLandmarks(), copied, "landmarks", "counts");
        List<Object> blendshapes = new ArrayList<>();
        for (var face : result.faceBlendshapes().orElseGet(ArrayList::new)) {
          blendshapes.add(categories(face));
        }
        copied.put("blendshapes", blendshapes);
        List<Object> matrices = new ArrayList<>();
        for (float[] matrix : result.facialTransformationMatrixes().orElseGet(ArrayList::new)) {
          double[] values = new double[matrix.length];
          // Google's Java task exports the matrix in column-major order.
          for (int i = 0; i < matrix.length; i++) values[i] = matrix[i];
          matrices.add(values);
        }
        copied.put("matrices", matrices);
        return copied;
      }

      @Override public void close() { task.close(); }
    };
  }

  private Task hand(BaseOptions base, RunningMode mode, MethodCall call) {
    HandLandmarker task = HandLandmarker.createFromOptions(context,
        HandLandmarker.HandLandmarkerOptions.builder()
            .setBaseOptions(base)
            .setRunningMode(mode)
            .setNumHands(number(call, "numHands").intValue())
            .setMinHandDetectionConfidence(number(call, "detectionConfidence").floatValue())
            .setMinHandPresenceConfidence(number(call, "presenceConfidence").floatValue())
            .setMinTrackingConfidence(number(call, "trackingConfidence").floatValue())
            .build());
    return new Task() {
      @Override public Map<String, Object> detect(MPImage image, ImageProcessingOptions processing,
          Long timestamp) {
        HandLandmarkerResult result = timestamp == null ? task.detect(image, processing)
            : task.detectForVideo(image, processing, timestamp);
        Map<String, Object> copied = new HashMap<>();
        pack(result.landmarks(), copied, "landmarks", "counts");
        pack(result.worldLandmarks(), copied, "worldLandmarks", "worldCounts");
        List<Object> handedness = new ArrayList<>();
        for (var hand : result.handedness()) handedness.add(categories(hand));
        copied.put("handedness", handedness);
        return copied;
      }

      @Override public void close() { task.close(); }
    };
  }

  private Object detect(MethodCall call) throws Exception {
    Task task = tasks.get(number(call, "id").intValue());
    if (task == null) throw new IllegalStateException("MediaPipe task has been disposed");
    Bitmap bitmap = decode(call);
    try {
      MPImage image = new BitmapImageBuilder(bitmap).build();
      try {
        ImageProcessingOptions processing = ImageProcessingOptions.builder()
            .setRotationDegrees(number(call, "rotation").intValue()).build();
        Number timestamp = call.argument("timestamp");
        Map<String, Object> copied = task.detect(image, processing,
            timestamp == null ? null : timestamp.longValue());
        copied.put("width", bitmap.getWidth());
        copied.put("height", bitmap.getHeight());
        return copied;
      } finally { image.close(); }
    } finally { bitmap.recycle(); }
  }

  /**
   * Packs landmark lists as x, y, z, visibility, presence per point (NaN when
   * absent) into one double[] under [valuesKey], with the points per subject
   * under [countsKey]. Flutter's codec sends both as typed arrays.
   */
  private static void pack(List<? extends List<?>> subjects, Map<String, Object> out,
      String valuesKey, String countsKey) {
    int[] counts = new int[subjects.size()];
    int total = 0;
    for (int i = 0; i < counts.length; i++) total += counts[i] = subjects.get(i).size();
    double[] values = new double[total * 5];
    int at = 0;
    for (List<?> points : subjects) {
      for (Object point : points) {
        if (point instanceof NormalizedLandmark p) {
          at = put(values, at, p.x(), p.y(), p.z(), p.visibility(), p.presence());
        } else {
          Landmark p = (Landmark) point;
          at = put(values, at, p.x(), p.y(), p.z(), p.visibility(), p.presence());
        }
      }
    }
    out.put(valuesKey, values);
    out.put(countsKey, counts);
  }

  private static int put(double[] values, int at, float x, float y, float z,
      Optional<Float> visibility, Optional<Float> presence) {
    values[at] = x;
    values[at + 1] = y;
    values[at + 2] = z;
    values[at + 3] = visibility.map(Float::doubleValue).orElse(Double.NaN);
    values[at + 4] = presence.map(Float::doubleValue).orElse(Double.NaN);
    return at + 5;
  }

  private static List<Object> categories(List<Category> source) {
    List<Object> copied = new ArrayList<>();
    for (Category c : source) {
      copied.add(Arrays.asList(c.index(), (double) c.score(), c.categoryName(), c.displayName()));
    }
    return copied;
  }

  private static Number number(MethodCall call, String key) {
    Number value = call.argument(key);
    if (value == null) throw new IllegalArgumentException("Missing " + key);
    return value;
  }

  private static Bitmap decode(MethodCall call) throws Exception {
    String path = call.argument("path");
    if (path != null) {
      Bitmap bitmap = BitmapFactory.decodeFile(path);
      if (bitmap == null) throw new IllegalArgumentException("Cannot decode image: " + path);
      try {
        int orientation = new ExifInterface(path).getAttributeInt(ExifInterface.TAG_ORIENTATION,
            ExifInterface.ORIENTATION_NORMAL);
        Matrix transform = new Matrix();
        switch (orientation) {
          case 2: transform.setScale(-1, 1); break;
          case 3: transform.setRotate(180); break;
          case 4: transform.setScale(1, -1); break;
          case 5: transform.setRotate(90); transform.postScale(-1, 1); break;
          case 6: transform.setRotate(90); break;
          case 7: transform.setRotate(-90); transform.postScale(-1, 1); break;
          case 8: transform.setRotate(-90); break;
          default: break;
        }
        Bitmap oriented = Bitmap.createBitmap(bitmap, 0, 0, bitmap.getWidth(), bitmap.getHeight(), transform, true);
        if (oriented != bitmap) bitmap.recycle();
        return oriented;
      } catch (Exception error) { bitmap.recycle(); throw error; }
    }
    int width = number(call, "width").intValue();
    int height = number(call, "height").intValue();
    int stride = number(call, "stride").intValue();
    byte[] bytes = call.argument("pixels");
    String format = call.argument("format");
    int channels = "rgb".equals(format) ? 3 : 4;
    if (!Arrays.asList("rgb", "rgba", "bgra").contains(format) || width <= 0 || height <= 0
        || stride < (long) width * channels || bytes == null || bytes.length != (long) stride * height) {
      throw new IllegalArgumentException("Invalid pixel buffer");
    }
    int[] argb = new int[Math.multiplyExact(width, height)];
    for (int y = 0; y < height; y++) {
      for (int x = 0; x < width; x++) {
        int i = y * stride + x * channels;
        int r = bytes[i + ("bgra".equals(format) ? 2 : 0)] & 255;
        int g = bytes[i + 1] & 255;
        int b = bytes[i + ("bgra".equals(format) ? 0 : 2)] & 255;
        // Alpha is not an inference input. Keep camera pixels opaque so Android
        // Bitmap premultiplication cannot change the RGB values.
        argb[y * width + x] = 0xff000000 | r << 16 | g << 8 | b;
      }
    }
    return Bitmap.createBitmap(argb, width, height, Bitmap.Config.ARGB_8888);
  }
}
