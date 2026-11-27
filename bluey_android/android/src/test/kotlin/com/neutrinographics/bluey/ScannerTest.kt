package com.neutrinographics.bluey

import android.content.Context
import android.os.Handler
import android.os.Looper
import io.mockk.*
import org.junit.After
import org.junit.Before
import org.junit.Test

/**
 * Unit tests for Scanner.
 *
 * A refused scan must reach Dart as its error code, not as a completed scan.
 */
class ScannerTest {

    private lateinit var mockFlutterApi: BlueyFlutterApi
    private lateinit var scanner: Scanner

    @Before
    fun setUp() {
        mockkStatic(Looper::class)
        every { Looper.getMainLooper() } returns mockk<Looper>(relaxed = true)

        mockkConstructor(Handler::class)
        every { anyConstructed<Handler>().post(any()) } answers {
            firstArg<Runnable>().run()
            true
        }

        mockFlutterApi = mockk(relaxed = true)
        scanner = Scanner(mockk<Context>(relaxed = true), null, mockFlutterApi)
    }

    @After
    fun tearDown() {
        clearAllMocks()
        unmockkAll()
    }

    @Test
    fun `a refused scan forwards the platform error code to Dart`() {
        // arrange
        val refusedAsRegistrationFailed = 2

        // act
        scanner.reportScanFailure(refusedAsRegistrationFailed)

        // assert
        verify(exactly = 1) { mockFlutterApi.onScanFailed(2L, any()) }
    }

    @Test
    fun `a failure from a scan another scan replaced is not reported`() {
        // arrange
        val replaced = mockk<android.bluetooth.le.ScanCallback>(relaxed = true)

        // act
        scanner.reportScanFailure(2, from = replaced)

        // assert
        verify(exactly = 0) { mockFlutterApi.onScanFailed(any(), any()) }
    }

    @Test
    fun `a refused scan does not report the scan as complete`() {
        // arrange
        val refusedAsInternalError = 3

        // act
        scanner.reportScanFailure(refusedAsInternalError)

        // assert
        verify(exactly = 0) { mockFlutterApi.onScanComplete(any()) }
    }
}
