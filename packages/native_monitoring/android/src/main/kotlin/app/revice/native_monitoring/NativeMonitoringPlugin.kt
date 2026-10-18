package app.revice.native_monitoring

import android.content.Context
import io.flutter.embedding.engine.plugins.FlutterPlugin
import io.flutter.plugin.common.MethodChannel
import io.flutter.embedding.engine.plugins.activity.ActivityAware
import io.flutter.embedding.engine.plugins.activity.ActivityPluginBinding
import io.flutter.plugin.common.PluginRegistry

class NativeMonitoringPlugin : FlutterPlugin, ActivityAware {
    private lateinit var channel: MethodChannel
    private lateinit var miniChannel: MethodChannel
    private lateinit var mini: MiniDashboard
    private var activityBinding: ActivityPluginBinding? = null
    private val permissionListener = PluginRegistry.RequestPermissionsResultListener { code, _, _ -> mini.permissionResult(code) }
    private val intentListener = PluginRegistry.NewIntentListener { intent -> mini.acceptIntent(intent); false }
    override fun onAttachedToEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        val context = binding.applicationContext
        val preferences = context.getSharedPreferences("revice", Context.MODE_PRIVATE)
        miniChannel = MethodChannel(binding.binaryMessenger, "app.revice/mini_dashboard")
        mini = MiniDashboard(context, miniChannel)
        miniChannel.setMethodCallHandler(mini::handle)
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
    override fun onDetachedFromEngine(binding: FlutterPlugin.FlutterPluginBinding) { channel.setMethodCallHandler(null); miniChannel.setMethodCallHandler(null); mini.detach(true) }
    override fun onAttachedToActivity(binding: ActivityPluginBinding) {
        activityBinding = binding; mini.activity = binding.activity
        binding.addRequestPermissionsResultListener(permissionListener); binding.addOnNewIntentListener(intentListener)
        mini.acceptIntent(binding.activity.intent)
    }
    private fun detachActivity(final: Boolean) {
        activityBinding?.removeRequestPermissionsResultListener(permissionListener)
        activityBinding?.removeOnNewIntentListener(intentListener)
        activityBinding = null; mini.detach(final)
    }
    override fun onDetachedFromActivityForConfigChanges() = detachActivity(false)
    override fun onReattachedToActivityForConfigChanges(binding: ActivityPluginBinding) = onAttachedToActivity(binding)
    override fun onDetachedFromActivity() = detachActivity(true)
}
