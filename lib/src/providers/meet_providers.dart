import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:livekit_client/livekit_client.dart';

// ─── ROOM — the LiveKit Room object, kept alive while call is active ───────────
// Holds the actual connected Room instance. Disposed when user leaves.
final meetLiveKitRoomProvider = NotifierProvider<MeetLiveKitRoomNotifier, Room>(MeetLiveKitRoomNotifier.new);

class MeetLiveKitRoomNotifier extends Notifier<Room> {
  @override
  Room build() {
    ref.onDispose(() {
      state.dispose();
    });
    return Room(
      roomOptions: const RoomOptions(
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
          simulcast: true,
          videoCodec: 'vp8',
        ),
        defaultAudioPublishOptions: AudioPublishOptions(
          dtx: true,
          red: true,
        ),
      ),
    );
  }

  /// Connects to a LiveKit room using a pre-fetched token.
  Future<void> connect({
    required String serverUrl,
    required String token,
  }) async {
    if (state.connectionState == ConnectionState.disconnected) {
      state.dispose();
      state = Room(
        roomOptions: const RoomOptions(
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
            simulcast: true,
            videoCodec: 'vp8',
          ),
          defaultAudioPublishOptions: AudioPublishOptions(
            dtx: true,
            red: true,
          ),
        ),
      );
    }

    try {
      await state.connect(
        serverUrl,
        token,
      );

      // Enable camera and microphone on join
      await state.localParticipant?.setCameraEnabled(true);
      await state.localParticipant?.setMicrophoneEnabled(true);
    } catch (e) {
      try {
        await state.disconnect();
      } catch (_) {}
      rethrow;
    }
  }

  /// Disconnects cleanly, releasing all media resources
  Future<void> disconnect() async {
    try {
      if (state.localParticipant != null) {
        // Forcefully release local hardware locks before dropping the WebSocket
        await state.localParticipant?.setMicrophoneEnabled(false);
        await state.localParticipant?.setCameraEnabled(false);
        await state.localParticipant?.setScreenShareEnabled(false);
      }
      // Put a timeout so we don't hang forever
      await state.disconnect().timeout(const Duration(seconds: 2));
    } catch (e) {
      // ignore: avoid_print
      print('Error disconnecting: $e');
    } finally {
      // Destroy the room engine to prevent any ghost audio from sticking around
      try {
        await state.dispose();
      } catch (_) {}
      
      // We must assign a new room so the provider remains in a valid state
      state = Room(
        roomOptions: const RoomOptions(
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
            simulcast: true,
            videoCodec: 'vp8',
          ),
          defaultAudioPublishOptions: AudioPublishOptions(
            dtx: true,
            red: true,
          ),
        ),
      );
    }
  }
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

// ─── CALL STATE — simple enum for UI to react to ──────────────────────────────
enum MeetCallState { idle, connecting, connected, disconnected, error, permissionsDenied }

final meetCallStateProvider = NotifierProvider<MeetCallStateNotifier, MeetCallState>(MeetCallStateNotifier.new);

class MeetCallStateNotifier extends Notifier<MeetCallState> {
  @override
  MeetCallState build() => MeetCallState.connecting;

  @override
  set state(MeetCallState value) => super.state = value;
}

// ─── CAMERA/MIC TOGGLES ───────────────────────────────────────────────────────
final meetIsCameraEnabledProvider = NotifierProvider<MeetCameraEnabledNotifier, bool>(MeetCameraEnabledNotifier.new);
class MeetCameraEnabledNotifier extends Notifier<bool> {
  @override
  bool build() => true;

  @override
  set state(bool value) => super.state = value;
}

final meetIsMicEnabledProvider = NotifierProvider<MeetMicEnabledNotifier, bool>(MeetMicEnabledNotifier.new);
class MeetMicEnabledNotifier extends Notifier<bool> {
  @override
  bool build() => true;

  @override
  set state(bool value) => super.state = value;
}

final meetIsScreenShareEnabledProvider = NotifierProvider<MeetScreenShareEnabledNotifier, bool>(MeetScreenShareEnabledNotifier.new);
class MeetScreenShareEnabledNotifier extends Notifier<bool> {
  @override
  bool build() => false;

  @override
  set state(bool value) => super.state = value;
}

final meetIsTileViewEnabledProvider = NotifierProvider<MeetTileViewEnabledNotifier, bool>(MeetTileViewEnabledNotifier.new);
class MeetTileViewEnabledNotifier extends Notifier<bool> {
  @override
  bool build() => true;

  @override
  set state(bool value) => super.state = value;
}

final meetIsChatOpenProvider = NotifierProvider<MeetChatOpenNotifier, bool>(MeetChatOpenNotifier.new);
class MeetChatOpenNotifier extends Notifier<bool> {
  @override
  bool build() => false;

  @override
  set state(bool value) => super.state = value;
}

