# mubeen_flutter

`mubeen_flutter` is a Flutter plugin that wraps Mubeen's two native device-fingerprinting
SDKs - `ai.mubeen:deviceintel-lib` on Android and `MubeenDeviceSDK` on iOS - behind one
Dart API. It gives you a persistent device id and a way to submit a device fingerprint to
Mubeen's backend for server-side risk scoring, e.g. at login and checkout. Android and iOS
differ in what their native SDKs can do; this plugin exposes those differences directly
instead of hiding them, so read the capability table below before you assume a method
behaves the same on both platforms.

## Install

Git dependency, pinned to a release tag:

```yaml
dependencies:
  mubeen_flutter:
    git:
      url: https://github.com/mubeen-ai/Mubeen-Flutter-SDK-public.git
      ref: v0.1.6
```

This package is not published to pub.dev. Pin the exact tag: `flutter pub get` then fetches
that release and nothing newer, so an upgrade is always a deliberate `ref` change.

**Minimum platform versions**: Android 7.0 (API 24), iOS 15.0.

**Minimum toolchain**: Flutter 3.44.0 (Dart 3.12.0). iOS needs Xcode 16 or newer - the SDK
binary needs a recent Swift compiler (tested with Xcode 26). On Android the plugin uses Flutter's
built-in Kotlin: it does not apply the Kotlin Gradle plugin itself, so Flutter's "plugins that
apply Kotlin Gradle Plugin (KGP)" warning never names it, and your app needs no Kotlin
changes for it. Tested on Flutter 3.44.0 and on current stable, for Android, for iOS
through CocoaPods (with Swift Package Manager turned off), and for iOS through Swift Package
Manager.
An existing app that kept a pre-AGP-9 Android toolchain also works without enabling built-in
Kotlin: tested on Flutter 3.44.0 with AGP 8.13.2 / Gradle 8.14.3 / Kotlin 2.3.0 and with
AGP 8.6.0 / Gradle 8.7 / Kotlin 2.0.21 (the oldest Flutter 3.44 accepts), as long as the app
declares the Kotlin Gradle plugin, as Flutter's app template does.

### iOS deployment target

The plugin needs an iOS deployment target of 15.0 or higher whichever way your app pulls in
iOS plugins. With SwiftPM (Flutter's default) that is the only change: set
the Runner target's Minimum Deployments to iOS 15.0 (step 2 below). SwiftPM downloads the
native SDK binary and verifies its checksum itself.

### iOS with CocoaPods

Your app uses CocoaPods when you turned Swift Package Manager off (it is on by default on
every Flutter this plugin supports) with
`flutter config --no-enable-swift-package-manager`. The native SDK binary ships inside the
plugin, so `pod install` downloads nothing extra. You need two changes, both for iOS 15.0:

1. In `ios/Podfile`, uncomment the platform line and set it to 15.0:

   ```ruby
   platform :ios, '15.0'
   ```

2. Set the Runner target's deployment target to 15.0: in Xcode, select the Runner target,
   open General, and set Minimum Deployments to iOS 15.0. That writes
   `IPHONEOS_DEPLOYMENT_TARGET = 15.0` into `ios/Runner.xcodeproj/project.pbxproj`.

Keep the rest of the Podfile Flutter generated, including `use_frameworks!`; that is the
setup this plugin is tested with. Then run `flutter build ios` (or `flutter run`), which runs `pod install`
for you. If `pod install` says the plugin requires a higher minimum deployment target,
step 1 is missing.

### Log level and your API key

`logLevel` is passed to the native SDK exactly as given, **in debug and release builds
alike** - the plugin never lowers it for you. `MubeenLogLevel.debug` turns on the native
Android SDK's `debugMode`, which switches its HTTP client to full (body-level) HTTP logging: your API key
then appears in cleartext in logcat on every upload (`X-API-Key: public_...`), and the
full request/response body is logged too. It is a publishable key, not a secret, but do not
ship a release build with `logLevel: debug`; use
`kDebugMode ? MubeenLogLevel.debug : MubeenLogLevel.warning` so a debug build stays verbose
and a release build does not. On Android, `warning` and below still allow a few unconditional
lines from the native SDK's own logger (see "Known limitations" below); none of them carries
your key, but a truncated device id can still appear.

### Changing your API key

Old app versions keep sending the key they were built with until users update. When you
switch keys (for example, moving region), ship the new key in an app update and keep the
old one active in the dashboard until adoption has caught up; revoking it earlier silently
stops fingerprints from those installs.

### Release builds (R8)

The plugin ships the Retrofit keep rules the native Android SDK's own consumer rules lack
(`android/consumer-rules.pro`). R8 full mode - the AGP 8+ default - strips generic signatures
Retrofit reads at runtime; without these rules every upload fails inside the SDK with
`ClassCastException: java.lang.Class cannot be cast to java.lang.reflect.ParameterizedType`,
which is exactly what happened to this plugin's own first release build. Consumer rules apply automatically to any module that depends on
this plugin, so you don't need to add anything to your own ProGuard config for this. If your
app has its own `proguard-rules.pro` with `-dontobfuscate` or generic-signature overrides,
nothing here conflicts - these are additive `-keep` rules, not global settings.

## Quick start

Call `configure` once at app start, before you need the device id or send any
fingerprint. Register the error callback at the same time - it is where failures that
happen after a call has returned surface (see [Delivery semantics](#delivery-semantics)).

**Every method reports failure through its returned `Future`, never by throwing
synchronously.** A missing `configure()`, an unsupported call, a bad argument (a malformed
`MubeenConfig` or a `custom` map that fails the guard below) all arrive the same way, so
`await` inside a normal `try`/`catch` catches everything - there is nothing to catch outside
the `await`. The only exception is the `capabilities` getter, which is synchronous and
throws `MubeenNotConfiguredError` directly if read before `configure()` completes.

```dart
import 'package:flutter/foundation.dart';
import 'package:mubeen_flutter/mubeen_flutter.dart';

/// Call once, e.g. in main() before runApp().
Future<void> configureMubeen() async {
  // Subscribe before configure: errors emitted during startup are not replayed.
  Mubeen.instance.errors.listen((MubeenError error) {
    // error is a MubeenNotConfiguredError, MubeenUnsupportedError,
    // MubeenAlreadyConfiguredError, MubeenInvalidConfigError, MubeenAuthError,
    // MubeenDisabledError, MubeenNetworkError or MubeenUnknownError. error.code carries
    // the wire code: not_configured, unsupported, already_configured, invalid_config,
    // rejected, disabled, network, rate_limited, unknown.
    debugPrint('mubeen error [${error.code}]: ${error.message}');
  });

  await Mubeen.instance.configure(
    const MubeenConfig(
      apiKey: 'public_xxxxxxxxxxxxxxxxxxxxxxxx', // must be a "public - JS client side" key
      logLevel: MubeenLogLevel.warning,
    ),
  );
}

/// Never triggers an upload.
Future<String> currentDeviceId() => Mubeen.instance.getDeviceId();

/// Call at login and at checkout. The same code runs on both platforms. Linkage
/// is only sent on iOS today: Android accepts it, uploads the fingerprint
/// without it, and reports that once on the errors stream (see the capability
/// table). Read capabilities.linkage if you need to know whether it was sent.
Future<void> sendFingerprint({String? accountId, String? paymentTokenId}) async {
  await Mubeen.instance.sendFingerprint(
    linkage: MubeenLinkage(accountId: accountId, paymentTokenId: paymentTokenId),
  );
}

// From your own async code, e.g. after a successful login:
//   await sendFingerprint(accountId: currentUser.id);
// and at checkout:
//   await sendFingerprint(accountId: currentUser.id, paymentTokenId: token.id);
```

`Mubeen` (`lib/mubeen_flutter.dart`) is the entire supported surface. `lib/src/messages.g.dart`
holds the raw Pigeon-generated channel bindings (`MubeenHostApi`, `MubeenFlutterApi`,
`MbConfig`, and friends) that `Mubeen` wraps - it is regenerated on every channel-contract
change, so importing it directly will break you on a patch release.

`sendFingerprint`'s optional `custom` map is validated in Dart before it ever reaches the
channel, in release builds too, not just debug. `sendFingerprint()` throws `ArgumentError`
through its `Future` for:

- a `custom` key not in `MubeenConfig.allowedCustomKeys`;
- a `custom` key named `account_id`, `payment_token_id`, `email` or `phone` - those go
  through `linkage` instead, and listing one of those names in `allowedCustomKeys` itself
  is also rejected;
- a `custom` value that contains an email address, or a phone number in international form
  (`+` or `00`, then 8-15 digits, the first not zero, with spaces/dots/dashes/parentheses allowed
  between them);
  fullwidth characters, Arabic-Indic and Persian digits and percent-escapes such as `%40`
  are folded before matching, and invisible format characters (zero-width spaces, soft
  hyphens) are removed. A `00` directly after identifier punctuation (`-`, `_`, `.`, `,`,
  `(`, `)` or a dash) is read as a zero-padded id, so `ORD-00123456789` passes. Other `00`
  shapes, such as `tel:00966...`, `phone=00966...`, a quoted number or one after a slash, are
  caught, and a value that starts with `00` followed by a non-zero digit, 8-15 digits in
  total, is always rejected. A `+` or `00` number glued to a letter or digit, as in
  `INV00966501234567`, is not matched;
- more than 30 `custom` keys, or a `custom` map that serializes to more than 4096 bytes of
  JSON.

**This is a safety net for mistakes, not a PII detector.** National-format phone numbers
(`0551234567`), government ids, ISO-8601 dates and times, UUIDs, prices, order ids and epoch
timestamps all pass - there is no way to tell a national id from an order id by shape alone.
`MubeenConfig.allowedCustomKeys` is the real control: only put keys there that you have
checked do not carry personal data. Personal identifiers always belong in `linkage`, which
the native SDK hashes before it leaves the device; iOS drops a linkage-named key from a raw
Pigeon call as a second line of defence, but the Dart-level check above already rejects it
first for every normal caller.

## Capability table

This is the most important section in this file. Read it before you call anything you
haven't seen in the quick start above.

| Method | Android | iOS | Error where a platform lacks it |
|---|---|---|---|
| `configure(config)` | Calls `MB_DeviceIntel.init(appContext, cfg)`; the plugin forces `uploadOnGetId = false` regardless of what you pass. Idempotent for an identical config. | Calls `Mubeen.configure(...)`. Idempotent for an identical config; the configured state is process-wide, so a second `FlutterEngine` sees it too. | Both platforms: validated in Dart first (blank `apiKey`, a malformed `endpoint` or one that is not `https`, except `http` to a local test host (`localhost`, `127.0.0.1`, `::1`, `10.0.2.2`), a linkage name in `allowedCustomKeys`, ...) with `ArgumentError` through the `Future` before anything reaches the native side. Then throws `MubeenAlreadyConfiguredError` (wire code `already_configured`) if you call it again with **different** values, including a different `allowedCustomKeys`. Neither native SDK reports a repeat call (Android keeps the first config, iOS silently re-configures), so the plugin tracks its own configured state and throws `already_configured` on a differing re-configure - see [Troubleshooting](#troubleshooting). Concurrent calls are safe: an identical call made while one is already running shares that call's result; a differing one throws `MubeenAlreadyConfiguredError` immediately; a failed call leaves the instance unconfigured and can be retried. |
| `MubeenConfig.android` / `MubeenConfig.ios` (native options) | `android` (`MubeenAndroidOptions`) maps onto `MB_DeviceConfig`; `ios` is ignored. | `ios` (`MubeenIosOptions`) maps onto `MubeenConfig`; `android` is ignored. | Never throws for the other platform's group: it is ignored by design, including when `configure()` decides whether a repeat call differs. Defaults equal each native SDK's own. See [Optional collectors](#optional-collectors). |
| `getDeviceId()` | Returns the persistent UUIDv7 from `getDeviceId()`. | Returns `Mubeen.deviceId`. | Throws `MubeenNotConfiguredError` if called before `configure()` completes. Otherwise supported on both. |
| `sendFingerprint({linkage, custom})` | Calls `uploadFingerprint()`. `linkage` and `custom` are accepted but **not sent**: the Android SDK's upload payload is fixed today and has no field for either. The fingerprint is uploaded without them, and the first time this happens in the process a `MubeenUnsupportedError` warning (wire code `unsupported`) is delivered on `Mubeen.instance.errors`; it is not repeated. | Calls `sendFingerprint(metadata:)`. `linkage` fields (`accountId`, `paymentTokenId`, `email`, `phone`) are hashed by the native SDK before transmission; `custom` values are sent as plain strings. | Throws `ArgumentError` on either platform, through the returned `Future`, if `custom` fails the Dart-side PII/size guard - see the quick start above. The guard runs on Android too, even though Android does not send `custom`, so a bad map fails the same way on both platforms. Passing `linkage` or `custom` never throws on Android; Android linkage support is tracked for a future `deviceintel-lib` release (1.8), and `capabilities.linkage` stays `false` until then. On iOS, if Mubeen's remote kill switch is on, throws `MubeenDisabledError` (wire code `disabled`) instead of uploading - see [Delivery semantics](#delivery-semantics). |
| `resetDeviceId()` | `clearDeviceId()` followed by `getDeviceId()`. | `Mubeen.resetDeviceId()`. | Throws `MubeenNotConfiguredError` if called before `configure()` completes. Otherwise supported on both. |
| `getFingerprint()` | Returns the full fingerprint as a JSON string. | No equivalent. SDK 2.0 is one-way submit only; there is no call that returns the fingerprint to the app. | Throws `MubeenUnsupportedError` on iOS. Check `capabilities.rawFingerprint` first. |
| `pendingUploadCount()` | Counts only uploads that **already failed** and are waiting to be retried. It reads `0` before a send, during a successful send, and after one, so it can never confirm a success - it is a failure-backlog gauge, not a progress indicator. Before `configure()` it throws `MubeenNotConfiguredError`: the Android SDK would answer `0`, and the plugin does not pass that through, because an uninitialised `0` is indistinguishable from an empty queue. | No equivalent. The retry queue is internal to the SDK and not introspectable. | Throws `MubeenUnsupportedError` on iOS, deliberately, instead of returning a fake `0` that would look like "queue empty." Check `capabilities.pendingUploadCount` first. |
| `capabilities` (getter, cached from `configure()`) | Returns `linkage: false` (until Android gets linkage support), `rawFingerprint: true`, `pendingUploadCount: true`. | Returns `linkage: true`, `rawFingerprint: false`, `pendingUploadCount: false`. | Throws `MubeenNotConfiguredError` if read before `configure()` completes; otherwise never throws. It's a synchronous property, not a method - use it to branch instead of catching `MubeenUnsupportedError`, as in the quick start above. |
| Auto Backup check (internal - not a public `Mubeen` method) | Run automatically, debug builds only, at the end of `configure()`. It only checks whether the merged manifest declares a `fullBackupContent` / `dataExtractionRules` attribute; it cannot see whether those rules include the SDK's prefs file. It logs a `debugPrint` warning when it finds no such attribute, which also happens for an app with no rules at all, where the platform default already keeps the id. Treat the warning as a prompt to check your backup setup (see [Auto Backup](#auto-backup-android) below), not as a verdict. There's no method to call this yourself - it wraps the raw Pigeon `backupRulesConfigured()` host call, which isn't exposed on `Mubeen`. | Runs, and always passes: the iOS side answers `true` because persistence is Keychain-based, not manifest-based, so there is nothing to check. The device id lives in the Keychain, which survives reinstalls on the same device. | Never throws out to your code - a failed check is swallowed so it can never break startup. |
| `Mubeen.instance.errors` (`Stream<MubeenError>`) | Delivered for transport failures (offline, DNS, TLS, timeout) as `MubeenNetworkError` (wire code `network`), usually twice per failed call; a missing INTERNET permission (the plugin's own manifest declares it, so this only happens if your app removes it); device-id storage failures and collection faults; a `MubeenUnsupportedError` warning when `collectAdvertisingId` is on but its dependency or the `AD_ID` permission is missing (see [Optional collectors](#optional-collectors)), and a one-time `MubeenUnsupportedError` warning the first time `sendFingerprint()` is given `linkage` or `custom` it cannot send. **Not** delivered for a rejected upload: a non-2xx response is logged and re-queued without notifying the stream. | Delivered for queued-upload failures (`429`, `5xx`); terminal `4xx` throws from the call itself as a `MubeenError` subtype. Transport failures (offline, DNS, TLS, timeouts) currently produce **no error at all** - see "Known limitations". | The closest thing to a delivery signal, but read the per-platform limits below before relying on it. If your app runs several `FlutterEngine`s (add-to-app, background isolates), every engine that has called `configure()` receives every async error - one engine detaching only removes its own channel. |

## Optional collectors

Each native SDK has its own optional configuration. The plugin exposes all of it that an app
can use, one group per platform, instead of trimming to what both platforms share:

```dart
await Mubeen.instance.configure(
  const MubeenConfig(
    apiKey: 'public_xxxxxxxxxxxxxxxxxxxxxxxx',
    android: MubeenAndroidOptions(collectLocation: true), // used on Android only
    ios: MubeenIosOptions(enableBehavioralSignals: true), // used on iOS only
  ),
);
```

The `android` group is applied on Android and ignored on iOS; the `ios` group is applied on
iOS and ignored on Android. That is by design, not a silent drop: the other platform's SDK has
no such setting. Set both groups unconditionally; there is no need for a platform check.

**Every default equals the native SDK's default.** An app that passes neither group gets
exactly the behavior it had before these options existed, and takes on no new store
disclosure. The privacy-sensitive collectors are all off by default. Neither native SDK ever
requests a permission: an option only unlocks a signal when your app already holds the
matching permission, and the signal is null otherwise.

The options take part in the `already_configured` check on the platform that applies them, so
changing one needs a full app restart (see [Troubleshooting](#troubleshooting)).

### Android (`MubeenAndroidOptions`, `deviceintel-lib` 1.7.3)

| Option | Default | What it adds to the fingerprint | Permission your app must request | Disclosure it creates |
|---|---|---|---|---|
| `collectLocation` | `false` | The device's last-known location: `latitude`, `longitude`, `location_accuracy_meters`, `location_timestamp`, `location_provider`, `location_is_coarse`. A cached fix only; the SDK never starts a GPS request, so collection never waits on it. | `ACCESS_FINE_LOCATION` or `ACCESS_COARSE_LOCATION` (runtime). | Google Play prominent disclosure for location, the Data Safety form, and privacy-policy and consent coverage for precise location. |
| `locationMaxAge` | 30 minutes | Nothing on its own. A cached fix older than this is reported as null. Only used when `collectLocation` is on. Must not be negative. | None. | None. |
| `collectAdvancedSignals` | `false` | Each only with its own permission: WiFi `wifi_ssid` / `wifi_bssid`; Bluetooth `bluetooth_name` / `bonded_device_count`; `phone_number`; `data_network_type`. Carrier, SIM and network metadata and adapter on/off state are collected either way; this flag does not control them. | WiFi: `ACCESS_FINE_LOCATION` plus `ACCESS_WIFI_STATE`, with location services on. Bluetooth: `BLUETOOTH_CONNECT` (Android 12+) or `BLUETOOTH` (below 12). Phone number: `READ_PHONE_NUMBERS` or `READ_PHONE_STATE`. Data-network type: `READ_PHONE_STATE`, or `READ_BASIC_PHONE_STATE` on Android 12+. | Google Play Data Safety disclosure, and privacy-policy and consent coverage. |
| `collectAdvertisingId` | `false` | The Google Advertising ID as `device_detail.gaid`, read through `AdvertisingIdClient`, so a user who opted out of ad personalization yields null. | Add the `com.google.android.gms:play-services-ads-identifier` dependency (without it `gaid` is null) and declare `com.google.android.gms.permission.AD_ID` in your manifest (required when your app targets API 33+). If either is missing, `configure()` still succeeds and the plugin sends a `MubeenUnsupportedError` warning on `errors` naming what is missing. | Declare advertising-ID collection in the Google Play Data Safety form and your privacy policy. |

Worth knowing on Android:

- On apps targeting API 30+, `phone_number` is usually null even with the permission granted,
  unless your app is the default SMS or dialer app or has carrier privileges. A null does not
  mean the permission is missing.
- Location, SSID/BSSID, phone number and Bluetooth name are masked before the SDK's upload
  logging writes them to logcat.
- Not exposed, on purpose: `collectionTimeoutMs` (nothing in `deviceintel-lib` 1.7.3 reads
  it, so it would be a switch that does nothing), `retryCount` and `compressEnabled`
  (upload-transport tuning), and `uploadOnGetId` and `errorCallback` (the plugin owns them,
  see the capability table). They stay at the SDK defaults.
- The native SDK exposes `okhttp`, `logging-interceptor`, `retrofit` and
  `kotlinx-coroutines` to your app (they are not hidden behind `implementation` in the
  SDK's own POM). If your app also depends on OkHttp directly, keep `okhttp` and
  `logging-interceptor` on the same version - for example by importing `okhttp-bom` - since
  OkHttp does not support mixed versions between its own artifacts. See "Known limitations".

### iOS (`MubeenIosOptions`, `MubeenDeviceSDK` 2.0.0)

| Option | Default | What it does | Permission your app must request | Disclosure it creates |
|---|---|---|---|---|
| `environment` | `MubeenIosEnvironment.production` | Sent as the fingerprint's `environment` field (`production` or `sandbox`). | None. | None. |
| `enableJailbreakChecks` | **`true`** | Runs the jailbreak and tamper scan (jailbreak file paths, a restricted write outside the sandbox, debugger, Frida and sideload detection) that fills `jailbreak_tamper`. This one is on by default: turning it off removes a signal, it does not add one. When off, `jailbreak_tamper` is still sent, with zeroed scores, so a score of 0 then means "not checked", not "clean". | None. | None beyond the defaults below; the SDK already reports these signals as diagnostic data. |
| `enableBehavioralSignals` | `false` | Adds the `behavior` block: `session_event_count` and `foreground_session_length_ms` (the block also carries `tap_cadence_summary`, which SDK 2.0.0 always marks disabled, and `navigation_pattern_hash`, always null). When off, `behavior` is null. | None. | The native docs name no extra App Store privacy label entry for it, and the SDK's privacy manifest does not declare one. It is app-usage data, so have whoever owns your privacy label decide whether it belongs under Usage Data. |

## Delivery semantics

**`sendFingerprint()` completing does not mean the backend received anything.** It means
accepted-or-queued, never confirmed-delivered. Concretely:

- **Android**: `uploadFingerprint()` is fire-and-forget. The Dart call resolves within
  milliseconds, once the native SDK has accepted the request; collection and the upload run
  afterwards, and there is no completion signal tied to the actual HTTP result.
- **iOS**: collection and the first upload attempt finish **before** the call returns
  (about 150 ms on a current iPhone). A `2xx` completes it. Any other `4xx` except
  `404`/`405`/`429` (e.g. `400`/`401`/`403`) throws `MubeenAuthError` from the call, and `404`/`405` throw `MubeenInvalidConfigError` (a
  wrong route, not a wrong key). On `429`, `5xx`, or when offline, the SDK queues the payload
  and the call **returns normally**. It also throws `MubeenDisabledError` while Mubeen's
  kill switch is on (see below).

Because of this, `await sendFingerprint(...)` returning without an exception tells you
almost nothing about whether the fingerprint actually reached Mubeen. Register the
`Mubeen.instance.errors` stream as shown in the quick start, and treat a
missing error as "nothing failed yet," not as "delivered."

**How far that signal reaches differs by platform today:**

- **Android: a rejected upload is currently invisible.** On a non-2xx response the native
  SDK logs it and re-queues the payload without notifying the error callback. A wrong API key (HTTP 401) therefore looks exactly like a
  success from Dart. What does reach the callback on Android: transport failures (offline,
  DNS, TLS, timeout) as `MubeenNetworkError` (wire code `network`), a missing INTERNET
  permission, device-id storage failures, collection faults, and the one-time warning
  that `linkage`/`custom` were not sent. `pendingUploadCount()` is
  the only client-side backstop: a rejected upload stays queued, so it reads above `0`
  after one. Until this is fixed in the native SDK, confirm a new integration server-side
  rather than trusting client-side silence. When a failure does reach the callback, expect
  **two** `network` events for one `sendFingerprint()` call, not one - see the
  two-requests-per-failure point below; if your monitoring counts errors for alerting,
  count events in pairs.
- **iOS: rejections do surface, but transport failures are currently silent.** Terminal
  `4xx` responses (other than `404`/`405`/`429`) throw from the call itself, and `429`/`5xx` reach the error callback.
  Offline, DNS failure, TLS failure and timeouts produce **no throw and no error event at
  all** - the payload silently joins the 50-item retry queue and is dropped oldest-first if
  it never sends. This includes an `endpoint` set to a host that App Transport Security
  blocks in a release build. Do not read a quiet `errors` stream
  on iOS as proof of delivery; verify server-side for a new integration, same as Android.
- **iOS: the kill switch is a soft no-op, not an error to alarm on.** If Mubeen has
  switched submissions off remotely, `sendFingerprint()` fails with `MubeenDisabledError`
  (wire code `disabled`) instead of uploading. This is not a key or config problem and
  retrying will not help until Mubeen turns submissions back on - catch it and continue
  your flow rather than surfacing it to the user or paging on it.

More limits worth knowing before you go looking for a bug that isn't one:

- The Android SDK drops uploads past **5 per minute**. Dropped uploads are silent.
- The Android SDK's retry queue is in memory only. If the process is killed, queued
  uploads are gone - they do not survive a restart.
- A failed upload costs **two** requests, not one: the retry queue is processed
  immediately on failure, so the payload is re-sent right away. Budget for that if you
  are counting requests.
- That immediate re-send is the only retry. A payload still failing after it stays in the
  queue (`pendingUploadCount()` reads 1) and is attempted again only when a *later* upload
  fails; a later successful upload does not flush it.
- **A `2xx` from the server confirms the request was accepted, not that it was stored.**
  Verifying a new integration server-side is the only reliable check.
- **Several `FlutterEngine`s in one process** (add-to-app, background isolates from a push
  plugin or a scheduled-task plugin) share the native SDK, which is process-wide on both
  platforms. A
  second engine's `configure()` with identical values is a no-op success; with different
  values it throws `MubeenAlreadyConfiguredError`, same as a second call on one engine. An
  async error is delivered to every engine that has called `configure()`, and one engine
  detaching only removes its own channel - the others keep receiving errors as before.

## Auto Backup (Android)

The Android SDK persists the device id in a SharedPreferences file
(`MB_device_intel_secure_prefs`) and relies on Android's own Auto Backup to carry it
across a reinstall. What you need to do depends on your manifest:

- **No backup rules declared** (no `android:fullBackupContent` or
  `android:dataExtractionRules`): nothing to do. The platform default backs up all shared
  prefs, including the SDK's.
- **Backup rules declared**: add the `<include>` lines shown below to your rules.
- **`android:allowBackup="false"`**: the device id will not survive a reinstall.

If you add the lines, put the `<include>` for the SDK's prefs file into your existing
rules - do not point your `fullBackupContent` /
`dataExtractionRules` attribute at the SDK's file directly, since these attributes are
include-only: doing so would restrict your app's entire backup to just the SDK's prefs and
exclude your own data.

```xml
<!-- res/xml/your_full_backup_content.xml - API <= 30 -->
<full-backup-content>
    <include domain="sharedpref" path="MB_device_intel_secure_prefs.xml" />
</full-backup-content>
```

```xml
<!-- res/xml/your_data_extraction_rules.xml - API 31+ -->
<data-extraction-rules>
    <cloud-backup>
        <include domain="sharedpref" path="MB_device_intel_secure_prefs.xml" />
    </cloud-backup>
</data-extraction-rules>
```

**Why the plugin doesn't inject this itself**: doing it from the plugin's own manifest
would risk a manifest-merger conflict if your app already declares
`android:fullBackupContent` or `android:dataExtractionRules` - that's a broken build the
first time someone runs `flutter build apk`, not a runtime warning. There is no public method
to check this yourself: the plugin runs the check automatically, in debug builds only, at the
end of `configure()`, and logs a warning when it cannot confirm the manifest declares backup
rules. It cannot see inside the rules, and an app with no rules at all also gets the warning,
so treat it as a prompt to check, not a verdict. It's silently skipped in
release builds and never throws - a failed check must not break your app's startup.

**What Auto Backup actually guarantees, stated plainly:**

- It restores the device id on **reinstall**, for the **same Google account**, with backup
  enabled. That's it.
- It does **not** survive **Clear Data / Clear Storage** - that path always mints a new id.
- A cloud restore **can carry the id onto a different physical device** (e.g. a user
  restoring their backup onto a new phone), so treat the Android device id as
  account-and-backup-scoped, not strictly device-bound.
- A **device-to-device transfer** (API 31+) can also carry the device id onto new
  hardware. Decide which you want and say so under `<device-transfer>` in your data
  extraction rules: the same `<include>` to let the id follow the user to a new phone, or an
  `<exclude>` to give each physical device its own id.

## Privacy and store compliance

**This is your responsibility as the integrating app, not something the plugin does for
you.** Neither native SDK requests a runtime permission on its own - Android's SDK needs
none of the permissions below to run (they only unlock optional signals your app already
holds the permission for), and iOS's SDK uses network access only.

**Identifiers collected by default** (the opt-in collectors - Android location, advertising
ID, advanced WiFi/Bluetooth/telephony signals, and iOS behavioral signals - are off unless you
turn them on, and each one you turn on adds the duties listed in
[Optional collectors](#optional-collectors)):

- **Android**: the persistent UUIDv7 device id; `media_drm_id` (Widevine device id,
  SHA-256 hashed, no permission needed); `android_id` (`Settings.Secure.ANDROID_ID`, no
  permission needed); `gsf_id` (Google Services Framework id - only collected if your app
  already declares `com.google.android.providers.gsf.permission.READ_GSERVICES`, otherwise
  null); plus zero-permission integrity signals (`app_signing_sha256`,
  `installer_package`, `verified_boot_state`, `bootloader_locked`, `selinux_enforcing`) and
  Tier-1 network/SIM metadata (carrier, MCC/MNC, SIM/network country, transport type) that
  rely only on permissions your app may already declare (`ACCESS_NETWORK_STATE`,
  `ACCESS_WIFI_STATE`, `BLUETOOTH`).
- **iOS**: the persistent UUIDv7 device id; `identifier_for_vendor` presence and a hash of
  it; device model, OS version, screen, locale, timezone; app bundle version and install
  age; network connection type, VPN and proxy detection; jailbreak/tamper scoring
  (including Frida and debugger detection). The SDK does not use location, contacts,
  photos, camera, or microphone.

**You must make store declarations for both platforms:**

- **Google Play Data Safety form**: declare the identifiers above as collected device
  identifiers.
- **App Store privacy label ("App Privacy" nutrition label)**: declare device
  identifiers/device ID usage.
- On both platforms: **a persistent device id plus an IDFV hash are linkable
  identifiers** - the iOS SDK's own documentation states this explicitly - and belong in
  your privacy disclosures regardless of platform.

**User identifiers must go through `linkage`, never `custom`.** The typed `linkage` field
(`accountId`, `paymentTokenId`, `email`, `phone`) is hashed by the native SDK before it
leaves the device. `custom` is for non-identifying extras only and is sent as plain
strings - putting an email, phone number, or any other PII-shaped value into `custom`
sends it in plaintext.

**Hashing a value does not remove your duty to declare it.** If you pass `linkage`, declare
Email Address, Phone Number and User ID (and Payment Info if you pass `paymentTokenId`) as
collected and **linked** to the user - not Tracking - in the App Store privacy label and the
Google Play Data Safety form, even though the native SDK hashes them before transmission.
A hash of an email or phone number is reversible in practice for a space this small
(a phone number is roughly 10^8 values), and both Apple and Google treat a hashed identifier
as personal data for label purposes, not as anonymized. If you turn on
`enableBehavioralSignals` (iOS), declare `session_event_count` and
`foreground_session_length_ms` as Usage Data / Product Interaction.

## Version table

| Plugin version | Android (`ai.mubeen:deviceintel-lib`) | iOS (`MubeenDeviceSDK`) |
|---|---|---|
| 0.1.6 | 1.7.3 | 2.0.0 |
| 0.1.5 | 1.7.3 | 2.0.0 |
| 0.1.4 | 1.7.3 | 2.0.0 |
| 0.1.3 | 1.7.3 | 2.0.0 |
| 0.1.2 | 1.7.3 | 2.0.0 |
| 0.1.1 | 1.7.3 | 2.0.0 |
| 0.1.0 | 1.7.3 | 2.0.0 |

## Troubleshooting

**Getting `429` while testing.** The mobile ingestion endpoints rate-limit per source IP,
and every device behind the same NAT'd IP shares that limit. If
your whole team is testing from one office network, you're all sharing one limit - this
is very often not an SDK bug, it's several phones on the same WiFi hitting the same limit.
Spread test devices across networks, or test sequentially, before assuming something is
broken.

**Getting an `already_configured` error.** Neither native SDK reports a second
`configure()` call: `MB_DeviceIntel.init()` on Android returns early and keeps the first
config, and `Mubeen.configure()` on iOS silently re-configures. That's invisible unless
you check for it, and it bites hardest with **Flutter hot restart**: hot restart re-runs
Dart's `main()` but does not restart the host process, so from Dart's point of view you
appear to be configuring fresh, while the native SDK underneath already holds a config from
earlier in the same process. The plugin tracks its own configured state and
throws `MubeenAlreadyConfiguredError` (wire code `already_configured`) if you call
`configure()` again with different values, so this surfaces immediately instead of silently
keeping stale config. Changing `allowedCustomKeys` counts as a different value too - it is
part of the comparison even though it never crosses the platform channel. A full app
restart (not just hot restart) always clears it.

**Getting a `401`.** Use one key of type
`public - JS client side` for both platforms; the Android ingestion endpoint rejects any
other key type with a `401` your app never sees. A key also belongs to
one region: used against another region's `endpoint` it gets a `401`, which iOS throws from
`sendFingerprint()` as `MubeenAuthError` and Android swallows silently.

**`configure()` throws `ArgumentError` for an `endpoint` that used to work.** `endpoint`
is validated in Dart: it must be an absolute URL with a host, `https` is always accepted,
and `http` is accepted only for `localhost`, `127.0.0.1`, `::1` and `10.0.2.2` (the Android
emulator's alias for the host machine), because both platforms block cleartext in release
builds. Pointing a real device at a LAN IP over `http` (a local test server on your
machine, e.g. `http://192.168.x.x:8787`) is not accepted - serve over `https`, or on Android
use `adb reverse` so the device's own `localhost`/`127.0.0.1` reaches your machine
(`10.0.2.2` only works from the emulator). Android still blocks that cleartext traffic
unless your app's debug build has a `networkSecurityConfig` permitting that host. Passing an
empty string for `endpoint` is also an error; pass `null` to get the default. A query
string, fragment, credentials (`user:pass@`), whitespace or a backslash is rejected too,
because the native SDKs append their own route to this base URL. A trailing slash is fine:
it is stripped before the value reaches native code.

## Known limitations

These are gaps in the native SDKs or the backend, not in this plugin's wrapper logic. Each
is tracked so it can be fixed upstream; this plugin cannot fix them from the wrapper layer.

- **iOS: transport failures are silent, not just rejections.** Offline, DNS
  failure, TLS failure and timeouts on iOS produce no throw and no `errors` event - see
  "Delivery semantics".
- **A client already on a newer OkHttp can hit a crash, not just a failed upload.**
  The Android SDK exposes `okhttp`, `logging-interceptor`, `retrofit` and
  `kotlinx-coroutines` to your app rather than hiding them. If your app resolves a
  different OkHttp version than the SDK's `logging-interceptor` expects, keep them in sync
  (see "Worth knowing on Android" above); this combination is not yet tested.
- **The Android SDK's classes can collide with another pre-obfuscated library.**
  Its AAR ships classes in single-letter top-level packages (`a.*`, `b.*`, `c.*`, `d.*`).
  If your app also depends on another SDK that ships similarly-named obfuscated classes,
  Android's build-time duplicate-class check can fail. There is no client-side workaround;
  it needs a repackage on the SDK side.
- **Hashed linkage values and iOS usage signals are not declared in the bundled privacy
  manifests.** The vendored SDK's `PrivacyInfo.xcprivacy` declares a device identifier,
  diagnostic data and its `UserDefaults` access, which is accurate for what the SDK itself
  does. Neither manifest mentions `linkage`, and that half is ours rather than the SDK
  vendor's: `linkage` is an API this plugin adds, carrying an email, a phone number, a user
  id and a payment token id, so the plugin's own manifest cannot be filled in upstream. It
  is left empty deliberately, because a static manifest would declare those four types for
  every app including the ones that never pass `linkage`. **If you use `linkage` or
  `enableBehavioralSignals`, declare that data yourself as described in "Privacy and store
  compliance" above; Xcode's aggregated privacy report will not do it for you.**
- **A burst of `sendFingerprint()` calls launches one full collection per call on Android.** There is no de-duplication or coalescing yet; each call runs its own
  10-25 s-on-a-slow-device collection concurrently. Call it at most once per meaningful
  event (login, checkout), not on every screen view or tap.
- **`logLevel` below `debug` does not fully silence the Android SDK's own logger.** A few of the SDK's internal log lines (upload status, a truncated device id)
  are unconditional in `deviceintel-lib` 1.7.3 regardless of the level you pass. Nothing at
  these lines is a secret, but if your release-logging policy forbids any device
  identifier in logcat, be aware the SDK does not honor `MubeenLogLevel.none` fully yet.

## Support

Report problems to engineering@mubeen.ai.

## License

Licensed under the Mubeen SDK License: see [LICENSE](LICENSE). Use requires an active
agreement with Mubeen AI. Third-party components are listed in [NOTICE](NOTICE).

