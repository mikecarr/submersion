import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:submersion/core/database/database.dart';

void main() {
  test('media has the compressed rendition columns after open', () async {
    final db = AppDatabase(NativeDatabase.memory());
    addTearDown(db.close);
    final cols = await db.customSelect("PRAGMA table_info('media')").get();
    final names = cols.map((c) => c.read<String>('name')).toSet();
    expect(
      names,
      containsAll(<String>{
        'compressed_level',
        'compressed_size_bytes',
        'remote_compressed_uploaded_at',
      }),
    );
  });

  test('schema version is 130', () {
    expect(AppDatabase.currentSchemaVersion, 130);
  });
}
