package com.neutrinographics.bluey

import android.Manifest
import android.app.Activity
import android.bluetooth.BluetoothAdapter
import android.bluetooth.BluetoothManager
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.content.IntentFilter
import android.content.pm.PackageManager
import android.os.Build
import android.provider.Settings
import androidx.core.app.ActivityCompat
import androidx.core.content.ContextCompat
import io.flutter.embedding.engine.plugins.FlutterPlugin
import io.flutter.embedding.engine.plugins.activity.ActivityAware
import io.flutter.embedding.engine.plugins.activity.ActivityPluginBinding
import io.flutter.plugin.common.PluginRegistry

/**
 * BlueyPlugin - Android implementation of Bluey BLE library.
 *
 * This follows Clean Architecture principles:
 * - Implements the platform interface defined via Pigeon
 * - Delegates to domain-specific classes (Scanner, ConnectionManager)
 * - Manages lifecycle and permissions
 */
class BlueyPlugin : FlutterPlugin, ActivityAware, BlueyHostApi, PluginRegistry.RequestPermissionsResultListener {
    private var context: Context? = null
    private var activity: Activity? = null
    private var activityBinding: ActivityPluginBinding? = null
    private var flutterApi: BlueyFlutterApi? = null

    private var bluetoothManager: BluetoothManager? = null
    private var bluetoothAdapter: BluetoothAdapter? = null

    private var scanner: Scanner? = null
    private var connectionManager: ConnectionManager? = null
    private var gattServer: GattServer? = null
    private var advertiser: Advertiser? = null

    // Bluetooth state receiver
    private var bluetoothStateReceiver: BroadcastReceiver? = null

    // Permission request callback
    private var permissionCallback: ((Result<Boolean>) -> Unit)? = null

    // FlutterPlugin implementation

    override fun onAttachedToEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        android.util.Log.d("BlueyPlugin", "onAttachedToEngine called")
        context = binding.applicationContext

        // Set up Pigeon APIs
        BlueyHostApi.setUp(binding.binaryMessenger, this)
        flutterApi = BlueyFlutterApi(binding.binaryMessenger)

        // Initialize Bluetooth
        bluetoothManager = context?.getSystemService(Context.BLUETOOTH_SERVICE) as? BluetoothManager
        bluetoothAdapter = bluetoothManager?.adapter

        // Initialize domain components
        scanner = Scanner(
            context = context!!,
            bluetoothAdapter = bluetoothAdapter,
            flutterApi = flutterApi!!
        )

        connectionManager = ConnectionManager(
            context = context!!,
            bluetoothAdapter = bluetoothAdapter,
            flutterApi = flutterApi!!
        )

        gattServer = GattServer(
            context = context!!,
            bluetoothManager = bluetoothManager,
            flutterApi = flutterApi!!
        )

        advertiser = Advertiser(
            context = context!!,
            bluetoothAdapter = bluetoothAdapter
        )

        // Start monitoring Bluetooth state
        startBluetoothStateMonitoring()
    }

    override fun onDetachedFromEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        BlueyHostApi.setUp(binding.binaryMessenger, null)

        // Stop Bluetooth state monitoring
        stopBluetoothStateMonitoring()

        // Clean up
        scanner?.cleanup()
        connectionManager?.cleanup()
        gattServer?.cleanup()
        advertiser?.cleanup()

        scanner = null
        connectionManager = null
        gattServer = null
        advertiser = null
        context = null
        flutterApi = null
    }

    // ActivityAware implementation

    override fun onAttachedToActivity(binding: ActivityPluginBinding) {
        activity = binding.activity
        activityBinding = binding
        binding.addRequestPermissionsResultListener(this)
        scanner?.setActivity(activity)
        connectionManager?.setActivity(activity)
        gattServer?.setActivity(activity)
        advertiser?.setActivity(activity)
    }

    override fun onDetachedFromActivityForConfigChanges() {
        activityBinding?.removeRequestPermissionsResultListener(this)
        activityBinding = null
        activity = null
    }

    override fun onReattachedToActivityForConfigChanges(binding: ActivityPluginBinding) {
        activity = binding.activity
        activityBinding = binding
        binding.addRequestPermissionsResultListener(this)
        scanner?.setActivity(activity)
        connectionManager?.setActivity(activity)
        gattServer?.setActivity(activity)
        advertiser?.setActivity(activity)
    }

    override fun onDetachedFromActivity() {
        activityBinding?.removeRequestPermissionsResultListener(this)
        activityBinding = null
        activity = null
        scanner?.setActivity(null)
        connectionManager?.setActivity(null)
        gattServer?.setActivity(null)
        advertiser?.setActivity(null)
    }

    // BlueyHostApi implementation

    override fun getState(callback: (Result<BluetoothStateDto>) -> Unit) {
        val state = getCurrentBluetoothState()
        callback(Result.success(state))
    }

    override fun requestEnable(callback: (Result<Boolean>) -> Unit) {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
            // Android 12+ requires BLUETOOTH_CONNECT permission
            if (ContextCompat.checkSelfPermission(
                    context!!,
                    Manifest.permission.BLUETOOTH_CONNECT
                ) != PackageManager.PERMISSION_GRANTED
            ) {
                callback(Result.success(false))
                return
            }
        }

        val adapter = bluetoothAdapter
        if (adapter == null) {
            callback(Result.success(false))
            return
        }

        if (adapter.isEnabled) {
            callback(Result.success(true))
            return
        }

        // Request enable (only works on older Android versions)
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.TIRAMISU) {
            try {
                val enableIntent = Intent(BluetoothAdapter.ACTION_REQUEST_ENABLE)
                activity?.startActivityForResult(enableIntent, REQUEST_ENABLE_BT)
                callback(Result.success(true))
            } catch (e: Exception) {
                callback(Result.success(false))
            }
        } else {
            // Android 13+ - user must enable manually via settings
            callback(Result.success(false))
        }
    }

    override fun authorize(callback: (Result<Boolean>) -> Unit) {
        val currentActivity = activity
        if (currentActivity == null) {
            callback(Result.success(false))
            return
        }

        // Determine which permissions are needed based on Android version
        val permissions = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
            arrayOf(
                Manifest.permission.BLUETOOTH_SCAN,
                Manifest.permission.BLUETOOTH_CONNECT,
                Manifest.permission.BLUETOOTH_ADVERTISE
            )
        } else {
            arrayOf(
                Manifest.permission.BLUETOOTH,
                Manifest.permission.BLUETOOTH_ADMIN,
                Manifest.permission.ACCESS_FINE_LOCATION
            )
        }

        // Check if permissions are already granted
        val allGranted = permissions.all {
            ContextCompat.checkSelfPermission(context!!, it) == PackageManager.PERMISSION_GRANTED
        }

        if (allGranted) {
            callback(Result.success(true))
            return
        }

        // Request permissions
        permissionCallback = callback
        ActivityCompat.requestPermissions(currentActivity, permissions, REQUEST_PERMISSIONS)
    }

    override fun openSettings(callback: (Result<Unit>) -> Unit) {
        try {
            val intent = Intent(Settings.ACTION_BLUETOOTH_SETTINGS)
            intent.flags = Intent.FLAG_ACTIVITY_NEW_TASK
            context?.startActivity(intent)
            callback(Result.success(Unit))
        } catch (e: Exception) {
            callback(Result.failure(e))
        }
    }

    override fun startScan(config: ScanConfigDto, callback: (Result<Unit>) -> Unit) {
        scanner?.startScan(config, callback) ?: callback(
            Result.failure(IllegalStateException("Scanner not initialized"))
        )
    }

    override fun stopScan(callback: (Result<Unit>) -> Unit) {
        scanner?.stopScan(callback) ?: callback(
            Result.failure(IllegalStateException("Scanner not initialized"))
        )
    }

    override fun connect(
        deviceId: String,
        config: ConnectConfigDto,
        callback: (Result<String>) -> Unit
    ) {
        connectionManager?.connect(deviceId, config, callback) ?: callback(
            Result.failure(IllegalStateException("ConnectionManager not initialized"))
        )
    }

    override fun disconnect(deviceId: String, callback: (Result<Unit>) -> Unit) {
        connectionManager?.disconnect(deviceId, callback) ?: callback(
            Result.failure(IllegalStateException("ConnectionManager not initialized"))
        )
    }

    override fun discoverServices(deviceId: String, callback: (Result<List<ServiceDto>>) -> Unit) {
        connectionManager?.discoverServices(deviceId, callback) ?: callback(
            Result.failure(IllegalStateException("ConnectionManager not initialized"))
        )
    }

    override fun readCharacteristic(
        deviceId: String,
        characteristicUuid: String,
        callback: (Result<ByteArray>) -> Unit
    ) {
        connectionManager?.readCharacteristic(deviceId, characteristicUuid, callback) ?: callback(
            Result.failure(IllegalStateException("ConnectionManager not initialized"))
        )
    }

    override fun writeCharacteristic(
        deviceId: String,
        characteristicUuid: String,
        value: ByteArray,
        withResponse: Boolean,
        callback: (Result<Unit>) -> Unit
    ) {
        connectionManager?.writeCharacteristic(deviceId, characteristicUuid, value, withResponse, callback) ?: callback(
            Result.failure(IllegalStateException("ConnectionManager not initialized"))
        )
    }

    override fun setNotification(
        deviceId: String,
        characteristicUuid: String,
        enable: Boolean,
        callback: (Result<Unit>) -> Unit
    ) {
        connectionManager?.setNotification(deviceId, characteristicUuid, enable, callback) ?: callback(
            Result.failure(IllegalStateException("ConnectionManager not initialized"))
        )
    }

    override fun readDescriptor(
        deviceId: String,
        descriptorUuid: String,
        callback: (Result<ByteArray>) -> Unit
    ) {
        connectionManager?.readDescriptor(deviceId, descriptorUuid, callback) ?: callback(
            Result.failure(IllegalStateException("ConnectionManager not initialized"))
        )
    }

    override fun writeDescriptor(
        deviceId: String,
        descriptorUuid: String,
        value: ByteArray,
        callback: (Result<Unit>) -> Unit
    ) {
        connectionManager?.writeDescriptor(deviceId, descriptorUuid, value, callback) ?: callback(
            Result.failure(IllegalStateException("ConnectionManager not initialized"))
        )
    }

    override fun requestMtu(deviceId: String, mtu: Long, callback: (Result<Long>) -> Unit) {
        connectionManager?.requestMtu(deviceId, mtu, callback) ?: callback(
            Result.failure(IllegalStateException("ConnectionManager not initialized"))
        )
    }

    override fun readRssi(deviceId: String, callback: (Result<Long>) -> Unit) {
        connectionManager?.readRssi(deviceId, callback) ?: callback(
            Result.failure(IllegalStateException("ConnectionManager not initialized"))
        )
    }

    // Server (Peripheral) operations

    override fun addService(service: LocalServiceDto, callback: (Result<Unit>) -> Unit) {
        gattServer?.addService(service, callback) ?: callback(
            Result.failure(IllegalStateException("GattServer not initialized"))
        )
    }

    override fun removeService(serviceUuid: String, callback: (Result<Unit>) -> Unit) {
        gattServer?.removeService(serviceUuid, callback) ?: callback(
            Result.failure(IllegalStateException("GattServer not initialized"))
        )
    }

    override fun startAdvertising(config: AdvertiseConfigDto, callback: (Result<Unit>) -> Unit) {
        // Log the GATT server state before advertising
        android.util.Log.d("BlueyPlugin", "startAdvertising called - logging GATT server state:")
        gattServer?.logServerState()

        advertiser?.startAdvertising(config) { result ->
            if (result.isSuccess) {
                android.util.Log.d("BlueyPlugin", "Advertising started - notifying GattServer")
                gattServer?.onAdvertisingStarted()
                gattServer?.logServerState()
            }
            callback(result)
        } ?: callback(
            Result.failure(IllegalStateException("Advertiser not initialized"))
        )
    }

    override fun stopAdvertising(callback: (Result<Unit>) -> Unit) {
        gattServer?.onAdvertisingStopped()
        advertiser?.stopAdvertising(callback) ?: callback(
            Result.failure(IllegalStateException("Advertiser not initialized"))
        )
    }

    override fun notifyCharacteristic(
        characteristicUuid: String,
        value: ByteArray,
        callback: (Result<Unit>) -> Unit
    ) {
        gattServer?.notifyCharacteristic(characteristicUuid, value, callback) ?: callback(
            Result.failure(IllegalStateException("GattServer not initialized"))
        )
    }

    override fun notifyCharacteristicTo(
        centralId: String,
        characteristicUuid: String,
        value: ByteArray,
        callback: (Result<Unit>) -> Unit
    ) {
        gattServer?.notifyCharacteristicTo(centralId, characteristicUuid, value, callback) ?: callback(
            Result.failure(IllegalStateException("GattServer not initialized"))
        )
    }

    override fun respondToReadRequest(
        requestId: Long,
        status: GattStatusDto,
        value: ByteArray?,
        callback: (Result<Unit>) -> Unit
    ) {
        gattServer?.respondToReadRequest(requestId, status, value, callback) ?: callback(
            Result.failure(IllegalStateException("GattServer not initialized"))
        )
    }

    override fun respondToWriteRequest(
        requestId: Long,
        status: GattStatusDto,
        callback: (Result<Unit>) -> Unit
    ) {
        gattServer?.respondToWriteRequest(requestId, status, callback) ?: callback(
            Result.failure(IllegalStateException("GattServer not initialized"))
        )
    }

    override fun disconnectCentral(centralId: String, callback: (Result<Unit>) -> Unit) {
        gattServer?.disconnectCentral(centralId, callback) ?: callback(
            Result.failure(IllegalStateException("GattServer not initialized"))
        )
    }

    override fun closeServer(callback: (Result<Unit>) -> Unit) {
        android.util.Log.d("BlueyPlugin", "closeServer called")
        advertiser?.cleanup()
        gattServer?.cleanup()
        callback(Result.success(Unit))
    }

    // Private helper methods

    private fun getCurrentBluetoothState(): BluetoothStateDto {
        val adapter = bluetoothAdapter ?: return BluetoothStateDto.UNSUPPORTED

        // Check permissions
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
            if (ContextCompat.checkSelfPermission(
                    context!!,
                    Manifest.permission.BLUETOOTH_CONNECT
                ) != PackageManager.PERMISSION_GRANTED
            ) {
                return BluetoothStateDto.UNAUTHORIZED
            }
        }

        return if (adapter.isEnabled) {
            BluetoothStateDto.ON
        } else {
            BluetoothStateDto.OFF
        }
    }

    private fun startBluetoothStateMonitoring() {
        // Register BroadcastReceiver for Bluetooth state changes
        bluetoothStateReceiver = object : BroadcastReceiver() {
            override fun onReceive(context: Context?, intent: Intent?) {
                if (intent?.action == BluetoothAdapter.ACTION_STATE_CHANGED) {
                    val state = intent.getIntExtra(
                        BluetoothAdapter.EXTRA_STATE,
                        BluetoothAdapter.ERROR
                    )
                    val bluetoothState = mapAdapterStateToDto(state)
                    flutterApi?.onStateChanged(bluetoothState) {}
                }
            }
        }

        val filter = IntentFilter(BluetoothAdapter.ACTION_STATE_CHANGED)
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
            context?.registerReceiver(
                bluetoothStateReceiver,
                filter,
                Context.RECEIVER_NOT_EXPORTED
            )
        } else {
            context?.registerReceiver(bluetoothStateReceiver, filter)
        }

        // Report initial state
        flutterApi?.onStateChanged(getCurrentBluetoothState()) {}
    }

    private fun stopBluetoothStateMonitoring() {
        bluetoothStateReceiver?.let { receiver ->
            try {
                context?.unregisterReceiver(receiver)
            } catch (e: IllegalArgumentException) {
                // Receiver was not registered, ignore
            }
        }
        bluetoothStateReceiver = null
    }

    private fun mapAdapterStateToDto(adapterState: Int): BluetoothStateDto {
        return when (adapterState) {
            BluetoothAdapter.STATE_OFF -> BluetoothStateDto.OFF
            BluetoothAdapter.STATE_TURNING_OFF -> BluetoothStateDto.OFF
            BluetoothAdapter.STATE_ON -> BluetoothStateDto.ON
            BluetoothAdapter.STATE_TURNING_ON -> BluetoothStateDto.OFF
            else -> BluetoothStateDto.UNKNOWN
        }
    }

    // RequestPermissionsResultListener implementation

    override fun onRequestPermissionsResult(
        requestCode: Int,
        permissions: Array<out String>,
        grantResults: IntArray
    ): Boolean {
        if (requestCode != REQUEST_PERMISSIONS) {
            return false
        }

        val allGranted = grantResults.isNotEmpty() && grantResults.all {
            it == PackageManager.PERMISSION_GRANTED
        }

        permissionCallback?.invoke(Result.success(allGranted))
        permissionCallback = null

        // Update state after permission change
        flutterApi?.onStateChanged(getCurrentBluetoothState()) {}

        return true
    }

    companion object {
        private const val REQUEST_ENABLE_BT = 1001
        private const val REQUEST_PERMISSIONS = 1002
    }
}
