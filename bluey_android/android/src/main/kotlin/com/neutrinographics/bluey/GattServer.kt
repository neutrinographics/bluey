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

    // Track connected centrals
    private val connectedCentrals = mutableMapOf<String, BluetoothDevice>()
    private val centralMtus = mutableMapOf<String, Int>()

    // Track notification subscriptions: characteristicUuid -> Set<centralId>
    private val subscriptions = mutableMapOf<String, MutableSet<String>>()

    // Pending callbacks for async service addition
    private var pendingServiceCallback: ((Result<Unit>) -> Unit)? = null

    // CCCD UUID for notifications/indications
    companion object {
        private val CCCD_UUID = UUID.fromString("00002902-0000-1000-8000-00805f9b34fb")
        private const val DEFAULT_MTU = 23
    }

    fun setActivity(activity: Activity?) {
        this.activity = activity
    }

    fun addService(service: LocalServiceDto, callback: (Result<Unit>) -> Unit) {
        android.util.Log.d("Bluey", "addService: uuid=${service.uuid}")
        if (!hasRequiredPermissions()) {
            android.util.Log.e("Bluey", "addService: missing permissions")
            callback(Result.failure(SecurityException("Missing required permissions")))
            return
        }

        ensureServerOpen()
        val server = gattServer
        if (server == null) {
            android.util.Log.e("Bluey", "addService: gattServer is null after ensureServerOpen")
            callback(Result.failure(IllegalStateException("Failed to open GATT server")))
            return
        }

        val gattService = createGattService(service)
        android.util.Log.d(
            "Bluey",
            "addService: created gattService with ${gattService.characteristics.size} characteristics"
        )
        pendingServiceCallback = callback

        try {
            val result = server.addService(gattService)
            android.util.Log.d("Bluey", "addService: server.addService returned $result")
            if (!result) {
                pendingServiceCallback = null
                callback(Result.failure(IllegalStateException("Failed to add service")))
            }
            // Callback will be invoked in onServiceAdded
        } catch (e: SecurityException) {
            android.util.Log.e("Bluey", "addService: SecurityException", e)
            pendingServiceCallback = null
            callback(Result.failure(e))
        }
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
                server.removeService(service)
            }
            callback(Result.success(Unit))
        } catch (e: SecurityException) {
            callback(Result.failure(e))
        } catch (e: Exception) {
            callback(Result.failure(e))
        }
    }

    fun notifyCharacteristic(
        characteristicUuid: String,
        value: ByteArray,
        callback: (Result<Unit>) -> Unit
    ) {
        val server = gattServer
        if (server == null) {
            callback(Result.failure(IllegalStateException("GATT server not running")))
            return
        }

        val normalizedUuid = normalizeUuid(characteristicUuid)
        val characteristic = findCharacteristic(normalizedUuid)
        if (characteristic == null) {
            callback(Result.failure(IllegalStateException("Characteristic not found: $characteristicUuid")))
            return
        }

        // Get subscribed centrals for this characteristic
        val subscribedCentralIds = subscriptions[normalizedUuid] ?: emptySet()
        if (subscribedCentralIds.isEmpty()) {
            callback(Result.success(Unit))
            return
        }

        try {
            for (centralId in subscribedCentralIds) {
                val device = connectedCentrals[centralId] ?: continue
                sendNotification(server, device, characteristic, value)
            }
            callback(Result.success(Unit))
        } catch (e: SecurityException) {
            callback(Result.failure(e))
        }
    }

    fun notifyCharacteristicTo(
        centralId: String,
        characteristicUuid: String,
        value: ByteArray,
        callback: (Result<Unit>) -> Unit
    ) {
        val server = gattServer
        if (server == null) {
            callback(Result.failure(IllegalStateException("GATT server not running")))
            return
        }

        val device = connectedCentrals[centralId]
        if (device == null) {
            callback(Result.failure(IllegalStateException("Central not connected: $centralId")))
            return
        }

        val normalizedUuid = normalizeUuid(characteristicUuid)
        val characteristic = findCharacteristic(normalizedUuid)
        if (characteristic == null) {
            callback(Result.failure(IllegalStateException("Characteristic not found: $characteristicUuid")))
            return
        }

        try {
            sendNotification(server, device, characteristic, value)
            callback(Result.success(Unit))
        } catch (e: SecurityException) {
            callback(Result.failure(e))
        }
    }

    fun respondToReadRequest(
        requestId: Long,
        status: GattStatusDto,
        value: ByteArray?,
        callback: (Result<Unit>) -> Unit
    ) {
        val server = gattServer
        if (server == null) {
            callback(Result.failure(IllegalStateException("GATT server not running")))
            return
        }

        // requestId encodes both the device hashcode and offset
        // For simplicity, we store pending requests with device reference
        // This is a simplified implementation - a production version would
        // track pending requests with their associated device
        callback(Result.success(Unit))
    }

    fun respondToWriteRequest(
        requestId: Long,
        status: GattStatusDto,
        callback: (Result<Unit>) -> Unit
    ) {
        val server = gattServer
        if (server == null) {
            callback(Result.failure(IllegalStateException("GATT server not running")))
            return
        }

        callback(Result.success(Unit))
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
            callback(Result.failure(e))
        }
    }

    fun cleanup() {
        try {
            gattServer?.close()
        } catch (e: Exception) {
            // Ignore errors during cleanup
        }
        gattServer = null
        connectedCentrals.clear()
        centralMtus.clear()
        subscriptions.clear()
        pendingServiceCallback = null
    }

    private fun ensureServerOpen() {
        if (gattServer != null) {
            android.util.Log.d("Bluey", "ensureServerOpen: server already open")
            return
        }

        if (!hasRequiredPermissions()) {
            android.util.Log.e("Bluey", "ensureServerOpen: missing permissions")
            return
        }

        try {
            android.util.Log.d("Bluey", "ensureServerOpen: opening GATT server")
            gattServer = bluetoothManager?.openGattServer(context, gattServerCallback)
            android.util.Log.d("Bluey", "ensureServerOpen: gattServer=$gattServer")
        } catch (e: SecurityException) {
            android.util.Log.e("Bluey", "ensureServerOpen: SecurityException", e)
        }
    }

    private val gattServerCallback = object : BluetoothGattServerCallback() {
        override fun onConnectionStateChange(device: BluetoothDevice, status: Int, newState: Int) {
            val deviceId = device.address

            when (newState) {
                BluetoothProfile.STATE_CONNECTED -> {
                    connectedCentrals[deviceId] = device
                    centralMtus[deviceId] = DEFAULT_MTU

                    val central = CentralDto(
                        id = deviceId,
                        mtu = DEFAULT_MTU.toLong()
                    )
                    // Must dispatch to main thread for Flutter platform channel
                    handler.post {
                        flutterApi.onCentralConnected(central) {}
                    }
                }

                BluetoothProfile.STATE_DISCONNECTED -> {
                    connectedCentrals.remove(deviceId)
                    centralMtus.remove(deviceId)

                    // Remove from all subscriptions
                    subscriptions.values.forEach { it.remove(deviceId) }

                    // Must dispatch to main thread for Flutter platform channel
                    handler.post {
                        flutterApi.onCentralDisconnected(deviceId) {}
                    }
                }
            }
        }

        override fun onServiceAdded(status: Int, service: BluetoothGattService) {
            val callback = pendingServiceCallback
            pendingServiceCallback = null

            if (callback != null) {
                if (status == BluetoothGatt.GATT_SUCCESS) {
                    callback(Result.success(Unit))
                } else {
                    callback(Result.failure(IllegalStateException("Failed to add service, status: $status")))
                }
            }
        }

        override fun onCharacteristicReadRequest(
            device: BluetoothDevice,
            requestId: Int,
            offset: Int,
            characteristic: BluetoothGattCharacteristic
        ) {
            val request = ReadRequestDto(
                requestId = requestId.toLong(),
                centralId = device.address,
                characteristicUuid = characteristic.uuid.toString(),
                offset = offset.toLong()
            )
            // Must dispatch to main thread for Flutter platform channel
            handler.post {
                flutterApi.onReadRequest(request) {}
            }

            // Auto-respond with success for now (simplified implementation)
            // A production version would wait for respondToReadRequest
            try {
                gattServer?.sendResponse(
                    device,
                    requestId,
                    BluetoothGatt.GATT_SUCCESS,
                    offset,
                    characteristic.value ?: ByteArray(0)
                )
            } catch (e: SecurityException) {
                // Permission revoked
            }
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
            val request = WriteRequestDto(
                requestId = requestId.toLong(),
                centralId = device.address,
                characteristicUuid = characteristic.uuid.toString(),
                value = value,
                offset = offset.toLong(),
                responseNeeded = responseNeeded
            )
            // Must dispatch to main thread for Flutter platform channel
            handler.post {
                flutterApi.onWriteRequest(request) {}
            }

            // Auto-respond if needed (simplified implementation)
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

        override fun onDescriptorReadRequest(
            device: BluetoothDevice,
            requestId: Int,
            offset: Int,
            descriptor: BluetoothGattDescriptor
        ) {
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
            // Check if this is a CCCD write (subscription change)
            if (descriptor.uuid == CCCD_UUID) {
                val characteristicUuid = descriptor.characteristic.uuid.toString()
                val centralId = device.address

                val isSubscribing = value.contentEquals(BluetoothGattDescriptor.ENABLE_NOTIFICATION_VALUE) ||
                        value.contentEquals(BluetoothGattDescriptor.ENABLE_INDICATION_VALUE)
                val isUnsubscribing = value.contentEquals(BluetoothGattDescriptor.DISABLE_NOTIFICATION_VALUE)

                if (isSubscribing) {
                    subscriptions.getOrPut(characteristicUuid) { mutableSetOf() }.add(centralId)
                    // Must dispatch to main thread for Flutter platform channel
                    handler.post {
                        flutterApi.onCharacteristicSubscribed(centralId, characteristicUuid) {}
                    }
                } else if (isUnsubscribing) {
                    subscriptions[characteristicUuid]?.remove(centralId)
                    // Must dispatch to main thread for Flutter platform channel
                    handler.post {
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
            centralMtus[device.address] = mtu
        }

        override fun onNotificationSent(device: BluetoothDevice, status: Int) {
            // Notification was sent - could track for reliability
        }
    }

    private fun createGattService(dto: LocalServiceDto): BluetoothGattService {
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

    private fun findCharacteristic(uuid: String): BluetoothGattCharacteristic? {
        val server = gattServer ?: return null

        for (service in server.services) {
            for (characteristic in service.characteristics) {
                if (characteristic.uuid.toString().equals(uuid, ignoreCase = true)) {
                    return characteristic
                }
            }
        }
        return null
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
