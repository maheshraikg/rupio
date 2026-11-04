package com.kspstadk.rupeetrack

import android.app.PendingIntent
import android.appwidget.AppWidgetManager
import android.appwidget.AppWidgetProvider
import android.content.ComponentName
import android.content.Context
import android.content.Intent
import android.graphics.Bitmap
import android.graphics.Canvas
import android.graphics.Color
import android.graphics.Paint
import android.graphics.RectF
import android.widget.RemoteViews
import org.json.JSONObject

/**
 * Home screen widget: this month's spending and one bar per day.
 *
 * The app sends the figures (already formatted and translated) through the
 * "updateWidget" method of the native channel; they are kept in the
 * widget's own preferences so the widget can redraw without the app.
 */
class SpendWidgetProvider : AppWidgetProvider() {
    override fun onUpdate(context: Context, manager: AppWidgetManager, ids: IntArray) {
        for (id in ids) manager.updateAppWidget(id, build(context))
    }

    companion object {
        private const val PREFS = "rupeetrack_widget"
        private const val KEY = "data"

        /** Stores [json] and redraws every Rupio widget. */
        fun save(context: Context, json: String) {
            context.getSharedPreferences(PREFS, Context.MODE_PRIVATE)
                .edit().putString(KEY, json).apply()
            val manager = AppWidgetManager.getInstance(context)
            val ids = manager.getAppWidgetIds(
                ComponentName(context, SpendWidgetProvider::class.java)
            )
            for (id in ids) manager.updateAppWidget(id, build(context))
        }

        private fun build(context: Context): RemoteViews {
            val views = RemoteViews(context.packageName, R.layout.rupeetrack_widget)
            val raw = context.getSharedPreferences(PREFS, Context.MODE_PRIVATE)
                .getString(KEY, null)
            var label = "Rupio"
            var total = "₹0"
            var values = DoubleArray(0)
            var color = Color.parseColor("#F87171")
            if (raw != null) {
                try {
                    val j = JSONObject(raw)
                    label = j.optString("label", label)
                    total = j.optString("total", total)
                    val arr = j.optJSONArray("values")
                    if (arr != null) {
                        values = DoubleArray(arr.length()) { arr.optDouble(it, 0.0) }
                    }
                    color = Color.parseColor(j.optString("color", "#F87171"))
                } catch (e: Exception) {
                    // Keep the defaults if the saved data is unreadable.
                }
            }
            views.setTextViewText(R.id.widget_label, label)
            views.setTextViewText(R.id.widget_total, total)
            views.setImageViewBitmap(R.id.widget_bars, bars(values, color))
            val open = Intent(context, MainActivity::class.java)
                .addFlags(Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_CLEAR_TOP)
            val pending = PendingIntent.getActivity(
                context, 0, open,
                PendingIntent.FLAG_IMMUTABLE or PendingIntent.FLAG_UPDATE_CURRENT
            )
            views.setOnClickPendingIntent(R.id.widget_root, pending)
            return views
        }

        private fun bars(values: DoubleArray, color: Int): Bitmap {
            val w = 620
            val h = 160
            val bmp = Bitmap.createBitmap(w, h, Bitmap.Config.ARGB_8888)
            val canvas = Canvas(bmp)
            val base = Paint(Paint.ANTI_ALIAS_FLAG)
            base.color = Color.parseColor("#2E2E2E")
            base.strokeWidth = 2f
            canvas.drawLine(0f, h - 1f, w.toFloat(), h - 1f, base)
            if (values.isEmpty()) return bmp
            var max = 0.0
            for (v in values) if (v > max) max = v
            val slot = w.toFloat() / values.size
            val bw = minOf(slot * 0.55f, 28f)
            val paint = Paint(Paint.ANTI_ALIAS_FLAG)
            for (i in values.indices) {
                val v = values[i]
                val scaled = if (max <= 0.0) 0f else (v / max * (h - 8)).toFloat()
                val height = if (v > 0.0) maxOf(scaled, 6f) else 3f
                val left = i * slot + (slot - bw) / 2
                paint.color = color
                paint.alpha = if (v > 0.0) 255 else 70
                canvas.drawRoundRect(
                    RectF(left, h - height, left + bw, h.toFloat()), bw / 2, bw / 2, paint
                )
            }
            return bmp
        }
    }
}
