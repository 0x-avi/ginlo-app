package `in`.ginlo.ginlo

import android.os.Build
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    // Dart asks "how far has the screen turned?" (0, 90, 180, 270 degrees). Flutter has no API
    // for this, and the camera plugin's orientation value doesn't follow the screen reliably.
    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "ginlo/display").setMethodCallHandler { call, result ->
            if (call.method == "rotationDegrees") {
                @Suppress("DEPRECATION")
                val rotation = if (Build.VERSION.SDK_INT >= 30) display!!.rotation else windowManager.defaultDisplay.rotation
                result.success(rotation * 90) // Surface.ROTATION_0..270 are 0..3
            } else {
                result.notImplemented()
            }
        }
    }
}
