package com.example.awa

import android.content.Context
import android.media.AudioManager
import android.os.Bundle
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity: FlutterActivity() {

    private val CHANNEL = "com.example.awa/audio"

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL).setMethodCallHandler { call, result ->
            when (call.method) {
                "muteVoiceFeedback" -> {
                    muteVoiceFeedback()
                    result.success(null)
                }
                "unmuteVoiceFeedback" -> {
                    unmuteVoiceFeedback()
                    result.success(null)
                }
                else -> result.notImplemented()
            }
        }
    }

    private fun muteVoiceFeedback() {
        try {
            val audioManager = getSystemService(Context.AUDIO_SERVICE) as AudioManager
            val streams = listOf(
                AudioManager.STREAM_ACCESSIBILITY,
                AudioManager.STREAM_VOICE_CALL,
                AudioManager.STREAM_NOTIFICATION
            )
            for (s in streams) {
                audioManager.adjustStreamVolume(s, AudioManager.ADJUST_MUTE, 0)
            }
        } catch (e: Exception) {
            e.printStackTrace()
        }
    }

    private fun unmuteVoiceFeedback() {
        try {
            val audioManager = getSystemService(Context.AUDIO_SERVICE) as AudioManager
            val streams = listOf(
                AudioManager.STREAM_ACCESSIBILITY,
                AudioManager.STREAM_VOICE_CALL,
                AudioManager.STREAM_NOTIFICATION
            )
            for (s in streams) {
                audioManager.adjustStreamVolume(s, AudioManager.ADJUST_UNMUTE, 0)
            }
        } catch (e: Exception) {
            e.printStackTrace()
        }
    }
}
