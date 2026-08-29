/// How a feeling is scored, which is what lets Insights say "keep doing
/// this" versus "consider changing this".
///
/// Because that is a rule and not presentation, which feeling carries which
/// valence is decided by the backend and served by `GET /feelings` — this
/// enum only names the closed vocabulary the contract defines, with
/// [unknown] so a value the backend adds later cannot crash the client.
enum Valence {
  /// A feeling insights treat as worth keeping.
  positive,

  /// A feeling insights are indifferent to.
  neutral,

  /// A feeling insights treat as worth changing.
  negative,

  /// A value this build does not recognise.
  unknown;

  /// Resolves a wire valence string. Lowercases first, and anything not in
  /// the closed vocabulary — including null — is [unknown]. Never throws.
  static Valence fromWire(String? raw) => switch (raw?.toLowerCase()) {
    'positive' => Valence.positive,
    'neutral' => Valence.neutral,
    'negative' => Valence.negative,
    _ => Valence.unknown,
  };
}

/// One feeling from the predefined mood set.
///
/// This used to be a hardcoded set duplicating the backend's seeded table.
/// The set's membership, labels and — most importantly — valences now come
/// from `GET /feelings` and are carried in this value type. Build instances
/// only from a [FeelingCatalog]; never invent one locally.
class const Feeling(
  final String key,
  final String label,
  final Valence valence,

  /// Which group this feeling is picked inside. Decided by the backend,
  /// never by this client.
  final String groupKey,
) {
  @override
  bool operator ==(Object other) =>
      other is Feeling &&
      other.key == key &&
      other.label == label &&
      other.valence == valence &&
      other.groupKey == groupKey;

  @override
  int get hashCode => Object.hash(key, label, valence, groupKey);

  @override
  String toString() => 'Feeling($key)';
}

/// A group of related feelings — the first level of the picker.
///
/// The vocabulary is around thirty words, far too many to put in front of
/// someone mid-entry without turning the fastest step into a scanning
/// exercise. A group is what the user chooses first; its own words open on
/// demand. Which group a feeling belongs to and the group's valence are the
/// backend's to decide; the accent colour a group is drawn in is this
/// client's.
class const FeelingGroup(
  final String key,
  final String label,
  final Valence valence,
  final List<Feeling> feelings,
) {
  @override
  bool operator ==(Object other) =>
      other is FeelingGroup &&
      other.key == key &&
      other.label == label &&
      other.valence == valence &&
      _listEquals(other.feelings, feelings);

  @override
  int get hashCode =>
      Object.hash(key, label, valence, Object.hashAll(feelings));
}

bool _listEquals<T>(List<T> a, List<T> b) {
  if (a.length != b.length) return false;
  for (var i = 0; i < a.length; i++) {
    if (a[i] != b[i]) return false;
  }
  return true;
}

/// An immutable snapshot of the backend-served feeling set, in the
/// backend's own order (the contract guarantees that order is stable).
///
/// Resolving a wire `feeling_key` requires a catalog, which is exactly the
/// compile-time pressure that keeps the set from being re-hardcoded.
class const FeelingCatalog(
  final List<Feeling> feelings, {
  final List<FeelingGroup> groups = const [],
}) {
  /// A catalog holding nothing — the state before `GET /feelings` has ever
  /// answered.
  static const FeelingCatalog empty = FeelingCatalog([]);

  /// The lookup [fromKey] and [fromKeys] read through. A getter rather than
  /// a cached field: the catalog's own constructor is const, which rules out
  /// a `late` field, and the vocabulary is small enough (around thirty
  /// entries) that rebuilding this on each call costs nothing that matters.
  Map<String, Feeling> get _byKey => {
    for (final feeling in feelings) feeling.key: feeling,
  };

  /// The feeling stored under [key], or null when it is missing or this
  /// build has no entry for it.
  Feeling? fromKey(String? key) => key == null ? null : _byKey[key];

  /// Resolves stored [keys], dropping any this build has no entry for
  /// rather than inventing one.
  List<Feeling> fromKeys(List<String> keys) => [
    for (final key in keys) ?_byKey[key],
  ];
}

/// The ceiling the backend enforces on how many feelings one entry may
/// carry.
const int kMaxFeelingsPerEntry = 4;
