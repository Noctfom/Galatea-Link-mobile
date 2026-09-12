// Galatea Link mobile 对局保活服务，在连接期间维持进程和网络响应

package com.noctfom.galatealink

import android.annotation.SuppressLint
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.app.Service
import android.content.Context
import android.content.Intent
import android.os.Build
import android.os.IBinder
import android.os.PowerManager
import androidx.core.app.NotificationCompat
import androidx.core.content.ContextCompat

class DuelKeepAliveService : Service() {
    companion object {
        private const val channelId = "galatea_duel_connection"
        private const val notificationId = 7319
        private const val wakeLockTag = "GalateaLinkMobile:DuelConnection"

        // 从前台应用启动对局保活服务
        fun start(context: Context) {
            val intent = Intent(context, DuelKeepAliveService::class.java)
            ContextCompat.startForegroundService(context, intent)
        }

        // 在游戏断开后停止对局保活服务
        fun stop(context: Context) {
            context.stopService(Intent(context, DuelKeepAliveService::class.java))
        }
    }

    private var wakeLock: PowerManager.WakeLock? = null

    // 创建通知通道并持有连接期间 CPU 唤醒锁
    override fun onCreate() {
        super.onCreate()
        createNotificationChannel()
        acquireWakeLock()
    }

    // 显示持续通知并保持服务直到主动断开
    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        val openApp = PendingIntent.getActivity(
            this,
            0,
            Intent(this, MainActivity::class.java).apply {
                this.flags = Intent.FLAG_ACTIVITY_SINGLE_TOP
            },
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
        )
        val notification = NotificationCompat.Builder(this, channelId)
            .setSmallIcon(R.drawable.ic_stat_link)
            .setContentTitle("Galatea Link mobile")
            .setContentText("游戏连接运行中")
            .setContentIntent(openApp)
            .setOngoing(true)
            .setSilent(true)
            .setCategory(NotificationCompat.CATEGORY_SERVICE)
            .build()
        startForeground(notificationId, notification)
        return START_NOT_STICKY
    }

    // 释放连接期间持有的系统资源
    override fun onDestroy() {
        wakeLock?.takeIf { it.isHeld }?.release()
        wakeLock = null
        super.onDestroy()
    }

    // 前台保活服务不提供绑定接口
    override fun onBind(intent: Intent?): IBinder? = null

    // 创建低干扰的对局连接通知通道
    private fun createNotificationChannel() {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O) return
        val channel = NotificationChannel(
            channelId,
            "游戏连接",
            NotificationManager.IMPORTANCE_LOW,
        ).apply {
            description = "保持 Galatea Link mobile 在对局期间正常响应"
            setShowBadge(false)
        }
        getSystemService(NotificationManager::class.java)
            .createNotificationChannel(channel)
    }

    // 获取仅在活动对局期间使用的局部 CPU 唤醒锁
    @SuppressLint("WakelockTimeout")
    private fun acquireWakeLock() {
        val manager = getSystemService(POWER_SERVICE) as PowerManager
        wakeLock = manager.newWakeLock(
            PowerManager.PARTIAL_WAKE_LOCK,
            wakeLockTag,
        ).apply { acquire() }
    }
}
