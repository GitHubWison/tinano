import 'package:meta/meta.dart';
import 'package:path/path.dart';
import 'package:sqflite/sqflite.dart';

typedef _OnCreate = Future<void> Function(Database db);
typedef _SchemaUpgrade = Future<void> Function(Database db);

class SchemaMigrationWithVersion {

  final _SchemaUpgrade upgrade;
  final int from;
  final int to;

  SchemaMigrationWithVersion(this.upgrade, this.from, this.to);
}

abstract class TinanoDatabase {

  /// The database from sqflite which we use to send queries etc.
  @protected
  DatabaseExecutor database;

  bool get isInTransaction => database is Transaction;

  /// Should only be used by the generated code
  _OnCreate onCreate;
  /// Should only be used by the generated code
  List<SchemaMigrationWithVersion> migrations = [];

  /// Creates a new instance of the database class but with the executor
  /// replaced to the one specified in the parameter. Useful as we can use
  /// this to create a new instance that doesn't write to the original database
  /// directly, but rather to a transaction created by that database.
  /// You should not override this method, the generated code will take care of
  /// that.
  @visibleForOverriding
  TinanoDatabase copyWithExecutor(DatabaseExecutor db);

  /// Opens this database. This method should only be invoked by the generated
  /// code.
  Future<void> performOpenAndInitialize(String fileName, int schemaVersion) async {
    final path = await getDatabasesPath();
    final dbPath = join(path, fileName);

    database = await openDatabase(
      dbPath,
      version: schemaVersion,
      onCreate: (db, _) async => await onCreate(db),
      onUpgrade: (db, from, to) async {
        var currentVersion = from;

        do {
          currentVersion = await _performSchemaUpgrade(currentVersion, db);
        } while (currentVersion != to);
      }
    );
  }

  /// Performs a schema upgrade from the current version to the highest version
  /// for which we have direct migration available.
  Future<int> _performSchemaUpgrade(int current, Database db) async {
    // Use a migration from the current version. Sort so that we can use the
    // migration that brings us to the biggest next schema version.
    final usableMigrations = migrations
      ..where((x) =>  x.from == current)
      ..sort((a, b) => a.to.compareTo(b.to));

    if (usableMigrations.isEmpty) {
      throw StateError("No migration to upgrade from $current");
    }

    final migration = usableMigrations.last;
    await migration.upgrade(db);

    return migration.to;
  }

  /// Starts a transaction or throws if already in a transaction. This method
  /// should only be called by autogenerated code.
  @protected
  Future<void> doInTransaction(Future<void> action(Transaction transaction)) async {
    final executor = database;
    if (isInTransaction) {
      throw StateError("Cannot start a transaction while already in a transaction");
    } else {
      await (executor as Database).transaction(action);
    }
  }
}
