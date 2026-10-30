import 'dart:async';
import 'dart:io';
import 'package:http/http.dart' as http;

// True when the error comes from the network itself (no connection, server unreachable or too slow)
// and not from the back answering with an error. Used to fall back to the saved data or the outbox.
bool isNetworkError(Object error) {
  return error is SocketException ||
      error is http.ClientException ||
      error is TimeoutException ||
      error is HandshakeException ||
      error.toString().contains('No se pudo conectar');
}

// An error whose text was written for the user (for example a refusal of the back). Anything else that is
// thrown (a parse error, a null error, a platform exception) never shows its own text.
class UserMessageException implements Exception {
  final String message;
  UserMessageException(this.message);

  @override
  String toString() => message;
}

// Pieces of text that only a developer should read: exception names, Dart type errors, stack traces
// and the internals of Spring
const _technicalMarkers = [
  'Exception',
  'Error:',
  'TypeError',
  'is not a subtype',
  "type '",
  'Instance of',
  'StackTrace',
  'package:',
  'dart:',
  'at com.',
  'org.springframework',
  'java.',
  'null check',
  'Null check',
];

// True when the text looks like something technical and not like a message for the user
bool looksTechnical(String text) {
  return _technicalMarkers.any(text.contains);
}

// The text of a plain (not JSON) answer of the back, or the fallback when it is empty, HTML, too long or
// technical. Used by the services to build the message of their exceptions.
String plainBackendText(String body, String fallback) {
  final text = body.trim();
  if (text.isEmpty || text.startsWith('<') || text.length > 200 || looksTechnical(text)) return fallback;
  return text;
}

// The exception that Exception('text') creates: the only kind the services use for the message of the back
bool _isOwnException(Object error) {
  return error is Exception && error.runtimeType.toString() == '_Exception';
}

// The text a screen shows for an error: its own message when the network failed, the text of the back
// (without "Exception: ") when it is an exception we wrote ourselves, and the generic message of the screen
// for anything else. A raw exception, a parse error or a platform error never reaches the user.
String userMessage(Object error, {required String network}) {
  if (isNetworkError(error)) return network;
  if (error is UserMessageException) {
    return error.message.trim().isEmpty ? network : error.message.trim();
  }
  if (!_isOwnException(error)) return network;

  final text = error.toString().replaceFirst('Exception: ', '').trim();
  if (text.isEmpty || looksTechnical(text)) return network;
  return text;
}
