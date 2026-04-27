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
    private val queues = mutableMapOf<String, GattOpQueue>()
    private val handler = Handler(Looper.getMainLooper())

    // Pending connect callback. GATT ops route through GattOpQueue; only
    // connect-phase still uses a top-level callback because the queue is
    // created on STATE_CONNECTED and doesn't exist yet when connect() is
    // invoked.
    private val pendingConnections = mutableMapOf<String, (Result<String>) -> Unit>()

    // Pending connect timeout Runnable, keyed by deviceId. Cancelled on
    // STATE_CONNECTED so a successful connect's timer doesn't later fire
    // and tear down a still-live connection.
    private val pendingConnectionTimeouts = mutableMapOf<String, Runnable>()

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
            callback(Result.failure(BlueyAndroidError.PermissionDenied("BLUETOOTH_CONNECT")))
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
            callback(Result.failure(BlueyAndroidError.BluetoothAdapterUnavailable))
            return
        }

        val device: BluetoothDevice
        try {
            device = adapter.getRemoteDevice(deviceId)
        } catch (e: IllegalArgumentException) {
            callback(Result.failure(BlueyAndroidError.InvalidDeviceAddress(deviceId)))
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
                            pendingCallback(Result.failure(BlueyAndroidError.ConnectionTimeout))
                        }
                    }
                    pendingConnectionTimeouts[deviceId] = timeoutRunnable
                    handler.postDelayed(timeoutRunnable, timeout)
                }
                // Don't call callback here - wait for onConnectionStateChange
            } else {
                notifyConnectionState(deviceId, ConnectionStateDto.DISCONNECTED)
                callback(Result.failure(BlueyAndroidError.GattConnectionCreationFailed))
            }
        } catch (e: SecurityException) {
            notifyConnectionState(deviceId, ConnectionStateDto.DISCONNECTED)
            callback(Result.failure(BlueyAndroidError.PermissionDenied("BLUETOOTH_CONNECT")))
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
            callback(Result.failure(BlueyAndroidError.PermissionDenied("BLUETOOTH_CONNECT")))
        } catch (e: Exception) {
            callback(Result.failure(e))
        }
    }

    fun discoverServices(deviceId: String, callback: (Result<List<ServiceDto>>) -> Unit) {
        val gatt = connections[deviceId]
        if (gatt == null) {
            callback(Result.failure(BlueyAndroidError.DeviceNotConnected))
            return
        }
        val queue = queueFor(deviceId)
        if (queue == null) {
            callback(Result.failure(BlueyAndroidError.NoQueueForConnection))
            return
        }
        queue.enqueue(
            DiscoverServicesOp(
                callback = { result ->
                    val mapped = result.map { mapServices(gatt.services) }
                    callback(mapped)
                },
                timeoutMs = discoverServicesTimeoutMs,
            )
        )
    }

    fun readCharacteristic(
        deviceId: String,
        characteristicUuid: String,
        callback: (Result<ByteArray>) -> Unit
    ) {
        val gatt = connections[deviceId]
        if (gatt == null) {
            callback(Result.failure(BlueyAndroidError.DeviceNotConnected))
            return
        }
        val characteristic = findCharacteristic(gatt, characteristicUuid)
        if (characteristic == null) {
            callback(Result.failure(BlueyAndroidError.CharacteristicNotFound(characteristicUuid)))
            return
        }
        val queue = queueFor(deviceId)
        if (queue == null) {
            callback(Result.failure(BlueyAndroidError.NoQueueForConnection))
            return
        }
        queue.enqueue(ReadCharacteristicOp(characteristic, callback, readCharacteristicTimeoutMs))
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
            callback(Result.failure(BlueyAndroidError.DeviceNotConnected))
            return
        }
        val characteristic = findCharacteristic(gatt, characteristicUuid)
        if (characteristic == null) {
            callback(Result.failure(BlueyAndroidError.CharacteristicNotFound(characteristicUuid)))
            return
        }
        val queue = queueFor(deviceId)
        if (queue == null) {
            callback(Result.failure(BlueyAndroidError.NoQueueForConnection))
            return
        }
        val writeType = if (withResponse) {
            BluetoothGattCharacteristic.WRITE_TYPE_DEFAULT
        } else {
            BluetoothGattCharacteristic.WRITE_TYPE_NO_RESPONSE
        }
        queue.enqueue(
            WriteCharacteristicOp(
                characteristic, value, writeType, callback, writeCharacteristicTimeoutMs,
            )
        )
    }

    fun setNotification(
        deviceId: String,
        characteristicUuid: String,
        enable: Boolean,
        callback: (Result<Unit>) -> Unit
    ) {
        val gatt = connections[deviceId]
        if (gatt == null) {
            callback(Result.failure(BlueyAndroidError.DeviceNotConnected))
            return
        }
        val characteristic = findCharacteristic(gatt, characteristicUuid)
        if (characteristic == null) {
            callback(Result.failure(BlueyAndroidError.CharacteristicNotFound(characteristicUuid)))
            return
        }

        // Step 1 (inline, sync): enable local notifications + look up CCCD.
        // SecurityException guard: BLUETOOTH_CONNECT can be revoked between
        // connect() and this call. Without this try/catch the exception would
        // propagate up to the Pigeon dispatcher and crash the plugin instead
        // of surfacing as a normal callback failure.
        val cccd: BluetoothGattDescriptor?
        val cccdValue: ByteArray
        try {
            if (!gatt.setCharacteristicNotification(characteristic, enable)) {
                callback(Result.failure(BlueyAndroidError.SetNotificationFailed(characteristicUuid)))
                return
            }
            cccd = characteristic.getDescriptor(CCCD_UUID)
            if (cccd == null) {
                callback(Result.success(Unit))
                return
            }
            // BluetoothGattDescriptor static fields are platform types in Kotlin; use
            // the well-known BLE spec byte values as fallbacks for stub environments.
            cccdValue = when {
                !enable ->
                    BluetoothGattDescriptor.DISABLE_NOTIFICATION_VALUE ?: byteArrayOf(0x00, 0x00)
                (characteristic.properties and BluetoothGattCharacteristic.PROPERTY_INDICATE) != 0 ->
                    BluetoothGattDescriptor.ENABLE_INDICATION_VALUE ?: byteArrayOf(0x02, 0x00)
                else ->
                    BluetoothGattDescriptor.ENABLE_NOTIFICATION_VALUE ?: byteArrayOf(0x01, 0x00)
            }
        } catch (e: SecurityException) {
            callback(Result.failure(BlueyAndroidError.PermissionDenied("BLUETOOTH_CONNECT")))
            return
        }
        val queue = queueFor(deviceId)
        if (queue == null) {
            callback(Result.failure(BlueyAndroidError.NoQueueForConnection))
            return
        }
        queue.enqueue(
            EnableNotifyCccdOp(cccd, cccdValue, callback, writeDescriptorTimeoutMs),
        )
    }

    fun readDescriptor(
        deviceId: String,
        descriptorUuid: String,
        callback: (Result<ByteArray>) -> Unit
    ) {
        val gatt = connections[deviceId]
        if (gatt == null) {
            callback(Result.failure(BlueyAndroidError.DeviceNotConnected))
            return
        }
        val descriptor = findDescriptor(gatt, descriptorUuid)
        if (descriptor == null) {
            callback(Result.failure(BlueyAndroidError.DescriptorNotFound(descriptorUuid)))
            return
        }
        val queue = queueFor(deviceId)
        if (queue == null) {
            callback(Result.failure(BlueyAndroidError.NoQueueForConnection))
            return
        }
        queue.enqueue(ReadDescriptorOp(descriptor, callback, readDescriptorTimeoutMs))
    }

    fun writeDescriptor(
        deviceId: String,
        descriptorUuid: String,
        value: ByteArray,
        callback: (Result<Unit>) -> Unit
    ) {
        val gatt = connections[deviceId]
        if (gatt == null) {
            callback(Result.failure(BlueyAndroidError.DeviceNotConnected))
            return
        }
        val descriptor = findDescriptor(gatt, descriptorUuid)
        if (descriptor == null) {
            callback(Result.failure(BlueyAndroidError.DescriptorNotFound(descriptorUuid)))
            return
        }
        val queue = queueFor(deviceId)
        if (queue == null) {
            callback(Result.failure(BlueyAndroidError.NoQueueForConnection))
            return
        }
        queue.enqueue(WriteDescriptorOp(descriptor, value, callback, writeDescriptorTimeoutMs))
    }

    fun requestMtu(deviceId: String, mtu: Long, callback: (Result<Long>) -> Unit) {
        val gatt = connections[deviceId]
        if (gatt == null) {
            callback(Result.failure(BlueyAndroidError.DeviceNotConnected))
            return
        }
        val queue = queueFor(deviceId)
        if (queue == null) {
            callback(Result.failure(BlueyAndroidError.NoQueueForConnection))
            return
        }
        queue.enqueue(RequestMtuOp(mtu.toInt(), callback, requestMtuTimeoutMs))
    }

    fun readRssi(deviceId: String, callback: (Result<Long>) -> Unit) {
        val gatt = connections[deviceId]
        if (gatt == null) {
            callback(Result.failure(BlueyAndroidError.DeviceNotConnected))
            return
        }
        val queue = queueFor(deviceId)
        if (queue == null) {
            callback(Result.failure(BlueyAndroidError.NoQueueForConnection))
            return
        }
        queue.enqueue(ReadRssiOp(callback, readRssiTimeoutMs))
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
        queues.clear()

        // Cancel any pending connect timeouts so they cannot fire after cleanup
        pendingConnectionTimeouts.values.forEach { handler.removeCallbacks(it) }
        pendingConnectionTimeouts.clear()

        // Clear pending connect callbacks
        pendingConnections.clear()
    }

    /** Resolves the [GattOpQueue] for [deviceId], or null if no connection exists. */
    private fun queueFor(deviceId: String): GattOpQueue? = queues[deviceId]

    /**
     * Builds a `gatt-status-failed` [FlutterError] carrying the native GATT
     * status code for transport to Dart. Used by every `BluetoothGattCallback`
     * override when [status] is not [BluetoothGatt.GATT_SUCCESS] so that the
     * status reaches callers as a typed protocol error instead of a bare
     * [IllegalStateException] that Pigeon would marshal with an unhelpful
     * `IllegalStateException` error code.
     *
     * The [status] is stored in `FlutterError.details` so Dart can read it
     * without parsing the human-readable message.
     */
    private fun statusFailedError(operation: String, status: Int): FlutterError =
        FlutterError(
            "gatt-status-failed",
            "$operation failed with status: $status",
            status,
        )

    private fun createGattCallback(deviceId: String): BluetoothGattCallback {
        return object : BluetoothGattCallback() {
            // Threading invariant (I062): every state-mutating branch body
            // is wrapped in `handler.post { ... }` so all map mutations,
            // pending-callback invocations, and gatt.close() calls happen
            // on the main looper thread. `onConnectionStateChange` fires
            // on a Binder IPC thread; without the marshal, ConnectionManager's
            // maps would be mutated concurrently with main-thread reads in
            // the public op methods.
            //
            // `notifyConnectionState` already internally posts to main, so
            // it can stay outside the wrapper.
            override fun onConnectionStateChange(gatt: BluetoothGatt, status: Int, newState: Int) {
                when (newState) {
                    BluetoothProfile.STATE_CONNECTING -> {
                        notifyConnectionState(deviceId, ConnectionStateDto.CONNECTING)
                    }

                    BluetoothProfile.STATE_CONNECTED -> {
                        notifyConnectionState(deviceId, ConnectionStateDto.CONNECTED)
                        handler.post {
                            // Cancel the pending connect timeout.
                            pendingConnectionTimeouts.remove(deviceId)?.let {
                                handler.removeCallbacks(it)
                            }
                            // Create the queue on the main thread to preserve
                            // GattOpQueue's single-threaded invariant.
                            queues[deviceId] = GattOpQueue(gatt, handler)
                            pendingConnections.remove(deviceId)?.invoke(Result.success(deviceId))
                        }
                    }

                    BluetoothProfile.STATE_DISCONNECTING -> {
                        notifyConnectionState(deviceId, ConnectionStateDto.DISCONNECTING)
                    }

                    BluetoothProfile.STATE_DISCONNECTED -> {
                        notifyConnectionState(deviceId, ConnectionStateDto.DISCONNECTED)
                        handler.post {
                            // Cancel any pending connect timeout. Stale
                            // disconnect-fallback timer cancellation (I060)
                            // is added in a later commit.
                            pendingConnectionTimeouts.remove(deviceId)?.let {
                                handler.removeCallbacks(it)
                            }
                            // Drain any in-flight + pending queue ops with
                            // gatt-disconnected. drainAll itself is safe to
                            // call here because we're already on main.
                            queues.remove(deviceId)?.drainAll(
                                FlutterError("gatt-disconnected",
                                    "connection lost with pending GATT op", null)
                            )
                            // Connection failed or disconnected — fail any
                            // pending connect callback with the appropriate
                            // typed error.
                            val pendingCallback = pendingConnections.remove(deviceId)
                            if (pendingCallback != null) {
                                val error = if (status != BluetoothGatt.GATT_SUCCESS) {
                                    statusFailedError("Connection", status)
                                } else {
                                    BlueyAndroidError.GattConnectionCreationFailed
                                }
                                pendingCallback.invoke(Result.failure(error))
                            }
                            connections.remove(deviceId)
                            try {
                                gatt.close()
                            } catch (e: Exception) {
                                // Ignore
                            }
                        }
                    }
                }
            }

            override fun onServicesDiscovered(gatt: BluetoothGatt, status: Int) {
                handler.post {
                    val result: Result<Any?> = if (status == BluetoothGatt.GATT_SUCCESS) {
                        Result.success(Unit)
                    } else {
                        Result.failure(statusFailedError("Service discovery", status))
                    }
                    queueFor(deviceId)?.onComplete(result)
                }
            }

            override fun onCharacteristicRead(
                gatt: BluetoothGatt,
                characteristic: BluetoothGattCharacteristic,
                value: ByteArray,
                status: Int
            ) {
                handler.post {
                    val result: Result<Any?> = if (status == BluetoothGatt.GATT_SUCCESS) {
                        Result.success(value)
                    } else {
                        Result.failure(statusFailedError("Read", status))
                    }
                    queueFor(deviceId)?.onComplete(result)
                }
            }

            @Deprecated("Deprecated in Java")
            @Suppress("DEPRECATION")
            override fun onCharacteristicRead(
                gatt: BluetoothGatt,
                characteristic: BluetoothGattCharacteristic,
                status: Int
            ) {
                handler.post {
                    val result: Result<Any?> = if (status == BluetoothGatt.GATT_SUCCESS) {
                        Result.success(characteristic.value ?: ByteArray(0))
                    } else {
                        Result.failure(statusFailedError("Read", status))
                    }
                    queueFor(deviceId)?.onComplete(result)
                }
            }

            override fun onCharacteristicWrite(
                gatt: BluetoothGatt,
                characteristic: BluetoothGattCharacteristic,
                status: Int
            ) {
                handler.post {
                    val result: Result<Any?> = if (status == BluetoothGatt.GATT_SUCCESS) {
                        Result.success(Unit)
                    } else {
                        Result.failure(statusFailedError("Write", status))
                    }
                    queueFor(deviceId)?.onComplete(result)
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
                handler.post {
                    val result: Result<Any?> = if (status == BluetoothGatt.GATT_SUCCESS) {
                        Result.success(value)
                    } else {
                        Result.failure(statusFailedError("Descriptor read", status))
                    }
                    queueFor(deviceId)?.onComplete(result)
                }
            }

            @Deprecated("Deprecated in Java")
            @Suppress("DEPRECATION")
            override fun onDescriptorRead(
                gatt: BluetoothGatt,
                descriptor: BluetoothGattDescriptor,
                status: Int
            ) {
                handler.post {
                    val result: Result<Any?> = if (status == BluetoothGatt.GATT_SUCCESS) {
                        Result.success(descriptor.value ?: ByteArray(0))
                    } else {
                        Result.failure(statusFailedError("Descriptor read", status))
                    }
                    queueFor(deviceId)?.onComplete(result)
                }
            }

            override fun onDescriptorWrite(
                gatt: BluetoothGatt,
                descriptor: BluetoothGattDescriptor,
                status: Int
            ) {
                handler.post {
                    val result: Result<Any?> = if (status == BluetoothGatt.GATT_SUCCESS) {
                        Result.success(Unit)
                    } else {
                        Result.failure(statusFailedError("Descriptor write", status))
                    }
                    queueFor(deviceId)?.onComplete(result)
                }
            }

            override fun onMtuChanged(gatt: BluetoothGatt, mtu: Int, status: Int) {
                handler.post {
                    val result: Result<Any?> = if (status == BluetoothGatt.GATT_SUCCESS) {
                        Result.success(mtu.toLong())
                    } else {
                        Result.failure(statusFailedError("MTU request", status))
                    }
                    queueFor(deviceId)?.onComplete(result)
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
                handler.post {
                    val result: Result<Any?> = if (status == BluetoothGatt.GATT_SUCCESS) {
                        Result.success(rssi.toLong())
                    } else {
                        Result.failure(statusFailedError("RSSI read", status))
                    }
                    queueFor(deviceId)?.onComplete(result)
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
