import 'dart:math';

final _random = Random();

/// A short unique id: microsecond timestamp plus random suffix, both base 36.
/// Sorts roughly by creation time, which keeps session files tidy on disk.
String newId() {
  final t = DateTime.now().microsecondsSinceEpoch.toRadixString(36);
  final r = _random.nextInt(1 << 30).toRadixString(36).padLeft(6, '0');
  return '$t-$r';
}
