import 'package:flutter_test/flutter_test.dart';
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

  setUp(() {
    auth = FakeAuthService();
    vm = LoginViewModel(authService: auth);
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

    test('validate() checks empty fields and email format', () {
      expect(vm.validate('', 'secret'), 'Please fill in all fields');
      expect(vm.validate('ana@test.com', ''), 'Please fill in all fields');
      expect(vm.validate('not-an-email', 'secret'), 'Please enter a valid email');
      expect(vm.validate('ana@test.com', 'secret'), isNull);
    });
  });
}
