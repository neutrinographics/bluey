package com.neutrinographics.bluey

import android.Manifest
import android.app.Activity
import android.bluetooth.BluetoothAdapter
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.os.Build
import android.provider.Settings
import android.util.Log
import androidx.core.content.ContextCompat
import io.mockk.*
import org.junit.After
import org.junit.Assert.*
import org.junit.Before
import org.junit.Test

class BlueyPluginTest {

    private lateinit var plugin: BlueyPlugin
    private lateinit var mockContext: Context
    private lateinit var mockActivity: Activity
    private lateinit var mockAdapter: BluetoothAdapter

    @Before
    fun setUp() {
        mockkStatic(Log::class)
        every { Log.d(any(), any()) } returns 0
        every { Log.e(any(), any()) } returns 0
        every { Log.e(any(), any(), any()) } returns 0
        every { Log.w(any(), any<String>()) } returns 0

        mockkStatic(ContextCompat::class)
        mockkConstructor(Intent::class)

        plugin = BlueyPlugin()
        mockContext = mockk(relaxed = true)
        mockActivity = mockk(relaxed = true)
        mockAdapter = mockk(relaxed = true)

        setPrivateField(plugin, "context", mockContext)
        setPrivateField(plugin, "activity", mockActivity)
        setPrivateField(plugin, "bluetoothAdapter", mockAdapter)
    }

    @After
    fun tearDown() {
        setSdkVersion(0)
        unmockkAll()
    }

    @Test
    fun `requestEnable on Android 13+ opens Bluetooth settings when adapter is disabled`() {
        setSdkVersion(Build.VERSION_CODES.TIRAMISU)
        every {
            ContextCompat.checkSelfPermission(mockContext, Manifest.permission.BLUETOOTH_CONNECT)
        } returns PackageManager.PERMISSION_GRANTED
        every { mockAdapter.isEnabled } returns false

        var result: Result<Boolean>? = null
        plugin.requestEnable { result = it }

        verify { mockActivity.startActivity(any()) }
        assertFalse(result!!.getOrThrow())
    }

    private fun setPrivateField(obj: Any, name: String, value: Any?) {
        val field = obj.javaClass.getDeclaredField(name)
        field.isAccessible = true
        field.set(obj, value)
    }

    private fun setSdkVersion(version: Int) {
        val sdkIntField = Build.VERSION::class.java.getDeclaredField("SDK_INT")
        val unsafeClass = Class.forName("sun.misc.Unsafe")
        val theUnsafe = unsafeClass.getDeclaredField("theUnsafe")
        theUnsafe.isAccessible = true
        val unsafe = theUnsafe.get(null)
        val staticFieldBase = unsafeClass.getMethod("staticFieldBase", java.lang.reflect.Field::class.java)
        val staticFieldOffset = unsafeClass.getMethod("staticFieldOffset", java.lang.reflect.Field::class.java)
        val putInt = unsafeClass.getMethod("putInt", Any::class.java, Long::class.javaPrimitiveType, Int::class.javaPrimitiveType)
        putInt.invoke(unsafe, staticFieldBase.invoke(unsafe, sdkIntField), staticFieldOffset.invoke(unsafe, sdkIntField) as Long, version)
    }
}
