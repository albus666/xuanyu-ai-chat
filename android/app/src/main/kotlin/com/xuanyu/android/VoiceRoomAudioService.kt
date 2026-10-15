package com.xuanyu.android

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.app.Service
import android.content.Context
import android.content.Intent
import android.content.pm.ServiceInfo
import android.os.Build
import android.os.IBinder
import androidx.core.app.NotificationCompat
import androidx.core.content.ContextCompat

/**
 * Keeps the process eligible to capture microphone audio while a user is on a
 * voice-room seat. Android requires a visible foreground-service notification
 * for background microphone capture.
 */
class VoiceRoomAudioService : Service() {
    companion object {
        private const val channelId = "xuanyu_voice_room_audio"
        private const val notificationId = 23017
        private const val extraTitle = "title"
        private const val extraMicrophone = "microphone"

        private data class Call(val title: String, val microphone: Boolean, val camera: Boolean)
        private val calls = linkedMapOf<String, Call>()

        fun start(context: Context, title: String, microphone: Boolean, owner: String = "room", camera: Boolean = false) {
            calls[owner] = Call(title, microphone, camera)
            update(context)
        }

        fun stop(context: Context, owner: String = "room") {
            calls.remove(owner)
            if (calls.isEmpty()) context.stopService(Intent(context, VoiceRoomAudioService::class.java))
            else update(context)
        }

        private fun update(context: Context) {
            val intent = Intent(context, VoiceRoomAudioService::class.java)
                .putExtra(extraTitle, calls.values.last().title)
                .putExtra(extraMicrophone, calls.values.any { it.microphone })
                .putExtra("camera", calls.values.any { it.camera })
            ContextCompat.startForegroundService(context, intent)
        }

    }

    override fun onCreate() {
        super.onCreate()
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            val manager = getSystemService(NotificationManager::class.java)
            manager.createNotificationChannel(
                NotificationChannel(
                    channelId,
                    "玄遇通话",
                    NotificationManager.IMPORTANCE_LOW,
                ).apply {
                    description = "通话期间保持收听和发言连接"
                    setShowBadge(false)
                },
            )
        }
    }

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        val title = intent?.getStringExtra(extraTitle).orEmpty().ifBlank { "语音房进行中" }
        val microphone = intent?.getBooleanExtra(extraMicrophone, false) == true
        val notification = buildNotification(title)
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
            var serviceType = if (microphone) {
                ServiceInfo.FOREGROUND_SERVICE_TYPE_MICROPHONE or
                    ServiceInfo.FOREGROUND_SERVICE_TYPE_MEDIA_PLAYBACK
            } else {
                ServiceInfo.FOREGROUND_SERVICE_TYPE_MEDIA_PLAYBACK
            }
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R && intent?.getBooleanExtra("camera", false) == true) {
                serviceType = serviceType or ServiceInfo.FOREGROUND_SERVICE_TYPE_CAMERA
            }
            startForeground(
                notificationId,
                notification,
                serviceType,
            )
        } else {
            startForeground(notificationId, notification)
        }
        return START_NOT_STICKY
    }

    override fun onBind(intent: Intent?): IBinder? = null

    override fun onDestroy() {
        stopForeground(STOP_FOREGROUND_REMOVE)
        super.onDestroy()
    }

    private fun buildNotification(title: String): Notification {
        val launchIntent = packageManager.getLaunchIntentForPackage(packageName)
            ?: Intent(this, MainActivity::class.java)
        val pendingIntent = PendingIntent.getActivity(
            this,
            0,
            launchIntent,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
        )
        return NotificationCompat.Builder(this, channelId)
            .setSmallIcon(R.mipmap.ic_launcher)
            .setContentTitle(title)
            .setContentText("通话正在进行，点击返回玄遇")
            .setContentIntent(pendingIntent)
            .setCategory(NotificationCompat.CATEGORY_CALL)
            .setOngoing(true)
            .setOnlyAlertOnce(true)
            .setSilent(true)
            .build()
    }
}
