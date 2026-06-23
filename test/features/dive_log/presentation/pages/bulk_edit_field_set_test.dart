import 'package:flutter_test/flutter_test.dart';
import 'package:submersion/features/dive_log/presentation/pages/bulk_edit_field_set.dart';

void main() {
  test('buildScalarCompanion includes only enabled fields', () {
    final c = buildScalarCompanion({
      BulkField.diveCenter,
      BulkField.rating,
    }, BulkScalarInputs(diveCenterId: 'dc1', rating: 5, waterType: 'salt'));
    expect(c.diveCenterId.present, isTrue);
    expect(c.rating.present, isTrue);
    expect(c.waterType.present, isFalse); // not enabled
  });

  test('an enabled field set to null clears that column', () {
    final c = buildScalarCompanion({BulkField.diveCenter}, BulkScalarInputs());
    expect(c.diveCenterId.present, isTrue);
    expect(c.diveCenterId.value, isNull);
  });

  test('diluentGas gate sets both o2 and he columns', () {
    final c = buildScalarCompanion({
      BulkField.diluentGas,
    }, BulkScalarInputs(diluentO2: 21, diluentHe: 35));
    expect(c.diluentO2.present, isTrue);
    expect(c.diluentHe.present, isTrue);
    expect(c.diluentO2.value, 21);
    expect(c.diluentHe.value, 35);
  });

  test('an empty enabled set yields an all-absent companion', () {
    final c = buildScalarCompanion({}, BulkScalarInputs());
    expect(c.toColumns(false), isEmpty);
  });
}
