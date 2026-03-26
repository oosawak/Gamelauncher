import 'dart:io' show File; // Only used for native
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';
import 'models.dart';
import 'game_store.dart';
final gameStore = GameStore.instance;
const bool kEnableGallery = false;
/* 2026-03-25 Gallery Comment Out
import 'gallery_screen.dart';
*/
class LauncherScreen extends StatefulWidget {
  final void Function(GameEntry game) onLaunch;
  const LauncherScreen({super.key, required this.onLaunch});

  @override
  State<LauncherScreen> createState() => _LauncherScreenState();
}

class _LauncherScreenState extends State<LauncherScreen> {
  List<GameEntry> _games   = [];
  List<String>    _folders = [];
  bool            _loading = true;
  final _urlController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _reload();
  }

  @override
  void dispose() {
    _urlController.dispose();
    super.dispose();
  }

  Future<void> _reload() async {
    setState(() => _loading = true);
    final games   = await gameStore.loadAll();
    final folders = await gameStore.loadFolderNames();
    setState(() {
      _games   = games;
      _folders = folders;
      _loading = false;
    });
  }

  // ── Add ───────────────────────────────────────────────────────────────

  Future<void> _pickFile() async {
    if (kIsWeb) return; // Webではファイルピック不可
    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['html'],
      allowMultiple: true,
    );
    if (result == null) return;
    for (final pf in result.files) {
      if (pf.path == null) continue;
      final name = pf.name.replaceAll('.html', '');
      await gameStore.addHtmlFile(File(pf.path!), name);
    }
    await _reload();
  }

  Future<void> _addFromUrl(String url) async {
    if (url.trim().isEmpty) return;
    final uri  = Uri.parse(url.trim());
    final name = uri.pathSegments
        .lastWhere((s) => s.isNotEmpty, orElse: () => 'WebGame')
        .replaceAll('.html', '');
    try {
      if (url.endsWith('.html')) {
        await gameStore.downloadHtml(url.trim(), name);
      } else {
        await gameStore.addBookmark(name: name, url: url.trim());
      }
      _urlController.clear();
      await _reload();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: Text('追加失敗: $e'),
            backgroundColor: Colors.red[900]));
      }
    }
  }

  // ── Edit sheet ────────────────────────────────────────────────────────

  Future<void> _showEditSheet(GameEntry game) async {
    await showModalBottomSheet(
      context: context,
      backgroundColor: const Color(0xFF1a1a2e),
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(16))),
      builder: (_) => _EditSheet(
        game:    game,
        folders: _folders,
        onRename: (newName) async {
          await gameStore.rename(game, newName);
          await _reload();
        },
        onMove: (folder) async {
          await gameStore.moveToFolder(game, folder);
          await _reload();
        },
        onDelete: () async {
          await gameStore.delete(game);
          await _reload();
        },
        onCreateFolder: (folderName) async {
          await gameStore.createFolder(folderName);
          await _reload();
        },
      ),
    );
  }
/* 2026-03-25 Gallery Comment Out
  void _openGallery() {
    Navigator.of(context).push(MaterialPageRoute(
      builder: (_) => GalleryScreen(
        onLaunch: (game) {
          Navigator.of(context).pop();
          widget.onLaunch(game);
        },
        onSaved: _reload,
      ),
    ));
  }
*/
  // ── Build ─────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0a0a1a),
      body: Column(children: [
        _buildHeader(),
        Expanded(
          child: _loading
              ? const Center(
                  child: CircularProgressIndicator(color: Colors.cyan))
              : _buildGroupedList(),
        ),
        _buildFooter(),
      ]),
    );
  }

  Widget _buildHeader() => Container(
        padding: const EdgeInsets.fromLTRB(24, 48, 24, 12),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            const Text('🎮  GAME LAUNCHER',
                style: TextStyle(
                    color: Colors.cyan,
                    fontSize: 22,
                    fontWeight: FontWeight.bold,
                    letterSpacing: 3)),
            // New folder button
            IconButton(
              icon: const Icon(Icons.create_new_folder_outlined,
                  color: Colors.white54),
              tooltip: 'フォルダーを作成',
              onPressed: () => _showCreateFolderDialog(),
            ),
          ],
        ),
      );

  Future<void> _showCreateFolderDialog() async {
    final ctrl = TextEditingController();
    await showDialog(
      context: context,
      builder: (_) => _InputDialog(
        title: 'フォルダーを作成',
        hint: 'フォルダー名',
        controller: ctrl,
        onConfirm: () async {
          if (ctrl.text.trim().isNotEmpty) {
            await gameStore.createFolder(ctrl.text.trim());
            await _reload();
          }
        },
      ),
    );
  }

  /// Build a grouped list: Built-ins → ungrouped → folder sections
  Widget _buildGroupedList() {
    final builtIns   = _games.where((g) => g.isBuiltIn).toList();
    final ungrouped  = _games
        .where((g) => !g.isBuiltIn && (g.folder == null || g.folder!.isEmpty))
        .toList();
    final Map<String, List<GameEntry>> grouped = {};
    for (final f in _folders) {
      grouped[f] = _games
          .where((g) => g.folder == f && !g.isBuiltIn)
          .toList();
    }

    final sections = <Widget>[];

    // Built-ins section
    if (builtIns.isNotEmpty) {
      sections.add(_SectionHeader(title: '⭐ ビルトイン', accent: Colors.cyan));
      for (final g in builtIns) {
        sections.add(_GameTile(
            game: g, onLaunch: () => widget.onLaunch(g), onEdit: null));
      }
    }

    // Ungrouped games
    if (ungrouped.isNotEmpty) {
      sections.add(_SectionHeader(title: '📁 マイゲーム', accent: Colors.white54));
      for (final g in ungrouped) {
        sections.add(_GameTile(
          game:    g,
          onLaunch: () => widget.onLaunch(g),
          onEdit:   () => _showEditSheet(g),
        ));
      }
    }

    // Folder sections
    for (final entry in grouped.entries) {
      sections.add(
          _SectionHeader(title: '📂 ${entry.key}', accent: Colors.purple[200]!));
      if (entry.value.isEmpty) {
        sections.add(Padding(
          padding: const EdgeInsets.only(left: 24, bottom: 8),
          child: Text('（空のフォルダー）',
              style: TextStyle(color: Colors.white24, fontSize: 12)),
        ));
      }
      for (final g in entry.value) {
        sections.add(_GameTile(
          game:    g,
          onLaunch: () => widget.onLaunch(g),
          onEdit:   () => _showEditSheet(g),
        ));
      }
    }

    if (sections.isEmpty) {
      return const Center(
          child: Text('ゲームがありません', style: TextStyle(color: Colors.white38)));
    }

    return ListView(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
      children: sections,
    );
  }

  Widget _buildFooter() => Container(
        padding: const EdgeInsets.fromLTRB(14, 8, 14, 30),
        decoration: const BoxDecoration(
            border: Border(top: BorderSide(color: Colors.white12)),
            color: Color(0xFF0a0a1a)),
        child: Column(children: [
/* 2026-03-25 Gallery Comment Out
          SizedBox(
            width: double.infinity,
            child: ElevatedButton.icon(
              onPressed: _openGallery,
              icon: const Icon(Icons.public, size: 18),
              label: const Text('Pyxel User Examples ギャラリー'),
              style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.purple,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  textStyle: const TextStyle(
                      fontSize: 14, fontWeight: FontWeight.bold)),
            ),
          ),
*/
          const SizedBox(height: 8),
          Row(children: [
            Expanded(
              child: TextField(
                controller: _urlController,
                style: const TextStyle(color: Colors.white, fontSize: 13),
                decoration: InputDecoration(
                  hintText: 'https://example.com/game.html',
                  hintStyle: TextStyle(color: Colors.white24, fontSize: 13),
                  filled: true,
                  fillColor: Colors.white10,
                  contentPadding: const EdgeInsets.symmetric(
                      horizontal: 12, vertical: 10),
                  border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(8),
                      borderSide: BorderSide.none),
                  prefixIcon:
                      const Icon(Icons.link, color: Colors.white38, size: 18),
                ),
                onSubmitted: _addFromUrl,
              ),
            ),
            const SizedBox(width: 8),
            _FooterBtn(
                icon: Icons.add,
                label: '追加',
                onTap: () => _addFromUrl(_urlController.text)),
          ]),
          const SizedBox(height: 8),
          Row(children: [
            _FooterBtn(
                icon: Icons.folder_open,
                label: 'ファイルを追加',
                onTap: _pickFile),
            const SizedBox(width: 8),
            _FooterBtn(icon: Icons.refresh, label: '更新', onTap: _reload),
          ]),
        ]),
      );
}

// ── Edit bottom sheet ──────────────────────────────────────────────────────

class _EditSheet extends StatelessWidget {
  const _EditSheet({
    required this.game,
    required this.folders,
    required this.onRename,
    required this.onMove,
    required this.onDelete,
    required this.onCreateFolder,
  });
  final GameEntry game;
  final List<String> folders;
  final Future<void> Function(String)  onRename;
  final Future<void> Function(String?) onMove;
  final Future<void> Function()        onDelete;
  final Future<void> Function(String)  onCreateFolder;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 32),
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        // Handle
        Container(
            width: 36,
            height: 4,
            decoration: BoxDecoration(
                color: Colors.white24,
                borderRadius: BorderRadius.circular(2))),
        const SizedBox(height: 12),
        Text(game.name,
            style: const TextStyle(
                color: Colors.white,
                fontSize: 15,
                fontWeight: FontWeight.bold),
            overflow: TextOverflow.ellipsis),
        const SizedBox(height: 16),
        // Rename
        _SheetAction(
          icon: Icons.edit,
          label: '名前を変更',
          color: Colors.cyan,
          onTap: () async {
            Navigator.pop(context);
            final ctrl = TextEditingController(text: game.name);
            await showDialog(
              context: context,
              builder: (_) => _InputDialog(
                title: '名前を変更',
                hint: '新しい名前',
                controller: ctrl,
                onConfirm: () => onRename(ctrl.text.trim()),
              ),
            );
          },
        ),
        // Move to folder
        _SheetAction(
          icon: Icons.drive_file_move_outlined,
          label: 'フォルダーに移動',
          color: Colors.purple[200]!,
          onTap: () async {
            Navigator.pop(context);
            await showDialog(
              context: context,
              builder: (_) => _FolderPickerDialog(
                currentFolder: game.folder,
                folders: folders,
                onPick: onMove,
                onCreateFolder: onCreateFolder,
              ),
            );
          },
        ),
        const Divider(color: Colors.white12, height: 24),
        // Delete
        _SheetAction(
          icon: Icons.delete_outline,
          label: '削除',
          color: Colors.red[300]!,
          onTap: () async {
            Navigator.pop(context);
            final ok = await showDialog<bool>(
              context: context,
              builder: (dialogContext) => AlertDialog(
                backgroundColor: const Color(0xFF1a1a2e),
                title: const Text('削除', style: TextStyle(color: Colors.white)),
                content: Text('「${game.name}」を削除しますか？',
                    style: const TextStyle(color: Colors.white70)),
                actions: [
                  TextButton(
                      onPressed: () => Navigator.pop(dialogContext, false),
                      child: const Text('キャンセル',
                          style: TextStyle(color: Colors.white54))),
                  ElevatedButton(
                      style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.red),
                      onPressed: () => Navigator.pop(dialogContext, true),
                      child: const Text('削除')),
                ],
              ),
            );
            if (ok == true) await onDelete();
          },
        ),
      ]),
    );
  }
}

class _SheetAction extends StatelessWidget {
  const _SheetAction(
      {required this.icon,
      required this.label,
      required this.color,
      required this.onTap});
  final IconData icon;
  final String label;
  final Color color;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => ListTile(
        leading: Icon(icon, color: color),
        title: Text(label, style: TextStyle(color: color, fontSize: 15)),
        onTap: onTap,
        contentPadding: EdgeInsets.zero,
      );
}

// ── Folder picker dialog ───────────────────────────────────────────────────

class _FolderPickerDialog extends StatefulWidget {
  const _FolderPickerDialog({
    required this.currentFolder,
    required this.folders,
    required this.onPick,
    required this.onCreateFolder,
  });
  final String? currentFolder;
  final List<String> folders;
  final Future<void> Function(String?) onPick;
  final Future<void> Function(String) onCreateFolder;

  @override
  State<_FolderPickerDialog> createState() => _FolderPickerDialogState();
}

class _FolderPickerDialogState extends State<_FolderPickerDialog> {
  late List<String> _folders;

  @override
  void initState() {
    super.initState();
    _folders = List.from(widget.folders);
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      backgroundColor: const Color(0xFF1a1a2e),
      title: const Text('フォルダーに移動',
          style: TextStyle(color: Colors.white)),
      content: SizedBox(
        width: 280,
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          // Root (no folder)
          _FolderOption(
            label: '📁 マイゲーム（フォルダーなし）',
            selected: widget.currentFolder == null || widget.currentFolder!.isEmpty,
            onTap: () {
              Navigator.pop(context);
              widget.onPick(null);
            },
          ),
          ..._folders.map((f) => _FolderOption(
                label: '📂 $f',
                selected: widget.currentFolder == f,
                onTap: () {
                  Navigator.pop(context);
                  widget.onPick(f);
                },
              )),
          const Divider(color: Colors.white12),
          // Create new folder inline
          TextButton.icon(
            icon: const Icon(Icons.create_new_folder_outlined,
                color: Colors.cyan, size: 18),
            label: const Text('新しいフォルダーを作成',
                style: TextStyle(color: Colors.cyan, fontSize: 13)),
            onPressed: () async {
              final ctrl = TextEditingController();
              await showDialog(
                context: context,
                builder: (_) => _InputDialog(
                  title: 'フォルダーを作成',
                  hint: 'フォルダー名',
                  controller: ctrl,
                  onConfirm: () async {
                    if (ctrl.text.trim().isNotEmpty) {
                      await widget.onCreateFolder(ctrl.text.trim());
                      setState(() => _folders.add(ctrl.text.trim()));
                    }
                  },
                ),
              );
            },
          ),
        ]),
      ),
    );
  }
}

class _FolderOption extends StatelessWidget {
  const _FolderOption(
      {required this.label, required this.selected, required this.onTap});
  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => ListTile(
        title: Text(label,
            style: TextStyle(
                color: selected ? Colors.cyan : Colors.white70,
                fontSize: 13)),
        trailing: selected
            ? const Icon(Icons.check, color: Colors.cyan, size: 18)
            : null,
        onTap: onTap,
        contentPadding: EdgeInsets.zero,
        dense: true,
      );
}

// ── Input dialog ───────────────────────────────────────────────────────────

class _InputDialog extends StatelessWidget {
  const _InputDialog({
    required this.title,
    required this.hint,
    required this.controller,
    required this.onConfirm,
  });
  final String title;
  final String hint;
  final TextEditingController controller;
  final Future<void> Function() onConfirm;

  @override
  Widget build(BuildContext context) => AlertDialog(
        backgroundColor: const Color(0xFF1a1a2e),
        title: Text(title, style: const TextStyle(color: Colors.white)),
        content: TextField(
          controller: controller,
          autofocus: true,
          style: const TextStyle(color: Colors.white),
          decoration: InputDecoration(
            hintText: hint,
            hintStyle: const TextStyle(color: Colors.white38),
            filled: true,
            fillColor: Colors.white10,
            border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(8),
                borderSide: BorderSide.none),
          ),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('キャンセル',
                  style: TextStyle(color: Colors.white54))),
          ElevatedButton(
              style: ElevatedButton.styleFrom(backgroundColor: Colors.cyan),
              onPressed: () async {
                await onConfirm();
                if (context.mounted) Navigator.pop(context);
              },
              child: const Text('OK',
                  style: TextStyle(color: Colors.black))),
        ],
      );
}

// ── Section header ─────────────────────────────────────────────────────────

class _SectionHeader extends StatelessWidget {
  const _SectionHeader({required this.title, required this.accent});
  final String title;
  final Color accent;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.fromLTRB(4, 12, 0, 4),
        child: Text(title,
            style: TextStyle(
                color: accent,
                fontSize: 12,
                fontWeight: FontWeight.bold,
                letterSpacing: 1)),
      );
}

// ── Game tile ──────────────────────────────────────────────────────────────

class _GameTile extends StatelessWidget {
  const _GameTile(
      {required this.game, required this.onLaunch, required this.onEdit});
  final GameEntry game;
  final VoidCallback onLaunch;
  final VoidCallback? onEdit;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 6),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.05),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(
            color: game.isBuiltIn
                ? Colors.cyan.withOpacity(0.3)
                : Colors.white12),
      ),
      child: Row(children: [
        // Thumbnail or icon
        ClipRRect(
          borderRadius:
              const BorderRadius.horizontal(left: Radius.circular(10)),
          child: game.thumbnailUrl != null
              ? Image.network(game.thumbnailUrl!,
                  width: 60,
                  height: 60,
                  fit: BoxFit.cover,
                  errorBuilder: (_, __, ___) => _icon(game))
              : _icon(game),
        ),
        // Name + badge
        Expanded(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
            child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(game.name,
                      style: const TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.w600,
                          fontSize: 13),
                      overflow: TextOverflow.ellipsis),
                  if (game.author?.isNotEmpty == true)
                    Text('by ${game.author}',
                        style: const TextStyle(
                            color: Colors.cyan, fontSize: 11)),
                  if (game.isUrlBased)
                    const Text('URL',
                        style:
                            TextStyle(color: Colors.white38, fontSize: 10)),
                ]),
          ),
        ),
        // Edit + Play
        Row(mainAxisSize: MainAxisSize.min, children: [
          if (onEdit != null)
            IconButton(
              icon: const Icon(Icons.more_vert,
                  color: Colors.white38, size: 20),
              onPressed: onEdit,
              tooltip: '編集',
            ),
          Padding(
            padding: const EdgeInsets.only(right: 10),
            child: ElevatedButton.icon(
              onPressed: onLaunch,
              icon: const Icon(Icons.play_arrow, size: 18),
              label: const Text('起動'),
              style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.cyan,
                  foregroundColor: Colors.black,
                  padding: const EdgeInsets.symmetric(
                      horizontal: 12, vertical: 8),
                  textStyle:
                      const TextStyle(fontWeight: FontWeight.bold)),
            ),
          ),
        ]),
      ]),
    );
  }

  Widget _icon(GameEntry g) => Container(
      width: 60,
      height: 60,
      color: Colors.white10,
      child: Icon(
          g.isBuiltIn ? Icons.star : Icons.sports_esports,
          color: g.isBuiltIn ? Colors.cyan : Colors.purple[200],
          size: 24));
}

class _FooterBtn extends StatelessWidget {
  const _FooterBtn(
      {required this.icon, required this.label, required this.onTap});
  final IconData icon;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => OutlinedButton.icon(
        onPressed: onTap,
        icon: Icon(icon, size: 16),
        label: Text(label),
        style: OutlinedButton.styleFrom(
            foregroundColor: Colors.white70,
            side: const BorderSide(color: Colors.white24),
            padding:
                const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            textStyle: const TextStyle(fontSize: 13)),
      );
}
