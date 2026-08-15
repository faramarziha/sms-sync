package com.faramarzi.smssync

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.content.IntentFilter
import android.net.Uri
import android.os.Build
import android.os.Bundle
import android.os.Handler
import android.os.Looper
import android.provider.Telephony
import android.telephony.SmsMessage
import android.telephony.SubscriptionManager
import android.telephony.TelephonyManager
import android.webkit.MimeTypeMap
import androidx.activity.enableEdgeToEdge
import androidx.annotation.NonNull
import androidx.core.content.ContextCompat
import androidx.core.content.FileProvider
import io.flutter.embedding.android.FlutterFragmentActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.io.File

class MainActivity : FlutterFragmentActivity() {
    private val CHANNEL = "com.faramarzi.smssync/native_channel"
    private var methodChannel: MethodChannel? = null
    private var smsReceiver: BroadcastReceiver? = null

    override fun onCreate(savedInstanceState: Bundle?) {
        enableEdgeToEdge()
        super.onCreate(savedInstanceState)
        registerSmsReceiver()
    }

    override fun onDestroy() {
        unregisterSmsReceiver()
        super.onDestroy()
    }

    private fun registerSmsReceiver() {
        if (smsReceiver != null) return
        smsReceiver = object : BroadcastReceiver() {
            override fun onReceive(context: Context?, intent: Intent?) {
                if (intent?.action == Telephony.Sms.Intents.SMS_RECEIVED_ACTION) {
                    // Acquire instant 5s temporary WakeLock to guarantee CPU stays awake during transmission
                    try {
                        val powerManager = getSystemService(Context.POWER_SERVICE) as? android.os.PowerManager
                        val wakeLock = powerManager?.newWakeLock(android.os.PowerManager.PARTIAL_WAKE_LOCK, "SMS_Sync::IncomingSmsWakeLock")
                        wakeLock?.acquire(5000L)
                    } catch (_: Exception) {}

                    val messages = Telephony.Sms.Intents.getMessagesFromIntent(intent)
                    if (messages != null && messages.isNotEmpty()) {
                        val grouped = messages.groupBy { it.originatingAddress ?: "Unknown" }
                        for ((address, partList) in grouped) {
                            val fullBody = StringBuilder()
                            var latestTimestamp = 0L
                            for (part in partList) {
                                fullBody.append(part.displayMessageBody ?: part.messageBody ?: "")
                                if (part.timestampMillis > latestTimestamp) {
                                    latestTimestamp = part.timestampMillis
                                }
                            }
                            val smsData = mapOf(
                                "address" to address,
                                "body" to fullBody.toString(),
                                "date" to latestTimestamp,
                                "id" to latestTimestamp
                            )
                            Handler(Looper.getMainLooper()).post {
                                methodChannel?.invokeMethod("onSmsReceived", smsData)
                            }
                        }
                    }
                }
            }
        }
        val filter = IntentFilter(Telephony.Sms.Intents.SMS_RECEIVED_ACTION)
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
            ContextCompat.registerReceiver(this, smsReceiver, filter, ContextCompat.RECEIVER_EXPORTED)
        } else {
            registerReceiver(smsReceiver, filter)
        }
    }

    private fun unregisterSmsReceiver() {
        smsReceiver?.let {
            try {
                unregisterReceiver(it)
            } catch (_: Exception) {}
            smsReceiver = null
        }
    }

    override fun configureFlutterEngine(@NonNull flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        methodChannel = MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL)
        methodChannel?.setMethodCallHandler { call, result ->
            when (call.method) {
                "getSubscriptionInfo" -> {
                    val info = getSubscriptionInfo()
                    result.success(info)
                }
                "getRecentSms" -> {
                    val limit = call.argument<Int>("limit") ?: 50
                    val smsList = getRecentSms(limit)
                    result.success(smsList)
                }
                "openFile" -> {
                    val path = call.argument<String>("path")
                    if (path != null) {
                        val success = openFile(path)
                        result.success(success)
                    } else {
                        result.error("INVALID_PATH", "Path is null", null)
                    }
                }
                "startForegroundService" -> {
                    startForegroundSyncService()
                    result.success(true)
                }
                "stopForegroundService" -> {
                    stopForegroundSyncService()
                    result.success(true)
                }
                "isIgnoringBatteryOptimizations" -> {
                    val powerManager = getSystemService(Context.POWER_SERVICE) as? android.os.PowerManager
                    val isIgnoring = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
                        powerManager?.isIgnoringBatteryOptimizations(packageName) ?: false
                    } else {
                        true
                    }
                    result.success(isIgnoring)
                }
                "requestIgnoreBatteryOptimizations" -> {
                    if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
                        try {
                            val intent = Intent(android.provider.Settings.ACTION_REQUEST_IGNORE_BATTERY_OPTIMIZATIONS).apply {
                                data = Uri.parse("package:$packageName")
                            }
                            startActivity(intent)
                            result.success(true)
                        } catch (e: Exception) {
                            try {
                                val intent = Intent(android.provider.Settings.ACTION_IGNORE_BATTERY_OPTIMIZATION_SETTINGS)
                                startActivity(intent)
                                result.success(true)
                            } catch (e2: Exception) {
                                result.success(false)
                            }
                        }
                    } else {
                        result.success(true)
                    }
                }
                else -> {
                    result.notImplemented()
                }
            }
        }
    }

    private fun startForegroundSyncService() {
        val serviceIntent = Intent(this, SyncForegroundService::class.java)
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            startForegroundService(serviceIntent)
        } else {
            startService(serviceIntent)
        }
    }

    private fun stopForegroundSyncService() {
        val serviceIntent = Intent(this, SyncForegroundService::class.java)
        stopService(serviceIntent)
    }

    private fun openFile(path: String): Boolean {
        return try {
            val file = File(path)
            if (!file.exists()) return false

            val uri: Uri = FileProvider.getUriForFile(this, "$packageName.fileprovider", file)
            val extension = file.extension
            val mimeType = if (extension.isNotEmpty()) {
                MimeTypeMap.getSingleton().getMimeTypeFromExtension(extension.lowercase()) ?: "*/*"
            } else {
                "*/*"
            }

            val intent = Intent(Intent.ACTION_VIEW).apply {
                setDataAndType(uri, mimeType)
                addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
                addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
            }
            startActivity(intent)
            true
        } catch (e: Exception) {
            e.printStackTrace()
            false
        }
    }

    private fun getSubscriptionInfo(): List<Map<String, Any?>> {
        val subscriptions = mutableListOf<Map<String, Any?>>()
        val subscriptionManager = getSystemService(Context.TELEPHONY_SUBSCRIPTION_SERVICE) as? SubscriptionManager ?: return subscriptions

        try {
            val activeSubscriptions = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.LOLLIPOP_MR1) {
                subscriptionManager.activeSubscriptionInfoList
            } else {
                null
            }

            activeSubscriptions?.forEach { info ->
                val data = mutableMapOf<String, Any?>()
                if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.LOLLIPOP_MR1) {
                    data["subscription_id"] = info.subscriptionId
                    data["phone_number"] = info.number ?: ""
                    data["carrier_name"] = info.displayName.toString()
                    data["sim_slot"] = info.simSlotIndex
                }
                subscriptions.add(data)
            }
        } catch (e: SecurityException) {
            // Handle missing permission
        }

        return subscriptions
    }

    private fun getRecentSms(limit: Int): List<Map<String, Any?>> {
        val smsList = mutableListOf<Map<String, Any?>>()
        try {
            val cursor = contentResolver.query(
                Telephony.Sms.CONTENT_URI,
                arrayOf(
                    Telephony.Sms._ID,
                    Telephony.Sms.ADDRESS,
                    Telephony.Sms.BODY,
                    Telephony.Sms.DATE,
                    Telephony.Sms.TYPE,
                    Telephony.Sms.THREAD_ID
                ),
                null,
                null,
                "${Telephony.Sms.DATE} DESC"
            )

            cursor?.use {
                val idIndex = it.getColumnIndex(Telephony.Sms._ID)
                val addressIndex = it.getColumnIndex(Telephony.Sms.ADDRESS)
                val bodyIndex = it.getColumnIndex(Telephony.Sms.BODY)
                val dateIndex = it.getColumnIndex(Telephony.Sms.DATE)
                val typeIndex = it.getColumnIndex(Telephony.Sms.TYPE)
                val threadIdIndex = it.getColumnIndex(Telephony.Sms.THREAD_ID)

                var count = 0
                while (it.moveToNext() && count < limit) {
                    val sms = mapOf(
                        "id" to it.getLong(idIndex),
                        "address" to (it.getString(addressIndex) ?: "Unknown"),
                        "body" to (it.getString(bodyIndex) ?: ""),
                        "date" to it.getLong(dateIndex),
                        "type" to it.getInt(typeIndex),
                        "thread_id" to it.getLong(threadIdIndex)
                    )
                    smsList.add(sms)
                    count++
                }
            }
        } catch (e: SecurityException) {
            // Missing READ_SMS permission
        } catch (e: Exception) {
            e.printStackTrace()
        }

        return smsList
    }
}
