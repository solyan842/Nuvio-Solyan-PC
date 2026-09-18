package com.nuvio.app.features.player

import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertTrue

class WindowsPlaybackHeadersTest {
    @Test
    fun `empty headers receive PlayTorrio compatible defaults`() {
        val headers = emptyMap<String, String>().withWindowsPlaybackDefaults()

        assertEquals("keep-alive", headers["Connection"])
        assertEquals("*/*", headers["Accept"])
        assertEquals(SOLYAN_WINDOWS_DEFAULT_USER_AGENT, headers["User-Agent"])
    }

    @Test
    fun `addon headers override defaults case insensitively without duplicates`() {
        val headers = mapOf(
            "user-agent" to "Addon-UA",
            "Referer" to "https://example.invalid/",
        ).withWindowsPlaybackDefaults()

        assertEquals("Addon-UA", headers.entries.single { it.key.equals("User-Agent", ignoreCase = true) }.value)
        assertEquals(1, headers.keys.count { it.equals("User-Agent", ignoreCase = true) })
        assertEquals("https://example.invalid/", headers["Referer"])
        assertTrue(headers.containsKey("Accept"))
        assertTrue(headers.containsKey("Connection"))
    }
}
