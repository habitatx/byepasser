import 'package:intl/intl.dart';

/// Smart preset lifetimes (minutes).
const List<int> lifetimePresets = <int>[
  5, 15, 30,
  60, 4 * 60, 8 * 60,
  24 * 60, 3 * 24 * 60, 7 * 24 * 60, 14 * 24 * 60, 30 * 24 * 60,
];

String formatLifetime(int minutes) {
  if (minutes < 60) return '${minutes}m';
  final hours = minutes ~/ 60;
  if (hours < 24) return '${hours}h';
  final days = hours ~/ 24;
  return '${days}d';
}

String formatFullLifetime(int minutes) {
  if (minutes < 60) return '$minutes minutes';
  final h = minutes ~/ 60;
  final m = minutes % 60;
  if (h < 24) {
    return m == 0 ? '$h hours' : '$h hr $m min';
  }
  final d = h ~/ 24;
  return '$d days';
}

/// Human friendly remaining string. Shows seconds only when < 1 hour and flag is true.
String formatRemaining(Duration d, {required bool showSeconds}) {
  if (d.isNegative) return 'Expired';

  final days = d.inDays;
  final hours = d.inHours.remainder(24);
  final minutes = d.inMinutes.remainder(60);
  final seconds = d.inSeconds.remainder(60);

  if (days > 0) {
    if (hours > 0) return '${days}d ${hours}h';
    return '${days}d';
  }
  if (hours > 0) {
    if (minutes > 0) return '${hours}h ${minutes}m';
    return '${hours}h';
  }
  if (minutes > 0) {
    if (showSeconds && d.inMinutes < 60) {
      return '${minutes}m ${seconds}s';
    }
    return '${minutes}m';
  }
  return '${seconds}s';
}

String formatExactExpiry(DateTime dt) {
  // e.g. "Jun 12 at 3:42 PM"
  return DateFormat('MMM d \'at\' h:mm a').format(dt);
}

int clampLifetime(int minutes) {
  return minutes.clamp(5, 30 * 24 * 60);
}

int clampSteamLifetime(int minutes) {
  return minutes.clamp(5, 30);
}

/// Simple local heuristics to suggest a good lifetime.
/// Feels "smart" / AI-assisted without any network or ML.
int suggestLifetimeMinutes(String body) {
  final text = body.trim().toLowerCase();
  if (text.isEmpty) return 60 * 24; // 1 day default

  final words = text.split(RegExp(r'\s+'));
  final length = text.length;

  // Very short thoughts or one-offs → short life
  if (length < 25 && words.length <= 5) {
    return 15; // 15 minutes
  }

  // Questions, reminders, "remember", "todo" → medium term
  if (text.contains('?') ||
      text.contains('remind') ||
      text.contains('remember') ||
      text.contains('todo') ||
      text.contains('later')) {
    return 60 * 24 * 3; // 3 days
  }

  // Ideas, thoughts, "what if", creative stuff → a few days
  if (text.contains('idea') ||
      text.contains('thought') ||
      text.contains('what if') ||
      text.contains('maybe')) {
    return 60 * 24 * 2; // 2 days
  }

  // Long notes or journaling feel → week+
  if (length > 350 || words.length > 60) {
    return 60 * 24 * 7; // 7 days
  }

  // Default calm window
  return 60 * 24 * 2; // 2 days
}

String getSuggestionReason(String body) {
  final text = body.trim().toLowerCase();
  if (text.isEmpty) return 'Balanced default';

  if (text.length < 25) return 'Short & sweet';
  if (text.contains('?')) return 'Question — keep it a bit';
  if (text.contains('remind') || text.contains('remember')) return 'Reminder';
  if (text.contains('idea') || text.contains('thought')) return 'Creative thought';
  if (text.length > 350) return 'Long note — give it time';
  return 'Fits the vibe';
}
