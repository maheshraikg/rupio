package com.kspstadk.rupeetrack

import android.Manifest
import android.content.ActivityNotFoundException
import android.content.Intent
import android.content.pm.PackageManager
import android.net.Uri
import android.os.Build
import android.os.Bundle
import android.provider.Settings
import android.provider.Telephony
import java.io.File
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

/**
 * Small native bridge ("rupeetrack/native"):
 *  - openApp / isInstalled: hand off to a payment app (CRED, PhonePe, ...).
 *  - smsPermission / requestSmsPermission / openAppSettings: READ_SMS access.
 *  - readSms: bank messages from the SMS inbox, read on the phone only.
 *  - takeSharedPdf, and "sharedPdf" calls to Dart: statement PDFs shared to
 *    or opened with the app, copied to the cache folder.
 *  - updateWidget: new figures for the home screen widget.
 */
class MainActivity : FlutterActivity() {
    private var channel: MethodChannel? = null
    private var pendingPermission: MethodChannel.Result? = null
    private var pendingSharedPdf: String? = null

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        pendingSharedPdf = sharedPdfFrom(intent)
    }

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        val path = sharedPdfFrom(intent) ?: return
        val ch = channel
        if (ch != null) ch.invokeMethod("sharedPdf", path) else pendingSharedPdf = path
    }

    /** Copies a PDF from a SEND / VIEW intent into the cache folder. */
    @Suppress("DEPRECATION")
    private fun sharedPdfFrom(intent: Intent?): String? {
        if (intent == null) return null
        val uri: Uri? = when (intent.action) {
            Intent.ACTION_SEND -> intent.getParcelableExtra<Uri>(Intent.EXTRA_STREAM)
            Intent.ACTION_VIEW -> intent.data
            else -> null
        }
        if (uri == null) return null
        val type = intent.type ?: contentResolver.getType(uri) ?: ""
        if (!type.contains("pdf") && !uri.toString().lowercase().endsWith(".pdf")) return null
        return try {
            val out = File(cacheDir, "shared-${System.currentTimeMillis()}.pdf")
            contentResolver.openInputStream(uri)?.use { input ->
                out.outputStream().use { input.copyTo(it) }
            } ?: return null
            out.absolutePath
        } catch (e: Exception) {
            null
        }
    }

    private fun smsPermissionState(): String = when {
        checkSelfPermission(Manifest.permission.READ_SMS) ==
            PackageManager.PERMISSION_GRANTED -> "granted"
        else -> "denied"
    }

    override fun onRequestPermissionsResult(
        requestCode: Int,
        permissions: Array<out String>,
        grantResults: IntArray
    ) {
        super.onRequestPermissionsResult(requestCode, permissions, grantResults)
        if (requestCode != SMS_REQUEST) return
        val granted = grantResults.isNotEmpty() &&
            grantResults[0] == PackageManager.PERMISSION_GRANTED
        // Refused with "don't ask again" (or blocked by policy): only the
        // system settings can turn it on now.
        val state = when {
            granted -> "granted"
            !shouldShowRequestPermissionRationale(Manifest.permission.READ_SMS) -> "blocked"
            else -> "denied"
        }
        pendingPermission?.success(state)
        pendingPermission = null
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        val ch = MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "rupeetrack/native")
        channel = ch
        ch.setMethodCallHandler { call, result ->
                when (call.method) {
                    "smsPermission" -> result.success(smsPermissionState())
                    "requestSmsPermission" -> {
                        if (smsPermissionState() == "granted") {
                            result.success("granted")
                        } else {
                            pendingPermission?.success("denied")
                            pendingPermission = result
                            requestPermissions(arrayOf(Manifest.permission.READ_SMS), SMS_REQUEST)
                        }
                    }
                    "openAppSettings" -> {
                        startActivity(
                            Intent(
                                Settings.ACTION_APPLICATION_DETAILS_SETTINGS,
                                Uri.fromParts("package", packageName, null)
                            ).addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                        )
                        result.success(null)
                    }
                    "takeSharedPdf" -> {
                        result.success(pendingSharedPdf)
                        pendingSharedPdf = null
                    }
                    "updateWidget" -> {
                        SpendWidgetProvider.save(applicationContext, call.argument<String>("json")!!)
                        result.success(null)
                    }
                    "openApp" -> result.success(openApp(call.argument<String>("package")!!))
                    "sendEmail" -> result.success(
                        sendEmail(
                            call.argument<String>("to")!!,
                            call.argument<String>("subject")!!,
                            call.argument<String>("body")!!,
                        )
                    )
                    "deviceInfo" -> result.success(
                        mapOf(
                            "app" to (try {
                                packageManager.getPackageInfo(packageName, 0).versionName
                            } catch (e: Exception) { null } ?: "?"),
                            "android" to Build.VERSION.RELEASE,
                            "device" to "${Build.MANUFACTURER} ${Build.MODEL}",
                        )
                    )
                    "isInstalled" -> result.success(
                        packageManager.getLaunchIntentForPackage(
                            call.argument<String>("package")!!
                        ) != null
                    )
                    "readSms" -> {
                        if (checkSelfPermission(Manifest.permission.READ_SMS) !=
                            PackageManager.PERMISSION_GRANTED
                        ) {
                            result.error("permission", "SMS permission not granted", null)
                        } else {
                            val since = call.argument<Number>("since")?.toLong() ?: 0L
                            val limit = call.argument<Int>("limit") ?: 5000
                            // Cursor work off the UI thread; reply on it.
                            Thread {
                                try {
                                    val messages = readSms(since, limit)
                                    runOnUiThread { result.success(messages) }
                                } catch (e: Exception) {
                                    runOnUiThread { result.error("read", e.message, null) }
                                }
                            }.start()
                        }
                    }
                    else -> result.notImplemented()
                }
            }
    }

    companion object {
        private const val SMS_REQUEST = 4021
    }

    /** Opens [pkg]; if it is not installed, opens its Play Store page. */
    private fun openApp(pkg: String): Boolean {
        val launch = packageManager.getLaunchIntentForPackage(pkg)
        if (launch != null) {
            startActivity(launch.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK))
            return true
        }
        try {
            startActivity(
                Intent(Intent.ACTION_VIEW, Uri.parse("market://details?id=$pkg"))
                    .addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
            )
        } catch (e: ActivityNotFoundException) {
            startActivity(
                Intent(
                    Intent.ACTION_VIEW,
                    Uri.parse("https://play.google.com/store/apps/details?id=$pkg")
                ).addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
            )
        }
        return false
    }

    /** Inbox messages newer than [since] (epoch millis), newest first. */
    private fun readSms(since: Long, limit: Int): List<Map<String, Any?>> {
        val out = ArrayList<Map<String, Any?>>()
        contentResolver.query(
            Telephony.Sms.Inbox.CONTENT_URI,
            arrayOf(Telephony.Sms.ADDRESS, Telephony.Sms.BODY, Telephony.Sms.DATE),
            "${Telephony.Sms.DATE} > ?",
            arrayOf(since.toString()),
            "${Telephony.Sms.DATE} DESC"
        )?.use { c ->
            val address = c.getColumnIndexOrThrow(Telephony.Sms.ADDRESS)
            val body = c.getColumnIndexOrThrow(Telephony.Sms.BODY)
            val date = c.getColumnIndexOrThrow(Telephony.Sms.DATE)
            while (c.moveToNext() && out.size < limit) {
                out.add(
                    mapOf(
                        "address" to c.getString(address),
                        "body" to c.getString(body),
                        "date" to c.getLong(date)
                    )
                )
            }
        }
        return out
    }

    /** Opens the user's email app with a draft; false when there is none. */
    private fun sendEmail(to: String, subject: String, body: String): Boolean {
        val intent = Intent(Intent.ACTION_SENDTO, Uri.parse("mailto:"))
            .putExtra(Intent.EXTRA_EMAIL, arrayOf(to))
            .putExtra(Intent.EXTRA_SUBJECT, subject)
            .putExtra(Intent.EXTRA_TEXT, body)
        return try {
            startActivity(intent)
            true
        } catch (e: ActivityNotFoundException) {
            false
        }
    }
}
