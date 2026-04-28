package com.neutrinographics.bluey

import android.Manifest
import android.app.Activity
import android.bluetooth.BluetoothDevice
import android.bluetooth.BluetoothGatt
import android.bluetooth.BluetoothGattCharacteristic
import android.bluetooth.BluetoothGattDescriptor
import android.bluetooth.BluetoothGattServer
import android.bluetooth.BluetoothGattServerCallback
import android.bluetooth.BluetoothGattService
import android.bluetooth.BluetoothManager
import android.bluetooth.BluetoothProfile
import android.content.Context
import android.content.pm.PackageManager
import android.os.Build
import android.os.Handler
import android.os.Looper
import android.util.Log
import androidx.core.content.ContextCompat
import java.util.UUID

/**
 * GattServer - handles BLE GATT server (peripheral) operations.
 *
 * Manages the GATT server including service registration, handling read/write
 * requests from centrals, and sending notifications/indications.
 * Follows Single Responsibility Principle.
 */
class GattServer(
    private val context: Context,
    private val bluetoothManager: BluetoothManager?,
    private val flutterApi: BlueyFlutterApi
) {
    private var activity: Activity? = null
    private var gattServer: BluetoothGattServer? = null
    private val handler = Handler(Looper.getMainLooper())

    init {
        Log.d("GattServer", "GattServer instance created: $this")
    }

    // Track connected centrals
    private val connectedCentrals = mutableMapOf<String, BluetoothDevice>()
    private val centralMtus = mutableMapOf<String, Int>()

    // Track notification subscriptions: characteristicUuid -> Set<centralId>
    private val subscriptions = mutableMapOf<String, MutableSet<String>>()

    // Pending ATT requests keyed by native Android requestId (cast to Long).
    // Populated on binder thread in onCharacteristic{Read,Write}Request;
    // drained on main thread in respondTo{Read,Write}Request, on central
    // disconnect, and on cleanup(). See PendingRequestRegistry for the
    // thread-safety argument.
    private val pendingReadRequests = PendingRequestRegistry<PendingRead>()
    private val pendingWriteRequests = PendingRequestRegistry<PendingWrite>()

    // Pending callbacks for async service additions, keyed by the
    // service UUID's string form (see the `key` extracted in addService
    // and matched against `service.uuid.toString()` in onServiceAdded).
    // Pre-I080 this was a single slot — parallel addService calls
    // overwrote each other and the first caller's Future never
    // resolved. Now each pending registration has its own slot.
    //
    // The callback receives the populated `LocalServiceDto` (handles
    // filled in for every characteristic / descriptor) on success.
    private val pendingServiceCallbacks = mutableMapOf<String, (Result<LocalServiceDto>) -> Unit>()

    /** Populated LocalServiceDto (handles stamped) per pending key. */
    private val pendingServiceDtos = mutableMapOf<String, LocalServiceDto>()

    // I088 D.13 — handle table for the local server's characteristics.
    // Module-wide monotonic counter starting at 1 (0 is reserved as
    // "invalid handle"); minted once per characteristic the first time
    // [addService] sees it. Cleared per-service on [removeService] and
    // entirely on [cleanup]. Used by [notifyCharacteristic] /
    // [notifyCharacteristicTo] to address local characteristics; the
    // CCCD-write path that surfaces ReadRequestDto / WriteRequestDto
    // also reverse-looks-up the handle here so the Dart peer can
    // dispatch on handle even when multiple characteristics share a
    // UUID across services.
    private val characteristicByHandle = mutableMapOf<Long, BluetoothGattCharacteristic>()
    private var nextLocalHandle: Long = 1

    /** Mints a handle for [characteristic] and stores it. */
    private fun mintLocalHandle(characteristic: BluetoothGattCharacteristic): Long {
        val h = nextLocalHandle
        nextLocalHandle += 1
        characteristicByHandle[h] = characteristic
        return h
    }

    /** Reverse lookup by reference identity. */
    private fun handleForCharacteristic(c: BluetoothGattCharacteristic): Long? {
        for ((h, ref) in characteristicByHandle) {
            if (ref === c) return h
        }
        return null
    }

    // Pending per-central notification completions (I012). Android's
    // `onNotificationSent(device, status)` doesn't carry the
    // characteristic UUID, so completions are FIFO per central:
    // each notifyCharacteristic / notifyCharacteristicTo enqueues a
    // PendingNotification per recipient; the next onNotificationSent
    // for that central pops the head.
    private val pendingNotifications =
        mutableMapOf<String, ArrayDeque<PendingNotification>>()

    /**
     * Per-central in-flight notification entry. [onComplete] receives
     * the per-send result; [timeoutRunnable] is the scheduled timer
     * that will fire if `onNotificationSent` doesn't arrive within
     * [NOTIFY_SEND_TIMEOUT_MS].
     */
    private class PendingNotification(
        val onComplete: (Result<Unit>) -> Unit,
    ) {
        var timeoutRunnable: Runnable? = null
    }

    // CCCD UUID for notifications/indications
    companion object {
        private val CCCD_UUID = UUID.fromString("00002902-0000-1000-8000-00805f9b34fb")
        private const val DEFAULT_MTU = 23

        /**
         * Maximum time to wait for `onNotificationSent` per recipient
         * before failing the per-send completion with `gatt-timeout`.
         * 5 s matches the I098 disconnect-fallback budget; on a
         * healthy link `onNotificationSent` typically fires in <100 ms.
         * (I012)
         */
        private const val NOTIFY_SEND_TIMEOUT_MS = 5_000L
    }

    fun setActivity(activity: Activity?) {
        this.activity = activity
    }

    fun addService(service: LocalServiceDto, callback: (Result<LocalServiceDto>) -> Unit) {
        Log.d("GattServer", "addService: ${service.uuid}")
        if (!hasRequiredPermissions()) {
            Log.d("GattServer", "addService: missing permissions")
            callback(Result.failure(BlueyAndroidError.PermissionDenied("BLUETOOTH_CONNECT")))
            return
        }

        ensureServerOpen()
        val server = gattServer
        if (server == null) {
            Log.d("GattServer", "addService: server is null after ensureServerOpen")
            callback(Result.failure(BlueyAndroidError.FailedToOpenGattServer))
            return
        }

        val builtChars = mutableListOf<BluetoothGattCharacteristic>()
        val gattService = createGattService(service, builtChars)
        // I088 D.13 — mint handles for every newly-built
        // BluetoothGattCharacteristic in the live Android service tree
        // and stamp them into a populated LocalServiceDto that we return
        // to Dart on success. We pass the freshly-collected `builtChars`
        // list rather than reading `gattService.characteristics` because
        // the JVM stub used in unit tests doesn't implement getters on
        // BluetoothGattService.
        val populated = populateHandles(service, builtChars)
        // Key by the service's *normalized* UUID (lowercase canonical form)
        // so onServiceAdded — which receives a BluetoothGattService whose
        // .uuid.toString() is also lowercase canonical — can match.
        val key = normalizeUuid(service.uuid).lowercase()
        pendingServiceCallbacks[key] = callback
        pendingServiceDtos[key] = populated

        try {
            Log.d("GattServer", "addService: calling server.addService")
            if (!server.addService(gattService)) {
                Log.d("GattServer", "addService: server.addService returned false")
                pendingServiceCallbacks.remove(key)
                pendingServiceDtos.remove(key)
                callback(Result.failure(BlueyAndroidError.FailedToAddService(service.uuid)))
            }
            Log.d("GattServer", "addService: server.addService returned true, waiting for onServiceAdded")
            // Callback will be invoked in onServiceAdded
        } catch (e: SecurityException) {
            Log.e("GattServer", "addService: SecurityException", e)
            pendingServiceCallbacks.remove(key)
            pendingServiceDtos.remove(key)
            callback(Result.failure(BlueyAndroidError.PermissionDenied("BLUETOOTH_CONNECT")))
        }
    }

    /**
     * Walks the just-built [gattService] in lock-step with [dto], minting
     * a handle for every characteristic and a per-characteristic
     * monotonic descriptor handle (parallel to the central-side scheme).
     * Returns a populated [LocalServiceDto] with handles stamped in.
     * The [characteristicByHandle] table is updated as a side-effect so
     * subsequent [notifyCharacteristic] calls and incoming ATT requests
     * can resolve handle ↔ BluetoothGattCharacteristic.
     */
    private fun populateHandles(
        dto: LocalServiceDto,
        builtChars: List<BluetoothGattCharacteristic>,
    ): LocalServiceDto {
        val populatedChars = mutableListOf<LocalCharacteristicDto>()
        // The builtChars list matches createGattService's append order,
        // so a positional zip is exact. CCCDs auto-added inside the
        // BluetoothGattCharacteristic itself stay out of the DTO and
        // out of this list.
        for ((idx, charDto) in dto.characteristics.withIndex()) {
            val gattChar = builtChars[idx]
            val charHandle = mintLocalHandle(gattChar)
            // Descriptor handles are minted per characteristic from a
            // local counter starting at 1, mirroring the central-side
            // scheme. CCCDs auto-added by createGattService aren't in
            // the DTO so they don't get DTO-side handles (they're never
            // addressed by Dart).
            var nextDescHandle = 1L
            val populatedDescs = charDto.descriptors.map { descDto ->
                LocalDescriptorDto(
                    uuid = descDto.uuid,
                    permissions = descDto.permissions,
                    value = descDto.value,
                    handle = nextDescHandle++,
                )
            }
            populatedChars.add(
                LocalCharacteristicDto(
                    uuid = charDto.uuid,
                    properties = charDto.properties,
                    permissions = charDto.permissions,
                    descriptors = populatedDescs,
                    handle = charHandle,
                ),
            )
        }
        // Included services aren't supported by the test fixtures and
        // this code path isn't exercised in production yet, so we
        // forward them unchanged rather than recurse with a fresh
        // builtChars list.
        return LocalServiceDto(
            uuid = dto.uuid,
            isPrimary = dto.isPrimary,
            characteristics = populatedChars,
            includedServices = dto.includedServices,
        )
    }

    fun removeService(serviceUuid: String, callback: (Result<Unit>) -> Unit) {
        val server = gattServer
        if (server == null) {
            callback(Result.success(Unit))
            return
        }

        try {
            val uuid = UUID.fromString(normalizeUuid(serviceUuid))
            val service = server.getService(uuid)
            if (service != null) {
                // I088 D.13 — drop handle entries for the service's
                // characteristics before removing the service. The
                // counter does NOT reset (matches the iOS handle store).
                for (char in service.characteristics ?: emptyList()) {
                    val h = handleForCharacteristic(char)
                    if (h != null) characteristicByHandle.remove(h)
                }
                server.removeService(service)
            }
            callback(Result.success(Unit))
        } catch (e: SecurityException) {
            callback(Result.failure(BlueyAndroidError.PermissionDenied("BLUETOOTH_CONNECT")))
        } catch (e: Exception) {
            callback(Result.failure(e))
        }
    }

    fun notifyCharacteristic(
        characteristicHandle: Long,
        value: ByteArray,
        callback: (Result<Unit>) -> Unit
    ) {
        val server = gattServer
        if (server == null) {
            callback(Result.failure(BlueyAndroidError.NotInitialized("GattServer")))
            return
        }

        val characteristic = characteristicByHandle[characteristicHandle]
        if (characteristic == null) {
            callback(Result.failure(BlueyAndroidError.HandleInvalidated(characteristicHandle)))
            return
        }
        val normalizedUuid = characteristic.uuid.toString().lowercase()

        // Defensive snapshot of the subscribed-centrals set. The
        // underlying MutableSet is mutated from binder-thread callbacks
        // (CCCD subscribe/unsubscribe in onDescriptorWriteRequest, and
        // STATE_DISCONNECTED in onConnectionStateChange). Iterating the
        // live set would throw ConcurrentModificationException if a
        // central disconnects or unsubscribes mid-fanout (I082).
        //
        // Snapshot semantics also make I086 a no-op: a removed service's
        // handle is dropped from characteristicByHandle, so we return
        // early above — any mid-fanout removal affects only the
        // subscription map, not the captured snapshot.
        val subscribedCentralIds = subscriptions[normalizedUuid]?.toList() ?: emptyList()
        val recipients = subscribedCentralIds.mapNotNull { id ->
            connectedCentrals[id]?.let { id to it }
        }
        if (recipients.isEmpty()) {
            callback(Result.success(Unit))
            return
        }

        // I012: aggregate per-central completions and only invoke the
        // outer callback after every recipient's `onNotificationSent`
        // has fired (or timed out / disconnected). All-or-nothing
        // semantics: success when every central acks with GATT_SUCCESS;
        // first non-success status, timeout, or disconnect surfaces as
        // the aggregate failure.
        val expected = recipients.size
        var completed = 0
        var firstFailure: Throwable? = null
        var fired = false
        val onPerCentralComplete: (Result<Unit>) -> Unit = { result ->
            if (!fired) {
                completed++
                if (firstFailure == null && result.isFailure) {
                    firstFailure = result.exceptionOrNull()
                }
                if (completed == expected) {
                    fired = true
                    val f = firstFailure
                    if (f != null) {
                        callback(Result.failure(f))
                    } else {
                        callback(Result.success(Unit))
                    }
                }
            }
        }

        // Enqueue all per-central pending entries BEFORE issuing any
        // sendNotification. If sendNotification(central1) triggers a
        // binder-thread reaction that races back to mutate state — for
        // example, a STATE_DISCONNECTED for central2 that drains
        // pendingNotifications[central2] — we want central2's entry to
        // already be enqueued so the drain finds it. (Otherwise the
        // entry is enqueued after the disconnect handler ran and sits
        // in the queue forever waiting for an onNotificationSent that
        // will never arrive.)
        for ((id, _) in recipients) {
            enqueuePendingNotification(id, onPerCentralComplete)
        }
        try {
            for ((_, device) in recipients) {
                sendNotification(server, device, characteristic, value)
            }
        } catch (e: SecurityException) {
            if (!fired) {
                fired = true
                callback(Result.failure(BlueyAndroidError.PermissionDenied("BLUETOOTH_CONNECT")))
            }
        }
    }

    fun notifyCharacteristicTo(
        centralId: String,
        characteristicHandle: Long,
        value: ByteArray,
        callback: (Result<Unit>) -> Unit
    ) {
        val server = gattServer
        if (server == null) {
            callback(Result.failure(BlueyAndroidError.NotInitialized("GattServer")))
            return
        }

        val device = connectedCentrals[centralId]
        if (device == null) {
            callback(Result.failure(BlueyAndroidError.CentralNotFound(centralId)))
            return
        }

        val characteristic = characteristicByHandle[characteristicHandle]
        if (characteristic == null) {
            callback(Result.failure(BlueyAndroidError.HandleInvalidated(characteristicHandle)))
            return
        }

        // I012: single-central path uses the same per-central FIFO
        // queue; the aggregate degenerates to "complete on first
        // onNotificationSent for this central".
        try {
            enqueuePendingNotification(centralId, callback)
            sendNotification(server, device, characteristic, value)
        } catch (e: SecurityException) {
            callback(Result.failure(BlueyAndroidError.PermissionDenied("BLUETOOTH_CONNECT")))
        }
    }

    /**
     * Enqueues a per-central pending notification with the
     * [NOTIFY_SEND_TIMEOUT_MS] timer. Returns immediately; the entry
     * resolves either via [BluetoothGattServerCallback.onNotificationSent]
     * (which pops the head and cancels the timer) or via the timer
     * firing (which removes the entry by reference and fails it with
     * `gatt-timeout`). On `STATE_DISCONNECTED` the queue is drained
     * with `gatt-disconnected`. (I012)
     */
    private fun enqueuePendingNotification(
        centralId: String,
        onComplete: (Result<Unit>) -> Unit,
    ) {
        val pending = PendingNotification(onComplete)
        val timeoutRunnable = Runnable {
            val q = pendingNotifications[centralId] ?: return@Runnable
            if (q.remove(pending)) {
                pending.onComplete(Result.failure(
                    FlutterError(
                        "gatt-timeout",
                        "notify timed out for $centralId",
                        null,
                    ),
                ))
            }
        }
        pending.timeoutRunnable = timeoutRunnable
        pendingNotifications.getOrPut(centralId) { ArrayDeque() }.addLast(pending)
        handler.postDelayed(timeoutRunnable, NOTIFY_SEND_TIMEOUT_MS)
    }

    fun respondToReadRequest(
        requestId: Long,
        status: GattStatusDto,
        value: ByteArray?,
        callback: (Result<Unit>) -> Unit
    ) {
        val server = gattServer
        if (server == null) {
            callback(Result.failure(BlueyAndroidError.NotInitialized("GattServer")))
            return
        }

        val pending = pendingReadRequests.pop(requestId)
        if (pending == null) {
            callback(Result.failure(BlueyAndroidError.NoPendingRequest(requestId)))
            return
        }

        try {
            server.sendResponse(
                pending.device,
                pending.requestId,
                status.toAndroidStatus(),
                pending.offset,
                value ?: ByteArray(0)
            )
            callback(Result.success(Unit))
        } catch (e: SecurityException) {
            callback(Result.failure(BlueyAndroidError.PermissionDenied("BLUETOOTH_CONNECT")))
        }
    }

    fun respondToWriteRequest(
        requestId: Long,
        status: GattStatusDto,
        callback: (Result<Unit>) -> Unit
    ) {
        val server = gattServer
        if (server == null) {
            callback(Result.failure(BlueyAndroidError.NotInitialized("GattServer")))
            return
        }

        val pending = pendingWriteRequests.pop(requestId)
        if (pending == null) {
            callback(Result.failure(BlueyAndroidError.NoPendingRequest(requestId)))
            return
        }

        try {
            // ATT Write Response PDU carries no payload — pass null.
            server.sendResponse(
                pending.device,
                pending.requestId,
                status.toAndroidStatus(),
                pending.offset,
                null
            )
            callback(Result.success(Unit))
        } catch (e: SecurityException) {
            callback(Result.failure(BlueyAndroidError.PermissionDenied("BLUETOOTH_CONNECT")))
        }
    }

    fun disconnectCentral(centralId: String, callback: (Result<Unit>) -> Unit) {
        val server = gattServer
        if (server == null) {
            callback(Result.success(Unit))
            return
        }

        val device = connectedCentrals[centralId]
        if (device == null) {
            callback(Result.success(Unit))
            return
        }

        try {
            server.cancelConnection(device)
            callback(Result.success(Unit))
        } catch (e: SecurityException) {
            callback(Result.failure(BlueyAndroidError.PermissionDenied("BLUETOOTH_CONNECT")))
        }
    }

    fun cleanup() {
        Log.d("GattServer", "cleanup() called - disconnecting ${connectedCentrals.size} centrals")

        // Disconnect all connected centrals before closing the server
        val server = gattServer
        if (server != null) {
            try {
                for ((address, device) in connectedCentrals) {
                    Log.d("GattServer", "Disconnecting central: $address")
                    try {
                        server.cancelConnection(device)
                    } catch (e: SecurityException) {
                        Log.e("GattServer", "Failed to disconnect $address: ${e.message}")
                    }
                }
            } catch (e: Exception) {
                Log.e("GattServer", "Error disconnecting centrals: ${e.message}")
            }

            try {
                server.close()
                Log.d("GattServer", "GATT server closed")
            } catch (e: Exception) {
                Log.e("GattServer", "Error closing GATT server: ${e.message}")
            }
        }

        gattServer = null
        connectedCentrals.clear()
        centralMtus.clear()
        subscriptions.clear()
        pendingReadRequests.clear()
        pendingWriteRequests.clear()
        pendingServiceCallbacks.clear()
        pendingServiceDtos.clear()
        characteristicByHandle.clear()

        // I012: drain in-flight notifications so callers' Futures don't
        // hang past server teardown. Mirrors the I061 cleanup contract
        // for ConnectionManager.
        if (pendingNotifications.isNotEmpty()) {
            val err = FlutterError(
                "gatt-disconnected",
                "GATT server torn down with pending notification",
                null,
            )
            for ((_, queue) in pendingNotifications) {
                for (entry in queue) {
                    entry.timeoutRunnable?.let { handler.removeCallbacks(it) }
                    entry.onComplete(Result.failure(err))
                }
            }
            pendingNotifications.clear()
        }
    }

    /**
     * Debug method to log the current state of the GATT server.
     * Useful for diagnosing connection callback issues.
     */
    fun logServerState() {
        Log.d("GattServer", "=== GATT Server State ===")
        Log.d("GattServer", "GattServer instance: $this")
        Log.d("GattServer", "gattServer: $gattServer")
        Log.d("GattServer", "gattServerCallback: $gattServerCallback")
        Log.d("GattServer", "connectedCentrals: ${connectedCentrals.keys}")

        val server = gattServer
        if (server != null) {
            Log.d("GattServer", "Services count: ${server.services.size}")
            server.services.forEach { service ->
                Log.d("GattServer", "  Service: ${service.uuid}")
            }

            // Try to get connected devices via BluetoothManager
            try {
                val connectedDevices =
                    bluetoothManager?.getConnectedDevices(android.bluetooth.BluetoothProfile.GATT_SERVER)
                Log.d("GattServer", "BluetoothManager.getConnectedDevices(GATT_SERVER): $connectedDevices")
            } catch (e: SecurityException) {
                Log.d("GattServer", "Cannot get connected devices: ${e.message}")
            }
        }
        Log.d("GattServer", "=========================")
    }

    private fun ensureServerOpen() {
        if (gattServer != null) {
            Log.d("GattServer", "ensureServerOpen: server already open")
            return
        }

        if (!hasRequiredPermissions()) {
            Log.d("GattServer", "ensureServerOpen: missing permissions")
            return
        }

        try {
            Log.d("GattServer", "ensureServerOpen: opening GATT server with callback $gattServerCallback")

            // Try to open the GATT server, with retry on failure
            var server = bluetoothManager?.openGattServer(context, gattServerCallback)

            if (server == null) {
                Log.w("GattServer", "ensureServerOpen: first attempt failed, retrying after delay...")
                // Sometimes the Bluetooth stack needs a moment, especially after being enabled
                Thread.sleep(100)
                server = bluetoothManager?.openGattServer(context, gattServerCallback)
            }

            gattServer = server
            Log.d("GattServer", "ensureServerOpen: server opened = ${gattServer != null}")

            if (gattServer == null) {
                Log.e("GattServer", "ensureServerOpen: Failed to open GATT server - Bluetooth may not be fully ready")
            }
        } catch (e: SecurityException) {
            Log.e("GattServer", "ensureServerOpen: SecurityException", e)
        } catch (e: Exception) {
            Log.e("GattServer", "ensureServerOpen: Exception", e)
        }
    }

    private val gattServerCallback = object : BluetoothGattServerCallback() {
        init {
            Log.d("GattServer", "BluetoothGattServerCallback created: $this")
        }

        override fun onConnectionStateChange(device: BluetoothDevice, status: Int, newState: Int) {
            val deviceId = device.address
            Log.d(
                "GattServer",
                "onConnectionStateChange: device=$deviceId status=$status newState=$newState"
            )

            when (newState) {
                BluetoothProfile.STATE_CONNECTED -> {
                    val isNew = connectedCentrals[deviceId] == null
                    Log.d("GattServer", "Central connected: $deviceId (new=$isNew)")
                    connectedCentrals[deviceId] = device
                    centralMtus[deviceId] = DEFAULT_MTU

                    if (isNew) {
                        val central = CentralDto(
                            id = deviceId,
                            mtu = DEFAULT_MTU.toLong()
                        )
                        // Must dispatch to main thread for Flutter platform channel
                        handler.post {
                            flutterApi.onCentralConnected(central) {}
                        }
                    }
                }

                BluetoothProfile.STATE_DISCONNECTED -> {
                    Log.d("GattServer", "Central disconnected: $deviceId")
                    connectedCentrals.remove(deviceId)
                    centralMtus.remove(deviceId)

                    // Marshal the subscriptions cleanup to the main thread so
                    // it doesn't race with `notifyCharacteristic`'s iteration
                    // (I082). The defensive snapshot at the iteration entry
                    // is the immediate guard; this post is the architectural
                    // invariant — same single-threaded discipline as I062's
                    // ConnectionManager fix.
                    //
                    // I012: drain any in-flight notifications for this
                    // central with `gatt-disconnected` so the awaiting
                    // notify futures don't hang on an `onNotificationSent`
                    // that will never arrive.
                    handler.post {
                        subscriptions.values.forEach { it.remove(deviceId) }
                        val pending = pendingNotifications.remove(deviceId)
                        if (pending != null) {
                            val err = FlutterError(
                                "gatt-disconnected",
                                "central disconnected with pending notification",
                                null,
                            )
                            for (entry in pending) {
                                entry.timeoutRunnable?.let { handler.removeCallbacks(it) }
                                entry.onComplete(Result.failure(err))
                            }
                        }
                    }

                    // Drain pending ATT requests for this central — no point
                    // keeping them; sendResponse would fail once the device is gone.
                    // Runs synchronously inside the binder callback so the main
                    // thread cannot observe a partial disconnect state.
                    val drainedReads = pendingReadRequests.drainWhere { it.device.address == deviceId }
                    val drainedWrites = pendingWriteRequests.drainWhere { it.device.address == deviceId }
                    if (drainedReads.isNotEmpty() || drainedWrites.isNotEmpty()) {
                        Log.d(
                            "GattServer",
                            "Drained ${drainedReads.size} read(s) and ${drainedWrites.size} write(s) on disconnect of $deviceId"
                        )
                    }

                    // Must dispatch to main thread for Flutter platform channel.
                    handler.post {
                        flutterApi.onCentralDisconnected(deviceId) {}
                    }
                }
            }
        }

        override fun onServiceAdded(status: Int, service: BluetoothGattService) {
            Log.d("GattServer", "onServiceAdded: status=$status service=${service.uuid}")
            // Look up the caller by service UUID. Match the same lowercase
            // canonical form used as the key in addService.
            val key = service.uuid.toString().lowercase()
            val callback = pendingServiceCallbacks.remove(key)
            val populated = pendingServiceDtos.remove(key)

            if (callback != null) {
                if (status == BluetoothGatt.GATT_SUCCESS && populated != null) {
                    callback(Result.success(populated))
                } else {
                    callback(Result.failure(BlueyAndroidError.FailedToAddService(service.uuid.toString(), status)))
                }
            }
        }

        override fun onCharacteristicReadRequest(
            device: BluetoothDevice,
            requestId: Int,
            offset: Int,
            characteristic: BluetoothGattCharacteristic
        ) {
            Log.d("GattServer", "onCharacteristicReadRequest: device=${device.address} char=${characteristic.uuid} requestId=$requestId")

            // Stash pending entry BEFORE posting to Flutter so the main
            // thread can never see a respondToRead before the put has
            // happened. synchronized in the registry establishes
            // happens-before with the main-thread pop.
            pendingReadRequests.put(
                requestId.toLong(),
                PendingRead(device, requestId, offset)
            )

            // I088 D.13 — reverse-look-up the minted handle from our
            // local table. Falls back to instanceId for the auto-added
            // CCCDs / control-service paths that aren't in the DTO yet
            // — those still surface a stable identifier.
            val charHandle = handleForCharacteristic(characteristic)
                ?: characteristic.instanceId.toLong()
            val request = ReadRequestDto(
                requestId = requestId.toLong(),
                centralId = device.address,
                characteristicUuid = characteristic.uuid.toString(),
                offset = offset.toLong(),
                characteristicHandle = charHandle,
            )
            // Must dispatch to main thread for Flutter platform channel.
            handler.post {
                flutterApi.onReadRequest(request) {}
            }
            // Intentionally NO sendResponse here — Dart's respondToRead
            // is the only code path that sends the response.
        }

        override fun onCharacteristicWriteRequest(
            device: BluetoothDevice,
            requestId: Int,
            characteristic: BluetoothGattCharacteristic,
            preparedWrite: Boolean,
            responseNeeded: Boolean,
            offset: Int,
            value: ByteArray
        ) {
            Log.d("GattServer", "onCharacteristicWriteRequest: device=${device.address} char=${characteristic.uuid} requestId=$requestId preparedWrite=$preparedWrite responseNeeded=$responseNeeded")

            val charHandle = handleForCharacteristic(characteristic)
                ?: characteristic.instanceId.toLong()
            val request = WriteRequestDto(
                requestId = requestId.toLong(),
                centralId = device.address,
                characteristicUuid = characteristic.uuid.toString(),
                value = value,
                offset = offset.toLong(),
                responseNeeded = responseNeeded,
                characteristicHandle = charHandle,
            )

            // Stash only for the "simple write with response" path. The
            // responseNeeded=false path has no response to send, and the
            // preparedWrite=true path keeps its existing auto-respond echo
            // behavior (owned by I050).
            if (responseNeeded && !preparedWrite) {
                pendingWriteRequests.put(
                    requestId.toLong(),
                    PendingWrite(device, requestId, offset, value)
                )
            }

            handler.post {
                flutterApi.onWriteRequest(request) {}
            }

            // Preserved auto-respond path for prepared writes (I050).
            if (responseNeeded && preparedWrite) {
                try {
                    gattServer?.sendResponse(
                        device,
                        requestId,
                        BluetoothGatt.GATT_SUCCESS,
                        offset,
                        value
                    )
                } catch (e: SecurityException) {
                    // Permission revoked.
                }
            }
        }

        override fun onDescriptorReadRequest(
            device: BluetoothDevice,
            requestId: Int,
            offset: Int,
            descriptor: BluetoothGattDescriptor
        ) {
            Log.d("GattServer", "onDescriptorReadRequest: device=${device.address} desc=${descriptor.uuid}")
            try {
                gattServer?.sendResponse(
                    device,
                    requestId,
                    BluetoothGatt.GATT_SUCCESS,
                    offset,
                    descriptor.value ?: ByteArray(0)
                )
            } catch (e: SecurityException) {
                // Permission revoked
            }
        }

        override fun onDescriptorWriteRequest(
            device: BluetoothDevice,
            requestId: Int,
            descriptor: BluetoothGattDescriptor,
            preparedWrite: Boolean,
            responseNeeded: Boolean,
            offset: Int,
            value: ByteArray
        ) {
            Log.d("GattServer", "onDescriptorWriteRequest: device=${device.address} desc=${descriptor.uuid}")
            // Check if this is a CCCD write (subscription change)
            if (descriptor.uuid == CCCD_UUID) {
                val characteristicUuid = descriptor.characteristic.uuid.toString()
                val centralId = device.address

                val isSubscribing = value.contentEquals(BluetoothGattDescriptor.ENABLE_NOTIFICATION_VALUE) ||
                        value.contentEquals(BluetoothGattDescriptor.ENABLE_INDICATION_VALUE)
                val isUnsubscribing = value.contentEquals(BluetoothGattDescriptor.DISABLE_NOTIFICATION_VALUE)

                // CCCD subscribe / unsubscribe mutates `subscriptions`,
                // which is read on the main thread by `notifyCharacteristic`.
                // Marshal the mutation onto the main thread alongside the
                // existing flutterApi notification so the threading invariant
                // holds (I082).
                if (isSubscribing) {
                    handler.post {
                        subscriptions.getOrPut(characteristicUuid) { mutableSetOf() }
                            .add(centralId)
                        flutterApi.onCharacteristicSubscribed(centralId, characteristicUuid) {}
                    }
                } else if (isUnsubscribing) {
                    handler.post {
                        subscriptions[characteristicUuid]?.remove(centralId)
                        flutterApi.onCharacteristicUnsubscribed(centralId, characteristicUuid) {}
                    }
                }
            }

            if (responseNeeded) {
                try {
                    gattServer?.sendResponse(
                        device,
                        requestId,
                        BluetoothGatt.GATT_SUCCESS,
                        offset,
                        value
                    )
                } catch (e: SecurityException) {
                    // Permission revoked
                }
            }
        }

        override fun onMtuChanged(device: BluetoothDevice, mtu: Int) {
            Log.d("GattServer", "onMtuChanged: device=${device.address} mtu=$mtu")
            centralMtus[device.address] = mtu
        }

        override fun onNotificationSent(device: BluetoothDevice, status: Int) {
            Log.d("GattServer", "onNotificationSent: device=${device.address} status=$status")
            // I012: pop the FIFO head for this central and complete its
            // notify. Fires on a binder thread; marshal to main so the
            // pendingNotifications map is only mutated on the main looper
            // (matches the I062 / I082 single-threaded discipline).
            val deviceId = device.address
            handler.post {
                val queue = pendingNotifications[deviceId] ?: return@post
                val pending = queue.removeFirstOrNull() ?: return@post
                if (queue.isEmpty()) pendingNotifications.remove(deviceId)
                pending.timeoutRunnable?.let { handler.removeCallbacks(it) }
                val result = if (status == BluetoothGatt.GATT_SUCCESS) {
                    Result.success(Unit)
                } else {
                    Result.failure(
                        FlutterError(
                            "gatt-status-failed",
                            "Notify failed with status: $status",
                            status,
                        ),
                    )
                }
                pending.onComplete(result)
            }
        }

        override fun onPhyUpdate(device: BluetoothDevice, txPhy: Int, rxPhy: Int, status: Int) {
            Log.d("GattServer", "onPhyUpdate: device=${device.address} txPhy=$txPhy rxPhy=$rxPhy status=$status")
        }

        override fun onPhyRead(device: BluetoothDevice, txPhy: Int, rxPhy: Int, status: Int) {
            Log.d("GattServer", "onPhyRead: device=${device.address} txPhy=$txPhy rxPhy=$rxPhy status=$status")
        }
    }

    private fun createGattService(
        dto: LocalServiceDto,
        outBuiltChars: MutableList<BluetoothGattCharacteristic>? = null,
    ): BluetoothGattService {
        val serviceType = if (dto.isPrimary) {
            BluetoothGattService.SERVICE_TYPE_PRIMARY
        } else {
            BluetoothGattService.SERVICE_TYPE_SECONDARY
        }

        val service = BluetoothGattService(
            UUID.fromString(normalizeUuid(dto.uuid)),
            serviceType
        )

        // Add characteristics
        for (charDto in dto.characteristics) {
            val characteristic = createGattCharacteristic(charDto)
            service.addCharacteristic(characteristic)
            outBuiltChars?.add(characteristic)
        }

        // Add included services
        for (includedDto in dto.includedServices) {
            val includedService = createGattService(includedDto)
            service.addService(includedService)
        }

        return service
    }

    private fun createGattCharacteristic(dto: LocalCharacteristicDto): BluetoothGattCharacteristic {
        var properties = 0
        if (dto.properties.canRead) properties = properties or BluetoothGattCharacteristic.PROPERTY_READ
        if (dto.properties.canWrite) properties = properties or BluetoothGattCharacteristic.PROPERTY_WRITE
        if (dto.properties.canWriteWithoutResponse) properties =
            properties or BluetoothGattCharacteristic.PROPERTY_WRITE_NO_RESPONSE
        if (dto.properties.canNotify) properties = properties or BluetoothGattCharacteristic.PROPERTY_NOTIFY
        if (dto.properties.canIndicate) properties = properties or BluetoothGattCharacteristic.PROPERTY_INDICATE

        var permissions = 0
        for (perm in dto.permissions) {
            permissions = permissions or when (perm) {
                GattPermissionDto.READ -> BluetoothGattCharacteristic.PERMISSION_READ
                GattPermissionDto.READ_ENCRYPTED -> BluetoothGattCharacteristic.PERMISSION_READ_ENCRYPTED
                GattPermissionDto.WRITE -> BluetoothGattCharacteristic.PERMISSION_WRITE
                GattPermissionDto.WRITE_ENCRYPTED -> BluetoothGattCharacteristic.PERMISSION_WRITE_ENCRYPTED
            }
        }

        val characteristic = BluetoothGattCharacteristic(
            UUID.fromString(normalizeUuid(dto.uuid)),
            properties,
            permissions
        )

        // Add descriptors
        for (descDto in dto.descriptors) {
            val descriptor = createGattDescriptor(descDto)
            characteristic.addDescriptor(descriptor)
        }

        // Add CCCD if notify or indicate is enabled
        if (dto.properties.canNotify || dto.properties.canIndicate) {
            val cccd = BluetoothGattDescriptor(
                CCCD_UUID,
                BluetoothGattDescriptor.PERMISSION_READ or BluetoothGattDescriptor.PERMISSION_WRITE
            )
            characteristic.addDescriptor(cccd)
        }

        return characteristic
    }

    private fun createGattDescriptor(dto: LocalDescriptorDto): BluetoothGattDescriptor {
        var permissions = 0
        for (perm in dto.permissions) {
            permissions = permissions or when (perm) {
                GattPermissionDto.READ -> BluetoothGattDescriptor.PERMISSION_READ
                GattPermissionDto.READ_ENCRYPTED -> BluetoothGattDescriptor.PERMISSION_READ_ENCRYPTED
                GattPermissionDto.WRITE -> BluetoothGattDescriptor.PERMISSION_WRITE
                GattPermissionDto.WRITE_ENCRYPTED -> BluetoothGattDescriptor.PERMISSION_WRITE_ENCRYPTED
            }
        }

        val descriptor = BluetoothGattDescriptor(
            UUID.fromString(normalizeUuid(dto.uuid)),
            permissions
        )

        dto.value?.let { descriptor.value = it }

        return descriptor
    }

    private fun sendNotification(
        server: BluetoothGattServer,
        device: BluetoothDevice,
        characteristic: BluetoothGattCharacteristic,
        value: ByteArray
    ) {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
            server.notifyCharacteristicChanged(device, characteristic, false, value)
        } else {
            @Suppress("DEPRECATION")
            characteristic.value = value
            @Suppress("DEPRECATION")
            server.notifyCharacteristicChanged(device, characteristic, false)
        }
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
                Manifest.permission.BLUETOOTH_CONNECT
            ) == PackageManager.PERMISSION_GRANTED &&
                    ContextCompat.checkSelfPermission(
                        context,
                        Manifest.permission.BLUETOOTH_ADVERTISE
                    ) == PackageManager.PERMISSION_GRANTED
        }
        return true
    }
}
