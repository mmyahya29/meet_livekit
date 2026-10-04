import 'dart:async';
import 'dart:math';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:livekit_client/livekit_client.dart';

import '../models/meet_failure.dart';
import '../models/meet_retry_policy.dart';
import '../models/meet_token_source.dart';

/// Default room options, hardened for real-world networks.
///
/// The one non-obvious change is [VideoPublishOptions.backupVideoCodec].
/// `livekit_client` defaults it to the *same* codec as the primary, and only
/// engages the backup when the two differ — so leaving it alone meant there
/// was no fallback codec at all. Devices that only software-decode VP8 showed
/// black tiles with working audio, which reads as "connected but no video".
const meetDefaultRoomOptions = RoomOptions(
  adaptiveStream: true,
  dynacast: true,
  defaultCameraCaptureOptions: CameraCaptureOptions(
    params: VideoParametersPresets.h720_169,
    maxFrameRate: 30,
  ),
  defaultAudioCaptureOptions: AudioCaptureOptions(
    echoCancellation: true,
    noiseSuppression: true,
    autoGainControl: true,
  ),
  defaultVideoPublishOptions: VideoPublishOptions(
    videoCodec: 'vp8',
    simulcast: true,
    degradationPreference: DegradationPreference.maintainFramerate,
    backupVideoCodec: BackupVideoCodec(
      enabled: true,
      codec: 'h264',
      simulcast: false,
    ),
  ),
  defaultAudioPublishOptions: AudioPublishOptions(dtx: true, red: true),
);

/// Default connect options with relaxed deadlines.
///
/// This is the highest-impact fix in the package. `livekit_client` defaults
/// `Timeouts.connection` to 10 seconds, and that single value is the deadline
/// the SDK applies to the *entire* ICE phase — TURN allocation, relay
/// candidate gathering, DTLS handshake and all. Ten seconds is comfortable on a
/// fast wired link and routinely exceeded on mobile data or any path that has
/// to fall back to TURN, at which point the SDK throws `MediaConnectException`
/// ("please check your network for ice connectivity").
///
/// That failure is network-dependent, not code-dependent, which is exactly the
/// reported pattern: fine for some users, never for others, on the same build.
final meetDefaultConnectOptions = ConnectOptions(
  autoSubscribe: true,
  timeouts: const Timeouts(
    connection: Duration(seconds: 30),
    peerConnection: Duration(seconds: 30),
    iceRestart: Duration(seconds: 20),
    publish: Duration(seconds: 15),
    subscribe: Duration(seconds: 15),
    debounce: Duration(milliseconds: 20),
  ),
);

/// Result of enabling the initial microphone and camera.
class MeetMediaOutcome {
  final bool microphoneEnabled;
  final bool cameraEnabled;

  /// Set when the camera could not be started. The call stays up and audio
  /// continues; only video is missing.
  final MeetFailure? cameraFailure;

  const MeetMediaOutcome({
    required this.microphoneEnabled,
    required this.cameraEnabled,
    this.cameraFailure,
  });

  /// The call is usable even with no camera.
  bool get hasAudio => microphoneEnabled;
}

// ─── ROOM ─────────────────────────────────────────────────────────────────────
// The connected LiveKit Room, kept alive while a call is active.
//
// The Room is deliberately NOT rebuilt between retry attempts. `Engine.connect`
// resets its own closed flag on entry, so a Room survives a failed attempt and
// can simply be connected again. The previous implementation tore the Room
// down on every single connect call, which is what made each retry expensive
// enough that concurrent retries starved one another.
final meetLiveKitRoomProvider = NotifierProvider<MeetLiveKitRoomNotifier, Room>(
  MeetLiveKitRoomNotifier.new,
);

class MeetLiveKitRoomNotifier extends Notifier<Room> {
  RoomOptions _roomOptions = meetDefaultRoomOptions;
  ConnectOptions _connectOptions = meetDefaultConnectOptions;
  MeetRetryPolicy _retryPolicy = const MeetRetryPolicy();
  final Random _random = Random();

  /// Single-flight guard. Every entry point funnels through this so that at
  /// most one connect attempt exists at a time; later callers await the one
  /// already in progress instead of starting a competing attempt.
  Future<void>? _inFlightConnect;
  Future<void>? _inFlightDisconnect;

  /// True once a connect gave up terminally. Guards the auto-reconnect path so
  /// a failure can never restart itself.
  bool _gaveUp = false;

  /// Set when the Room has been disposed and must be rebuilt before use.
  bool _needsFreshRoom = false;

  /// Mirrors the Room held in provider state.
  ///
  /// Riverpod forbids touching provider state inside a lifecycle callback, so
  /// `ref.onDispose` cannot read `state`. This plain field carries the current
  /// instance out to teardown instead.
  Room? _currentRoom;

  /// True after `ref.onDispose` has run; aborts anything still in flight.
  bool _shutDown = false;

  @override
  Room build() {
    _roomOptions = meetDefaultRoomOptions;
    _connectOptions = meetDefaultConnectOptions;
    _retryPolicy = const MeetRetryPolicy();
    _gaveUp = false;
    _needsFreshRoom = false;
    _shutDown = false;
    _inFlightConnect = null;
    _inFlightDisconnect = null;
    _currentRoom = null;

    ref.onDispose(() {
      _shutDown = true;
      final room = _currentRoom;
      _currentRoom = null;
      try {
        room?.dispose();
      } catch (_) {
        // Nothing useful to do while the provider is being torn down.
      }
    });

    return _adoptRoom(Room(roomOptions: _roomOptions));
  }

  /// Overrides the hardened defaults. Call before [connect].
  void configure({
    RoomOptions? roomOptions,
    ConnectOptions? connectOptions,
    MeetRetryPolicy? retryPolicy,
  }) {
    if (roomOptions != null) _roomOptions = roomOptions;
    if (connectOptions != null) _connectOptions = connectOptions;
    if (retryPolicy != null) _retryPolicy = retryPolicy;
  }

  MeetRetryPolicy get retryPolicy => _retryPolicy;

  /// Whether the last connect attempt failed terminally.
  bool get hasGaveUp => _gaveUp;

  /// Clears the terminal-failure latch so a host-initiated retry can proceed.
  void resetGaveUp() => _gaveUp = false;

  Room _ensureRoom() {
    if (_needsFreshRoom) {
      _allocateRoom();
    }
    return state;
  }

  /// Installs [room] as the current room and as provider state.
  Room _adoptRoom(Room room) {
    _currentRoom = room;
    return room;
  }

  void _allocateRoom() {
    final previous = _currentRoom;
    try {
      previous?.dispose();
    } catch (_) {
      // A Room that already tore itself down needs no further cleanup.
    }
    _currentRoom = null;
    state = _adoptRoom(Room(roomOptions: _roomOptions));
    _needsFreshRoom = false;
  }

  /// Connects to the LiveKit room, retrying according to [MeetRetryPolicy].
  ///
  /// Concurrent callers coalesce onto a single attempt. Throws a [MeetFailure]
  /// once the budget is exhausted or the failure is terminal — it never loops
  /// indefinitely, and never leaves the caller without an answer.
  Future<void> connect({
    required String serverUrl,
    required MeetTokenSource tokenSource,
  }) {
    final existing = _inFlightConnect;
    if (existing != null) return existing;

    _gaveUp = false;

    final attempt = _runConnect(serverUrl, tokenSource);
    _inFlightConnect = attempt;

    return attempt.whenComplete(() {
      if (identical(_inFlightConnect, attempt)) {
        _inFlightConnect = null;
      }
    });
  }

  Future<void> _runConnect(
    String serverUrl,
    MeetTokenSource tokenSource,
  ) async {
    var attempt = 0;
    var tokenRefreshed = false;

    while (true) {
      if (_shutDown) {
        throw const MeetFailure(
          kind: MeetFailureKind.cancelled,
          message: 'Connect abandoned: the room was disposed.',
        );
      }

      attempt++;

      try {
        final room = _ensureRoom();
        final token = await tokenSource.obtain(refresh: tokenRefreshed);

        if (_shutDown) {
          throw const MeetFailure(
            kind: MeetFailureKind.cancelled,
            message: 'Connect abandoned: the room was disposed.',
          );
        }

        await room.connect(serverUrl, token, connectOptions: _connectOptions);

        // Success. Clearing the latch here is what lets the auto-reconnect
        // path resume after a genuine network drop.
        _gaveUp = false;
        return;
      } catch (error) {
        final failure = MeetFailure.from(error);

        if (_shutDown || failure.kind == MeetFailureKind.cancelled) {
          _gaveUp = false;
          throw failure;
        }

        // A refresh is only worth attempting once per connect session.
        final canRefresh =
            tokenSource.canRefresh &&
            !tokenRefreshed &&
            failure.kind == MeetFailureKind.auth;

        final shouldRetry = _retryPolicy.shouldRetry(
          attempt: attempt,
          failure: failure,
          canRefreshToken: canRefresh,
        );

        if (!shouldRetry) {
          _gaveUp = true;
          // Release the engine so a terminal failure does not leave a camera
          // or microphone locked.
          _needsFreshRoom = true;
          _allocateRoom();
          throw failure;
        }

        if (canRefresh) tokenRefreshed = true;

        final delay = _retryPolicy.backoffFor(
          nextAttempt: attempt + 1,
          random: _random,
        );
        await Future<void>.delayed(delay);
      }
    }
  }

  /// Starts the microphone, then the camera, after the room is connected.
  ///
  /// Deliberately separate from [connect]. Enabling capture inside the connect
  /// path meant a single denied camera permission threw out of `connect()` and
  /// took the whole call down with it; here the audio path is established
  /// first and a camera failure is reported without tearing anything down.
  Future<MeetMediaOutcome> enableInitialMedia({
    bool camera = true,
    bool microphone = true,
  }) async {
    final participant = state.localParticipant;
    if (participant == null) {
      return const MeetMediaOutcome(
        microphoneEnabled: false,
        cameraEnabled: false,
      );
    }

    var micEnabled = false;
    if (microphone) {
      try {
        micEnabled = (await participant.setMicrophoneEnabled(true)) != null;
      } catch (error) {
        debugLog('meet_livekit: microphone failed to start — $error');
      }
    }

    // Attempted independently of the microphone. Tying the camera to
    // `micEnabled` meant `startWithMicrophone: false` silently produced a
    // video-less call, and a mic denial blocked video that was still fine.
    // A camera failure can no longer take the call down because it is caught
    // here rather than thrown out of the connect path.
    var camEnabled = false;
    MeetFailure? camFailure;
    if (camera) {
      try {
        camEnabled = (await participant.setCameraEnabled(true)) != null;
      } catch (error) {
        camFailure = MeetFailure.from(error);
        debugLog(
          'meet_livekit: camera failed to start, continuing without video — $camFailure',
        );
      }
    }

    return MeetMediaOutcome(
      microphoneEnabled: micEnabled,
      cameraEnabled: camEnabled,
      cameraFailure: camFailure,
    );
  }

  /// Disconnects cleanly, releasing all media resources.
  ///
  /// Guarded the same way as [connect] so a teardown racing a reconnect cannot
  /// interleave two engine operations.
  Future<void> disconnect() {
    final existing = _inFlightDisconnect;
    if (existing != null) return existing;

    final attempt = _disconnect();
    _inFlightDisconnect = attempt;

    return attempt.whenComplete(() {
      if (identical(_inFlightDisconnect, attempt)) {
        _inFlightDisconnect = null;
      }
    });
  }

  Future<void> _disconnect() async {
    try {
      final participant = state.localParticipant;
      if (participant != null) {
        // Release hardware locks before dropping the signalling connection.
        await participant.setMicrophoneEnabled(false);
        await participant.setCameraEnabled(false);
        await participant.setScreenShareEnabled(false);
      }
    } catch (error) {
      debugLog('meet_livekit: error while releasing media — $error');
    }

    try {
      await state.disconnect().timeout(const Duration(seconds: 3));
    } catch (error) {
      debugLog('meet_livekit: error while disconnecting — $error');
    } finally {
      // Destroying the engine is what prevents ghost audio from surviving the
      // call. The provider is left holding a fresh, valid Room.
      _needsFreshRoom = false;
      _allocateRoom();
    }
  }
}

/// Emits a diagnostic line.
///
/// Route this at the host's logger to get the connectionState / failure-kind
/// trail that makes production connection problems diagnosable at all. It was
/// previously impossible to tell an expired token from an ICE timeout from a
/// denied camera, because every failure was reduced to a substring match.
void debugLog(String message) {
  // ignore: avoid_print
  print(message);
}

// ---------------------------------------------------------------------------
// END-CALL LATCH
// ---------------------------------------------------------------------------
// Set by the host app to end a call *intentionally* — for example when the host
// runs its own countdown outside this package and that countdown expires.
//
// This exists because MeetRoomScreen treats any unexpected `disconnected` room
// event as a network drop and auto-reconnects (see `_onRoomEvent`). Disconnecting
// the [Room] directly bypasses the private `_isManuallyEnding` guard, so the room
// silently comes back and the call restarts. Latching the intent here lets the
// host end the call through this package's own graceful path — which still emits
// a MeetingSummary to `onLeaveCall` — while keeping reconnect-on-network-drop
// working for genuine connectivity loss.
//
// The flag is one-shot: MeetRoomScreen clears it as soon as it consumes it, and
// also clears it in `dispose()`, so a stale `true` can never end the next call.
class MeetEndCallRequester extends Notifier<bool> {
  @override
  bool build() => false;

  void request() => state = true;

  void clear() => state = false;
}

final meetEndCallRequestedProvider =
    NotifierProvider<MeetEndCallRequester, bool>(MeetEndCallRequester.new);

// ─── CALL STATE ───────────────────────────────────────────────────────────────
enum MeetCallState {
  idle,
  connecting,
  connected,
  disconnected,
  error,
  permissionsDenied,
}

final meetCallStateProvider =
    NotifierProvider<MeetCallStateNotifier, MeetCallState>(
      MeetCallStateNotifier.new,
    );

class MeetCallStateNotifier extends Notifier<MeetCallState> {
  @override
  MeetCallState build() => MeetCallState.idle;

  @override
  set state(MeetCallState value) => super.state = value;
}

// ─── CAMERA/MIC TOGGLES ───────────────────────────────────────────────────────
final meetIsCameraEnabledProvider =
    NotifierProvider<MeetCameraEnabledNotifier, bool>(
      MeetCameraEnabledNotifier.new,
    );

class MeetCameraEnabledNotifier extends Notifier<bool> {
  @override
  bool build() => true;

  @override
  set state(bool value) => super.state = value;
}

final meetIsMicEnabledProvider = NotifierProvider<MeetMicEnabledNotifier, bool>(
  MeetMicEnabledNotifier.new,
);

class MeetMicEnabledNotifier extends Notifier<bool> {
  @override
  bool build() => true;

  @override
  set state(bool value) => super.state = value;
}

final meetIsScreenShareEnabledProvider =
    NotifierProvider<MeetScreenShareEnabledNotifier, bool>(
      MeetScreenShareEnabledNotifier.new,
    );

class MeetScreenShareEnabledNotifier extends Notifier<bool> {
  @override
  bool build() => false;

  @override
  set state(bool value) => super.state = value;
}

final meetIsTileViewEnabledProvider =
    NotifierProvider<MeetTileViewEnabledNotifier, bool>(
      MeetTileViewEnabledNotifier.new,
    );

class MeetTileViewEnabledNotifier extends Notifier<bool> {
  @override
  bool build() => true;

  @override
  set state(bool value) => super.state = value;
}

final meetIsChatOpenProvider = NotifierProvider<MeetChatOpenNotifier, bool>(
  MeetChatOpenNotifier.new,
);

class MeetChatOpenNotifier extends Notifier<bool> {
  @override
  bool build() => false;

  @override
  set state(bool value) => super.state = value;
}

/// Clears every call-scoped UI flag back to its default.
///
/// These providers are application-scoped singletons and are not
/// `autoDispose`, so without this a second call inherited the first call's
/// chat-open / grid-view / camera state. The camera and mic booleans in
/// particular could disagree with the real hardware, leaving the UI showing a
/// muted microphone that was actually publishing.
void resetCallScopedState(WidgetRef ref) {
  ref.read(meetIsChatOpenProvider.notifier).state = false;
  ref.read(meetIsTileViewEnabledProvider.notifier).state = true;
  ref.read(meetIsScreenShareEnabledProvider.notifier).state = false;
  ref.read(meetIsCameraEnabledProvider.notifier).state = true;
  ref.read(meetIsMicEnabledProvider.notifier).state = true;
}
