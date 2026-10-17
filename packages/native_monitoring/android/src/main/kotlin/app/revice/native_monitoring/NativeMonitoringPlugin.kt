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
