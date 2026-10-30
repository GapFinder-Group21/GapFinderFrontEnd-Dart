import 'dart:io';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:gapfinderfrontend_dart/core/storage/local_file_store.dart';

// Copy of the open table photo, kept until the table is published.
// The camera leaves the photo in a temp folder the OS may clean, so it is copied to
// pending_photos/<timestamp>.jpg and its relative path is saved.
class PendingPhotoStore {
  static const _pathKey = 'joel_pending_photo_path';

  // A photo of a wizard left more than this long ago is not offered to a new table
  static const maxAge = Duration(hours: 24);

  // True when the photo saved at this path (pending_photos/<millis>.jpg) is older than maxAge
  static bool isExpired(String path, DateTime now) {
    final millis = int.tryParse(p.basenameWithoutExtension(path));
    if (millis == null) return false;
    return now.difference(DateTime.fromMillisecondsSinceEpoch(millis)) > maxAge;
  }

  // Save and clear run one after the other, so a fast publish never leaves a file behind
  Future<void> _queue = Future.value();

  Future<T> _inOrder<T>(Future<T> Function() action) {
    final result = _queue.then((_) => action());
    _queue = result.then((_) {}, onError: (_) {});
    return result;
  }

  // Copies the photo and returns its relative path; the previous pending photo is removed
  Future<String> save(File photo) => _inOrder(() async {
        final path = 'pending_photos/${DateTime.now().millisecondsSinceEpoch}.jpg';
        await LocalFileStore.instance.writeBytes(path, await photo.readAsBytes());

        final prefs = await SharedPreferences.getInstance();
        final previous = prefs.getString(_pathKey);
        await prefs.setString(_pathKey, path);
        if (previous != null && previous != path) await LocalFileStore.instance.delete(previous);
        return path;
      });

  // Relative path of the pending photo, or null if there is none
  Future<String?> currentPath() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_pathKey);
  }

  // The pending photo as a File, or null if there is none, the file is gone or it is too old
  // (an old one is removed, so days later a new table does not start with it)
  Future<File?> currentFile() async {
    final path = await currentPath();
    if (path == null) return null;
    if (isExpired(path, DateTime.now())) {
      await clear();
      return null;
    }
    final root = await getApplicationDocumentsDirectory();
    final file = File(p.join(root.path, path));
    return await file.exists() ? file : null;
  }

  // Removes the file and its path (after the table was published)
  Future<void> clear() => _inOrder(() async {
        final prefs = await SharedPreferences.getInstance();
        final path = prefs.getString(_pathKey);
        if (path != null) await LocalFileStore.instance.delete(path);
        await prefs.remove(_pathKey);
      });
}
