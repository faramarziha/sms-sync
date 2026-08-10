package com.example.sms_sync

import android.content.Context
import android.content.Intent
import android.net.Uri
import android.os.Build
import android.os.Bundle
import android.provider.Telephony
import android.telephony.SubscriptionManager
import android.telephony.TelephonyManager
import android.webkit.MimeTypeMap
import androidx.activity.enableEdgeToEdge
import androidx.annotation.NonNull
import androidx.core.content.FileProvider
import io.flutter.embedding.android.FlutterFragmentActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.io.File

class MainActivity : FlutterFragmentActivity() {
    private val CHANNEL = "com.example.sms_sync/native_channel"

    override fun onCreate(savedInstanceState: Bundle?) {
        enableEdgeToEdge()
        super.onCreate(savedInstanceState)
    }

    override fun configureFlutterEngine(@NonNull flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL).setMethodCallHandler { call, result ->
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
            val extension = MimeTypeMap.getFileExtensionFromUrl(Uri.fromFile(file).toString())
            val mimeType = MimeTypeMap.getSingleton().getMimeTypeFromExtension(extension.lowercase()) ?: "*/*"

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
            "${Telephony.Sms.DATE} DESC LIMIT $limit"
        )

        cursor?.use {
            val idIndex = it.getColumnIndex(Telephony.Sms._ID)
            val addressIndex = it.getColumnIndex(Telephony.Sms.ADDRESS)
            val bodyIndex = it.getColumnIndex(Telephony.Sms.BODY)
            val dateIndex = it.getColumnIndex(Telephony.Sms.DATE)
            val typeIndex = it.getColumnIndex(Telephony.Sms.TYPE)
            val threadIdIndex = it.getColumnIndex(Telephony.Sms.THREAD_ID)

            while (it.moveToNext()) {
                val sms = mapOf(
                    "id" to it.getLong(idIndex),
                    "address" to it.getString(addressIndex),
                    "body" to it.getString(bodyIndex),
                    "date" to it.getLong(dateIndex),
                    "type" to it.getInt(typeIndex),
                    "thread_id" to it.getLong(threadIdIndex)
                )
                smsList.add(sms)
            }
        }

        return smsList
    }
}
