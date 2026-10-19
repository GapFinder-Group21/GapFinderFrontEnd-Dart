import 'dart:convert';
import 'dart:io';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

// Saves and reads files inside the documents folder of the app.
// Paths are relative (for example 'cache/schedule.json'); the folders are created if needed.
class LocalFileStore {
  static final LocalFileStore instance = LocalFileStore._();
  LocalFileStore._();

  // Saves any value that jsonEncode can write
  Future<void> writeJson(String path, Object data) async {
    final file = await _file(path, createFolder: true);
    await file.writeAsString(jsonEncode(data));
  }

  // The decoded JSON, or null if the file does not exist
  Future<dynamic> readJson(String path) async {
    final file = await _file(path);
    if (!await file.exists()) return null;
    return jsonDecode(await file.readAsString());
  }

  Future<void> writeBytes(String path, List<int> bytes) async {
    final file = await _file(path, createFolder: true);
    await file.writeAsBytes(bytes);
  }

  // The bytes of the file, or null if it does not exist
  Future<List<int>?> readBytes(String path) async {
    final file = await _file(path);
    if (!await file.exists()) return null;
    return file.readAsBytes();
  }

  Future<void> delete(String path) async {
    final file = await _file(path);
    if (await file.exists()) await file.delete();
  }

  // When the file was saved, or null if it does not exist (useful for "actualizado a las HH:mm")
  Future<DateTime?> lastModified(String path) async {
    final file = await _file(path);
    if (!await file.exists()) return null;
    return file.lastModified();
  }

  Future<File> _file(String path, {bool createFolder = false}) async {
    final root = await getApplicationDocumentsDirectory();
    final file = File(p.join(root.path, path));
    if (createFolder) await file.parent.create(recursive: true);
    return file;
  }
}
