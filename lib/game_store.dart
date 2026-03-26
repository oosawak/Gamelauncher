import 'dart:convert';
import 'dart:io';
import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';
import 'models.dart';

/// Native-only GameStore for GAME LAUNCHER
class GameStore {
  GameStore._();
  static final instance = GameStore._();

  // Built-in games (update as needed)
  static const _builtIns = [
    {'name': 'Cubeboy (Built-in)',        'asset': 'assets/docs/Cubeboy.html'},
    {'name': 'R.P..G...8bit (Built-in)',  'asset': 'assets/docs/R_P__G___8bit.html'},
    {'name': 'Lineboy (Built-in)',        'asset': 'assets/docs/lineboy.html'},
  ];

  // ── Paths ─────────────────────────────────────────────
  Future<Directory> _romsDir() async {
    final docs = await getApplicationDocumentsDirectory();
    final dir  = Directory('${docs.path}/ROMs');
    if (!await dir.exists()) await dir.create(recursive: true);
    return dir;
  }

  Future<File> _bookmarksFile() async {
    final dir = await _romsDir();
    return File('${dir.path}/bookmarks.json');
  }

  // ── Bookmarks ────────────────────────────────────────
  Future<List<Map<String, String>>> _loadBookmarks() async {
    final file = await _bookmarksFile();
    if (!await file.exists()) return [];
    try {
      final List decoded = jsonDecode(await file.readAsString());
      return decoded
          .cast<Map<String, dynamic>>()
          .map((m) => m.map((k, v) => MapEntry(k, v.toString())))
          .toList();
    } catch (_) {
      return [];
    }
  }

  Future<void> _saveBookmarks(List<Map<String, String>> bm) async {
    final file = await _bookmarksFile();
    await file.writeAsString(jsonEncode(bm));
  }

  // ── Public: load ─────────────────────────────────────
  Future<List<GameEntry>> loadAll() async {
    final games = <GameEntry>[];
    // 1. Built-ins
    for (final e in _builtIns) {
      try {
        final html = await rootBundle.loadString(e['asset']!);
        games.add(GameEntry(
            name: e['name']!, htmlContent: html, isBuiltIn: true));
      } catch (_) {}
    }
    // 2. ROMs from storage
    final romsDir = await _romsDir();
    await for (final entity in romsDir.list(recursive: true)) {
      if (entity is! File) continue;
      if (!entity.path.endsWith('.html')) continue;
      final rel    = entity.path.substring(romsDir.path.length + 1);
      final parts  = rel.split('/');
      final folder = parts.length > 1 ? parts.first : null;
      final name   = parts.last.replaceAll('.html', '');
      games.add(GameEntry(
        name:        name,
        htmlContent: await entity.readAsString(),
        filePath:    entity.path,
        folder:      folder,
      ));
    }
    // 3. URL bookmarks
    for (final bm in await _loadBookmarks()) {
      games.add(GameEntry(
        name:        bm['name']        ?? 'Unknown',
        url:         bm['url'],
        folder:      bm['folder']?.isEmpty ?? true ? null : bm['folder'],
        thumbnailUrl: bm['thumbUrl'],
        author:      bm['author'],
        description: bm['description'],
      ));
    }
    return games;
  }

  Future<List<String>> loadFolderNames() async {
    final romsDir = await _romsDir();
    final names   = <String>{};
    await for (final e in romsDir.list()) {
      if (e is Directory) {
        final n = e.path.split('/').last;
        if (!n.startsWith('.')) names.add(n);
      }
    }
    for (final bm in await _loadBookmarks()) {
      final f = bm['folder'] ?? '';
      if (f.isNotEmpty) names.add(f);
    }
    return names.toList()..sort();
  }

  Future<void> addHtmlFile(File src, String name, {String? folder}) async {
    final dir = await _folderDir(folder);
    final safe = _safe(name);
    await src.copy('${dir.path}/$safe.html');
  }

  Future<void> downloadHtml(String url, String name, {String? folder}) async {
    final client = HttpClient();
    try {
      final req = await client.getUrl(Uri.parse(url));
      final res = await req.close();
      if (res.statusCode != 200) throw Exception('HTTP ${res.statusCode}');
      final html = await res.transform(const SystemEncoding().decoder).join();
      final dir  = await _folderDir(folder);
      await File('${dir.path}/${_safe(name)}.html').writeAsString(html);
    } finally {
      client.close();
    }
  }

  Future<void> addBookmark({
    required String name,
    required String url,
    String?  folder,
    String?  thumbUrl,
    String?  author,
    String?  description,
  }) async {
    final bookmarks = await _loadBookmarks();
    if (bookmarks.any((b) => b['url'] == url)) return;
    bookmarks.add({
      'name': name,
      'url':  url,
      if (folder?.isNotEmpty == true) 'folder': folder!,
      if (thumbUrl    != null) 'thumbUrl':    thumbUrl,
      if (author      != null) 'author':      author,
      if (description != null) 'description': description,
    });
    await _saveBookmarks(bookmarks);
  }

  Future<bool> isSaved(String url) async {
    final bm = await _loadBookmarks();
    return bm.any((b) => b['url'] == url);
  }

  Future<GameEntry> rename(GameEntry entry, String newName) async {
    if (entry.filePath != null) {
      final old  = File(entry.filePath!);
      final dir  = old.parent;
      final dest = File('${dir.path}/${_safe(newName)}.html');
      await old.rename(dest.path);
      return entry.copyWith(name: newName);
    } else if (entry.url != null) {
      final bm = await _loadBookmarks();
      for (final b in bm) {
        if (b['url'] == entry.url) b['name'] = newName;
      }
      await _saveBookmarks(bm);
      return entry.copyWith(name: newName);
    }
    return entry.copyWith(name: newName);
  }

  Future<GameEntry> moveToFolder(GameEntry entry, String? folder) async {
    final targetDir = await _folderDir(folder);
    if (entry.filePath != null) {
      final old  = File(entry.filePath!);
      final dest = File('${targetDir.path}/${old.uri.pathSegments.last}');
      await old.rename(dest.path);
      return entry.copyWith(folder: folder ?? '');
    } else if (entry.url != null) {
      final bm = await _loadBookmarks();
      for (final b in bm) {
        if (b['url'] == entry.url) {
          if (folder?.isNotEmpty == true) {
            b['folder'] = folder!;
          } else {
            b.remove('folder');
          }
        }
      }
      await _saveBookmarks(bm);
      return entry.copyWith(folder: folder ?? '');
    }
    return entry;
  }

  Future<void> createFolder(String name) async {
    final dir = await _folderDir(name);
    await dir.create(recursive: true);
  }

  Future<void> delete(GameEntry entry) async {
    if (entry.filePath != null) {
      final f = File(entry.filePath!);
      if (await f.exists()) await f.delete();
    } else if (entry.url != null) {
      final bm = await _loadBookmarks();
      bm.removeWhere((b) => b['url'] == entry.url);
      await _saveBookmarks(bm);
    }
  }

  // ── Helpers ──────────────────────────────────────────
  Future<Directory> _folderDir(String? folder) async {
    final root = await _romsDir();
    if (folder == null || folder.isEmpty) return root;
    final dir = Directory('${root.path}/${_safe(folder)}');
    if (!await dir.exists()) await dir.create(recursive: true);
    return dir;
  }

  static String _safe(String s) =>
      s.trim().replaceAll(RegExp(r'[/\\:*?"<>|]'), '_');
}
