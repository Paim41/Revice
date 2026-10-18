package app.revice.native_monitoring

import android.content.Context
import io.flutter.embedding.engine.plugins.FlutterPlugin
import io.flutter.plugin.common.MethodChannel

class NativeMonitoringPlugin : FlutterPlugin {
    private lateinit var channel: MethodChannel
    override fun onAttachedToEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        val context = binding.applicationContext
        val preferences = context.getSharedPreferences("revice", Context.MODE_PRIVATE)
        channel = MethodChannel(binding.binaryMessenger, "app.revice/monitoring")
        channel.setMethodCallHandler { call, result ->
            when (call.method) {
                "appMetadata" -> {
                    try {
                        val info = context.packageManager.getPackageInfo(context.packageName, 0)
                        val build = if (android.os.Build.VERSION.SDK_INT >= 28) info.longVersionCode.toString() else info.versionCode.toString()
                        result.success(mapOf("version" to (info.versionName ?: "Unknown"), "build" to build))
                    } catch (error: Exception) { result.error("METADATA", "Application information unavailable", null) }
                }
                "openDeveloperProfile" -> {
                    try {
                        val intent = android.content.Intent(android.content.Intent.ACTION_VIEW, android.net.Uri.parse("https://github.com/Paim41"))
                        intent.addFlags(android.content.Intent.FLAG_ACTIVITY_NEW_TASK)
                        context.startActivity(intent)
                        result.success(true)
                    } catch (error: android.content.ActivityNotFoundException) { result.success(false) }
                    catch (error: SecurityException) { result.success(false) }
                }
                "readSnapshot" -> {
                    try { result.success(DeviceCollector(context).read()) }
                    catch (error: SecurityException) { result.error("ACCESS", "Android denied metric access", null) }
                    catch (error: IllegalArgumentException) { result.error("READ", "Metric source unavailable", null) }
                }
                "preferences" -> result.success(mapOf(
                    "onboarded" to preferences.getBoolean("onboarded", false),
                    "reduceMotion" to preferences.getBoolean("reduceMotion", false)
                ))
                "savePreferences" -> {
                    val saved = preferences.edit()
                        .putBoolean("onboarded", call.argument<Boolean>("onboarded") ?: false)
                        .putBoolean("reduceMotion", call.argument<Boolean>("reduceMotion") ?: false).commit()
                    if (saved) result.success(null) else result.error("SAVE", "Unable to persist preferences", null)
                }
                else -> result.notImplemented()
            }
        }
    }
    override fun onDetachedFromEngine(binding: FlutterPlugin.FlutterPluginBinding) { channel.setMethodCallHandler(null) }
}
