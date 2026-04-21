package com.neutrinographics.bluey

import android.bluetooth.BluetoothGatt
import android.bluetooth.BluetoothGattCharacteristic
import android.bluetooth.BluetoothGattDescriptor
import android.os.Build

/**
 * A serialized GATT command. Each subclass knows how to initiate itself on a
 * [BluetoothGatt] handle and how to deliver the result to its caller.
 *
 * Instances are Command objects (Command pattern) — they carry a user
 * callback executed exactly once. Configuration fields are immutable after
 * construction.
 */
// NOTE: declared `abstract class` rather than `sealed class` even though
// the set of subclasses is known and closed. Two Kotlin constraints force
// this choice:
//   1. Sealed classes permit subclassing only within the same module.
//      Android Gradle treats main and test sourcesets as separate Kotlin
//      modules, so a sealed GattOp would reject test-only subclasses
//      declared in GattOpQueueTest.kt.
//   2. Sealed classes cannot be extended via anonymous objects at all.
//      Several unit tests use `object : GattOp() { ... }` to capture
//      local state via closure (see GattOpQueueTest.kt reentrancy test).
// The `internal` modifier is sufficient to prevent external extension;
// all production subclasses are declared in this file.
internal abstract class GattOp {
    /** Human-readable description for error messages, e.g. "Write characteristic". */
    abstract val description: String

    /** Timeout in milliseconds. Sourced from ConnectionManager configuration. */
    abstract val timeoutMs: Long

    /**
     * Initiates the op on the provided GATT handle.
     *
     * @return `true` if the OS accepted the request (async completion pending),
     *         `false` if synchronously rejected. On `false`, the queue fails
     *         the callback with an [IllegalStateException] and advances.
     */
    abstract fun execute(gatt: BluetoothGatt): Boolean

    /**
     * Delivers the op's outcome to the caller. Called on successful
     * [android.bluetooth.BluetoothGattCallback] completion, timeout,
     * synchronous rejection, or queue drain on disconnect.
     */
    abstract fun complete(result: Result<Any?>)
}

internal class ReadCharacteristicOp(
    private val characteristic: BluetoothGattCharacteristic,
    private val callback: (Result<ByteArray>) -> Unit,
    override val timeoutMs: Long,
) : GattOp() {
    override val description = "Read characteristic"
    override fun execute(gatt: BluetoothGatt): Boolean = gatt.readCharacteristic(characteristic)
    @Suppress("UNCHECKED_CAST")
    override fun complete(result: Result<Any?>) {
        callback(result.map { it as ByteArray })
    }
}

internal class WriteCharacteristicOp(
    private val characteristic: BluetoothGattCharacteristic,
    private val value: ByteArray,
    private val writeType: Int,
    private val callback: (Result<Unit>) -> Unit,
    override val timeoutMs: Long,
) : GattOp() {
    override val description = "Write characteristic"
    override fun execute(gatt: BluetoothGatt): Boolean {
        return if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
            gatt.writeCharacteristic(characteristic, value, writeType) == BluetoothGatt.GATT_SUCCESS
        } else {
            @Suppress("DEPRECATION")
            characteristic.writeType = writeType
            @Suppress("DEPRECATION")
            characteristic.value = value
            @Suppress("DEPRECATION")
            gatt.writeCharacteristic(characteristic)
        }
    }
    override fun complete(result: Result<Any?>) {
        callback(result.map { Unit })
    }
}

internal class ReadDescriptorOp(
    private val descriptor: BluetoothGattDescriptor,
    private val callback: (Result<ByteArray>) -> Unit,
    override val timeoutMs: Long,
) : GattOp() {
    override val description = "Read descriptor"
    override fun execute(gatt: BluetoothGatt): Boolean = gatt.readDescriptor(descriptor)
    @Suppress("UNCHECKED_CAST")
    override fun complete(result: Result<Any?>) {
        callback(result.map { it as ByteArray })
    }
}

internal class WriteDescriptorOp(
    private val descriptor: BluetoothGattDescriptor,
    private val value: ByteArray,
    private val callback: (Result<Unit>) -> Unit,
    override val timeoutMs: Long,
) : GattOp() {
    override val description = "Write descriptor"
    override fun execute(gatt: BluetoothGatt): Boolean {
        return if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
            gatt.writeDescriptor(descriptor, value) == BluetoothGatt.GATT_SUCCESS
        } else {
            @Suppress("DEPRECATION")
            descriptor.value = value
            @Suppress("DEPRECATION")
            gatt.writeDescriptor(descriptor)
        }
    }
    override fun complete(result: Result<Any?>) {
        callback(result.map { Unit })
    }
}

internal class EnableNotifyCccdOp(
    private val descriptor: BluetoothGattDescriptor,
    private val value: ByteArray,
    private val callback: (Result<Unit>) -> Unit,
    override val timeoutMs: Long,
) : GattOp() {
    override val description = "Enable notify CCCD"
    override fun execute(gatt: BluetoothGatt): Boolean {
        return if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
            gatt.writeDescriptor(descriptor, value) == BluetoothGatt.GATT_SUCCESS
        } else {
            @Suppress("DEPRECATION")
            descriptor.value = value
            @Suppress("DEPRECATION")
            gatt.writeDescriptor(descriptor)
        }
    }
    override fun complete(result: Result<Any?>) {
        callback(result.map { Unit })
    }
}

internal class DiscoverServicesOp(
    private val callback: (Result<Unit>) -> Unit,
    override val timeoutMs: Long,
) : GattOp() {
    override val description = "Service discovery"
    override fun execute(gatt: BluetoothGatt): Boolean = gatt.discoverServices()
    override fun complete(result: Result<Any?>) {
        callback(result.map { Unit })
    }
}

internal class RequestMtuOp(
    private val mtu: Int,
    private val callback: (Result<Long>) -> Unit,
    override val timeoutMs: Long,
) : GattOp() {
    override val description = "MTU request"
    override fun execute(gatt: BluetoothGatt): Boolean = gatt.requestMtu(mtu)
    @Suppress("UNCHECKED_CAST")
    override fun complete(result: Result<Any?>) {
        callback(result.map { it as Long })
    }
}

internal class ReadRssiOp(
    private val callback: (Result<Long>) -> Unit,
    override val timeoutMs: Long,
) : GattOp() {
    override val description = "RSSI read"
    override fun execute(gatt: BluetoothGatt): Boolean = gatt.readRemoteRssi()
    @Suppress("UNCHECKED_CAST")
    override fun complete(result: Result<Any?>) {
        callback(result.map { it as Long })
    }
}
