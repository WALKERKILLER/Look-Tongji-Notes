package cn.lookstudio.look_studio

import android.app.Activity
import android.os.Build
import android.view.KeyEvent
import android.view.MotionEvent
import android.view.View
import android.view.ViewGroup
import androidx.input.motionprediction.MotionEventPredictor
import com.huawei.stylus.penengine.estimate.HwMotionEventInfo
import com.huawei.stylus.penengine.estimate.HwMotionEventQueue
import com.huawei.stylus.penengine.estimate.HwStrokeEstimate
import io.flutter.embedding.android.FlutterView
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodChannel
import kotlin.math.hypot

/** Optional, frame-coalesced preview data. Real pointer input stays in Flutter.
 * Sources and fallback rationale: docs/decisions/0023-native-stylus-preview.md.
 */
class StylusBridge(private val activity: Activity, messenger: BinaryMessenger) {
    private val channel = EventChannel(messenger, "look/stylus/events")
    private val methods = MethodChannel(messenger, "look/stylus")
    private var sink: EventChannel.EventSink? = null
    private var enabled = false
    private var buttons = false
    private var predictor: MotionEventPredictor? = null
    private var vendor: HwMotionEventQueue? = null
    private var vendorChecked = false
    private var lastVendorTime = -1L
    private var last: MotionEvent? = null
    private var scheduled = false
    private var previewFrames = 0
    private var sideButtonArmed = false
    private var sideButtonUsedForContact = false
    private var buttonEvents = 0
    private var vendorFrames = 0
    private var fallbackFrames = 0
    private var backend = "off"
    private val root get() = activity.window.decorView
    private val frame = Runnable { scheduled = false; publish() }

    init {
        channel.setStreamHandler(object : EventChannel.StreamHandler {
            override fun onListen(arguments: Any?, events: EventChannel.EventSink) { sink = events }
            override fun onCancel(arguments: Any?) { sink = null; reset() }
        })
        methods.setMethodCallHandler { call, result ->
            when (call.method) {
                "configure" -> {
                    enabled = call.argument<Boolean>("prediction") == true
                    buttons = call.argument<Boolean>("buttons") == true
                    reset()
                    if (enabled) prepare()
                    result.success(status())
                }
                "status" -> result.success(status())
                else -> result.notImplemented()
            }
        }
    }

    private fun status() = mapOf("backend" to backend, "previewFrames" to previewFrames,
        "buttonEvents" to buttonEvents, "vendorFrames" to vendorFrames,
        "fallbackFrames" to fallbackFrames, "vendorAvailable" to (vendor != null))

    private fun prepare() {
        predictor = MotionEventPredictor.newInstance(root)
        if (!vendorChecked) {
            vendorChecked = true
            // Missing vendor runtime must never prevent the application starting.
            try {
                if (Build.MANUFACTURER.equals("HUAWEI", true) && HwStrokeEstimate.isFeatureEnable()) {
                    vendor = HwMotionEventQueue()
                }
            } catch (_: LinkageError) { vendor = null }
              catch (_: RuntimeException) { vendor = null }
        }
        backend = if (vendor != null) "huawei" else "androidx"
    }

    fun touch(event: MotionEvent) {
        if (sideButtonArmed && event.buttonState and MotionEvent.BUTTON_STYLUS_PRIMARY != 0) {
            sideButtonUsedForContact = true
        }
        if (!enabled || sink == null) return
        if (predictor == null) prepare()
        try { predictor?.record(event) }
        catch (_: IllegalArgumentException) { predictor = MotionEventPredictor.newInstance(root) }
        if (event.actionMasked == MotionEvent.ACTION_UP ||
            event.actionMasked == MotionEvent.ACTION_CANCEL || event.pointerCount != 1) {
            clearTail()
            clearVendor()
            return
        }
        if (event.getToolType(0) != MotionEvent.TOOL_TYPE_STYLUS ||
            event.actionMasked !in listOf(MotionEvent.ACTION_DOWN, MotionEvent.ACTION_MOVE)) return
        if (event.actionMasked == MotionEvent.ACTION_DOWN) clearVendor()
        vendor?.let { queue ->
            try {
                val samples = ArrayList<HwMotionEventInfo>()
                for (h in 0 until event.historySize) {
                    val time = event.getHistoricalEventTime(h)
                    if (time > lastVendorTime) samples.add(HwMotionEventInfo(
                        event.getHistoricalX(h), event.getHistoricalY(h), event.getHistoricalPressure(h),
                        event.getHistoricalAxisValue(MotionEvent.AXIS_TILT, h), time))
                }
                if (event.eventTime > lastVendorTime) samples.add(HwMotionEventInfo(
                    event.x, event.y, event.pressure, event.getAxisValue(MotionEvent.AXIS_TILT), event.eventTime))
                lastVendorTime = event.eventTime
                if (samples.isNotEmpty() && queue.fill(samples) < 0) disableVendor()
            } catch (_: LinkageError) { disableVendor() }
              catch (_: RuntimeException) { disableVendor() }
        }
        last?.recycle()
        last = MotionEvent.obtain(event)
        if (!scheduled) { scheduled = true; root.postOnAnimation(frame) }
    }

    private fun flutterView(view: View): FlutterView? {
        if (view is FlutterView) return view
        if (view is ViewGroup) for (i in 0 until view.childCount) {
            flutterView(view.getChildAt(i))?.let { return it }
        }
        return null
    }

    private fun publish() {
        val e = last ?: return
        val view = flutterView(root) ?: return
        val density = activity.resources.displayMetrics.density
        val location = IntArray(2); view.getLocationOnScreen(location)
        val dx = e.rawX - e.x - location[0]; val dy = e.rawY - e.y - location[1]
        val points = ArrayList<List<Double>>()
        fun add(x: Float, y: Float, pressure: Float, time: Long) {
            if (!x.isFinite() || !y.isFinite() || !pressure.isFinite() ||
                time <= e.eventTime || time > e.eventTime + 48 ||
                hypot(x - e.x, y - e.y) > 48 * density || points.size >= 8) return
            points.add(listOf(((x + dx) / density).toDouble(), ((y + dy) / density).toDouble(),
                pressure.coerceIn(.05f, 1f).toDouble()))
        }
        vendor?.let { queue ->
            try {
                HwStrokeEstimate.setRefreshRate(view.display?.refreshRate ?: 60f)
                val predicted = ArrayList<HwMotionEventInfo>()
                if (HwStrokeEstimate.getEstimateEvent(queue.queue, predicted) < 0) disableVendor()
                else predicted.take(8).forEach { add(it.x, it.y, it.press, it.eventTime) }
            } catch (_: LinkageError) { disableVendor() }
              catch (_: RuntimeException) { disableVendor() }
        }
        // AndroidX is continuously fed, so vendor failure has a warm fallback.
        if (points.isNotEmpty()) vendorFrames++
        if (points.isEmpty()) {
            var predicted: MotionEvent? = null
            try {
                predicted = predictor?.predict()
                predicted?.let { p ->
                    for (h in 0 until p.historySize) add(p.getHistoricalX(h), p.getHistoricalY(h),
                        p.getHistoricalPressure(h), p.getHistoricalEventTime(h))
                    add(p.x, p.y, p.pressure, p.eventTime)
                }
            } catch (_: IllegalArgumentException) { /* Next real event replaces the preview. */ }
            finally { predicted?.recycle() }
            if (points.isNotEmpty()) fallbackFrames++
        }
        if (points.isNotEmpty()) previewFrames++
        sink?.success(mapOf("type" to "prediction", "time" to e.eventTime,
            "x" to (e.x + dx) / density, "y" to (e.y + dy) / density, "points" to points))
    }

    fun generic(event: MotionEvent) {
        if (!buttons || event.pointerCount != 1 ||
            event.getToolType(0) != MotionEvent.TOOL_TYPE_STYLUS ||
            event.actionButton != MotionEvent.BUTTON_STYLUS_PRIMARY) return
        if (event.actionMasked == MotionEvent.ACTION_BUTTON_PRESS) {
            sideButtonArmed = true
            sideButtonUsedForContact = false
        } else if (event.actionMasked == MotionEvent.ACTION_BUTTON_RELEASE) {
            // Holding the side button while touching uses Flutter's temporary
            // eraser. Only a complete hover click toggles the selected tool.
            if (sideButtonArmed && !sideButtonUsedForContact) toggle()
            sideButtonArmed = false
        }
    }

    fun key(event: KeyEvent): Boolean {
        if (!buttons || sink == null || event.keyCode != KeyEvent.KEYCODE_STYLUS_BUTTON_PRIMARY) return false
        if (event.action == KeyEvent.ACTION_UP && !event.isCanceled) toggle()
        return true
    }

    private fun toggle() {
        if (!buttons || sink == null) return
        buttonEvents++
        sink?.success(mapOf("type" to "toggleEraser"))
    }

    private fun clearVendor() {
        lastVendorTime = -1
        try { vendor?.clear() } catch (_: LinkageError) { disableVendor() }
        catch (_: RuntimeException) { disableVendor() }
    }

    private fun disableVendor() { vendor = null; backend = "androidx" }
    private fun clearTail() {
        root.removeCallbacks(frame); scheduled = false
        last?.recycle(); last = null
        sink?.success(mapOf("type" to "clear"))
    }
    fun reset() {
        clearTail(); clearVendor(); predictor = null; backend = "off"
        sideButtonArmed = false; sideButtonUsedForContact = false
    }
    fun dispose() { reset(); channel.setStreamHandler(null); methods.setMethodCallHandler(null); sink = null }
}
