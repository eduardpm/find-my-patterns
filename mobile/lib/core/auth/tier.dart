import '../network/api_client.dart';

/// The two tiers `GET /auth/me` can report (M-3, #48's backend half).
///
/// A closed set rather than a raw string carried around the app: every
/// screen that renders differently by tier switches on this, and the
/// compiler flags a screen that forgets a case the day a third tier is
/// ever added.
enum Tier {
  /// No entitlement on file -- the default for every account until it
  /// buys or is granted one.
  free,

  /// A live entitlement, permanent or with an expiry (see [MeInfo.expiresAt]).
  premium;

  /// `'premium'` maps to [premium]; anything else -- `'free'`, an
  /// unrecognised value, or the key being absent entirely -- maps to
  /// [free]. The safe reading of "we don't know this account's tier" is
  /// "free": this client never renders a premium surface on a guess.
  static Tier fromWire(String? raw) =>
      raw == 'premium' ? Tier.premium : Tier.free;
}

/// `GET /auth/me`'s response, restricted to what this client acts on.
///
/// The endpoint also answers the account's id, email and creation date
/// (`UserOut`, `backend/src/auth/identity.service.ts`) -- dropped here the
/// same way `MoodSeries` drops `GET /insights/series`'s `granularity`: this
/// client has nothing to do with an account identity beyond its tier, since
/// the diary itself runs single-tenant on the user's own device.
class const MeInfo(
  final Tier tier,

  /// The entitlement's own expiry, `null` for free or for a lifetime
  /// purchase. Not read anywhere yet -- Play Billing's purchase flow and
  /// any "renews on ..." copy are a later, store-launch ticket -- but kept
  /// on the model now rather than dropped and re-added, since it is already
  /// on the wire for free.
  final DateTime? expiresAt,
);

/// Decodes `GET /auth/me`'s response.
MeInfo meInfoFromJson(JsonObject json) => MeInfo(
  Tier.fromWire(json['tier'] as String?),
  _parseInstant(json['expires_at'] as String?),
);

/// Matches a trailing `Z` or a numeric UTC offset such as `+02:00`.
final RegExp _zonePattern = RegExp(r'(Z|[+-]\d{2}:?\d{2})$');

/// Parses a nullable backend timestamp into a UTC instant, or `null` when
/// [raw] itself is `null` -- unlike `pattern.dart`'s `_parseInstant`, which
/// backs a field that is always present on the wire, `expires_at` is
/// genuinely absent for a free or lifetime account and that has to survive
/// the parse rather than fall back to the epoch.
DateTime? _parseInstant(String? raw) {
  if (raw == null) return null;
  try {
    final normalized = _zonePattern.hasMatch(raw) ? raw : '${raw}Z';
    return DateTime.parse(normalized).toUtc();
  } on FormatException {
    return null;
  }
}
