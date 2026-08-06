package com.westinx.yurunavi

import android.app.Service
import android.content.Intent
import android.graphics.PixelFormat
import android.os.Build
import android.os.IBinder
import android.provider.Settings
import android.view.Gravity
import android.view.LayoutInflater
import android.view.View
import android.view.WindowManager
import android.widget.ImageView
import android.widget.TextView

/**
 * 플로팅 오버레이 서비스 — SYSTEM_ALERT_WINDOW 권한으로 다른 앱 위에 안내 아이콘을 표시한다.
 *
 * - Dart에서 `com.westinx.yurunavi/nav_floating` MethodChannel을 통해 show/update/hide 를 호출.
 * - 탭 시 getLaunchIntentForPackage + FLAG_ACTIVITY_NEW_TASK | SINGLE_TOP | CLEAR_TOP 으로
 *   기존 MainActivity를 포그라운드로 복귀 → nav_screen이 resumed 훅에서 hide() 를 호출.
 * - 드래그 이동은 v1 스코프 밖 — 고정 위치(우측 하단, 72dp 정사각형).
 */
class FloatingOverlayService : Service() {

    companion object {
        const val ACTION_SHOW   = "com.westinx.yurunavi.action.OVERLAY_SHOW"
        const val ACTION_UPDATE = "com.westinx.yurunavi.action.OVERLAY_UPDATE"
        const val ACTION_HIDE   = "com.westinx.yurunavi.action.OVERLAY_HIDE"
        const val EXTRA_ICON    = "iconRes"
        const val EXTRA_TEXT    = "distanceText"

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

    override fun onBind(intent: Intent?): IBinder? = null

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        when (intent?.action) {
            ACTION_SHOW -> {
                val iconType = intent.getStringExtra(EXTRA_ICON) ?: "nav_straight"
                val distText = intent.getStringExtra(EXTRA_TEXT) ?: ""
                showOverlay(iconType, distText)
            }
            ACTION_UPDATE -> {
                val iconType = intent.getStringExtra(EXTRA_ICON) ?: "nav_straight"
                val distText = intent.getStringExtra(EXTRA_TEXT) ?: ""
                updateOverlay(iconType, distText)
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

    private fun showOverlay(iconType: String, distText: String) {
        if (!Settings.canDrawOverlays(this)) return
        if (overlayView != null) {
            // 이미 떠 있으면 업데이트만
            updateOverlay(iconType, distText)
            return
        }

        val wm = getSystemService(WINDOW_SERVICE) as WindowManager
        windowManager = wm

        val view = LayoutInflater.from(this)
            .inflate(R.layout.floating_nav, null)

        val iconName = drawableNameForIconType(iconType)
        val iconResId = resources.getIdentifier(iconName, "drawable", packageName)
        if (iconResId != 0) {
            view.findViewById<ImageView>(R.id.nav_icon)?.setImageResource(iconResId)
        }
        view.findViewById<TextView>(R.id.nav_dist)?.text = distText

        // 아이콘 탭 → 앱 포그라운드 복귀
        view.setOnClickListener {
            val launchIntent = (packageManager.getLaunchIntentForPackage(packageName)
                ?: Intent(this, MainActivity::class.java)).apply {
                flags = Intent.FLAG_ACTIVITY_NEW_TASK or
                        Intent.FLAG_ACTIVITY_SINGLE_TOP or
                        Intent.FLAG_ACTIVITY_CLEAR_TOP
            }
            startActivity(launchIntent)
        }

        val sizePx = (72 * resources.displayMetrics.density).toInt()
        val type = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            WindowManager.LayoutParams.TYPE_APPLICATION_OVERLAY
        } else {
            @Suppress("DEPRECATION")
            WindowManager.LayoutParams.TYPE_PHONE
        }
        val params = WindowManager.LayoutParams(
            sizePx,
            sizePx,
            type,
            WindowManager.LayoutParams.FLAG_NOT_FOCUSABLE or
                    WindowManager.LayoutParams.FLAG_LAYOUT_IN_SCREEN,
            PixelFormat.TRANSLUCENT
        ).apply {
            gravity = Gravity.BOTTOM or Gravity.END
            x = (16 * resources.displayMetrics.density).toInt()
            y = (80 * resources.displayMetrics.density).toInt()
        }

        overlayView = view
        wm.addView(view, params)
    }

    private fun updateOverlay(iconType: String, distText: String) {
        val view = overlayView ?: run {
            showOverlay(iconType, distText)
            return
        }
        val iconName = drawableNameForIconType(iconType)
        val iconResId = resources.getIdentifier(iconName, "drawable", packageName)
        if (iconResId != 0) {
            view.findViewById<ImageView>(R.id.nav_icon)?.setImageResource(iconResId)
        }
        view.findViewById<TextView>(R.id.nav_dist)?.text = distText
    }

    private fun hideOverlay() {
        overlayView?.let { v ->
            try {
                windowManager?.removeView(v)
            } catch (_: Exception) { /* view가 이미 분리됐으면 무시 */ }
        }
        overlayView = null
    }
}
