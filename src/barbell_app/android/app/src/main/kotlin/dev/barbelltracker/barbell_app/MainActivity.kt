package dev.barbelltracker.barbell_app

import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine

class MainActivity : FlutterActivity() {
    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        SetVideoExportChannel(applicationContext, flutterEngine.dartExecutor.binaryMessenger)
    }
}
