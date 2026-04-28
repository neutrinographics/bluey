package com.neutrinographics.bluey

import android.bluetooth.BluetoothGatt
import android.os.Handler

/**
 * Per-connection serial GATT operation queue.
 *
 * Aggregate root for "work-in-flight on a single [BluetoothGatt] handle."
 * Enforces Android's single-op-in-flight constraint by serializing every
 * GATT operation through a FIFO queue with per-op timeouts.
 *
 * Thread safety: this class is NOT thread-safe. All public methods must be
 * called on the main thread (the same thread the supplied [Handler]
 * dispatches on). The [ConnectionManager.createGattCallback] pattern
 * marshals [android.bluetooth.BluetoothGattCallback] events via
 * `handler.post { queue.onComplete(...) }` before touching the queue.
 */
internal class GattOpQueue(
    private val gatt: BluetoothGatt,
    private val handler: Handler,
) {
    private val pending = ArrayDeque<GattOp>()
    private var current: GattOp? = null
    private var currentTimeout: Runnable? = null

    /**
     * Adds [op] to the queue. If the queue is idle, the op is started
     * immediately. Otherwise it runs after all previously-enqueued ops
     * complete (FIFO).
     */
    fun enqueue(op: GattOp) {
        pending.addLast(op)
        if (current == null) startNext()
    }

    /**
     * Signals that the currently-in-flight op has completed (successfully
     * or with a status-based failure). Fires the op's callback, advances
     * the queue.
     *
     * No-op if there is no current op (stray callback from the BLE stack,
     * e.g. the native layer firing a delayed callback after we've already
     * timed out or drained).
     */
    fun onComplete(result: Result<Any?>) {
        val op = current ?: return
        currentTimeout?.let { handler.removeCallbacks(it) }
        currentTimeout = null
        current = null  // clear BEFORE firing callback (reentrancy safety)
        try {
            op.complete(result)
        } catch (e: Throwable) {
            BlueyLog.log(LogLevelDto.ERROR, CONTEXT, "GattOp.complete threw: $e")
        }
        // Guard: reentrant enqueue inside op.complete may have already set
        // current (started the next op). Only advance if still idle.
        if (current == null && pending.isNotEmpty()) startNext()
    }

    /**
     * Fails the currently-in-flight op and every queued op with [reason],
     * then resets the queue. Called when the connection is torn down.
     */
    fun drainAll(reason: Throwable) {
        currentTimeout?.let { handler.removeCallbacks(it) }
        currentTimeout = null
        val inFlight = current
        val queued = pending.toList()
        current = null
        pending.clear()
        inFlight?.let {
            try { it.complete(Result.failure(reason)) }
            catch (e: Throwable) { BlueyLog.log(LogLevelDto.ERROR, CONTEXT, "GattOp.complete threw during drain: $e") }
        }
        for (op in queued) {
            try { op.complete(Result.failure(reason)) }
            catch (e: Throwable) { BlueyLog.log(LogLevelDto.ERROR, CONTEXT, "GattOp.complete threw during drain: $e") }
        }
    }

    private fun startNext() {
        val op = pending.removeFirst()
        current = op

        val timeout = Runnable {
            // Defensive: fire only if this op is still current
            if (current !== op) return@Runnable
            currentTimeout = null
            current = null
            try {
                op.complete(
                    Result.failure(
                        FlutterError(
                            "gatt-timeout",
                            "${op.description} timed out",
                            null,
                        )
                    )
                )
            } catch (e: Throwable) {
                BlueyLog.log(LogLevelDto.ERROR, CONTEXT, "GattOp.complete threw during timeout: $e")
            }
            // Guard: reentrant enqueue may have set current already
            if (current == null && pending.isNotEmpty()) startNext()
        }
        currentTimeout = timeout
        handler.postDelayed(timeout, op.timeoutMs)

        val executeOutcome: Result<Boolean> = try {
            Result.success(op.execute(gatt))
        } catch (e: Throwable) {
            BlueyLog.log(LogLevelDto.ERROR, CONTEXT, "GattOp.execute threw: $e")
            Result.failure(e)
        }

        // Two sync-failure modes:
        //   - execute() returned false: use syncFailureMessage (preserves
        //     existing Phase 1 / pre-Phase-1 error text).
        //   - execute() threw (e.g. SecurityException when BLUETOOTH_CONNECT
        //     is revoked): propagate the original exception so callers can
        //     diagnose root cause instead of seeing a generic rejection.
        val syncFailure: Throwable? = when {
            executeOutcome.isFailure -> executeOutcome.exceptionOrNull()
            executeOutcome.getOrThrow() -> null
            else -> IllegalStateException(op.syncFailureMessage)
        }

        if (syncFailure != null) {
            currentTimeout?.let { handler.removeCallbacks(it) }
            currentTimeout = null
            current = null
            try {
                op.complete(Result.failure(syncFailure))
            } catch (e: Throwable) {
                BlueyLog.log(LogLevelDto.ERROR, CONTEXT, "GattOp.complete threw during sync-failure: $e")
            }
            // Guard: reentrant enqueue may have set current already
            if (current == null && pending.isNotEmpty()) startNext()
        }
    }

    companion object {
        private const val CONTEXT = "bluey.android.gatt_queue"
    }
}
