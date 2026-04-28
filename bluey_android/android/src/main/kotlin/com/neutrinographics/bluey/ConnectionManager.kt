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

    // Pending disconnect callbacks, keyed by deviceId. A disconnect()
    // call registers its callback here and returns; the callback fires
    // either from the STATE_DISCONNECTED handler (success) or from the
    // 5 s fallback runnable (failure with gatt-disconnected). Multiple
    // concurrent disconnect() calls to the same deviceId share-the-future:
    // every callback fires when the link comes down. (I060 + spec
    // Decision 3.)
    private val pendingDisconnects = mutableMapOf<String, MutableList<(Result<Unit>) -> Unit>>()

    // Pending disconnect fallback Runnable, keyed by deviceId. Force-closes
    // the gatt and synthesizes a gatt-disconnected failure if
    // STATE_DISCONNECTED never arrives within DISCONNECT_FALLBACK_MS.
    private val pendingDisconnectTimeouts = mutableMapOf<String, Runnable>()

    // I088 — handle-identity lookup tables. Populated when
    // onServicesDiscovered fires (after the existing rediscovery flow);
    // cleared on STATE_DISCONNECTED and on onServiceChanged (before
    // re-discovery is triggered) so stale handles can't outlive the
    // attribute layout they reference.
    //
    // Characteristic handles use the public
    // `BluetoothGattCharacteristic.getInstanceId()`. Descriptor handles
    // are minted client-side from a per-device monotonic counter
    // starting at 1, because `BluetoothGattDescriptor.getInstanceId()`
    // is `@hide` in AOSP. iOS mints both kinds the same way; Android's
    // descriptor minting mirrors that.
    private val characteristicByHandle:
        MutableMap<String, MutableMap<Int, BluetoothGattCharacteristic>> = mutableMapOf()
    private val descriptorByHandle:
        MutableMap<String, MutableMap<Int, BluetoothGattDescriptor>> = mutableMapOf()
    private val nextDescriptorHandle: MutableMap<String, Int> = mutableMapOf()

    // CCCD UUID for enabling notifications/indications
    companion object {
        private val CCCD_UUID = UUID.fromString("00002902-0000-1000-8000-00805f9b34fb")

        /**
         * Maximum time to wait for `STATE_DISCONNECTED` after a `disconnect()`
         * call before force-closing the gatt and synthesizing a
         * `gatt-disconnected` failure. Android's `BluetoothGatt.disconnect()`
         * is fire-and-forget at the OS level; occasionally the callback
         * genuinely doesn't arrive (driver bug, peer unreachable, controller
         * stuck). 5 s is comfortably above the typical <1 s OS-level disconnect
         * latency and below most app-level timeouts. (I060 + spec Decision 1.)
         */
        private const val DISCONNECT_FALLBACK_MS = 5_000L
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

        // Reject concurrent connects to the same device (I098 item 5).
        // Order matters: check the in-flight set BEFORE the established
        // set. Otherwise the established check would fire idempotent
        // success during the connecting → connected window where
        // connections[deviceId] is populated but the link isn't up yet
        // (the original false-positive bug).
        if (pendingConnections.containsKey(deviceId)) {
            callback(Result.failure(BlueyAndroidError.ConnectInProgress(deviceId)))
            return
        }

        // Check if already connected (idempotent success).
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

    /**
     * Disconnects from [deviceId]. The callback fires only after the OS
     * reports `STATE_DISCONNECTED` (success) or after a 5 s fallback timer
     * force-closes the gatt and synthesizes a `gatt-disconnected` failure.
     *
     * Calling `disconnect()` on a deviceId with no entry in [connections]
     * fires the callback synchronously with success (idempotent / no-op,
     * matches the iOS I044 fix).
     *
     * Multiple concurrent `disconnect()` calls to the same deviceId
     * share-the-future: every registered callback fires when the link
     * comes down. (I060 + spec Decision 3.)
     */
    fun disconnect(deviceId: String, callback: (Result<Unit>) -> Unit) {
        val gatt = connections[deviceId]
        if (gatt == null) {
            // Nothing to disconnect — already gone (idempotent).
            callback(Result.success(Unit))
            return
        }

        // Share-the-future: append to the list if a disconnect is already
        // in flight for this device. Only the first disconnect issues the
        // gatt.disconnect() call and schedules the fallback; subsequent
        // ones piggy-back on the same completion.
        val existing = pendingDisconnects[deviceId]
        if (existing != null) {
            existing.add(callback)
            return
        }
        pendingDisconnects[deviceId] = mutableListOf(callback)

        try {
            notifyConnectionState(deviceId, ConnectionStateDto.DISCONNECTING)
            gatt.disconnect()
        } catch (e: SecurityException) {
            // Permission revoked between connect() and disconnect(). Drop
            // the registered callbacks and surface synchronously.
            pendingDisconnects.remove(deviceId)
            callback(Result.failure(BlueyAndroidError.PermissionDenied("BLUETOOTH_CONNECT")))
            return
        } catch (e: Exception) {
            pendingDisconnects.remove(deviceId)
            callback(Result.failure(e))
            return
        }

        // Schedule the 5 s fallback. If STATE_DISCONNECTED fires within
        // the window, the fallback Runnable is cancelled in the
        // STATE_DISCONNECTED handler. If not, it force-closes the gatt
        // and surfaces gatt-disconnected to every registered callback.
        val fallback = Runnable {
            // If pendingDisconnects[deviceId] is still populated, the OS
            // callback never arrived; complete the callbacks with
            // gatt-disconnected and tear down state ourselves.
            val callbacks = pendingDisconnects.remove(deviceId) ?: return@Runnable
            pendingDisconnectTimeouts.remove(deviceId)
            queues.remove(deviceId)?.drainAll(
                FlutterError("gatt-disconnected",
                    "connection lost with pending GATT op", null)
            )
            connections.remove(deviceId)
            try {
                gatt.close()
            } catch (e: Exception) {
                // Ignore — we're already in the failure path.
            }
            // Synthesize the missing platform DISCONNECTED so domain-side
            // ConnectionState reaches its terminal value.
            notifyConnectionState(deviceId, ConnectionStateDto.DISCONNECTED)
            val error = FlutterError(
                "gatt-disconnected",
                "disconnect timed out after ${DISCONNECT_FALLBACK_MS}ms; force-closed gatt",
                null,
            )
            for (cb in callbacks) cb(Result.failure(error))
        }
        pendingDisconnectTimeouts[deviceId] = fallback
        handler.postDelayed(fallback, DISCONNECT_FALLBACK_MS)
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
                    val mapped = result.map { mapServices(deviceId, gatt.services) }
                    callback(mapped)
                },
                timeoutMs = discoverServicesTimeoutMs,
            )
        )
    }

    fun readCharacteristic(
        deviceId: String,
        characteristicUuid: String,
        characteristicHandle: Long?,
        callback: (Result<ByteArray>) -> Unit
    ) {
        val gatt = connections[deviceId]
        if (gatt == null) {
            callback(Result.failure(BlueyAndroidError.DeviceNotConnected))
            return
        }
        val characteristic = when (val result = lookupCharacteristic(deviceId, gatt, characteristicUuid, characteristicHandle)) {
            is LookupResult.Found -> result.value
            is LookupResult.HandleInvalidated -> {
                callback(Result.failure(BlueyAndroidError.HandleInvalidated(result.handle, result.uuid)))
                return
            }
            is LookupResult.NotFound -> {
                callback(Result.failure(BlueyAndroidError.CharacteristicNotFound(characteristicUuid)))
                return
            }
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
        characteristicHandle: Long?,
        callback: (Result<Unit>) -> Unit
    ) {
        val gatt = connections[deviceId]
        if (gatt == null) {
            callback(Result.failure(BlueyAndroidError.DeviceNotConnected))
            return
        }
        val characteristic = when (val result = lookupCharacteristic(deviceId, gatt, characteristicUuid, characteristicHandle)) {
            is LookupResult.Found -> result.value
            is LookupResult.HandleInvalidated -> {
                callback(Result.failure(BlueyAndroidError.HandleInvalidated(result.handle, result.uuid)))
                return
            }
            is LookupResult.NotFound -> {
                callback(Result.failure(BlueyAndroidError.CharacteristicNotFound(characteristicUuid)))
                return
            }
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
        characteristicHandle: Long?,
        callback: (Result<Unit>) -> Unit
    ) {
        val gatt = connections[deviceId]
        if (gatt == null) {
            callback(Result.failure(BlueyAndroidError.DeviceNotConnected))
            return
        }
        val characteristic = when (val result = lookupCharacteristic(deviceId, gatt, characteristicUuid, characteristicHandle)) {
            is LookupResult.Found -> result.value
            is LookupResult.HandleInvalidated -> {
                callback(Result.failure(BlueyAndroidError.HandleInvalidated(result.handle, result.uuid)))
                return
            }
            is LookupResult.NotFound -> {
                callback(Result.failure(BlueyAndroidError.CharacteristicNotFound(characteristicUuid)))
                return
            }
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
        characteristicHandle: Long?,
        descriptorHandle: Long?,
        callback: (Result<ByteArray>) -> Unit
    ) {
        val gatt = connections[deviceId]
        if (gatt == null) {
            callback(Result.failure(BlueyAndroidError.DeviceNotConnected))
            return
        }
        val descriptor = when (val result = lookupDescriptor(deviceId, gatt, descriptorUuid, descriptorHandle)) {
            is LookupResult.Found -> result.value
            is LookupResult.HandleInvalidated -> {
                callback(Result.failure(BlueyAndroidError.HandleInvalidated(result.handle, result.uuid)))
                return
            }
            is LookupResult.NotFound -> {
                callback(Result.failure(BlueyAndroidError.DescriptorNotFound(descriptorUuid)))
                return
            }
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
        characteristicHandle: Long?,
        descriptorHandle: Long?,
        callback: (Result<Unit>) -> Unit
    ) {
        val gatt = connections[deviceId]
        if (gatt == null) {
            callback(Result.failure(BlueyAndroidError.DeviceNotConnected))
            return
        }
        val descriptor = when (val result = lookupDescriptor(deviceId, gatt, descriptorUuid, descriptorHandle)) {
            is LookupResult.Found -> result.value
            is LookupResult.HandleInvalidated -> {
                callback(Result.failure(BlueyAndroidError.HandleInvalidated(result.handle, result.uuid)))
                return
            }
            is LookupResult.NotFound -> {
                callback(Result.failure(BlueyAndroidError.DescriptorNotFound(descriptorUuid)))
                return
            }
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

    /**
     * Tears down all in-flight connection state. Called on engine detach
     * / activity destroy. Order matters (I061):
     *
     *   1. Drain queues with gatt-disconnected so in-flight queue ops fire
     *      their callbacks.
     *   2. Fail pending connect callbacks with a typed cleanup error.
     *   3. Succeed pending disconnect callbacks (the user asked for the
     *      link to come down; cleanup made that happen — spec Decision 2).
     *   4. Cancel scheduled timeout Runnables.
     *   5. Disconnect and close every BluetoothGatt handle.
     *   6. Clear all maps.
     *
     * The completions happen BEFORE gatt.disconnect() so that if the OS
     * later schedules a STATE_DISCONNECTED for a torn-down connection,
     * the binder-thread handler.post finds empty maps and is a no-op
     * (rather than racing with cleanup() and double-firing user
     * callbacks).
     */
    fun cleanup() {
        // 1. Drain in-flight queue ops.
        val drainError = FlutterError(
            "gatt-disconnected", "cleanup in progress", null,
        )
        for ((_, queue) in queues) {
            queue.drainAll(drainError)
        }
        queues.clear()

        // 2. Fail pending connect callbacks.
        val connectCallbacks = pendingConnections.values.toList()
        pendingConnections.clear()
        for (cb in connectCallbacks) {
            cb(Result.failure(BlueyAndroidError.GattConnectionCreationFailed))
        }

        // 3. Succeed pending disconnect callbacks. The link is going away
        //    — that is what disconnect() callers asked for.
        val disconnectCallbackLists = pendingDisconnects.values.toList()
        pendingDisconnects.clear()
        for (callbacks in disconnectCallbackLists) {
            for (cb in callbacks) cb(Result.success(Unit))
        }

        // 4. Cancel scheduled timeouts.
        pendingConnectionTimeouts.values.forEach { handler.removeCallbacks(it) }
        pendingConnectionTimeouts.clear()
        pendingDisconnectTimeouts.values.forEach { handler.removeCallbacks(it) }
        pendingDisconnectTimeouts.clear()

        // 5. Disconnect and close every gatt handle. Errors are ignored —
        //    we're already in the failure path.
        for ((_, gatt) in connections) {
            try {
                gatt.disconnect()
            } catch (e: Exception) {
                // Ignore
            }
            try {
                gatt.close()
            } catch (e: Exception) {
                // Ignore
            }
        }
        connections.clear()
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
                            // Cancel any pending connect timeout and any
                            // pending disconnect fallback timer — neither
                            // should fire once STATE_DISCONNECTED has arrived.
                            pendingConnectionTimeouts.remove(deviceId)?.let {
                                handler.removeCallbacks(it)
                            }
                            pendingDisconnectTimeouts.remove(deviceId)?.let {
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
                            // Pending disconnects succeed — this is the
                            // expected completion path for disconnect().
                            // Every registered share-the-future callback fires.
                            pendingDisconnects.remove(deviceId)?.forEach { cb ->
                                cb(Result.success(Unit))
                            }
                            connections.remove(deviceId)
                            // I088 — drop the per-device handle lookup
                            // tables; the attribute database is gone.
                            characteristicByHandle.remove(deviceId)
                            descriptorByHandle.remove(deviceId)
                            nextDescriptorHandle.remove(deviceId)
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
                    // I088 — populate handle lookup tables BEFORE firing
                    // the queue's completion. The DiscoverServicesOp
                    // callback runs inside `onComplete` and synchronously
                    // calls `mapServices`, which reverse-looks-up
                    // descriptor handles from `descriptorByHandle[deviceId]`.
                    // If we populated AFTER `onComplete`, mapServices
                    // would see an empty handle map. Replace any previous
                    // tables wholesale so a fresh discovery (e.g. after
                    // onServiceChanged) starts from a clean slate.
                    if (status == BluetoothGatt.GATT_SUCCESS) {
                        val charMap = mutableMapOf<Int, BluetoothGattCharacteristic>()
                        val descMap = mutableMapOf<Int, BluetoothGattDescriptor>()
                        var nextDesc = 1
                        for (service in gatt.services) {
                            for (char in service.characteristics) {
                                charMap[char.instanceId] = char
                                for (desc in char.descriptors) {
                                    descMap[nextDesc] = desc
                                    nextDesc++
                                }
                            }
                        }
                        characteristicByHandle[deviceId] = charMap
                        descriptorByHandle[deviceId] = descMap
                        nextDescriptorHandle[deviceId] = nextDesc
                    }

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
                    // I088 — clear stale handle tables before the platform
                    // schedules re-discovery; the next onServicesDiscovered
                    // will repopulate them. Without this clear, a write
                    // racing the re-discovery could resolve a handle that
                    // pointed at the previous attribute layout.
                    characteristicByHandle.remove(deviceId)
                    descriptorByHandle.remove(deviceId)
                    nextDescriptorHandle.remove(deviceId)
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

    /**
     * I088 — result of a handle-first attribute lookup.
     *
     * `Found` carries the resolved characteristic / descriptor reference.
     *
     * `HandleInvalidated` indicates the Dart side passed a non-null
     * handle but the per-device handle table no longer recognises it
     * (Service Changed cleared it; the caller is holding a stale
     * reference from the prior discovery). The caller maps this to
     * [BlueyAndroidError.HandleInvalidated] so the Dart adapter
     * surfaces it as `AttributeHandleInvalidatedException`. Distinct
     * from `NotFound`, which is the legacy null-handle / UUID-miss
     * path.
     *
     * `NotFound` is the residual case: no handle was supplied and
     * the UUID-keyed traversal also missed.
     */
    private sealed class LookupResult<out T> {
        data class Found<T>(val value: T) : LookupResult<T>()
        data class HandleInvalidated(val handle: Long, val uuid: String) :
            LookupResult<Nothing>()
        object NotFound : LookupResult<Nothing>()
    }

    /**
     * I088 D.11 — handle-first lookup. Refines the D.8 behaviour:
     *
     *   * `handle != null` and present in the table → `Found`.
     *   * `handle != null` but missing → `HandleInvalidated`. We do *not*
     *     fall back to UUID in this case: the Dart side opted into
     *     handle routing by passing a non-null handle, so a miss carries
     *     the specific "Service Changed cleared the table" semantics
     *     rather than a generic "couldn't find it". Falling back to UUID
     *     here would mask that signal and silently route the op to a
     *     potentially-different attribute under the same UUID.
     *   * `handle == null` → UUID fallback, as before. Legacy path for
     *     callers (e.g. tests) that still issue ops by UUID alone.
     *
     * D.13 will retire the UUID fallback entirely; handles will become
     * required.
     */
    private fun lookupCharacteristic(
        deviceId: String,
        gatt: BluetoothGatt,
        uuid: String,
        handle: Long?,
    ): LookupResult<BluetoothGattCharacteristic> {
        if (handle != null) {
            val match = characteristicByHandle[deviceId]?.get(handle.toInt())
            return if (match != null) {
                LookupResult.Found(match)
            } else {
                LookupResult.HandleInvalidated(handle, uuid)
            }
        }
        return findCharacteristic(gatt, uuid)?.let { LookupResult.Found(it) }
            ?: LookupResult.NotFound
    }

    /**
     * I088 D.11 — handle-first lookup for descriptors. Mirrors
     * [lookupCharacteristic]: a non-null handle that misses the table
     * surfaces `HandleInvalidated` instead of falling back to UUID.
     */
    private fun lookupDescriptor(
        deviceId: String,
        gatt: BluetoothGatt,
        uuid: String,
        handle: Long?,
    ): LookupResult<BluetoothGattDescriptor> {
        if (handle != null) {
            val match = descriptorByHandle[deviceId]?.get(handle.toInt())
            return if (match != null) {
                LookupResult.Found(match)
            } else {
                LookupResult.HandleInvalidated(handle, uuid)
            }
        }
        return findDescriptor(gatt, uuid)?.let { LookupResult.Found(it) }
            ?: LookupResult.NotFound
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

    private fun mapServices(deviceId: String, services: List<BluetoothGattService>): List<ServiceDto> {
        return services.map { service ->
            ServiceDto(
                uuid = service.uuid.toString(),
                isPrimary = service.type == BluetoothGattService.SERVICE_TYPE_PRIMARY,
                characteristics = mapCharacteristics(deviceId, service.characteristics),
                includedServices = mapServices(deviceId, service.includedServices ?: emptyList())
            )
        }
    }

    private fun mapCharacteristics(
        deviceId: String,
        characteristics: List<BluetoothGattCharacteristic>?,
    ): List<CharacteristicDto> {
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
                descriptors = mapDescriptors(deviceId, characteristic.descriptors),
                // I088 — emit the characteristic's public instanceId as
                // the handle so Dart can address chars by handle without
                // having to disambiguate UUID collisions across services.
                handle = characteristic.instanceId.toLong(),
            )
        }
    }

    private fun mapDescriptors(
        deviceId: String,
        descriptors: List<BluetoothGattDescriptor>?,
    ): List<DescriptorDto> {
        // I088 — reverse-lookup each descriptor's minted handle from the
        // table populated in `onServicesDiscovered` (BluetoothGattDescriptor
        // has no public instanceId, so handles are minted client-side).
        // Reference equality is correct: the same Java object that was
        // stored at population time is the one being mapped here.
        val descMap = descriptorByHandle[deviceId]
        return (descriptors ?: emptyList()).map { descriptor ->
            val handle = descMap?.entries?.firstOrNull { it.value === descriptor }?.key
            DescriptorDto(
                uuid = descriptor.uuid.toString(),
                handle = handle?.toLong(),
            )
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
