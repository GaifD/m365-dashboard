package com.gaifd.m365_dashboard

import android.content.Context
import android.content.Intent
import android.net.Uri
import android.os.Build
import android.os.PowerManager
import android.provider.Settings
import android.view.WindowManager
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "m365/system").setMethodCallHandler { call, result ->
            try {
                when (call.method) {
                    "startService" -> result.success(
                        RideService.start(
                            applicationContext,
                            call.argument<String>("title") ?: "",
                            call.argument<String>("text") ?: ""
                        )
                    )
                    "updateService" -> {
                        RideService.update(
                            applicationContext,
                            call.argument<String>("title") ?: "",
                            call.argument<String>("text") ?: ""
                        )
                        result.success(null)
                    }
                    "serviceStatus" -> result.success(
                        mapOf("running" to RideService.running, "error" to RideService.lastError)
                    )
                    "stopService" -> {
                        RideService.stop(applicationContext)
                        result.success(null)
                    }
                    "setShowWhenLocked" -> {
                        setLocked(call.argument<Boolean>("on") == true)
                        result.success(null)
                    }
                    "isIgnoringBatteryOptimizations" -> {
                        val pm = getSystemService(Context.POWER_SERVICE) as PowerManager
                        result.success(
                            if (Build.VERSION.SDK_INT >= 23) pm.isIgnoringBatteryOptimizations(packageName) else true
                        )
                    }
                    "requestIgnoreBatteryOptimizations" -> {
                        requestBattery()
                        result.success(null)
                    }
                    "openAppSettings" -> {
                        val i = Intent(Settings.ACTION_APPLICATION_DETAILS_SETTINGS, Uri.parse("package:$packageName"))
                        i.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                        startActivity(i)
                        result.success(null)
                    }
                    else -> result.notImplemented()
                }
            } catch (e: Exception) {
                result.error("ERR", e.message, null)
            }
        }
    }

    private fun requestBattery() {
        if (Build.VERSION.SDK_INT < 23) return
        try {
            val i = Intent(Settings.ACTION_REQUEST_IGNORE_BATTERY_OPTIMIZATIONS, Uri.parse("package:$packageName"))
            startActivity(i)
        } catch (e: Exception) {
            val i = Intent(Settings.ACTION_IGNORE_BATTERY_OPTIMIZATION_SETTINGS)
            startActivity(i)
        }
    }

    @Suppress("DEPRECATION")
    private fun setLocked(on: Boolean) {
        if (Build.VERSION.SDK_INT >= 27) {
            setShowWhenLocked(on)
        } else {
            if (on) window.addFlags(WindowManager.LayoutParams.FLAG_SHOW_WHEN_LOCKED)
            else window.clearFlags(WindowManager.LayoutParams.FLAG_SHOW_WHEN_LOCKED)
        }
    }
}
