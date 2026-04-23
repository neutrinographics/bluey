package com.neutrinographics.bluey

import android.bluetooth.BluetoothGatt
import org.junit.Assert.assertEquals
import org.junit.Test

class GattStatusMappingTest {

    @Test
    fun `SUCCESS maps to GATT_SUCCESS`() {
        assertEquals(BluetoothGatt.GATT_SUCCESS, GattStatusDto.SUCCESS.toAndroidStatus())
    }

    @Test
    fun `READ_NOT_PERMITTED maps to GATT_READ_NOT_PERMITTED`() {
        assertEquals(
            BluetoothGatt.GATT_READ_NOT_PERMITTED,
            GattStatusDto.READ_NOT_PERMITTED.toAndroidStatus()
        )
    }

    @Test
    fun `WRITE_NOT_PERMITTED maps to GATT_WRITE_NOT_PERMITTED`() {
        assertEquals(
            BluetoothGatt.GATT_WRITE_NOT_PERMITTED,
            GattStatusDto.WRITE_NOT_PERMITTED.toAndroidStatus()
        )
    }

    @Test
    fun `INVALID_OFFSET maps to GATT_INVALID_OFFSET`() {
        assertEquals(
            BluetoothGatt.GATT_INVALID_OFFSET,
            GattStatusDto.INVALID_OFFSET.toAndroidStatus()
        )
    }

    @Test
    fun `INVALID_ATTRIBUTE_LENGTH maps to GATT_INVALID_ATTRIBUTE_LENGTH`() {
        assertEquals(
            BluetoothGatt.GATT_INVALID_ATTRIBUTE_LENGTH,
            GattStatusDto.INVALID_ATTRIBUTE_LENGTH.toAndroidStatus()
        )
    }

    @Test
    fun `INSUFFICIENT_AUTHENTICATION maps to GATT_INSUFFICIENT_AUTHENTICATION`() {
        assertEquals(
            BluetoothGatt.GATT_INSUFFICIENT_AUTHENTICATION,
            GattStatusDto.INSUFFICIENT_AUTHENTICATION.toAndroidStatus()
        )
    }

    @Test
    fun `INSUFFICIENT_ENCRYPTION maps to GATT_INSUFFICIENT_ENCRYPTION`() {
        assertEquals(
            BluetoothGatt.GATT_INSUFFICIENT_ENCRYPTION,
            GattStatusDto.INSUFFICIENT_ENCRYPTION.toAndroidStatus()
        )
    }

    @Test
    fun `REQUEST_NOT_SUPPORTED maps to GATT_REQUEST_NOT_SUPPORTED`() {
        assertEquals(
            BluetoothGatt.GATT_REQUEST_NOT_SUPPORTED,
            GattStatusDto.REQUEST_NOT_SUPPORTED.toAndroidStatus()
        )
    }
}
