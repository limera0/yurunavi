package com.westinx.yurunavi

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.app.Service
import android.content.Context
import android.content.Intent
import android.os.Build
import android.os.IBinder
import androidx.core.app.NotificationCompat
import androidx.core.app.NotificationManagerCompat

/**
 * Phase A background navigation: a plain Intent-driven foreground service that keeps the
 * process alive (and TTS audio playing) while the user switches away to another app during
 * a ride. No static singleton/instance reference is kept — every call is a fresh Intent with
 * an action + optional `EXTRA_TEXT`, per the approved plan.
 *
 * Started/updated/stopped from Dart via `lib/services/nav_foreground_service.dart` through the
 * `com.westinx.yurunavi/nav_service` MethodChannel handled in [MainActivity].
 */
class NavForegroundService : Service() {

    companion object {
        const val ACTION_START = "com.westinx.yurunavi.action.NAV_START"
        const val ACTION_UPDATE = "com.westinx.yurunavi.action.NAV_UPDATE"
        const val ACTION_STOP = "com.westinx.yurunavi.action.NAV_STOP"
        const val EXTRA_TEXT = "text"

        private const val CHANNEL_ID = "nav_foreground_channel"
        private const val CHANNEL_NAME = "주행 안내"
        private const val NOTIFICATION_ID = 1001
    }

    override fun onBind(intent: Intent?): IBinder? = null

    /**
     * Called when the user swipes the app away from the recent-apps list. This is the most
     * common way riders "close" the app, and Flutter's widget `dispose()` (which normally
     * sends ACTION_STOP) is not guaranteed to run in that path — leaving the foreground
     * service (and its status-bar notification) alive indefinitely. Mirror the ACTION_STOP
     * cleanup here so the notification is always removed when the task is removed, regardless
     * of whether Dart got a chance to call stop() first.
     */
    override fun onTaskRemoved(rootIntent: Intent?) {
        stopForeground(STOP_FOREGROUND_REMOVE)
        stopSelf()
        super.onTaskRemoved(rootIntent)
    }

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        when (intent?.action) {
            ACTION_START -> {
                createNotificationChannel()
                startForeground(NOTIFICATION_ID, buildNotification(intent.getStringExtra(EXTRA_TEXT)))
            }
            ACTION_UPDATE -> {
                val notification = buildNotification(intent.getStringExtra(EXTRA_TEXT))
                NotificationManagerCompat.from(this).notify(NOTIFICATION_ID, notification)
            }
            ACTION_STOP -> {
                stopForeground(STOP_FOREGROUND_REMOVE)
                stopSelf(startId)
            }
        }
        return START_NOT_STICKY
    }

    private fun createNotificationChannel() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            val manager = getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
            if (manager.getNotificationChannel(CHANNEL_ID) == null) {
                val channel = NotificationChannel(
                    CHANNEL_ID,
                    CHANNEL_NAME,
                    NotificationManager.IMPORTANCE_LOW
                )
                manager.createNotificationChannel(channel)
            }
        }
    }

    private fun buildNotification(text: String?): Notification {
        val contentIntent = (packageManager.getLaunchIntentForPackage(packageName)
            ?: Intent(this, MainActivity::class.java)).apply {
            flags = Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_CLEAR_TOP
        }
        val pendingIntentFlags = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
        } else {
            PendingIntent.FLAG_UPDATE_CURRENT
        }
        val pendingIntent = PendingIntent.getActivity(
            this,
            0,
            contentIntent,
            pendingIntentFlags
        )

        return NotificationCompat.Builder(this, CHANNEL_ID)
            .setContentTitle(CHANNEL_NAME)
            .setContentText(text ?: "")
            .setSmallIcon(R.mipmap.ic_launcher)
            .setContentIntent(pendingIntent)
            .setOngoing(true)
            .setOnlyAlertOnce(true)
            .setPriority(NotificationCompat.PRIORITY_LOW)
            .build()
    }
}
