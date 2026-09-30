import 'dart:async';

import 'package:flutter/material.dart';

import 'fingerprint_test_channel.dart';

enum TestPhase { checking, idle, listening, success, failed, error }

class FingerprintTestPage extends StatefulWidget {
  const FingerprintTestPage({super.key});

  @override
  State<FingerprintTestPage> createState() => _FingerprintTestPageState();
}

class _FingerprintTestPageState extends State<FingerprintTestPage>
    with SingleTickerProviderStateMixin {
  final FingerprintTestChannel _channel = FingerprintTestChannel();
  StreamSubscription<FingerprintEvent>? _sub;

  late final AnimationController _pulse = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 900),
  );

  TestPhase _phase = TestPhase.checking;
  FingerprintDeviceInfo _info = const FingerprintDeviceInfo(
    hasHardware: false,
    isHardwareDetected: false,
    hasEnrolled: false,
    sdkInt: 0,
  );

  String _status = 'Checking fingerprint hardware…';
  int _failedMatches = 0;

  /// Same policy as Cashify Diagnose (sa/b.java): after this many
  /// non-matching reads the test is marked FAILED.
  static const int _maxFailedMatches = 2;

  /// `biometryType` is only reported on iOS (`faceID`/`touchID`/`opticID`);
  /// null on Android → fingerprint wording everywhere.
  String get _biometry => _info.biometryType ?? 'fingerprint';

  bool get _isFaceLike =>
      _biometry == 'faceID' || _biometry == 'opticID';

  String get _bioName => switch (_biometry) {
        'faceID' => 'Face ID',
        'opticID' => 'Optic ID',
        'touchID' => 'Touch ID',
        _ => 'fingerprint',
      };

  @override
  void initState() {
    super.initState();
    _sub = _channel.events.listen(_onEvent, onError: (Object e) {
      _setPhase(TestPhase.error, 'Channel error: $e');
    });
    _refreshInfo();
  }

  @override
  void dispose() {
    _sub?.cancel();
    _channel.stopTest();
    _pulse.dispose();
    super.dispose();
  }

  // ---------------------------------------------------------------- events

  void _onEvent(FingerprintEvent e) {
    switch (e.type) {
      case 'listening':
        _setPhase(
          TestPhase.listening,
          _isFaceLike
              ? 'Look at the screen — $_bioName is active…'
              : 'Touch the fingerprint sensor…',
        );
        _pulse.repeat(reverse: true);
        break;
      case 'help':
        _status = e.message ?? 'Adjust your finger and try again';
        setState(() {});
        break;
      case 'failed':
        _failedMatches++;
        if (_failedMatches >= _maxFailedMatches) {
          _channel.stopTest();
          _pulse.stop();
          _setPhase(
            TestPhase.failed,
            _isFaceLike
                ? 'FAIL — $_bioName read the face $_failedMatches times '
                    'but it never matched the enrollment.'
                : 'FAIL — sensor read the finger $_failedMatches times '
                    'but it never matched the enrollment.',
          );
        } else {
          _setPhase(
            TestPhase.listening,
            _isFaceLike
                ? 'Read OK, but no match — use the enrolled face '
                    '(attempt ${_failedMatches + 1} of $_maxFailedMatches)'
                : 'Read OK, but no match — try the enrolled finger '
                    '(attempt ${_failedMatches + 1} of $_maxFailedMatches)',
          );
          _pulse.repeat(reverse: true);
        }
        break;
      case 'success':
        _pulse.stop();
        _setPhase(
          TestPhase.success,
          _isFaceLike
              ? 'PASS — $_bioName is working.'
              : 'PASS — fingerprint sensor is working.',
        );
        break;
      case 'stopped':
        _pulse.stop();
        _setPhase(TestPhase.idle, 'Test stopped.');
        break;
      case 'error':
        _pulse.stop();
        _setPhase(TestPhase.error, _describeError(e));
        break;
    }
  }

  String _describeError(FingerprintEvent e) {
    // Android: android.hardware.fingerprint.FingerprintManager codes (+ app codes).
    // iOS: app codes 100–103 + raw LAError codes (negative).
    switch (e.code) {
      case 100:
        return _isFaceLike
            ? 'FAIL — no $_bioName hardware available.'
            : 'FAIL — no fingerprint hardware available.';
      case 101:
        return _isFaceLike
            ? 'No face enrolled. Add $_bioName in Settings → '
                'Face ID & Passcode, then retry.'
            : 'No fingerprint enrolled. Enroll one in Settings, then retry.';
      case 102:
        return 'Device passcode is not set — set a passcode first.';
      case 103: // iOS lockout (LAError.biometryLockout)
      case 7: // Android lockout
      case 9: // Android lockout (fatal)
      case -8: // LAError.biometryLockout raw value
        return 'Locked out after too many attempts — wait 30 s and retry.';
      case 10:
      case -2: // LAError.userCancel raw value
        return 'Cancelled by user.';
      default:
        return 'Error ${e.code}: ${e.message ?? 'unknown'}';
    }
  }

  void _setPhase(TestPhase phase, String status) {
    if (!mounted) return;
    setState(() {
      _phase = phase;
      _status = status;
      if (phase == TestPhase.listening || phase == TestPhase.success) {
        // attempts reset whenever a new test starts
      }
      if (phase == TestPhase.listening && _failedMatches >= _maxFailedMatches) {
        _failedMatches = 0;
      }
    });
  }

  // ---------------------------------------------------------------- actions
  Future<void> _refreshInfo() async {
    try {
      final info = await _channel.getInfo();
      if (!mounted) return;
      setState(() {
        _info = info;
        _phase = TestPhase.idle;
        _status = info.canTest
            ? 'Ready — press Start test.'
            : !info.hasHardware || !info.isHardwareDetected
                ? 'This device has no $_bioName hardware.'
                : 'No $_bioName enrolled yet.';
      });
    } catch (e) {
      if (!mounted) return;
      _setPhase(TestPhase.error, 'Failed to query biometric info: $e');
    }
  }

  Future<void> _start() async {
    _failedMatches = 0;
    try {
      await _channel.startTest();
      // 'listening' event will follow and update the UI
    } catch (e) {
      _setPhase(TestPhase.error, 'Could not start test: $e');
    }
  }

  Future<void> _stop() => _channel.stopTest();

  // ---------------------------------------------------------------- UI
  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final bool isBiometricIos = _info.biometryType != null;
    return Scaffold(
      appBar: AppBar(
        title: Text(
          _biometry != 'fingerprint' ? '$_bioName Test' : 'Fingerprint Test',
        ),
      ),
      body: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _infoChips(scheme),
            const SizedBox(height: 24),
            Expanded(child: Center(child: _sensorVisual(scheme))),
            const SizedBox(height: 16),
            _statusCard(scheme),
            const SizedBox(height: 16),
            _buttons(),
            const SizedBox(height: 12),
            Text(
              _isFaceLike
                  ? 'This test uses Apple LocalAuthentication '
                      '(system $_bioName prompt) only — no camera preview, '
                      'no photo or video is ever captured.'
                  : isBiometricIos
                      ? 'This test uses Apple LocalAuthentication '
                          '(Touch ID) only — no camera involved.'
                      : 'This test uses FingerprintManager only — '
                          'no camera, no BiometricPrompt, no face recognition.',
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: scheme.onSurfaceVariant,
                  ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _infoChips(ColorScheme scheme) {
    Widget chip(String label, bool ok) => Chip(
          avatar: Icon(
            ok ? Icons.check_circle : Icons.cancel,
            size: 18,
            color: ok ? Colors.green : scheme.error,
          ),
          label: Text(label),
        );
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      alignment: WrapAlignment.center,
      children: [
        chip('Hardware', _info.hasHardware && _info.isHardwareDetected),
        chip('Enrolled', _info.hasEnrolled),
        if (_info.biometryType != null)
          chip('iOS ${_info.sdkInt}', true)
        else
          chip('API ${_info.sdkInt}', true),
        if (_isFaceLike) chip('Face ID sensor', true),
      ],
    );
  }

  Widget _sensorVisual(ColorScheme scheme) {
    final listening = _phase == TestPhase.listening;
    final IconData icon = switch (_phase) {
      TestPhase.success => Icons.verified,
      TestPhase.failed => _isFaceLike ? Icons.face : Icons.fingerprint,
      TestPhase.error => Icons.error_outline,
      _ => _isFaceLike ? Icons.face : Icons.fingerprint,
    };
    final Color color = switch (_phase) {
      TestPhase.success => Colors.green,
      TestPhase.failed || TestPhase.error => scheme.error,
      _ => listening ? scheme.primary : scheme.outline,
    };
    return ScaleTransition(
      scale: Tween(begin: 1.0, end: listening ? 1.15 : 1.0).animate(
        CurvedAnimation(parent: _pulse, curve: Curves.easeInOut),
      ),
      child: Icon(icon, size: 140, color: color),
    );
  }

  Widget _statusCard(ColorScheme scheme) {
    final (bg, fg) = switch (_phase) {
      TestPhase.success => (Colors.green.shade50, Colors.green.shade900),
      TestPhase.failed || TestPhase.error => (scheme.errorContainer, scheme.onErrorContainer),
      _ => (scheme.surfaceContainerHighest, scheme.onSurface),
    };
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: fg.withValues(alpha: 0.2)),
      ),
      child: Text(
        _status,
        textAlign: TextAlign.center,
        style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600, color: fg),
      ),
    );
  }

  Widget _buttons() {
    final canStart = _phase == TestPhase.idle ||
        _phase == TestPhase.success ||
        _phase == TestPhase.failed ||
        _phase == TestPhase.error;
    return Row(
      children: [
        Expanded(
          child: FilledButton.icon(
            onPressed: _info.canTest && canStart ? _start : null,
            icon: const Icon(Icons.play_arrow),
            label: const Text('Start test'),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: OutlinedButton.icon(
            onPressed: _phase == TestPhase.listening ? _stop : null,
            icon: const Icon(Icons.stop),
            label: const Text('Stop'),
          ),
        ),
        if (!_info.hasEnrolled) ...[
          const SizedBox(width: 12),
          IconButton.filledTonal(
            tooltip: 'Enroll biometric in Settings',
            onPressed: _channel.openEnrollmentSettings,
            icon: const Icon(Icons.settings),
          ),
        ],
      ],
    );
  }
}
