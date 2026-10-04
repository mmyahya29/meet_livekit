import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:meet_livekit/meet_livekit.dart';

void main() {
  group('MeetRetryPolicy.shouldRetry', () {
    const policy = MeetRetryPolicy(maxAttempts: 3);

    test('stops once the attempt budget is spent', () {
      const failure = MeetFailure(
        kind: MeetFailureKind.network,
        message: 'offline',
      );

      expect(
        policy.shouldRetry(
          attempt: 1,
          failure: failure,
          canRefreshToken: false,
        ),
        isTrue,
      );
      expect(
        policy.shouldRetry(
          attempt: 2,
          failure: failure,
          canRefreshToken: false,
        ),
        isTrue,
      );
      // Third attempt is the last one, so no fourth.
      expect(
        policy.shouldRetry(
          attempt: 3,
          failure: failure,
          canRefreshToken: false,
        ),
        isFalse,
      );
    });

    test('maxAttempts of 1 disables retrying entirely', () {
      const failure = MeetFailure(
        kind: MeetFailureKind.network,
        message: 'offline',
      );

      expect(
        MeetRetryPolicy.none.shouldRetry(
          attempt: 1,
          failure: failure,
          canRefreshToken: true,
        ),
        isFalse,
      );
    });

    test('auth failure is terminal unless a token refresh is possible', () {
      const authFailure = MeetFailure(
        kind: MeetFailureKind.auth,
        message: 'token rejected',
      );

      // A static token cannot produce a different one, so retrying is a
      // guaranteed 401 and must not consume the budget.
      expect(
        policy.shouldRetry(
          attempt: 1,
          failure: authFailure,
          canRefreshToken: false,
        ),
        isFalse,
      );
      expect(
        policy.shouldRetry(
          attempt: 1,
          failure: authFailure,
          canRefreshToken: true,
        ),
        isTrue,
      );
    });

    test('ice failure never retries, even with a refreshable token', () {
      const iceFailure = MeetFailure(
        kind: MeetFailureKind.ice,
        message: 'no candidate pair',
      );

      expect(
        policy.shouldRetry(
          attempt: 1,
          failure: iceFailure,
          canRefreshToken: true,
        ),
        isFalse,
      );
    });

    test('media failure never retries', () {
      const mediaFailure = MeetFailure(
        kind: MeetFailureKind.media,
        message: 'camera denied',
      );

      expect(
        policy.shouldRetry(
          attempt: 1,
          failure: mediaFailure,
          canRefreshToken: true,
        ),
        isFalse,
      );
    });

    test('cancelled failure never retries', () {
      const cancelled = MeetFailure(
        kind: MeetFailureKind.cancelled,
        message: 'disposed',
      );

      expect(
        policy.shouldRetry(
          attempt: 1,
          failure: cancelled,
          canRefreshToken: true,
        ),
        isFalse,
      );
    });

    test('server and timeout failures do consume the budget', () {
      for (final kind in [MeetFailureKind.server, MeetFailureKind.timeout]) {
        expect(
          policy.shouldRetry(
            attempt: 1,
            failure: MeetFailure(kind: kind, message: 'x'),
            canRefreshToken: false,
          ),
          isTrue,
          reason: '$kind should be retryable',
        );
      }
    });
  });

  group('MeetRetryPolicy.backoffFor', () {
    test('grows exponentially when jitter is disabled', () {
      const policy = MeetRetryPolicy(
        initialBackoff: Duration(seconds: 2),
        multiplier: 2.0,
        maxBackoff: Duration(seconds: 60),
        jitter: 0.0,
      );
      final random = Random(1);

      expect(
        policy.backoffFor(nextAttempt: 1, random: random),
        const Duration(seconds: 2),
      );
      expect(
        policy.backoffFor(nextAttempt: 2, random: random),
        const Duration(seconds: 4),
      );
      expect(
        policy.backoffFor(nextAttempt: 3, random: random),
        const Duration(seconds: 8),
      );
      expect(
        policy.backoffFor(nextAttempt: 4, random: random),
        const Duration(seconds: 16),
      );
    });

    test('never exceeds maxBackoff', () {
      const policy = MeetRetryPolicy(
        initialBackoff: Duration(seconds: 2),
        multiplier: 3.0,
        maxBackoff: Duration(seconds: 10),
        jitter: 0.0,
      );
      final random = Random(7);

      expect(
        policy.backoffFor(nextAttempt: 9, random: random),
        const Duration(seconds: 10),
      );
    });

    test('a non-positive attempt is treated as the first', () {
      const policy = MeetRetryPolicy(
        initialBackoff: Duration(seconds: 3),
        maxBackoff: Duration(seconds: 30),
        jitter: 0.0,
      );

      expect(
        policy.backoffFor(nextAttempt: 0, random: Random(1)),
        const Duration(seconds: 3),
      );
    });

    test(
      'jitter stays within the configured band around the nominal delay',
      () {
        const policy = MeetRetryPolicy(
          initialBackoff: Duration(seconds: 10),
          multiplier: 1.0,
          maxBackoff: Duration(seconds: 60),
          jitter: 0.3,
        );

        final random = Random(42);
        for (var i = 0; i < 300; i++) {
          final delay = policy.backoffFor(nextAttempt: 1, random: random);
          expect(delay.inMilliseconds, greaterThanOrEqualTo(7000));
          expect(delay.inMilliseconds, lessThanOrEqualTo(13000));
        }
      },
    );

    test('jitter cannot push the delay past maxBackoff', () {
      const policy = MeetRetryPolicy(
        initialBackoff: Duration(seconds: 10),
        multiplier: 4.0,
        maxBackoff: Duration(seconds: 10),
        jitter: 1.0,
      );

      final random = Random(3);
      for (var i = 0; i < 200; i++) {
        final delay = policy.backoffFor(nextAttempt: 3, random: random);
        expect(delay.inMilliseconds, lessThanOrEqualTo(10000));
        expect(delay.inMilliseconds, greaterThanOrEqualTo(0));
      }
    });

    test('is deterministic for a given seed', () {
      const policy = MeetRetryPolicy(jitter: 0.5);

      expect(
        policy.backoffFor(nextAttempt: 2, random: Random(99)),
        policy.backoffFor(nextAttempt: 2, random: Random(99)),
      );
    });

    test(
      'actually varies across seeds, so clients do not retry in lockstep',
      () {
        const policy = MeetRetryPolicy(
          initialBackoff: Duration(seconds: 10),
          multiplier: 1.0,
          maxBackoff: Duration(seconds: 60),
          jitter: 0.5,
        );

        final samples = <int>{
          for (var seed = 0; seed < 20; seed++)
            policy
                .backoffFor(nextAttempt: 1, random: Random(seed))
                .inMilliseconds,
        };

        expect(samples.length, greaterThan(1));
      },
    );
  });

  group('MeetRetryPolicy invariants', () {
    test('rejects an attempt budget below 1', () {
      expect(
        () => MeetRetryPolicy(maxAttempts: 0),
        throwsA(isA<AssertionError>()),
      );
    });

    test('rejects a shrinking multiplier', () {
      expect(
        () => MeetRetryPolicy(multiplier: 0.5),
        throwsA(isA<AssertionError>()),
      );
    });

    test('rejects out-of-range jitter', () {
      expect(
        () => MeetRetryPolicy(jitter: 1.5),
        throwsA(isA<AssertionError>()),
      );
      expect(
        () => MeetRetryPolicy(jitter: -0.1),
        throwsA(isA<AssertionError>()),
      );
    });
  });
}
