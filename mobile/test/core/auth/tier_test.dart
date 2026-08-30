import 'package:find_my_patterns/core/auth/tier.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('Tier.fromWire', () {
    test("'premium' maps to premium", () {
      expect(Tier.fromWire('premium'), Tier.premium);
    });

    test("'free', anything unrecognised, and null all map to free", () {
      expect(Tier.fromWire('free'), Tier.free);
      expect(Tier.fromWire('lifetime'), Tier.free);
      expect(Tier.fromWire(null), Tier.free);
    });
  });

  group('meInfoFromJson', () {
    test('decodes a premium account with a live expiry', () {
      final me = meInfoFromJson({
        'tier': 'premium',
        'expires_at': '2027-01-01T00:00:00Z',
      });
      expect(me.tier, Tier.premium);
      expect(me.expiresAt, DateTime.utc(2027));
    });

    test(
      'a null expires_at survives as null -- free or a lifetime purchase',
      () {
        final me = meInfoFromJson({'tier': 'free', 'expires_at': null});
        expect(me.tier, Tier.free);
        expect(me.expiresAt, isNull);
      },
    );

    test('an absent expires_at key reads the same as an explicit null', () {
      final me = meInfoFromJson({'tier': 'premium'});
      expect(me.expiresAt, isNull);
    });

    test('a timestamp with no zone marker is read as UTC, matching '
        '`pattern.dart`\'s own `_parseInstant`', () {
      final me = meInfoFromJson({
        'tier': 'premium',
        'expires_at': '2027-01-01T00:00:00',
      });
      expect(me.expiresAt, DateTime.utc(2027));
    });

    test('an unparseable expires_at falls back to null, not the epoch -- '
        'unlike a field that is always present, this one is genuinely '
        'absent for a free or lifetime account and must stay absent on a '
        'parse failure too', () {
      final me = meInfoFromJson({
        'tier': 'premium',
        'expires_at': 'not a date',
      });
      expect(me.expiresAt, isNull);
    });

    test('an absent tier defaults to free, never a guess', () {
      final me = meInfoFromJson({});
      expect(me.tier, Tier.free);
      expect(me.expiresAt, isNull);
    });
  });
}
