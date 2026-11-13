/// One WireGuard outbound as the Core sees it. Handshake and reset stamps are
/// milliseconds since the epoch, so zero means "never".
class WireGuardStatus {
  const WireGuardStatus({
    required this.name,
    required this.initialized,
    required this.initError,
    required this.lastHandshake,
    required this.failStreak,
    required this.gaveUp,
    required this.lastReset,
    required this.endpoint,
  });

  factory WireGuardStatus.fromJson(Map<String, Object?> json) {
    final lastHandshake = _stamp(json['lastHandshake']);
    final lastReset = _stamp(json['lastReset']);
    return WireGuardStatus(
      name: json['name'] as String? ?? '',
      initialized: json['initialized'] as bool? ?? false,
      initError: json['initError'] as String? ?? '',
      lastHandshake: lastHandshake,
      failStreak: (json['failStreak'] as num?)?.toInt() ?? 0,
      gaveUp: json['gaveUp'] as bool? ?? false,
      lastReset: lastReset,
      endpoint: json['endpoint'] as String? ?? '',
    );
  }

  final String name;
  final bool initialized;
  final String initError;
  final DateTime? lastHandshake;
  final int failStreak;
  final bool gaveUp;
  final DateTime? lastReset;
  final String endpoint;

  bool get healthy => initialized && initError.isEmpty && !gaveUp;

  static DateTime? _stamp(Object? value) {
    final millis = (value as num?)?.toInt() ?? 0;
    if (millis <= 0) return null;
    return DateTime.fromMillisecondsSinceEpoch(millis);
  }
}
