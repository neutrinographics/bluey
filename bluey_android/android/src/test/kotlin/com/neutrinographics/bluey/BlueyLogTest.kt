package com.neutrinographics.bluey

import io.mockk.every
import io.mockk.mockk
import io.mockk.slot
import io.mockk.unmockkAll
import io.mockk.verify
import org.junit.After
import org.junit.Assert.assertEquals
import org.junit.Before
import org.junit.Test

/** Unit tests for [BlueyLog] singleton. */
class BlueyLogTest {

    private lateinit var mockFlutterApi: BlueyFlutterApi

    @Before
    fun setUp() {
        BlueyLog.resetForTest()
        mockFlutterApi = mockk(relaxed = true)
    }

    @After
    fun tearDown() {
        BlueyLog.resetForTest()
        unmockkAll()
    }

    @Test
    fun `log emits via flutterApi onLog when level is met`() {
        BlueyLog.bind(mockFlutterApi)
        BlueyLog.setLevel(LogLevelDto.INFO)

        val captured = slot<LogEventDto>()
        every { mockFlutterApi.onLog(capture(captured), any()) } answers { }

        BlueyLog.log(
            LogLevelDto.INFO,
            "bluey.android.test",
            "hello",
            data = mapOf("k" to "v"),
            errorCode = "E1",
        )

        verify(exactly = 1) { mockFlutterApi.onLog(any(), any()) }
        assertEquals("bluey.android.test", captured.captured.context)
        assertEquals(LogLevelDto.INFO, captured.captured.level)
        assertEquals("hello", captured.captured.message)
        assertEquals("v", captured.captured.data["k"])
        assertEquals("E1", captured.captured.errorCode)
    }

    @Test
    fun `log does NOT emit when level is filtered`() {
        BlueyLog.bind(mockFlutterApi)
        BlueyLog.setLevel(LogLevelDto.INFO)

        BlueyLog.log(LogLevelDto.TRACE, "bluey.android.test", "filtered")
        BlueyLog.log(LogLevelDto.DEBUG, "bluey.android.test", "filtered")

        verify(exactly = 0) { mockFlutterApi.onLog(any(), any()) }
    }

    @Test
    fun `setLevel updates the threshold`() {
        BlueyLog.bind(mockFlutterApi)

        BlueyLog.setLevel(LogLevelDto.WARN)
        BlueyLog.log(LogLevelDto.INFO, "ctx", "info-suppressed")
        verify(exactly = 0) { mockFlutterApi.onLog(any(), any()) }

        BlueyLog.log(LogLevelDto.WARN, "ctx", "warn-emitted")
        verify(exactly = 1) { mockFlutterApi.onLog(any(), any()) }
    }

    @Test
    fun `with no flutterApi bound silently no-ops the bridge`() {
        // No bind() call.
        BlueyLog.setLevel(LogLevelDto.TRACE)

        // Should not crash.
        BlueyLog.log(LogLevelDto.INFO, "ctx", "early-log")

        // Once bound, subsequent log goes through.
        BlueyLog.bind(mockFlutterApi)
        BlueyLog.log(LogLevelDto.INFO, "ctx", "later-log")
        verify(exactly = 1) { mockFlutterApi.onLog(any(), any()) }
    }
}
