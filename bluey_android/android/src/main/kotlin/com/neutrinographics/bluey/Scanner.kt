package com.neutrinographics.bluey

import android.Manifest
import android.app.Activity
import android.bluetooth.BluetoothAdapter
import android.bluetooth.le.BluetoothLeScanner
import android.bluetooth.le.ScanCallback
import android.bluetooth.le.ScanFilter
import android.bluetooth.le.ScanResult
import android.bluetooth.le.ScanSettings
import android.content.Context
import android.content.pm.PackageManager
import android.os.Build
import android.os.Handler
import android.os.Looper
import android.os.ParcelUuid
import androidx.core.content.ContextCompat
import java.util.UUID

/**
 * Scanner - handles BLE scanning operations.
 *
 * This is a domain component that encapsulates BLE scanning logic.
 * Follows Single Responsibility Principle.
 */
class Scanner(
    private val context: Context,
    private val bluetoothAdapter: BluetoothAdapter?,
    private val flutterApi: BlueyFlutterApi
) {
    private var activity: Activity? = null
    private var bleScanner: BluetoothLeScanner? = null
    private var scanCallback: ScanCallback? = null
    private val handler = Handler(Looper.getMainLooper())
    private var scanTimeoutRunnable: Runnable? = null

    fun setActivity(activity: Activity?) {
        this.activity = activity
    }

    fun startScan(config: ScanConfigDto, callback: (Result<Unit>) -> Unit) {
        // Check permissions
        if (!hasRequiredPermissions()) {
            callback(Result.failure(BlueyAndroidError.PermissionDenied("BLUETOOTH_SCAN")))
            return
        }

        // Check Bluetooth state
        val adapter = bluetoothAdapter
        if (adapter == null || !adapter.isEnabled) {
            callback(Result.failure(BlueyAndroidError.BluetoothNotAvailableOrDisabled))
            return
        }

        // Stop any existing scan
        stopScanInternal()

        // Get BLE scanner
        bleScanner = adapter.bluetoothLeScanner
        if (bleScanner == null) {
            callback(Result.failure(BlueyAndroidError.BleScannerNotAvailable))
            return
        }

        // Build scan filters
        val filters = buildScanFilters(config)

        // Build scan settings
        val settings = ScanSettings.Builder()
            .setScanMode(ScanSettings.SCAN_MODE_LOW_LATENCY)
            .build()

        // Create callback
        scanCallback = object : ScanCallback() {
            override fun onScanResult(callbackType: Int, result: ScanResult) {
                handleScanResult(result)
            }

            override fun onBatchScanResults(results: List<ScanResult>) {
                results.forEach { handleScanResult(it) }
            }

            override fun onScanFailed(errorCode: Int) {
                // Must dispatch to main thread for Flutter platform channel
                handler.post {
                    flutterApi.onScanComplete {}
                }
            }
        }

        // Start scanning
        try {
            bleScanner?.startScan(filters, settings, scanCallback)

            // Set timeout if specified
            config.timeoutMs?.let { timeout ->
                scanTimeoutRunnable = Runnable {
                    stopScanInternal()
                    // Already on main thread via handler
                    flutterApi.onScanComplete {}
                }
                handler.postDelayed(scanTimeoutRunnable!!, timeout.toLong())
            }

            callback(Result.success(Unit))
        } catch (e: SecurityException) {
            callback(Result.failure(e))
        } catch (e: Exception) {
            callback(Result.failure(e))
        }
    }

    fun stopScan(callback: (Result<Unit>) -> Unit) {
        stopScanInternal()
        // Already on main thread when called from plugin
        flutterApi.onScanComplete {}
        callback(Result.success(Unit))
    }

    fun cleanup() {
        stopScanInternal()
    }

    private fun stopScanInternal() {
        scanTimeoutRunnable?.let { handler.removeCallbacks(it) }
        scanTimeoutRunnable = null

        try {
            scanCallback?.let { bleScanner?.stopScan(it) }
        } catch (e: SecurityException) {
            // Permission was revoked, ignore
        } catch (e: Exception) {
            // Ignore errors during cleanup
        }

        scanCallback = null
    }

    private fun buildScanFilters(config: ScanConfigDto): List<ScanFilter> {
        val filters = mutableListOf<ScanFilter>()

        // Add service UUID filters
        for (uuidString in config.serviceUuids) {
            try {
                val uuid = UUID.fromString(normalizeUuid(uuidString))
                val filter = ScanFilter.Builder()
                    .setServiceUuid(ParcelUuid(uuid))
                    .build()
                filters.add(filter)
            } catch (e: IllegalArgumentException) {
                // Invalid UUID, skip
            }
        }

        return filters
    }

    private fun handleScanResult(result: ScanResult) {
        val device = result.device
        val scanRecord = result.scanRecord

        // Extract service UUIDs
        val serviceUuids = scanRecord?.serviceUuids?.map { it.uuid.toString() } ?: emptyList()

        // Extract manufacturer data (first one if multiple)
        var manufacturerDataCompanyId: Long? = null
        var manufacturerData: List<Long>? = null

        scanRecord?.manufacturerSpecificData?.let { sparseArray ->
            if (sparseArray.size() > 0) {
                val key = sparseArray.keyAt(0)
                val data = sparseArray.get(key)
                manufacturerDataCompanyId = key.toLong()
                manufacturerData = data?.map { it.toLong() }
            }
        }

        // Create device DTO
        // Prefer the advertised local name from the scan record over the
        // cached name from BluetoothDevice, which may be stale or missing.
        val deviceDto = DeviceDto(
            id = device.address,
            name = scanRecord?.deviceName ?: device.name,
            rssi = result.rssi.toLong(),
            serviceUuids = serviceUuids,
            manufacturerDataCompanyId = manufacturerDataCompanyId,
            manufacturerData = manufacturerData
        )

        // Must dispatch to main thread for Flutter platform channel
        handler.post {
            flutterApi.onDeviceDiscovered(deviceDto) {}
        }
    }

    private fun hasRequiredPermissions(): Boolean {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
            // Android 12+
            return ContextCompat.checkSelfPermission(
                context,
                Manifest.permission.BLUETOOTH_SCAN
            ) == PackageManager.PERMISSION_GRANTED
        } else {
            // Android 11 and below
            return ContextCompat.checkSelfPermission(
                context,
                Manifest.permission.ACCESS_FINE_LOCATION
            ) == PackageManager.PERMISSION_GRANTED
        }
    }

    private fun normalizeUuid(uuid: String): String {
        // If it's a short UUID (4 chars), expand to full Bluetooth base UUID
        return if (uuid.length == 4) {
            "0000$uuid-0000-1000-8000-00805f9b34fb"
        } else {
            uuid
        }
    }
}
