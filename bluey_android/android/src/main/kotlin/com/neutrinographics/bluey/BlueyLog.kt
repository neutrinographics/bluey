package com.neutrinographics.bluey

/**
 * Process-wide structured logger for the Bluey Android plugin.
 *
 * Forwards log events to the Dart side via `BlueyFlutterApi.onLog(...)` so
 * they reach the unified `Bluey.logEvents` stream. The bridge is
 * best-effort: if no [BlueyFlutterApi] is bound (e.g. very early plugin
 * attach, or after detach), emits are silently dropped per the
 * bootstrap-loss policy of the structured-logging plan (I307).
 *
 * Level filtering is applied before forwarding — events below [minLevel]
 * are dropped entirely. Default threshold is [LogLevelDto.INFO]; Dart
 * side updates it via the `BlueyHostApi.setLogLevel` channel.
 *
 * This is a singleton because there is exactly one Flutter engine per
 * process for the plugin. Tests use [resetForTest] to clear state between
 * runs.
 */
object BlueyLog {
    @Volatile
    private var minLevel: LogLevelDto = LogLevelDto.INFO

    @Volatile
    private var flutterApi: BlueyFlutterApi? = null

    /** Bind the Pigeon FlutterApi for native→Dart log forwarding. */
    fun bind(api: BlueyFlutterApi) {
        flutterApi = api
    }

    /** Update the minimum severity threshold. Events below this level are dropped. */
    fun setLevel(level: LogLevelDto) {
        minLevel = level
    }

    /** Reset state. Test-only. */
    @JvmStatic
    internal fun resetForTest() {
        minLevel = LogLevelDto.INFO
        flutterApi = null
    }

    /**
     * Emit a structured log event.
     *
     * @param level severity; events below the configured threshold are dropped.
     * @param context coarse subsystem tag (e.g. `"bluey.android.connection"`).
     * @param message human-readable message; do not embed secrets or full payload bytes.
     * @param data optional structured key/value pairs (preferred over string interpolation).
     * @param errorCode optional stable error code (e.g. `"GATT_133"`).
     */
    fun log(
        level: LogLevelDto,
        context: String,
        message: String,
        data: Map<String, Any?> = emptyMap(),
        errorCode: String? = null,
    ) {
        if (level.raw < minLevel.raw) return

        // Bridge to Dart (best-effort).
        val api = flutterApi ?: return
        // Pigeon generates `Map<String?, Any?>` for `data`; widen the key type
        // so callers can pass a plain `Map<String, Any?>`.
        val pigeonData: Map<String?, Any?> = data.mapKeys { it.key }
        api.onLog(
            LogEventDto(
                context = context,
                level = level,
                message = message,
                data = pigeonData,
                errorCode = errorCode,
                timestampMicros = System.currentTimeMillis() * 1000L,
            ),
        ) {}
    }
}
