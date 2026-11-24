package com.repform.repform_app

import android.app.Activity
import android.content.Context
import android.media.AudioAttributes
import android.media.AudioFocusRequest
import android.media.AudioManager
import android.media.ToneGenerator
import android.media.SoundPool
import android.media.MediaMetadataRetriever
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
    private val repSounds = SoundPool.Builder().setMaxStreams(1)
        .setAudioAttributes(attributes).build()
    private var repSoundId = 0
    private var repStream = 0
    private var repReady = false
    private var repDurationMs = 700L
    private var soundGeneration = 0
    private var soundPlaying = false
    private var speaking = false
    private var speechPending = false
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
        repSounds.setOnLoadCompleteListener { _, id, status ->
            handler.post { if (!closed && id == repSoundId) repReady = status == 0 }
        }
        try {
            val metadata = MediaMetadataRetriever()
            try {
                activity.resources.openRawResourceFd(R.raw.rep_beep).use { file ->
                    metadata.setDataSource(file.fileDescriptor, file.startOffset, file.length)
                    repDurationMs = metadata.extractMetadata(MediaMetadataRetriever.METADATA_KEY_DURATION)
                        ?.toLongOrNull() ?: repDurationMs
                }
            } finally { metadata.release() }
            repSoundId = repSounds.load(activity, R.raw.rep_beep, 1)
        } catch (_: RuntimeException) { /* Short tone remains available if decoding fails. */ }
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
                handler.post {
                    if (id == generation.toString()) {
                        speaking = false
                        releaseIfQuiet()
                    }
                }
            }
            @Deprecated("Called by older TTS engines")
            override fun onError(id: String?) {
                handler.post {
                    if (id == generation.toString()) {
                        speaking = false
                        playTone("ready")
                    }
                }
            }
        })
        handler.post { if (!closed) channel.invokeMethod("availability", ready) }
    }

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            "getSettings" -> result.success(mapOf(
                "mode" to preferences.getString("mode", "voice"),
                "voiceAvailable" to ready))
            "setSettings" -> {
                preferences.edit().putString("mode", call.argument<String>("mode"))
                    .remove("speakReps").apply()
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

    private fun releaseIfQuiet() {
        if (!speaking && !speechPending && !soundPlaying) releaseFocus()
    }

    private fun cue(text: String?, tone: String, mode: String) {
        if (closed) return
        if (mode == "muted") { stop(); return }
        if (tone == "rep") {
            if (!requestFocus()) return
            val duration = playRep()
            // Ordinary beeps leave a brief milestone sentence free to finish.
            if (mode == "voice" && ready && !text.isNullOrBlank()) speak(text, duration + 30)
        } else {
            stop()
            if (!requestFocus()) return
            if (mode == "voice" && ready && !text.isNullOrBlank()) speak(text)
            else playTone(tone)
        }
    }

    private fun speak(text: String, delayMs: Long = 0) {
        val current = ++generation
        speech?.stop()
        speaking = false
        speechPending = true
        handler.postDelayed({
            if (!closed && current == generation) {
                speechPending = false
                speaking = true
                if (speech?.speak(text, TextToSpeech.QUEUE_FLUSH, null, current.toString()) != TextToSpeech.SUCCESS) {
                    speaking = false
                    playTone("ready")
                }
            }
        }, delayMs)
    }

    private fun stopSound() {
        soundGeneration++
        tones?.stopTone()
        if (repStream != 0) repSounds.stop(repStream)
        repStream = 0
        soundPlaying = false
    }

    private fun soundEndsAfter(duration: Long) {
        soundPlaying = true
        val current = soundGeneration
        handler.postDelayed({
            if (!closed && current == soundGeneration) {
                soundPlaying = false
                releaseIfQuiet()
            }
        }, duration + 50)
    }

    private fun playRep(): Long {
        stopSound()
        if (repReady) {
            repStream = repSounds.play(repSoundId, 1f, 1f, 1, 0, 1f)
            if (repStream != 0) {
                soundEndsAfter(repDurationMs)
                return repDurationMs
            }
        }
        playTone("rep")
        return 90
    }

    private fun playTone(kind: String) {
        if (closed) return
        stopSound()
        val type = when (kind) {
            "error" -> ToneGenerator.TONE_PROP_NACK
            "reset" -> ToneGenerator.TONE_PROP_PROMPT
            "rep" -> ToneGenerator.TONE_PROP_BEEP
            else -> ToneGenerator.TONE_PROP_ACK
        }
        val duration = if (kind == "rep") 90 else 220
        tones?.startTone(type, duration)
        soundEndsAfter(duration.toLong())
    }

    fun stop() {
        generation++
        speechPending = false
        speaking = false
        speech?.stop()
        stopSound()
        releaseFocus()
    }

    fun close() {
        closed = true
        stop()
        handler.removeCallbacksAndMessages(null)
        speech?.shutdown()
        tones?.release()
        repSounds.release()
        channel.setMethodCallHandler(null)
        activity.window.clearFlags(WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON)
    }
}
