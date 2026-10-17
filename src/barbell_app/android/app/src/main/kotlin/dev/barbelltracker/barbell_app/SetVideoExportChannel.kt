package dev.barbelltracker.barbell_app

import android.content.Context
import android.graphics.Bitmap
import android.graphics.Canvas
import android.graphics.Color
import android.graphics.Paint
import android.graphics.Path
import android.graphics.PorterDuff
import android.graphics.RectF
import android.graphics.Typeface
import android.media.MediaMetadataRetriever
import android.util.Log
import androidx.annotation.OptIn
import androidx.media3.common.MediaItem
import androidx.media3.common.util.UnstableApi
import androidx.media3.effect.BitmapOverlay
import androidx.media3.effect.OverlayEffect
import androidx.media3.effect.OverlaySettings
import androidx.media3.effect.StaticOverlaySettings
import androidx.media3.effect.TextureOverlay
import androidx.media3.transformer.Composition
import androidx.media3.transformer.EditedMediaItem
import androidx.media3.transformer.Effects
import androidx.media3.transformer.ExportException
import androidx.media3.transformer.ExportResult
import androidx.media3.transformer.Transformer
import com.google.common.collect.ImmutableList
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import java.io.File

/**
 * Native half of `lib/video/set_video_exporter.dart`: crops a set's video
 * and burns in the metrics panel with Media3 Transformer, like the reference
 * app's `SetVideoExporter` + `SetMetricsOverlay`. All timing (crop, which
 * rep is shown, bar fill) is decided in Dart and arrives as samples; this
 * only draws.
 */
@OptIn(markerClass = [UnstableApi::class])
class SetVideoExportChannel(private val context: Context, messenger: BinaryMessenger) :
    MethodChannel.MethodCallHandler {

    private val channel = MethodChannel(messenger, "barbell_app/set_video_export")
    private var active: Transformer? = null
    private var pending: MethodChannel.Result? = null

    init {
        channel.setMethodCallHandler(this)
    }

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            "probe" -> {
                val meta = probe(call.argument<String>("path")!!)
                result.success(meta?.let {
                    mapOf("width" to it.width, "height" to it.height, "durationMs" to it.durationMs)
                })
            }
            "export" -> export(call, result)
            "cancel" -> {
                cancel()
                result.success(null)
            }
            else -> result.notImplemented()
        }
    }

    private data class Meta(val width: Int, val height: Int, val durationMs: Long)

    /** Display size (rotation applied) and duration, as `readMetadata`. */
    private fun probe(path: String): Meta? {
        val r = MediaMetadataRetriever()
        return try {
            r.setDataSource(path)
            val w = r.extractMetadata(MediaMetadataRetriever.METADATA_KEY_VIDEO_WIDTH)?.toIntOrNull()
            val h = r.extractMetadata(MediaMetadataRetriever.METADATA_KEY_VIDEO_HEIGHT)?.toIntOrNull()
            val rot = r.extractMetadata(MediaMetadataRetriever.METADATA_KEY_VIDEO_ROTATION)?.toIntOrNull() ?: 0
            val d = r.extractMetadata(MediaMetadataRetriever.METADATA_KEY_DURATION)?.toLongOrNull()
            if (w == null || h == null || d == null) null
            else if (rot == 90 || rot == 270) Meta(h, w, d) else Meta(w, h, d)
        } catch (e: Exception) {
            null
        } finally {
            try { r.release() } catch (_: Exception) {}
        }
    }

    private fun export(call: MethodCall, result: MethodChannel.Result) {
        if (active != null) {
            result.error("busy", "An export is already running", null)
            return
        }
        val input = call.argument<String>("input")!!
        val output = call.argument<String>("output")!!
        val meta = probe(input)
        if (meta == null) {
            result.success(false)
            return
        }
        @Suppress("UNCHECKED_CAST")
        val panel = SetMetricsOverlay(
            frameWidth = meta.width,
            frameHeight = meta.height,
            weightLine = call.argument<String>("weightLine")!!,
            repNumbers = call.argument<List<String>>("repNumbers")!!,
            repVelocities = call.argument<List<String>>("repVelocities")!!,
            repHasVelocity = call.argument<List<Boolean>>("repHasVelocity")!!,
            repBands = (call.argument<List<Any?>>("repBands")!!).map { b ->
                (b as List<Number>?)?.let { Pair(it[0].toFloat(), it[1].toFloat()) }
            },
            stepMs = call.argument<Int>("stepMs")!!,
            fill = call.argument<FloatArray>("fill")!!,
            barRep = call.argument<IntArray>("barRep")!!,
            activeRep = call.argument<IntArray>("activeRep")!!,
        )
        val start = (call.argument<Number>("cropStartMs")!!).toLong()
        val end = (call.argument<Number>("cropEndMs")!!).toLong()
        val item = MediaItem.Builder()
            .setUri(android.net.Uri.fromFile(File(input)))
            .setClippingConfiguration(
                MediaItem.ClippingConfiguration.Builder()
                    .setStartPositionMs(start)
                    .setEndPositionMs(end)
                    .build()
            )
            .build()
        val edited = EditedMediaItem.Builder(item)
            .setRemoveAudio(true)
            .setEffects(Effects(listOf(), listOf(OverlayEffect(ImmutableList.of<TextureOverlay>(panel)))))
            .build()
        File(output).delete()
        pending = result
        val transformer = Transformer.Builder(context)
            .addListener(object : Transformer.Listener {
                override fun onCompleted(composition: Composition, exportResult: ExportResult) {
                    finish(true)
                }

                override fun onError(
                    composition: Composition,
                    exportResult: ExportResult,
                    exportException: ExportException,
                ) {
                    Log.w(TAG, "Overlay export failed", exportException)
                    File(output).delete()
                    finish(false)
                }
            })
            .build()
        active = transformer
        try {
            transformer.start(edited, output)
        } catch (e: Exception) {
            Log.w(TAG, "Overlay export failed to start", e)
            finish(false)
        }
    }

    private fun finish(ok: Boolean) {
        active = null
        val r = pending
        pending = null
        r?.success(ok)
    }

    /** `cancelActiveExport`. The pending export call returns false. */
    private fun cancel() {
        try { active?.cancel() } catch (_: Exception) {}
        finish(false)
    }

    companion object {
        private const val TAG = "SetVideoExporter"
    }
}

/**
 * `SetMetricsOverlay`: a 450 × 230 (reference size, scaled to the frame)
 * panel 4 % from the left and 14 % from the bottom. Static: "Bar Speed",
 * "<weight> x <reps>", "Rep" and the bar track. Per frame: the bar fill
 * (purple, with the rep's orange sticking band in amber) and, while a rep
 * is in progress, its number and mean velocity in m/s.
 *
 * The reference app also draws its logo and a weight icon; this draws
 * neither.
 */
@OptIn(markerClass = [UnstableApi::class])
private class SetMetricsOverlay(
    private val frameWidth: Int,
    private val frameHeight: Int,
    private val weightLine: String,
    private val repNumbers: List<String>,
    private val repVelocities: List<String>,
    private val repHasVelocity: List<Boolean>,
    private val repBands: List<Pair<Float, Float>?>,
    private val stepMs: Int,
    private val fill: FloatArray,
    private val barRep: IntArray,
    private val activeRep: IntArray,
) : BitmapOverlay() {

    // SetVideoOverlayGeometry
    private val s = minOf(maxOf(frameWidth / 720f, frameHeight / 1280f), 3f)
    private val panelWidth = maxOf((s * 450f).toInt(), 1)
    private val panelHeight = maxOf((s * 230f).toInt(), 1)

    private val secondaryText = Color.argb(255, 199, 199, 204)
    private val barPurple = Color.parseColor("#9357FF")
    private val barAmber = Color.parseColor("#FF9900")
    private val bold = Typeface.create(Typeface.DEFAULT, Typeface.BOLD)

    private val basePanel: Bitmap by lazy { renderBasePanel() }

    // Two buffers so each frame hands Media3 a different bitmap and it
    // always re-uploads the texture.
    private val work = Array(2) { Bitmap.createBitmap(panelWidth, panelHeight, Bitmap.Config.ARGB_8888) }
    private var flip = 0

    private val settings: OverlaySettings by lazy {
        val x = (((0.04f * frameWidth) + panelWidth / 2f) * 2f) / frameWidth - 1f
        val y = (((0.14f * frameHeight) + panelHeight / 2f) * 2f) / frameHeight - 1f
        StaticOverlaySettings.Builder().setBackgroundFrameAnchor(x, y).build()
    }

    override fun getOverlaySettings(presentationTimeUs: Long): OverlaySettings = settings

    override fun getBitmap(presentationTimeUs: Long): Bitmap {
        val k = ((presentationTimeUs / 1000) / stepMs).toInt().coerceIn(0, fill.size - 1)
        flip = 1 - flip
        val bmp = work[flip]
        val canvas = Canvas(bmp)
        canvas.drawColor(0, PorterDuff.Mode.CLEAR)
        canvas.drawBitmap(basePanel, 0f, 0f, null)
        drawRepBar(canvas, fill[k], barRep[k])
        drawActiveRep(canvas, activeRep[k])
        return bmp
    }

    private fun renderBasePanel(): Bitmap {
        val bmp = Bitmap.createBitmap(panelWidth, panelHeight, Bitmap.Config.ARGB_8888)
        val canvas = Canvas(bmp)
        val bg = Paint(Paint.ANTI_ALIAS_FLAG).apply { color = Color.BLACK; alpha = 153 }
        canvas.drawRoundRect(RectF(0f, 0f, panelWidth.toFloat(), panelHeight.toFloat()), s * 20f, s * 20f, bg)
        val title = Paint(Paint.ANTI_ALIAS_FLAG).apply {
            color = Color.WHITE; textSize = s * 35f; typeface = bold
        }
        canvas.drawText("Bar Speed", s * 25f, s * 95f, title)
        val secondary = Paint(Paint.ANTI_ALIAS_FLAG).apply { color = secondaryText; textSize = s * 30f }
        canvas.drawText(weightLine, s * 60f, s * 145f, secondary)
        val rep = Paint(Paint.ANTI_ALIAS_FLAG).apply { color = secondaryText; textSize = s * 35f }
        canvas.drawText("Rep", s * 310f, s * 75f, rep)
        val track = Paint(Paint.ANTI_ALIAS_FLAG).apply { color = Color.WHITE; alpha = 51 }
        canvas.drawRoundRect(barTrackRect(), s * 15f, s * 15f, track)
        return bmp
    }

    private fun barTrackRect(): RectF {
        val h = s * 30f
        val top = panelHeight - s * 25f - h
        return RectF(s * 25f, top, s * 25f + s * 400f, top + h)
    }

    private fun drawRepBar(canvas: Canvas, f: Float, rep: Int) {
        if (f <= 0f || rep < 0) return
        val r = barTrackRect()
        canvas.save()
        canvas.clipPath(Path().apply { addRoundRect(r, s * 15f, s * 15f, Path.Direction.CW) })
        val purple = Paint(Paint.ANTI_ALIAS_FLAG).apply { color = barPurple }
        canvas.drawRect(r.left, r.top, r.left + r.width() * f, r.bottom, purple)
        val band = repBands.getOrNull(rep)
        if (band != null && f > band.first) {
            val amber = Paint(Paint.ANTI_ALIAS_FLAG).apply { color = barAmber }
            canvas.drawRect(
                r.left + r.width() * band.first, r.top,
                r.left + r.width() * minOf(f, band.second), r.bottom, amber,
            )
        }
        canvas.restore()
    }

    private fun drawActiveRep(canvas: Canvas, rep: Int) {
        if (rep < 0 || rep >= repNumbers.size) return
        val number = Paint(Paint.ANTI_ALIAS_FLAG).apply {
            color = Color.WHITE; textSize = s * 35f; typeface = bold; textAlign = Paint.Align.RIGHT
        }
        canvas.drawText(repNumbers[rep], s * 415f, s * 75f, number)
        val velocity = Paint(Paint.ANTI_ALIAS_FLAG).apply {
            color = if (repHasVelocity[rep]) Color.WHITE else secondaryText
            textSize = s * 50f; typeface = bold; textAlign = Paint.Align.RIGHT
        }
        canvas.drawText(repVelocities[rep], s * 360f, s * 150f, velocity)
        val unit = Paint(Paint.ANTI_ALIAS_FLAG).apply {
            color = secondaryText; textSize = s * 35f; typeface = bold; textAlign = Paint.Align.RIGHT
        }
        canvas.drawText("m/s", s * 425f, s * 150f, unit)
    }
}
