import 'dart:async';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:gapfinderfrontend_dart/core/network/network_errors.dart';

void main() {
  const screen = 'No pudimos cargar, intenta de nuevo';

  group('userMessage', () {
    test('a network error gives the own message of the screen', () {
      expect(userMessage(const SocketException('Failed host lookup'), network: 'Sin red'), 'Sin red');
      expect(userMessage(TimeoutException('slow'), network: 'Sin red'), 'Sin red');
    });

    test('an error of the back keeps its text without "Exception: "', () {
      expect(userMessage(Exception('La open table está llena'), network: 'Sin red'), 'La open table está llena');
    });

    test('an empty error falls back to the own message', () {
      expect(userMessage(Exception(''), network: 'Sin red'), 'Sin red');
    });

    test('a message written for the user (UserMessageException) is shown as it is', () {
      expect(userMessage(UserMessageException('Tu sesión expiró'), network: screen), 'Tu sesión expiró');
      expect(userMessage(UserMessageException('  '), network: screen), screen);
    });
  });

  group('a raw exception never reaches the user', () {
    test('TimeoutException', () {
      expect(userMessage(TimeoutException('Future not completed', const Duration(seconds: 15)), network: screen), screen);
    });

    test('SocketException', () {
      expect(userMessage(const SocketException('Connection refused'), network: screen), screen);
    });

    test('ClientException', () {
      expect(userMessage(http.ClientException('Connection closed'), network: screen), screen);
    });

    test('FormatException (a parse error)', () {
      expect(userMessage(const FormatException('Unexpected character'), network: screen), screen);
    });

    test('TypeError (a null or a wrong type in the answer)', () {
      Object? error;
      try {
        // ignore: unnecessary_cast
        final Object value = <String, dynamic>{'a': null}['a'] ?? 'x';
        (value as int).toString();
      } catch (e) {
        error = e;
      }

      expect(error, isA<TypeError>());
      expect(userMessage(error!, network: screen), screen);
    });

    test('any other error type', () {
      expect(userMessage(StateError('Bad state: no element'), network: screen), screen);
      expect(userMessage(ArgumentError('bad'), network: screen), screen);
      expect(userMessage('a plain string error', network: screen), screen);
    });

    test('an exception we wrote with technical text is replaced too', () {
      expect(userMessage(Exception("type 'Null' is not a subtype of type 'int'"), network: screen), screen);
      expect(userMessage(Exception('Instance of _Exception'), network: screen), screen);
      expect(userMessage(Exception('java.lang.IllegalStateException at com.backend.X'), network: screen), screen);
    });
  });

  group('plainBackendText', () {
    test('keeps a readable text of the back', () {
      expect(plainBackendText('La open table ya terminó', 'fallback'), 'La open table ya terminó');
    });

    test('uses the fallback for an empty body, HTML, a very long text or a technical one', () {
      expect(plainBackendText('', 'fallback'), 'fallback');
      expect(plainBackendText('<html><body>502</body></html>', 'fallback'), 'fallback');
      expect(plainBackendText('x' * 300, 'fallback'), 'fallback');
      expect(plainBackendText('org.springframework.web.HttpMessageNotReadableException', 'fallback'), 'fallback');
    });
  });
}
