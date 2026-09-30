import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:fingerprint_test/fingerprint_test_page.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const MethodChannel methods = MethodChannel('fingerprint_test/methods');
  const EventChannel events = EventChannel('fingerprint_test/events');
  final List<String> methodCalls = <String>[];

  setUp(() {
    methodCalls.clear();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(methods, (MethodCall call) async {
      methodCalls.add(call.method);
      switch (call.method) {
        case 'getInfo':
          return <dynamic, dynamic>{
            'hasHardware': true,
            'isHardwareDetected': true,
            'hasEnrolled': true,
            'sdkInt': 34,
          };
        default:
          return null;
      }
    });
  });

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(methods, null);
  });

  testWidgets('idle → listening → PASS flow', (WidgetTester tester) async {
    MockStreamHandlerEventSink? sink;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockStreamHandler(
      events,
      MockStreamHandler.inline(
        onListen: (Object? args, MockStreamHandlerEventSink eventsSink) {
          sink = eventsSink;
        },
        onCancel: (Object? args) {},
      ),
    );

    await tester.pumpWidget(const MaterialApp(home: FingerprintTestPage()));
    await tester.pumpAndSettle();

    // Hardware info loaded → ready to start.
    expect(find.text('Ready — press Start test.'), findsOneWidget);
    expect(find.text('Start test'), findsOneWidget);

    // Start the test → native startTest() must be invoked.
    await tester.tap(find.text('Start test'));
    await tester.pump();
    expect(methodCalls, contains('startTest'));

    // Native pushes 'listening'.
    sink!.success(<dynamic, dynamic>{
      'type': 'listening',
      'code': 0,
      'message': null,
    });
    await tester.pump(const Duration(milliseconds: 50));
    expect(find.text('Touch the fingerprint sensor…'), findsOneWidget);

    // Native pushes 'success' → PASS card.
    sink!.success(<dynamic, dynamic>{
      'type': 'success',
      'code': 0,
      'message': 'Fingerprint matched',
    });
    await tester.pump(const Duration(milliseconds: 50));
    expect(
      find.text('PASS — fingerprint sensor is working.'),
      findsOneWidget,
    );
  });

  testWidgets('two failed reads → FAIL (Cashify retry policy)',
      (WidgetTester tester) async {
    MockStreamHandlerEventSink? sink;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockStreamHandler(
      events,
      MockStreamHandler.inline(
        onListen: (Object? args, MockStreamHandlerEventSink eventsSink) {
          sink = eventsSink;
        },
        onCancel: (Object? args) {},
      ),
    );

    await tester.pumpWidget(const MaterialApp(home: FingerprintTestPage()));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Start test'));
    await tester.pump();

    void push(String type, [int code = 0]) =>
        sink!.success(<dynamic, dynamic>{'type': type, 'code': code, 'message': null});

    push('listening');
    await tester.pump(const Duration(milliseconds: 20));

    push('failed'); // first non-match → retry allowed
    await tester.pump(const Duration(milliseconds: 20));
    expect(find.textContaining('attempt 2 of 2'), findsOneWidget);

    push('failed'); // second non-match → FAIL
    await tester.pump(const Duration(milliseconds: 20));
    expect(find.textContaining('FAIL'), findsOneWidget);

    // The test must have auto-stopped itself.
    expect(methodCalls, contains('stopTest'));
  });

  testWidgets('app-level error 101 → enrollment prompt', (WidgetTester tester) async {
    MockStreamHandlerEventSink? sink;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockStreamHandler(
      events,
      MockStreamHandler.inline(
        onListen: (Object? args, MockStreamHandlerEventSink eventsSink) {
          sink = eventsSink;
        },
        onCancel: (Object? args) {},
      ),
    );

    await tester.pumpWidget(const MaterialApp(home: FingerprintTestPage()));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Start test'));
    await tester.pump();

    sink!.success(<dynamic, dynamic>{
      'type': 'error',
      'code': 101,
      'message': 'No fingerprint enrolled',
    });
    await tester.pump(const Duration(milliseconds: 20));
    expect(find.textContaining('No fingerprint enrolled'), findsOneWidget);
  });
}
