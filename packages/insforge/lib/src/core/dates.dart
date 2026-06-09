// packages/insforge_core/lib/src/dates.dart

/// Parses an InsForge/Postgres timestamp into a UTC [DateTime].
///
/// Handles ISO8601 (with or without fractional seconds / `Z`) and date-only
/// `yyyy-MM-dd` values. Returns null for null, empty, or unparseable input.
DateTime? parseInsforgeDate(String? value) {
  if (value == null || value.isEmpty) return null;
  final parsed = DateTime.tryParse(value);
  return parsed?.toUtc();
}
