import 'package:gapfinderfrontend_dart/core/storage/hive_store.dart';

// What the user has typed in the sign up form. It has no password field on purpose:
// the password cannot be saved because there is nowhere to put it.
class RegisterDraft {
  final String name;
  final String email;
  final String? career;
  final String semester;

  const RegisterDraft({required this.name, required this.email, required this.career, required this.semester});
}

// Draft of the sign up form in Hive (box miguel_register_draft). It is deleted when the sign up works.
class RegisterDraftStore {
  static const boxName = 'miguel_register_draft';

  Future<void> save(RegisterDraft draft) async {
    final box = await HiveStore.box(boxName);
    await box.putAll({
      'name': draft.name,
      'email': draft.email,
      'career': draft.career,
      'semester': draft.semester,
      'saved_at': DateTime.now().toIso8601String(),
    });
  }

  // The saved draft, or null if there is none
  Future<RegisterDraft?> get() async {
    final box = await HiveStore.box(boxName);
    if (!box.containsKey('name')) return null;
    return RegisterDraft(
      name: box.get('name') as String? ?? '',
      email: box.get('email') as String? ?? '',
      career: box.get('career') as String?,
      semester: box.get('semester') as String? ?? '',
    );
  }

  Future<void> clear() async {
    final box = await HiveStore.box(boxName);
    await box.clear();
  }
}
