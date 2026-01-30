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

/**
 * BlueyPlugin - Android implementation of Bluey BLE library.
 *
 * This follows Clean Architecture principles:
 * - Implements the platform interface defined via Pigeon
 * - Delegates to domain-specific classes (Scanner, ConnectionManager)
 * - Manages lifecycle and permissions
 */
class BlueyPlugin : FlutterPlugin, ActivityAware, BlueyHostApi {
    private var context: Context? = null
    private var activity: Activity? = null
    private var flutterApi: BlueyFlutterApi? = null

    private var bluetoothManager: BluetoothManager? = null
    private var bluetoothAdapter: BluetoothAdapter? = null

    private var scanner: Scanner? = null
    private var connectionManager: ConnectionManager? = null

    // Bluetooth state receiver
    private var bluetoothStateReceiver: BroadcastReceiver? = null

    // FlutterPlugin implementation

    override fun onAttachedToEngine(binding: FlutterPlugin.FlutterPluginBinding) {
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

        scanner = null
        connectionManager = null
        context = null
        flutterApi = null
    }

    // ActivityAware implementation

    override fun onAttachedToActivity(binding: ActivityPluginBinding) {
        activity = binding.activity
        scanner?.setActivity(activity)
        connectionManager?.setActivity(activity)
    }

    override fun onDetachedFromActivityForConfigChanges() {
        activity = null
    }

    override fun onReattachedToActivityForConfigChanges(binding: ActivityPluginBinding) {
        activity = binding.activity
        scanner?.setActivity(activity)
        connectionManager?.setActivity(activity)
    }

    override fun onDetachedFromActivity() {
        activity = null
        scanner?.setActivity(null)
        connectionManager?.setActivity(null)
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

    companion object {
        private const val REQUEST_ENABLE_BT = 1001
    }
}
