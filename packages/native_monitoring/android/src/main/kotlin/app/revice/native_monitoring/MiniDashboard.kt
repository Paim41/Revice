package app.revice.native_monitoring

import android.Manifest
import android.app.Activity
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.graphics.Color
import android.os.Build
import android.provider.Settings
import androidx.core.app.ActivityCompat
import androidx.core.app.NotificationCompat
import androidx.core.app.NotificationManagerCompat
import androidx.core.content.ContextCompat
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import org.json.JSONArray
import org.json.JSONObject
import java.text.SimpleDateFormat
import java.util.Date
import java.util.Locale

class DashboardDismissReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent) {
        if (intent.action == "app.revice.DISMISS_DASHBOARD") {
            context.getSharedPreferences("revice", Context.MODE_PRIVATE).edit().putBoolean("miniDismissed", true).apply()
        }
    }
}

/** One silent notification, powered only by telemetry delivered by existing monitors. */
class MiniDashboard(private val context: Context, private val channel: MethodChannel) {
    companion object { const val ID = 4101; const val CHANNEL = "revice_mini_dashboard"; const val PERMISSION = 4102; const val TARGET = "reviceDashboardTarget" }
    private val prefs get() = context.getSharedPreferences("revice", Context.MODE_PRIVATE)
    private val manager get() = NotificationManagerCompat.from(context)
    var activity: Activity? = null
    private var permissionResult: MethodChannel.Result? = null
    private var navigation: String? = null
    private var lastRendered: String? = null

    private fun options() = JSONObject(prefs.getString("miniOptions", "{}") ?: "{}")
    private fun allowed(): Boolean = manager.areNotificationsEnabled() &&
        (Build.VERSION.SDK_INT < 33 || ContextCompat.checkSelfPermission(context, Manifest.permission.POST_NOTIFICATIONS) == PackageManager.PERMISSION_GRANTED) &&
        (Build.VERSION.SDK_INT < 26 || context.getSystemService(NotificationManager::class.java).getNotificationChannel(CHANNEL)?.importance != NotificationManager.IMPORTANCE_NONE)

    fun acceptIntent(intent: Intent?) {
        val target = intent?.getStringExtra(TARGET)
        if (target == "home" || target == "devices") { navigation = target; intent.removeExtra(TARGET); channel.invokeMethod("navigationAvailable", null) }
    }
    fun permissionResult(code: Int): Boolean {
        if (code != PERMISSION) return false
        permissionResult?.success(allowed()); permissionResult = null
        return true
    }
    fun detach(final: Boolean) {
        activity = null
        if (final) { permissionResult?.success(false); permissionResult = null }
    }

    fun handle(call: MethodCall, result: MethodChannel.Result) {
        try {
            when (call.method) {
                "load" -> result.success(mapOf("options" to options().toString(), "allowed" to allowed(), "dismissed" to prefs.getBoolean("miniDismissed", false)))
                "save" -> {
                    val opts = JSONObject(call.argument<String>("options") ?: "{}")
                    prefs.edit().putString("miniOptions", opts.toString()).apply()
                    if (call.argument<Boolean>("showAgain") == true) prefs.edit().putBoolean("miniDismissed", false).apply()
                    if (!opts.optBoolean("enabled", false)) {
                        prefs.edit().remove("miniData").apply(); manager.cancel(ID); lastRendered = null
                    } else render()
                    result.success(null)
                }
                "update" -> {
                    // Do not retain telemetry for an opted-out feature.
                    if (!options().optBoolean("enabled", false)) { result.success(null); return }
                    val incoming = JSONObject(call.argument<String>("data") ?: "{}")
                    if (call.argument<Boolean>("background") == true) {
                        val previous = JSONObject(prefs.getString("miniData", "{}") ?: "{}")
                        val oldRows = previous.optJSONArray("rows") ?: JSONArray()
                        val newRows = incoming.optJSONArray("rows") ?: JSONArray()
                        if (incoming.optString("owner").isNotEmpty() && incoming.optString("owner") == previous.optString("owner")) {
                            for (i in 0 until oldRows.length()) {
                                val row = oldRows.getJSONObject(i)
                                if (!row.optBoolean("local")) newRows.put(row)
                            }
                        }
                        incoming.put("rows", newRows)
                    }
                    prefs.edit().putString("miniData", incoming.toString()).apply(); render(); result.success(null)
                }
                "permission" -> {
                    val current = activity
                    if (Build.VERSION.SDK_INT >= 33 && ContextCompat.checkSelfPermission(context, Manifest.permission.POST_NOTIFICATIONS) != PackageManager.PERMISSION_GRANTED && current != null && permissionResult == null) {
                        permissionResult = result
                        ActivityCompat.requestPermissions(current, arrayOf(Manifest.permission.POST_NOTIFICATIONS), PERMISSION)
                    } else result.success(allowed())
                }
                "systemSettings" -> {
                    val intent = if (Build.VERSION.SDK_INT >= 26) Intent(Settings.ACTION_APP_NOTIFICATION_SETTINGS).putExtra(Settings.EXTRA_APP_PACKAGE, context.packageName)
                        else Intent(Settings.ACTION_APPLICATION_DETAILS_SETTINGS, android.net.Uri.parse("package:${context.packageName}"))
                    context.startActivity(intent.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)); result.success(null)
                }
                "takeNavigation" -> { result.success(navigation); navigation = null }
                else -> result.notImplemented()
            }
        } catch (error: SecurityException) { result.error("NOTIFICATIONS", "Notification access unavailable", null) }
          catch (error: org.json.JSONException) { result.error("DATA", "Dashboard data unavailable", null) }
          catch (error: android.content.ActivityNotFoundException) { result.error("SETTINGS", "Android settings unavailable", null) }
    }

    private fun destination(target: String): PendingIntent {
        val intent = context.packageManager.getLaunchIntentForPackage(context.packageName)!!
            .addFlags(Intent.FLAG_ACTIVITY_CLEAR_TOP or Intent.FLAG_ACTIVITY_SINGLE_TOP).putExtra(TARGET, target)
        return PendingIntent.getActivity(context, if (target == "home") 4103 else 4104, intent, PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE)
    }
    private fun percent(row: JSONObject, key: String): String {
        val value = row.optDouble(key, Double.NaN)
        return if (value.isFinite() && value in 0.0..100.0) String.format(Locale.US, "%.2f%%", value) else "N/A"
    }
    private fun observation(row: JSONObject): String {
        val timestamp = row.optLong("observed", 0)
        if (timestamp <= 0) return "No reading"
        return "Observed " + SimpleDateFormat("dd MMM HH:mm", Locale.getDefault()).format(Date(timestamp))
    }
    private fun render() {
        val opts = options()
        if (!opts.optBoolean("enabled", false) || prefs.getBoolean("miniDismissed", false)) return
        if (Build.VERSION.SDK_INT >= 26) {
            val channel = NotificationChannel(CHANNEL, "Mini Dashboard", NotificationManager.IMPORTANCE_LOW)
            channel.description = "Silent, cached device readings. Updated by existing monitoring."
            channel.setSound(null, null); channel.enableVibration(false)
            context.getSystemService(NotificationManager::class.java).createNotificationChannel(channel)
        }
        if (!allowed()) return
        val data = JSONObject(prefs.getString("miniData", "{}") ?: "{}")
        val rows = data.optJSONArray("rows") ?: JSONArray()
        val favorites = opts.optJSONArray("favorites") ?: JSONArray()
        val favoriteIds = (0 until favorites.length()).map { favorites.optString(it) }
        val selected = (0 until rows.length()).map { rows.getJSONObject(it) }.filter { row ->
            if (row.optBoolean("local")) opts.optBoolean("local", true)
            else opts.optBoolean("remote", true) && (favoriteIds.isEmpty() || favoriteIds.contains(row.optString("id")))
        }
        val lines = selected.take(4).map { row ->
            val name = row.optString("name", "Device").replace('\n', ' ').take(40)
            val platform = if (row.optString("platform") == "windows") "Windows" else "Android"
            val metrics = mutableListOf<String>()
            if (opts.optBoolean("battery", true)) metrics.add("Battery ${percent(row, "battery")}" + if (row.optBoolean("charging")) " ⚡" else "")
            if (opts.optBoolean("storage", true)) metrics.add("Storage ${percent(row, "storage")} used")
            if (opts.optBoolean("updated", true)) metrics.add(observation(row))
            "$name · $platform\n" + metrics.joinToString(" · ")
        }
        val extra = if (selected.size > 4) "\n+${selected.size - 4} more devices" else ""
        val text = if (lines.isEmpty()) "No selected readings. Open Revice to configure devices." else lines.joinToString("\n\n") + extra
        val title = "Revice · ${selected.size} Devices"
        val summary = lines.firstOrNull()?.replace('\n', ':') ?: "Mini Dashboard"
        // Absolute observation times remain truthful without a timer to refresh age labels.
        val fingerprint = opts.toString() + title + text
        val active = manager.activeNotifications.any { it.id == ID }
        if (fingerprint == lastRendered && active) return
        val redacted = NotificationCompat.Builder(context, CHANNEL).setSmallIcon(R.drawable.ic_revice_notification)
            .setContentTitle("Revice Mini Dashboard").setContentText("Unlock to view your devices").build()
        val dismissed = PendingIntent.getBroadcast(context, 4105, Intent(context, DashboardDismissReceiver::class.java).setAction("app.revice.DISMISS_DASHBOARD"), PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE)
        val notification = NotificationCompat.Builder(context, CHANNEL)
            .setSmallIcon(R.drawable.ic_revice_notification).setColor(Color.rgb(185,243,90))
            .setContentTitle(title).setContentText(summary)
            .setStyle(NotificationCompat.BigTextStyle().bigText(text).setSummaryText("Cached readings · open for current status"))
            .setContentIntent(destination("home")).addAction(0, "View Devices", destination("devices"))
            .setDeleteIntent(dismissed).setOnlyAlertOnce(true).setSilent(true).setShowWhen(false)
            .setOngoing(opts.optBoolean("ongoing", false)).setAutoCancel(false)
            .setCategory(NotificationCompat.CATEGORY_STATUS)
            .setVisibility(if (opts.optBoolean("privacy", true)) NotificationCompat.VISIBILITY_PRIVATE else NotificationCompat.VISIBILITY_PUBLIC)
            .setPublicVersion(redacted).build()
        manager.notify(ID, notification); lastRendered = fingerprint
    }
}
