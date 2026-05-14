import 'package:bluey/bluey.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('AdvertisingState', () {
    test('has all five expected values', () {
      expect(AdvertisingState.values, hasLength(5));
      expect(AdvertisingState.values, contains(AdvertisingState.idle));
      expect(AdvertisingState.values, contains(AdvertisingState.starting));
      expect(AdvertisingState.values, contains(AdvertisingState.advertising));
      expect(AdvertisingState.values, contains(AdvertisingState.stopping));
      expect(AdvertisingState.values, contains(AdvertisingState.invalidated));
    });

    test('invalidated is distinct from idle', () {
      expect(AdvertisingState.invalidated, isNot(equals(AdvertisingState.idle)));
    });
  });
}
