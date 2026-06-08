// packages/insforge_database/lib/src/enums.dart

/// Count algorithm for `count()` queries, sent as `Prefer: count=<token>`.
enum CountType {
  /// Exact count (full scan). Most accurate, slowest.
  exact,

  /// Planner estimate. Fast, may be inaccurate after bulk writes.
  planned,

  /// Statistics-based estimate. Fastest, least accurate.
  estimated;

  /// The `Prefer: count=` token for this algorithm.
  String get preferToken => name;
}

/// Full-text search parsing strategy, mapped to its PostgREST operator.
///
/// * [plain] → `plfts` (plainto_tsquery) — default.
/// * [phrase] → `phfts` (phraseto_tsquery).
/// * [websearch] → `wfts` (websearch_to_tsquery).
/// * [full] → `fts` (to_tsquery, raw tsquery syntax).
enum TextSearchType {
  plain('plfts'),
  phrase('phfts'),
  websearch('wfts'),
  full('fts');

  const TextSearchType(this.value);

  /// The PostgREST operator string for this search type.
  final String value;
}
