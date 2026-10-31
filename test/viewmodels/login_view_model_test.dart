import 'dart:io';

import 'noop_local_cache.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';
import 'package:gapfinderfrontend_dart/models/responses/auth_response.dart';
import 'package:gapfinderfrontend_dart/services/auth_service.dart';
import 'package:gapfinderfrontend_dart/viewmodels/auth/login_view_model.dart';

class FakeAuthService extends AuthService {
  Object? error;
  String? lastEmail;

  @override
  Future<AuthResponse> login(String email, String password) async {
    lastEmail = email;
    if (error != null) throw error!;
    return AuthResponse(
      id: 1,
      accessToken: 'access',
      refreshToken: 'refresh',
      email: email,
      name: 'Test',
    );
  }
}

void main() {
  late FakeAuthService auth;
  late LoginViewModel vm;
  late Directory hiveDir;

  // Login clears the register draft, which lives in a Hive box
  setUpAll(() async {
    hiveDir = await Directory.systemTemp.createTemp('login_view_model_test');
    Hive.init(hiveDir.path);
  });

  tearDownAll(() async {
    await Hive.close();
    await hiveDir.delete(recursive: true);
  });

  setUp(() {
    auth = FakeAuthService();
    vm = LoginViewModel(authService: auth, localCache: NoopLocalCache());
  });

  tearDown(() => vm.dispose());

  group('LoginViewModel', () {
    test('initial state: not loading and no error', () {
      expect(vm.isLoading, isFalse);
      expect(vm.errorMessage, isNull);
    });

    test('login() returns true and stops loading', () async {
      final loadingStates = <bool>[];
      vm.addListener(() => loadingStates.add(vm.isLoading));

      final ok = await vm.login('ana@test.com', 'secret');

      expect(ok, isTrue);
      expect(auth.lastEmail, 'ana@test.com');
      expect(vm.errorMessage, isNull);
      expect(vm.isLoading, isFalse);
      expect(loadingStates, [true, false]);
    });

    test('login() returns false and sets errorMessage on error', () async {
      auth.error = Exception('Invalid credentials');

      final ok = await vm.login('ana@test.com', 'wrong');

      expect(ok, isFalse);
      expect(vm.errorMessage, 'Invalid credentials');
      expect(vm.isLoading, isFalse);
    });

    test('J-11: a technical error shows the generic message, never the exception text', () async {
      auth.error = const FormatException('Unexpected character at position 0');

      expect(await vm.login('ana@test.com', 'secret'), isFalse);

      expect(vm.errorMessage, 'No pudimos iniciar sesión. Intenta de nuevo');
    });

    test('validate() checks empty fields and email format', () {
      expect(vm.validate('', 'secret'), 'Please fill in all fields');
      expect(vm.validate('ana@test.com', ''), 'Please fill in all fields');
      expect(vm.validate('not-an-email', 'secret'), 'Please enter a valid email');
      expect(vm.validate('ana@test.com', 'secret'), isNull);
    });
  });
}
