import 'dart:convert';

import 'package:path/path.dart' as p;
import 'package:sqflite/sqflite.dart';
import 'package:pm5_bike/core/session_accumulator.dart';
import 'package:pm5_bike/data/workout_session.dart';

class SessionRepository {
  Database? _database;

  Future<List<WorkoutSession>> list() async {
    final database = await _open();
    final rows = await database.query('sessions', orderBy: 'started_at DESC');
    return [for (final row in rows) _fromRow(row)];
  }

  Future<void> insert(WorkoutSession session) async {
    final database = await _open();
    await database.insert('sessions', _toRow(session));
  }

  Future<void> delete(String id) async {
    final database = await _open();
    await database.delete('sessions', where: 'id = ?', whereArgs: [id]);
  }

  Future<Database> _open() async {
    final existing = _database;
    if (existing != null) {
      return existing;
    }
    final directory = await getDatabasesPath();
    final database = await openDatabase(
      p.join(directory, 'pm5_bike.db'),
      version: 1,
      onCreate: (db, version) async {
        await db.execute('''
          CREATE TABLE sessions (
            id TEXT PRIMARY KEY,
            started_at INTEGER NOT NULL,
            ended_at INTEGER NOT NULL,
            elapsed_seconds REAL NOT NULL,
            distance_meters REAL NOT NULL,
            average_watts REAL NOT NULL,
            pm5_average_watts REAL,
            calories REAL NOT NULL,
            average_rpm REAL NOT NULL,
            level INTEGER NOT NULL,
            had_out_of_range INTEGER NOT NULL,
            out_of_range_seconds REAL NOT NULL,
            samples_json TEXT NOT NULL
          )
        ''');
      },
    );
    _database = database;
    return database;
  }

  Map<String, Object?> _toRow(WorkoutSession session) {
    return {
      'id': session.id,
      'started_at': session.startedAt.toUtc().millisecondsSinceEpoch,
      'ended_at': session.endedAt.toUtc().millisecondsSinceEpoch,
      'elapsed_seconds': session.elapsedSeconds,
      'distance_meters': session.distanceMeters,
      'average_watts': session.averageWatts,
      'pm5_average_watts': session.pm5AverageWatts,
      'calories': session.calories,
      'average_rpm': session.averageRpm,
      'level': session.level,
      'had_out_of_range': session.hadOutOfRange ? 1 : 0,
      'out_of_range_seconds': session.outOfRangeSeconds,
      'samples_json': jsonEncode([
        for (final sample in session.samples) sample.toJson(),
      ]),
    };
  }

  WorkoutSession _fromRow(Map<String, Object?> row) {
    final samples = <SessionSample>[];
    final rawSamples = row['samples_json'];
    if (rawSamples is String) {
      final decoded = jsonDecode(rawSamples);
      if (decoded is List) {
        for (final item in decoded) {
          if (item is Map<String, dynamic>) {
            final sample = SessionSample.fromJson(item);
            if (sample != null) {
              samples.add(sample);
            }
          } else if (item is Map) {
            final sample = SessionSample.fromJson(
              Map<String, dynamic>.from(item),
            );
            if (sample != null) {
              samples.add(sample);
            }
          }
        }
      }
    }
    final pm5 = row['pm5_average_watts'];
    return WorkoutSession(
      id: row['id']! as String,
      startedAt: DateTime.fromMillisecondsSinceEpoch(
        row['started_at']! as int,
        isUtc: true,
      ).toLocal(),
      endedAt: DateTime.fromMillisecondsSinceEpoch(
        row['ended_at']! as int,
        isUtc: true,
      ).toLocal(),
      elapsedSeconds: (row['elapsed_seconds']! as num).toDouble(),
      distanceMeters: (row['distance_meters']! as num).toDouble(),
      averageWatts: (row['average_watts']! as num).toDouble(),
      pm5AverageWatts: pm5 is num ? pm5.toDouble() : null,
      calories: (row['calories']! as num).toDouble(),
      averageRpm: (row['average_rpm']! as num).toDouble(),
      level: row['level']! as int,
      hadOutOfRange: row['had_out_of_range'] == 1,
      outOfRangeSeconds: (row['out_of_range_seconds']! as num).toDouble(),
      samples: samples,
    );
  }
}
