package com.racepredictor.predict

import android.app.PendingIntent
import android.appwidget.AppWidgetManager
import android.appwidget.AppWidgetProvider
import android.content.Context
import android.content.Intent
import android.content.SharedPreferences
import android.widget.RemoteViews
import org.json.JSONObject
import java.text.SimpleDateFormat
import java.util.Date
import java.util.Locale

/**
 * ════════════════════════════════════════════════════════════════════════
 * Widget Pronostic Hippique — Widget écran d'accueil Android
 *
 * Affiche :
 *  • Le meilleur pari du jour (confiance IA + nom du cheval + gain)
 *  • Hippodrome + heure de la course
 *  • Nombre de courses analysées
 *  • Confiance globale (score principal)
 *  • Bouton pour ouvrir l'app directement sur Best Bet
 *
 * Taille : 2×2 cellules minimum, redimensionnable jusqu'à 4×3
 * Mise à jour : toutes les 30 min via SharedPreferences (données Flutter)
 * ════════════════════════════════════════════════════════════════════════
 */
class RacePredictorWidget : AppWidgetProvider() {

    companion object {
        const val PREFS_NAME     = "RacePredictorWidgetData"
        const val KEY_COURSE     = "widget_course_name"
        const val KEY_HORSE      = "widget_horse_name"
        const val KEY_HORSE_NUM  = "widget_horse_num"
        const val KEY_CONFIANCE  = "widget_confiance"
        const val KEY_GAIN       = "widget_gain"
        const val KEY_HIPPODROME = "widget_hippodrome"
        const val KEY_HEURE      = "widget_heure"
        const val KEY_NB_COURSES = "widget_nb_courses"
        const val KEY_UPDATED_AT = "widget_updated_at"
        const val KEY_JSON_DATA  = "widget_json_data"
        // ★ v2.0 : nouveaux champs depuis widget_service.dart
        const val KEY_SCORE_IA   = "widget_score_ia"
        const val KEY_TYPE_PARI  = "widget_type_pari"
        const val KEY_TENDANCE   = "widget_tendance"
        const val KEY_ELO        = "widget_elo"

        /** Appelé par Flutter via MethodChannel pour mettre à jour les données */
        fun updateWidgetData(context: Context, data: Map<String, Any>) {
            val prefs = context.getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)
            val editor = prefs.edit()
            data.forEach { (k, v) -> editor.putString(k, v.toString()) }
            editor.apply()

            // Forcer la mise à jour de tous les widgets actifs
            val manager = AppWidgetManager.getInstance(context)
            val componentName = android.content.ComponentName(context, RacePredictorWidget::class.java)
            val ids = manager.getAppWidgetIds(componentName)
            if (ids.isNotEmpty()) {
                onUpdate(context, manager, ids)
            }
        }

        fun onUpdate(context: Context, manager: AppWidgetManager, ids: IntArray) {
            for (id in ids) {
                updateWidget(context, manager, id)
            }
        }

        private fun updateWidget(context: Context, manager: AppWidgetManager, widgetId: Int) {
            val prefs = context.getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)
            val views = RemoteViews(context.packageName, R.layout.race_predictor_widget)

            // ── Données depuis SharedPreferences (mises à jour par Flutter) ──
            val courseName  = prefs.getString(KEY_COURSE,     "Aucune course") ?: "Aucune course"
            val horseName   = prefs.getString(KEY_HORSE,      "Chargement…")   ?: "Chargement…"
            val horseNum    = prefs.getString(KEY_HORSE_NUM,  "?")             ?: "?"
            val confiance   = prefs.getString(KEY_CONFIANCE,  "--")            ?: "--"
            val gain        = prefs.getString(KEY_GAIN,       "--")            ?: "--"
            val hippodrome  = prefs.getString(KEY_HIPPODROME, "—")             ?: "—"
            val heure       = prefs.getString(KEY_HEURE,      "--:--")         ?: "--:--"
            val nbCourses   = prefs.getString(KEY_NB_COURSES, "0")             ?: "0"
            val updatedAt   = prefs.getString(KEY_UPDATED_AT, null)

            // ── Heure de dernière MAJ ──────────────────────────────────────
            val updateLabel = if (updatedAt != null) {
                try {
                    val ts = updatedAt.toLong()
                    val diff = (System.currentTimeMillis() - ts) / 60000
                    when {
                        diff < 1  -> "À l'instant"
                        diff < 60 -> "Il y a ${diff}min"
                        else      -> "Il y a ${diff/60}h"
                    }
                } catch (e: Exception) { "—" }
            } else "Appuyez pour actualiser"

            // ── Couleur confiance ──────────────────────────────────────────
            val confianceInt = confiance.replace("%","").toIntOrNull() ?: 0
            val confianceColor = when {
                confianceInt >= 78 -> 0xFF4CAF7D.toInt()  // Vert
                confianceInt >= 65 -> 0xFF8BC34A.toInt()  // Vert clair
                confianceInt >= 50 -> 0xFFFFB74D.toInt()  // Orange
                else               -> 0xFFEF5350.toInt()  // Rouge
            }

            // ── Remplir les vues ───────────────────────────────────────────
            // Lire les nouvelles données v2.0
            val scoreIA  = prefs.getString(KEY_SCORE_IA,  null)
            val tendance = prefs.getString(KEY_TENDANCE,  null)
            val typePari = prefs.getString(KEY_TYPE_PARI, null)

            // Label confiance enrichi : confiance + tendance si dispo
            val confianceLabel = when {
                tendance == "↑ En hausse"  -> "$confiance ↑"
                tendance == "↓ En baisse"  -> "$confiance ↓"
                else                        -> "$confiance"
            }

            views.setTextViewText(R.id.widget_last_update,   updateLabel)
            views.setTextViewText(R.id.widget_top_confiance, confianceLabel)
            views.setTextColor(R.id.widget_top_confiance,    confianceColor)
            views.setTextViewText(R.id.widget_course_name,   courseName)
            views.setTextViewText(R.id.widget_horse_name,    "N°$horseNum — $horseName")
            views.setTextViewText(R.id.widget_hippodrome,    hippodrome)
            views.setTextViewText(R.id.widget_heure,         heure)
            views.setTextViewText(R.id.widget_gain,          if (gain == "--") "—" else "+$gain€")
            views.setTextViewText(R.id.widget_nb_courses,    "$nbCourses course${if ((nbCourses.toIntOrNull() ?: 0) > 1) "s" else ""} analysée${if ((nbCourses.toIntOrNull() ?: 0) > 1) "s" else ""}")
            views.setTextColor(R.id.widget_gain,             confianceColor)

            // ── Intent : ouvrir l'app au clic sur le widget ────────────────
            val openIntent = context.packageManager.getLaunchIntentForPackage(context.packageName)
                ?.apply {
                    flags = Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_CLEAR_TOP
                    putExtra("open_screen", "best_bet")
                }
            val pendingOpen = PendingIntent.getActivity(
                context, 0, openIntent ?: Intent(context, MainActivity::class.java),
                PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
            )
            views.setOnClickPendingIntent(R.id.widget_root,     pendingOpen)
            views.setOnClickPendingIntent(R.id.widget_open_btn, pendingOpen)

            manager.updateAppWidget(widgetId, views)
        }
    }

    override fun onUpdate(context: Context, manager: AppWidgetManager, ids: IntArray) {
        Companion.onUpdate(context, manager, ids)
    }

    override fun onEnabled(context: Context) {
        super.onEnabled(context)
        // Premier widget ajouté — initialiser avec données vides
    }

    override fun onDisabled(context: Context) {
        super.onDisabled(context)
    }
}
