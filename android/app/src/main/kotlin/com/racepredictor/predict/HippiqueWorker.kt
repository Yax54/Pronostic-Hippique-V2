package com.racepredictor.predict

import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.content.Context
import android.content.Intent
import android.content.SharedPreferences
import android.os.Build
import android.util.Log
import androidx.core.app.NotificationCompat
import androidx.work.*
import org.json.JSONArray
import org.json.JSONObject
import java.net.HttpURLConnection
import java.net.URL
import java.text.SimpleDateFormat
import java.util.Calendar
import java.util.*
import java.util.concurrent.TimeUnit

/**
 * ═══════════════════════════════════════════════════════════════════════
 * HippiqueWorker — Tâche arrière-plan toutes les heures
 * ═══════════════════════════════════════════════════════════════════════
 *
 * Ce Worker Android tourne en arrière-plan toutes les heures SANS
 * que l'utilisateur n'ouvre l'app. Il fait deux choses :
 *
 * 1. COTES DISPONIBLES :
 *    Pour chaque course suivie (TrackedCourse sauvegardée par Flutter),
 *    il vérifie si les cotes PMU viennent d'apparaître (publiées ~1h avant).
 *    Si oui → notification "Les cotes sont disponibles pour X !"
 *
 * 2. ALERTES FAVORIS :
 *    Pour chaque course marquée "favorite" (sans pari placé),
 *    il vérifie si les cotes ont changé significativement ou si le
 *    favori IA est disponible. Si oui → notification "Votre favori X
 *    a une cote intéressante, pensez à parier !"
 *
 * Consommation batterie : minimale — WorkManager optimise l'exécution
 * selon l'état de la batterie et de la connexion.
 * ═══════════════════════════════════════════════════════════════════════
 */
class HippiqueWorker(
    private val context: Context,
    params: WorkerParameters
) : CoroutineWorker(context, params) {

    companion object {
        private const val TAG = "HippiqueWorker"
        private const val WORK_NAME = "hippique_background_check"
        private const val CHANNEL_ID = "race_predictor_alerts"
        private const val CHANNEL_COTES  = "hippique_cotes"
        private const val CHANNEL_FAVORI = "hippique_favori"
        private const val CHANNEL_DEPART  = "hippique_depart"  // ★ v9.5 : alerte 10 min avant
        private const val CHANNEL_RAPPEL  = "hippique_rappel"  // ★ v9.6 : rappel analyse journée
        private const val CHANNEL_HEBDO   = "hippique_hebdo"   // ★ v9.86 : rapport hebdomadaire
        private const val CHANNEL_ELO     = "hippique_elo"     // ★ v9.86 : alerte ELO cheval

        // Clé pour la date de la dernière analyse journée
        private const val KEY_DERNIERE_ANALYSE  = "flutter.ia_derniere_analyse_v1"
        // ★ v9.6 : Notifications en attente écrites par Flutter quand app fermée
        private const val KEY_PENDING_NOTIFS    = "flutter.hippique_pending_notifs"

        // SharedPreferences partagées avec Flutter (même clé que alert_service.dart)
        private const val PREFS_FLUTTER = "FlutterSharedPreferences"
        private const val KEY_TRACKED   = "flutter.tracked_courses_v1"  // ★ Fix : v1 correspond à alert_service._trackedKey
        private const val KEY_FAVORITES = "flutter.hippique_favorites_v1"
        private const val KEY_ALERT_CONFIG = "flutter.alert_config_v2"   // ★ v9.93 : scope des alertes
        // Clé pour éviter les doublons de notifications
        private const val KEY_NOTIF_SENT = "hippique_notif_sent_v1"

        private const val PMU_BASE = "https://online.turfinfo.api.pmu.fr/rest/client/1"

        /**
         * Lance le Worker périodique — à appeler depuis MainActivity au démarrage.
         * Si déjà planifié → rien ne se passe (KEEP).
         */
        fun planifier(context: Context) {
            val constraints = Constraints.Builder()
                .setRequiredNetworkType(NetworkType.CONNECTED)
                .build()

            val request = PeriodicWorkRequestBuilder<HippiqueWorker>(
                15, TimeUnit.MINUTES,          // ★ v9.5 : toutes les 15 min (minimum Android)
                5,  TimeUnit.MINUTES           // flexibilité ±5 min
            )
                .setConstraints(constraints)
                .setBackoffCriteria(
                    BackoffPolicy.LINEAR,
                    15, TimeUnit.MINUTES
                )
                .build()

            WorkManager.getInstance(context).enqueueUniquePeriodicWork(
                WORK_NAME,
                ExistingPeriodicWorkPolicy.KEEP, // ne pas reprogrammer si déjà actif
                request
            )
            Log.d(TAG, "WorkManager planifié — vérification toutes les 15 min (flex ±5 min)")
        }

        /**
         * Replanifie après redémarrage (appelé depuis BootReceiver).
         */
        fun replanifierApresReboot(context: Context) {
            planifier(context)
            Log.d(TAG, "WorkManager replanifié après reboot")
        }
    }

    override suspend fun doWork(): Result {
        Log.d(TAG, "⏰ HippiqueWorker démarré — ${Date()}")
        try {
            createNotificationChannels()
            val today = todayStr()

            // 1. Vérifier les cotes pour les courses suivies
            verifierCotesCoursesSuivies(today)

            // 2. Alerter sur les favoris non pariés
            alerterFavorisNonParIes(today)
            // 3. ★ v9.5 : Alerter 10 min avant le départ des favoris
            alerterDepartProchain(today)
            // 4. ★ v9.85 : Alerter 30 min avant le départ des favoris non pariés
            alerter30MinAvantDepart(today)
            // 5. ★ v9.6 : Rappel si analyse journée non lancée depuis 2 jours
            rappelerAnalyseJournee()
            // 6. ★ v9.85 : Résumé du soir enrichi (21h)
            envoyerResumeSoir()
            // 7. ★ v9.85 : Alerte si cote d'un favori IA chute brutalement
            alerterChuteCote(today)
            // 8. ★ v9.6 Fix arrière-plan : envoyer les notifications Flutter en attente
            envoyerNotificationsPendingFlutter()
            // 9. ★ v9.86 : Rapport hebdomadaire (lundi matin 8h-10h)
            envoyerRapportHebdomadaire()
            // 10. ★ v9.86 : Alerte progression ELO cheval
            alerterProgressionEloCheval(today)
            // 11. ★ v9.86 : Mettre à jour widget avec badge IA
            mettreAJourWidgetBadgeIA()

        } catch (e: Exception) {
            Log.e(TAG, "Erreur HippiqueWorker: ${e.message}")
            return Result.retry()
        }
        return Result.success()
    }

    // ─── 1. COTES DISPONIBLES ─────────────────────────────────────────────────

    private fun verifierCotesCoursesSuivies(today: String) {
        val prefs = context.getSharedPreferences(PREFS_FLUTTER, Context.MODE_PRIVATE)
        val trackedJson = prefs.getString(KEY_TRACKED, null) ?: return
        val notifSentPrefs = context.getSharedPreferences(KEY_NOTIF_SENT, Context.MODE_PRIVATE)

        try {
            val courses = JSONArray(trackedJson)
            for (i in 0 until courses.length()) {
                val course = courses.getJSONObject(i)
                val isGagne = if (course.has("isGagne")) course.get("isGagne") else null
                // Ne traiter que les courses sans résultat (pas encore terminées)
                if (isGagne != null) continue

                val heureDepart = course.optString("heureDepart", "") ?: continue
                if (!heureDepart.startsWith(today.substring(0, 4))) continue

                val numR = course.optInt("numReunion", 0)
                val numC = course.optInt("numCourse", 0)
                val nomCourse = course.optString("nomCourse", "Course")
                val hippodrome = course.optString("hippodrome", "")

                val notifKey = "cotes_${today}_R${numR}C${numC}"
                if (notifSentPrefs.getBoolean(notifKey, false)) continue

                // Vérifier si les cotes sont disponibles via API PMU
                val cotesDisponibles = verifierCotesPmu(today, numR, numC)
                if (cotesDisponibles) {
                    envoyerNotification(
                        id = notifKey.hashCode(),
                        title = "🏇 Cotes disponibles !",
                        body = "$nomCourse ($hippodrome) — Les cotes PMU viennent d'être publiées. Consultez l'app pour analyser la course.",
                        channel = CHANNEL_COTES
                    )
                    notifSentPrefs.edit().putBoolean(notifKey, true).apply()
                    Log.d(TAG, "✅ Notification cotes envoyée : R${numR}C${numC}")
                }
            }
        } catch (e: Exception) {
            Log.e(TAG, "Erreur verifierCotesCoursesSuivies: ${e.message}")
        }
    }

    private fun verifierCotesPmu(dateStr: String, numR: Int, numC: Int): Boolean {
        // Format date PMU : ddMMyyyy
        return try {
            val url = URL("$PMU_BASE/programme/$dateStr/R$numR/C$numC/participants?specialisation=INTERNET")
            val conn = url.openConnection() as HttpURLConnection
            conn.connectTimeout = 8000
            conn.readTimeout = 8000
            conn.setRequestProperty("Accept", "application/json")
            conn.setRequestProperty("User-Agent", "PronosticHippique/1.0")

            val code = conn.responseCode
            if (code != 200) return false

            val body = conn.inputStream.bufferedReader().readText()
            conn.disconnect()

            val json = JSONObject(body)
            val participants = json.optJSONArray("participants") ?: return false

            // Les cotes sont disponibles si au moins 1 participant a une cote > 1
            for (i in 0 until participants.length()) {
                val p = participants.getJSONObject(i)
                val rapport = p.optJSONObject("rapportDirect")
                val cote = rapport?.optDouble("rapport", 0.0) ?: 0.0
                if (cote > 1.0) return true
            }
            false
        } catch (e: Exception) {
            Log.d(TAG, "Cotes non disponibles R${numR}C${numC}: ${e.message}")
            false
        }
    }

    // ─── 2. ALERTES FAVORIS NON PARIÉS ───────────────────────────────────────

    private fun alerterFavorisNonParIes(today: String) {
        val prefs = context.getSharedPreferences(PREFS_FLUTTER, Context.MODE_PRIVATE)
        val favJson = prefs.getString(KEY_FAVORITES, null) ?: return
        val notifSentPrefs = context.getSharedPreferences(KEY_NOTIF_SENT, Context.MODE_PRIVATE)

        try {
            val favorites = JSONArray(favJson)
            for (i in 0 until favorites.length()) {
                val fav = favorites.getJSONObject(i)
                val numR = fav.optInt("numR", 0)
                val numC = fav.optInt("numC", 0)
                val nomCourse = fav.optString("nomCourse", "Course")
                val hippodrome = fav.optString("hippodrome", "")
                val scoreIA = fav.optDouble("scoreIA", 0.0)
                val dejaParI = fav.optBoolean("dejaParI", false)

                if (dejaParI) continue // Déjà pari placé → pas d'alerte
                // ★ v9.93 : respecter le scope
                if (!coursePasseFiltre(numR, numC, today)) continue

                val notifKey = "favori_${today}_R${numR}C${numC}"
                if (notifSentPrefs.getBoolean(notifKey, false)) continue

                // Vérifier les cotes et scorer ce favori
                val info = recupererInfoCourse(today, numR, numC) ?: continue
                val cote = info.first
                val nbPartants = info.second

                // Alerter si cote intéressante (entre 3 et 20) et score IA élevé
                if (cote in 3.0..20.0 && scoreIA >= 65.0) {
                    val msg = buildString {
                        append("$nomCourse ($hippodrome)")
                        append(" — Cote : ×${String.format("%.1f", cote)}")
                        append(", Score IA : ${scoreIA.toInt()}/100")
                        append(". Pensez à parier !")
                    }
                    envoyerNotification(
                        id = notifKey.hashCode(),
                        title = "⭐ Favori IA à surveiller !",
                        body = msg,
                        channel = CHANNEL_FAVORI
                    )
                    notifSentPrefs.edit().putBoolean(notifKey, true).apply()
                    Log.d(TAG, "✅ Notification favori envoyée : R${numR}C${numC} cote=$cote score=$scoreIA")
                }
            }
        } catch (e: Exception) {
            Log.e(TAG, "Erreur alerterFavorisNonParIes: ${e.message}")
        }
    }

    private fun recupererInfoCourse(dateStr: String, numR: Int, numC: Int): Pair<Double, Int>? {
        return try {
            val url = URL("$PMU_BASE/programme/$dateStr/R$numR/C$numC/participants?specialisation=INTERNET")
            val conn = url.openConnection() as HttpURLConnection
            conn.connectTimeout = 8000
            conn.readTimeout = 8000
            conn.setRequestProperty("Accept", "application/json")
            conn.setRequestProperty("User-Agent", "PronosticHippique/1.0")

            if (conn.responseCode != 200) return null

            val body = conn.inputStream.bufferedReader().readText()
            conn.disconnect()

            val json = JSONObject(body)
            val participants = json.optJSONArray("participants") ?: return null

            var totalCote = 0.0
            var nbAvecCote = 0
            val nbPartants = participants.length()

            for (i in 0 until nbPartants) {
                val p = participants.getJSONObject(i)
                val rapport = p.optJSONObject("rapportDirect")
                val cote = rapport?.optDouble("rapport", 0.0) ?: 0.0
                if (cote > 1.0) {
                    totalCote += cote
                    nbAvecCote++
                }
            }

            if (nbAvecCote == 0) return null
            // Retourner la cote moyenne (indicateur de la difficulté de la course)
            Pair(totalCote / nbAvecCote, nbPartants)
        } catch (e: Exception) {
            null
        }
    }

    // ─── ★ v9.5 : ALERTE 10 MIN AVANT DÉPART ───────────────────────────────────

    private fun alerterDepartProchain(today: String) {
        val prefs = context.getSharedPreferences(PREFS_FLUTTER, Context.MODE_PRIVATE)
        val favJson = prefs.getString(KEY_FAVORITES, null) ?: return
        val notifSentPrefs = context.getSharedPreferences(KEY_NOTIF_SENT, Context.MODE_PRIVATE)

        try {
            val favorites = JSONArray(favJson)
            val maintenant = Calendar.getInstance()
            val hNow = maintenant.get(Calendar.HOUR_OF_DAY)
            val mNow = maintenant.get(Calendar.MINUTE)
            val minutesNow = hNow * 60 + mNow

            for (i in 0 until favorites.length()) {
                val fav = favorites.getJSONObject(i)
                val dejaParI = fav.optBoolean("dejaParI", false)
                if (dejaParI) continue

                val heureStr = fav.optString("heure", "") // format "HH:mm"
                if (heureStr.length < 5) continue

                val parts = heureStr.split(":")
                if (parts.size < 2) continue
                val hDepart  = parts[0].toIntOrNull() ?: continue
                val mDepart  = parts[1].toIntOrNull() ?: continue
                val minutesDepart = hDepart * 60 + mDepart

                val diff = minutesDepart - minutesNow
                // Alerter si entre 8 et 12 minutes avant le départ
                if (diff < 8 || diff > 12) continue

                val numR = fav.optInt("numR", 0)
                val numC = fav.optInt("numC", 0)
                val nomCourse  = fav.optString("nomCourse", "Course")
                val hippodrome = fav.optString("hippodrome", "")

                // ★ v9.93 : respecter le scope
                if (!coursePasseFiltre(numR, numC, today)) continue
                val notifKey = "depart_${today}_R${numR}C${numC}"
                if (notifSentPrefs.getBoolean(notifKey, false)) continue

                envoyerNotification(
                    id = notifKey.hashCode(),
                    title = "⏰ Départ dans $diff minutes !",
                    body = "$nomCourse ($hippodrome) — Votre course favorite commence bientôt. Placez votre pari !",
                    channel = CHANNEL_DEPART
                )
                notifSentPrefs.edit().putBoolean(notifKey, true).apply()
                Log.d(TAG, "✅ Notification départ envoyée : R${numR}C${numC} dans ${diff}min")
            }
        } catch (e: Exception) {
            Log.e(TAG, "Erreur alerterDepartProchain: ${e.message}")
        }
    }

    // ─── ★ v9.6 Fix arrière-plan : NOTIFICATIONS FLUTTER EN ATTENTE ──────────────

    private fun envoyerNotificationsPendingFlutter() {
        try {
            val prefs = context.getSharedPreferences(PREFS_FLUTTER, Context.MODE_PRIVATE)
            // Flutter écrit en setString + jsonEncode → lire getString + JSONArray
            val json = prefs.getString(KEY_PENDING_NOTIFS.removePrefix("flutter."), null)
                ?: return

            val jsonArray = try { JSONArray(json) } catch (e: Exception) { return }
            if (jsonArray.length() == 0) return

            val now = System.currentTimeMillis()
            val processed = mutableListOf<String>()
            val pending = (0 until jsonArray.length()).map { jsonArray.getString(it) }

            for (entry in pending) {
                try {
                    val parts = entry.split("|")
                    if (parts.size < 4) continue
                    val notifId   = parts[0].toIntOrNull() ?: continue
                    val title     = parts[1]
                    val body      = parts[2]
                    val timestamp = parts[3].toLongOrNull() ?: 0L

                    // Ignorer les notifications de plus de 2 heures
                    if (now - timestamp > 2 * 60 * 60 * 1000L) continue

                    // Choisir le bon canal selon le contenu du titre
                    val channel = when {
                        title.contains("départ", ignoreCase = true) ||
                        title.contains("Départ", ignoreCase = true) -> CHANNEL_DEPART
                        title.contains("favori", ignoreCase = true) -> CHANNEL_FAVORI
                        title.contains("analyse", ignoreCase = true) -> CHANNEL_RAPPEL
                        else -> CHANNEL_COTES
                    }

                    envoyerNotification(notifId, title, body, channel)
                    processed.add(entry)
                    Log.d(TAG, "✅ Notif Flutter envoyée: $title")
                } catch (e: Exception) {
                    Log.e(TAG, "Erreur traitement notif: \${e.message}")
                }
            }

            // Vider les notifications traitées
            if (processed.isNotEmpty()) {
                val editor = prefs.edit()
                editor.remove(KEY_PENDING_NOTIFS.removePrefix("flutter."))
                editor.apply()
                Log.d(TAG, "✅ \${processed.size} notif(s) Flutter envoyée(s) depuis arrière-plan")
            }
        } catch (e: Exception) {
            Log.e(TAG, "Erreur envoyerNotificationsPendingFlutter: \${e.message}")
        }
    }

    // ─── ★ v9.6 : RAPPEL ANALYSE JOURNÉE ────────────────────────────────────────

    // ─── ★ v9.85 : ALERTE 30 MIN AVANT DÉPART ───────────────────────────────
    private fun alerter30MinAvantDepart(today: String) {
        val prefs = context.getSharedPreferences(PREFS_FLUTTER, Context.MODE_PRIVATE)
        val notifSentPrefs = context.getSharedPreferences(KEY_NOTIF_SENT, Context.MODE_PRIVATE)
        val raw = prefs.getString(KEY_FAVORITES, "[]") ?: "[]"
        try {
            val arr = org.json.JSONArray(raw)
            val maintenant = java.util.Calendar.getInstance()
            for (i in 0 until arr.length()) {
                val obj = arr.getJSONObject(i)
                val heureStr = obj.optString("heure", "")
                val nomCourse = obj.optString("nomCourse", "")
                val hippodrome = obj.optString("hippodrome", "")
                if (heureStr.isEmpty() || nomCourse.isEmpty()) continue
                // ★ v9.93 : respecter le scope
                val numR = obj.optInt("numR", 0)
                val numC = obj.optInt("numC", 0)
                if (numR > 0 && numC > 0 && !coursePasseFiltre(numR, numC, today)) continue
                // Parser heure (format HH:mm)
                val parts = heureStr.split(":")
                if (parts.size < 2) continue
                val hDepart = parts[0].toIntOrNull() ?: continue
                val mDepart = parts[1].toIntOrNull() ?: continue
                val depart = java.util.Calendar.getInstance().apply {
                    set(java.util.Calendar.HOUR_OF_DAY, hDepart)
                    set(java.util.Calendar.MINUTE, mDepart)
                    set(java.util.Calendar.SECOND, 0)
                }
                val diffMin = ((depart.timeInMillis - maintenant.timeInMillis) / 60000).toInt()
                // Alerter si entre 28 et 32 minutes avant
                if (diffMin in 28..32) {
                    val notifKey = "rappel30_${today}_${nomCourse.take(10)}"
                    if (!notifSentPrefs.getBoolean(notifKey, false)) {
                        envoyerNotification(
                            id = notifKey.hashCode(),
                            title = "⏰ Départ dans 30 min — $nomCourse",
                            body = "Votre favori à $hippodrome part dans environ 30 minutes. Pensez à parier !",
                            channel = CHANNEL_RAPPEL
                        )
                        notifSentPrefs.edit().putBoolean(notifKey, true).apply()
                    }
                }
            }
        } catch (e: Exception) {
            Log.e(TAG, "Erreur alerter30Min: ${e.message}")
        }
    }

    // ─── ★ v9.85 : RÉSUMÉ DU SOIR ENRICHI ───────────────────────────────────
    private fun envoyerResumeSoir() {
        val maintenant = java.util.Calendar.getInstance()
        val heure = maintenant.get(java.util.Calendar.HOUR_OF_DAY)
        // Envoyer uniquement entre 21h00 et 21h59
        if (heure != 21) return

        val prefs = context.getSharedPreferences(PREFS_FLUTTER, Context.MODE_PRIVATE)
        val notifSentPrefs = context.getSharedPreferences(KEY_NOTIF_SENT, Context.MODE_PRIVATE)
        val today = todayStr()
        val notifKey = "resume_soir_$today"
        if (notifSentPrefs.getBoolean(notifKey, false)) return

        // Lire le prénom de l'IA
        val prenomIA = prefs.getString("flutter.ia_prenom", "Aria") ?: "Aria"

        // Lire la dernière note journalière si disponible
        val derniereAnalyse = prefs.getString(KEY_DERNIERE_ANALYSE, null)
        val body = if (derniereAnalyse == today) {
            "$prenomIA a terminé l'analyse de la journée. Consultez votre journal IA pour voir ce qu'elle a appris."
        } else {
            "$prenomIA attend votre analyse du soir. Lancez IA Stats → Analyser la journée pour qu'elle apprenne de cette journée."
        }

        envoyerNotification(
            id = notifKey.hashCode(),
            title = "🌙 Résumé du soir — $prenomIA",
            body = body,
            channel = CHANNEL_RAPPEL
        )
        notifSentPrefs.edit().putBoolean(notifKey, true).apply()
    }

    // ─── ★ v9.85 : ALERTE CHUTE DE COTE (favori IA dont la cote baisse) ──────
    private fun alerterChuteCote(today: String) {
        val prefs = context.getSharedPreferences(PREFS_FLUTTER, Context.MODE_PRIVATE)
        val notifSentPrefs = context.getSharedPreferences(KEY_NOTIF_SENT, Context.MODE_PRIVATE)

        // ★ v9.93 : Lire d'abord les mouvements calculés par CoteTrackerService Flutter
        // (plus précis : fenêtre 15 min, seuil -40%, scoreIA intégré)
        val mouvRaw = prefs.getString("flutter.cote_mouvements_live_v1", null)
        if (mouvRaw != null && mouvRaw.length > 2) {
            try {
                val arr = org.json.JSONArray(mouvRaw)
                for (i in 0 until arr.length()) {
                    val obj = arr.getJSONObject(i)
                    val nomCheval    = obj.optString("nomCheval", "")
                    val courseKey    = obj.optString("courseKey", "")
                    val variationPct = obj.optDouble("variationPct", 0.0)
                    val coteDebut    = obj.optDouble("coteDebut", 0.0)
                    val coteCourante = obj.optDouble("coteCourante", 0.0)
                    val categorie    = obj.optString("categorie", "stable")

                    // Seuil : effondrement (-40%+) ou forte baisse (-20%+) seulement
                    if (variationPct > -20) continue
                    if (nomCheval.isEmpty() || courseKey.isEmpty()) continue

                    val notifKey = "chute_cote_flutter_${today}_${courseKey.take(12)}_${obj.optString("numero","")}"
                    if (notifSentPrefs.getBoolean(notifKey, false)) continue

                    val reduction = (-variationPct).toInt()
                    val titre = if (variationPct <= -40)
                        "🔥 Signal fort — $nomCheval"
                    else
                        "📉 Cote en baisse — $nomCheval"
                    val body = "Cote : ${String.format("%.1f", coteDebut)} → ${String.format("%.1f", coteCourante)} (−$reduction% en < 15 min)\nLe marché confirme l'analyse IA !"

                    envoyerNotification(
                        id = notifKey.hashCode(),
                        title = titre,
                        body = body,
                        channel = CHANNEL_COTES
                    )
                    notifSentPrefs.edit().putBoolean(notifKey, true).apply()
                }
                return // CoteTrackerService a pris en charge → pas besoin de la logique legacy
            } catch (e: Exception) {
                Log.e(TAG, "Erreur lecture mouvements Flutter: ${e.message}")
                // Fallback vers la logique legacy ci-dessous
            }
        }

        // ★ Logique legacy (fallback si CoteTrackerService n'a pas encore de données)
        val raw = prefs.getString(KEY_FAVORITES, "[]") ?: "[]"
        try {
            val arr = org.json.JSONArray(raw)
            val coteSaved = context.getSharedPreferences("hippique_cotes_saved", Context.MODE_PRIVATE)
            for (i in 0 until arr.length()) {
                val obj = arr.getJSONObject(i)
                val nomCourse = obj.optString("nomCourse", "")
                val scoreIA = obj.optDouble("scoreIA", 0.0)
                if (nomCourse.isEmpty() || scoreIA < 70) continue
                // ★ v9.93 : respecter le scope
                val ckR = obj.optInt("numR", 0)
                val ckC = obj.optInt("numC", 0)
                if (ckR > 0 && ckC > 0 && !coursePasseFiltre(ckR, ckC, today)) continue

                val coteActuelle = obj.optDouble("cote", 0.0)
                if (coteActuelle <= 0) continue

                val coteKey = "cote_${today}_${nomCourse.take(10)}"
                val coteAncienne = coteSaved.getFloat(coteKey, 0f).toDouble()

                if (coteAncienne > 0 && coteActuelle < coteAncienne * 0.75) {
                    val notifKey = "chute_cote_${today}_${nomCourse.take(10)}"
                    if (!notifSentPrefs.getBoolean(notifKey, false)) {
                        val reduction = ((1 - coteActuelle / coteAncienne) * 100).toInt()
                        envoyerNotification(
                            id = notifKey.hashCode(),
                            title = "📉 Signal fort — $nomCourse",
                            body = "La cote de votre favori IA a chuté de $reduction% (${String.format("%.1f", coteAncienne)} → ${String.format("%.1f", coteActuelle)}). Le marché confirme l'analyse IA !",
                            channel = CHANNEL_FAVORI
                        )
                        notifSentPrefs.edit().putBoolean(notifKey, true).apply()
                    }
                }
                coteSaved.edit().putFloat(coteKey, coteActuelle.toFloat()).apply()
            }
        } catch (e: Exception) {
            Log.e(TAG, "Erreur alerterChuteCote: ${e.message}")
        }
    }

    // ─── 9. ★ v9.86 : RAPPORT HEBDOMADAIRE (lundi 8h-10h) ───────────────────

    private fun envoyerRapportHebdomadaire() {
        val maintenant = java.util.Calendar.getInstance()
        val jourSemaine = maintenant.get(java.util.Calendar.DAY_OF_WEEK)
        val heure       = maintenant.get(java.util.Calendar.HOUR_OF_DAY)

        // Uniquement lundi (Calendar.MONDAY = 2), entre 8h et 10h
        if (jourSemaine != java.util.Calendar.MONDAY || heure < 8 || heure > 10) return

        val prefs = context.getSharedPreferences(PREFS_FLUTTER, Context.MODE_PRIVATE)
        val notifSentPrefs = context.getSharedPreferences(KEY_NOTIF_SENT, Context.MODE_PRIVATE)

        // Notifier une seule fois par semaine
        val sdf  = java.text.SimpleDateFormat("yyyyMMdd", java.util.Locale.FRANCE)
        val today = sdf.format(java.util.Date())
        val notifKey = "rapport_hebdo_$today"
        if (notifSentPrefs.getBoolean(notifKey, false)) return

        // Lire le rapport hebdomadaire stocké par Flutter (ia_rapport_hebdo_v1)
        val hebdoRaw = prefs.getString("flutter.ia_rapport_hebdo_v1", null)
        // Clé réelle écrite par IaPersonalityService Flutter : 'flutter.ia_prenom'
        val iaName   = prefs.getString("flutter.ia_prenom", "Mon IA") ?: "Mon IA"

        val body: String
        if (hebdoRaw != null) {
            try {
                val obj          = org.json.JSONObject(hebdoRaw)
                val nbJours      = obj.optInt("nbJours", 0)
                val tauxGagnant  = obj.optDouble("tauxGagnant", 0.0)
                val totalCourses = obj.optInt("totalCourses", 0)
                val meilleureDisc= obj.optString("meilleureDisc", "")
                val semaine      = obj.optString("semaine", "")

                body = buildString {
                    append("📊 Bilan semaine du $semaine — $nbJours jours analysés, $totalCourses courses. ")
                    append("Taux de réussite : ${tauxGagnant.toInt()}%.")
                    if (meilleureDisc.isNotEmpty()) append(" Meilleure discipline : $meilleureDisc.")
                    append(" Ouvrez le Journal IA pour les détails.")
                }
            } catch (e: Exception) {
                Log.e(TAG, "Erreur parse rapport hebdo: ${e.message}")
                return
            }
        } else {
            // Pas encore de rapport sauvegardé — message d'encouragement
            body = "$iaName analyse depuis quelques jours. Lancez une analyse journée pour construire votre premier bilan hebdo !"
        }

        envoyerNotification(
            id      = notifKey.hashCode(),
            title   = "📅 Bilan hebdomadaire de $iaName",
            body    = body,
            channel = CHANNEL_HEBDO
        )
        notifSentPrefs.edit().putBoolean(notifKey, true).apply()
        Log.d(TAG, "✅ Rapport hebdomadaire envoyé")
    }

    // ─── 10. ★ v9.86 : ALERTE PROGRESSION ELO CHEVAL ────────────────────────

    private fun alerterProgressionEloCheval(today: String) {
        val prefs = context.getSharedPreferences(PREFS_FLUTTER, Context.MODE_PRIVATE)
        val notifSentPrefs = context.getSharedPreferences(KEY_NOTIF_SENT, Context.MODE_PRIVATE)

        // Lire les ELO stockés par Flutter (elo_ratings_v1)
        val eloRaw = prefs.getString("elo_ratings_v1", null) ?: return

        try {
            val eloObj = org.json.JSONObject(eloRaw)
            val keys   = eloObj.keys()

            // Chercher un cheval avec une forte progression ELO cette semaine (variationMois > 60)
            val chevauxForts = mutableListOf<Pair<String, Double>>()
            while (keys.hasNext()) {
                val nomCle = keys.next()
                val entry  = eloObj.optJSONObject(nomCle) ?: continue
                val variation = entry.optDouble("variationMois", 0.0)
                val nbCourses = entry.optInt("nbCourses", 0)
                val rating    = entry.optDouble("rating", 1500.0)
                // Critère : progression significative (> 60 pts) + au moins 5 courses + rating élevé
                if (variation > 60 && nbCourses >= 5 && rating > 1600) {
                    chevauxForts.add(Pair(nomCle, variation))
                }
            }

            if (chevauxForts.isEmpty()) return

            // Trier par progression décroissante
            chevauxForts.sortByDescending { it.second }
            val top = chevauxForts.first()
            val nom = top.first.replace("_", " ")

            val notifKey = "elo_progression_${today}_${nom.take(10)}"
            if (notifSentPrefs.getBoolean(notifKey, false)) return

            // Vérifier si ce cheval est dans les favoris (courses suivies)
            val favJson = prefs.getString(KEY_FAVORITES, "[]") ?: "[]"
            val favArr  = org.json.JSONArray(favJson)
            var courseCheval = ""
            for (i in 0 until favArr.length()) {
                val fav = favArr.optJSONObject(i) ?: continue
                if (fav.optString("nom", "").equals(nom, ignoreCase = true)) {
                    courseCheval = fav.optString("nomCourse", "")
                    break
                }
            }

            val body = buildString {
                append("⚡ $nom affiche une progression ELO de +${top.second.toInt()} pts cette semaine — cheval en pleine montée en puissance.")
                if (courseCheval.isNotEmpty()) append(" Sa prochaine course : $courseCheval.")
                append(" Surveillez-le avant la publication des cotes !")
            }

            envoyerNotification(
                id      = notifKey.hashCode(),
                title   = "📈 Cheval en forme : $nom",
                body    = body,
                channel = CHANNEL_ELO
            )
            notifSentPrefs.edit().putBoolean(notifKey, true).apply()
            Log.d(TAG, "✅ Alerte ELO envoyée pour $nom (+${top.second.toInt()} pts)")

        } catch (e: Exception) {
            Log.e(TAG, "Erreur alerterProgressionEloCheval: ${e.message}")
        }
    }

    // ─── 11. ★ v9.86 : WIDGET BADGE IA ──────────────────────────────────────

    private fun mettreAJourWidgetBadgeIA() {
        val prefs = context.getSharedPreferences(PREFS_FLUTTER, Context.MODE_PRIVATE)

        try {
            // Lire les données IA depuis SharedPreferences
            // Clés réelles écrites par Flutter (avec préfixe 'flutter.') :
            //   IaBadgesService → 'flutter.ia_badges_v1' (JSON map des badges débloqués)
            //   IaPersonalityService → 'flutter.ia_prenom', 'flutter.ia_avatar_id'
            //   widget_service → 'flutter.widget_ia_badges', etc.
            // Le Worker ne peut pas désérialiser le JSON ia_badges_v1, il lit
            // directement les clés widget déjà préparées par widget_service.dart.
            val iaBadgesWidget  = prefs.getString("flutter.widget_ia_badges", "") ?: ""
            val niveauLabel     = prefs.getString("flutter.widget_ia_niveau", "") ?: ""
            val iaName          = prefs.getString("flutter.ia_prenom", "IA") ?: "IA"
            val nbBadges        = if (iaBadgesWidget.isNotEmpty()) 1 else 0

            if (iaBadgesWidget.isEmpty() && niveauLabel.isEmpty()) return

            // Écrire dans les clés widget Flutter (lues par widget_service.dart / RacePredictorWidget.kt)
            val editor = prefs.edit()
            if (iaBadgesWidget.isNotEmpty()) editor.putString("widget_ia_badges", iaBadgesWidget)
            if (niveauLabel.isNotEmpty())     editor.putString("widget_ia_niveau", niveauLabel)
            editor.putString("widget_ia_name", iaName)
            editor.apply()

            Log.d(TAG, "✅ Widget badge IA mis à jour : $nbBadges badges, niveau=$niveauLabel")
        } catch (e: Exception) {
            Log.e(TAG, "Erreur mettreAJourWidgetBadgeIA: ${e.message}")
        }
    }

    private fun rappelerAnalyseJournee() {
        val prefs = context.getSharedPreferences(PREFS_FLUTTER, Context.MODE_PRIVATE)
        val notifSentPrefs = context.getSharedPreferences(KEY_NOTIF_SENT, Context.MODE_PRIVATE)

        // Lire la date de dernière analyse depuis SharedPreferences Flutter
        val derniereAnalyseStr = prefs.getString(KEY_DERNIERE_ANALYSE, null)

        val maintenant = java.util.Calendar.getInstance()
        val heure = maintenant.get(java.util.Calendar.HOUR_OF_DAY)

        // N'envoyer le rappel qu'en soirée (entre 19h et 22h)
        if (heure < 19 || heure > 22) return

        val today = todayStr()
        val notifKey = "rappel_analyse_$today"
        if (notifSentPrefs.getBoolean(notifKey, false)) return

        // Calculer depuis combien de jours il n'y a pas eu d'analyse
        var joursDepuisAnalyse = 99
        if (derniereAnalyseStr != null) {
            try {
                val sdf = java.text.SimpleDateFormat("ddMMyyyy", java.util.Locale.FRANCE)
                val derniereDate = sdf.parse(derniereAnalyseStr)
                val maintDate = sdf.parse(today)
                if (derniereDate != null && maintDate != null) {
                    val diff = maintDate.time - derniereDate.time
                    joursDepuisAnalyse = (diff / (1000 * 60 * 60 * 24)).toInt()
                }
            } catch (e: Exception) {
                Log.d(TAG, "Erreur parsing date analyse: \${e.message}")
            }
        }

        // Alerter si 2 jours ou plus sans analyse (ou jamais analysé)
        if (joursDepuisAnalyse >= 2) {
            val msg = if (joursDepuisAnalyse >= 99)
                "Vous n'avez jamais lancé l'analyse de journée. " +
                "Ouvrez IA Stats → Analyser la journée pour alimenter l'apprentissage IA."
            else
                "Vous n'avez pas analysé depuis $joursDepuisAnalyse jour(s). " +
                "L'IA ne peut pas apprendre sans données ! Lancez l'analyse ce soir."

            envoyerNotification(
                id = notifKey.hashCode(),
                title = "📊 Analyse IA en attente",
                body = msg,
                channel = CHANNEL_RAPPEL
            )
            notifSentPrefs.edit().putBoolean(notifKey, true).apply()
            Log.d(TAG, "✅ Rappel analyse envoyé ($joursDepuisAnalyse jours)")
        }
    }

    // ─── NOTIFICATIONS ────────────────────────────────────────────────────────

    // ★ v9.93 : Lire les flags de scope depuis Flutter (multi-sélection possible)
    data class ScopeConfig(
        val toutes:  Boolean,
        val favoris: Boolean,
        val suivies: Boolean,
    )

    private fun lireScopeConfig(): ScopeConfig {
        val prefs = context.getSharedPreferences(PREFS_FLUTTER, Context.MODE_PRIVATE)
        val cfgStr = prefs.getString(KEY_ALERT_CONFIG, null)
            ?: return ScopeConfig(toutes = true, favoris = false, suivies = false)
        return try {
            val cfg = org.json.JSONObject(cfgStr)
            ScopeConfig(
                toutes  = cfg.optBoolean("scopeToutes",  true),
                favoris = cfg.optBoolean("scopeFavoris", false),
                suivies = cfg.optBoolean("scopeSuivies", false),
            )
        } catch (e: Exception) {
            ScopeConfig(toutes = true, favoris = false, suivies = false)
        }
    }

    // ★ v9.93 : Vérifier si une course passe le filtre scope
    // Gère correctement la multi-sélection :
    //   - scopeToutes seul         → toutes les courses
    //   - scopeFavoris seul        → favoris uniquement
    //   - scopeSuivies seul        → courses avec mise > 0
    //   - scopeFavoris + scopeSuivies → cours qui est favoris OU suivie (union)
    //   - aucun flag               → fallback toutes (sécurité)
    private fun coursePasseFiltre(numR: Int, numC: Int, today: String): Boolean {
        val scope = lireScopeConfig()

        // Aucun flag ou toutes → laisser passer
        val aucunFlag = !scope.toutes && !scope.favoris && !scope.suivies
        if (aucunFlag || scope.toutes) return true

        val prefs = context.getSharedPreferences(PREFS_FLUTTER, Context.MODE_PRIVATE)

        // Vérification favoris
        if (scope.favoris) {
            val favJson = prefs.getString(KEY_FAVORITES, "[]") ?: "[]"
            try {
                val arr = org.json.JSONArray(favJson)
                for (i in 0 until arr.length()) {
                    val f = arr.getJSONObject(i)
                    if (f.optInt("numR") == numR && f.optInt("numC") == numC) return true
                }
            } catch (e: Exception) { /* continuer */ }
        }

        // Vérification suivies (avec mise engagée > 0)
        if (scope.suivies) {
            val trackedJson = prefs.getString(KEY_TRACKED, "[]") ?: "[]"
            try {
                val arr = org.json.JSONArray(trackedJson)
                for (i in 0 until arr.length()) {
                    val t = arr.getJSONObject(i)
                    val tR = t.optInt("numReunion", 0)
                    val tC = t.optInt("numCourse",  0)
                    if (tR == numR && tC == numC) {
                        val mise = t.optDouble("miseEngagee", 0.0)
                        if (mise > 0) return true
                    }
                }
            } catch (e: Exception) { /* continuer */ }
        }

        // Aucune condition remplie → filtrer
        return false
    }

    private fun envoyerNotification(id: Int, title: String, body: String, channel: String) {
        val tapIntent = Intent(context, MainActivity::class.java).apply {
            flags = Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_CLEAR_TASK
        }
        val pendingFlags = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M)
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
        else PendingIntent.FLAG_UPDATE_CURRENT

        val pendingIntent = PendingIntent.getActivity(context, id, tapIntent, pendingFlags)

        val notif = NotificationCompat.Builder(context, channel)
            .setSmallIcon(R.drawable.ic_notification)
            .setContentTitle(title)
            .setContentText(body)
            .setStyle(NotificationCompat.BigTextStyle().bigText(body))
            .setPriority(NotificationCompat.PRIORITY_HIGH)
            .setAutoCancel(true)
            .setContentIntent(pendingIntent)
            .setVibrate(longArrayOf(0, 250, 150, 250))
            .build()

        val mgr = context.getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
        mgr.notify(id, notif)
    }

    private fun createNotificationChannels() {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O) return
        val mgr = context.getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager

        // Canal : Cotes disponibles
        if (mgr.getNotificationChannel(CHANNEL_COTES) == null) {
            mgr.createNotificationChannel(NotificationChannel(
                CHANNEL_COTES,
                "Cotes disponibles",
                NotificationManager.IMPORTANCE_HIGH
            ).apply {
                description = "Notification quand les cotes PMU sont publiées pour vos courses"
                enableVibration(true)
            })
        }
        // Canal : Départ imminent
        if (mgr.getNotificationChannel(CHANNEL_DEPART) == null) {
            mgr.createNotificationChannel(NotificationChannel(
                CHANNEL_DEPART,
                "Départ imminent",
                NotificationManager.IMPORTANCE_HIGH
            ).apply {
                description = "Alerte 10 minutes avant le départ d'un favori non parié"
                enableVibration(true)
            })
        }
        // Canal : Rappel analyse journée
        if (mgr.getNotificationChannel(CHANNEL_RAPPEL) == null) {
            mgr.createNotificationChannel(NotificationChannel(
                CHANNEL_RAPPEL,
                "Rappel analyse journée",
                NotificationManager.IMPORTANCE_DEFAULT
            ).apply {
                description = "Rappel quotidien si l'analyse de journée n'a pas été lancée"
                enableVibration(false)
            })
        }
        // Canal : Favoris IA
        if (mgr.getNotificationChannel(CHANNEL_FAVORI) == null) {
            mgr.createNotificationChannel(NotificationChannel(
                CHANNEL_FAVORI,
                "Favoris IA à surveiller",
                NotificationManager.IMPORTANCE_DEFAULT
            ).apply {
                description = "Rappel pour les courses favorites non pariées avec bonne cote"
                enableVibration(false)
            })
        }
        // ★ v9.86 : Canal bilan hebdomadaire
        if (mgr.getNotificationChannel(CHANNEL_HEBDO) == null) {
            mgr.createNotificationChannel(NotificationChannel(
                CHANNEL_HEBDO,
                "Bilan hebdomadaire IA",
                NotificationManager.IMPORTANCE_DEFAULT
            ).apply {
                description = "Bilan automatique chaque lundi matin : taux de réussite, meilleure discipline"
                enableVibration(false)
            })
        }
        // ★ v9.86 : Canal alerte ELO cheval en progression
        if (mgr.getNotificationChannel(CHANNEL_ELO) == null) {
            mgr.createNotificationChannel(NotificationChannel(
                CHANNEL_ELO,
                "Cheval en progression ELO",
                NotificationManager.IMPORTANCE_DEFAULT
            ).apply {
                description = "Alerte quand un cheval suivi affiche une forte progression ELO cette semaine"
                enableVibration(false)
            })
        }
    }

    // ─── UTILITAIRES ─────────────────────────────────────────────────────────

    private fun todayStr(): String {
        // Format API PMU : ddMMyyyy
        return SimpleDateFormat("ddMMyyyy", Locale.FRANCE).format(Date())
    }
}
