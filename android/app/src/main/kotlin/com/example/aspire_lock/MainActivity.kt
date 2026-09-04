package com.example.aspire_lock

import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.util.TimeZone

/**
 * Small native bridge for things the Flutter engine cannot get on its
 * own — currently just the device's real IANA timezone id.
 */
class MainActivity : FlutterActivity() {

    private val channelName = "com.aspirelock/native"

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, channelName).setMethodCallHandler { call, result ->
            when (call.method) {
                "getDeviceTimeZone" -> {
                    // Real fix for alarms firing at the wrong time: the
                    // `timezone` Dart package defaults tz.local to UTC
                    // unless the app explicitly tells it the device's
                    // real IANA timezone id (e.g. "Asia/Karachi"). Without
                    // this, every scheduled alarm was off by the user's
                    // UTC offset (5 hours for PKT) — usually landing in
                    // the past, so it got silently skipped as "already
                    // due", and the alarm never fired at all.
                    result.success(TimeZone.getDefault().id)
                }
                else -> result.notImplemented()
            }
        }
    }
}
