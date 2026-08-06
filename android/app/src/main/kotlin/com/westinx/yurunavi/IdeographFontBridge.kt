package com.westinx.yurunavi

import android.graphics.Paint
import android.graphics.Typeface
import android.os.Build
import android.util.Xml
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodChannel
import org.xmlpull.v1.XmlPullParser
import java.io.File
import java.io.FileInputStream

/**
 * 한글을 지원하는 시스템 폰트 열거 채널 (O1 청크3, 지도 표의문자 폰트 선택 UI).
 *
 * 배경: `maplibre_gl` 포크(청크2)가 추가한 `localIdeographFontFamily` 옵션은 MapView
 * 생성 시점에 한 번 baked-in되는 네이티브 폰트 패밀리명을 받는다. 사용자가 고를 수
 * 있는 후보 목록이 있어야 하는데, 제조사(OEM)마다 시스템 한글 폰트명이 달라
 * 하드코딩할 수 없다 — `/system/etc/fonts.xml`을 파싱해 `<family name="...">` 후보를
 * 뽑고, 각 이름으로 만든 `Typeface`가 실제로 '한' 글리프를 그릴 수 있는지
 * (`Paint.hasGlyph`, API 23+)로 걸러낸다.
 *
 * `fonts.xml`의 존재 여부/포맷은 OEM·OS 버전마다 다르다(설계 문서
 * `RECON_0806_O1_asset_localization_design.md` §0-B 참고). 파싱 중 어떤 예외가
 * 나든 앱을 죽이면 안 되므로 전부 try/catch로 감싸고 실패 시 빈 리스트로 폴백한다.
 */
class IdeographFontBridge(messenger: BinaryMessenger) {

    companion object {
        private const val CHANNEL = "com.westinx.yurunavi/ideograph_fonts"
        private const val FONTS_XML_PATH = "/system/etc/fonts.xml"
        private const val KOREAN_PROBE_CHAR = "한"
    }

    init {
        MethodChannel(messenger, CHANNEL).setMethodCallHandler { call, result ->
            if (call.method == "listKoreanFonts") {
                result.success(listKoreanFonts())
            } else {
                result.notImplemented()
            }
        }
    }

    /** 실패해도 예외를 던지지 않는다 — 최악의 경우 빈 리스트를 반환한다. */
    private fun listKoreanFonts(): List<String> {
        return try {
            val candidates = parseFontFamilyNames()
            if (candidates.isEmpty()) return emptyList()
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
                candidates.filter { supportsKoreanGlyph(it) }
            } else {
                // hasGlyph API가 없는 구버전 — 글리프 검증 없이 후보를 그대로 반환하면
                // 한글을 지원하지 않는 폰트가 섞일 위험이 있으므로 빈 목록으로 안전하게 폴백.
                emptyList()
            }
        } catch (e: Exception) {
            emptyList()
        }
    }

    /** `/system/etc/fonts.xml`에서 이름 있는 `<family>` 후보만 뽑는다. */
    private fun parseFontFamilyNames(): List<String> {
        val file = File(FONTS_XML_PATH)
        if (!file.exists()) return emptyList()
        val names = mutableListOf<String>()
        try {
            FileInputStream(file).use { input ->
                val parser: XmlPullParser = Xml.newPullParser()
                parser.setInput(input, null)
                var eventType = parser.eventType
                while (eventType != XmlPullParser.END_DOCUMENT) {
                    if (eventType == XmlPullParser.START_TAG && parser.name == "family") {
                        val name = parser.getAttributeValue(null, "name")
                        // 이름 없는 family는 fallback-only 항목(특정 폰트로 지정 불가) — 건너뛴다.
                        if (!name.isNullOrBlank()) names.add(name)
                    }
                    eventType = parser.next()
                }
            }
        } catch (e: Exception) {
            return emptyList()
        }
        return names
    }

    private fun supportsKoreanGlyph(fontFamily: String): Boolean {
        return try {
            val typeface = Typeface.create(fontFamily, Typeface.NORMAL)
            val paint = Paint().apply { this.typeface = typeface }
            paint.hasGlyph(KOREAN_PROBE_CHAR)
        } catch (e: Exception) {
            false
        }
    }
}
