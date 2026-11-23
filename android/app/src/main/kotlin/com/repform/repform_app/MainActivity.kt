package com.repform.repform_app

import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    private var workoutAudio: WorkoutAudio? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        workoutAudio = WorkoutAudio(this, MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "fittracker/workout_audio"))
    }

    override fun onPause() {
        workoutAudio?.stop()
        super.onPause()
    }

    override fun onDestroy() {
        workoutAudio?.close()
        super.onDestroy()
    }
}
