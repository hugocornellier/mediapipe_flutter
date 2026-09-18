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
import com.google.mediapipe.tasks.core.BaseOptions;
import com.google.mediapipe.tasks.core.Delegate;
import com.google.mediapipe.tasks.vision.core.ImageProcessingOptions;
import com.google.mediapipe.tasks.vision.core.RunningMode;
import com.google.mediapipe.tasks.vision.facelandmarker.FaceLandmarker;
import com.google.mediapipe.tasks.vision.facelandmarker.FaceLandmarkerResult;
import io.flutter.embedding.engine.plugins.FlutterPlugin;
import io.flutter.plugin.common.MethodCall;
import io.flutter.plugin.common.MethodChannel;
import java.nio.ByteBuffer;
import java.util.ArrayList;
import java.util.Arrays;
import java.util.HashMap;
import java.util.List;
import java.util.Map;
import java.util.concurrent.ExecutorService;
import java.util.concurrent.Executors;

/** Google's unmodified task graph, serialized on the thread owning its GPU context. */
public final class MediaPipeVisionPlugin implements FlutterPlugin, MethodChannel.MethodCallHandler {
  private MethodChannel channel;
  private Context context;
  private ExecutorService worker;
  private final Handler main = new Handler(Looper.getMainLooper());
  // Only the worker accesses tasks, including create and close.
  private final Map<Integer, FaceLandmarker> tasks = new HashMap<>();
  private final Map<Integer, ByteBuffer> modelBuffers = new HashMap<>();
  private int nextId;

  @Override public void onAttachedToEngine(FlutterPluginBinding binding) {
    context = binding.getApplicationContext();
    worker = Executors.newSingleThreadExecutor(r -> new Thread(r, "MediaPipe FaceLandmarker"));
    channel = new MethodChannel(binding.getBinaryMessenger(), "mediapipe_flutter_vision/android");
    channel.setMethodCallHandler(this);
  }

  @Override public void onDetachedFromEngine(FlutterPluginBinding binding) {
    channel.setMethodCallHandler(null);
    worker.execute(() -> {
      for (FaceLandmarker task : tasks.values()) {
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
            FaceLandmarker task = tasks.remove(id);
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
    FaceLandmarker.FaceLandmarkerOptions options = FaceLandmarker.FaceLandmarkerOptions.builder()
        .setBaseOptions(base.build())
        .setRunningMode("video".equals(call.argument("mode")) ? RunningMode.VIDEO : RunningMode.IMAGE)
        .setNumFaces(number(call, "numFaces").intValue())
        .setMinFaceDetectionConfidence(number(call, "detectionConfidence").floatValue())
        .setMinFacePresenceConfidence(number(call, "presenceConfidence").floatValue())
        .setMinTrackingConfidence(number(call, "trackingConfidence").floatValue())
        .setOutputFaceBlendshapes(Boolean.TRUE.equals(call.argument("blendshapes")))
        .setOutputFacialTransformationMatrixes(Boolean.TRUE.equals(call.argument("matrices")))
        .build();
    FaceLandmarker task = FaceLandmarker.createFromOptions(context, options);
    int id = nextId++;
    tasks.put(id, task);
    // Retain direct model storage for the task's entire native lifetime.
    if (buffer != null) modelBuffers.put(id, buffer);
    return id;
  }

  private Object detect(MethodCall call) throws Exception {
    FaceLandmarker task = tasks.get(number(call, "id").intValue());
    if (task == null) throw new IllegalStateException("FaceLandmarker has been disposed");
    Bitmap bitmap = decode(call);
    try {
      MPImage image = new BitmapImageBuilder(bitmap).build();
      try {
        ImageProcessingOptions processing = ImageProcessingOptions.builder()
            .setRotationDegrees(number(call, "rotation").intValue()).build();
        Number timestamp = call.argument("timestamp");
        FaceLandmarkerResult result = timestamp == null ? task.detect(image, processing)
            : task.detectForVideo(image, processing, timestamp.longValue());
        Map<String, Object> copied = new HashMap<>();
        copied.put("width", bitmap.getWidth());
        copied.put("height", bitmap.getHeight());
        List<Object> faces = new ArrayList<>();
        for (var face : result.faceLandmarks()) {
          List<Object> points = new ArrayList<>();
          for (var p : face) {
            points.add(Arrays.asList((double) p.x(), (double) p.y(), (double) p.z(),
                p.visibility().map(Float::doubleValue).orElse(null),
                p.presence().map(Float::doubleValue).orElse(null)));
          }
          faces.add(points);
        }
        copied.put("landmarks", faces);
        List<Object> blendshapes = new ArrayList<>();
        for (var face : result.faceBlendshapes().orElseGet(ArrayList::new)) {
          List<Object> categories = new ArrayList<>();
          for (var c : face) categories.add(Arrays.asList(c.index(), (double) c.score(),
              c.categoryName(), c.displayName()));
          blendshapes.add(categories);
        }
        copied.put("blendshapes", blendshapes);
        List<Object> matrices = new ArrayList<>();
        for (float[] matrix : result.facialTransformationMatrixes().orElseGet(ArrayList::new)) {
          List<Double> values = new ArrayList<>();
          // Google's Java task exports the matrix in column-major order.
          for (float value : matrix) values.add((double) value);
          matrices.add(values);
        }
        copied.put("matrices", matrices);
        return copied;
      } finally { image.close(); }
    } finally { bitmap.recycle(); }
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
