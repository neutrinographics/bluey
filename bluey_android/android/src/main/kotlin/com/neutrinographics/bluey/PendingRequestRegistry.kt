package com.neutrinographics.bluey

import android.bluetooth.BluetoothDevice
import android.bluetooth.BluetoothGatt

/**
 * Thread-safe map of outstanding ATT requests awaiting a Dart-side response.
 *
 * Binder-thread callbacks [put] entries; main-thread Pigeon handlers [pop]
 * them when Dart calls respondTo{Read,Write}. [drainWhere] is called on
 * central disconnect; [clear] is called on server cleanup.
 *
 * All operations are guarded by [lock]. Collections returned by
 * [drainWhere] and [clear] are snapshots detached from internal state;
 * no live views escape the lock. See the thread-safety argument in the
 * design spec for the full invariant set.
 *
 * Predicates passed to [drainWhere] run under the lock — they MUST be
 * O(1) and non-reentrant (no calls back into this registry).
 */
internal class PendingRequestRegistry<T> {
    private val lock = Any()
    private val entries = HashMap<Long, T>()

    fun put(id: Long, entry: T) = synchronized(lock) {
        entries[id] = entry
    }

    fun pop(id: Long): T? = synchronized(lock) {
        entries.remove(id)
    }

    fun drainWhere(predicate: (T) -> Boolean): List<T> = synchronized(lock) {
        val matched = entries.filterValues(predicate)
        matched.keys.forEach { entries.remove(it) }
        matched.values.toList()
    }

    fun clear(): List<T> = synchronized(lock) {
        val all = entries.values.toList()
        entries.clear()
        all
    }

    val size: Int get() = synchronized(lock) { entries.size }
}

internal data class PendingRead(
    val device: BluetoothDevice,
    val requestId: Int,
    val offset: Int,
)

internal data class PendingWrite(
    val device: BluetoothDevice,
    val requestId: Int,
    val offset: Int,
    /**
     * Reserved for prepared-write flow (I050); unused in the current
     * response path since ATT write responses carry no payload.
     * MUST NOT be mutated after construction — the registry's
     * thread-safety argument assumes immutability of stored entries.
     */
    val value: ByteArray,
)

internal fun GattStatusDto.toAndroidStatus(): Int = when (this) {
    GattStatusDto.SUCCESS -> BluetoothGatt.GATT_SUCCESS
    GattStatusDto.READ_NOT_PERMITTED -> BluetoothGatt.GATT_READ_NOT_PERMITTED
    GattStatusDto.WRITE_NOT_PERMITTED -> BluetoothGatt.GATT_WRITE_NOT_PERMITTED
    GattStatusDto.INVALID_OFFSET -> BluetoothGatt.GATT_INVALID_OFFSET
    GattStatusDto.INVALID_ATTRIBUTE_LENGTH -> BluetoothGatt.GATT_INVALID_ATTRIBUTE_LENGTH
    GattStatusDto.INSUFFICIENT_AUTHENTICATION -> BluetoothGatt.GATT_INSUFFICIENT_AUTHENTICATION
    GattStatusDto.INSUFFICIENT_ENCRYPTION -> BluetoothGatt.GATT_INSUFFICIENT_ENCRYPTION
    GattStatusDto.REQUEST_NOT_SUPPORTED -> BluetoothGatt.GATT_REQUEST_NOT_SUPPORTED
}
