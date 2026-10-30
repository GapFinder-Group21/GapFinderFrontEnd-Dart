import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:gapfinderfrontend_dart/services/app_session_service.dart';

void main() {
  final tenOClock = DateTime(2026, 10, 30, 10, 2, 5);

  test('the opening is sent with the time the phone saw', () async {
    String? endpoint;
    Map<String, dynamic>? body;
    final service = AppSessionService(
      isOnline: () => true,
      post: (e, b) async {
        endpoint = e;
        body = b;
        return http.Response('', 201);
      },
      enqueue: (e, b) async => fail('it was online: nothing should be queued'),
    );

    await service.registerOpen(4, openedAt: tenOClock);

    expect(endpoint, '/app-sessions/user/4');
    expect(body, {'openedAt': tenOClock.toIso8601String()});
  });

  test('an opening without connection is queued with its original time', () async {
    String? queuedEndpoint;
    Map<String, dynamic>? queuedBody;
    final service = AppSessionService(
      isOnline: () => false,
      post: (e, b) async => fail('there is no connection: nothing should be sent'),
      enqueue: (e, b) async {
        queuedEndpoint = e;
        queuedBody = b;
      },
    );

    await service.registerOpen(4, openedAt: tenOClock);

    expect(queuedEndpoint, '/app-sessions/user/4');
    expect(queuedBody, {'openedAt': tenOClock.toIso8601String()});
  });

  test('if the network fails while sending, the opening is queued with the same time', () async {
    Map<String, dynamic>? queuedBody;
    final service = AppSessionService(
      isOnline: () => true,
      post: (e, b) async => throw const SocketException('no route'),
      enqueue: (e, b) async => queuedBody = b,
    );

    await service.registerOpen(4, openedAt: tenOClock);

    expect(queuedBody, {'openedAt': tenOClock.toIso8601String()});
  });

  test('without a given time it uses the moment of the call', () async {
    Map<String, dynamic>? body;
    final service = AppSessionService(
      isOnline: () => true,
      post: (e, b) async {
        body = b;
        return http.Response('', 201);
      },
    );
    final before = DateTime.now();

    await service.registerOpen(4);

    final sent = DateTime.parse(body!['openedAt'] as String);
    expect(sent.isBefore(before), isFalse);
    expect(sent.isAfter(DateTime.now().add(const Duration(seconds: 1))), isFalse);
  });

  test('an answer that is not 201 is an error', () async {
    final service = AppSessionService(
      isOnline: () => true,
      post: (e, b) async => http.Response('', 500),
    );

    expect(() => service.registerOpen(4, openedAt: tenOClock), throwsException);
  });
}
