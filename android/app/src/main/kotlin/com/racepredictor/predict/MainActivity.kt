package com.racepredictor.predict

import android.Manifest
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.appwidget.AppWidgetManager
import android.content.ComponentName
import android.content.Context
import android.content.Intent
import android.content.SharedPreferences
import android.content.pm.PackageManager
import android.net.Uri
import android.os.Build
import android.provider.Settings
import androidx.core.app.ActivityCompat
import androidx.core.app.NotificationCompat
import androidx.core.content.ContextCompat
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

import androidx.work.WorkManager

class MainActivity : FlutterActivity() {

    private val WIDGET_CHANNEL = "com.racepredictor.predict/widget"
    private val PERMISSIONS_CHANNEL = "com.racepredictor.predict/permissions"
    private val PREFS_NAME = "RacePredictorWidgetData"
    private val NOTIFICATION_PERMISSION_REQUEST_CODE = 1001
    private val NOTIFICATION_CHANNEL_ID = "race_predictor_alerts"

    // Callback pour résultat de permission
    private var permissionResult: MethodChannel.Result? = null

    // ★ v9.98 : stocke le deep link reçu avant que Flutter soit prêt
    private var pendingCourseKey: String? = null
    private var pendingTab: String? = null

    override fun onCreate(savedInstanceState: android.os.Bundle?) {
        super.onCreate(savedInstanceState)
        HippiqueWorker.planifier(applicationContext)
        // ★ v9.98 : app lancée depuis zéro via tap notification → stocker pour envoi après Flutter init
        val courseKey = intent?.getStringExtra("deep_link_course_key")
        if (!courseKey.isNullOrEmpty()) {
            pendingCourseKey = courseKey
            pendingTab = intent?.getStringExtra("deep_link_tab") ?: "mes_paris"
        }
    }

    // ★ v9.84 : Deep link — lire l'intent quand l'app est déjà ouverte (foreground/background)
    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        setIntent(intent)
        _handleDeepLinkIntent(intent)
    }

    private fun _handleDeepLinkIntent(intent: Intent) {
        val courseKey = intent.getStringExtra("deep_link_course_key") ?: return
        val tab       = intent.getStringExtra("deep_link_tab") ?: "mes_paris"
        // Envoyer au Flutter via le canal deep link
        flutterEngine?.dartExecutor?.binaryMessenger?.let { messenger ->
            MethodChannel(messenger, "com.racepredictor.predict/deep_link")
                .invokeMethod("openCourse", mapOf("courseKey" to courseKey, "tab" to tab))
        }
    }

    // ★ v9.98 : appelé par Flutter quand il est prêt — envoie le deep link en attente
    private fun _flushPendingDeepLink() {
        val courseKey = pendingCourseKey ?: return
        val tab       = pendingTab ?: "mes_paris"
        pendingCourseKey = null
        pendingTab = null
        flutterEngine?.dartExecutor?.binaryMessenger?.let { messenger ->
            MethodChannel(messenger, "com.racepredictor.predict/deep_link")
                .invokeMethod("openCourse", mapOf("courseKey" to courseKey, "tab" to tab))
        }
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        // ── Canal Widget ────────────────────────────────────────────────────
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, WIDGET_CHANNEL)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "updateWidget" -> {
                        try {
                            val prefs: SharedPreferences =
                                applicationContext.getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)
                            val editor = prefs.edit()
                            @Suppress("UNCHECKED_CAST")
                            val data = call.arguments as? Map<String, String> ?: emptyMap()
                            data.forEach { (key, value) -> editor.putString(key, value) }
                            editor.apply()

                            val manager = AppWidgetManager.getInstance(applicationContext)
                            val ids = manager.getAppWidgetIds(
                                ComponentName(applicationContext, RacePredictorWidget::class.java)
                            )
                            if (ids.isNotEmpty()) {
                                RacePredictorWidget.onUpdate(applicationContext, manager, ids)
                            }
                            result.success("Widget updated: ${ids.size} instance(s)")
                        } catch (e: Exception) {
                            result.error("WIDGET_ERROR", e.message, null)
                        }
                    }
                    "getWidgetCount" -> {
                        val manager = AppWidgetManager.getInstance(applicationContext)
                        val ids = manager.getAppWidgetIds(
                            ComponentName(applicationContext, RacePredictorWidget::class.java)
                        )
                        result.success(ids.size)
                    }
                    else -> result.notImplemented()
                }
            }

        // ── Canal Permissions Notifications ────────────────────────────────
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, PERMISSIONS_CHANNEL)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "checkNotificationPermission" -> {
                        result.success(isNotificationPermissionGranted())
                    }
                    "requestNotificationPermission" -> {
                        if (isNotificationPermissionGranted()) {
                            // Permission déjà accordée
                            createNotificationChannel()
                            result.success(true)
                        } else if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
                            // Android 13+ : demander la permission
                            permissionResult = result
                            ActivityCompat.requestPermissions(
                                this,
                                arrayOf(Manifest.permission.POST_NOTIFICATIONS),
                                NOTIFICATION_PERMISSION_REQUEST_CODE
                            )
                            // result sera appelé dans onRequestPermissionsResult
                        } else {
                            // Android < 13 : notifications accordées par défaut
                            createNotificationChannel()
                            result.success(true)
                        }
                    }
                    "openNotificationSettings" -> {
                        try {
                            val intent = Intent().apply {
                                action = Settings.ACTION_APP_NOTIFICATION_SETTINGS
                                putExtra(Settings.EXTRA_APP_PACKAGE, packageName)
                            }
                            startActivity(intent)
                            result.success(true)
                        } catch (e: Exception) {
                            try {
                                val intent = Intent(Settings.ACTION_APPLICATION_DETAILS_SETTINGS).apply {
                                    data = Uri.fromParts("package", packageName, null)
                                }
                                startActivity(intent)
                                result.success(true)
                            } catch (e2: Exception) {
                                result.error("SETTINGS_ERROR", e2.message, null)
                            }
                        }
                    }
                    // ★ NOUVELLE MÉTHODE : envoyer une vraie notification Android
                    "showNotification" -> {
                        try {
                            val args = call.arguments as? Map<*, *> ?: emptyMap<String, String>()
                            val title    = args["title"]     as? String ?: "Pronostic Hippique"
                            val body     = args["body"]      as? String ?: ""
                            val notifId  = (args["id"] as? Int) ?: System.currentTimeMillis().toInt()
                            val courseKey = args["courseKey"] as? String ?: "" // ★ v9.84 deep link

                            // Intent pour rouvrir l'app au tap — avec courseKey pour deep link
                            val tapIntent = Intent(applicationContext, MainActivity::class.java).apply {
                                flags = Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_CLEAR_TASK
                                if (courseKey.isNotEmpty()) {
                                    putExtra("deep_link_course_key", courseKey)
                                    putExtra("deep_link_tab", "mes_paris")
                                }
                            }
                            val pendingFlags = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M)
                                PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
                            else PendingIntent.FLAG_UPDATE_CURRENT
                            val pendingIntent = PendingIntent.getActivity(
                                applicationContext, notifId, tapIntent, pendingFlags
                            )

                            createNotificationChannel()
                            val notif = NotificationCompat.Builder(applicationContext, NOTIFICATION_CHANNEL_ID)
                                .setSmallIcon(R.drawable.ic_notification)
                                .setContentTitle(title)
                                .setContentText(body)
                                .setStyle(NotificationCompat.BigTextStyle().bigText(body))
                                .setPriority(NotificationCompat.PRIORITY_HIGH)
                                .setAutoCancel(true)
                                .setContentIntent(pendingIntent)
                                .setVibrate(longArrayOf(0, 300, 200, 300))
                                .build()

                            val notifManager = getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
                            notifManager.notify(notifId, notif)
                            result.success(true)
                        } catch (e: Exception) {
                            result.error("NOTIF_ERROR", e.message, null)
                        }
                    }
                    else -> result.notImplemented()
                }
            }

        // Créer le canal de notification au démarrage
        createNotificationChannel()

        // ★ v9.98 : envoyer le deep link en attente (app lancée depuis zéro via notification)
        android.os.Handler(android.os.Looper.getMainLooper()).postDelayed({
            _flushPendingDeepLink()
        }, 800)
    }

    private fun isNotificationPermissionGranted(): Boolean {
        return if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
            ContextCompat.checkSelfPermission(
                this,
                Manifest.permission.POST_NOTIFICATIONS
            ) == PackageManager.PERMISSION_GRANTED
        } else {
            // Sur Android < 13, on vérifie si les notifications sont activées globalement
            val notifManager = getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
            notifManager.areNotificationsEnabled()
        }
    }

    private fun createNotificationChannel() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            val channel = NotificationChannel(
                NOTIFICATION_CHANNEL_ID,
                "Alertes Pronostic Hippique",
                NotificationManager.IMPORTANCE_HIGH
            ).apply {
                description = "Alertes de courses : départ imminent, résultats, paris"
                enableVibration(true)
                enableLights(true)
            }
            val notifManager = getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
            notifManager.createNotificationChannel(channel)
        }
    }

    override fun onRequestPermissionsResult(
        requestCode: Int,
        permissions: Array<out String>,
        grantResults: IntArray
    ) {
        super.onRequestPermissionsResult(requestCode, permissions, grantResults)
        if (requestCode == NOTIFICATION_PERMISSION_REQUEST_CODE) {
            val granted = grantResults.isNotEmpty() &&
                    grantResults[0] == PackageManager.PERMISSION_GRANTED
            if (granted) {
                createNotificationChannel()
            }
            permissionResult?.success(granted)
            permissionResult = null
        }
    }
}
