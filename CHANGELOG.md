## 0.1.5

Released 2026-10-21.

- Moved to https://github.com/mubeen-ai/Mubeen-Flutter-SDK-public. Change your git
  dependency's `url` to `https://github.com/mubeen-ai/Mubeen-Flutter-SDK-public.git` and
  `ref` to `v0.1.5`.
- Licensed under the Mubeen SDK License (`LICENSE`); third-party components are listed in
  `NOTICE`.
- Documentation updates. No code changes.

## 0.1.4

Released 2026-10-12.

- README and package docs corrected after a full review; no code changes.

## 0.1.3

Released 2026-10-11.

- Install instructions use the HTTPS repository URL, so no GitHub account or SSH key is
  needed to fetch the package. No code changes.

## 0.1.2

Released 2026-09-30.

- Android: `sendFingerprint(linkage: ..., custom: ...)` no longer throws
  `MubeenUnsupportedError`. The Android SDK (`deviceintel-lib` 1.7.3) has no field for
  either, so they are accepted, not sent, and the fingerprint is uploaded without them.
  Client code is now the same on both platforms. The first time this happens in a process,
  one `MubeenUnsupportedError` warning (wire code `unsupported`) is delivered on
  `Mubeen.instance.errors`; it is not repeated. `capabilities.linkage` stays `false` on
  Android, so read it if you need to know whether linkage was sent.
- The `custom` guard (allowlist, PII checks, size limits) still runs on Android, so a bad
  `custom` map throws `ArgumentError` on both platforms.
- iOS: unchanged.

## 0.1.1

Released 2026-09-22.

- `configure()` works where the quick start calls it, in `main()` before `runApp()`: the
  plugin now initialises the Flutter binding itself. On 0.1.0 that call fails.
- An `endpoint` with a trailing slash works on iOS. Trailing slashes are stripped before the
  value reaches native code; on 0.1.0 a trailing slash made every iOS upload fail with a
  `405`, reported as `MubeenAuthError`. `https://h/` and `https://h` also count as the same
  value for the `already_configured` check.
- `configure()` rejects an `endpoint` carrying a query string, fragment, credentials,
  whitespace or a backslash with `ArgumentError`, instead of producing a broken upload URL.
  Credentials are not echoed in the error message.
- iOS: a `404` or `405` from `sendFingerprint()` throws `MubeenInvalidConfigError` (wire code
  `invalid_config`) instead of `MubeenAuthError`, since it means a wrong route, not a wrong
  key.
- `custom` guard: a zero-padded id after identifier punctuation, such as `ORD-00123456789`
  or `INV_0098765432`, is no longer rejected as a phone number. Other `00` shapes
  (`tel:00966...`, `phone=00966...`, a quoted number) are still caught, and invisible format
  characters inside a number no longer let it slip past the check.
- Android: when `collectAdvertisingId` is on but the `play-services-ads-identifier`
  dependency or the `AD_ID` permission (for apps targeting API 33+) is missing, `configure()`
  still succeeds and a `MubeenUnsupportedError` warning arrives on `errors`. On 0.1.0 every
  fingerprint silently carried a null advertising id.
- iOS CocoaPods: the podspec no longer sets `EXCLUDED_ARCHS`, which could make `pod install`
  abort when another pod set it to a different value.
- `configure()` retry fixes: an identical retry after a failed capabilities call now finishes
  configuring instead of reporting success on an unusable instance or throwing
  `already_configured`; mutating the `allowedCustomKeys` set after a call no longer hides a
  changed configuration.
- `MubeenCapabilities` now has value equality, so it can be compared in tests.
- `LICENSE` contains only the licence terms.

## 0.1.0

Initial release. Wraps `ai.mubeen:deviceintel-lib` 1.7.3 (Android) and `MubeenDeviceSDK`
2.0.0 (iOS) behind one Dart API, generated with Pigeon for typed Kotlin/Swift/Dart
bindings.

- `configure()`, `getDeviceId()`, `sendFingerprint()`, `resetDeviceId()` on both platforms.
- `getFingerprint()` and `pendingUploadCount()` on Android only; both throw
  `MubeenUnsupportedError` on iOS rather than returning a placeholder value.
- `capabilities` so callers can branch on the per-platform capability model instead of
  catching `MubeenUnsupportedError`: Android and iOS support different subsets of
  `sendFingerprint`'s `linkage`/`custom`, `getFingerprint`, and `pendingUploadCount`, and
  the plugin throws rather than faking a value a platform's native SDK cannot produce.
- Automatic Auto Backup check on Android, debug builds only: `configure()` warns via
  `debugPrint` when it cannot confirm the manifest declares backup rules.
- Typed `linkage` (`accountId`, `paymentTokenId`, `email`, `phone`), hashed natively
  before transmission. Available on iOS today; Android throws `MubeenUnsupportedError` if passed,
  pending `deviceintel-lib` 1.8.
- `configure()` throws `MubeenAlreadyConfiguredError` (wire code `already_configured`) on a
  second call with different values; neither native SDK reports a repeat call on its own -
  this matters most under Flutter hot restart, which restarts Dart but not the host process.
- `getDeviceId()` never triggers an upload: the plugin forces the Android SDK's
  `uploadOnGetId` to `false` regardless of what is passed in `configure()`.
- Requires Flutter 3.44 / Dart 3.12.
- Uses Flutter's built-in Kotlin: the Android module does not apply the Kotlin Gradle
  plugin, as Flutter's plugin-author migration guide requires, so AGP 9+ apps get no
  "plugins that apply Kotlin Gradle Plugin (KGP)" warning for it and the plugin keeps
  building once Flutter drops support for plugins that apply KGP.
- Distributed as a git dependency, pinned to a release tag; not published to pub.dev.
- Ships the Retrofit keep rules the native Android SDK's own consumer rules lack
  (`android/consumer-rules.pro`). Without them, R8 full mode (the AGP 8+ default) strips
  generic signatures Retrofit reads at runtime and every upload fails inside the SDK with a
  `ClassCastException` on `ParameterizedType` in any release build with minification on -
  found and fixed after it broke this plugin's own first release build; verified on-device
  after the fix.
- Per-platform native options: `MubeenConfig(android: MubeenAndroidOptions(...), ios:
  MubeenIosOptions(...))`. Android gets `collectLocation`, `locationMaxAge`,
  `collectAdvancedSignals` and `collectAdvertisingId`; iOS gets `environment`,
  `enableJailbreakChecks` and `enableBehavioralSignals`. Each group applies only on its own
  platform, every default equals the native SDK's (the privacy-sensitive collectors stay off),
  and the options take part in the `already_configured` check.
- `custom` guardrail, designed so it does not reject legitimate data such as ISO-8601
  dates, UUIDs, prices and order ids in release builds. A value is refused when it contains an email address
  (including `user@localhost` and plus-addressing) or a phone number in international
  form (`+` or `00`, then 8-15 digits; spaces, dots, dashes, underscores, commas and
  parentheses allowed between digits). Fullwidth characters, Arabic-Indic and Persian
  digits and `%40` are folded before matching. National numbers and government ids are not
  detected; `allowedCustomKeys` is the control.
- `custom` keys named `account_id`, `payment_token_id`, `email` or `phone` throw
  `ArgumentError` on both platforms; so does listing them in `allowedCustomKeys`.
- The 4096-byte `custom` limit counts the UTF-8 bytes of the JSON-encoded map.
- `configure()` validates the config in Dart, identically on both platforms: a blank
  `apiKey`, an empty or relative `endpoint`, a scheme other than `https`, or `http` to any
  host other than `localhost`, `127.0.0.1`, `::1` and `10.0.2.2` throws `ArgumentError`.
- `configure()` is safe to call concurrently: identical calls share one native call, a
  differing call throws `MubeenAlreadyConfiguredError`, and a failed call can be retried.
  Changing `allowedCustomKeys` on a second call throws `MubeenAlreadyConfiguredError`.
- Every `Mubeen` method reports failure through its returned `Future`, including
  `MubeenNotConfiguredError`, `MubeenUnsupportedError` and `ArgumentError`; none throws
  synchronously.
- Error types include `MubeenInvalidConfigError` (wire code `invalid_config`) and
  `MubeenDisabledError` (wire code `disabled`, the iOS SDK's remote kill switch). Calling
  the plugin where it has no native side (web, desktop, unit tests without a mocked host)
  throws `MubeenUnsupportedError`.
- Several Flutter engines in one process (background isolates, add-to-app): async SDK
  errors reach every attached engine, and one engine detaching does not silence the
  others. iOS configure state is process-wide like Android's, so a second engine gets the
  same `already_configured` rule.
- Android: error codes come from the SDK's error type and exact messages, so an upload
  failure whose message happens to contain `401`, `403` or `429` is not reported as
  `rejected`/`rate_limited`. The debug-only Auto Backup check reads the base APK's
  manifest, not a split or WebView manifest.

Not included in this release: Android linkage/custom metadata (blocked on
`deviceintel-lib` 1.8) and a Flutter-specific traffic marker.
