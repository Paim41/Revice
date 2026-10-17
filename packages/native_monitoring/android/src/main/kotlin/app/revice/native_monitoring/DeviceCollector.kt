package app.revice.native_monitoring

import android.content.Context
import android.content.Intent
import android.content.IntentFilter
import android.os.BatteryManager
import android.os.Build
import android.os.Environment
import android.os.StatFs

class DeviceCollector(private val context: Context) {
    fun read(): Map<String, Any?> {
        val battery = context.registerReceiver(null, IntentFilter(Intent.ACTION_BATTERY_CHANGED))
        fun extra(key: String): Int? = if (battery?.hasExtra(key) == true) battery.getIntExtra(key, -1) else null
        val present = battery?.getBooleanExtra(BatteryManager.EXTRA_PRESENT, true) == true
        val level = extra(BatteryManager.EXTRA_LEVEL)
        val scale = extra(BatteryManager.EXTRA_SCALE)
        val percent = if (present && level != null && scale != null && scale > 0 && level in 0..scale) level * 100.0 / scale else null
        val charging = when (extra(BatteryManager.EXTRA_STATUS)) {
            BatteryManager.BATTERY_STATUS_CHARGING, BatteryManager.BATTERY_STATUS_FULL -> true
            BatteryManager.BATTERY_STATUS_DISCHARGING, BatteryManager.BATTERY_STATUS_NOT_CHARGING -> false
            else -> null
        }
        val health = when (extra(BatteryManager.EXTRA_HEALTH)) {
            BatteryManager.BATTERY_HEALTH_GOOD -> "Good"
            BatteryManager.BATTERY_HEALTH_OVERHEAT -> "Overheated"
            BatteryManager.BATTERY_HEALTH_DEAD -> "Dead"
            BatteryManager.BATTERY_HEALTH_OVER_VOLTAGE -> "Over voltage"
            BatteryManager.BATTERY_HEALTH_UNSPECIFIED_FAILURE -> "Failure"
            BatteryManager.BATTERY_HEALTH_COLD -> "Cold"
            else -> null
        }
        val storage = try {
            val fs = StatFs(Environment.getDataDirectory().absolutePath)
            mapOf("totalBytes" to fs.totalBytes, "availableBytes" to fs.availableBytes)
        } catch (error: IllegalArgumentException) { null }
        return mapOf(
            "schemaVersion" to 1,
            "observedAt" to System.currentTimeMillis(),
            "device" to mapOf("model" to Build.MODEL, "manufacturer" to Build.MANUFACTURER, "androidVersion" to Build.VERSION.RELEASE),
            "battery" to if (!present) null else mapOf(
                "percentage" to percent, "charging" to charging,
                "temperatureC" to extra(BatteryManager.EXTRA_TEMPERATURE)?.takeIf { it in -500..1500 }?.div(10.0),
                "voltageMv" to extra(BatteryManager.EXTRA_VOLTAGE)?.takeIf { it > 0 },
                "health" to health,
                "cycleCount" to if (Build.VERSION.SDK_INT >= 34) extra(BatteryManager.EXTRA_CYCLE_COUNT)?.takeIf { it >= 0 } else null
            ),
            "storage" to storage
        )
    }
}

