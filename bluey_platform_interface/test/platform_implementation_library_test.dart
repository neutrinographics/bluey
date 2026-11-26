import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('the main library does not export the implementation library', () {
    // arrange
    final mainLibrary =
        File('lib/bluey_platform_interface.dart').readAsStringSync();

    // act
    final namesImplementation =
        mainLibrary.contains('src/implementation/') ||
        mainLibrary.contains('platform_implementation.dart');

    // assert
    expect(namesImplementation, isFalse);
  });
}
