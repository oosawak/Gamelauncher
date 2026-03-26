/// A launchable game entry.
class GameEntry {
  final String  name;
  final String? htmlContent;
  final String? url;
  final String? filePath;
  final String? folder;       // null / '' = root, otherwise folder name
  final String? thumbnailUrl;
  final String? author;
  final String? description;
  final bool    isBuiltIn;

  bool get isUrlBased  => url != null && htmlContent == null;
  bool get isDeletable => !isBuiltIn;

  const GameEntry({
    required this.name,
    this.htmlContent,
    this.url,
    this.filePath,
    this.folder,
    this.thumbnailUrl,
    this.author,
    this.description,
    this.isBuiltIn = false,
  });

  GameEntry copyWith({String? name, String? folder}) => GameEntry(
        name:         name         ?? this.name,
        htmlContent:  htmlContent,
        url:          url,
        filePath:     filePath,
        folder:       folder       ?? this.folder,
        thumbnailUrl: thumbnailUrl,
        author:       author,
        description:  description,
        isBuiltIn:    isBuiltIn,
      );
}
