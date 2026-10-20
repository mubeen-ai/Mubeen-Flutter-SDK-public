// Manual test harness for mubeen_flutter.
//
// Every button is always enabled, including the ones that cannot work on the
// current platform. That is deliberate: tapping "Get raw fingerprint" on iOS and
// watching MubeenUnsupportedError land in the log is the fastest way to confirm
// the plugin is honest about capabilities. Visible state beats a tidy screen.

import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:mubeen_flutter/mubeen_flutter.dart';

/// A CI release-build upload check. Empty, and so inert,
/// unless the app is built with --dart-define=MUBEEN_E2E_SELFTEST_ENDPOINT=...
/// pointing at a local test server. The same define also switches the
/// Android release build to a network security config that allows cleartext to
/// the emulator's host alias (example/android/app/build.gradle.kts).
const String _selfTestEndpoint = String.fromEnvironment(
  'MUBEEN_E2E_SELFTEST_ENDPOINT',
);

/// Mirror every harness line into the device log (logcat on Android, Console on
/// iOS). OFF unless the build passes --dart-define=MUBEEN_HARNESS_LOGCAT=true.
///
/// A remote device farm needs it: "copy log" writes to the handset's own
/// clipboard, which never leaves the remote device, so the farm's log viewer is
/// the only way to get a result out as text. But this is also the example app
/// clients read as the reference integration, and writing fingerprint verdicts
/// and device ids to the device log in a release build is not a pattern to copy:
/// it tells anyone with adb what the fraud check detected. So it is opt-in, set
/// only when building an APK or .ipa for a device farm.
const bool _mirrorToDeviceLog = bool.fromEnvironment('MUBEEN_HARNESS_LOGCAT');

final RegExp _uuid = RegExp(
  r'\b([0-9a-fA-F]{8})-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}\b',
);

/// Keeps the first 8 hex digits of any UUID, enough to tell two devices apart in
/// a test run without writing the full identifier to a device log.
String _truncateIds(String line) =>
    line.replaceAllMapped(_uuid, (Match m) => '${m[1]}-…');

/// Shown in the app bar so a screenshot says which build is running.
const String _buildId = String.fromEnvironment(
  'MUBEEN_BUILD_ID',
  defaultValue: 'local',
);

void main() {
  runApp(const MubeenExampleApp());
  if (_selfTestEndpoint.isNotEmpty) unawaited(_releaseSelfTest());
}

/// Configures against the fake server and sends one fingerprint, so CI can
/// prove a minified build really uploads. The key is fake on purpose.
Future<void> _releaseSelfTest() async {
  try {
    await Mubeen.instance.configure(
      const MubeenConfig(
        apiKey: 'pk_e2e_release_selftest',
        endpoint: _selfTestEndpoint,
      ),
    );
    await Mubeen.instance.sendFingerprint();
    debugPrint('mubeen selftest: sendFingerprint returned');
  } on Object catch (e) {
    debugPrint('mubeen selftest: FAILED $e');
  }
}

class MubeenExampleApp extends StatelessWidget {
  const MubeenExampleApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'mubeen_flutter harness',
      theme: ThemeData(useMaterial3: true),
      home: const HarnessScreen(),
    );
  }
}

class HarnessScreen extends StatefulWidget {
  const HarnessScreen({super.key});

  @override
  State<HarnessScreen> createState() => _HarnessScreenState();
}

class _HarnessScreenState extends State<HarnessScreen> {
  final TextEditingController _apiKey = TextEditingController(
    text: 'public_replace_me',
  );
  final TextEditingController _endpoint = TextEditingController();
  final List<String> _log = <String>[];

  StreamSubscription<MubeenError>? _errorSub;
  bool _configured = false;
  String _deviceId = '(not fetched)';
  String _lastResult = '(nothing yet)';

  // Native options, all at the native defaults. Changing one after configure is
  // a quick way to see already_configured on the platform that applies it.
  MubeenAndroidOptions _android = const MubeenAndroidOptions();
  MubeenIosOptions _ios = const MubeenIosOptions();

  // Off by default, as it should be in any app: `debug` makes the Android SDK log
  // full HTTP bodies and the API key header, in release builds too.
  bool _debugLogging = false;

  @override
  void initState() {
    super.initState();
    // Subscribe before configure: errors emitted during startup are not replayed.
    _errorSub = Mubeen.instance.errors.listen((MubeenError error) {
      _append('ASYNC ERROR  ${error.code}  ${error.message}');
    });
  }

  @override
  void dispose() {
    _errorSub?.cancel();
    _apiKey.dispose();
    _endpoint.dispose();
    super.dispose();
  }

  void _append(String line) {
    final String stamp = DateTime.now().toIso8601String().substring(11, 23);
    if (_mirrorToDeviceLog) {
      // Device farms only (see _mirrorToDeviceLog). Device ids are truncated
      // on the way out: the log is readable by adb, bug reports and the farm's
      // own retention, and the full id identifies the handset.
      debugPrint('MUBEEN_HARNESS $stamp  ${_truncateIds(line)}');
    }
    setState(() => _log.insert(0, '$stamp  $line'));
  }

  /// Runs [action] and makes the outcome visible either way.
  Future<void> _run(String label, Future<Object?> Function() action) async {
    _append('-> $label');
    // Elapsed time is logged because it is a real question about this plugin: collection
    // takes 200-800 ms on a fast device and 10-25 s on a slow or emulated one, and the
    // only way to know a given phone's number is to measure it here.
    final Stopwatch watch = Stopwatch()..start();
    String took() => '${watch.elapsedMilliseconds} ms';
    try {
      final Object? result = await action();
      setState(() => _lastResult = '$label: ${result ?? 'ok'}');
      _append('<- $label (${took()}): ${result ?? 'ok'}');
    } on MubeenError catch (e) {
      setState(() => _lastResult = '$label FAILED: $e');
      _append('!! $label (${took()}): $e');
    } on ArgumentError catch (e) {
      // The config and PII / size guardrails. Thrown in release builds too.
      setState(() => _lastResult = '$label REJECTED LOCALLY');
      _append(
        '!! $label rejected before the channel (${took()}): ${e.message}',
      );
    } on Object catch (e) {
      setState(() => _lastResult = '$label FAILED: $e');
      _append('!! $label: unexpected $e');
    }
  }

  Future<void> _configure() async {
    await _run('configure', () async {
      await Mubeen.instance.configure(
        MubeenConfig(
          apiKey: _apiKey.text.trim(),
          endpoint: _endpoint.text.trim().isEmpty
              ? null
              : _endpoint.text.trim(),
          logLevel: _debugLogging
              ? MubeenLogLevel.debug
              : MubeenLogLevel.warning,
          allowedCustomKeys: const <String>{'checkout_step', 'app_screen'},
          android: _android,
          ios: _ios,
        ),
      );
      setState(() => _configured = true);
      return Mubeen.instance.capabilities.toString();
    });
  }

  MubeenAndroidOptions _androidWith({
    bool? collectLocation,
    bool? collectAdvancedSignals,
    bool? collectAdvertisingId,
  }) => MubeenAndroidOptions(
    collectLocation: collectLocation ?? _android.collectLocation,
    locationMaxAge: _android.locationMaxAge,
    collectAdvancedSignals:
        collectAdvancedSignals ?? _android.collectAdvancedSignals,
    collectAdvertisingId: collectAdvertisingId ?? _android.collectAdvertisingId,
  );

  @override
  Widget build(BuildContext context) {
    final MubeenCapabilities? caps = _configured
        ? Mubeen.instance.capabilities
        : null;

    return Scaffold(
      // The build id is on screen because two APK files with the same name, one of
      // them stale, are indistinguishable once they are on a phone. Pass
      // --dart-define=MUBEEN_BUILD_ID=<short sha> when building one to hand over.
      appBar: AppBar(
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            const Text('mubeen_flutter harness'),
            Text(
              'build $_buildId',
              style: Theme.of(context).textTheme.labelSmall,
            ),
          ],
        ),
      ),
      // The whole page scrolls. It used to be a Column ending in Expanded, which fills the
      // viewport exactly once: on a phone shorter than the content (found on a real device,
      // not on the tall container screen) the buttons consumed the height, the log got none,
      // and nothing scrolled, so the log was unreachable.
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              TextField(
                controller: _apiKey,
                decoration: const InputDecoration(
                  labelText: 'API key (must be "public - JS client side")',
                ),
              ),
              TextField(
                controller: _endpoint,
                decoration: const InputDecoration(
                  labelText:
                      'Endpoint (blank = default; https, or http to a local host)',
                ),
              ),
              // Opt-in collectors (off by default, as in the native SDKs). Each
              // group only takes effect on its own platform.
              Wrap(
                spacing: 4,
                children: <Widget>[
                  _OptionChip(
                    label: 'Debug logging',
                    value: _debugLogging,
                    onChanged: (bool v) => setState(() => _debugLogging = v),
                  ),
                  _OptionChip(
                    label: 'Android location',
                    value: _android.collectLocation,
                    onChanged: (bool v) => setState(
                      () => _android = _androidWith(collectLocation: v),
                    ),
                  ),
                  _OptionChip(
                    label: 'Android advanced signals',
                    value: _android.collectAdvancedSignals,
                    onChanged: (bool v) => setState(
                      () => _android = _androidWith(collectAdvancedSignals: v),
                    ),
                  ),
                  _OptionChip(
                    label: 'Android advertising id',
                    value: _android.collectAdvertisingId,
                    onChanged: (bool v) => setState(
                      () => _android = _androidWith(collectAdvertisingId: v),
                    ),
                  ),
                  _OptionChip(
                    label: 'iOS behavioral signals',
                    value: _ios.enableBehavioralSignals,
                    onChanged: (bool v) => setState(
                      () => _ios = MubeenIosOptions(
                        environment: _ios.environment,
                        enableJailbreakChecks: _ios.enableJailbreakChecks,
                        enableBehavioralSignals: v,
                      ),
                    ),
                  ),
                  _OptionChip(
                    label: 'iOS jailbreak checks',
                    value: _ios.enableJailbreakChecks,
                    onChanged: (bool v) => setState(
                      () => _ios = MubeenIosOptions(
                        environment: _ios.environment,
                        enableJailbreakChecks: v,
                        enableBehavioralSignals: _ios.enableBehavioralSignals,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              _StateRow(label: 'configured', value: '$_configured'),
              _StateRow(label: 'device id', value: _deviceId),
              _StateRow(label: 'last result', value: _lastResult),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                children: <Widget>[
                  _CapabilityChip(
                    name: 'linkage + custom',
                    value: caps?.linkage,
                  ),
                  _CapabilityChip(
                    name: 'rawFingerprint',
                    value: caps?.rawFingerprint,
                  ),
                  _CapabilityChip(
                    name: 'pendingUploadCount',
                    value: caps?.pendingUploadCount,
                  ),
                ],
              ),
              const Divider(),
              Wrap(
                spacing: 8,
                runSpacing: 4,
                children: <Widget>[
                  FilledButton(
                    onPressed: _configure,
                    child: const Text('configure'),
                  ),
                  OutlinedButton(
                    onPressed: () => _run('getDeviceId', () async {
                      final String id = await Mubeen.instance.getDeviceId();
                      setState(() => _deviceId = id);
                      return id;
                    }),
                    child: const Text('getDeviceId'),
                  ),
                  OutlinedButton(
                    onPressed: () => _run(
                      'sendFingerprint (bare)',
                      () => Mubeen.instance.sendFingerprint(),
                    ),
                    child: const Text('sendFingerprint'),
                  ),
                  OutlinedButton(
                    onPressed: () => _run(
                      'sendFingerprint (linkage + custom)',
                      () => Mubeen.instance.sendFingerprint(
                        linkage: const MubeenLinkage(
                          accountId: 'acct_demo',
                          email: 'demo@example.com',
                        ),
                        custom: const <String, String>{
                          'checkout_step': 'payment-review',
                        },
                      ),
                    ),
                    child: const Text('sendFingerprint + linkage'),
                  ),
                  OutlinedButton(
                    onPressed: () => _run(
                      'sendFingerprint (PII in custom)',
                      () => Mubeen.instance.sendFingerprint(
                        custom: const <String, String>{
                          'checkout_step': 'user demo@example.com',
                        },
                      ),
                    ),
                    child: const Text('guardrail: PII in custom'),
                  ),
                  OutlinedButton(
                    onPressed: () => _run(
                      'sendFingerprint (unregistered key)',
                      () => Mubeen.instance.sendFingerprint(
                        custom: const <String, String>{'not_registered': 'x'},
                      ),
                    ),
                    child: const Text('guardrail: unknown key'),
                  ),
                  OutlinedButton(
                    onPressed: () => _run('resetDeviceId', () async {
                      final String id = await Mubeen.instance.resetDeviceId();
                      setState(() => _deviceId = id);
                      return id;
                    }),
                    child: const Text('resetDeviceId'),
                  ),
                  OutlinedButton(
                    onPressed: () => _run('getFingerprint', () async {
                      final String json = await Mubeen.instance
                          .getFingerprint();
                      return '${json.length} bytes of JSON, '
                          '${_riskSummary(json)}';
                    }),
                    child: const Text('getFingerprint (Android)'),
                  ),
                  OutlinedButton(
                    onPressed: () => _run(
                      'pendingUploadCount',
                      () => Mubeen.instance.pendingUploadCount(),
                    ),
                    child: const Text('pendingUploadCount (Android)'),
                  ),
                  TextButton(
                    onPressed: () => setState(_log.clear),
                    child: const Text('clear log'),
                  ),
                  TextButton(
                    onPressed: _log.isEmpty
                        ? null
                        : () async {
                            await Clipboard.setData(
                              ClipboardData(text: _log.reversed.join('\n')),
                            );
                            if (context.mounted) {
                              ScaffoldMessenger.of(context).showSnackBar(
                                const SnackBar(
                                  content: Text(
                                    'log copied, oldest line first',
                                  ),
                                ),
                              );
                            }
                          },
                    child: const Text('copy log'),
                  ),
                ],
              ),
              const Divider(),
              Text(
                'Log: async upload failures only ever appear here, never as a '
                'thrown error from sendFingerprint.',
                style: Theme.of(context).textTheme.bodySmall,
              ),
              DecoratedBox(
                decoration: BoxDecoration(
                  border: Border.all(color: Theme.of(context).dividerColor),
                ),
                child: SizedBox(
                  height: 260,
                  child: ListView.builder(
                    padding: const EdgeInsets.all(6),
                    itemCount: _log.length,
                    itemBuilder: (BuildContext context, int i) => Text(
                      _log[i],
                      style: const TextStyle(
                        fontFamily: 'monospace',
                        fontSize: 12,
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _StateRow extends StatelessWidget {
  const _StateRow({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        SizedBox(
          width: 100,
          child: Text(
            label,
            style: const TextStyle(fontWeight: FontWeight.bold),
          ),
        ),
        // One line, always. A wrapping value used to move every button below
        // this row by up to ~470px and could overflow the Column outright,
        // which broke coordinate-driven automation and hid the log. The full
        // text is never lost: _run() appends it verbatim to the log below.
        Expanded(child: SelectableText(value, maxLines: 1)),
      ],
    );
  }
}

/// A compact on/off toggle for one native option.
class _OptionChip extends StatelessWidget {
  const _OptionChip({
    required this.label,
    required this.value,
    required this.onChanged,
  });

  final String label;
  final bool value;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    return FilterChip(
      label: Text(label),
      selected: value,
      onSelected: onChanged,
      visualDensity: VisualDensity.compact,
    );
  }
}

/// Null means "not known yet" — the plugin refuses to guess before configure.
class _CapabilityChip extends StatelessWidget {
  const _CapabilityChip({required this.name, required this.value});

  final String name;
  final bool? value;

  @override
  Widget build(BuildContext context) {
    final String mark = switch (value) {
      true => 'YES',
      false => 'NO',
      null => '?',
    };
    return Chip(label: Text('$name: $mark'));
  }
}

/// The signals in a fingerprint payload that are actually asserted, for the log
/// line. A real phone is the only place root, emulator and tamper detection can
/// be read for real: a container reports itself rooted and a simulator cannot
/// answer at all, so the byte count alone was never the interesting part of
/// getFingerprint().
///
/// This walks the whole payload rather than naming a path, because the first
/// version of it guessed the shape from the ingestion table's column names and
/// was wrong three ways over: the flags are nested under `risk_signals`, they
/// carry no `risk_` prefix, and their values are the strings "true"/"false",
/// not booleans. It reported "none" on every device, which reads exactly like a
/// clean phone. Walking means the log stays truthful if the SDK moves a key.
String _riskSummary(String fingerprintJson) {
  const Set<String> integrityKeys = <String>{
    'verified_boot_state',
    'bootloader_locked',
    'selinux_enforcing',
  };
  final List<String> asserted = <String>[];
  final List<String> integrity = <String>[];

  void walk(Object? node) {
    if (node is Map<String, Object?>) {
      for (final MapEntry<String, Object?> e in node.entries) {
        final Object? v = e.value;
        if (v == true || v == 'true') asserted.add(e.key);
        if (integrityKeys.contains(e.key)) integrity.add('${e.key}=$v');
        walk(v);
      }
    } else if (node is List<Object?>) {
      node.forEach(walk);
    }
  }

  try {
    walk(jsonDecode(fingerprintJson));
  } on FormatException catch (e) {
    return 'signals: payload did not parse ($e)';
  }
  asserted.sort();
  integrity.sort();
  return 'true-valued keys: ${asserted.isEmpty ? 'none' : asserted.join(', ')}; '
      '${integrity.isEmpty ? 'no integrity keys in payload' : integrity.join(' ')}';
}
