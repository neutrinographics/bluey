import 'package:bluey/src/features/discovery/domain/scan_id.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('a ScanId equals another of the same value and no other', () {
    // arrange
    const id = ScanId(1);

    // act
    const same = ScanId(1);
    const other = ScanId(2);

    // assert
    expect(id, same);
    expect(id.hashCode, same.hashCode);
    expect(id, isNot(other));
  });

  test('a ScannerId equals another of the same value and no other', () {
    // arrange
    const id = ScannerId(1);

    // act
    const same = ScannerId(1);
    const other = ScannerId(2);

    // assert
    expect(id, same);
    expect(id.hashCode, same.hashCode);
    expect(id, isNot(other));
  });

  test('a scan id and a scanner id of one number are not equal', () {
    // arrange
    const scan = ScanId(1);

    // act
    const scanner = ScannerId(1);

    // assert
    expect(scan == scanner, isFalse);
  });
}
