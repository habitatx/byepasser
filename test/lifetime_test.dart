import 'package:byepasser/utils/lifetime.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('formats Byepasser lifetimes clearly', () {
    expect(formatLifetime(5), '5 min');
    expect(formatLifetime(60), '1 hr');
    expect(formatLifetime(10080), '7 days');
    expect(formatLifetime(43200), '30 days');
  });

  test('detects notes that are dying soon', () {
    final now = DateTime(2026, 1, 1, 12);
    expect(isDyingSoon(now.add(const Duration(hours: 2)), now), isTrue);
    expect(isDyingSoon(now.add(const Duration(days: 2)), now), isFalse);
  });
}
