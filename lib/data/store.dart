import 'dart:convert';
import 'dart:io';

import 'package:path_provider/path_provider.dart';

/// Простое хранилище JSON-файлов в папке приложения, отдельная папка на каждый самокат.
/// Записи идут строго по очереди, чтобы файлы не портились.
class Store {
  final Directory dir;
  Future<void> _queue = Future.value();

  Store._(this.dir);

  static Future<Store> open(String key) async {
    final base = await getApplicationDocumentsDirectory();
    final d = Directory('${base.path}/m365/$key');
    await Directory('${d.path}/trips').create(recursive: true);
    return Store._(d);
  }

  File _f(String name) => File('${dir.path}/$name');

  Future<dynamic> readJson(String name) async {
    try {
      final f = _f(name);
      if (!await f.exists()) return null;
      return jsonDecode(await f.readAsString());
    } catch (_) {
      return null;
    }
  }

  Future<void> writeJson(String name, Object? value) {
    final text = jsonEncode(value);
    _queue = _queue.then((_) async {
      final f = _f(name);
      final tmp = File('${f.path}.tmp');
      await tmp.writeAsString(text, flush: true);
      await tmp.rename(f.path);
    }).catchError((_) {});
    return _queue;
  }

  Future<void> delete(String name) {
    _queue = _queue.then((_) async {
      final f = _f(name);
      if (await f.exists()) await f.delete();
    }).catchError((_) {});
    return _queue;
  }
}
