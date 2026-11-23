package com.repform.repform_app

import android.app.Activity
import android.content.Context
import android.media.AudioAttributes
import android.media.AudioFocusRequest
import android.media.AudioManager
import android.media.ToneGenerator
import android.os.Build
import android.os.Handler
import android.os.Looper
import android.speech.tts.TextToSpeech
import android.speech.tts.UtteranceProgressListener
import android.view.WindowManager
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import java.util.Locale

class WorkoutAudio(private val activity: Activity, private val channel: MethodChannel) :
    MethodChannel.MethodCallHandler, TextToSpeech.OnInitListener {
    private val preferences = activity.getSharedPreferences("workout_audio", Context.MODE_PRIVATE)
    private val manager = activity.getSystemService(Context.AUDIO_SERVICE) as AudioManager
    private val handler = Handler(Looper.getMainLooper())
    private val attributes = AudioAttributes.Builder()
        .setUsage(AudioAttributes.USAGE_ASSISTANCE_NAVIGATION_GUIDANCE)
        .setContentType(AudioAttributes.CONTENT_TYPE_SPEECH).build()
    private var speech: TextToSpeech? = null
    private var tones: ToneGenerator? = null
    private var ready = false
    private var closed = false
    private var generation = 0
    private var focusRequest: AudioFocusRequest? = null
    private val focusListener = AudioManager.OnAudioFocusChangeListener { change ->
        if (change < 0) stop()
    }

    init {
        channel.setMethodCallHandler(this)
        speech = TextToSpeech(activity, this)
        try { tones = ToneGenerator(AudioManager.STREAM_MUSIC, 75) } catch (_: RuntimeException) { }
        if (Build.VERSION.SDK_INT >= 26) {
            focusRequest = AudioFocusRequest.Builder(AudioManager.AUDIOFOCUS_GAIN_TRANSIENT_MAY_DUCK)
                .setAudioAttributes(attributes).setOnAudioFocusChangeListener(focusListener).build()
        }
    }

    override fun onInit(status: Int) {
        if (closed) return
        val engine = speech ?: return
        if (status == TextToSpeech.SUCCESS && engine.setLanguage(Locale.ENGLISH) >= 0) {
            val offline = engine.voices?.firstOrNull {
                it.locale.language == "en" && !it.isNetworkConnectionRequired
            }
            if (offline != null) {
                engine.voice = offline
                engine.setSpeechRate(0.95f)
                engine.setAudioAttributes(attributes)
                ready = true
            }
        }
        engine.setOnUtteranceProgressListener(object : UtteranceProgressListener() {
            override fun onStart(id: String?) { }
            override fun onDone(id: String?) {
                handler.post { if (id == generation.toString()) releaseFocus() }
            }
            @Deprecated("Called by older TTS engines")
            override fun onError(id: String?) {
                handler.post { if (id == generation.toString()) playTone("ready") }
            }
        })
        handler.post { if (!closed) channel.invokeMethod("availability", ready) }
    }

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            "getSettings" -> result.success(mapOf(
                "mode" to preferences.getString("mode", "voice"),
                "speakReps" to preferences.getBoolean("speakReps", false),
                "voiceAvailable" to ready))
            "setSettings" -> {
                preferences.edit().putString("mode", call.argument<String>("mode"))
                    .putBoolean("speakReps", call.argument<Boolean>("speakReps") ?: false).apply()
                result.success(null)
            }
            "setActive" -> {
                if (call.arguments == true) activity.window.addFlags(WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON)
                else activity.window.clearFlags(WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON)
                result.success(null)
            }
            "cue" -> {
                cue(call.argument<String>("text"), call.argument<String>("tone") ?: "ready",
                    call.argument<String>("mode") ?: "muted")
                result.success(null)
            }
            "stop" -> { stop(); result.success(null) }
            else -> result.notImplemented()
        }
    }

    @Suppress("DEPRECATION")
    private fun requestFocus(): Boolean {
        val result = if (Build.VERSION.SDK_INT >= 26) manager.requestAudioFocus(focusRequest!!)
        else manager.requestAudioFocus(focusListener, AudioManager.STREAM_MUSIC, AudioManager.AUDIOFOCUS_GAIN_TRANSIENT_MAY_DUCK)
        return result == AudioManager.AUDIOFOCUS_REQUEST_GRANTED
    }

    @Suppress("DEPRECATION")
    private fun releaseFocus() {
        if (Build.VERSION.SDK_INT >= 26) focusRequest?.let { manager.abandonAudioFocusRequest(it) }
        else manager.abandonAudioFocus(focusListener)
    }

    private fun cue(text: String?, tone: String, mode: String) {
        stop()
        if (closed || mode == "muted" || !requestFocus()) return
        if (mode == "voice" && ready && !text.isNullOrBlank()) {
            val result = speech?.speak(text, TextToSpeech.QUEUE_FLUSH, null, generation.toString())
            if (result == TextToSpeech.ERROR) playTone(tone)
        } else playTone(tone)
    }

    private fun playTone(kind: String) {
        if (closed) return
        val type = when (kind) {
            "error" -> ToneGenerator.TONE_PROP_NACK
            "reset" -> ToneGenerator.TONE_PROP_PROMPT
            "rep" -> ToneGenerator.TONE_PROP_BEEP
            else -> ToneGenerator.TONE_PROP_ACK
        }
        tones?.startTone(type, if (kind == "rep") 90 else 220)
        val current = generation
        handler.postDelayed({ if (current == generation) releaseFocus() }, 350)
    }

    fun stop() {
        generation++
        speech?.stop()
        tones?.stopTone()
        releaseFocus()
    }

    fun close() {
        closed = true
        stop()
        handler.removeCallbacksAndMessages(null)
        speech?.shutdown()
        tones?.release()
        channel.setMethodCallHandler(null)
        activity.window.clearFlags(WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON)
    }
}
