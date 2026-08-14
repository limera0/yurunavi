package com.westinx.yurunavi

import android.app.Service
import android.content.Intent
import android.content.SharedPreferences
import android.graphics.PixelFormat
import android.os.Build
import android.os.IBinder
import android.provider.Settings
import android.view.Gravity
import android.view.LayoutInflater
import android.view.MotionEvent
import android.view.View
import android.view.WindowManager
import android.widget.ImageView
import android.widget.TextView
import kotlin.math.abs

/**
 * 플로팅 오버레이 서비스 — SYSTEM_ALERT_WINDOW 권한으로 다른 앱 위에 안내 아이콘을 표시한다.
 *
 * S21 리디자인(2026-08-14, 네이버지도 스타일 기준):
 * - 2줄(현재+다음 안내) 표시, 화면폭 비례 크기(72dp 정사각형 대비 대폭 확대).
 * - 드래그로 화면 어디든 이동 가능, 마지막 위치를 SharedPreferences에 저장해 다음 표시 때 복원.
 * - Dart에서 `com.westinx.yurunavi/nav_floating` MethodChannel을 통해 show/update/hide 를 호출.
 * - 짧은 탭(드래그 임계값 미만 이동) 시 getLaunchIntentForPackage + FLAG_ACTIVITY_NEW_TASK |
 *   SINGLE_TOP | CLEAR_TOP 으로 기존 MainActivity를 포그라운드로 복귀 → nav_screen이 resumed
 *   훅에서 hide() 를 호출.
 */
class FloatingOverlayService : Service() {

    companion object {
        const val ACTION_SHOW   = "com.westinx.yurunavi.action.OVERLAY_SHOW"
        const val ACTION_UPDATE = "com.westinx.yurunavi.action.OVERLAY_UPDATE"
        const val ACTION_HIDE   = "com.westinx.yurunavi.action.OVERLAY_HIDE"
        const val EXTRA_ICON    = "iconRes"
        const val EXTRA_TEXT    = "distanceText"
        const val EXTRA_ICON2   = "iconRes2"
        const val EXTRA_TEXT2   = "distanceText2"

        private const val PREFS_NAME = "yurunavi_overlay_prefs"
        private const val KEY_POS_X = "overlay_pos_x"
        private const val KEY_POS_Y = "overlay_pos_y"

        /** 짧은 탭 vs 드래그를 가르는 이동 임계값(dp). */
        private const val DRAG_THRESHOLD_DP = 10f

        /** 오버레이 폭 = 화면폭의 이 비율 (네이버지도 참고 스크린샷 기준 30~40%). */
        private const val WIDTH_RATIO = 0.35f

        /** iconType 문자열 → 앱 내 아이콘 리소스 이름 매핑 */
        internal fun drawableNameForIconType(iconType: String): String = when (iconType) {
            "nav_right"                -> "nav_right"
            "nav_sharp_right"          -> "nav_sharp_right"
            "nav_uturn"                -> "nav_uturn"
            "nav_sharp_left"           -> "nav_sharp_left"
            "nav_left"                 -> "nav_left"
            "nav_fork_right"           -> "nav_fork_right"
            "nav_fork_left"            -> "nav_fork_left"
            "nav_roundabout_right"     -> "nav_roundabout_right"
            "nav_roundabout_left"      -> "nav_roundabout_left"
            "nav_roundabout_straight"  -> "nav_roundabout_straight"
            else                       -> "nav_straight"
        }
    }

    private var windowManager: WindowManager? = null
    private var overlayView: View? = null
    private var overlayParams: WindowManager.LayoutParams? = null

    override fun onBind(intent: Intent?): IBinder? = null

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        when (intent?.action) {
            ACTION_SHOW -> {
                val iconType = intent.getStringExtra(EXTRA_ICON) ?: "nav_straight"
                val distText = intent.getStringExtra(EXTRA_TEXT) ?: ""
                val iconType2 = intent.getStringExtra(EXTRA_ICON2)
                val distText2 = intent.getStringExtra(EXTRA_TEXT2)
                showOverlay(iconType, distText, iconType2, distText2)
            }
            ACTION_UPDATE -> {
                val iconType = intent.getStringExtra(EXTRA_ICON) ?: "nav_straight"
                val distText = intent.getStringExtra(EXTRA_TEXT) ?: ""
                val iconType2 = intent.getStringExtra(EXTRA_ICON2)
                val distText2 = intent.getStringExtra(EXTRA_TEXT2)
                updateOverlay(iconType, distText, iconType2, distText2)
            }
            ACTION_HIDE -> {
                hideOverlay()
                stopSelf(startId)
            }
        }
        return START_NOT_STICKY
    }

    override fun onDestroy() {
        hideOverlay()
        super.onDestroy()
    }

    private fun prefs(): SharedPreferences =
        getSharedPreferences(PREFS_NAME, MODE_PRIVATE)

    private fun showOverlay(iconType: String, distText: String, iconType2: String?, distText2: String?) {
        if (!Settings.canDrawOverlays(this)) return
        if (overlayView != null) {
            // 이미 떠 있으면 업데이트만
            updateOverlay(iconType, distText, iconType2, distText2)
            return
        }

        val wm = getSystemService(WINDOW_SERVICE) as WindowManager
        windowManager = wm

        val view = LayoutInflater.from(this)
            .inflate(R.layout.floating_nav, null)

        applyGuidance(view, iconType, distText, iconType2, distText2)

        val density = resources.displayMetrics.density
        val screenWidth = resources.displayMetrics.widthPixels
        val screenHeight = resources.displayMetrics.heightPixels
        val widthPx = (screenWidth * WIDTH_RATIO).toInt()

        val type = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            WindowManager.LayoutParams.TYPE_APPLICATION_OVERLAY
        } else {
            @Suppress("DEPRECATION")
            WindowManager.LayoutParams.TYPE_PHONE
        }
        val params = WindowManager.LayoutParams(
            widthPx,
            WindowManager.LayoutParams.WRAP_CONTENT,
            type,
            WindowManager.LayoutParams.FLAG_NOT_FOCUSABLE or
                    WindowManager.LayoutParams.FLAG_LAYOUT_IN_SCREEN,
            PixelFormat.TRANSLUCENT
        ).apply {
            gravity = Gravity.TOP or Gravity.START
            val savedX = prefs().getInt(KEY_POS_X, -1)
            val savedY = prefs().getInt(KEY_POS_Y, -1)
            if (savedX >= 0 && savedY >= 0) {
                x = savedX
                y = savedY
            } else {
                // 기본 위치: 화면 중앙보다 살짝 아래(코너 고정이 아니라 참고 스크린샷의
                // 자유 배치 느낌에 맞춘 초기값) — 실기기 검증에서 조정 대상.
                x = screenWidth - widthPx - (16 * density).toInt()
                y = (screenHeight * 0.4f).toInt()
            }
        }

        view.setOnTouchListener(makeDragTouchListener(view, params, wm, density, screenWidth, screenHeight, widthPx))

        overlayView = view
        overlayParams = params
        wm.addView(view, params)
    }

    /**
     * 드래그 이동 + 짧은 탭(=앱 복귀) 제스처를 한 리스너에서 처리한다.
     * ACTION_UP에서 총 이동량이 [DRAG_THRESHOLD_DP] 미만이면 탭으로 간주해 앱을 복귀시키고,
     * 그 이상이면 드래그로 간주해 마지막 위치를 저장한다 — 둘이 서로의 제스처를 삼키지 않도록
     * 별도의 OnClickListener는 두지 않는다.
     */
    private fun makeDragTouchListener(
        view: View,
        params: WindowManager.LayoutParams,
        wm: WindowManager,
        density: Float,
        screenWidth: Int,
        screenHeight: Int,
        viewWidthPx: Int,
    ): View.OnTouchListener {
        val dragThresholdPx = DRAG_THRESHOLD_DP * density
        var initialX = 0
        var initialY = 0
        var initialTouchX = 0f
        var initialTouchY = 0f
        var isDragging = false

        return View.OnTouchListener { v, event ->
            when (event.action) {
                MotionEvent.ACTION_DOWN -> {
                    initialX = params.x
                    initialY = params.y
                    initialTouchX = event.rawX
                    initialTouchY = event.rawY
                    isDragging = false
                    true
                }
                MotionEvent.ACTION_MOVE -> {
                    val dx = event.rawX - initialTouchX
                    val dy = event.rawY - initialTouchY
                    if (!isDragging && (abs(dx) > dragThresholdPx || abs(dy) > dragThresholdPx)) {
                        isDragging = true
                    }
                    if (isDragging) {
                        val viewHeightPx = if (v.height > 0) v.height else viewWidthPx
                        params.x = (initialX + dx.toInt())
                            .coerceIn(0, (screenWidth - viewWidthPx).coerceAtLeast(0))
                        params.y = (initialY + dy.toInt())
                            .coerceIn(0, (screenHeight - viewHeightPx).coerceAtLeast(0))
                        wm.updateViewLayout(v, params)
                    }
                    true
                }
                MotionEvent.ACTION_UP -> {
                    if (isDragging) {
                        prefs().edit()
                            .putInt(KEY_POS_X, params.x)
                            .putInt(KEY_POS_Y, params.y)
                            .apply()
                    } else {
                        launchApp()
                    }
                    true
                }
                else -> false
            }
        }
    }

    private fun launchApp() {
        val launchIntent = (packageManager.getLaunchIntentForPackage(packageName)
            ?: Intent(this, MainActivity::class.java)).apply {
            flags = Intent.FLAG_ACTIVITY_NEW_TASK or
                    Intent.FLAG_ACTIVITY_SINGLE_TOP or
                    Intent.FLAG_ACTIVITY_CLEAR_TOP
        }
        startActivity(launchIntent)
    }

    private fun applyGuidance(view: View, iconType: String, distText: String, iconType2: String?, distText2: String?) {
        val iconName = drawableNameForIconType(iconType)
        val iconResId = resources.getIdentifier(iconName, "drawable", packageName)
        if (iconResId != 0) {
            view.findViewById<ImageView>(R.id.nav_icon)?.setImageResource(iconResId)
        }
        view.findViewById<TextView>(R.id.nav_dist)?.text = distText

        val rowNext = view.findViewById<View>(R.id.nav_row_next)
        val divider = view.findViewById<View>(R.id.nav_divider)
        if (iconType2.isNullOrEmpty() && distText2.isNullOrEmpty()) {
            rowNext?.visibility = View.GONE
            divider?.visibility = View.GONE
        } else {
            val iconName2 = drawableNameForIconType(iconType2 ?: "nav_straight")
            val iconResId2 = resources.getIdentifier(iconName2, "drawable", packageName)
            if (iconResId2 != 0) {
                view.findViewById<ImageView>(R.id.nav_icon2)?.setImageResource(iconResId2)
            }
            view.findViewById<TextView>(R.id.nav_dist2)?.text = distText2 ?: ""
            rowNext?.visibility = View.VISIBLE
            divider?.visibility = View.VISIBLE
        }
    }

    private fun updateOverlay(iconType: String, distText: String, iconType2: String?, distText2: String?) {
        val view = overlayView ?: run {
            showOverlay(iconType, distText, iconType2, distText2)
            return
        }
        applyGuidance(view, iconType, distText, iconType2, distText2)
    }

    private fun hideOverlay() {
        overlayView?.let { v ->
            try {
                windowManager?.removeView(v)
            } catch (_: Exception) { /* view가 이미 분리됐으면 무시 */ }
        }
        overlayView = null
        overlayParams = null
    }
}
