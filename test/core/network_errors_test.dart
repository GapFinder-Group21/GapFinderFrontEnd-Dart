import 'dart:async';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:gapfinderfrontend_dart/core/network/network_errors.dart';

void main() {
  group('userMessage', () {
    test('a network error gives the own message of the screen', () {
      expect(userMessage(const SocketException('Failed host lookup'), network: 'Sin red'), 'Sin red');
      expect(userMessage(TimeoutException('slow'), network: 'Sin red'), 'Sin red');
    });

    test('an error of the back keeps its text without "Exception: "', () {
      expect(userMessage(Exception('Table is full'), network: 'Sin red'), 'Table is full');
    });

    test('an empty error falls back to the own message', () {
      expect(userMessage(Exception(''), network: 'Sin red'), 'Sin red');
    });
  });
}
