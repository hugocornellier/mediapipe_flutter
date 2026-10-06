package dev.mediapipe.flutter.core;

import android.os.Handler;
import android.os.Looper;
import com.google.mediapipe.tasks.core.BaseOptions;
import io.flutter.plugin.common.BinaryMessenger;
import io.flutter.plugin.common.MethodCall;
import io.flutter.plugin.common.MethodChannel;
import java.nio.ByteBuffer;
import java.util.HashMap;
import java.util.List;
import java.util.Map;
import java.util.Set;
import java.util.concurrent.ExecutorService;
import java.util.concurrent.Executors;
import java.util.function.Consumer;

/**
 * What the family plugins share on Android: one worker thread that creates, runs and closes
 * Google's tasks in order, the model buffers kept alive for them, the method channel's
 * dispatch and replies, and streamed updates sent back to Dart. A family supplies how its tasks
 * are created and which methods they answer; everything Google runs stays in the family.
 */
public final class TaskHost implements MethodChannel.MethodCallHandler {
  /** One of Google's tasks and how the family runs it. Only the worker thread touches it. */
  public interface Task extends AutoCloseable {
    /** Answers one of the family's methods (the host's constructor names them). */
    Object call(String method, MethodCall call) throws Exception;

    /**
     * Starts one streamed request, whose updates the family sends with {@link TaskHost#emit}
     * as they arrive, the last one marked {@code done}.
     */
    default void stream(MethodCall call, int request) throws Exception {
      throw new UnsupportedOperationException("MediaPipe task does not stream");
    }

    @Override void close();
  }

  /** Where a new task reads its model: the request's bytes, or a path. */
  public static final class Model {
    private final byte[] bytes;
    private final String path;
    private ByteBuffer buffer;

    Model(byte[] bytes, String path) {
      this.bytes = bytes;
      this.path = path;
    }

    /** The model's bytes, when the request sent them. */
    public byte[] bytes() {
      return bytes;
    }

    /** The model's path, when the request named one. */
    public String path() {
      return path;
    }

    /**
     * The model's bytes as a direct buffer, which the host keeps alive as long as the task:
     * Google's native task reads it in place, without a copy, and keeps no reference of its own
     * (upstream-issues.md UP-033).
     */
    public ByteBuffer direct() {
      if (buffer == null && bytes != null) {
        buffer = ByteBuffer.allocateDirect(bytes.length);
        buffer.put(bytes).rewind();
      }
      return buffer;
    }

    /** Google's base options reading this model: its {@link #direct} buffer, or its path. */
    public BaseOptions.Builder baseOptions() {
      BaseOptions.Builder base = BaseOptions.builder();
      if (bytes != null) {
        base.setModelAssetBuffer(direct());
      } else if (path != null) {
        base.setModelAssetPath(path);
      }
      return base;
    }
  }

  /** Creates the family's task for one {@code create} call. */
  public interface Factory {
    Task create(MethodCall call, Model model) throws Exception;
  }

  private final MethodChannel channel;
  private final ExecutorService worker;
  private final Handler main = new Handler(Looper.getMainLooper());
  private final Factory factory;
  private final Set<String> methods;
  private final MethodChannel.MethodCallHandler fallback;
  // Only the worker touches these, create and close included.
  private final Map<Integer, Task> tasks = new HashMap<>();
  // A field that is only written would not hold the buffers: R8 removes such
  // fields from release builds, the buffer is collected, and inference reads
  // freed memory (UP-033). These are read when the task closes.
  private final Map<Integer, ByteBuffer> modelBuffers = new HashMap<>();
  private int nextId;

  /**
   * Opens the family's channel. {@code methods} are the ones its tasks answer through
   * {@link Task#call}; {@code create}, {@code stream} and {@code close} are the host's. Any
   * other method goes to {@code fallback} on the platform thread, or is unimplemented.
   */
  public TaskHost(BinaryMessenger messenger, String channelName, String threadName,
      Factory factory, Set<String> methods, MethodChannel.MethodCallHandler fallback) {
    this.channel = new MethodChannel(messenger, channelName);
    this.worker = Executors.newSingleThreadExecutor(r -> new Thread(r, threadName));
    this.factory = factory;
    this.methods = methods;
    this.fallback = fallback;
    channel.setMethodCallHandler(this);
  }

  /** Closes every task on the worker, then the worker and the channel. */
  public void detach() {
    channel.setMethodCallHandler(null);
    worker.execute(() -> {
      for (Task task : tasks.values()) {
        try {
          task.close();
        } catch (RuntimeException ignored) {
          // Closing is best effort; the task is gone either way.
        }
      }
      tasks.clear();
      modelBuffers.clear();
    });
    worker.shutdown();
  }

  @Override public void onMethodCall(MethodCall call, MethodChannel.Result reply) {
    switch (call.method) {
      case "create": case "stream": case "close": break;
      default:
        if (!methods.contains(call.method)) {
          if (fallback != null) fallback.onMethodCall(call, reply);
          else reply.notImplemented();
          return;
        }
    }
    worker.execute(() -> {
      try {
        Object value;
        switch (call.method) {
          case "create": value = create(call); break;
          case "stream": task(call).stream(call, number(call, "request")); value = null; break;
          case "close": {
            int id = number(call, "id");
            Task task = tasks.remove(id);
            try {
              if (task != null) task.close();
            } finally {
              modelBuffers.remove(id);
            }
            value = null;
            break;
          }
          default: value = task(call).call(call.method, call);
        }
        main.post(() -> reply.success(value));
      } catch (Exception | LinkageError error) {
        main.post(() -> reply.error("mediapipe", error.toString(), null));
      }
    });
  }

  private int create(MethodCall call) throws Exception {
    Model model = new Model(call.argument("modelBytes"), call.argument("modelPath"));
    Task task = factory.create(call, model);
    int id = nextId++;
    tasks.put(id, task);
    // Retain direct model storage for the task's entire native lifetime.
    if (model.buffer != null) modelBuffers.put(id, model.buffer);
    return id;
  }

  /** The task a request names by {@code id}; on the worker. */
  private Task task(MethodCall call) {
    Task task = tasks.get(number(call, "id"));
    if (task == null) throw new IllegalStateException("MediaPipe task has been disposed");
    return task;
  }

  /**
   * Sends one streamed update, or Google's error, for {@code request} to Dart as an
   * {@code update} call on the family's channel, from any thread.
   */
  public void emit(int request, Map<String, Object> result, String error) {
    Map<String, Object> event = new HashMap<>();
    event.put("request", request);
    if (result != null) event.put("result", result);
    if (error != null) event.put("error", error);
    main.post(() -> channel.invokeMethod("update", event));
  }

  /** A whole-number argument that must be present. */
  public static int number(MethodCall call, String key) {
    Number value = call.argument(key);
    if (value == null) throw new IllegalArgumentException("Missing " + key);
    return value.intValue();
  }

  /**
   * A whole-number argument that must be present and may need 64 bits, such as a timestamp in
   * milliseconds: Flutter sends a Dart int above 2^31 as a {@code Long}, which {@link #number}
   * would truncate.
   */
  public static long wholeNumber(MethodCall call, String key) {
    Number value = call.argument(key);
    if (value == null) throw new IllegalArgumentException("Missing " + key);
    return value.longValue();
  }

  /** A decimal argument that must be present. */
  public static float decimal(MethodCall call, String key) {
    Number value = call.argument(key);
    if (value == null) throw new IllegalArgumentException("Missing " + key);
    return value.floatValue();
  }

  /**
   * Passes the classifier settings a request sent, named as in Google's JavaScript API, to the
   * setters of a task's options builder. A setting the request left out keeps Google's default.
   */
  public static void classifierOptions(
      MethodCall call,
      Consumer<String> displayNamesLocale,
      Consumer<Integer> maxResults,
      Consumer<Float> scoreThreshold,
      Consumer<List<String>> categoryAllowlist,
      Consumer<List<String>> categoryDenylist) {
    if (call.hasArgument("displayNamesLocale")) {
      displayNamesLocale.accept(call.argument("displayNamesLocale"));
    }
    if (call.hasArgument("maxResults")) maxResults.accept(number(call, "maxResults"));
    if (call.hasArgument("scoreThreshold")) {
      scoreThreshold.accept(decimal(call, "scoreThreshold"));
    }
    if (call.hasArgument("categoryAllowlist")) {
      categoryAllowlist.accept(call.argument("categoryAllowlist"));
    }
    if (call.hasArgument("categoryDenylist")) {
      categoryDenylist.accept(call.argument("categoryDenylist"));
    }
  }
}
