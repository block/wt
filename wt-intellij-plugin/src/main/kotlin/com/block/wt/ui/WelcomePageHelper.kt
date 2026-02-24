package com.block.wt.ui

import com.intellij.openapi.editor.colors.EditorColorsManager
import com.intellij.ui.JBColor
import com.intellij.util.ui.JBUI
import com.intellij.util.ui.UIUtil
import java.awt.Color
import java.util.Base64

/**
 * Builds the welcome page HTML with IntelliJ theme colors injected as CSS variables
 * and the screenshot embedded as a base64 data URI.
 */
object WelcomePageHelper {

    fun buildThemedHtml(): String? {
        val template = javaClass.getResource("/welcome.html")?.readText() ?: return null
        val screenshotDataUri = loadScreenshotDataUri()
        val themeStyle = buildThemeStyle()

        return template
            .replace("/*{{THEME_CSS}}*/", themeStyle)
            .replace("{{SCREENSHOT_SRC}}", screenshotDataUri)
    }

    private fun loadScreenshotDataUri(): String {
        val bytes = javaClass.getResourceAsStream("/ui.png")?.readBytes()
            ?: return ""
        val encoded = Base64.getEncoder().encodeToString(bytes)
        return "data:image/png;base64,$encoded"
    }

    private fun buildThemeStyle(): String {
        val scheme = EditorColorsManager.getInstance().globalScheme
        val bg = scheme.defaultBackground
        val fg = scheme.defaultForeground
        val panelBg = UIUtil.getPanelBackground()
        val linkColor = JBUI.CurrentTheme.Link.Foreground.ENABLED
        val separatorColor = JBColor.namedColor("Group.separatorColor", panelBg)
        val infoFg = JBColor.namedColor("Component.infoForeground", fg)

        // Derive surface and accent colors from the theme
        val isDark = ColorUtil.isDark(bg)
        val surface = if (isDark) ColorUtil.brighten(panelBg, 0.06) else Color.WHITE
        val surfaceHover = if (isDark) ColorUtil.brighten(panelBg, 0.10) else ColorUtil.darken(Color.WHITE, 0.02)
        val border = if (isDark) ColorUtil.brighten(panelBg, 0.15) else ColorUtil.darken(Color.WHITE, 0.10)
        val borderStrong = if (isDark) ColorUtil.brighten(panelBg, 0.25) else ColorUtil.darken(Color.WHITE, 0.18)
        val muted = infoFg
        val subtle = if (isDark) ColorUtil.blend(fg, bg, 0.45) else ColorUtil.blend(fg, bg, 0.55)
        val accentBg = if (isDark) ColorUtil.blend(linkColor, bg, 0.15) else ColorUtil.blend(linkColor, Color.WHITE, 0.10)
        val accentBorder = if (isDark) ColorUtil.blend(linkColor, bg, 0.35) else ColorUtil.blend(linkColor, Color.WHITE, 0.30)
        val kbdBg = if (isDark) ColorUtil.brighten(panelBg, 0.04) else ColorUtil.darken(Color.WHITE, 0.04)
        val kbdBorder = borderStrong
        val kbdShadow = if (isDark) ColorUtil.darken(bg, 0.15) else ColorUtil.darken(Color.WHITE, 0.25)
        val placeholderBg = if (isDark) ColorUtil.brighten(bg, 0.04) else ColorUtil.darken(Color.WHITE, 0.03)
        val placeholderBorder = border
        val placeholderFg = subtle

        return """
            :root {
                --bg: ${bg.css()};
                --fg: ${fg.css()};
                --muted: ${muted.css()};
                --subtle: ${subtle.css()};
                --surface: ${surface.css()};
                --surface-hover: ${surfaceHover.css()};
                --border: ${border.css()};
                --border-strong: ${borderStrong.css()};
                --accent: ${linkColor.css()};
                --accent-fg: ${if (isDark) ColorUtil.darken(linkColor, 0.7).css() else "#ffffff"};
                --accent-muted: ${linkColor.css()};
                --accent-bg: ${accentBg.css()};
                --accent-border: ${accentBorder.css()};
                --kbd-bg: ${kbdBg.css()};
                --kbd-border: ${kbdBorder.css()};
                --kbd-shadow: ${kbdShadow.css()};
                --step-num: ${linkColor.css()};
                --placeholder-bg: ${placeholderBg.css()};
                --placeholder-border: ${placeholderBorder.css()};
                --placeholder-fg: ${placeholderFg.css()};
                --diagram-line: ${border.css()};
                --diagram-node: ${linkColor.css()};
                --diagram-node-fg: ${if (isDark) ColorUtil.darken(linkColor, 0.7).css() else "#ffffff"};
                --diagram-arrow: ${subtle.css()};
                --tag-bg: ${accentBg.css()};
                --tag-border: ${accentBorder.css()};
                --tag-fg: ${linkColor.css()};
                --shadow-card: 0 1px 3px ${ColorUtil.withAlpha(Color.BLACK, if (isDark) 0.20 else 0.04)}, 0 1px 2px ${ColorUtil.withAlpha(Color.BLACK, if (isDark) 0.15 else 0.06)};
                --shadow-card-hover: 0 4px 12px ${ColorUtil.withAlpha(Color.BLACK, if (isDark) 0.25 else 0.06)}, 0 2px 4px ${ColorUtil.withAlpha(Color.BLACK, if (isDark) 0.15 else 0.04)};
            }
        """.trimIndent()
    }

    private fun Color.css(): String = "rgb($red, $green, $blue)"
}

private object ColorUtil {
    fun isDark(c: Color): Boolean = (c.red * 0.299 + c.green * 0.587 + c.blue * 0.114) < 128

    fun brighten(c: Color, amount: Double): Color {
        val r = (c.red + (255 - c.red) * amount).toInt().coerceIn(0, 255)
        val g = (c.green + (255 - c.green) * amount).toInt().coerceIn(0, 255)
        val b = (c.blue + (255 - c.blue) * amount).toInt().coerceIn(0, 255)
        return Color(r, g, b)
    }

    fun darken(c: Color, amount: Double): Color {
        val r = (c.red * (1 - amount)).toInt().coerceIn(0, 255)
        val g = (c.green * (1 - amount)).toInt().coerceIn(0, 255)
        val b = (c.blue * (1 - amount)).toInt().coerceIn(0, 255)
        return Color(r, g, b)
    }

    fun blend(c1: Color, c2: Color, ratio: Double): Color {
        val r = (c1.red * ratio + c2.red * (1 - ratio)).toInt().coerceIn(0, 255)
        val g = (c1.green * ratio + c2.green * (1 - ratio)).toInt().coerceIn(0, 255)
        val b = (c1.blue * ratio + c2.blue * (1 - ratio)).toInt().coerceIn(0, 255)
        return Color(r, g, b)
    }

    fun withAlpha(c: Color, alpha: Double): String =
        "rgba(${c.red}, ${c.green}, ${c.blue}, $alpha)"
}
