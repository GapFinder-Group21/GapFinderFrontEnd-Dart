import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';
import 'package:gapfinderfrontend_dart/data/local/miguel/miguel_local_cache.dart';
import 'package:gapfinderfrontend_dart/data/local/miguel/register_draft_store.dart';
import 'package:gapfinderfrontend_dart/models/responses/auth_response.dart';
import 'package:gapfinderfrontend_dart/services/auth_service.dart';
import 'package:gapfinderfrontend_dart/viewmodels/auth/login_view_model.dart';

import 'noop_local_cache.dart';

class _AuthService extends AuthService {
  Object? error;

  @override
  Future<AuthResponse> login(String email, String password) async {
    if (error != null) throw error!;
    return AuthResponse(id: 1, accessToken: 'a', refreshToken: 'r', email: email, name: 'Ana');
  }
}

// Notes when the draft is cleared
class _DraftCache extends MiguelLocalCache {
  int clears = 0;

  @override
  void clearRegisterDraft() => clears++;
}

void main() {
  late Directory tempDir;

  setUpAll(() async {
    tempDir = await Directory.systemTemp.createTemp('register_draft_privacy_test');
    Hive.init(tempDir.path);
  });

  tearDownAll(() async {
    await Hive.close();
    await tempDir.delete(recursive: true);
  });

  const draft = RegisterDraft(name: 'Ana', email: 'ana@test.com', career: 'Systems', semester: '5');

  group('the sign up draft on a shared phone', () {
    test('a draft saved less than a day ago is given back', () async {
      final store = RegisterDraftStore();
      await store.save(draft);

      final restored = await store.get(now: DateTime.now().add(const Duration(hours: 23)));

      expect(restored?.email, 'ana@test.com');
      await store.clear();
    });

    test('an old draft (saved_at) is not given back and is deleted', () async {
      final store = RegisterDraftStore();
      await store.save(draft);

      expect(await store.get(now: DateTime.now().add(const Duration(hours: 25))), isNull);

      // It is gone for good, not only hidden
      expect(await store.get(), isNull);
      final box = await Hive.openBox(RegisterDraftStore.boxName);
      expect(box.isEmpty, isTrue);
    });

    test('a draft without saved_at is treated as old', () async {
      final box = await Hive.openBox(RegisterDraftStore.boxName);
      await box.putAll({'name': 'Luis', 'email': 'luis@test.com', 'career': null, 'semester': '3'});

      expect(await RegisterDraftStore().get(), isNull);
      expect(box.isEmpty, isTrue);
    });

    test('the password is still never stored', () async {
      final store = RegisterDraftStore();
      await store.save(draft);

      final box = await Hive.openBox(RegisterDraftStore.boxName);
      expect(box.keys.any((k) => k.toString().toLowerCase().contains('pass')), isFalse);
      await store.clear();
    });
  });

  group('logging in clears the sign up draft', () {
    late _AuthService auth;
    late _DraftCache drafts;
    late LoginViewModel vm;

    setUp(() {
      auth = _AuthService();
      drafts = _DraftCache();
      vm = LoginViewModel(authService: auth, localCache: NoopLocalCache(), draftCache: drafts);
    });

    tearDown(() => vm.dispose());

    test('a successful login clears it', () async {
      expect(await vm.login('ana@test.com', 'secret'), isTrue);

      expect(drafts.clears, 1);
    });

    test('a failed login keeps it', () async {
      auth.error = Exception('Invalid credentials');

      expect(await vm.login('ana@test.com', 'wrong'), isFalse);

      expect(drafts.clears, 0);
    });
  });
}
