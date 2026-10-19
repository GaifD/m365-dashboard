package com.gaifd.m365_dashboard

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
import android.os.PowerManager

/**
 * Фоновая служба: держит процесс и процессор живыми, пока идёт поездка,
 * чтобы связь с самокатом и запись не прерывались при выключенном экране.
 */
class RideService : Service() {
    companion object {
        private const val CHANNEL = "ride_v2"
        private const val NOTIF_ID = 365

        @Volatile
        var running = false

        @Volatile
        var lastError: String? = null
        private var title = "M365 Dashboard"
        private var text = "Подключение…"

        fun start(ctx: Context, t: String, x: String): Boolean {
            title = t
            text = x
            if (running) {
                update(ctx, t, x)
                return true
            }
            val i = Intent(ctx, RideService::class.java)
            return try {
                lastError = null
                if (Build.VERSION.SDK_INT >= 26) ctx.startForegroundService(i) else ctx.startService(i)
                true
            } catch (e: Exception) {
                lastError = "start: " + e.toString()
                false
            }
        }

        fun stop(ctx: Context) {
            ctx.stopService(Intent(ctx, RideService::class.java))
        }

        fun update(ctx: Context, t: String, x: String) {
            title = t
            text = x
            if (!running) return
            val nm = ctx.getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
            nm.notify(NOTIF_ID, build(ctx))
        }

        private fun ensureChannel(ctx: Context) {
            if (Build.VERSION.SDK_INT >= 26) {
                val nm = ctx.getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
                if (nm.getNotificationChannel(CHANNEL) == null) {
                    val ch = NotificationChannel(CHANNEL, "Поездка", NotificationManager.IMPORTANCE_DEFAULT)
                    ch.setShowBadge(false)
                    ch.setSound(null, null)
                    ch.enableVibration(false)
                    ch.lockscreenVisibility = Notification.VISIBILITY_PUBLIC
                    nm.createNotificationChannel(ch)
                }
            }
        }

        @Suppress("DEPRECATION")
        private fun builder(ctx: Context): Notification.Builder =
            if (Build.VERSION.SDK_INT >= 26) Notification.Builder(ctx, CHANNEL) else Notification.Builder(ctx)

        fun build(ctx: Context): Notification {
            ensureChannel(ctx)
            val open = ctx.packageManager.getLaunchIntentForPackage(ctx.packageName)
            val flags = PendingIntent.FLAG_UPDATE_CURRENT or
                (if (Build.VERSION.SDK_INT >= 23) PendingIntent.FLAG_IMMUTABLE else 0)
            val pi = PendingIntent.getActivity(ctx, 0, open, flags)
            val b = builder(ctx)
                .setContentTitle(title)
                .setContentText(text)
                .setSmallIcon(android.R.drawable.stat_sys_data_bluetooth)
                .setOngoing(true)
                .setOnlyAlertOnce(true)
                .setShowWhen(false)
                .setContentIntent(pi)
                .setVisibility(Notification.VISIBILITY_PUBLIC)
            if (Build.VERSION.SDK_INT >= 31) {
                b.setForegroundServiceBehavior(Notification.FOREGROUND_SERVICE_IMMEDIATE)
            }
            return b.build()
        }
    }

    private var wakeLock: PowerManager.WakeLock? = null

    override fun onBind(intent: Intent?): IBinder? = null

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        val n = build(this)
        try {
            if (Build.VERSION.SDK_INT >= 29) {
                startForeground(NOTIF_ID, n, ServiceInfo.FOREGROUND_SERVICE_TYPE_CONNECTED_DEVICE)
            } else {
                startForeground(NOTIF_ID, n)
            }
        } catch (e: Exception) {
            lastError = "foreground: " + e.toString()
            stopSelf()
            return START_NOT_STICKY
        }
        running = true
        if (wakeLock == null) {
            val pm = getSystemService(Context.POWER_SERVICE) as PowerManager
            wakeLock = pm.newWakeLock(PowerManager.PARTIAL_WAKE_LOCK, "m365:ride").also { it.acquire() }
        }
        return START_NOT_STICKY
    }

    override fun onDestroy() {
        running = false
        wakeLock?.let { if (it.isHeld) it.release() }
        wakeLock = null
        super.onDestroy()
    }
}
