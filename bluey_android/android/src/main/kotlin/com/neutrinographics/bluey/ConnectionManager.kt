package com.neutrinographics.bluey

import android.Manifest
import android.app.Activity
import android.bluetooth.BluetoothAdapter
import android.bluetooth.BluetoothDevice
import android.bluetooth.BluetoothGatt
import android.bluetooth.BluetoothGattCallback
import android.bluetooth.BluetoothGattCharacteristic
import android.bluetooth.BluetoothGattDescriptor
import android.bluetooth.BluetoothGattService
import android.bluetooth.BluetoothProfile
import android.content.Context
import android.content.pm.PackageManager
import android.os.Build
import android.os.Handler
import android.os.Looper
import androidx.core.content.ContextCompat
import java.util.UUID

/**
 * ConnectionManager - handles BLE connection and GATT operations.
 *
 * Manages GATT connections to BLE peripherals including service discovery,
 * characteristic read/write, notifications, and MTU negotiation.
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

    // Pending operation callbacks - GATT operations are async
    private val pendingConnections = mutableMapOf<String, (Result<String>) -> Unit>()
    private val pendingServiceDiscovery = mutableMapOf<String, (Result<List<ServiceDto>>) -> Unit>()
    private val pendingReads = mutableMapOf<String, (Result<ByteArray>) -> Unit>()
    private val pendingWrites = mutableMapOf<String, (Result<Unit>) -> Unit>()
    private val pendingDescriptorReads = mutableMapOf<String, (Result<ByteArray>) -> Unit>()
    private val pendingDescriptorWrites = mutableMapOf<String, (Result<Unit>) -> Unit>()
    private val pendingMtuRequests = mutableMapOf<String, (Result<Long>) -> Unit>()
    private val pendingRssiReads = mutableMapOf<String, (Result<Long>) -> Unit>()

    // Pending timeout Runnables — kept alongside each callback map so that a
    // completed operation's timer can be cancelled. Without this, a stale
    // timer from a finished operation will fire and cancel a newer
    // operation that reuses the same key (e.g. same characteristic).
    private val pendingConnectionTimeouts = mutableMapOf<String, Runnable>()
    private val pendingServiceDiscoveryTimeouts = mutableMapOf<String, Runnable>()
    private val pendingReadTimeouts = mutableMapOf<String, Runnable>()
    private val pendingWriteTimeouts = mutableMapOf<String, Runnable>()
    private val pendingDescriptorReadTimeouts = mutableMapOf<String, Runnable>()
    private val pendingDescriptorWriteTimeouts = mutableMapOf<String, Runnable>()
    private val pendingMtuTimeouts = mutableMapOf<String, Runnable>()
    private val pendingRssiTimeouts = mutableMapOf<String, Runnable>()

    // CCCD UUID for enabling notifications/indications
    companion object {
        private val CCCD_UUID = UUID.fromString("00002902-0000-1000-8000-00805f9b34fb")
    }

    // Configurable timeout values — set via configure(), defaults match previous hardcoded values
    private var discoverServicesTimeoutMs = 15_000L
    private var readCharacteristicTimeoutMs = 10_000L
    private var writeCharacteristicTimeoutMs = 10_000L
    private var readDescriptorTimeoutMs = 10_000L
    private var writeDescriptorTimeoutMs = 10_000L
    private var requestMtuTimeoutMs = 10_000L
    private var readRssiTimeoutMs = 5_000L

    fun configure(config: BlueyConfigDto) {
        config.discoverServicesTimeoutMs?.let { discoverServicesTimeoutMs = it }
        config.readCharacteristicTimeoutMs?.let { readCharacteristicTimeoutMs = it }
        config.writeCharacteristicTimeoutMs?.let { writeCharacteristicTimeoutMs = it }
        config.readDescriptorTimeoutMs?.let { readDescriptorTimeoutMs = it }
        config.writeDescriptorTimeoutMs?.let { writeDescriptorTimeoutMs = it }
        config.requestMtuTimeoutMs?.let { requestMtuTimeoutMs = it }
        config.readRssiTimeoutMs?.let { readRssiTimeoutMs = it }
    }

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
        val gattCallback = createGattCallback(deviceId)

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
                // Store callback to be called when connection is established
                pendingConnections[deviceId] = callback

                // Set timeout if specified
                config.timeoutMs?.let { timeout ->
                    val timeoutRunnable = Runnable {
                        pendingConnectionTimeouts.remove(deviceId)
                        // If still connecting after timeout, fail the connection
                        val pendingCallback = pendingConnections.remove(deviceId)
                        if (pendingCallback != null) {
                            val currentGatt = connections.remove(deviceId)
                            if (currentGatt != null) {
                                try {
                                    currentGatt.disconnect()
                                    currentGatt.close()
                                } catch (e: SecurityException) {
                                    // Permission revoked
                                }
                            }
                            notifyConnectionState(deviceId, ConnectionStateDto.DISCONNECTED)
                            pendingCallback(Result.failure(IllegalStateException("Connection timeout")))
                        }
                    }
                    pendingConnectionTimeouts[deviceId] = timeoutRunnable
                    handler.postDelayed(timeoutRunnable, timeout)
                }
                // Don't call callback here - wait for onConnectionStateChange
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

    fun discoverServices(deviceId: String, callback: (Result<List<ServiceDto>>) -> Unit) {
        val gatt = connections[deviceId]
        if (gatt == null) {
            callback(Result.failure(IllegalStateException("Device not connected: $deviceId")))
            return
        }

        // Check if services already discovered
        val services = gatt.services
        if (services != null && services.isNotEmpty()) {
            callback(Result.success(mapServices(services)))
            return
        }

        // Store callback for async response
        pendingServiceDiscovery[deviceId] = callback

        try {
            if (!gatt.discoverServices()) {
                pendingServiceDiscovery.remove(deviceId)
                callback(Result.failure(IllegalStateException("Failed to start service discovery")))
            } else {
                // Schedule timeout
                val timeoutRunnable = Runnable {
                    pendingServiceDiscoveryTimeouts.remove(deviceId)
                    val pendingCallback = pendingServiceDiscovery.remove(deviceId)
                    pendingCallback?.invoke(Result.failure(IllegalStateException("Service discovery timed out")))
                }
                pendingServiceDiscoveryTimeouts[deviceId] = timeoutRunnable
                handler.postDelayed(timeoutRunnable, discoverServicesTimeoutMs)
            }
        } catch (e: SecurityException) {
            pendingServiceDiscovery.remove(deviceId)
            callback(Result.failure(e))
        }
    }

    fun readCharacteristic(
        deviceId: String,
        characteristicUuid: String,
        callback: (Result<ByteArray>) -> Unit
    ) {
        val gatt = connections[deviceId]
        if (gatt == null) {
            callback(Result.failure(IllegalStateException("Device not connected: $deviceId")))
            return
        }

        val characteristic = findCharacteristic(gatt, characteristicUuid)
        if (characteristic == null) {
            callback(Result.failure(IllegalStateException("Characteristic not found: $characteristicUuid")))
            return
        }

        // Store callback for async response
        val key = "$deviceId:$characteristicUuid"
        pendingReads[key] = callback

        try {
            if (!gatt.readCharacteristic(characteristic)) {
                pendingReads.remove(key)
                callback(Result.failure(IllegalStateException("Failed to read characteristic")))
            } else {
                // Schedule timeout
                val timeoutRunnable = Runnable {
                    pendingReadTimeouts.remove(key)
                    val pendingCallback = pendingReads.remove(key)
                    pendingCallback?.invoke(Result.failure(IllegalStateException("Read characteristic timed out")))
                }
                pendingReadTimeouts[key] = timeoutRunnable
                handler.postDelayed(timeoutRunnable, readCharacteristicTimeoutMs)
            }
        } catch (e: SecurityException) {
            pendingReads.remove(key)
            callback(Result.failure(e))
        }
    }

    fun writeCharacteristic(
        deviceId: String,
        characteristicUuid: String,
        value: ByteArray,
        withResponse: Boolean,
        callback: (Result<Unit>) -> Unit
    ) {
        val gatt = connections[deviceId]
        if (gatt == null) {
            callback(Result.failure(IllegalStateException("Device not connected: $deviceId")))
            return
        }

        val characteristic = findCharacteristic(gatt, characteristicUuid)
        if (characteristic == null) {
            callback(Result.failure(IllegalStateException("Characteristic not found: $characteristicUuid")))
            return
        }

        // Store callback for async response
        val key = "$deviceId:$characteristicUuid"
        pendingWrites[key] = callback

        try {
            val writeType = if (withResponse) {
                BluetoothGattCharacteristic.WRITE_TYPE_DEFAULT
            } else {
                BluetoothGattCharacteristic.WRITE_TYPE_NO_RESPONSE
            }

            val success = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
                gatt.writeCharacteristic(characteristic, value, writeType) == BluetoothGatt.GATT_SUCCESS
            } else {
                @Suppress("DEPRECATION")
                characteristic.writeType = writeType
                @Suppress("DEPRECATION")
                characteristic.value = value
                @Suppress("DEPRECATION")
                gatt.writeCharacteristic(characteristic)
            }

            if (!success) {
                pendingWrites.remove(key)
                callback(Result.failure(IllegalStateException("Failed to write characteristic")))
            } else if (withResponse) {
                // Schedule timeout (only for write-with-response)
                val timeoutRunnable = Runnable {
                    pendingWriteTimeouts.remove(key)
                    val pendingCallback = pendingWrites.remove(key)
                    pendingCallback?.invoke(Result.failure(IllegalStateException("Write characteristic timed out")))
                }
                pendingWriteTimeouts[key] = timeoutRunnable
                handler.postDelayed(timeoutRunnable, writeCharacteristicTimeoutMs)
            }
        } catch (e: SecurityException) {
            pendingWrites.remove(key)
            callback(Result.failure(e))
        }
    }

    fun setNotification(
        deviceId: String,
        characteristicUuid: String,
        enable: Boolean,
        callback: (Result<Unit>) -> Unit
    ) {
        val gatt = connections[deviceId]
        if (gatt == null) {
            callback(Result.failure(IllegalStateException("Device not connected: $deviceId")))
            return
        }

        val characteristic = findCharacteristic(gatt, characteristicUuid)
        if (characteristic == null) {
            callback(Result.failure(IllegalStateException("Characteristic not found: $characteristicUuid")))
            return
        }

        try {
            // Enable local notifications
            if (!gatt.setCharacteristicNotification(characteristic, enable)) {
                callback(Result.failure(IllegalStateException("Failed to set notification")))
                return
            }

            // Write to CCCD to enable remote notifications
            val cccd = characteristic.getDescriptor(CCCD_UUID)
            if (cccd == null) {
                // Some characteristics don't have CCCD, that's OK
                callback(Result.success(Unit))
                return
            }

            val cccdValue = when {
                !enable -> BluetoothGattDescriptor.DISABLE_NOTIFICATION_VALUE
                (characteristic.properties and BluetoothGattCharacteristic.PROPERTY_INDICATE) != 0 ->
                    BluetoothGattDescriptor.ENABLE_INDICATION_VALUE

                else -> BluetoothGattDescriptor.ENABLE_NOTIFICATION_VALUE
            }

            // Store callback for async response
            val key = "$deviceId:${CCCD_UUID}"
            pendingDescriptorWrites[key] = callback

            val success = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
                gatt.writeDescriptor(cccd, cccdValue) == BluetoothGatt.GATT_SUCCESS
            } else {
                @Suppress("DEPRECATION")
                cccd.value = cccdValue
                @Suppress("DEPRECATION")
                gatt.writeDescriptor(cccd)
            }

            if (!success) {
                pendingDescriptorWrites.remove(key)
                callback(Result.failure(IllegalStateException("Failed to write CCCD")))
            }
        } catch (e: SecurityException) {
            callback(Result.failure(e))
        }
    }

    fun readDescriptor(
        deviceId: String,
        descriptorUuid: String,
        callback: (Result<ByteArray>) -> Unit
    ) {
        val gatt = connections[deviceId]
        if (gatt == null) {
            callback(Result.failure(IllegalStateException("Device not connected: $deviceId")))
            return
        }

        val descriptor = findDescriptor(gatt, descriptorUuid)
        if (descriptor == null) {
            callback(Result.failure(IllegalStateException("Descriptor not found: $descriptorUuid")))
            return
        }

        val key = "$deviceId:$descriptorUuid"
        pendingDescriptorReads[key] = callback

        try {
            if (!gatt.readDescriptor(descriptor)) {
                pendingDescriptorReads.remove(key)
                callback(Result.failure(IllegalStateException("Failed to read descriptor")))
            } else {
                // Schedule timeout
                val timeoutRunnable = Runnable {
                    pendingDescriptorReadTimeouts.remove(key)
                    val pendingCallback = pendingDescriptorReads.remove(key)
                    pendingCallback?.invoke(Result.failure(IllegalStateException("Read descriptor timed out")))
                }
                pendingDescriptorReadTimeouts[key] = timeoutRunnable
                handler.postDelayed(timeoutRunnable, readDescriptorTimeoutMs)
            }
        } catch (e: SecurityException) {
            pendingDescriptorReads.remove(key)
            callback(Result.failure(e))
        }
    }

    fun writeDescriptor(
        deviceId: String,
        descriptorUuid: String,
        value: ByteArray,
        callback: (Result<Unit>) -> Unit
    ) {
        val gatt = connections[deviceId]
        if (gatt == null) {
            callback(Result.failure(IllegalStateException("Device not connected: $deviceId")))
            return
        }

        val descriptor = findDescriptor(gatt, descriptorUuid)
        if (descriptor == null) {
            callback(Result.failure(IllegalStateException("Descriptor not found: $descriptorUuid")))
            return
        }

        val key = "$deviceId:$descriptorUuid"
        pendingDescriptorWrites[key] = callback

        try {
            val success = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
                gatt.writeDescriptor(descriptor, value) == BluetoothGatt.GATT_SUCCESS
            } else {
                @Suppress("DEPRECATION")
                descriptor.value = value
                @Suppress("DEPRECATION")
                gatt.writeDescriptor(descriptor)
            }

            if (!success) {
                pendingDescriptorWrites.remove(key)
                callback(Result.failure(IllegalStateException("Failed to write descriptor")))
            } else {
                // Schedule timeout
                val timeoutRunnable = Runnable {
                    pendingDescriptorWriteTimeouts.remove(key)
                    val pendingCallback = pendingDescriptorWrites.remove(key)
                    pendingCallback?.invoke(Result.failure(IllegalStateException("Write descriptor timed out")))
                }
                pendingDescriptorWriteTimeouts[key] = timeoutRunnable
                handler.postDelayed(timeoutRunnable, writeDescriptorTimeoutMs)
            }
        } catch (e: SecurityException) {
            pendingDescriptorWrites.remove(key)
            callback(Result.failure(e))
        }
    }

    fun requestMtu(deviceId: String, mtu: Long, callback: (Result<Long>) -> Unit) {
        val gatt = connections[deviceId]
        if (gatt == null) {
            callback(Result.failure(IllegalStateException("Device not connected: $deviceId")))
            return
        }

        pendingMtuRequests[deviceId] = callback

        try {
            if (!gatt.requestMtu(mtu.toInt())) {
                pendingMtuRequests.remove(deviceId)
                callback(Result.failure(IllegalStateException("Failed to request MTU")))
            } else {
                // Schedule timeout
                val timeoutRunnable = Runnable {
                    pendingMtuTimeouts.remove(deviceId)
                    val pendingCallback = pendingMtuRequests.remove(deviceId)
                    pendingCallback?.invoke(Result.failure(IllegalStateException("MTU request timed out")))
                }
                pendingMtuTimeouts[deviceId] = timeoutRunnable
                handler.postDelayed(timeoutRunnable, requestMtuTimeoutMs)
            }
        } catch (e: SecurityException) {
            pendingMtuRequests.remove(deviceId)
            callback(Result.failure(e))
        }
    }

    fun readRssi(deviceId: String, callback: (Result<Long>) -> Unit) {
        val gatt = connections[deviceId]
        if (gatt == null) {
            callback(Result.failure(IllegalStateException("Device not connected: $deviceId")))
            return
        }

        pendingRssiReads[deviceId] = callback

        try {
            if (!gatt.readRemoteRssi()) {
                pendingRssiReads.remove(deviceId)
                callback(Result.failure(IllegalStateException("Failed to read RSSI")))
            } else {
                // Schedule timeout
                val timeoutRunnable = Runnable {
                    pendingRssiTimeouts.remove(deviceId)
                    val pendingCallback = pendingRssiReads.remove(deviceId)
                    pendingCallback?.invoke(Result.failure(IllegalStateException("RSSI read timed out")))
                }
                pendingRssiTimeouts[deviceId] = timeoutRunnable
                handler.postDelayed(timeoutRunnable, readRssiTimeoutMs)
            }
        } catch (e: SecurityException) {
            pendingRssiReads.remove(deviceId)
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

        // Cancel all pending timeouts so they cannot fire after cleanup
        pendingConnectionTimeouts.values.forEach { handler.removeCallbacks(it) }
        pendingServiceDiscoveryTimeouts.values.forEach { handler.removeCallbacks(it) }
        pendingReadTimeouts.values.forEach { handler.removeCallbacks(it) }
        pendingWriteTimeouts.values.forEach { handler.removeCallbacks(it) }
        pendingDescriptorReadTimeouts.values.forEach { handler.removeCallbacks(it) }
        pendingDescriptorWriteTimeouts.values.forEach { handler.removeCallbacks(it) }
        pendingMtuTimeouts.values.forEach { handler.removeCallbacks(it) }
        pendingRssiTimeouts.values.forEach { handler.removeCallbacks(it) }
        pendingConnectionTimeouts.clear()
        pendingServiceDiscoveryTimeouts.clear()
        pendingReadTimeouts.clear()
        pendingWriteTimeouts.clear()
        pendingDescriptorReadTimeouts.clear()
        pendingDescriptorWriteTimeouts.clear()
        pendingMtuTimeouts.clear()
        pendingRssiTimeouts.clear()

        // Clear all pending callbacks
        pendingConnections.clear()
        pendingServiceDiscovery.clear()
        pendingReads.clear()
        pendingWrites.clear()
        pendingDescriptorReads.clear()
        pendingDescriptorWrites.clear()
        pendingMtuRequests.clear()
        pendingRssiReads.clear()
    }

    /**
     * Cancels all pending timeout Runnables scheduled for the given device.
     *
     * Called on disconnect so that stale timers from in-flight operations
     * don't fire and corrupt a future operation that happens to reuse the
     * same completion key (same characteristic/descriptor/device).
     */
    private fun cancelAllTimeouts(deviceId: String) {
        pendingConnectionTimeouts.remove(deviceId)?.let { handler.removeCallbacks(it) }
        pendingServiceDiscoveryTimeouts.remove(deviceId)?.let { handler.removeCallbacks(it) }
        pendingMtuTimeouts.remove(deviceId)?.let { handler.removeCallbacks(it) }
        pendingRssiTimeouts.remove(deviceId)?.let { handler.removeCallbacks(it) }

        // Keyed maps: "$deviceId:$uuid" — remove any entries belonging to
        // this device, cancelling each timer before removal.
        val prefix = "$deviceId:"
        cancelTimersWithPrefix(pendingReadTimeouts, prefix)
        cancelTimersWithPrefix(pendingWriteTimeouts, prefix)
        cancelTimersWithPrefix(pendingDescriptorReadTimeouts, prefix)
        cancelTimersWithPrefix(pendingDescriptorWriteTimeouts, prefix)
    }

    private fun cancelTimersWithPrefix(map: MutableMap<String, Runnable>, prefix: String) {
        val keys = map.keys.filter { it.startsWith(prefix) }
        for (key in keys) {
            map.remove(key)?.let { handler.removeCallbacks(it) }
        }
    }

    private fun createGattCallback(deviceId: String): BluetoothGattCallback {
        return object : BluetoothGattCallback() {
            override fun onConnectionStateChange(gatt: BluetoothGatt, status: Int, newState: Int) {
                when (newState) {
                    BluetoothProfile.STATE_CONNECTING -> {
                        notifyConnectionState(deviceId, ConnectionStateDto.CONNECTING)
                    }

                    BluetoothProfile.STATE_CONNECTED -> {
                        notifyConnectionState(deviceId, ConnectionStateDto.CONNECTED)
                        // Cancel the pending connect timeout
                        pendingConnectionTimeouts.remove(deviceId)?.let { handler.removeCallbacks(it) }
                        // Connection successful - invoke pending callback on main thread
                        val pendingCallback = pendingConnections.remove(deviceId)
                        if (pendingCallback != null) {
                            handler.post {
                                pendingCallback.invoke(Result.success(deviceId))
                            }
                        }
                    }

                    BluetoothProfile.STATE_DISCONNECTING -> {
                        notifyConnectionState(deviceId, ConnectionStateDto.DISCONNECTING)
                    }

                    BluetoothProfile.STATE_DISCONNECTED -> {
                        notifyConnectionState(deviceId, ConnectionStateDto.DISCONNECTED)
                        // Cancel any pending timeouts for this device so stale
                        // timers cannot fire against a future operation.
                        cancelAllTimeouts(deviceId)
                        // Connection failed or disconnected - invoke pending callback with error if present
                        val pendingCallback = pendingConnections.remove(deviceId)
                        if (pendingCallback != null) {
                            val errorMessage = if (status != BluetoothGatt.GATT_SUCCESS) {
                                "Connection failed with status: $status"
                            } else {
                                "Connection failed"
                            }
                            handler.post {
                                pendingCallback.invoke(Result.failure(IllegalStateException(errorMessage)))
                            }
                        }
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
                // Cancel the pending timeout since discovery resolved
                pendingServiceDiscoveryTimeouts.remove(deviceId)?.let { handler.removeCallbacks(it) }
                val callback = pendingServiceDiscovery.remove(deviceId)
                if (callback != null) {
                    val result = if (status == BluetoothGatt.GATT_SUCCESS) {
                        Result.success(mapServices(gatt.services))
                    } else {
                        Result.failure(IllegalStateException("Service discovery failed with status: $status"))
                    }
                    handler.post { callback(result) }
                }
            }

            override fun onCharacteristicRead(
                gatt: BluetoothGatt,
                characteristic: BluetoothGattCharacteristic,
                value: ByteArray,
                status: Int
            ) {
                val key = "$deviceId:${characteristic.uuid}"
                // Cancel the pending timeout since the read resolved
                pendingReadTimeouts.remove(key)?.let { handler.removeCallbacks(it) }
                val callback = pendingReads.remove(key)
                if (callback != null) {
                    val result = if (status == BluetoothGatt.GATT_SUCCESS) {
                        Result.success(value)
                    } else {
                        Result.failure(IllegalStateException("Read failed with status: $status"))
                    }
                    handler.post { callback(result) }
                }
            }

            @Deprecated("Deprecated in Java")
            @Suppress("DEPRECATION")
            override fun onCharacteristicRead(
                gatt: BluetoothGatt,
                characteristic: BluetoothGattCharacteristic,
                status: Int
            ) {
                val key = "$deviceId:${characteristic.uuid}"
                // Cancel the pending timeout since the read resolved
                pendingReadTimeouts.remove(key)?.let { handler.removeCallbacks(it) }
                val callback = pendingReads.remove(key)
                if (callback != null) {
                    val result = if (status == BluetoothGatt.GATT_SUCCESS) {
                        Result.success(characteristic.value ?: ByteArray(0))
                    } else {
                        Result.failure(IllegalStateException("Read failed with status: $status"))
                    }
                    handler.post { callback(result) }
                }
            }

            override fun onCharacteristicWrite(
                gatt: BluetoothGatt,
                characteristic: BluetoothGattCharacteristic,
                status: Int
            ) {
                val key = "$deviceId:${characteristic.uuid}"
                // Cancel the pending timeout since the write resolved
                pendingWriteTimeouts.remove(key)?.let { handler.removeCallbacks(it) }
                val callback = pendingWrites.remove(key)
                if (callback != null) {
                    val result = if (status == BluetoothGatt.GATT_SUCCESS) {
                        Result.success(Unit)
                    } else {
                        Result.failure(IllegalStateException("Write failed with status: $status"))
                    }
                    handler.post { callback(result) }
                }
            }

            override fun onCharacteristicChanged(
                gatt: BluetoothGatt,
                characteristic: BluetoothGattCharacteristic,
                value: ByteArray
            ) {
                val event = NotificationEventDto(
                    deviceId = deviceId,
                    characteristicUuid = characteristic.uuid.toString(),
                    value = value
                )
                // Must dispatch to main thread for Flutter platform channel
                handler.post {
                    flutterApi.onNotification(event) {}
                }
            }

            @Deprecated("Deprecated in Java")
            @Suppress("DEPRECATION")
            override fun onCharacteristicChanged(
                gatt: BluetoothGatt,
                characteristic: BluetoothGattCharacteristic
            ) {
                val event = NotificationEventDto(
                    deviceId = deviceId,
                    characteristicUuid = characteristic.uuid.toString(),
                    value = characteristic.value ?: ByteArray(0)
                )
                // Must dispatch to main thread for Flutter platform channel
                handler.post {
                    flutterApi.onNotification(event) {}
                }
            }

            override fun onDescriptorRead(
                gatt: BluetoothGatt,
                descriptor: BluetoothGattDescriptor,
                status: Int,
                value: ByteArray
            ) {
                val key = "$deviceId:${descriptor.uuid}"
                // Cancel the pending timeout since the read resolved
                pendingDescriptorReadTimeouts.remove(key)?.let { handler.removeCallbacks(it) }
                val callback = pendingDescriptorReads.remove(key)
                if (callback != null) {
                    val result = if (status == BluetoothGatt.GATT_SUCCESS) {
                        Result.success(value)
                    } else {
                        Result.failure(IllegalStateException("Descriptor read failed with status: $status"))
                    }
                    handler.post { callback(result) }
                }
            }

            @Deprecated("Deprecated in Java")
            @Suppress("DEPRECATION")
            override fun onDescriptorRead(
                gatt: BluetoothGatt,
                descriptor: BluetoothGattDescriptor,
                status: Int
            ) {
                val key = "$deviceId:${descriptor.uuid}"
                // Cancel the pending timeout since the read resolved
                pendingDescriptorReadTimeouts.remove(key)?.let { handler.removeCallbacks(it) }
                val callback = pendingDescriptorReads.remove(key)
                if (callback != null) {
                    val result = if (status == BluetoothGatt.GATT_SUCCESS) {
                        Result.success(descriptor.value ?: ByteArray(0))
                    } else {
                        Result.failure(IllegalStateException("Descriptor read failed with status: $status"))
                    }
                    handler.post { callback(result) }
                }
            }

            override fun onDescriptorWrite(
                gatt: BluetoothGatt,
                descriptor: BluetoothGattDescriptor,
                status: Int
            ) {
                val key = "$deviceId:${descriptor.uuid}"
                // Cancel the pending timeout since the write resolved
                pendingDescriptorWriteTimeouts.remove(key)?.let { handler.removeCallbacks(it) }
                val callback = pendingDescriptorWrites.remove(key)
                if (callback != null) {
                    val result = if (status == BluetoothGatt.GATT_SUCCESS) {
                        Result.success(Unit)
                    } else {
                        Result.failure(IllegalStateException("Descriptor write failed with status: $status"))
                    }
                    handler.post { callback(result) }
                }
            }

            override fun onMtuChanged(gatt: BluetoothGatt, mtu: Int, status: Int) {
                // Cancel the pending timeout since the MTU request resolved
                pendingMtuTimeouts.remove(deviceId)?.let { handler.removeCallbacks(it) }
                val callback = pendingMtuRequests.remove(deviceId)
                if (callback != null) {
                    val result = if (status == BluetoothGatt.GATT_SUCCESS) {
                        Result.success(mtu.toLong())
                    } else {
                        Result.failure(IllegalStateException("MTU request failed with status: $status"))
                    }
                    handler.post { callback(result) }
                }

                // Also notify Flutter of MTU change
                val event = MtuChangedEventDto(deviceId = deviceId, mtu = mtu.toLong())
                // Must dispatch to main thread for Flutter platform channel
                handler.post {
                    flutterApi.onMtuChanged(event) {}
                }
            }

            override fun onServiceChanged(gatt: BluetoothGatt) {
                handler.post {
                    flutterApi.onServicesChanged(deviceId) {}
                }
            }

            override fun onReadRemoteRssi(gatt: BluetoothGatt, rssi: Int, status: Int) {
                // Cancel the pending timeout since the RSSI read resolved
                pendingRssiTimeouts.remove(deviceId)?.let { handler.removeCallbacks(it) }
                val callback = pendingRssiReads.remove(deviceId)
                if (callback != null) {
                    val result = if (status == BluetoothGatt.GATT_SUCCESS) {
                        Result.success(rssi.toLong())
                    } else {
                        Result.failure(IllegalStateException("RSSI read failed with status: $status"))
                    }
                    handler.post { callback(result) }
                }
            }
        }
    }

    private fun notifyConnectionState(deviceId: String, state: ConnectionStateDto) {
        val event = ConnectionStateEventDto(
            deviceId = deviceId,
            state = state
        )
        // Must dispatch to main thread for Flutter platform channel
        handler.post {
            flutterApi.onConnectionStateChanged(event) {}
        }
    }

    private fun findCharacteristic(gatt: BluetoothGatt, uuid: String): BluetoothGattCharacteristic? {
        val normalizedUuid = normalizeUuid(uuid)
        for (service in gatt.services ?: emptyList()) {
            for (characteristic in service.characteristics ?: emptyList()) {
                if (characteristic.uuid.toString().equals(normalizedUuid, ignoreCase = true)) {
                    return characteristic
                }
            }
        }
        return null
    }

    private fun findDescriptor(gatt: BluetoothGatt, uuid: String): BluetoothGattDescriptor? {
        val normalizedUuid = normalizeUuid(uuid)
        for (service in gatt.services ?: emptyList()) {
            for (characteristic in service.characteristics ?: emptyList()) {
                for (descriptor in characteristic.descriptors ?: emptyList()) {
                    if (descriptor.uuid.toString().equals(normalizedUuid, ignoreCase = true)) {
                        return descriptor
                    }
                }
            }
        }
        return null
    }

    private fun mapServices(services: List<BluetoothGattService>): List<ServiceDto> {
        return services.map { service ->
            ServiceDto(
                uuid = service.uuid.toString(),
                isPrimary = service.type == BluetoothGattService.SERVICE_TYPE_PRIMARY,
                characteristics = mapCharacteristics(service.characteristics),
                includedServices = mapServices(service.includedServices ?: emptyList())
            )
        }
    }

    private fun mapCharacteristics(characteristics: List<BluetoothGattCharacteristic>?): List<CharacteristicDto> {
        return (characteristics ?: emptyList()).map { characteristic ->
            val props = characteristic.properties
            CharacteristicDto(
                uuid = characteristic.uuid.toString(),
                properties = CharacteristicPropertiesDto(
                    canRead = (props and BluetoothGattCharacteristic.PROPERTY_READ) != 0,
                    canWrite = (props and BluetoothGattCharacteristic.PROPERTY_WRITE) != 0,
                    canWriteWithoutResponse = (props and BluetoothGattCharacteristic.PROPERTY_WRITE_NO_RESPONSE) != 0,
                    canNotify = (props and BluetoothGattCharacteristic.PROPERTY_NOTIFY) != 0,
                    canIndicate = (props and BluetoothGattCharacteristic.PROPERTY_INDICATE) != 0
                ),
                descriptors = mapDescriptors(characteristic.descriptors)
            )
        }
    }

    private fun mapDescriptors(descriptors: List<BluetoothGattDescriptor>?): List<DescriptorDto> {
        return (descriptors ?: emptyList()).map { descriptor ->
            DescriptorDto(uuid = descriptor.uuid.toString())
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
