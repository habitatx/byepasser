import 'dart:math' as math;

const minLifetimeMinutes = 5;
const maxLifetimeMinutes = 43200;
const minSteamLifetimeMinutes = 5;
const maxSteamLifetimeMinutes = 30;

class LifetimePreset {
  const LifetimePreset(this.label, this.minutes);

  final String label;
  final int minutes;
}

const lifetimePresets = [
  LifetimePreset('5m', 5),
  LifetimePreset('15m', 15),
  LifetimePreset('30m', 30),
  LifetimePreset('1h', 60),
  LifetimePreset('4h', 240),
  LifetimePreset('8h', 480),
  LifetimePreset('1d', 1440),
  LifetimePreset('3d', 4320),
  LifetimePreset('7d', 10080),
  LifetimePreset('14d', 20160),
  LifetimePreset('30d', 43200),
];

const steamLifetimePresets = [
  LifetimePreset('5m', 5),
  LifetimePreset('10m', 10),
  LifetimePreset('15m', 15),
  LifetimePreset('20m', 20),
  LifetimePreset('30m', 30),
];

double minutesToSlider(int minutes, {required int min, required int max}) {
  final clamped = minutes.clamp(min, max);
  final logMin = math.log(min);
  final logMax = math.log(max);
  return ((math.log(clamped) - logMin) / (logMax - logMin)).clamp(0.0, 1.0);
}

int sliderToMinutes(double value, {required int min, required int max}) {
  final logMin = math.log(min);
  final logMax = math.log(max);
  return math.exp(logMin + value.clamp(0.0, 1.0) * (logMax - logMin)).round();
}

String formatLifetime(int minutes) {
  if (minutes < 60) {
    return '$minutes min';
  }
  if (minutes < 1440) {
    final hours = minutes ~/ 60;
    final remainder = minutes % 60;
    return remainder == 0 ? '$hours hr' : '$hours hr $remainder min';
  }
  final days = minutes ~/ 1440;
  final remainderHours = (minutes % 1440) ~/ 60;
  return remainderHours == 0 ? '$days days' : '$days days $remainderHours hr';
}

String formatCountdown(
  Duration duration, {
  required bool showSeconds,
  bool huge = false,
}) {
  if (duration.isNegative) {
    return huge ? '00:00' : 'expired';
  }

  final days = duration.inDays;
  final hours = duration.inHours.remainder(24);
  final minutes = duration.inMinutes.remainder(60);
  final seconds = duration.inSeconds.remainder(60);

  if (duration.inHours < 1 && showSeconds) {
    return '${minutes.toString().padLeft(2, '0')}:'
        '${seconds.toString().padLeft(2, '0')}';
  }
  if (days > 0) {
    return huge ? '${days}d ${hours}h' : '$days days $hours hr';
  }
  if (duration.inHours > 0) {
    return huge
        ? '${duration.inHours}h ${minutes}m'
        : '${duration.inHours} hr $minutes min';
  }
  return '$minutes min';
}

bool isDyingSoon(DateTime expiresAt, DateTime now) {
  final remaining = expiresAt.difference(now);
  return !remaining.isNegative && remaining <= const Duration(hours: 24);
}

double expiryProgress(DateTime createdAt, DateTime expiresAt, DateTime now) {
  final total = expiresAt.difference(createdAt).inSeconds;
  if (total <= 0) {
    return 1;
  }
  final elapsed = now.difference(createdAt).inSeconds.clamp(0, total);
  return elapsed / total;
}
