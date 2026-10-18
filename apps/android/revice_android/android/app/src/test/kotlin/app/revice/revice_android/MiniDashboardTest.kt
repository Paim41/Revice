package app.revice.revice_android

import android.Manifest
import android.app.Application
import android.app.Notification
import android.app.NotificationManager
import android.content.Context
import android.content.Intent
import app.revice.native_monitoring.MiniDashboard
import app.revice.native_monitoring.DashboardDismissReceiver
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import org.json.JSONObject
import org.junit.Assert.*
import org.junit.Before
import org.junit.Test
import org.junit.runner.RunWith
import org.mockito.Mockito.mock
import org.robolectric.RobolectricTestRunner
import org.robolectric.RuntimeEnvironment
import org.robolectric.Shadows.shadowOf
import org.robolectric.annotation.Config

@RunWith(RobolectricTestRunner::class)
@Config(sdk = [33])
class MiniDashboardTest {
    private lateinit var app: Application
    private lateinit var dashboard: MiniDashboard
    private lateinit var manager: NotificationManager
    private fun make() = MiniDashboard(app, MethodChannel(mock(BinaryMessenger::class.java), "test"))
    @Before fun setup() {
        app = RuntimeEnvironment.getApplication()
        app.getSharedPreferences("revice", Context.MODE_PRIVATE).edit().clear().commit()
        shadowOf(app).grantPermissions(Manifest.permission.POST_NOTIFICATIONS)
        manager = app.getSystemService(NotificationManager::class.java)
        manager.cancelAll(); dashboard = make()
    }
    private fun call(method: String, args: Map<String, Any?> = emptyMap(), target: MiniDashboard = dashboard): Any? {
        var value: Any? = null
        target.handle(MethodCall(method, args), object: MethodChannel.Result {
            override fun success(result: Any?) { value = result }
            override fun error(code: String, message: String?, details: Any?) { fail("$code: $message") }
            override fun notImplemented() { fail("Method not implemented") }
        })
        return value
    }
    private fun enable(extra: String = "") = call("save", mapOf("options" to """{"enabled":true$extra}""", "showAgain" to true))
    private fun data(battery: Int = 78) = """{"owner":"owner","rows":[{"id":"local","local":true,"name":"POCO F7","platform":"android","battery":$battery,"storage":64,"charging":true,"observed":1600000000000},{"id":"pc","local":false,"name":"Paim Windows","platform":"windows","storage":67,"observed":1600000000000}]}"""
    private fun update(value: String = data(), background: Boolean = false, target: MiniDashboard = dashboard) = call("update", mapOf("data" to value, "background" to background), target)
    private fun notification() = manager.activeNotifications.single().notification

    @Test fun defaultOffPermissionAndStableSilentNotification() {
        update();assertTrue(manager.activeNotifications.isEmpty())
        assertFalse(JSONObject((call("load") as Map<*,*>)["options"] as String).optBoolean("enabled"))
        enable();update()
        val n = notification()
        assertEquals("Revice · 2 Devices", n.extras.getCharSequence(Notification.EXTRA_TITLE).toString())
        val text=n.extras.getCharSequence(Notification.EXTRA_BIG_TEXT).toString()
        assertTrue(text.contains("Battery 78.00%"));assertTrue(text.contains("Storage 64.00%"));assertTrue(text.contains("Paim Windows"));assertTrue(text.contains("Battery N/A"))
        assertTrue(text.contains("Observed"));assertFalse(text.contains("live", ignoreCase=true))
        assertEquals(NotificationManager.IMPORTANCE_LOW, manager.getNotificationChannel(MiniDashboard.CHANNEL).importance)
        assertNull(manager.getNotificationChannel(MiniDashboard.CHANNEL).sound)
        update(data(79));assertEquals(1,manager.activeNotifications.size)
        assertEquals(MiniDashboard.ID,manager.activeNotifications.single().id)
        assertTrue(notification().extras.getCharSequence(Notification.EXTRA_BIG_TEXT).toString().contains("79.00%"))
        call("save", mapOf("options" to """{"enabled":false}"""));assertTrue(manager.activeNotifications.isEmpty())
    }
    @Test fun lockScreenIntentsFavoritesAndOverflow() {
        enable();update()
        val n=notification()
        assertEquals(Notification.VISIBILITY_PRIVATE,n.visibility)
        assertEquals("Unlock to view your devices",n.publicVersion.extras.getCharSequence(Notification.EXTRA_TEXT).toString())
        assertEquals("home",shadowOf(n.contentIntent).savedIntent.getStringExtra(MiniDashboard.TARGET))
        assertEquals("devices",shadowOf(n.actions.single().actionIntent).savedIntent.getStringExtra(MiniDashboard.TARGET))
        assertTrue(n.contentIntent.isImmutable)
        enable(",\"local\":false,\"favorites\":[\"pc\"],\"battery\":false,\"privacy\":false")
        val text=notification().extras.getCharSequence(Notification.EXTRA_BIG_TEXT).toString()
        assertFalse(text.contains("POCO"));assertFalse(text.contains("Battery"));assertTrue(text.contains("Windows"))
        assertEquals(Notification.VISIBILITY_PUBLIC,notification().visibility)
        enable()
        val many=JSONObject(data());val rows=many.getJSONArray("rows")
        for(i in 1..5)rows.put(JSONObject("""{"id":"$i","name":"Phone $i","platform":"android"}"""))
        update(many.toString());assertTrue(notification().extras.getCharSequence(Notification.EXTRA_BIG_TEXT).toString().contains("+3 more devices"))
    }
    @Test fun dismissalRestartAndBackgroundOwnerIsolation() {
        enable();update()
        DashboardDismissReceiver().onReceive(app,Intent("app.revice.DISMISS_DASHBOARD"))
        manager.cancel(MiniDashboard.ID);update();assertTrue(manager.activeNotifications.isEmpty())
        val restarted=make();update(target=restarted);assertTrue(manager.activeNotifications.isEmpty())
        call("save",mapOf("options" to """{"enabled":true}""","showAgain" to true),restarted)
        update("""{"owner":"owner","rows":[{"local":true,"name":"New local","platform":"android"}]}""",true,restarted)
        assertTrue(notification().extras.getCharSequence(Notification.EXTRA_BIG_TEXT).toString().contains("Paim Windows"))
        update("""{"owner":"","rows":[]}""",true,restarted)
        assertFalse(notification().extras.getCharSequence(Notification.EXTRA_BIG_TEXT).toString().contains("Paim Windows"))
    }
    @Test fun blockedPermissionAndNavigationWhitelist() {
        shadowOf(app).denyPermissions(Manifest.permission.POST_NOTIFICATIONS)
        enable();update();assertTrue(manager.activeNotifications.isEmpty())
        assertEquals(false,(call("load") as Map<*,*>)["allowed"])
        dashboard.acceptIntent(Intent().putExtra(MiniDashboard.TARGET,"private-token"));assertNull(call("takeNavigation"))
        dashboard.acceptIntent(Intent().putExtra(MiniDashboard.TARGET,"devices"));assertEquals("devices",call("takeNavigation"));assertNull(call("takeNavigation"))
    }
}
