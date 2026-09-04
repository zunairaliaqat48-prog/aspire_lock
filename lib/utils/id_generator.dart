import 'dart:math';

/// Generates a reasonably-unique ID using timestamp + random suffix.
/// Avoids needing an extra package (like `uuid`) for simple local use.
String generateId() {
  final timestamp = DateTime.now().microsecondsSinceEpoch;
  final rand = Random().nextInt(999999);
  return '$timestamp-$rand';
}
