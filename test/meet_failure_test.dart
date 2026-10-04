import 'package:flutter_test/flutter_test.dart';
import 'package:livekit_client/livekit_client.dart';
import 'package:meet_livekit/meet_livekit.dart';

// `dart:async` is deliberately not imported: livekit_client exports its own
// `TimeoutException`, which would become ambiguous with the core one.
void main() {
  group('MeetFailure.from — typed LiveKit exceptions', () {
    test('401 is classified as auth and is not retryable', () {
      final failure = MeetFailure.from(
        ConnectException(
          'token rejected',
          reason: ConnectionErrorReason.NotAllowed,
          statusCode: 401,
        ),
      );

      expect(failure.kind, MeetFailureKind.auth);
      expect(failure.statusCode, 401);
      expect(failure.isRetryable, isFalse);
    });

    test('403 is classified as auth', () {
      final failure = MeetFailure.from(
        ConnectException(
          'forbidden',
          reason: ConnectionErrorReason.NotAllowed,
          statusCode: 403,
        ),
      );

      expect(failure.kind, MeetFailureKind.auth);
    });

    test('NotAllowed without a status code is still auth', () {
      final failure = MeetFailure.from(
        ConnectException('nope', reason: ConnectionErrorReason.NotAllowed),
      );

      expect(failure.kind, MeetFailureKind.auth);
      expect(failure.statusCode, isNull);
    });

    test('ConnectException timeout maps to timeout and stays retryable', () {
      final failure = MeetFailure.from(
        ConnectException('slow', reason: ConnectionErrorReason.Timeout),
      );

      expect(failure.kind, MeetFailureKind.timeout);
      expect(failure.isRetryable, isTrue);
    });

    test(
      'ConnectException internal error maps to server and stays retryable',
      () {
        final failure = MeetFailure.from(
          ConnectException('boom', reason: ConnectionErrorReason.InternalError),
        );

        expect(failure.kind, MeetFailureKind.server);
        expect(failure.isRetryable, isTrue);
      },
    );

    test('MediaConnectException maps to ice and is NOT retryable', () {
      final failure = MeetFailure.from(MediaConnectException());

      expect(failure.kind, MeetFailureKind.ice);
      // Retrying a failed ICE gathering just repeats it. It needs a TURN or
      // network fix, not another attempt.
      expect(failure.isRetryable, isFalse);
      expect(failure.message, contains('TURN'));
    });

    test('TrackCreateException maps to media and is NOT retryable', () {
      final failure = MeetFailure.from(TrackCreateException('no camera'));

      expect(failure.kind, MeetFailureKind.media);
      expect(failure.isRetryable, isFalse);
    });

    test('NegotiationError maps to ice', () {
      final failure = MeetFailure.from(NegotiationError('sdp mismatch'));

      expect(failure.kind, MeetFailureKind.ice);
    });

    test('CertificatePinningException maps to auth', () {
      final failure = MeetFailure.from(
        CertificatePinningException(
          'pin mismatch',
          host: 'example.livekit.cloud',
        ),
      );

      expect(failure.kind, MeetFailureKind.auth);
    });

    test('DataPublishException maps to server', () {
      final failure = MeetFailure.from(DataPublishException('nope'));

      expect(failure.kind, MeetFailureKind.server);
    });

    test('a pre-classified MeetFailure passes through unchanged', () {
      const original = MeetFailure(
        kind: MeetFailureKind.cancelled,
        message: 'gone',
      );
      expect(MeetFailure.from(original), same(original));
    });
  });

  group('MeetFailure.from — string fallback (Flutter web)', () {
    test('401 in the text maps to auth, not media', () {
      // "denied" appears in many 401 messages; credentials must win because
      // treating an expired token as a camera problem hides the real cause.
      final failure = MeetFailure.from(
        Exception('WebSocket error 401 Unauthorized: permission denied'),
      );

      expect(failure.kind, MeetFailureKind.auth);
    });

    test('NotAllowedError maps to media', () {
      final failure = MeetFailure.from(
        Exception('NotAllowedError: Permission denied'),
      );

      expect(failure.kind, MeetFailureKind.media);
    });

    test('socket failures map to network', () {
      expect(
        MeetFailure.from(Exception('SocketException: connection refused')).kind,
        MeetFailureKind.network,
      );
      expect(
        MeetFailure.from(Exception('Failed to fetch')).kind,
        MeetFailureKind.network,
      );
    });

    test('ice candidate text maps to ice', () {
      expect(
        MeetFailure.from(Exception('no ice candidate pair available')).kind,
        MeetFailureKind.ice,
      );
    });

    test('unclassifiable input falls back to unknown and stays retryable', () {
      final failure = MeetFailure.from(Exception('something odd'));

      expect(failure.kind, MeetFailureKind.unknown);
      expect(failure.isRetryable, isTrue);
    });
  });
}
