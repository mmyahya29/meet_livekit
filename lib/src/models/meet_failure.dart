import 'package:livekit_client/livekit_client.dart';

/// Why a connection attempt failed.
///
/// This exists because a single `catch (e)` collapsed every failure into a
/// lowercase substring test, which made an expired token indistinguishable
/// from an ICE timeout from a denied camera in production logs. Hosts could
/// not tell which of those they were looking at, so none of them could be
/// diagnosed or fixed from the field.
enum MeetFailureKind {
  /// The server rejected our credentials (401/403, expired or malformed token).
  auth,

  /// ICE never produced a viable candidate pair. Almost always a network
  /// topology problem — symmetric NAT, blocked UDP, or a missing/unreachable
  /// TURN server. This presents to the user as "connected but no media".
  ice,

  /// The OS refused camera or microphone access.
  media,

  /// Signaling could not be reached at all.
  network,

  /// The server was reached but failed to answer (5xx, internal error).
  server,

  /// An operation exceeded its deadline.
  timeout,

  /// A connect attempt was abandoned because the screen was disposed or the
  /// host explicitly ended the call.
  cancelled,

  /// Not classifiable. Treated as retryable because that is the safer default.
  unknown,
}

extension MeetFailureKindX on MeetFailureKind {
  /// Whether retrying the same connect could plausibly succeed without any
  /// change to credentials, permissions, or network.
  ///
  /// [auth] and [ice] are deliberately **not** retryable here. Retrying an
  /// expired token just gets another 401; retrying a failed ICE gathering just
  /// repeats it. Both need an intervention first — a token refresh or a TURN
  /// fix — so the caller surfaces them instead of burning a retry budget.
  bool get isRetryable => switch (this) {
    MeetFailureKind.network ||
    MeetFailureKind.server ||
    MeetFailureKind.timeout ||
    MeetFailureKind.unknown => true,
    MeetFailureKind.auth ||
    MeetFailureKind.ice ||
    MeetFailureKind.media ||
    MeetFailureKind.cancelled => false,
  };
}

/// A classified connection failure.
class MeetFailure implements Exception {
  final MeetFailureKind kind;
  final String message;
  final int? statusCode;
  final Object? cause;

  const MeetFailure({
    required this.kind,
    required this.message,
    this.statusCode,
    this.cause,
  });

  bool get isRetryable => kind.isRetryable;

  /// Classifies any thrown object into a [MeetFailure].
  ///
  /// Typed [LiveKitException]s are matched first because they are reliable on
  /// every platform. The string fallback exists for Flutter web, where a JS
  /// exception can reach the Dart boundary without its original type.
  factory MeetFailure.from(Object error) {
    if (error is MeetFailure) return error;

    final failure = _fromTyped(error);
    if (failure != null) return failure;
    return _fromText(error);
  }

  static MeetFailure? _fromTyped(Object error) {
    if (error is ConnectException) {
      // NotAllowed carries a 4xx, so credentials are the problem. Checked
      // before `reason` because NotAllowed does not always mean an HTTP code
      // is present on the exception.
      if (error.statusCode == 401 || error.statusCode == 403) {
        return MeetFailure(
          kind: MeetFailureKind.auth,
          message:
              'LiveKit rejected the access token (HTTP ${error.statusCode}). '
              'The token is expired or malformed.',
          statusCode: error.statusCode,
          cause: error,
        );
      }
      return switch (error.reason) {
        ConnectionErrorReason.NotAllowed => MeetFailure(
          kind: MeetFailureKind.auth,
          message: error.message,
          statusCode: error.statusCode == 0 ? null : error.statusCode,
          cause: error,
        ),
        ConnectionErrorReason.Timeout => MeetFailure(
          kind: MeetFailureKind.timeout,
          message: error.message,
          cause: error,
        ),
        ConnectionErrorReason.InternalError => MeetFailure(
          kind: MeetFailureKind.server,
          message: error.message,
          cause: error,
        ),
      };
    }

    // "Ice connection failed" — the SFU told us it could not reach the client,
    // or vice versa. This is the TURN/NAT signature.
    if (error is MediaConnectException) {
      return MeetFailure(
        kind: MeetFailureKind.ice,
        message:
            '${error.message}. No viable ICE candidate pair was found. '
            'This usually means UDP is blocked or no TURN server is reachable.',
        cause: error,
      );
    }

    if (error is TimeoutException) {
      return MeetFailure(
        kind: MeetFailureKind.timeout,
        message: error.message,
        cause: error,
      );
    }

    // Raised when the OS refuses to hand over camera/mic.
    if (error is TrackCreateException) {
      return MeetFailure(
        kind: MeetFailureKind.media,
        message: '${error.message}. Camera or microphone access was denied.',
        cause: error,
      );
    }

    // Codec negotiation failing is an SDP-level problem, closest to ICE.
    if (error is NegotiationError) {
      return MeetFailure(
        kind: MeetFailureKind.ice,
        message: error.message,
        cause: error,
      );
    }

    if (error is CertificatePinningException) {
      return MeetFailure(
        kind: MeetFailureKind.auth,
        message: error.message,
        cause: error,
      );
    }

    if (error is DataPublishException || error is TrackPublishException) {
      return MeetFailure(
        kind: MeetFailureKind.server,
        message: error.toString(),
        cause: error,
      );
    }

    return null;
  }

  static MeetFailure _fromText(Object error) {
    final text = error.toString();
    final lower = text.toLowerCase();

    // Order matters. `notallowederror` also contains "permission", and a
    // 401 message can contain "denied", so credentials are tested first.
    if (lower.contains('401') ||
        lower.contains('403') ||
        lower.contains('unauthorized') ||
        lower.contains('forbidden') ||
        (lower.contains('token') && lower.contains('expired'))) {
      return MeetFailure(
        kind: MeetFailureKind.auth,
        message: text,
        cause: error,
      );
    }

    if (lower.contains('notallowed') ||
        lower.contains('permission') ||
        lower.contains('denied')) {
      return MeetFailure(
        kind: MeetFailureKind.media,
        message: text,
        cause: error,
      );
    }

    if (lower.contains('ice') || lower.contains('candidate')) {
      return MeetFailure(
        kind: MeetFailureKind.ice,
        message: text,
        cause: error,
      );
    }

    if (lower.contains('timeout') || lower.contains('timed out')) {
      return MeetFailure(
        kind: MeetFailureKind.timeout,
        message: text,
        cause: error,
      );
    }

    if (lower.contains('socket') ||
        lower.contains('network') ||
        lower.contains('unreachable') ||
        lower.contains('refused') ||
        lower.contains('host lookup') ||
        lower.contains('failed to fetch')) {
      return MeetFailure(
        kind: MeetFailureKind.network,
        message: text,
        cause: error,
      );
    }

    return MeetFailure(
      kind: MeetFailureKind.unknown,
      message: text,
      cause: error,
    );
  }

  @override
  String toString() =>
      'MeetFailure(${kind.name}${statusCode == null ? '' : ' $statusCode'}): $message';
}
