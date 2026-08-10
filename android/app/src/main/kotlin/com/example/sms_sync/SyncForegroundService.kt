package com.example.sms_sync

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.Service
import android.content.Context
import android.content.Intent
import android.net.wifi.WifiManager
import android.os.Build
import android.os.IBinder
import android.os.PowerManager
import androidx.core.app.NotificationCompat

class SyncForegroundService : Service() {
    private var wakeLock: PowerManager.WakeLock? = null
    private var wifiLock: WifiManager.WifiLock? = null

    companion object {
        const val CHANNEL_ID = "sms_sync_foreground_channel"
        const val NOTIFICATION_ID = 8881
    }

    override fun onCreate() {
        super.onCreate()
        createNotificationChannel()

        // Acquire WakeLock and WifiLock to prevent socket drops when backgrounded
        val powerManager = getSystemService(Context.POWER_SERVICE) as PowerManager
        wakeLock = powerManager.newWakeLock(PowerManager.PARTIAL_WAKE_LOCK, "SMS_Sync::BackgroundWakeLock")
        wakeLock?.acquire(10 * 60 * 1000L) // 10 minutes timeout, renewed by periodic pings

        val wifiManager = applicationContext.getSystemService(Context.WIFI_SERVICE) as WifiManager
        wifiLock = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
            wifiManager.createWifiLock(WifiManager.WIFI_MODE_FULL_HIGH_PERF, "SMS_Sync::WifiLock")
        } else {
            @Suppress("DEPRECATION")
            wifiManager.createWifiLock(WifiManager.WIFI_MODE_FULL, "SMS_Sync::WifiLock")
        }
        wifiLock?.acquire()
    }

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        val notification = createNotification()
        startForeground(NOTIFICATION_ID, notification)
        return START_STICKY
    }

    override fun onBind(intent: Intent?): IBinder? {
        return null
    }

    override fun onDestroy() {
        try {
            if (wakeLock?.isHeld == true) wakeLock?.release()
            if (wifiLock?.isHeld == true) wifiLock?.release()
        } catch (_: Exception) {}
        super.onDestroy()
    }

    private fun createNotificationChannel() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            val channel = NotificationChannel(
                CHANNEL_ID,
                "SMS Sync Background Service",
                NotificationManager.IMPORTANCE_LOW
            ).apply {
                description = "Keeps Wi-Fi synchronization active when app is backgrounded."
            }
            val manager = getSystemService(NotificationManager::class.java)
            manager.createNotificationChannel(channel)
        }
    }

    private fun createNotification(): Notification {
        return NotificationCompat.Builder(this, CHANNEL_ID)
            .setContentTitle("SMS Sync Active")
            .setContentText("Connected to PC — Background sync running")
            .setSmallIcon(android.R.drawable.stat_notify_sync)
            .setOngoing(true)
            .setPriority(NotificationCompat.PRIORITY_LOW)
            .build()
    }
}
