package com.yunxu.yunxulearn

import android.app.AlarmManager
import android.app.PendingIntent
import android.content.Context
import android.content.Intent
import android.os.Build
import androidx.core.app.NotificationManagerCompat
import com.dexterous.flutterlocalnotifications.ScheduledNotificationReceiver
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            ANDROID_MAINTENANCE_CHANNEL,
        ).setMethodCallHandler { call, result ->
            when (call.method) {
                CLEAR_SCHEDULED_NOTIFICATION_CACHE_METHOD -> {
                    val notificationId = call.argument<Int>("notificationId")
                    if (notificationId == null) {
                        result.error(
                            "missing_notification_id",
                            "notificationId is required.",
                            null,
                        )
                        return@setMethodCallHandler
                    }

                    clearScheduledNotificationCache(notificationId)
                    result.success(null)
                }

                else -> result.notImplemented()
            }
        }
    }

    private fun clearScheduledNotificationCache(notificationId: Int) {
        getSharedPreferences(SCHEDULED_NOTIFICATIONS_PREFS, Context.MODE_PRIVATE)
            .edit()
            .remove(SCHEDULED_NOTIFICATIONS_KEY)
            .apply()

        val intent = Intent(this, ScheduledNotificationReceiver::class.java)
        var flags = PendingIntent.FLAG_UPDATE_CURRENT
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
            flags = flags or PendingIntent.FLAG_IMMUTABLE
        }
        val pendingIntent = PendingIntent.getBroadcast(this, notificationId, intent, flags)
        val alarmManager = getSystemService(Context.ALARM_SERVICE) as AlarmManager
        alarmManager.cancel(pendingIntent)
        NotificationManagerCompat.from(this).cancel(notificationId)
    }

    companion object {
        private const val ANDROID_MAINTENANCE_CHANNEL =
            "com.yunxu.yunxulearn/android_maintenance"
        private const val CLEAR_SCHEDULED_NOTIFICATION_CACHE_METHOD =
            "clearScheduledNotificationCache"
        private const val SCHEDULED_NOTIFICATIONS_PREFS = "scheduled_notifications"
        private const val SCHEDULED_NOTIFICATIONS_KEY = "scheduled_notifications"
    }
}
