package com.neutrinographics.bluey

import android.Manifest
import android.app.Activity
import android.bluetooth.BluetoothAdapter
import android.bluetooth.le.AdvertiseCallback
import android.bluetooth.le.AdvertiseData
import android.bluetooth.le.AdvertiseSettings
import android.bluetooth.le.BluetoothLeAdvertiser
import android.content.Context
import android.content.pm.PackageManager
import android.os.Build
import android.os.Handler
import android.os.Looper
import android.os.ParcelUuid
import androidx.core.content.ContextCompat
import android.util.Log
import java.util.UUID

/**
 * Advertiser - handles BLE advertising operations.
 *
 * Manages BLE advertising to make the device discoverable as a peripheral.
 * Follows Single Responsibility Principle.
 */
class Advertiser(
    private val context: Context,
    private val bluetoothAdapter: BluetoothAdapter?
) {
    private var activity: Activity? = null
    private var advertiser: BluetoothLeAdvertiser? = null
    private var advertiseCallback: AdvertiseCallback? = null
    private var isAdvertising = false
    private val handler = Handler(Looper.getMainLooper())
    private var timeoutRunnable: Runnable? = null

    fun setActivity(activity: Activity?) {
        this.activity = activity
    }

    fun startAdvertising(config: AdvertiseConfigDto, callback: (Result<Unit>) -> Unit) {
        if (!hasRequiredPermissions()) {
            callback(Result.failure(SecurityException("Missing required permissions: BLUETOOTH_ADVERTISE")))
            return
        }

        if (isAdvertising) {
            callback(Result.success(Unit))
            return
        }

        val adapter = bluetoothAdapter
        if (adapter == null) {
            callback(Result.failure(IllegalStateException("Bluetooth adapter not available")))
            return
        }

        advertiser = adapter.bluetoothLeAdvertiser
        if (advertiser == null) {
            callback(Result.failure(IllegalStateException("BLE advertising not supported")))
            return
        }

        // Build advertise settings
        val settingsBuilder = AdvertiseSettings.Builder()
            .setAdvertiseMode(AdvertiseSettings.ADVERTISE_MODE_LOW_LATENCY) // More frequent advertising
            .setTxPowerLevel(AdvertiseSettings.ADVERTISE_TX_POWER_HIGH) // Higher power for better visibility
            .setConnectable(true)

        config.timeoutMs?.let { timeout ->
            // Android timeout is in milliseconds, max 180000 (3 minutes)
            val androidTimeout = (timeout / 1000).coerceIn(0, 180).toInt()
            settingsBuilder.setTimeout(androidTimeout * 1000)
        }

        val settings = settingsBuilder.build()

        // Build advertise data - keep it minimal, put service UUIDs here
        val dataBuilder = AdvertiseData.Builder()
            .setIncludeDeviceName(false) // Don't include name in main packet to save space

        // Add service UUIDs to main advertise data
        for (uuidString in config.serviceUuids) {
            try {
                val uuid = UUID.fromString(normalizeUuid(uuidString))
                dataBuilder.addServiceUuid(ParcelUuid(uuid))
            } catch (e: IllegalArgumentException) {
                // Invalid UUID, skip
            }
        }

        // Add manufacturer data
        config.manufacturerDataCompanyId?.let { companyId ->
            config.manufacturerData?.let { data ->
                dataBuilder.addManufacturerData(companyId.toInt(), data)
            }
        }

        val advertiseData = dataBuilder.build()

        // Build scan response - put device name here
        val scanResponseBuilder = AdvertiseData.Builder()
            .setIncludeDeviceName(config.name != null)

        val scanResponse = scanResponseBuilder.build()

        // Create callback
        advertiseCallback = object : AdvertiseCallback() {
            override fun onStartSuccess(settingsInEffect: AdvertiseSettings?) {
                Log.d("Advertiser", "Advertising started successfully. Settings: $settingsInEffect")
                Log.d("Advertiser", "  connectable: ${settingsInEffect?.isConnectable}")
                Log.d("Advertiser", "  mode: ${settingsInEffect?.mode}")
                Log.d("Advertiser", "  txPowerLevel: ${settingsInEffect?.txPowerLevel}")
                isAdvertising = true
                callback(Result.success(Unit))

                // Set up timeout if specified and not handled by Android
                config.timeoutMs?.let { timeout ->
                    if (timeout > 180000) {
                        // Android max is 180 seconds, handle longer timeouts ourselves
                        timeoutRunnable = Runnable {
                            stopAdvertisingInternal()
                        }
                        handler.postDelayed(timeoutRunnable!!, timeout)
                    }
                }
            }

            override fun onStartFailure(errorCode: Int) {
                isAdvertising = false
                val errorMessage = when (errorCode) {
                    ADVERTISE_FAILED_DATA_TOO_LARGE -> "Advertise data too large"
                    ADVERTISE_FAILED_TOO_MANY_ADVERTISERS -> "Too many advertisers"
                    ADVERTISE_FAILED_ALREADY_STARTED -> "Already started"
                    ADVERTISE_FAILED_INTERNAL_ERROR -> "Internal error"
                    ADVERTISE_FAILED_FEATURE_UNSUPPORTED -> "Feature unsupported"
                    else -> "Unknown error: $errorCode"
                }
                callback(Result.failure(IllegalStateException(errorMessage)))
            }
        }

        try {
            advertiser?.startAdvertising(settings, advertiseData, scanResponse, advertiseCallback)
        } catch (e: SecurityException) {
            callback(Result.failure(e))
        }
    }

    fun stopAdvertising(callback: (Result<Unit>) -> Unit) {
        stopAdvertisingInternal()
        callback(Result.success(Unit))
    }

    fun cleanup() {
        Log.d("Advertiser", "cleanup() called, isAdvertising=$isAdvertising")
        stopAdvertisingInternal()
    }

    private fun stopAdvertisingInternal() {
        // Cancel timeout
        timeoutRunnable?.let { handler.removeCallbacks(it) }
        timeoutRunnable = null

        if (!isAdvertising) {
            Log.d("Advertiser", "stopAdvertisingInternal: not advertising, skipping")
            return
        }

        advertiseCallback?.let { cb ->
            try {
                Log.d("Advertiser", "stopAdvertisingInternal: stopping advertising")
                advertiser?.stopAdvertising(cb)
            } catch (e: SecurityException) {
                Log.e("Advertiser", "stopAdvertisingInternal: SecurityException", e)
            }
        }

        isAdvertising = false
        advertiseCallback = null
        Log.d("Advertiser", "stopAdvertisingInternal: advertising stopped")
    }

    private fun normalizeUuid(uuid: String): String {
        return if (uuid.length == 4) {
            "0000$uuid-0000-1000-8000-00805f9b34fb"
        } else {
            uuid
        }
    }

    private fun hasRequiredPermissions(): Boolean {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
            return ContextCompat.checkSelfPermission(
                context,
                Manifest.permission.BLUETOOTH_ADVERTISE
            ) == PackageManager.PERMISSION_GRANTED
        }
        return true
    }
}
