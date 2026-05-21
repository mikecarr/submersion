import 'package:submersion/features/universal_import/data/value_objects/scanned_file.dart';

/// A user-granted folder to enumerate. On desktop [path] is an absolute
/// filesystem path; on Android it is a persisted tree URI string; on
/// iOS / macOS it is a security-scoped directory URL string.
class GrantedFolder {
  final String path;
  const GrantedFolder({required this.path});
}

/// Platform abstraction enumerating a user-granted folder recursively and
/// yielding a persistable [ScannedFile] per file.
///
/// The iOS / macOS implementation MUST create each file's security-scoped
/// bookmark while the directory scope is held (during the walk), which is
/// why the stream yields a [ScannedFile] carrying a handle rather than
/// just a name. Callers enumerate exactly once per run.
abstract class DirectoryScanner {
  Stream<ScannedFile> scan(GrantedFolder folder);
}
