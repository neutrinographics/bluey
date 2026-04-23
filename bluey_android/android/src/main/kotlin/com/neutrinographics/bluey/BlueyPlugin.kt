package com.neutrinographics.bluey

import android.Manifest
import android.app.Activity
import android.app.Application
import android.bluetooth.BluetoothAdapter
import android.bluetooth.BluetoothManager
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.content.IntentFilter
import android.content.pm.PackageManager
import android.os.Build
import android.os.Bundle
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

    // Configuration: whether to clean up BLE resources when activity is destroyed
    // Default is true to prevent zombie connections
    private var cleanupOnActivityDestroy: Boolean = true

    // Activity lifecycle callbacks for more reliable cleanup
    private var activityLifecycleCallbacks: Application.ActivityLifecycleCallbacks? = null

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

        // Register activity lifecycle callbacks for more reliable cleanup
        registerActivityLifecycleCallbacks(binding.activity)
    }

    private fun registerActivityLifecycleCallbacks(activity: Activity) {
        val application = activity.application ?: return

        // Unregister any existing callbacks first
        activityLifecycleCallbacks?.let { application.unregisterActivityLifecycleCallbacks(it) }

        activityLifecycleCallbacks = object : Application.ActivityLifecycleCallbacks {
            override fun onActivityCreated(activity: Activity, savedInstanceState: Bundle?) {}
            override fun onActivityStarted(activity: Activity) {}
            override fun onActivityResumed(activity: Activity) {}
            override fun onActivityPaused(activity: Activity) {}
            override fun onActivityStopped(activity: Activity) {}
            override fun onActivitySaveInstanceState(activity: Activity, outState: Bundle) {}

            override fun onActivityDestroyed(activity: Activity) {
                android.util.Log.d(
                    "BlueyPlugin",
                    "onActivityDestroyed called for ${activity.javaClass.simpleName}, isOurActivity=${activity == this@BlueyPlugin.activity}, cleanupOnActivityDestroy=$cleanupOnActivityDestroy"
                )
                if (activity == this@BlueyPlugin.activity && cleanupOnActivityDestroy) {
                    android.util.Log.d("BlueyPlugin", "Cleaning up BLE resources in onActivityDestroyed")
                    advertiser?.cleanup()
                    gattServer?.cleanup()
                }
            }
        }

        application.registerActivityLifecycleCallbacks(activityLifecycleCallbacks)
        android.util.Log.d("BlueyPlugin", "Registered ActivityLifecycleCallbacks")
    }

    private fun unregisterActivityLifecycleCallbacks() {
        val application = activity?.application ?: return
        activityLifecycleCallbacks?.let {
            application.unregisterActivityLifecycleCallbacks(it)
            android.util.Log.d("BlueyPlugin", "Unregistered ActivityLifecycleCallbacks")
        }
        activityLifecycleCallbacks = null
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

        // Unregister lifecycle callbacks
        unregisterActivityLifecycleCallbacks()

        // Clean up BLE resources if configured to do so
        // This prevents zombie BLE connections when the app is closed
        // Note: onActivityDestroyed may have already done this cleanup, but it's safe to call twice
        if (cleanupOnActivityDestroy) {
            android.util.Log.d(
                "BlueyPlugin",
                "Activity detached - cleaning up BLE resources (cleanupOnActivityDestroy=true)"
            )
            advertiser?.cleanup()
            gattServer?.cleanup()
        } else {
            android.util.Log.d("BlueyPlugin", "Activity detached - skipping cleanup (cleanupOnActivityDestroy=false)")
        }

        activity = null
        scanner?.setActivity(null)
        connectionManager?.setActivity(null)
        gattServer?.setActivity(null)
        advertiser?.setActivity(null)
    }

    // BlueyHostApi implementation

    override fun configure(config: BlueyConfigDto, callback: (Result<Unit>) -> Unit) {
        try {
            cleanupOnActivityDestroy = config.cleanupOnActivityDestroy
            connectionManager?.configure(config)
            android.util.Log.d("BlueyPlugin", "Configured: cleanupOnActivityDestroy=$cleanupOnActivityDestroy")
            callback(Result.success(Unit))
        } catch (e: Throwable) {
            callback(Result.failure(e.toClientFlutterError()))
        }
    }

    override fun getState(callback: (Result<BluetoothStateDto>) -> Unit) {
        try {
            val state = getCurrentBluetoothState()
            callback(Result.success(state))
        } catch (e: Throwable) {
            callback(Result.failure(e.toClientFlutterError()))
        }
    }

    override fun requestEnable(callback: (Result<Boolean>) -> Unit) {
        try {
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
                // Android 13+ - open Bluetooth settings for the user
                try {
                    val settingsIntent = Intent(Settings.ACTION_BLUETOOTH_SETTINGS)
                    activity?.startActivity(settingsIntent)
                } catch (_: Exception) {
                    // Settings activity unavailable
                }
                callback(Result.success(false))
            }
        } catch (e: Throwable) {
            callback(Result.failure(e.toClientFlutterError()))
        }
    }

    override fun authorize(callback: (Result<Boolean>) -> Unit) {
        try {
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
        } catch (e: Throwable) {
            callback(Result.failure(e.toClientFlutterError()))
        }
    }

    override fun openSettings(callback: (Result<Unit>) -> Unit) {
        try {
            val intent = Intent(Settings.ACTION_BLUETOOTH_SETTINGS)
            intent.flags = Intent.FLAG_ACTIVITY_NEW_TASK
            context?.startActivity(intent)
            callback(Result.success(Unit))
        } catch (e: Throwable) {
            callback(Result.failure(e.toClientFlutterError()))
        }
    }

    override fun startScan(config: ScanConfigDto, callback: (Result<Unit>) -> Unit) {
        try {
            val s = scanner ?: throw BlueyAndroidError.NotInitialized("Scanner")
            s.startScan(config) { result ->
                callback(result.recoverCatching { e -> throw e.toClientFlutterError() })
            }
        } catch (e: Throwable) {
            callback(Result.failure(e.toClientFlutterError()))
        }
    }

    override fun stopScan(callback: (Result<Unit>) -> Unit) {
        try {
            val s = scanner ?: throw BlueyAndroidError.NotInitialized("Scanner")
            s.stopScan { result ->
                callback(result.recoverCatching { e -> throw e.toClientFlutterError() })
            }
        } catch (e: Throwable) {
            callback(Result.failure(e.toClientFlutterError()))
        }
    }

    override fun connect(
        deviceId: String,
        config: ConnectConfigDto,
        callback: (Result<String>) -> Unit
    ) {
        try {
            val cm = connectionManager ?: throw BlueyAndroidError.NotInitialized("ConnectionManager")
            cm.connect(deviceId, config) { result ->
                callback(result.recoverCatching { e -> throw e.toClientFlutterError() })
            }
        } catch (e: Throwable) {
            callback(Result.failure(e.toClientFlutterError()))
        }
    }

    override fun disconnect(deviceId: String, callback: (Result<Unit>) -> Unit) {
        try {
            val cm = connectionManager ?: throw BlueyAndroidError.NotInitialized("ConnectionManager")
            cm.disconnect(deviceId) { result ->
                callback(result.recoverCatching { e -> throw e.toClientFlutterError() })
            }
        } catch (e: Throwable) {
            callback(Result.failure(e.toClientFlutterError()))
        }
    }

    override fun discoverServices(deviceId: String, callback: (Result<List<ServiceDto>>) -> Unit) {
        try {
            val cm = connectionManager ?: throw BlueyAndroidError.NotInitialized("ConnectionManager")
            cm.discoverServices(deviceId) { result ->
                callback(result.recoverCatching { e -> throw e.toClientFlutterError() })
            }
        } catch (e: Throwable) {
            callback(Result.failure(e.toClientFlutterError()))
        }
    }

    override fun readCharacteristic(
        deviceId: String,
        characteristicUuid: String,
        callback: (Result<ByteArray>) -> Unit
    ) {
        try {
            val cm = connectionManager ?: throw BlueyAndroidError.NotInitialized("ConnectionManager")
            cm.readCharacteristic(deviceId, characteristicUuid) { result ->
                callback(result.recoverCatching { e -> throw e.toClientFlutterError() })
            }
        } catch (e: Throwable) {
            callback(Result.failure(e.toClientFlutterError()))
        }
    }

    override fun writeCharacteristic(
        deviceId: String,
        characteristicUuid: String,
        value: ByteArray,
        withResponse: Boolean,
        callback: (Result<Unit>) -> Unit
    ) {
        try {
            val cm = connectionManager ?: throw BlueyAndroidError.NotInitialized("ConnectionManager")
            cm.writeCharacteristic(deviceId, characteristicUuid, value, withResponse) { result ->
                callback(result.recoverCatching { e -> throw e.toClientFlutterError() })
            }
        } catch (e: Throwable) {
            callback(Result.failure(e.toClientFlutterError()))
        }
    }

    override fun setNotification(
        deviceId: String,
        characteristicUuid: String,
        enable: Boolean,
        callback: (Result<Unit>) -> Unit
    ) {
        try {
            val cm = connectionManager ?: throw BlueyAndroidError.NotInitialized("ConnectionManager")
            cm.setNotification(deviceId, characteristicUuid, enable) { result ->
                callback(result.recoverCatching { e -> throw e.toClientFlutterError() })
            }
        } catch (e: Throwable) {
            callback(Result.failure(e.toClientFlutterError()))
        }
    }

    override fun readDescriptor(
        deviceId: String,
        descriptorUuid: String,
        callback: (Result<ByteArray>) -> Unit
    ) {
        try {
            val cm = connectionManager ?: throw BlueyAndroidError.NotInitialized("ConnectionManager")
            cm.readDescriptor(deviceId, descriptorUuid) { result ->
                callback(result.recoverCatching { e -> throw e.toClientFlutterError() })
            }
        } catch (e: Throwable) {
            callback(Result.failure(e.toClientFlutterError()))
        }
    }

    override fun writeDescriptor(
        deviceId: String,
        descriptorUuid: String,
        value: ByteArray,
        callback: (Result<Unit>) -> Unit
    ) {
        try {
            val cm = connectionManager ?: throw BlueyAndroidError.NotInitialized("ConnectionManager")
            cm.writeDescriptor(deviceId, descriptorUuid, value) { result ->
                callback(result.recoverCatching { e -> throw e.toClientFlutterError() })
            }
        } catch (e: Throwable) {
            callback(Result.failure(e.toClientFlutterError()))
        }
    }

    override fun requestMtu(deviceId: String, mtu: Long, callback: (Result<Long>) -> Unit) {
        try {
            val cm = connectionManager ?: throw BlueyAndroidError.NotInitialized("ConnectionManager")
            cm.requestMtu(deviceId, mtu) { result ->
                callback(result.recoverCatching { e -> throw e.toClientFlutterError() })
            }
        } catch (e: Throwable) {
            callback(Result.failure(e.toClientFlutterError()))
        }
    }

    override fun readRssi(deviceId: String, callback: (Result<Long>) -> Unit) {
        try {
            val cm = connectionManager ?: throw BlueyAndroidError.NotInitialized("ConnectionManager")
            cm.readRssi(deviceId) { result ->
                callback(result.recoverCatching { e -> throw e.toClientFlutterError() })
            }
        } catch (e: Throwable) {
            callback(Result.failure(e.toClientFlutterError()))
        }
    }

    // Server (Peripheral) operations

    override fun addService(service: LocalServiceDto, callback: (Result<Unit>) -> Unit) {
        try {
            val gs = gattServer ?: throw BlueyAndroidError.NotInitialized("GattServer")
            gs.addService(service) { result ->
                callback(result.recoverCatching { e -> throw e.toServerFlutterError() })
            }
        } catch (e: Throwable) {
            callback(Result.failure(e.toServerFlutterError()))
        }
    }

    override fun removeService(serviceUuid: String, callback: (Result<Unit>) -> Unit) {
        try {
            val gs = gattServer ?: throw BlueyAndroidError.NotInitialized("GattServer")
            gs.removeService(serviceUuid) { result ->
                callback(result.recoverCatching { e -> throw e.toServerFlutterError() })
            }
        } catch (e: Throwable) {
            callback(Result.failure(e.toServerFlutterError()))
        }
    }

    override fun startAdvertising(config: AdvertiseConfigDto, callback: (Result<Unit>) -> Unit) {
        try {
            // Log the GATT server state before advertising
            android.util.Log.d("BlueyPlugin", "startAdvertising called - logging GATT server state:")
            gattServer?.logServerState()

            val adv = advertiser ?: throw BlueyAndroidError.NotInitialized("Advertiser")
            adv.startAdvertising(config) { result ->
                callback(result.recoverCatching { e -> throw e.toServerFlutterError() })
            }
        } catch (e: Throwable) {
            callback(Result.failure(e.toServerFlutterError()))
        }
    }

    override fun stopAdvertising(callback: (Result<Unit>) -> Unit) {
        try {
            val adv = advertiser ?: throw BlueyAndroidError.NotInitialized("Advertiser")
            adv.stopAdvertising { result ->
                callback(result.recoverCatching { e -> throw e.toServerFlutterError() })
            }
        } catch (e: Throwable) {
            callback(Result.failure(e.toServerFlutterError()))
        }
    }

    override fun notifyCharacteristic(
        characteristicUuid: String,
        value: ByteArray,
        callback: (Result<Unit>) -> Unit
    ) {
        try {
            val gs = gattServer ?: throw BlueyAndroidError.NotInitialized("GattServer")
            gs.notifyCharacteristic(characteristicUuid, value) { result ->
                callback(result.recoverCatching { e -> throw e.toServerFlutterError() })
            }
        } catch (e: Throwable) {
            callback(Result.failure(e.toServerFlutterError()))
        }
    }

    override fun notifyCharacteristicTo(
        centralId: String,
        characteristicUuid: String,
        value: ByteArray,
        callback: (Result<Unit>) -> Unit
    ) {
        try {
            val gs = gattServer ?: throw BlueyAndroidError.NotInitialized("GattServer")
            gs.notifyCharacteristicTo(centralId, characteristicUuid, value) { result ->
                callback(result.recoverCatching { e -> throw e.toServerFlutterError() })
            }
        } catch (e: Throwable) {
            callback(Result.failure(e.toServerFlutterError()))
        }
    }

    override fun respondToReadRequest(
        requestId: Long,
        status: GattStatusDto,
        value: ByteArray?,
        callback: (Result<Unit>) -> Unit
    ) {
        try {
            val gs = gattServer ?: throw BlueyAndroidError.NotInitialized("GattServer")
            gs.respondToReadRequest(requestId, status, value) { result ->
                callback(result.recoverCatching { e -> throw e.toServerFlutterError() })
            }
        } catch (e: Throwable) {
            callback(Result.failure(e.toServerFlutterError()))
        }
    }

    override fun respondToWriteRequest(
        requestId: Long,
        status: GattStatusDto,
        callback: (Result<Unit>) -> Unit
    ) {
        try {
            val gs = gattServer ?: throw BlueyAndroidError.NotInitialized("GattServer")
            gs.respondToWriteRequest(requestId, status) { result ->
                callback(result.recoverCatching { e -> throw e.toServerFlutterError() })
            }
        } catch (e: Throwable) {
            callback(Result.failure(e.toServerFlutterError()))
        }
    }

    override fun disconnectCentral(centralId: String, callback: (Result<Unit>) -> Unit) {
        try {
            val gs = gattServer ?: throw BlueyAndroidError.NotInitialized("GattServer")
            gs.disconnectCentral(centralId) { result ->
                callback(result.recoverCatching { e -> throw e.toServerFlutterError() })
            }
        } catch (e: Throwable) {
            callback(Result.failure(e.toServerFlutterError()))
        }
    }

    override fun closeServer(callback: (Result<Unit>) -> Unit) {
        try {
            android.util.Log.d("BlueyPlugin", "closeServer called")
            advertiser?.cleanup()
            gattServer?.cleanup()
            callback(Result.success(Unit))
        } catch (e: Throwable) {
            callback(Result.failure(e.toServerFlutterError()))
        }
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
