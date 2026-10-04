import 'package:livekit_client/livekit_client.dart';

/// Supplies the LiveKit access token used to join a room.
///
/// A plain token string breaks down for any call that outlives the token's
/// lifetime: the SDK re-presents the same JWT on every reconnect, gets a 401,
/// and the client has no way to tell that apart from a network drop, so it
/// reconnects and is rejected again. Supplying a source that can mint a fresh
/// token lets the package recover instead of looping.
abstract class MeetTokenSource {
  const MeetTokenSource();

  /// Returns a token to connect with.
  ///
  /// [refresh] is true only after the previous token was rejected as invalid,
  /// so implementations can serve a cached token cheaply and fetch a new one
  /// exactly when it is needed.
  Future<String> obtain({required bool refresh});

  /// Whether [obtain] can produce a *different* token when asked to refresh.
  ///
  /// A static token cannot, so auth failures are treated as terminal rather
  /// than burning the retry budget on a guaranteed 401.
  bool get canRefresh => true;
}

/// The original behaviour: one fixed token, no refresh capability.
class MeetStaticTokenSource extends MeetTokenSource {
  final String token;

  const MeetStaticTokenSource(this.token);

  @override
  bool get canRefresh => false;

  @override
  Future<String> obtain({required bool refresh}) async => token;
}

/// Delegates to a host callback so the host can use whatever token service it
/// already has.
///
/// ```dart
/// MeetCallbackTokenSource((refresh) async {
///   if (!refresh) return cachedToken;
///   return (await myAuthService.freshToken()).accessToken;
/// })
/// ```
class MeetCallbackTokenSource extends MeetTokenSource {
  final Future<String> Function(bool refresh) callback;

  const MeetCallbackTokenSource(this.callback);

  @override
  Future<String> obtain({required bool refresh}) => callback(refresh);
}

/// Adapts a LiveKit [TokenSourceFixed] to a [MeetTokenSource].
///
/// Each [obtain] issues a fresh fetch, so this should be wrapped in
/// `livekit_client`'s `CachingTokenSource` if the host wants to avoid a network
/// round trip on every reconnect.
class MeetLiveKitTokenSource extends MeetTokenSource {
  final TokenSourceFixed source;

  const MeetLiveKitTokenSource(this.source);

  @override
  Future<String> obtain({required bool refresh}) async {
    final response = await source.fetch();
    return response.participantToken;
  }
}
