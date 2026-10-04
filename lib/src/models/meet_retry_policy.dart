import 'dart:math';

import 'meet_failure.dart';

/// How the package retries a failed connection.
///
/// The previous behaviour gave every call site its own `retries: 3` default,
/// which meant one network blip could fan out into roughly a dozen concurrent
/// connect attempts. Each one disposed and rebuilt the [Room], so the attempts
/// starved each other and the call failed *because* of the retry logic rather
/// than because of the network. A single shared policy replaces all of that.
class MeetRetryPolicy {
  /// Total attempts, counting the first one. `1` disables retrying.
  final int maxAttempts;

  /// Backoff before the first retry.
  final Duration initialBackoff;

  /// Ceiling for the exponential growth.
  final Duration maxBackoff;

  /// Growth factor applied per attempt.
  final double multiplier;

  /// Fraction of the computed delay to randomise, in `0.0`-`1.0`.
  ///
  /// Without jitter every client that loses connectivity at the same moment
  /// retries in lockstep and stampedes the SFU.
  final double jitter;

  const MeetRetryPolicy({
    this.maxAttempts = 3,
    this.initialBackoff = const Duration(seconds: 2),
    this.maxBackoff = const Duration(seconds: 20),
    this.multiplier = 2.0,
    this.jitter = 0.3,
  }) : assert(maxAttempts >= 1, 'maxAttempts must be at least 1'),
       assert(multiplier >= 1.0, 'multiplier must not shrink the delay'),
       assert(jitter >= 0.0 && jitter <= 1.0, 'jitter must be within 0.0-1.0');

  /// No retries at all.
  static const MeetRetryPolicy none = MeetRetryPolicy(
    maxAttempts: 1,
    initialBackoff: Duration.zero,
  );

  /// Whether another attempt should be made after [failure].
  ///
  /// A non-retryable failure stops immediately. An [MeetFailureKind.auth]
  /// failure is allowed one more attempt *only* when the host supplied a token
  /// provider, because a fresh token is exactly the intervention it needs.
  bool shouldRetry({
    required int attempt,
    required MeetFailure failure,
    required bool canRefreshToken,
  }) {
    if (attempt >= maxAttempts) return false;
    if (failure.kind == MeetFailureKind.cancelled) return false;
    if (failure.kind == MeetFailureKind.media) return false;
    if (failure.kind == MeetFailureKind.auth) return canRefreshToken;
    return failure.isRetryable;
  }

  /// Delay before attempt number [nextAttempt] (1-based; the first retry is 1).
  ///
  /// [random] is injectable so the jitter is deterministic under test.
  Duration backoffFor({required int nextAttempt, required Random random}) {
    if (nextAttempt < 1) nextAttempt = 1;

    var millis = initialBackoff.inMilliseconds.toDouble();
    for (var i = 1; i < nextAttempt; i++) {
      millis *= multiplier;
      if (millis >= maxBackoff.inMilliseconds) break;
    }

    final capped = millis.clamp(0.0, maxBackoff.inMilliseconds.toDouble());
    if (jitter == 0.0) {
      return Duration(milliseconds: capped.round());
    }

    // Symmetric jitter around the nominal delay, then clamp so a large jitter
    // can never push the delay past the configured ceiling.
    final spread = capped * jitter;
    final offset = (random.nextDouble() * 2 - 1) * spread;
    final jittered = (capped + offset).clamp(
      0.0,
      maxBackoff.inMilliseconds.toDouble(),
    );
    return Duration(milliseconds: jittered.round());
  }

  MeetRetryPolicy copyWith({
    int? maxAttempts,
    Duration? initialBackoff,
    Duration? maxBackoff,
    double? multiplier,
    double? jitter,
  }) {
    return MeetRetryPolicy(
      maxAttempts: maxAttempts ?? this.maxAttempts,
      initialBackoff: initialBackoff ?? this.initialBackoff,
      maxBackoff: maxBackoff ?? this.maxBackoff,
      multiplier: multiplier ?? this.multiplier,
      jitter: jitter ?? this.jitter,
    );
  }
}
