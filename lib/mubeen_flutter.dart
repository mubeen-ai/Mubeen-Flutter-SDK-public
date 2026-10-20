/// Mubeen device fingerprinting for Flutter.
///
/// This library is the entire supported surface. Everything under `lib/src/` is
/// generated from `pigeons/messages.dart` and is regenerated on every contract
/// change — importing it directly will break you on a patch release.
///
/// Platform behaviour differs, on purpose. Nothing here fakes a capability the
/// native SDK lacks: an unsupported call throws [MubeenUnsupportedError] rather
/// than returning a plausible zero. Check [Mubeen.capabilities] before wiring UI
/// to a platform-specific call. The one exception is `linkage` and `custom` on
/// [Mubeen.sendFingerprint] on Android: they are accepted but not sent, so
/// client code is identical on both platforms, and a one-time
/// [MubeenUnsupportedError] warning on [Mubeen.errors] says so.
library;

import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart' show PlatformException;
import 'package:flutter/widgets.dart' show WidgetsFlutterBinding;

import 'src/messages.g.dart';

// ---------------------------------------------------------------------------
// Public models
//
// These intentionally duplicate the generated Pigeon classes. The generated file
// is rewritten whenever the channel contract changes; if clients imported it,
// every wire tweak would be a breaking API change for them.
// ---------------------------------------------------------------------------

/// Verbosity handed to the native SDKs' own loggers.
///
/// Passed to the native SDK as given, in debug **and** release builds: the
/// plugin never lowers it for you. Use `warning` (the default) in release;
/// pick a more verbose level only behind `kDebugMode` or a debug flag.
///
/// Android: the SDK has one debug switch, which only `debug` turns on; it logs
/// collected signals and full HTTP bodies (including the `X-API-Key` header) to
/// logcat. iOS: maps onto the SDK's `OSLog` level.
enum MubeenLogLevel {
  /// No logging requested. Note that the Android SDK still writes some upload and
  /// storage lines of its own; only its verbose HTTP logging is gated by this.
  none,

  /// Failures only.
  error,

  /// Failures and warnings. The default, and the level to ship with.
  warning,

  /// Adds lifecycle information.
  info,

  /// Everything, including the native Android SDK's HTTP logging, which prints your
  /// API key to logcat. Never ship a release build at this level.
  debug,
}

/// Android-only options, passed straight into the native `MB_DeviceConfig`.
///
/// **Applied on Android, ignored on iOS, by design.** The iOS SDK has no
/// equivalent collectors, so there is nothing to map these onto there; set them
/// unconditionally and each platform takes what applies to it. They take part in
/// the [MubeenAlreadyConfiguredError] comparison on Android only.
///
/// Every default equals `deviceintel-lib` 1.7.3's own, so an app that never
/// passes this gets exactly the native default behavior. The three collectors
/// are **opt-in** and privacy-sensitive: the native SDK never requests a
/// runtime permission, reads each signal only when your app already holds the
/// matching permission, and degrades to null otherwise. Turning one on makes
/// your app responsible for the permission request and for the Google Play
/// Data Safety disclosure. See the README, "Optional collectors".
@immutable
class MubeenAndroidOptions {
  /// Creates Android options. All defaults are the native SDK's.
  const MubeenAndroidOptions({
    this.collectLocation = false,
    this.locationMaxAge = const Duration(minutes: 30),
    this.collectAdvancedSignals = false,
    this.collectAdvertisingId = false,
  });

  /// Adds the device's last-known location (a cached fix, never an active GPS
  /// request) to the fingerprint.
  ///
  /// Needs `ACCESS_FINE_LOCATION` or `ACCESS_COARSE_LOCATION`, requested by
  /// your app. Without it the location fields are null. Default false.
  final bool collectLocation;

  /// Oldest cached fix still reported when [collectLocation] is on; an older
  /// fix is reported as null. Default 30 minutes. Must not be negative.
  final Duration locationMaxAge;

  /// Adds WiFi SSID/BSSID, Bluetooth name and paired-device count, phone
  /// number and data-network type, each only when your app holds that signal's
  /// permission (see the README table). Carrier/SIM/network metadata is
  /// collected either way and is not controlled here. Default false.
  final bool collectAdvancedSignals;

  /// Adds the Google Advertising ID, read through `AdvertisingIdClient`, so a
  /// user who opted out of ad personalization yields null.
  ///
  /// Your app must add the `play-services-ads-identifier` dependency and
  /// declare `com.google.android.gms.permission.AD_ID` (apps targeting API
  /// 33+); without the dependency the id is null. The plugin checks both during
  /// the first [Mubeen.configure] and, if either is missing, reports a
  /// [MubeenUnsupportedError] on [Mubeen.errors] naming what is missing. That
  /// report is a warning: configuration still succeeds and the rest of the
  /// fingerprint is unaffected. Default false.
  final bool collectAdvertisingId;

  @override
  bool operator ==(Object other) =>
      other is MubeenAndroidOptions &&
      other.collectLocation == collectLocation &&
      other.locationMaxAge == locationMaxAge &&
      other.collectAdvancedSignals == collectAdvancedSignals &&
      other.collectAdvertisingId == collectAdvertisingId;

  @override
  int get hashCode => Object.hash(
    collectLocation,
    locationMaxAge,
    collectAdvancedSignals,
    collectAdvertisingId,
  );
}

/// iOS `MubeenEnvironment`, reported in every iOS fingerprint.
enum MubeenIosEnvironment {
  /// Live traffic. The native SDK's own default.
  production,

  /// Marks the fingerprint as test traffic so it can be told apart server-side. It does
  /// not change the endpoint: that is [MubeenConfig.endpoint].
  sandbox,
}

/// iOS-only options, passed straight into the native `MubeenConfig`.
///
/// **Applied on iOS, ignored on Android, by design.** The Android SDK has no
/// equivalents. They take part in the [MubeenAlreadyConfiguredError]
/// comparison on iOS only.
///
/// Every default equals `MubeenDeviceSDK` 2.0.0's own. None of these needs an
/// iOS permission.
@immutable
class MubeenIosOptions {
  /// Creates iOS options. All defaults are the native SDK's.
  const MubeenIosOptions({
    this.environment = MubeenIosEnvironment.production,
    this.enableJailbreakChecks = true,
    this.enableBehavioralSignals = false,
  });

  /// Sent as the fingerprint's `environment` field. Default production.
  final MubeenIosEnvironment environment;

  /// Runs the jailbreak/tamper scan (filesystem paths, restricted write,
  /// debugger, Frida, sideload). **Default true**, unlike the collectors
  /// above. When false the `jailbreak_tamper` block is still sent, zeroed, so
  /// a zero score then means "not checked", not "clean".
  final bool enableJailbreakChecks;

  /// Adds the `behavior` block: session event count and foreground session
  /// length. Default false, in which case `behavior` is null.
  final bool enableBehavioralSignals;

  @override
  bool operator ==(Object other) =>
      other is MubeenIosOptions &&
      other.environment == environment &&
      other.enableJailbreakChecks == enableJailbreakChecks &&
      other.enableBehavioralSignals == enableBehavioralSignals;

  @override
  int get hashCode =>
      Object.hash(environment, enableJailbreakChecks, enableBehavioralSignals);
}

/// Configuration for [Mubeen.configure].
@immutable
class MubeenConfig {
  /// Creates a configuration.
  ///
  /// [allowedCustomKeys] is enforced in Dart only and never crosses the channel;
  /// it is the allowlist every key in [Mubeen.sendFingerprint]'s `custom` map is
  /// checked against. Registering keys once here is what makes an accidental
  /// `{'user_email': ...}` a loud failure in QA instead of a silent PII leak.
  const MubeenConfig({
    required this.apiKey,
    this.endpoint,
    this.logLevel = MubeenLogLevel.warning,
    this.allowedCustomKeys = const <String>{},
    this.android = const MubeenAndroidOptions(),
    this.ios = const MubeenIosOptions(),
  });

  /// Publishable key. Must not be empty or whitespace-only: [Mubeen.configure]
  /// throws [ArgumentError] for that on both platforms.
  ///
  /// Must be a `public - JS client side` key, on both platforms. With any other
  /// key type every Android upload is
  /// rejected with a 401 **that the app never sees**: the Android SDK reports no
  /// HTTP status, so nothing reaches [Mubeen.errors] or the returned Future.
  /// Only server-side verification, or logcat at [MubeenLogLevel.debug], shows it.
  ///
  /// The key must also come from the same region as [endpoint]: a key issued in
  /// one region is rejected with 401 by another region's ingestion host.
  final String apiKey;

  /// Base URL of the ingestion service. Null uses the plugin's default
  /// ingestion host on both platforms; set it explicitly for another region or
  /// for self-hosted ingestion, and match it to [apiKey]'s region.
  ///
  /// A trailing slash is stripped before the value reaches native code, so
  /// `https://h/` and `https://h` behave identically, including when deciding
  /// whether a repeat [Mubeen.configure] call differs. A query string, fragment,
  /// credentials, whitespace or a backslash is rejected, because the native SDKs
  /// append their own route to this base URL.
  ///
  /// Validated by [Mubeen.configure] before anything reaches the native side,
  /// with an [ArgumentError] on failure: it must be an absolute URL with a
  /// host, and an empty string is an error, not "use the default". `https` is
  /// always accepted. `http` is accepted only for the local test hosts
  /// `localhost`, `127.0.0.1`, `::1` and `10.0.2.2` (the Android emulator's
  /// alias for the host machine), because both platforms block cleartext
  /// traffic in release builds. Any other scheme is rejected.
  final String? endpoint;

  /// Native log verbosity. Same meaning on both platforms.
  final MubeenLogLevel logLevel;

  /// Keys permitted in [Mubeen.sendFingerprint]'s `custom` map.
  ///
  /// Empty (the default) means `custom` must be empty. Dart-side only; identical
  /// on both platforms. The linkage field names (`account_id`,
  /// `payment_token_id`, `email`, `phone`) are not allowed here: use
  /// [MubeenLinkage] for those. Part of the [MubeenAlreadyConfiguredError]
  /// comparison: changing it on a second [Mubeen.configure] throws.
  final Set<String> allowedCustomKeys;

  /// Native options applied on Android only. See [MubeenAndroidOptions].
  final MubeenAndroidOptions android;

  /// Native options applied on iOS only. See [MubeenIosOptions].
  final MubeenIosOptions ios;

  @override
  bool operator ==(Object other) =>
      other is MubeenConfig &&
      other.apiKey == apiKey &&
      other.endpoint == endpoint &&
      other.logLevel == logLevel &&
      setEquals(other.allowedCustomKeys, allowedCustomKeys) &&
      other.android == android &&
      other.ios == ios;

  @override
  int get hashCode => Object.hash(apiKey, endpoint, logLevel, android, ios);
}

/// Whether [a] and [b] configure the native SDK of the current platform
/// identically. Each platform ignores the other platform's option group, so a
/// difference there is not a different configuration.
///
/// Compares only what the NATIVE side receives. `allowedCustomKeys` is left out
/// on purpose: it never crosses the channel (it is not in the Pigeon contract),
/// so callers compare it separately, against a frozen snapshot rather than the
/// caller's live Set. The endpoint is compared normalised, because that is the
/// value native gets: `https://h/` and `https://h` are the same configuration.
bool _sameNativeConfig(MubeenConfig a, MubeenConfig b) {
  final bool common =
      a.apiKey == b.apiKey &&
      _normalizeEndpoint(a.endpoint) == _normalizeEndpoint(b.endpoint) &&
      a.logLevel == b.logLevel;
  return switch (defaultTargetPlatform) {
    TargetPlatform.android => common && a.android == b.android,
    TargetPlatform.iOS => common && a.ios == b.ios,
    _ => common && a.android == b.android && a.ios == b.ios,
  };
}

/// Identifiers the backend hashes for cross-session linkage.
///
/// These four fields are the only sanctioned route for personal data. The
/// **native** SDK hashes them before they leave the device, which is why they are
/// exempt from the PII checks applied to `custom` — do not hash them yourself,
/// a second implementation would drift from what the backend expects.
///
/// Android: `deviceintel-lib` 1.7.3 has no field for linkage, so it is accepted
/// and not sent; the fingerprint is uploaded without it and a one-time
/// [MubeenUnsupportedError] warning arrives on [Mubeen.errors]. iOS: sent. See
/// [MubeenCapabilities.linkage].
@immutable
class MubeenLinkage {
  /// Creates a linkage bundle. All fields are optional; an all-null instance is
  /// legal but pointless.
  const MubeenLinkage({
    this.accountId,
    this.paymentTokenId,
    this.email,
    this.phone,
  });

  /// Your stable account identifier for the signed-in user.
  final String? accountId;

  /// Payment instrument token, not a PAN. Never send a card number.
  final String? paymentTokenId;

  /// Raw email. Hashed natively.
  final String? email;

  /// Raw phone number. Hashed natively.
  final String? phone;
}

/// What the current platform's native SDK can actually do.
///
/// Read from [Mubeen.capabilities] after [Mubeen.configure]. Values are fixed for
/// the lifetime of the process — they describe the linked SDK, not a runtime
/// permission — so caching them in your own state is safe.
@immutable
class MubeenCapabilities {
  /// Creates a capability set. Construct one yourself only in tests.
  const MubeenCapabilities({
    required this.linkage,
    required this.rawFingerprint,
    required this.pendingUploadCount,
  });

  /// Whether [Mubeen.sendFingerprint] accepts `linkage` **and** `custom`.
  ///
  /// iOS: true. Android: false until `deviceintel-lib` 1.8 lands. When false,
  /// either argument is still accepted and validated, but NOT sent: the
  /// fingerprint is uploaded without them, and the first time this happens in
  /// the process a [MubeenUnsupportedError] warning is delivered on
  /// [Mubeen.errors]. Client code is identical on both platforms.
  final bool linkage;

  /// Whether [Mubeen.getFingerprint] works.
  ///
  /// Android: true. iOS: false — that SDK is one-way submit and has no
  /// equivalent, so the call throws [MubeenUnsupportedError].
  final bool rawFingerprint;

  /// Whether [Mubeen.pendingUploadCount] works.
  ///
  /// Android: true. iOS: false — its retry queue is not introspectable, and the
  /// call throws [MubeenUnsupportedError] rather than returning a fake 0.
  final bool pendingUploadCount;

  @override
  bool operator ==(Object other) =>
      other is MubeenCapabilities &&
      other.linkage == linkage &&
      other.rawFingerprint == rawFingerprint &&
      other.pendingUploadCount == pendingUploadCount;

  @override
  int get hashCode => Object.hash(linkage, rawFingerprint, pendingUploadCount);

  @override
  String toString() =>
      'MubeenCapabilities(linkage: $linkage, rawFingerprint: $rawFingerprint, '
      'pendingUploadCount: $pendingUploadCount)';
}

// ---------------------------------------------------------------------------
// Errors
// ---------------------------------------------------------------------------

/// Base type for every failure Mubeen reports.
///
/// Also the element type of [Mubeen.errors]: an async upload failure and a
/// thrown call failure are the same shape, so one `catch`/`switch` handles both.
/// Sealed — you can switch exhaustively over the subtypes.
///
/// Programming errors (a bad config or `custom` map) are **not** modelled here;
/// those are an [ArgumentError], delivered through the returned `Future` like
/// every other failure, because they are your bug, not the device's.
sealed class MubeenError implements Exception {
  /// Creates an error with a wire [code] and a human-readable [message].
  const MubeenError(this.code, this.message);

  /// The native code string, preserved verbatim so you can distinguish members
  /// of a shared class (e.g. `rate_limited` vs `network`) and log it.
  final String code;

  /// Human-readable detail from the native SDK. Not localized; do not show it
  /// to end users.
  final String message;

  @override
  String toString() => '$runtimeType($code): $message';
}

/// [Mubeen.configure] has not completed, or the native SDK lost its
/// initialization. Identical on Android and iOS.
class MubeenNotConfiguredError extends MubeenError {
  /// Creates a not-configured error.
  const MubeenNotConfiguredError(String message)
    : super('not_configured', message);
}

/// The call is not available on this platform.
///
/// Check [Mubeen.capabilities] to find out which calls are live before you build
/// UI around them; this error is thrown, never returned as an empty value.
///
/// Also thrown for every call on a platform the plugin has no native
/// implementation for (web, desktop, or a unit test without a mocked host):
/// the channel has no handler there. That case arrives with [code]
/// `unsupported` too; the [message] names the channel.
///
/// Two cases are delivered on [Mubeen.errors] instead of thrown, both on
/// Android: when [MubeenAndroidOptions.collectAdvertisingId] is on but the app
/// cannot satisfy it (missing dependency or permission), and, once per process,
/// when [Mubeen.sendFingerprint] was given `linkage` or `custom` that the SDK
/// cannot send (the fingerprint itself was uploaded). They are warnings, not a
/// sign the plugin is unavailable, so do not disable the SDK on them; read the
/// [message].
class MubeenUnsupportedError extends MubeenError {
  /// Creates an unsupported-capability error.
  const MubeenUnsupportedError(String message) : super('unsupported', message);
}

/// [Mubeen.configure] was called a second time with different values.
///
/// Both native SDKs early-return when already initialized, so the second config
/// would be silently ignored. This is thrown instead. It bites hardest under
/// Flutter hot restart, which restarts Dart but not the host process: your Dart
/// state looks unconfigured while the native SDK is still holding the old
/// config. Full restart the app after changing config.
class MubeenAlreadyConfiguredError extends MubeenError {
  /// Creates an already-configured error.
  const MubeenAlreadyConfiguredError(String message)
    : super('already_configured', message);
}

/// The native SDK refused the configuration (wire code `invalid_config`).
///
/// A setup mistake to fix, not a transient failure. The Dart facade already
/// rejects an empty key and a malformed endpoint with an [ArgumentError], so
/// this one comes from native: the iOS SDK's own configuration checks, or, from
/// [Mubeen.sendFingerprint] on iOS, an HTTP 404 or 405 meaning the endpoint does
/// not serve the fingerprint route.
class MubeenInvalidConfigError extends MubeenError {
  /// Creates an invalid-config error.
  const MubeenInvalidConfigError(String message)
    : super('invalid_config', message);
}

/// The backend rejected the request — wrong key type, revoked key, or a payload
/// the ingestion service refused.
///
/// iOS only in practice: the Android SDK (`deviceintel-lib` 1.7.3) reports no
/// HTTP rejection to the plugin at all, so a 401 there is silent. Do not read
/// the absence of this error on Android as "the key works". See
/// [MubeenConfig.apiKey].
class MubeenAuthError extends MubeenError {
  /// Creates a rejection error.
  const MubeenAuthError(String message) : super('rejected', message);
}

/// Mubeen has switched submissions off remotely (wire code `disabled`).
///
/// iOS only: the SDK's remote configuration carries a kill switch, and while it
/// is on, [Mubeen.sendFingerprint] throws this. It is not a key problem and
/// retrying will not help until Mubeen turns submissions back on. Treat it as
/// a soft no-op: catch it and carry on with your flow.
class MubeenDisabledError extends MubeenError {
  /// Creates a disabled error.
  const MubeenDisabledError(String message) : super('disabled', message);
}

/// The upload could not reach the backend, or was throttled.
///
/// Covers wire code `network` and `rate_limited`; read [code] to tell them
/// apart. Both are transient and both are retried natively — Android keeps a
/// queue you can inspect with [Mubeen.pendingUploadCount], iOS does not.
class MubeenNetworkError extends MubeenError {
  /// Creates a network error with the originating wire code.
  const MubeenNetworkError(super.code, super.message);
}

/// Fallback for a code this Dart version does not know.
///
/// A newer native SDK can emit a code an older plugin has never heard of; you
/// still get [code] and [message] rather than a swallowed failure.
class MubeenUnknownError extends MubeenError {
  /// Creates an unknown error, preserving the original wire code.
  const MubeenUnknownError(super.code, super.message);
}

/// Strips trailing slashes from an endpoint before it crosses the channel.
///
/// The two platforms need OPPOSITE forms and only one of them used to say so.
/// Retrofit rejects an Android base URL that does not end in `/`, so the Kotlin
/// side appends one. The iOS SDK appends its own path to the URL it is given, so
/// a trailing slash there produces `https://host//v1/mobile/fingerprint` and the
/// server answers `405 Method Not Allowed`, which was then reported as an auth
/// error, sending the client to check an API key that was fine. (A 404/405 now
/// maps to [MubeenInvalidConfigError] instead.)
///
/// Found on a real iPhone on 2026-09-20: `https://fp.de.mubeen.ai/` failed with
/// 405 and `https://fp.de.mubeen.ai` succeeded. Writing a trailing slash is
/// completely natural, and it produced a working Android and a broken iOS.
///
/// Normalising here rather than in each host keeps one rule in one place, and
/// keeps it testable without a Mac. Android still appends the slash it needs.
String? _normalizeEndpoint(String? endpoint) {
  if (endpoint == null) return null;
  String trimmed = endpoint;
  while (trimmed.length > 1 && trimmed.endsWith('/')) {
    trimmed = trimmed.substring(0, trimmed.length - 1);
  }
  return trimmed;
}

/// The single place wire codes become Dart types.
///
/// Both the thrown-error path and the [Mubeen.errors] stream route through here,
/// so the two can never drift.
MubeenError _errorFromCode(String code, String? message) {
  final String text = message ?? code;
  return switch (code) {
    'not_configured' => MubeenNotConfiguredError(text),
    'unsupported' => MubeenUnsupportedError(text),
    'already_configured' => MubeenAlreadyConfiguredError(text),
    'invalid_config' => MubeenInvalidConfigError(text),
    'rejected' => MubeenAuthError(text),
    'disabled' => MubeenDisabledError(text),
    // Pigeon's own code when the channel has no native handler.
    'channel-error' => MubeenUnsupportedError(
      'mubeen_flutter has no native implementation on this platform (only '
      'Android and iOS are supported), or the plugin is not registered with '
      'this Flutter engine. $text',
    ),
    'network' || 'rate_limited' => MubeenNetworkError(code, text),
    _ => MubeenUnknownError(code, text),
  };
}

// ---------------------------------------------------------------------------
// custom-map guardrail
// ---------------------------------------------------------------------------

const int _maxCustomKeys = 30;
const int _maxCustomBytes = 4096;

/// The field names the iOS SDK hashes as linkage. A `custom` key with one of
/// these names would be taken out of `custom` natively, so it is refused here.
const Set<String> _linkageKeyNames = <String>{
  'account_id',
  'payment_token_id',
  'email',
  'phone',
};

/// Contains-match, not anchored: `order for a@b.com` must fail too. Matches
/// any `local@domain`, including `user@localhost` and plus-addressing.
///
/// The lookbehind makes the local part start at a token boundary, which keeps
/// the scan linear on long values without an `@`.
final RegExp _emailPattern = RegExp(
  r'(?<![^\s@])[^\s@]+@[^\s@]*[\p{L}\p{N}]',
  unicode: true,
);

/// Separators allowed between the digits of a phone number.
const String _phoneSeparator = r'[\s.\-_,()\u2010-\u2015\u2212]';

/// A phone number in international form: `+` or `00`, then a country code
/// (never 0) and 8-15 digits in total, with separators anywhere between them.
///
/// It must be a whole token: not glued to a letter or digit on either side, and
/// not the tail of a longer digit run. The `00` form additionally must not follow
/// identifier punctuation, because it is otherwise indistinguishable from a
/// zero-padded identifier behind a prefix: `ORD-00123456789` and
/// `INV_0098765432` matched before that restriction and were rejected in
/// release builds, which is the same failure the removed 7-digit-run rule
/// caused. `+` stays unanchored, so a number inside a sentence is still caught.
/// A value that *starts* with `00` and 8-15 digits is still rejected: nothing
/// tells it apart from a dialled number, and an id almost always carries a
/// prefix.
/// National-format numbers and government ids are deliberately not detected: no
/// heuristic tells them apart from order ids, prices and timestamps.
/// [MubeenConfig.allowedCustomKeys] is the real control.
/// Punctuation that joins an identifier's prefix to its digits, as in
/// `ORD-00123456789`, `INV_0098765432` or `ref(0012345678)`. A `00` directly
/// after one of these is a zero-padded id, not a dialling prefix.
///
/// This is a DENY list of punctuation, not an allow list of whitespace. The first
/// version required the `00` to follow whitespace or start the value, which fixed
/// the order ids and silently stopped catching `tel:00966501234567`,
/// `phone=00966501234567` and a quoted `"00966501234567"`, the everyday shapes of
/// a Saudi number written into a field. Found in review on 2026-09-22.
const String _idPunctuation = r'[.\-_,()\u2010-\u2015\u2212]';

final RegExp _internationalPhonePattern = RegExp(
  '(?<![0-9A-Za-z])(?<![0-9]$_phoneSeparator*)(?:\\+|(?<!$_idPunctuation)00)$_phoneSeparator*'
  '[1-9](?:$_phoneSeparator*[0-9]){7,14}(?!$_phoneSeparator*[0-9])(?![A-Za-z])',
);

final RegExp _percentEscape = RegExp('%([0-9A-Fa-f]{2})');

/// Folds the look-alike forms a PII check must see through, without a Unicode
/// normalization package: fullwidth ASCII (U+FF01-FF5E, as NFKC does), small
/// and ideographic forms of `@`, `+` and space, and Arabic-Indic (U+0660-0669)
/// and Extended Arabic-Indic/Persian (U+06F0-06F9) digits. Then decodes
/// percent-escapes of printable ASCII, so `%40` reads as `@`; malformed or
/// non-ASCII escapes are left as they are.
String _foldForPiiCheck(String value) {
  final StringBuffer out = StringBuffer();
  for (final int rune in value.runes) {
    if (rune >= 0xFF01 && rune <= 0xFF5E) {
      out.writeCharCode(rune - 0xFEE0);
    } else if (rune >= 0x0660 && rune <= 0x0669) {
      out.writeCharCode(0x30 + rune - 0x0660);
    } else if (rune >= 0x06F0 && rune <= 0x06F9) {
      out.writeCharCode(0x30 + rune - 0x06F0);
    } else if (rune == 0xFE6B) {
      out.write('@');
    } else if (rune == 0xFE62) {
      out.write('+');
    } else if (rune == 0x3000) {
      out.write(' ');
    } else if (rune == 0x200B || rune == 0x200C || rune == 0x200D ||
        rune == 0x2060 || rune == 0xFEFF || rune == 0x00AD) {
      // Invisible format characters: dropped, so `+966\u200B501234567` cannot
      // slip a real number past both patterns by splitting its digit run.
    } else {
      out.writeCharCode(rune);
    }
  }
  return out.toString().replaceAllMapped(_percentEscape, (Match m) {
    final int code = int.parse(m[1]!, radix: 16);
    return code >= 0x20 && code <= 0x7E ? String.fromCharCode(code) : m[0]!;
  });
}

/// Throws [ArgumentError] if [custom] would leak PII or blow the size budget.
///
/// Deliberately not an `assert`: it fires in release too. A key silently dropped
/// in production is a far worse outcome than a crash a QA pass catches. That is
/// also why the value checks are narrow: a check that rejects legitimate data
/// (dates, UUIDs, prices) would break real flows in release.
void _validateCustom(Map<String, String> custom, Set<String> allowedKeys) {
  if (custom.isEmpty) return;

  if (custom.length > _maxCustomKeys) {
    throw ArgumentError.value(
      custom.length,
      'custom',
      'too many keys (max $_maxCustomKeys). The backend caps the whole request '
          'body at 20KB and the fingerprint itself uses most of that budget',
    );
  }

  // The serialized size is what the request body actually carries. Checked
  // first, so the pattern scans below only ever see bounded input.
  final int bytes = utf8.encode(jsonEncode(custom)).length;
  if (bytes > _maxCustomBytes) {
    throw ArgumentError.value(
      bytes,
      'custom',
      'custom map is $bytes bytes as JSON, over the $_maxCustomBytes byte '
          'limit. The backend rejects request bodies over 20KB and the '
          'fingerprint payload claims most of that',
    );
  }

  for (final MapEntry<String, String> entry in custom.entries) {
    final String key = entry.key;
    if (_linkageKeyNames.contains(key)) {
      throw ArgumentError.value(
        key,
        'custom',
        'is a linkage field name. Pass it through MubeenLinkage, which the '
            'native SDK hashes; a custom key with this name would be dropped',
      );
    }
    if (!allowedKeys.contains(key)) {
      throw ArgumentError.value(
        key,
        'custom',
        allowedKeys.isEmpty
            ? 'no custom keys are registered. Pass them in '
                  'MubeenConfig.allowedCustomKeys before sending any'
            : 'key is not registered in MubeenConfig.allowedCustomKeys '
                  '(${(allowedKeys.toList()..sort()).join(', ')})',
      );
    }

    final String value = _foldForPiiCheck(entry.value);
    // Messages never echo the value: it is exactly the thing we suspect is PII.
    if (_emailPattern.hasMatch(value)) {
      throw ArgumentError(
        'custom["$key"] looks like an email address. Personal identifiers go in '
        'MubeenLinkage, which the native SDK hashes. Value withheld from this '
        'message.',
      );
    }
    if (_internationalPhonePattern.hasMatch(value)) {
      throw ArgumentError(
        'custom["$key"] looks like a phone number in international form. Use '
        'MubeenLinkage.phone. Value withheld from this message.',
      );
    }
  }
}

/// Test and emulator hosts that may use cleartext `http`.
const Set<String> _cleartextHosts = <String>{
  'localhost',
  '127.0.0.1',
  '::1',
  '10.0.2.2',
};

/// Throws [ArgumentError] for a config the native side would reject, or would
/// treat differently per platform. Never echoes the key.
void _validateConfig(MubeenConfig config) {
  if (config.apiKey.trim().isEmpty) {
    throw ArgumentError('MubeenConfig.apiKey must not be empty or blank.');
  }
  final String? endpoint = config.endpoint;
  if (endpoint != null) {
    final Uri? uri = Uri.tryParse(endpoint);
    if (endpoint.isEmpty || uri == null || !uri.hasScheme || uri.host.isEmpty) {
      throw ArgumentError.value(
        endpoint,
        'MubeenConfig.endpoint',
        'must be an absolute URL with a host, such as '
            '"https://ingest.example.com". Use null, not an empty string, for '
            'the default endpoint',
      );
    }
    // Credentials in the URL: rejected WITHOUT echoing the value, because an
    // ArgumentError.value would put them in toString(), and from there into any
    // crash report or log the client forwards errors to. Checked before the
    // scheme check below, which does echo the endpoint.
    if (uri.userInfo.isNotEmpty) {
      throw ArgumentError(
        'MubeenConfig.endpoint must not contain credentials (user:password@). '
        'Value withheld from this message.',
      );
    }
    // The native SDKs append their own route to this URL. A query or fragment
    // ends up in front of that route (https://h/?a=1 becomes a request for
    // ...?a=1/v1/mobile/fingerprint on iOS), and whitespace or a backslash is
    // never part of a valid base URL; trimming it silently would hide a typo.
    if (uri.hasQuery ||
        uri.hasFragment ||
        endpoint.contains(RegExp(r'[\s\\]'))) {
      throw ArgumentError.value(
        endpoint,
        'MubeenConfig.endpoint',
        'must be a plain base URL: no query string, no fragment, no whitespace '
            'or backslash',
      );
    }
    final bool allowed = switch (uri.scheme) {
      'https' => true,
      'http' => _cleartextHosts.contains(uri.host),
      _ => false,
    };
    if (!allowed) {
      throw ArgumentError.value(
        endpoint,
        'MubeenConfig.endpoint',
        uri.scheme == 'http'
            ? 'must use https. Cleartext http is blocked in release builds on '
                  'both Android and iOS, so it is accepted only for the local '
                  'test hosts ${_cleartextHosts.join(', ')}'
            : 'must use https',
      );
    }
  }
  if (config.android.locationMaxAge.isNegative) {
    throw ArgumentError.value(
      config.android.locationMaxAge,
      'android.locationMaxAge',
      'must not be negative; the native SDK would treat every fix as stale',
    );
  }
  for (final String key in config.allowedCustomKeys) {
    if (_linkageKeyNames.contains(key)) {
      throw ArgumentError.value(
        key,
        'MubeenConfig.allowedCustomKeys',
        'is a linkage field name. Use MubeenLinkage for it',
      );
    }
  }
}

// ---------------------------------------------------------------------------
// Facade
// ---------------------------------------------------------------------------

/// Entry point to the Mubeen SDK. Use [Mubeen.instance].
///
/// Call [configure] once at startup, then everything else.
///
/// Every method reports failure through its returned `Future`, never by
/// throwing synchronously: a missing [configure] ([MubeenNotConfiguredError]),
/// an unsupported call ([MubeenUnsupportedError]) and a bad argument
/// ([ArgumentError]) all arrive the same way, and all before anything reaches
/// the native side. So `.catchError`, `unawaited` and `FutureBuilder` behave as
/// expected. Only the [capabilities] getter throws synchronously.
class Mubeen implements MubeenFlutterApi {
  Mubeen._(this._host);

  /// The process-wide instance. The native SDKs are singletons; this mirrors
  /// them rather than pretending several independent clients can exist.
  static final Mubeen instance = Mubeen._(MubeenHostApi());

  /// Builds an instance over a stand-in host API. Tests only.
  @visibleForTesting
  factory Mubeen.forTesting(MubeenHostApi host) => Mubeen._(host);

  final MubeenHostApi _host;
  final StreamController<MubeenError> _errors =
      StreamController<MubeenError>.broadcast();

  MubeenCapabilities? _capabilities;
  Set<String> _allowedCustomKeys = const <String>{};

  /// The config of the last successful [configure].
  MubeenConfig? _applied;

  /// The config the native SDK accepted, set before [capabilities] is read.
  ///
  /// Equal to [_applied] on every successful path. It differs only in the window
  /// where native init succeeded and the capabilities call then failed: native is
  /// initialised and cannot be re-initialised, but Dart is not configured.
  MubeenConfig? _nativeConfiguredWith;

  /// The [configure] currently running, shared by identical concurrent calls.
  Future<void>? _configuring;
  MubeenConfig? _configuringWith;

  /// `allowedCustomKeys` of the in-flight [configure], frozen when it started, so
  /// a caller mutating its own Set mid-flight cannot change what is compared.
  Set<String>? _configuringKeys;

  /// Async failures the native SDKs report outside a method call.
  ///
  /// **This is the only signal that an upload actually failed.** [sendFingerprint]
  /// completing means accepted-or-queued, never delivered: on Android
  /// `uploadFingerprint()` is fire-and-forget, and on iOS a queued retry reports
  /// success immediately. If you do not listen here, a 100% failure rate looks
  /// identical to success on both platforms.
  ///
  /// Broadcast, so late listeners are fine, but events emitted before you
  /// subscribe are gone — subscribe in the same frame you call [configure].
  /// Never closes.
  Stream<MubeenError> get errors => _errors.stream;

  /// What this platform's native SDK can do. Cached during [configure].
  ///
  /// Throws [MubeenNotConfiguredError] before [configure] completes. Identical
  /// call on both platforms; the values differ — see [MubeenCapabilities].
  MubeenCapabilities get capabilities {
    _requireConfigured();
    return _capabilities!;
  }

  /// Initializes the native SDK. Call once, before anything else.
  ///
  /// Android: initializes `deviceintel-lib` on `Dispatchers.IO`; forces the
  /// SDK's `uploadOnGetId` to false (its default is true) so [getDeviceId] never
  /// triggers an upload. iOS: initializes the SDK on a background queue.
  ///
  /// Idempotent for an identical [config]. A second call with **different**
  /// values throws [MubeenAlreadyConfiguredError] instead of silently keeping
  /// the first config — see that error for the hot-restart case.
  /// [MubeenConfig.allowedCustomKeys] counts as a value here.
  ///
  /// Concurrent calls are safe: a call made while another is still running
  /// waits for that one and gets its result if the configs are identical, and
  /// throws [MubeenAlreadyConfiguredError] if they differ. A failed call leaves
  /// the instance unconfigured, so you can call it again.
  ///
  /// [MubeenConfig.android] is applied on Android and [MubeenConfig.ios] on
  /// iOS; each platform ignores the other group, including when deciding
  /// whether a repeat call differs.
  ///
  /// Throws [ArgumentError] before touching the channel, on both platforms,
  /// for a blank `apiKey`, an unusable `endpoint` (see [MubeenConfig.endpoint]),
  /// a negative `android.locationMaxAge`, or a linkage field name in
  /// `allowedCustomKeys`.
  ///
  /// Also populates [capabilities] and registers the [errors] stream.
  Future<void> configure(MubeenConfig config) async {
    _validateConfig(config);

    final Future<void>? inFlight = _configuring;
    if (inFlight != null) {
      if (!_sameNativeConfig(_configuringWith!, config) ||
          !setEquals(_configuringKeys, config.allowedCustomKeys)) {
        throw _differentConfigError;
      }
      return inFlight;
    }
    // Refusing a DIFFERENT config and short-circuiting an IDENTICAL one are two
    // separate questions, and they answer to different state.
    //
    // What native holds is `_applied ?? _nativeConfiguredWith`: `_applied` is set
    // only once both channel calls succeed, so when capabilities() failed after
    // configure() succeeded, Dart holds nothing while the native SDK is
    // initialised and cannot be re-initialised. A differing retry must be refused
    // from here rather than sent to native to be told the same thing.
    //
    // Whether THIS instance is usable is `_applied` alone. An identical retry in
    // that same window has to re-run and pick up the capabilities call that
    // failed: native treats a repeat init with identical values as a no-op, so
    // the retry costs one wasted round trip and finishes the job. Answering it
    // from `_nativeConfiguredWith` would return success with `_capabilities`
    // still null, leaving every later call throwing not-configured - and
    // contradicting this method's own promise that a failed call leaves the
    // instance re-configurable.
    final MubeenConfig? nativeHolds = _applied ?? _nativeConfiguredWith;
    if (nativeHolds != null) {
      // The second comparison is against the frozen snapshot, not against
      // nativeHolds.allowedCustomKeys: MubeenConfig is @immutable but the Set it
      // holds belongs to the caller, so mutating that Set and re-configuring
      // would compare it to itself and silently no-op, leaving the new keys
      // unregistered and sendFingerprint rejecting them.
      if (!_sameNativeConfig(nativeHolds, config) ||
          !setEquals(_allowedCustomKeys, config.allowedCustomKeys)) {
        throw _differentConfigError;
      }
    }
    final MubeenConfig? applied = _applied;
    if (applied != null) {
      // Already applied, same values: nothing to do. Re-running would cost two
      // channel round trips (configure + capabilities) for a native call that
      // short-circuits anyway, and defensive call sites do configure() on every
      // entry point.
      return;
    }

    final Future<void> run = _configure(config);
    _configuring = run;
    _configuringWith = config;
    _configuringKeys = Set<String>.unmodifiable(config.allowedCustomKeys);
    try {
      await run;
    } finally {
      _configuring = null;
      _configuringWith = null;
      _configuringKeys = null;
    }
  }

  static const MubeenAlreadyConfiguredError _differentConfigError =
      MubeenAlreadyConfiguredError(
        'configure() has already run with a different configuration and the '
        'native SDK cannot be re-initialised. '
        'Configure once, with the final values; to change them, fully restart '
        'the app.',
      );

  Future<void> _configure(MubeenConfig config) async {
    // Idempotent, and required: every channel call below reaches the default
    // binary messenger through ServicesBinding.instance, which throws
    // "Binding has not yet been initialized" until runApp() or this call has
    // run. The README documents configuring in main() before runApp(), which is
    // precisely the window where the binding does not exist yet, so the plugin
    // opens it rather than making every client remember.
    WidgetsFlutterBinding.ensureInitialized();
    // Registered first: a failure raised during native init would otherwise hit
    // a channel with no handler and be lost.
    MubeenFlutterApi.setUp(this);
    await _guard(
      () => _host.configure(
        MbConfig(
          apiKey: config.apiKey,
          endpoint: _normalizeEndpoint(config.endpoint),
          logLevel: _toWireLogLevel(config.logLevel),
          android: MbAndroidOptions(
            collectLocation: config.android.collectLocation,
            locationMaxAgeMs: config.android.locationMaxAge.inMilliseconds,
            collectAdvancedSignals: config.android.collectAdvancedSignals,
            collectAdvertisingId: config.android.collectAdvertisingId,
          ),
          ios: MbIosOptions(
            environment: switch (config.ios.environment) {
              MubeenIosEnvironment.production => MbIosEnvironment.production,
              MubeenIosEnvironment.sandbox => MbIosEnvironment.sandbox,
            },
            enableJailbreakChecks: config.ios.enableJailbreakChecks,
            enableBehavioralSignals: config.ios.enableBehavioralSignals,
          ),
        ),
      ),
    );
    // Native is initialised from here on, whatever happens next. The key
    // snapshot is frozen HERE, not after capabilities: if capabilities then
    // fails, the identical retry is compared against these keys, and an empty
    // snapshot would make it read as "a different configuration" for any app
    // that registers custom keys - which is the documented recommended setup.
    // Safe to set early: sendFingerprint is gated on _capabilities, not on this.
    _nativeConfiguredWith = config;
    _allowedCustomKeys = Set<String>.unmodifiable(config.allowedCustomKeys);

    final MbCapabilities caps = await _guard(_host.capabilities);
    _capabilities = MubeenCapabilities(
      // The wire type tracks `linkage` and `customData` separately, because
      // deviceintel-lib 1.8 may ship the two independently. This public flag
      // covers both, so it must require both: if a platform ever reports them
      // differently, the flag goes false. sendFingerprint does not throw on
      // it: Android accepts linkage and custom, drops them natively, and warns
      // once on errors, so the flag is how an app learns they were not sent.
      linkage: caps.linkage && caps.customData,
      rawFingerprint: caps.rawFingerprint,
      pendingUploadCount: caps.pendingUploadCount,
    );
    _applied = config;

    if (kDebugMode) {
      // Diagnostic only: nothing downstream reads it, so it must not add a
      // channel round trip to app startup.
      unawaited(_warnIfBackupRulesMissing());
    }
  }

  /// The persistent UUIDv7 device id.
  ///
  /// Android: read from the SDK's prefs file; never triggers an upload (see
  /// [configure]). Survives app restarts, and reinstalls only when Auto Backup
  /// rules cover that prefs file. iOS: read from the keychain, so it survives
  /// reinstall by default.
  ///
  /// Fails with [MubeenNotConfiguredError] if [configure] has not completed.
  Future<String> getDeviceId() async {
    _requireConfigured();
    return _guard(_host.getDeviceId);
  }

  /// Collects a fingerprint and uploads it. What completion means differs by
  /// platform, because the two native SDKs do:
  ///
  /// - **Android:** completing means the request was handed to the SDK, in
  ///   milliseconds; collection and upload run afterwards in the background. A
  ///   rejected upload (for example a 401) is re-queued by the SDK and reaches
  ///   neither this Future nor [errors]; [pendingUploadCount] is the backstop.
  /// - **iOS:** collection and the first upload attempt finish BEFORE the Future
  ///   completes (about 150 ms measured on an iPhone). A 2xx completes it; any
  ///   other 4xx except 404/405/429 (e.g. 400/401/403) throws
  ///   [MubeenAuthError] and a 404/405 throws [MubeenInvalidConfigError] from
  ///   this call. A 429 or 5xx completes it normally, is queued for retry, and
  ///   is reported on [errors]. An offline attempt (or a DNS, TLS or timeout
  ///   failure) also completes it normally and is queued, but is silent: no
  ///   error is reported on [errors].
  ///
  /// [linkage] and [custom] are sent on iOS only until `deviceintel-lib` 1.8.
  /// On Android the call accepts them and uploads the fingerprint without
  /// them; the first time this happens in the process, a
  /// [MubeenUnsupportedError] warning is delivered on [errors]. Read
  /// `capabilities.linkage` to know whether they are sent.
  ///
  /// Fails with [ArgumentError], in debug *and* release and on both platforms,
  /// when [custom] has:
  /// - a key outside [MubeenConfig.allowedCustomKeys], or a linkage field name
  ///   (`account_id`, `payment_token_id`, `email`, `phone`);
  /// - a value containing an email address (`name@domain`, including
  ///   `user@localhost`), or a phone number in international form (`+` or
  ///   `00`, then 8-15 digits, separators allowed). A `00` directly after an
  ///   identifier's punctuation (`ORD-00123456789`, `INV_0098765432`) is read as
  ///   a zero-padded id, not a dialling prefix. Fullwidth characters,
  ///   Arabic-Indic and Persian digits, `%40` and invisible format characters
  ///   are folded first;
  /// - more than 30 keys, or more than 4096 bytes as UTF-8 JSON.
  ///
  /// These checks are a safety net for mistakes, not a PII detector: national
  /// phone numbers and government ids are not recognised. The allowlist is the
  /// real control. Personal data belongs in [linkage], where the native SDK
  /// hashes it; nothing is hashed in Dart.
  Future<void> sendFingerprint({
    MubeenLinkage? linkage,
    Map<String, String> custom = const <String, String>{},
  }) async {
    _requireConfigured();
    // Validated on every platform, including Android where native does not
    // send `custom`, so the same bad map fails the same way everywhere. Native
    // decides what it can send; Android drops linkage/custom and warns once.
    _validateCustom(custom, _allowedCustomKeys);
    return _guard(
      () => _host.sendFingerprint(
        MbFingerprintRequest(
          linkage: linkage == null
              ? null
              : MbLinkage(
                  accountId: linkage.accountId,
                  paymentTokenId: linkage.paymentTokenId,
                  email: linkage.email,
                  phone: linkage.phone,
                ),
          custom: custom.isEmpty ? null : Map<String, String>.of(custom),
        ),
      ),
    );
  }

  /// Wipes the stored id and returns the newly minted one.
  ///
  /// Android: clears the prefs entry. iOS: clears the keychain entry. On both,
  /// every prior fingerprint stays attached to the old id — this breaks
  /// continuity deliberately, for a "forget me" flow.
  ///
  /// Fails with [MubeenNotConfiguredError] if [configure] has not completed.
  Future<String> resetDeviceId() async {
    _requireConfigured();
    return _guard(_host.resetDeviceId);
  }

  /// The full fingerprint as a JSON string, without uploading it.
  ///
  /// Android only. iOS throws [MubeenUnsupportedError] — that SDK is one-way
  /// submit and has no equivalent. Gate on `capabilities.rawFingerprint`.
  ///
  /// The JSON shape is the native SDK's, not this plugin's, and is not part of
  /// this package's API contract. Treat it as an opaque blob for debugging.
  Future<String> getFingerprint() async {
    _requireConfigured();
    _requireCapability(
      _capabilities!.rawFingerprint,
      'getFingerprint',
      'capabilities.rawFingerprint',
      'the iOS SDK is one-way submit and cannot return a fingerprint',
    );
    return _guard(_host.getFingerprint);
  }

  /// How many uploads are waiting in the native retry queue.
  ///
  /// Android only. iOS throws [MubeenUnsupportedError] — its retry queue is not
  /// introspectable. Gate on `capabilities.pendingUploadCount`.
  ///
  /// On Android this is a real queue depth, not a fake 0: when the SDK is
  /// uninitialized it would return 0, which is why [configure] is required first.
  Future<int> pendingUploadCount() async {
    _requireConfigured();
    _requireCapability(
      _capabilities!.pendingUploadCount,
      'pendingUploadCount',
      'capabilities.pendingUploadCount',
      "the iOS SDK's retry queue is not introspectable",
    );
    return _guard(_host.pendingUploadCount);
  }

  /// Receives async native failures. Called by the platform; not part of the
  /// client API. Listen to [errors] instead.
  @override
  void onError(MbError error) {
    _errors.add(_errorFromCode(error.code, error.message));
  }

  void _requireConfigured() {
    if (_capabilities == null) {
      throw const MubeenNotConfiguredError(
        'Mubeen.instance.configure() has not completed. Await it during app '
        'startup before calling anything else.',
      );
    }
  }

  void _requireCapability(
    bool available,
    String method,
    String flag,
    String why,
  ) {
    if (!available) {
      throw MubeenUnsupportedError(
        '$method is not supported on this platform: $why. Check $flag first.',
      );
    }
  }

  Future<void> _warnIfBackupRulesMissing() async {
    try {
      if (!await _guard(_host.backupRulesConfigured)) {
        debugPrint(
          'mubeen_flutter: could not confirm that Android Auto Backup covers the '
          'SDK prefs file. If your manifest declares no backup rules at all, the '
          'platform default backs up all shared prefs and the device id should '
          'survive a reinstall; if it declares rules, add the SDK prefs file to '
          'them (see README, Auto Backup). This is a prompt to check, not a verdict.',
        );
      }
    } on MubeenError {
      // Not fatal, and meaningless on iOS. Never break startup over a warning.
    }
  }

  Future<T> _guard<T>(Future<T> Function() call) async {
    try {
      return await call();
    } on PlatformException catch (e) {
      throw _errorFromCode(e.code, e.message);
    }
  }
}

MbLogLevel _toWireLogLevel(MubeenLogLevel level) => switch (level) {
  MubeenLogLevel.none => MbLogLevel.none,
  MubeenLogLevel.error => MbLogLevel.error,
  MubeenLogLevel.warning => MbLogLevel.warning,
  MubeenLogLevel.info => MbLogLevel.info,
  MubeenLogLevel.debug => MbLogLevel.debug,
};
