package com.neutrinographics.bluey

import android.Manifest
import android.app.Activity
import android.bluetooth.BluetoothAdapter
import android.bluetooth.BluetoothDevice
import android.bluetooth.BluetoothGatt
import android.bluetooth.BluetoothGattCallback
import android.bluetooth.BluetoothProfile
import android.content.Context
import android.content.pm.PackageManager
import android.os.Build
import android.os.Handler
import android.os.Looper
import androidx.core.content.ContextCompat

/**
 * ConnectionManager - handles BLE connection operations.
 *
 * Manages GATT connections to BLE peripherals.
 * Follows Single Responsibility Principle.
 */
class ConnectionManager(
    private val context: Context,
    private val bluetoothAdapter: BluetoothAdapter?,
    private val flutterApi: BlueyFlutterApi
) {
    private var activity: Activity? = null
    private val connections = mutableMapOf<String, BluetoothGatt>()
    private val handler = Handler(Looper.getMainLooper())

    fun setActivity(activity: Activity?) {
        this.activity = activity
    }

    fun connect(
        deviceId: String,
        config: ConnectConfigDto,
        callback: (Result<String>) -> Unit
    ) {
        // Check permissions
        if (!hasRequiredPermissions()) {
            callback(Result.failure(SecurityException("Missing required permissions")))
            return
        }

        // Check if already connected
        if (connections.containsKey(deviceId)) {
            callback(Result.success(deviceId))
            return
        }

        // Get Bluetooth device
        val adapter = bluetoothAdapter
        if (adapter == null) {
            callback(Result.failure(IllegalStateException("Bluetooth adapter not available")))
            return
        }

        val device: BluetoothDevice
        try {
            device = adapter.getRemoteDevice(deviceId)
        } catch (e: IllegalArgumentException) {
            callback(Result.failure(IllegalArgumentException("Invalid device address: $deviceId")))
            return
        }

        // Create GATT callback
        val gattCallback = object : BluetoothGattCallback() {
            override fun onConnectionStateChange(gatt: BluetoothGatt, status: Int, newState: Int) {
                when (newState) {
                    BluetoothProfile.STATE_CONNECTING -> {
                        notifyConnectionState(deviceId, ConnectionStateDto.CONNECTING)
                    }

                    BluetoothProfile.STATE_CONNECTED -> {
                        notifyConnectionState(deviceId, ConnectionStateDto.CONNECTED)
                        // Discover services after connection
                        try {
                            gatt.discoverServices()
                        } catch (e: SecurityException) {
                            // Permission revoked
                        }
                    }

                    BluetoothProfile.STATE_DISCONNECTING -> {
                        notifyConnectionState(deviceId, ConnectionStateDto.DISCONNECTING)
                    }

                    BluetoothProfile.STATE_DISCONNECTED -> {
                        notifyConnectionState(deviceId, ConnectionStateDto.DISCONNECTED)
                        // Clean up
                        connections.remove(deviceId)
                        try {
                            gatt.close()
                        } catch (e: Exception) {
                            // Ignore
                        }
                    }
                }
            }

            override fun onServicesDiscovered(gatt: BluetoothGatt, status: Int) {
                if (status == BluetoothGatt.GATT_SUCCESS) {
                    // Services discovered successfully
                    // This is where we'd expose GATT services to Dart
                }
            }

            // TODO: Add more callbacks for characteristic read/write/notify
        }

        // Connect to GATT
        try {
            notifyConnectionState(deviceId, ConnectionStateDto.CONNECTING)

            val gatt = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
                device.connectGatt(context, false, gattCallback, BluetoothDevice.TRANSPORT_LE)
            } else {
                device.connectGatt(context, false, gattCallback)
            }

            if (gatt != null) {
                connections[deviceId] = gatt

                // Set timeout if specified
                config.timeoutMs?.let { timeout ->
                    handler.postDelayed({
                        // If still connecting after timeout, disconnect
                        if (connections.containsKey(deviceId)) {
                            val currentGatt = connections[deviceId]
                            if (currentGatt != null) {
                                try {
                                    currentGatt.disconnect()
                                } catch (e: SecurityException) {
                                    // Permission revoked
                                }
                            }
                        }
                    }, timeout.toLong())
                }

                callback(Result.success(deviceId))
            } else {
                notifyConnectionState(deviceId, ConnectionStateDto.DISCONNECTED)
                callback(Result.failure(IllegalStateException("Failed to create GATT connection")))
            }
        } catch (e: SecurityException) {
            notifyConnectionState(deviceId, ConnectionStateDto.DISCONNECTED)
            callback(Result.failure(e))
        } catch (e: Exception) {
            notifyConnectionState(deviceId, ConnectionStateDto.DISCONNECTED)
            callback(Result.failure(e))
        }
    }

    fun disconnect(deviceId: String, callback: (Result<Unit>) -> Unit) {
        val gatt = connections[deviceId]
        if (gatt == null) {
            callback(Result.success(Unit))
            return
        }

        try {
            notifyConnectionState(deviceId, ConnectionStateDto.DISCONNECTING)
            gatt.disconnect()
            callback(Result.success(Unit))
        } catch (e: SecurityException) {
            callback(Result.failure(e))
        } catch (e: Exception) {
            callback(Result.failure(e))
        }
    }

    fun cleanup() {
        // Disconnect all connections
        val deviceIds = connections.keys.toList()
        for (deviceId in deviceIds) {
            try {
                connections[deviceId]?.disconnect()
            } catch (e: Exception) {
                // Ignore errors during cleanup
            }
        }
        connections.clear()
    }

    private fun notifyConnectionState(deviceId: String, state: ConnectionStateDto) {
        val event = ConnectionStateEventDto(
            deviceId = deviceId,
            state = state
        )
        flutterApi.onConnectionStateChanged(event) {}
    }

    private fun hasRequiredPermissions(): Boolean {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
            // Android 12+
            return ContextCompat.checkSelfPermission(
                context,
                Manifest.permission.BLUETOOTH_CONNECT
            ) == PackageManager.PERMISSION_GRANTED
        } else {
            // Android 11 and below - no special permission needed for GATT
            return true
        }
    }
}
