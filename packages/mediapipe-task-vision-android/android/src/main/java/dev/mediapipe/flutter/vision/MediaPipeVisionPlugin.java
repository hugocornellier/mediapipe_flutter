package dev.mediapipe.flutter.vision;

import android.content.Context;
import android.graphics.Bitmap;
import android.graphics.BitmapFactory;
import android.graphics.Matrix;
import android.graphics.RectF;
import android.os.Handler;
import android.os.Looper;
import androidx.exifinterface.media.ExifInterface;
import com.google.mediapipe.framework.image.BitmapImageBuilder;
import com.google.mediapipe.framework.image.ByteBufferExtractor;
import com.google.mediapipe.framework.image.MPImage;
import com.google.mediapipe.proto.CalculatorOptionsProto.CalculatorOptions;
import com.google.mediapipe.proto.CalculatorProto.CalculatorGraphConfig;
import com.google.mediapipe.tasks.TensorsToSegmentationCalculatorOptionsProto.TensorsToSegmentationCalculatorOptions;
import com.google.mediapipe.tasks.components.containers.Category;
import com.google.mediapipe.tasks.components.containers.Classifications;
import com.google.mediapipe.tasks.components.containers.Detection;
import com.google.mediapipe.tasks.components.containers.Embedding;
import com.google.mediapipe.tasks.components.containers.NormalizedKeypoint;
import com.google.mediapipe.tasks.components.containers.Landmark;
import com.google.mediapipe.tasks.components.containers.NormalizedLandmark;
import com.google.mediapipe.tasks.components.processors.ClassifierOptions;
import com.google.mediapipe.tasks.core.BaseOptions;
import com.google.mediapipe.tasks.core.Delegate;
import com.google.mediapipe.tasks.core.TaskRunner;
import com.google.mediapipe.tasks.vision.core.BaseVisionTaskApi;
import com.google.mediapipe.tasks.vision.core.ImageProcessingOptions;
import com.google.mediapipe.tasks.vision.core.RunningMode;
import com.google.mediapipe.tasks.vision.facedetector.FaceDetector;
import com.google.mediapipe.tasks.vision.facedetector.FaceDetectorResult;
import com.google.mediapipe.tasks.vision.facelandmarker.FaceLandmarker;
import com.google.mediapipe.tasks.vision.facelandmarker.FaceLandmarkerResult;
import com.google.mediapipe.tasks.vision.gesturerecognizer.GestureRecognizer;
import com.google.mediapipe.tasks.vision.gesturerecognizer.GestureRecognizerResult;
import com.google.mediapipe.tasks.vision.handlandmarker.HandLandmarker;
import com.google.mediapipe.tasks.vision.handlandmarker.HandLandmarkerResult;
import com.google.mediapipe.tasks.vision.holisticlandmarker.HolisticLandmarker;
import com.google.mediapipe.tasks.vision.holisticlandmarker.HolisticLandmarkerResult;
import com.google.mediapipe.tasks.vision.imageclassifier.ImageClassifier;
import com.google.mediapipe.tasks.vision.imageclassifier.ImageClassifierResult;
import com.google.mediapipe.tasks.vision.imageembedder.ImageEmbedder;
import com.google.mediapipe.tasks.vision.imageembedder.ImageEmbedderResult;
import com.google.mediapipe.tasks.vision.imagesegmenter.ImageSegmenter;
import com.google.mediapipe.tasks.vision.imagesegmenter.ImageSegmenterResult;
import com.google.mediapipe.tasks.vision.interactivesegmenter.InteractiveSegmenter;
import com.google.mediapipe.tasks.vision.interactivesegmenter.InteractiveSegmenterOptions;
import com.google.mediapipe.tasks.vision.interactivesegmenter.Stroke;
import com.google.mediapipe.tasks.vision.objectdetector.ObjectDetector;
import com.google.mediapipe.tasks.vision.objectdetector.ObjectDetectorResult;
import com.google.mediapipe.tasks.vision.poselandmarker.PoseLandmarker;
import com.google.mediapipe.tasks.vision.poselandmarker.PoseLandmarkerResult;
import com.google.mediapipe.util.proto.LabelMapProto.LabelMapItem;
import com.google.protobuf.ExtensionRegistryLite;
import com.google.protobuf.InvalidProtocolBufferException;
import io.flutter.embedding.engine.plugins.FlutterPlugin;
import io.flutter.plugin.common.BinaryMessenger;
import io.flutter.plugin.common.MethodCall;
import io.flutter.plugin.common.MethodChannel;
import java.io.File;
import java.io.FileOutputStream;
import java.io.IOException;
import java.io.UncheckedIOException;
import java.lang.reflect.Field;
import java.nio.ByteBuffer;
import java.nio.ByteOrder;
import java.util.ArrayList;
import java.util.Arrays;
import java.util.HashMap;
import java.util.List;
import java.util.Map;
import java.util.Optional;
import java.util.concurrent.ConcurrentHashMap;
import java.util.concurrent.ExecutorService;
import java.util.concurrent.Executors;
import java.util.concurrent.atomic.AtomicInteger;

/** Google's unmodified task graphs, serialized on the thread owning their GPU contexts. */
public final class MediaPipeVisionPlugin implements FlutterPlugin, MethodChannel.MethodCallHandler {
  /** One official task. Only the worker thread creates, runs and closes it. */
  private interface Task extends AutoCloseable {
    /** Runs one image; [timestamp] is null in IMAGE mode. Copies the result. */
    Map<String, Object> detect(MPImage image, ImageProcessingOptions processing, Long timestamp);

    /** Replaces a stateful task's image, which it keeps until the next one. */
    default void setImage(Bitmap bitmap) {
      bitmap.recycle();
      throw new UnsupportedOperationException("This task has no image session");
    }

    /** Segments a stateful task's image with a full stroke history. */
    default Object segment(List<List<Object>> strokes) {
      throw new UnsupportedOperationException("This task has no stroke session");
    }

    @Override void close();
  }

  // Masks travel on their own binary channel: a frame's confidence masks can
  // outgrow the Java heap that the method codec copies its reply onto.
  private static final String MASKS = "mediapipe_flutter_vision/android/masks";

  private MethodChannel channel;
  private BinaryMessenger messenger;
  private Context context;
  private ExecutorService worker;
  private final Handler main = new Handler(Looper.getMainLooper());
  // Only the worker accesses tasks, including create and close.
  private final Map<Integer, Task> tasks = new HashMap<>();
  private final Map<Integer, ByteBuffer> modelBuffers = new HashMap<>();
  private int nextId;
  // Masks in native memory, each fetched once, right after the detect reply
  // that names it. The worker adds them; the platform thread takes them.
  private final Map<Integer, ByteBuffer> maskData = new ConcurrentHashMap<>();
  private final AtomicInteger nextMask = new AtomicInteger();

  @Override public void onAttachedToEngine(FlutterPluginBinding binding) {
    context = binding.getApplicationContext();
    worker = Executors.newSingleThreadExecutor(r -> new Thread(r, "MediaPipe vision tasks"));
    messenger = binding.getBinaryMessenger();
    channel = new MethodChannel(messenger, "mediapipe_flutter_vision/android");
    channel.setMethodCallHandler(this);
    messenger.setMessageHandler(MASKS, (message, reply) -> reply.reply(message == null ? null
        : maskData.remove(message.order(ByteOrder.LITTLE_ENDIAN).getInt(0))));
  }

  @Override public void onDetachedFromEngine(FlutterPluginBinding binding) {
    channel.setMethodCallHandler(null);
    messenger.setMessageHandler(MASKS, null);
    maskData.clear();
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
    if (!Arrays.asList("create", "detect", "setImage", "segment", "close").contains(call.method)) {
      reply.notImplemented();
      return;
    }
    worker.execute(() -> {
      try {
        Object value;
        switch (call.method) {
          case "create": value = create(call); break;
          case "detect": value = detect(call); break;
          case "setImage": task(call).setImage(decode(call)); value = null; break;
          case "segment": value = task(call).segment(call.argument("strokes")); break;
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
    String name = call.argument("task");
    ByteBuffer buffer = null;
    File modelFile = null;
    if (model != null && "interactive_segmenter".equals(name)) {
      // UP-022: this task drops a model buffer, so it gets a private copy on disk.
      modelFile = writeModel(model);
      base.setModelAssetPath(modelFile.getAbsolutePath());
    } else if (model != null) {
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
    Task task;
    switch (name == null ? "" : name) {
      case "face_landmarker": task = face(base.build(), mode, call); break;
      case "hand_landmarker": task = hand(base.build(), mode, call); break;
      case "pose_landmarker": task = pose(base.build(), mode, call); break;
      case "gesture_recognizer": task = gesture(base.build(), mode, call); break;
      case "holistic_landmarker": task = holistic(base.build(), mode, call); break;
      case "face_detector": task = faceDetector(base.build(), mode, call); break;
      case "object_detector": task = objectDetector(base.build(), mode, call); break;
      case "image_classifier": task = imageClassifier(base.build(), mode, call); break;
      case "image_embedder": task = imageEmbedder(base.build(), mode, call); break;
      case "image_segmenter": task = imageSegmenter(base.build(), mode, call); break;
      case "interactive_segmenter":
        try {
          task = interactiveSegmenter(base.build(), modelFile);
        } catch (RuntimeException error) {
          if (modelFile != null) modelFile.delete();
          throw error;
        }
        break;
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

  private Task pose(BaseOptions base, RunningMode mode, MethodCall call) {
    PoseLandmarker task = PoseLandmarker.createFromOptions(context,
        PoseLandmarker.PoseLandmarkerOptions.builder()
            .setBaseOptions(base)
            .setRunningMode(mode)
            .setNumPoses(number(call, "numPoses").intValue())
            .setMinPoseDetectionConfidence(number(call, "detectionConfidence").floatValue())
            .setMinPosePresenceConfidence(number(call, "presenceConfidence").floatValue())
            .setMinTrackingConfidence(number(call, "trackingConfidence").floatValue())
            .setOutputSegmentationMasks(Boolean.TRUE.equals(call.argument("masks")))
            .build());
    return new Task() {
      @Override public Map<String, Object> detect(MPImage image, ImageProcessingOptions processing,
          Long timestamp) {
        PoseLandmarkerResult result = timestamp == null ? task.detect(image, processing)
            : task.detectForVideo(image, processing, timestamp);
        Map<String, Object> copied = new HashMap<>();
        pack(result.landmarks(), copied, "landmarks", "counts");
        pack(result.worldLandmarks(), copied, "worldLandmarks", "worldCounts");
        copied.put("masks", result.segmentationMasks().map(MediaPipeVisionPlugin.this::masks).orElse(null));
        return copied;
      }

      @Override public void close() { task.close(); }
    };
  }

  private Task gesture(BaseOptions base, RunningMode mode, MethodCall call) {
    GestureRecognizer task = GestureRecognizer.createFromOptions(context,
        GestureRecognizer.GestureRecognizerOptions.builder()
            .setBaseOptions(base)
            .setRunningMode(mode)
            .setNumHands(number(call, "numHands").intValue())
            .setMinHandDetectionConfidence(number(call, "detectionConfidence").floatValue())
            .setMinHandPresenceConfidence(number(call, "presenceConfidence").floatValue())
            .setMinTrackingConfidence(number(call, "trackingConfidence").floatValue())
            .setCannedGesturesClassifierOptions(classifier(call.argument("canned")))
            .setCustomGesturesClassifierOptions(classifier(call.argument("custom")))
            .build());
    return new Task() {
      @Override public Map<String, Object> detect(MPImage image, ImageProcessingOptions processing,
          Long timestamp) {
        GestureRecognizerResult result = timestamp == null ? task.recognize(image, processing)
            : task.recognizeForVideo(image, processing, timestamp);
        Map<String, Object> copied = new HashMap<>();
        pack(result.landmarks(), copied, "landmarks", "counts");
        pack(result.worldLandmarks(), copied, "worldLandmarks", "worldCounts");
        List<Object> handedness = new ArrayList<>();
        for (var hand : result.handedness()) handedness.add(categories(hand));
        copied.put("handedness", handedness);
        List<Object> gestures = new ArrayList<>();
        for (var hand : result.gestures()) gestures.add(categories(hand));
        copied.put("gestures", gestures);
        return copied;
      }

      @Override public void close() { task.close(); }
    };
  }

  private Task holistic(BaseOptions base, RunningMode mode, MethodCall call) {
    HolisticLandmarker task = HolisticLandmarker.createFromOptions(context,
        HolisticLandmarker.HolisticLandmarkerOptions.builder()
            .setBaseOptions(base)
            .setRunningMode(mode)
            .setMinFaceDetectionConfidence(number(call, "faceDetectionConfidence").floatValue())
            .setMinFaceSuppressionThreshold(number(call, "faceSuppressionThreshold").floatValue())
            .setMinFacePresenceConfidence(number(call, "facePresenceConfidence").floatValue())
            .setMinHandLandmarksConfidence(number(call, "handLandmarksConfidence").floatValue())
            .setMinPoseDetectionConfidence(number(call, "poseDetectionConfidence").floatValue())
            .setMinPoseSuppressionThreshold(number(call, "poseSuppressionThreshold").floatValue())
            .setMinPosePresenceConfidence(number(call, "posePresenceConfidence").floatValue())
            .setOutputFaceBlendshapes(Boolean.TRUE.equals(call.argument("blendshapes")))
            .setOutputPoseSegmentationMasks(Boolean.TRUE.equals(call.argument("masks")))
            .build());
    return new Task() {
      @Override public Map<String, Object> detect(MPImage image, ImageProcessingOptions processing,
          Long timestamp) {
        HolisticLandmarkerResult result = timestamp == null ? task.detect(image, processing)
            : task.detectForVideo(image, processing, timestamp);
        Map<String, Object> copied = new HashMap<>();
        // One subject: each part travels as a one-list pack, possibly empty.
        pack(List.of(result.faceLandmarks()), copied, "face", "faceCounts");
        pack(List.of(result.poseLandmarks()), copied, "pose", "poseCounts");
        pack(List.of(result.poseWorldLandmarks()), copied, "poseWorld", "poseWorldCounts");
        pack(List.of(result.leftHandLandmarks()), copied, "leftHand", "leftHandCounts");
        pack(List.of(result.leftHandWorldLandmarks()), copied, "leftHandWorld", "leftHandWorldCounts");
        pack(List.of(result.rightHandLandmarks()), copied, "rightHand", "rightHandCounts");
        pack(List.of(result.rightHandWorldLandmarks()), copied, "rightHandWorld", "rightHandWorldCounts");
        copied.put("blendshapes", result.faceBlendshapes().map(MediaPipeVisionPlugin::categories).orElse(null));
        copied.put("mask", result.segmentationMask().map(MediaPipeVisionPlugin.this::mask).orElse(null));
        return copied;
      }

      @Override public void close() { task.close(); }
    };
  }

  private Task faceDetector(BaseOptions base, RunningMode mode, MethodCall call) {
    FaceDetector task = FaceDetector.createFromOptions(context,
        FaceDetector.FaceDetectorOptions.builder()
            .setBaseOptions(base)
            .setRunningMode(mode)
            .setMinDetectionConfidence(number(call, "detectionConfidence").floatValue())
            .setMinSuppressionThreshold(number(call, "suppressionThreshold").floatValue())
            .build());
    return new Task() {
      @Override public Map<String, Object> detect(MPImage image, ImageProcessingOptions processing,
          Long timestamp) {
        FaceDetectorResult result = timestamp == null ? task.detect(image, processing)
            : task.detectForVideo(image, processing, timestamp);
        Map<String, Object> copied = new HashMap<>();
        copied.put("detections", detections(result.detections()));
        return copied;
      }

      @Override public void close() { task.close(); }
    };
  }

  private Task objectDetector(BaseOptions base, RunningMode mode, MethodCall call) {
    Map<String, Object> limits = call.argument("classifier");
    ObjectDetector.ObjectDetectorOptions.Builder options =
        ObjectDetector.ObjectDetectorOptions.builder().setBaseOptions(base).setRunningMode(mode);
    ClassifierOptions classifier = classifier(limits);
    classifier.maxResults().ifPresent(options::setMaxResults);
    classifier.scoreThreshold().ifPresent(options::setScoreThreshold);
    classifier.displayNamesLocale().ifPresent(options::setDisplayNamesLocale);
    if (!classifier.categoryAllowlist().isEmpty()) options.setCategoryAllowlist(classifier.categoryAllowlist());
    if (!classifier.categoryDenylist().isEmpty()) options.setCategoryDenylist(classifier.categoryDenylist());
    ObjectDetector task = ObjectDetector.createFromOptions(context, options.build());
    return new Task() {
      @Override public Map<String, Object> detect(MPImage image, ImageProcessingOptions processing,
          Long timestamp) {
        ObjectDetectorResult result = timestamp == null ? task.detect(image, processing)
            : task.detectForVideo(image, processing, timestamp);
        Map<String, Object> copied = new HashMap<>();
        copied.put("detections", detections(result.detections()));
        return copied;
      }

      @Override public void close() { task.close(); }
    };
  }

  private Task imageClassifier(BaseOptions base, RunningMode mode, MethodCall call) {
    Map<String, Object> limits = call.argument("classifier");
    ImageClassifier.ImageClassifierOptions.Builder options =
        ImageClassifier.ImageClassifierOptions.builder().setBaseOptions(base).setRunningMode(mode);
    ClassifierOptions classifier = classifier(limits);
    classifier.maxResults().ifPresent(options::setMaxResults);
    classifier.scoreThreshold().ifPresent(options::setScoreThreshold);
    classifier.displayNamesLocale().ifPresent(options::setDisplayNamesLocale);
    if (!classifier.categoryAllowlist().isEmpty()) options.setCategoryAllowlist(classifier.categoryAllowlist());
    if (!classifier.categoryDenylist().isEmpty()) options.setCategoryDenylist(classifier.categoryDenylist());
    ImageClassifier task = ImageClassifier.createFromOptions(context, options.build());
    return new Task() {
      @Override public Map<String, Object> detect(MPImage image, ImageProcessingOptions processing,
          Long timestamp) {
        ImageClassifierResult result = timestamp == null ? task.classify(image, processing)
            : task.classifyForVideo(image, processing, timestamp);
        List<Object> heads = new ArrayList<>();
        for (Classifications head : result.classificationResult().classifications()) {
          heads.add(Arrays.asList(categories(head.categories()), head.headIndex(),
              head.headName().orElse(null)));
        }
        Map<String, Object> copied = new HashMap<>();
        copied.put("classifications", heads);
        return copied;
      }

      @Override public void close() { task.close(); }
    };
  }

  private Task imageEmbedder(BaseOptions base, RunningMode mode, MethodCall call) {
    ImageEmbedder task = ImageEmbedder.createFromOptions(context,
        ImageEmbedder.ImageEmbedderOptions.builder()
            .setBaseOptions(base)
            .setRunningMode(mode)
            .setL2Normalize(Boolean.TRUE.equals(call.argument("l2Normalize")))
            .setQuantize(Boolean.TRUE.equals(call.argument("quantize")))
            .build());
    return new Task() {
      @Override public Map<String, Object> detect(MPImage image, ImageProcessingOptions processing,
          Long timestamp) {
        ImageEmbedderResult result = timestamp == null ? task.embed(image, processing)
            : task.embedForVideo(image, processing, timestamp);
        List<Object> heads = new ArrayList<>();
        for (Embedding head : result.embeddingResult().embeddings()) {
          // Google fills one representation and leaves the other empty.
          float[] values = head.floatEmbedding();
          double[] floats = null;
          if (values != null && values.length > 0) {
            floats = new double[values.length];
            for (int i = 0; i < values.length; i++) floats[i] = values[i];
          }
          heads.add(Arrays.asList(floats, floats == null ? head.quantizedEmbedding() : null,
              head.headIndex(), head.headName().orElse(null)));
        }
        Map<String, Object> copied = new HashMap<>();
        copied.put("embeddings", heads);
        return copied;
      }

      @Override public void close() { task.close(); }
    };
  }

  private Task imageSegmenter(BaseOptions base, RunningMode mode, MethodCall call) {
    ImageSegmenter.ImageSegmenterOptions.Builder options =
        ImageSegmenter.ImageSegmenterOptions.builder()
            .setBaseOptions(base)
            .setRunningMode(mode)
            .setOutputConfidenceMasks(Boolean.TRUE.equals(call.argument("confidenceMasks")))
            .setOutputCategoryMask(Boolean.TRUE.equals(call.argument("categoryMask")));
    String locale = call.argument("displayNamesLocale");
    if (locale != null) options.setDisplayNamesLocale(locale);
    ImageSegmenter task = ImageSegmenter.createFromOptions(context, options.build());
    List<String> labels = segmenterLabels(task);
    return new Task() {
      @Override public Map<String, Object> detect(MPImage image, ImageProcessingOptions processing,
          Long timestamp) {
        ImageSegmenterResult result = timestamp == null ? task.segment(image, processing)
            : task.segmentForVideo(image, processing, timestamp);
        Map<String, Object> copied = new HashMap<>();
        copied.put("confidenceMasks",
            result.confidenceMasks().map(MediaPipeVisionPlugin.this::masks).orElse(null));
        copied.put("categoryMask", result.categoryMask().map(MediaPipeVisionPlugin.this::mask).orElse(null));
        List<Float> scores = result.qualityScores();
        float[] quality = new float[scores.size()];
        for (int i = 0; i < quality.length; i++) quality[i] = scores.get(i);
        copied.put("qualityScores", quality);
        copied.put("labels", labels);
        return copied;
      }

      @Override public void close() { task.close(); }
    };
  }

  /**
   * The model's labels in mask order. Google's getLabels() reads them from the
   * segmentation calculator's options in a graph config parsed with an empty
   * extension registry, so in 1.0.0 it finds none (upstream-issues.md UP-019).
   * This parses those options again with their extension registered.
   */
  private static List<String> segmenterLabels(ImageSegmenter task) {
    List<String> labels = task.getLabels();
    if (!labels.isEmpty()) return labels;
    try {
      Field field = BaseVisionTaskApi.class.getDeclaredField("runner");
      field.setAccessible(true);
      CalculatorGraphConfig graph = ((TaskRunner) field.get(task)).getCalculatorGraphConfig();
      ExtensionRegistryLite registry = ExtensionRegistryLite.newInstance();
      registry.add(TensorsToSegmentationCalculatorOptions.ext);
      for (CalculatorGraphConfig.Node node : graph.getNodeList()) {
        if (!node.getName().contains("mediapipe.tasks.TensorsToSegmentationCalculator")) continue;
        Map<Long, LabelMapItem> items = CalculatorOptions
            .parseFrom(node.getOptions().toByteString(), registry)
            .getExtension(TensorsToSegmentationCalculatorOptions.ext)
            .getLabelItemsMap();
        List<String> names = new ArrayList<>();
        for (long i = 0; i < items.size(); i++) {
          LabelMapItem item = items.get(i);
          names.add(item == null ? "" : item.getName());
        }
        return names;
      }
    } catch (ReflectiveOperationException | InvalidProtocolBufferException error) {
      throw new IllegalStateException("Cannot read the segmentation labels", error);
    }
    return labels;
  }

  private File writeModel(byte[] model) {
    File file = null;
    try {
      file = File.createTempFile("interactive_segmenter", ".task", context.getCacheDir());
      try (FileOutputStream out = new FileOutputStream(file)) {
        out.write(model);
      }
      return file;
    } catch (IOException error) {
      if (file != null) file.delete();
      throw new UncheckedIOException(error);
    }
  }

  /** [modelFile], when set, is the task's private model copy, deleted on close. */
  private Task interactiveSegmenter(BaseOptions base, File modelFile) {
    InteractiveSegmenter task = InteractiveSegmenter.createFromOptions(context,
        InteractiveSegmenterOptions.builder().setBaseOptions(base).build());
    return new Task() {
      private MPImage image;
      private Bitmap bitmap;

      @Override public Map<String, Object> detect(MPImage image, ImageProcessingOptions processing,
          Long timestamp) {
        throw new IllegalArgumentException("Interactive Segmenter takes setImage and segment");
      }

      @Override public void setImage(Bitmap next) {
        MPImage nextImage = new BitmapImageBuilder(next).build();
        try {
          task.setImage(nextImage);
        } catch (RuntimeException error) {
          nextImage.close();
          next.recycle();
          throw error;
        }
        release();
        image = nextImage;
        bitmap = next;
      }

      /** Each stroke as [brush mode, x, y pairs as double[], completed]. */
      @Override public Object segment(List<List<Object>> strokes) {
        List<Stroke> history = new ArrayList<>();
        for (List<Object> stroke : strokes) {
          int mode = ((Number) stroke.get(0)).intValue();
          double[] xy = (double[]) stroke.get(1);
          List<NormalizedKeypoint> points = new ArrayList<>();
          for (int i = 0; i + 1 < xy.length; i += 2) {
            points.add(NormalizedKeypoint.create((float) xy[i], (float) xy[i + 1]));
          }
          history.add(Stroke.builder()
              .setBrushMode(mode == 1 ? Stroke.BrushMode.POSITIVE
                  : mode == 2 ? Stroke.BrushMode.NEGATIVE : Stroke.BrushMode.LASSO)
              .setPoints(points)
              .setCompleted(Boolean.TRUE.equals(stroke.get(2)))
              .build());
        }
        MPImage mask = task.segment(history);
        try { return mask(mask); } finally { mask.close(); }
      }

      private void release() {
        if (image != null) image.close();
        if (bitmap != null) bitmap.recycle();
        image = null;
        bitmap = null;
      }

      @Override public void close() {
        try {
          task.close();
        } finally {
          release();
          if (modelFile != null) modelFile.delete();
        }
      }
    };
  }

  private List<Object> masks(List<MPImage> source) {
    List<Object> copied = new ArrayList<>();
    for (MPImage image : source) copied.add(mask(image));
    return copied;
  }

  /**
   * Copies a mask into native memory and names it as [width, height, bytes
   * per value, id] for the Dart side to fetch on MASKS: 4 for float32
   * confidences, 1 for uint8 categories, both in native byte order.
   */
  private List<Object> mask(MPImage image) {
    int width = image.getWidth();
    int height = image.getHeight();
    int count = Math.multiplyExact(width, height);
    ByteBuffer source = ByteBufferExtractor.extract(image).duplicate();
    source.rewind();
    int depth = source.remaining() == (long) count * 4 ? 4 : source.remaining() == count ? 1 : 0;
    if (depth == 0) {
      throw new IllegalStateException("Unexpected mask layout: " + source.remaining()
          + " bytes for " + width + "x" + height);
    }
    // A binary reply sends its buffer up to the position, so it stays at the end.
    ByteBuffer copy = ByteBuffer.allocateDirect(source.remaining());
    copy.put(source);
    int id = nextMask.incrementAndGet();
    maskData.put(id, copy);
    return Arrays.asList(width, height, depth, id);
  }

  /** Each detection as [left, top, right, bottom], categories, keypoints [x, y, label, score]. */
  private static List<Object> detections(List<Detection> source) {
    List<Object> copied = new ArrayList<>();
    for (Detection detection : source) {
      RectF box = detection.boundingBox();
      List<Object> keypoints = new ArrayList<>();
      for (NormalizedKeypoint k : detection.keypoints().orElseGet(ArrayList::new)) {
        keypoints.add(Arrays.asList((double) k.x(), (double) k.y(), k.label().orElse(null),
            k.score().map(Float::doubleValue).orElse(null)));
      }
      copied.add(Arrays.asList(
          new double[] {box.left, box.top, box.right, box.bottom},
          categories(detection.categories()), keypoints));
    }
    return copied;
  }

  /** Canned or custom gesture limits; Google rejects a non-positive maxResults. */
  private static ClassifierOptions classifier(Map<String, Object> source) {
    ClassifierOptions.Builder options = ClassifierOptions.builder();
    if (source == null) return options.build();
    Number maxResults = (Number) source.get("maxResults");
    if (maxResults != null && maxResults.intValue() > 0) options.setMaxResults(maxResults.intValue());
    Number threshold = (Number) source.get("scoreThreshold");
    if (threshold != null) options.setScoreThreshold(threshold.floatValue());
    String locale = (String) source.get("displayNamesLocale");
    if (locale != null) options.setDisplayNamesLocale(locale);
    @SuppressWarnings("unchecked") List<String> allow = (List<String>) source.get("allowlist");
    if (allow != null && !allow.isEmpty()) options.setCategoryAllowlist(allow);
    @SuppressWarnings("unchecked") List<String> deny = (List<String>) source.get("denylist");
    if (deny != null && !deny.isEmpty()) options.setCategoryDenylist(deny);
    return options.build();
  }

  private Task task(MethodCall call) {
    Task task = tasks.get(number(call, "id").intValue());
    if (task == null) throw new IllegalStateException("MediaPipe task has been disposed");
    return task;
  }

  private Object detect(MethodCall call) throws Exception {
    Task task = task(call);
    Bitmap bitmap = decode(call);
    try {
      MPImage image = new BitmapImageBuilder(bitmap).build();
      try {
        ImageProcessingOptions.Builder options = ImageProcessingOptions.builder()
            .setRotationDegrees(number(call, "rotation").intValue());
        List<Number> region = call.argument("region");
        if (region != null) {
          options.setRegionOfInterest(new RectF(region.get(0).floatValue(),
              region.get(1).floatValue(), region.get(2).floatValue(), region.get(3).floatValue()));
        }
        ImageProcessingOptions processing = options.build();
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
