import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/foundation.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:googleapis/drive/v3.dart' as drive;
import 'package:http/http.dart' as http;

import '../models/article.dart';

/// Backs the article library up to a folder in the user's Google Drive and
/// restores it on demand.
///
/// Requires a Google Cloud OAuth client ID for this app's package name and
/// SHA-1 fingerprint — see the README for setup steps.
class DriveSyncService extends ChangeNotifier {
  static const String _scope = drive.DriveApi.driveFileScope;
  static const String _folderName = 'Read Later Backup';
  static const String _fileName = 'read_later_backup.json';
  static const String _folderMime = 'application/vnd.google-apps.folder';

  GoogleSignInAccount? _account;
  drive.DriveApi? _driveApi;
  bool _busy = false;
  String? _statusMessage;
  bool _initialized = false;

  bool get isSignedIn => _driveApi != null;
  bool get isBusy => _busy;
  String? get accountEmail => _account?.email;
  String? get statusMessage => _statusMessage;

  Future<void> init() async {
    if (_initialized) return;
    _initialized = true;

    await GoogleSignIn.instance.initialize();

    // Silently restore a previous session (no-op if never signed in).
    try {
      final future = GoogleSignIn.instance.attemptLightweightAuthentication();
      final account = await future;
      if (account != null) {
        await _useAccount(account, promptIfNeeded: false);
      }
    } catch (_) {
      // Ignore; the user can sign in from Settings.
    }
  }

  Future<void> signIn() async {
    try {
      final account =
          await GoogleSignIn.instance.authenticate(scopeHint: [_scope]);
      await _useAccount(account, promptIfNeeded: true);
      _statusMessage = null;
      notifyListeners();
    } on GoogleSignInException catch (e) {
      if (e.code == GoogleSignInExceptionCode.canceled) {
        _statusMessage = 'Sign-in cancelled.';
      } else {
        _statusMessage = 'Sign-in failed: ${e.description ?? e.code.name}';
      }
      notifyListeners();
    }
  }

  Future<void> signOut() async {
    await GoogleSignIn.instance.signOut();
    _account = null;
    _driveApi = null;
    _statusMessage = null;
    notifyListeners();
  }

  /// Refreshes the access token and (re)builds the Drive API client.
  Future<void> _useAccount(
    GoogleSignInAccount account, {
    required bool promptIfNeeded,
  }) async {
    final authClient = account.authorizationClient;
    GoogleSignInClientAuthorization? authz =
        await authClient.authorizationForScopes([_scope]);
    if (authz == null && promptIfNeeded) {
      authz = await authClient.authorizeScopes([_scope]);
    }
    if (authz == null) {
      throw const GoogleSignInException(
        code: GoogleSignInExceptionCode.unknownError,
        description: 'Could not get Drive authorization.',
      );
    }
    _account = account;
    _driveApi = drive.DriveApi(_AuthClient(authz.accessToken));
    notifyListeners();
  }

  /// Uploads [articles] as a JSON file in the "Read Later Backup" folder.
  Future<void> backup(List<Article> articles) async {
    await _guard(() async {
      await _refreshAccessToken();
      final payload = jsonEncode({
        'version': 1,
        'exportedAt': DateTime.now().millisecondsSinceEpoch,
        'articles': articles.map((a) => a.toJson()).toList(),
      });
      final bytes = utf8.encode(payload);
      final media = drive.Media(
        Stream.value(bytes),
        bytes.length,
        contentType: 'application/json',
      );

      final folderId = await _getOrCreateFolder();
      final existing = await _getBackupFile(folderId);
      if (existing == null) {
        await _driveApi!.files.create(
          drive.File(name: _fileName, parents: [folderId]),
          uploadMedia: media,
          uploadOptions: drive.UploadOptions(),
        );
      } else {
        await _driveApi!.files.update(
          drive.File(),
          existing.id!,
          uploadMedia: media,
          uploadOptions: drive.UploadOptions(),
        );
      }
      _statusMessage =
          'Backed up ${articles.length} article${articles.length == 1 ? '' : 's'} to Drive.';
    });
  }

  /// Downloads the backup file and returns its articles (empty if none yet).
  Future<List<Article>> restore() async {
    var result = <Article>[];
    await _guard(() async {
      await _refreshAccessToken();
      final folderId = await _getOrCreateFolder();
      final file = await _getBackupFile(folderId);
      if (file == null) {
        _statusMessage = 'No backup found on Drive yet.';
        return;
      }
      final media = await _driveApi!.files.get(
        file.id!,
        downloadOptions: drive.DownloadOptions.fullMedia,
      ) as drive.Media;
      final bytes = await media.stream.fold<BytesBuilder>(
        BytesBuilder(),
        (builder, chunk) => builder..add(chunk),
      );
      final decoded = jsonDecode(utf8.decode(bytes.takeBytes()));
      final articles = (decoded['articles'] as List<dynamic>? ?? [])
          .map((e) => Article.fromJson(Map<String, dynamic>.from(e as Map)))
          .toList();
      result = articles;
      _statusMessage =
          'Restored ${articles.length} article${articles.length == 1 ? '' : 's'} from Drive.';
    });
    return result;
  }

  /// Drive access tokens expire after ~1 hour; fetch a fresh one before each
  /// operation when it's still possible without user interaction.
  Future<void> _refreshAccessToken() async {
    final account = _account;
    if (account == null) return;
    try {
      final authz = await account.authorizationClient
          .authorizationForScopes([_scope]);
      if (authz != null) {
        _driveApi = drive.DriveApi(_AuthClient(authz.accessToken));
      }
    } catch (_) {
      // Keep the current client; failures surface in _guard.
    }
  }

  Future<String> _getOrCreateFolder() async {
    final existing = await _findFolder();
    if (existing != null) return existing;
    final created = await _driveApi!.files.create(
      drive.File(
        name: _folderName,
        mimeType: _folderMime,
        parents: ['root'],
      ),
      $fields: 'id',
    );
    return created.id!;
  }

  Future<String?> _findFolder() async {
    final list = await _driveApi!.files.list(
      q: "name = '$_folderName' and 'root' in parents and trashed = false",
      $fields: 'files(id, name)',
    );
    final files = list.files ?? const [];
    return files.isEmpty ? null : files.first.id;
  }

  Future<drive.File?> _getBackupFile(String folderId) async {
    final list = await _driveApi!.files.list(
      q: "name = '$_fileName' and '$folderId' in parents and trashed = false",
      $fields: 'files(id, name)',
    );
    final files = list.files ?? const [];
    return files.isEmpty ? null : files.first;
  }

  /// Wraps an operation, setting the busy flag and catching errors into
  /// [statusMessage].
  Future<void> _guard(Future<void> Function() action) async {
    if (!isSignedIn) {
      _statusMessage = 'Sign in with Google first (Settings → Backup).';
      notifyListeners();
      return;
    }
    _busy = true;
    _statusMessage = null;
    notifyListeners();
    try {
      await action();
    } on http.ClientException catch (e) {
      _statusMessage = 'Network error: ${e.message}';
    } catch (e) {
      _statusMessage = 'Drive error: $e';
    } finally {
      _busy = false;
      notifyListeners();
    }
  }
}

/// Adds `Authorization: Bearer <token>` to every request for the Drive API.
class _AuthClient extends http.BaseClient {
  final String _token;
  final http.Client _inner = http.Client();

  _AuthClient(this._token);

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    request.headers['Authorization'] = 'Bearer $_token';
    return _inner.send(request);
  }

  @override
  void close() {
    _inner.close();
    super.close();
  }
}
