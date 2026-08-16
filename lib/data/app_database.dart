import 'package:path/path.dart' as p;
import 'package:sqflite/sqflite.dart';

/// Opens (and creates if needed) the app's SQLite database.
class AppDatabase {
  AppDatabase._();

  static const String _dbName = 'read_later.db';

  /// Opens the database. Tests can pass an in-memory or temp path.
  static Future<Database> open({String? path}) async {
    final dbPath = path ?? p.join(await getDatabasesPath(), _dbName);
    return openDatabase(
      dbPath,
      version: 1,
      onCreate: (db, version) async {
        await db.execute('''
          CREATE TABLE articles (
            id TEXT PRIMARY KEY,
            url TEXT NOT NULL,
            title TEXT NOT NULL,
            site_name TEXT,
            byline TEXT,
            excerpt TEXT,
            image_url TEXT,
            favicon_url TEXT,
            published_time TEXT,
            content_html TEXT NOT NULL DEFAULT '',
            text_content TEXT NOT NULL DEFAULT '',
            word_count INTEGER NOT NULL DEFAULT 0,
            reading_time_minutes INTEGER NOT NULL DEFAULT 0,
            saved_at INTEGER NOT NULL,
            updated_at INTEGER NOT NULL,
            status TEXT NOT NULL DEFAULT 'unread',
            is_favorite INTEGER NOT NULL DEFAULT 0,
            has_content INTEGER NOT NULL DEFAULT 0,
            read_progress REAL NOT NULL DEFAULT 0,
            listen_position INTEGER NOT NULL DEFAULT 0,
            listen_segment INTEGER NOT NULL DEFAULT 0
          )
        ''');
        await db.execute(
          'CREATE INDEX idx_articles_saved_at ON articles(saved_at DESC)',
        );
        await db.execute(
          'CREATE UNIQUE INDEX idx_articles_url ON articles(url)',
        );
      },
    );
  }
}
