package com.example.mediapipe_gallery

import android.content.Intent
import android.net.TrafficStats
import android.os.Process
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.net.HttpURLConnection
import java.net.URL
import kotlin.concurrent.thread

class MainActivity : FlutterActivity() {
  // Temporary, for telemetry_long_probe_test.dart. Loads no library.
  override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
    super.configureFlutterEngine(flutterEngine)
    MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "probe/net").setMethodCallHandler { call, result ->
      val uid = Process.myUid()
      when (call.method) {
        "uidBytes" -> result.success(
          listOf(
            TrafficStats.getUidTxBytes(uid),
            TrafficStats.getUidRxBytes(uid),
            TrafficStats.getUidTxPackets(uid),
            TrafficStats.getUidRxPackets(uid),
          ),
        )
        "javaGet" -> thread {
          val status = try {
            val connection = URL(call.arguments as String).openConnection() as HttpURLConnection
            connection.setRequestProperty("Connection", "close")
            val code = connection.responseCode
            connection.inputStream.use { it.readBytes() }
            connection.disconnect()
            code
          } catch (error: Exception) {
            -1
          }
          runOnUiThread { result.success(status) }
        }
        "background" -> {
          moveTaskToBack(true)
          result.success(null)
        }
        "foreground" -> {
          startActivity(Intent(this, MainActivity::class.java).addFlags(Intent.FLAG_ACTIVITY_REORDER_TO_FRONT))
          result.success(null)
        }
        else -> result.notImplemented()
      }
    }
  }
}
