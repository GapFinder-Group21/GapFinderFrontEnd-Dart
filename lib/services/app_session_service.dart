import 'package:gapfinderfrontend_dart/core/network/api_client.dart';

class AppSessionService {
  // Registers that the user opened the app - POST /app-sessions/user/{userId}
  Future<void> registerOpen(int userId) async {
    final res = await ApiClient.post('/app-sessions/user/$userId');

    if (res.statusCode != 201) {
      throw Exception('Error registering app open: ${res.statusCode}');
    }
  }
}
