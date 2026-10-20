package ai.mubeen.mubeen_flutter

import ai.mubeen.deviceintel.DeviceIntelError
import ai.mubeen.deviceintel.ErrorCallback
import ai.mubeen.deviceintel.ErrorType
import ai.mubeen.deviceintel.MB_DeviceConfig
import ai.mubeen.deviceintel.MB_DeviceIntel
import android.content.Context
import android.content.pm.ApplicationInfo
import android.content.pm.PackageManager
import android.os.Build
import io.flutter.embedding.engine.plugins.FlutterPlugin
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext
import org.xmlpull.v1.XmlPullParser
import java.io.IOException
import java.util.concurrent.CopyOnWriteArrayList
import java.util.concurrent.atomic.AtomicBoolean

/**
 * Android implementation of the `mubeen_flutter` Pigeon contract.
 *
 * Threading: Pigeon 29 generates `suspend fun` host methods and invokes them from its own
 * `CoroutineScope(Dispatchers.Main)`, so each method already starts on the platform thread. The
 * SDK's collection path blocks for 200-800ms on a fast device per the
 * [MB_DeviceIntel.getFingerprint] KDoc, and 10-25 s on slow or emulated ones (measured), so every SDK
 * call is moved onto [Dispatchers.IO] with [onIo]; the reply is delivered back on the main thread
 * by Pigeon when the suspend function returns.
 *
 * Failure policy: no SDK call is allowed to escape as a host-app crash. Everything is wrapped
 * and surfaced as a `FlutterError` with one of the contract's code strings.
 */
class MubeenFlutterPlugin : FlutterPlugin, MubeenHostApi {

    private var applicationContext: Context? = null

    /** This engine's Dart channel, registered with [ErrorRelay] while attached. */
    private var flutterApi: MubeenFlutterApi? = null

    override fun onAttachedToEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        // applicationContext, never the Activity: the SDK holds this for the whole process
        // (MB_DeviceIntel.kt:94 `context = appContext.applicationContext`), so an Activity here
        // would leak it, and there is no Activity at all at engine-attach time.
        applicationContext = binding.applicationContext
        val api = MubeenFlutterApi(binding.binaryMessenger)
        flutterApi = api
        ErrorRelay.apis.add(api)
        MubeenHostApi.setUp(binding.binaryMessenger, this)
    }

    override fun onDetachedFromEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        MubeenHostApi.setUp(binding.binaryMessenger, null)
        // The SDK stores our ErrorCallback in its process-wide config and never clears it
        // (MB_DeviceIntel has no unregister; `config` is only reset by the internal
        // resetForTesting at MB_DeviceIntel.kt:249). ErrorRelay is therefore a process-lifetime
        // object on purpose - dropping this engine's MubeenFlutterApi from it is what actually
        // releases the engine. Only this engine's entry goes: other engines in the process
        // (background isolates, add-to-app) keep receiving errors.
        flutterApi?.let { ErrorRelay.apis.remove(it) }
        flutterApi = null
        applicationContext = null
    }

    // ---------------------------------------------------------------- host api

    override suspend fun configure(config: MbConfig) {
        val context = applicationContext
            ?: throw FlutterError("not_configured", "Plugin is not attached to a Flutter engine.")
        onIo { applyConfig(context, config) }
    }

    override suspend fun getDeviceId(): String = onIo {
        requireConfigured()
        MB_DeviceIntel.getDeviceId()
    }

    override suspend fun getFingerprint(): String = onIo {
        requireConfigured()
        MB_DeviceIntel.getFingerprint().toString()
    }

    override suspend fun pendingUploadCount(): Long = onIo {
        requireConfigured()
        MB_DeviceIntel.getPendingUploadCount().toLong()
    }

    override suspend fun resetDeviceId(): String = onIo {
        requireConfigured()
        MB_DeviceIntel.clearDeviceId()
        MB_DeviceIntel.getDeviceId()
    }

    override suspend fun sendFingerprint(request: MbFingerprintRequest): Unit = onIo {
        requireConfigured()
        if ((request.linkage != null || !request.custom.isNullOrEmpty()) &&
            linkageDropWarned.compareAndSet(false, true)
        ) {
            // deviceintel-lib 1.7.3's upload payload is built entirely from collectors
            // (MB_DeviceIntel.collectFingerprint, MB_DeviceIntel.kt:341+); there is no setter for
            // caller-supplied linkage or custom fields. They are accepted so client code is the
            // same on both platforms, dropped here, and the fingerprint is uploaded without them.
            // Dropping is reported once per process on the error stream, the same channel as the
            // advertising id warning, so it is visible without failing the call.
            ErrorRelay.emit(
                MbError(
                    code = "unsupported",
                    message = "linkage/custom were not sent: deviceintel-lib 1.7.3 on Android " +
                        "has no field for them. The fingerprint was uploaded without them. " +
                        "Check capabilities.linkage."
                )
            )
        }
        // Fire-and-forget by design: uploadFingerprint() returns immediately and reports real
        // outcomes through MubeenFlutterApi.onError.
        MB_DeviceIntel.uploadFingerprint()
    }

    override fun capabilities(): MbCapabilities {
        requireConfigured()
        return MbCapabilities(
            linkage = false,
            // Tracked separately from `linkage` in the contract; 1.7.3 supports neither.
            customData = false,
            rawFingerprint = true,
            pendingUploadCount = true
        )
    }

    /**
     * Whether the host app declares Auto Backup rules that *could* cover the SDK's prefs file.
     *
     * What this actually proves, and what it does not:
     *
     * - We read the host's merged `AndroidManifest.xml` and look for an `android:fullBackupContent`
     *   / `android:dataExtractionRules` attribute that points at an XML resource. That tells us the
     *   host **declares** backup rules. It does **not** tell us those rules contain
     *   `<include domain="sharedpref" path="MB_device_intel_secure_prefs.xml" />`. Proving that
     *   would mean resolving and parsing the referenced XML resource (and, for
     *   `dataExtractionRules`, its `<cloud-backup>` / `<device-transfer>` sections) on every call;
     *   we deliberately do not.
     * - Consequences for the caller:
     *   - `true` means "rules exist" - the device id *may* survive reinstall. Verify by eye that
     *     the include line from the README is in the referenced file.
     *   - `false` has two very different causes that this boolean cannot separate: (a)
     *     `android:allowBackup="false"`, where the id definitely will not survive, and (b) no rules
     *     declared at all, which is the platform default and where Auto Backup backs up *all*
     *     shared prefs - so the id actually **does** survive. A `false` is therefore a prompt to
     *     look, not a verdict.
     *
     * Android-version split: the platform reads `fullBackupContent` on API <= 30 and
     * `dataExtractionRules` on API 31+, falling back to `fullBackupContent` when the newer
     * attribute is absent - mirrored below.
     */
    override fun backupRulesConfigured(): Boolean {
        requireConfigured()
        backupRulesCache?.let { return it }
        val context = applicationContext ?: return false
        val result = try {
            declaresBackupRules(context)
        } catch (t: Throwable) {
            // Reading the manifest is a diagnostic nicety; it must never fail a call.
            android.util.Log.w(TAG, "Could not inspect host backup rules", t)
            false
        }
        backupRulesCache = result
        return result
    }

    // ---------------------------------------------------------------- internals

    /**
     * Applies [config] to the process-wide SDK singleton, or explains why it cannot.
     *
     * [MB_DeviceIntel.init] opens with `if (isInitialized) return` (MB_DeviceIntel.kt:91-92), so a
     * second init with different values is silently ignored by the SDK and the first config keeps
     * running. That is invisible from Dart and bites hardest under Flutter hot restart, which
     * re-runs Dart `main()` without restarting the host process. We track what we applied and
     * refuse instead of pretending.
     */
    private fun applyConfig(context: Context, config: MbConfig) {
        synchronized(CONFIG_LOCK) {
            val previous = appliedConfig
            if (previous != null) {
                // Only what Android applies is compared: `config.ios` is ignored on this
                // platform by design, so a difference there is not a different configuration.
                if (previous == config.copy(ios = previous.ios)) return // identical: a no-op
                throw FlutterError(
                    "already_configured",
                    "MB_DeviceIntel was already configured with a different configuration and the " +
                        "native SDK cannot be re-initialised: MB_DeviceIntel.init() returns early " +
                        "when already initialised, so the first configuration stays in effect. " +
                        "Fully restart the host process (a Flutter hot restart is not enough - it " +
                        "restarts Dart, not the process) and configure once with the new values."
                )
            }
            if (MB_DeviceIntel.isInitialized()) {
                throw FlutterError(
                    "already_configured",
                    "MB_DeviceIntel was already initialised by native host code before the Flutter " +
                        "plugin configured it, so this configuration was NOT applied - including " +
                        "uploadOnGetId=false and the error callback this plugin relies on. Remove " +
                        "the native MB_DeviceIntel.init() call, or drive the SDK from native only."
                )
            }
            MB_DeviceIntel.init(context, buildSdkConfig(config))
            appliedConfig = config
        }
        reportUnavailableCollectors(context, config)
    }

    /**
     * Reports opt-in collectors this app cannot actually satisfy, on the error stream.
     *
     * `collectAdvertisingId` is the one that matters: deviceintel-lib reads the GAID through
     * `AdvertisingIdClient`, which ships in `play-services-ads-identifier` and is on nobody's
     * classpath unless the host app adds it - the SDK's POM pulls only retrofit, okhttp and
     * coroutines. On targetSdk 33+ it additionally needs the `AD_ID` permission, which no
     * manifest here declares. Miss either and the SDK's reflective lookup just fails: configure()
     * succeeds, nothing is raised, and every fingerprint carries a null `gaid` for the life of
     * the integration.
     *
     * Reported rather than thrown, and only when the collector was asked for. A client who opted
     * in gets told once, on the channel the contract already documents for things that cannot be
     * thrown; a client who did not opt in hears nothing. Failing configure() outright would break
     * an app that set the flag optimistically.
     */
    private fun reportUnavailableCollectors(context: Context, config: MbConfig) {
        if (!config.android.collectAdvertisingId) return

        val missing = buildList {
            if (!classExists("com.google.android.gms.ads.identifier.AdvertisingIdClient")) {
                add(
                    "the com.google.android.gms:play-services-ads-identifier dependency is not on " +
                        "the app's classpath"
                )
            }
            // targetSdk, not the device's API level: the AD_ID requirement applies to
            // apps TARGETING 33+, on any device. Gating on SDK_INT warned an app
            // targeting 32 on an Android 13 phone and skipped an app targeting 33 on
            // an older one.
            if (context.applicationInfo.targetSdkVersion >= Build.VERSION_CODES.TIRAMISU &&
                !declaresPermission(context, AD_ID_PERMISSION)
            ) {
                add("the app's manifest does not declare $AD_ID_PERMISSION, required on API 33+")
            }
        }
        if (missing.isEmpty()) return

        ErrorRelay.emit(
            MbError(
                code = "unsupported",
                message = "collectAdvertisingId was requested but cannot work in this app: " +
                    missing.joinToString(" and ") + ". The advertising id will be null on every " +
                    "fingerprint until this is fixed; the rest of the fingerprint is unaffected."
            )
        )
    }

    // Both probes catch Throwable, not the one exception each obviously throws. They run
    // inside configure() after the SDK has initialised, and a diagnostic must never be the
    // reason configure() fails: Class.forName with initialize=false still raises
    // NoClassDefFoundError when a superclass is absent (a half-present play-services is
    // exactly the situation this code is looking at), and getPackageInfo can surface a
    // wrapped RuntimeException on an oversized parcel.
    //
    // They fail in OPPOSITE directions, deliberately. classExists answers "missing", so a
    // class that cannot be loaded is reported, which is correct: the SDK's own lookup fails
    // the same way and falls back to a null gaid. declaresPermission answers "declared", so
    // a lookup that throws never invents a warning.
    private fun classExists(name: String): Boolean =
        try {
            Class.forName(name, false, javaClass.classLoader)
            true
        } catch (_: Throwable) {
            false
        }

    private fun declaresPermission(context: Context, permission: String): Boolean =
        try {
            context.packageManager
                .getPackageInfo(context.packageName, PackageManager.GET_PERMISSIONS)
                .requestedPermissions
                ?.contains(permission) == true
        } catch (_: Throwable) {
            // Treated as declared, so a failed lookup never invents a warning.
            true
        }

    private fun buildSdkConfig(config: MbConfig): MB_DeviceConfig {
        val sdkConfig = MB_DeviceConfig(
            apiKey = config.apiKey,
            // Forced. The SDK default is true (MB_DeviceConfig.kt:85), which makes every
            // getDeviceId() collect and upload a full fingerprint in the background
            // (MB_DeviceIntel.kt:130-132). The contract says getDeviceId() never uploads.
            uploadOnGetId = false,
            // The SDK has one boolean where the contract has five levels: debugMode gates its
            // logcat chatter AND flips OkHttp to BODY logging (UploadManager.kt:149-154). Only the
            // most verbose contract level earns that.
            debugMode = config.logLevel == MbLogLevel.DEBUG,
            errorCallback = ErrorRelay,
            // Opt-in collectors, passed through as-is. The Dart facade sends the SDK's own
            // defaults (all off, 30-minute max age) unless the app changed them. The SDK never
            // requests a permission for any of these; the host app must hold it.
            collectLocation = config.android.collectLocation,
            locationMaxAgeMs = config.android.locationMaxAgeMs,
            collectAdvancedSignals = config.android.collectAdvancedSignals,
            collectAdvertisingId = config.android.collectAdvertisingId
            // Not exposed: collectionTimeoutMs (read by nothing in deviceintel-lib 1.7.3),
            // retryCount and compressEnabled (upload-transport tuning), uploadOnGetId and
            // errorCallback (owned by this plugin, above). SDK defaults apply.
        )
        val endpoint = config.endpoint
        return if (endpoint.isNullOrBlank()) {
            sdkConfig
        } else {
            // Retrofit rejects a baseUrl that does not end in '/', and it does so lazily inside
            // UploadManager's `by lazy { createApi() }` - i.e. on the first upload, far from this
            // call. Normalise here so a missing slash cannot become a mystery upload failure.
            sdkConfig.copy(baseUrl = if (endpoint.endsWith("/")) endpoint else "$endpoint/")
        }
    }

    private fun requireConfigured() {
        if (appliedConfig == null) {
            // Deliberately not driven by the SDK's own IllegalStateException: its text is an
            // implementation detail and it is not thrown by every entry point (getPendingUploadCount
            // returns 0 when uninitialised, MB_DeviceIntel.kt:186).
            throw FlutterError(
                "not_configured",
                "MubeenFlutter.configure() has not completed successfully. Call configure() first."
            )
        }
    }

    private fun declaresBackupRules(context: Context): Boolean {
        // Parens matter: Kotlin's infix `and` binds looser than `==`.
        if ((context.applicationInfo.flags and ApplicationInfo.FLAG_ALLOW_BACKUP) == 0) return false

        // Not `openXmlResourceParser("AndroidManifest.xml")`: cookie 0 searches every APK
        // loaded into the AssetManager, last-added first, so it can return a split APK's or
        // the WebView provider's manifest instead of the app's.
        val assets = context.assets
        val cookie = findBaseManifestCookie(context.packageName) { assets.openXmlResourceParser(it, MANIFEST) }
            ?: return false

        var hasFullBackupContent = false
        var hasDataExtractionRules = false
        val parser = assets.openXmlResourceParser(cookie, MANIFEST)
        try {
            var event = parser.eventType
            while (event != XmlPullParser.END_DOCUMENT) {
                if (event == XmlPullParser.START_TAG && parser.name == "application") {
                    for (i in 0 until parser.attributeCount) {
                        // A non-zero resource value means the attribute points at an @xml/...
                        // resource. `android:fullBackupContent="false"` resolves to 0 here and is
                        // correctly not counted as "declares rules".
                        if (parser.getAttributeResourceValue(i, 0) == 0) continue
                        when (parser.getAttributeNameResource(i)) {
                            android.R.attr.fullBackupContent -> hasFullBackupContent = true
                            android.R.attr.dataExtractionRules -> hasDataExtractionRules = true
                        }
                    }
                    break
                }
                event = parser.next()
            }
        } finally {
            parser.close()
        }

        return if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
            hasDataExtractionRules || hasFullBackupContent
        } else {
            hasFullBackupContent
        }
    }

    /**
     * Runs [block] on [Dispatchers.IO] and rethrows any failure as a `FlutterError`, which is the
     * only exception type Pigeon's generated `wrapError` turns into a contract code string - an
     * unwrapped throwable would reach Dart as its Java class name instead. A fingerprinting SDK
     * must never take the host down.
     */
    private suspend fun <T> onIo(block: () -> T): T = withContext(Dispatchers.IO) {
        try {
            block()
        } catch (t: Throwable) {
            throw asFlutterError(t)
        }
    }

    private fun asFlutterError(t: Throwable): FlutterError = when (t) {
        is FlutterError -> t
        else -> {
            android.util.Log.w(TAG, "Native SDK call failed", t)
            FlutterError("unknown", "${t.javaClass.simpleName}: ${t.message}")
        }
    }

    internal companion object {
        private const val TAG = "MubeenFlutter"

        /** Required from targetSdk 33 to read the advertising id. Declared by the host app. */
        private const val AD_ID_PERMISSION = "com.google.android.gms.permission.AD_ID"

        /**
         * The host app's manifest cannot change while the process lives, so this is computed
         * once per PROCESS. It sits on the companion deliberately: as an instance field every
         * additional Flutter engine (background isolate, add-to-app) would redo the manifest
         * scan that this cache exists to avoid.
         */
        @Volatile
        private var backupRulesCache: Boolean? = null
        private const val MANIFEST = "AndroidManifest.xml"

        /** Asset cookies are small consecutive ints; an app never loads this many APKs. */
        private const val MAX_ASSET_COOKIE = 64

        /**
         * The asset cookie whose `AndroidManifest.xml` is the base APK's: its root
         * `<manifest>` names [packageName] and has no `split` attribute. Split APKs name the
         * same package with a `split`; the framework, shared libraries and the WebView
         * provider name other packages. Null when none matches.
         */
        internal fun findBaseManifestCookie(
            packageName: String,
            open: (cookie: Int) -> XmlPullParser,
        ): Int? {
            for (cookie in 1..MAX_ASSET_COOKIE) {
                val parser = try {
                    open(cookie)
                } catch (e: Exception) {
                    continue // no such cookie, or an asset path without a manifest
                }
                try {
                    if (isBaseManifest(parser, packageName)) return cookie
                } catch (e: Exception) {
                    // An unreadable manifest is not the one we want.
                } finally {
                    (parser as? AutoCloseable)?.close()
                }
            }
            return null
        }

        private fun isBaseManifest(parser: XmlPullParser, packageName: String): Boolean {
            var event = parser.eventType
            while (event != XmlPullParser.START_TAG && event != XmlPullParser.END_DOCUMENT) {
                event = parser.next()
            }
            return event == XmlPullParser.START_TAG &&
                parser.name == "manifest" &&
                parser.getAttributeValue(null, "package") == packageName &&
                parser.getAttributeValue(null, "split") == null
        }

        private val CONFIG_LOCK = Any()

        /**
         * The config we handed to the SDK, or null if we never did. Process-scoped, like
         * [MB_DeviceIntel] itself, so a second Flutter engine sees the same truth as the first.
         */
        @Volatile
        internal var appliedConfig: MbConfig? = null

        /**
         * Whether the "linkage/custom were not sent" warning has been emitted. Process-scoped so
         * a second engine does not repeat it: the limitation belongs to the linked SDK.
         */
        private val linkageDropWarned = AtomicBoolean(false)

        /** Test seam: the SDK singleton and this field both outlive a single test. */
        internal fun resetConfigStateForTesting() {
            appliedConfig = null
            // Also process-wide, and a test that reaches backupRulesConfigured() populates it
            // for the rest of the JVM. Leaving it would make the first test written for the
            // other branch pass or fail depending on what ran before it.
            backupRulesCache = null
            linkageDropWarned.set(false)
        }
    }
}

/**
 * Bridges the SDK's process-wide [ErrorCallback] to every attached Flutter engine.
 *
 * The SDK captures the callback at `init()` and never releases it, so this is an object rather
 * than a plugin field - it keeps the leak to one stateless singleton instead of a whole engine.
 * The SDK is one per process but engines are not (background isolates, add-to-app), so each
 * attached engine registers its own [MubeenFlutterApi] in [apis] and every error goes to all
 * of them. An engine whose Dart side never called `configure()` has no handler, and its send
 * fails with a channel error that is logged and dropped.
 */
internal object ErrorRelay : ErrorCallback {

    /**
     * Process-lifetime, like this object: the SDK never releases the callback, so there is no
     * detach point at which cancelling would be correct. Engines leave [apis] on detach instead.
     */
    private val main = CoroutineScope(SupervisorJob() + Dispatchers.Main)

    /** One entry per attached engine. Empty between detach and the next attach. */
    internal val apis = CopyOnWriteArrayList<MubeenFlutterApi>()

    override fun onError(error: DeviceIntelError) =
        emit(MbError(code = mapCode(error), message = error.toString()))

    /** Delivers [payload] to every attached engine. Also used for errors the plugin itself raises. */
    internal fun emit(payload: MbError) {
        // The SDK fires this from OkHttp / its own IO scope (UploadManager.kt:33-70). Pigeon must
        // be called on the platform thread, and its generated onError is a suspend fun that waits
        // for the Dart reply - so this is launched, never awaited: Dart cannot fix a delivery
        // failure and an upload error must not block the SDK's IO thread.
        for (api in apis) {
            main.launch {
                // Re-checked on the main thread: the engine may have detached meanwhile.
                if (api !in apis) return@launch
                try {
                    api.onError(payload)
                } catch (t: Throwable) {
                    android.util.Log.w("MubeenFlutter", "Dropping SDK error for one engine", t)
                }
            }
        }
    }

    /** The exact text deviceintel-lib 1.7.3 reports for a missing INTERNET permission. */
    private const val MISSING_INTERNET_PERMISSION = "Cannot upload fingerprint: Missing INTERNET permission."

    /** The prefix of every transport failure deviceintel-lib 1.7.3 reports (UploadManager.kt:53,107). */
    private const val NETWORK_ERROR_PREFIX = "Network error during upload: "

    /**
     * Maps a [DeviceIntelError] onto the contract's code strings, from its [ErrorType] and cause
     * first and only then from exact message prefixes the SDK emits - never by searching the
     * message for numbers, because transport messages carry host names, IPv6 addresses and
     * certificate pins that contain `401`, `403` or `429` by accident.
     *
     * What deviceintel-lib 1.7.3 actually reports (every `DeviceIntelError(` in its sources, and
     * the same strings in the published AAR):
     * - `UPLOAD_FAILURE` "Network error during upload: ..." with an [IOException] cause:
     *   `network`.
     * - `UPLOAD_FAILURE` "Cannot upload fingerprint: Missing INTERNET permission. ...", sometimes
     *   with an [IOException] cause: `unknown`. A permanent setup mistake, not a transient
     *   network fault; its message names the fix.
     * - `UPLOAD_FAILURE` "Unexpected error during upload: ...": `unknown`.
     * - `FINGERPRINT_COLLECTION` and `DEVICE_ID_GENERATION`, whatever the cause: `unknown`.
     *   Collection failures are local even when the cause is an IOException.
     * - `NOT_INITIALIZED`: `not_configured`.
     *
     * `rejected` and `rate_limited` are never produced on Android: 1.7.3 reports no HTTP status
     * to the callback at all (a non-2xx is logged and queued, UploadManager.kt:215-230) and its
     * client-side rate limiter returns silently. Map them here once the SDK reports status codes
     * as structured data.
     */
    internal fun mapCode(error: DeviceIntelError): String = when (error.type) {
        ErrorType.NOT_INITIALIZED -> "not_configured"
        ErrorType.UPLOAD_FAILURE -> when {
            error.message.startsWith(MISSING_INTERNET_PERMISSION) -> "unknown"
            error.cause is IOException -> "network"
            error.message.startsWith(NETWORK_ERROR_PREFIX) -> "network"
            else -> "unknown"
        }
        else -> "unknown"
    }
}
