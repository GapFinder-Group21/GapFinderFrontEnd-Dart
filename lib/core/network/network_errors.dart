import 'dart:async';
import 'dart:io';
import 'package:http/http.dart' as http;

// True for errors caused by the network (no connection, too slow, connection lost),
// not for the back answering with an error status
bool isNetworkError(Object error) {
  return error is SocketException ||
      error is TimeoutException ||
      error is http.ClientException ||
      error is HandshakeException;
// True when the error comes from the network itself (no connection, server unreachable or too slow)
// and not from the back answering with an error. Used to fall back to the saved data or the outbox.
bool isNetworkError(Object error) {
  return error is SocketException ||
      error is http.ClientException ||
      error is TimeoutException ||
      error.toString().contains('No se pudo conectar');
}
