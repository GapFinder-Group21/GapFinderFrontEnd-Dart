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
