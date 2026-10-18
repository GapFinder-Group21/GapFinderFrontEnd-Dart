import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

// Fake of flutter_secure_storage so TokenStorage can run in tests
class SecureStorageMock {
  static const _channel = MethodChannel('plugins.it_nomads.com/flutter_secure_storage');
  final Map<String, String> values = {};

  void install() {
    values.clear();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(_channel, (call) async {
      final key = call.arguments['key'] as String?;
      switch (call.method) {
        case 'read':
          return values[key];
        case 'write':
          values[key!] = call.arguments['value'] as String;
          return null;
        case 'delete':
          values.remove(key);
          return null;
      }
      return null;
    });
  }

  void uninstall() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(_channel, null);
  }

  void setUserId(int id) => values['userId'] = '$id';
}

// Lets the un-awaited refresh() calls of the view models finish
Future<void> settle() async {
  for (var i = 0; i < 10; i++) {
    await Future<void>.delayed(Duration.zero);
  }
}
