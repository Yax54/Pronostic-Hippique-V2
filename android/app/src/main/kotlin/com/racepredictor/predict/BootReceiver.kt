package com.racepredictor.predict

import android.appwidget.AppWidgetManager
import android.content.BroadcastReceiver
import android.content.ComponentName
import android.content.Context
import android.content.Intent
import android.util.Log

/**
 * BootReceiver — Restaure le widget ET replanifie WorkManager après redémarrage
 *
 * Android supprime les widgets actifs et annule les Workers au redémarrage.
 * Ce receiver relance tout dès que le téléphone a fini de démarrer.
 */
class BootReceiver : BroadcastReceiver() {

    override fun onReceive(context: Context, intent: Intent) {
        when (intent.action) {
            Intent.ACTION_BOOT_COMPLETED,
            Intent.ACTION_MY_PACKAGE_REPLACED -> {
                // 1. Relancer la mise à jour de tous les widgets actifs
                val manager = AppWidgetManager.getInstance(context)
                val ids = manager.getAppWidgetIds(
                    ComponentName(context, RacePredictorWidget::class.java)
                )
                if (ids.isNotEmpty()) {
                    RacePredictorWidget.onUpdate(context, manager, ids)
                }

                // ★ 2. Replanifier le Worker de vérification des cotes
                HippiqueWorker.replanifierApresReboot(context)
                Log.d("BootReceiver", "✅ Widget et WorkManager replanifiés après reboot")
            }
        }
    }
}

