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

    await state.connect(
      serverUrl,
      token,
    );

    // Enable camera and microphone on join
    await state.localParticipant?.setCameraEnabled(true);
    await state.localParticipant?.setMicrophoneEnabled(true);
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
      await state.disconnect();
    } catch (e) {
      // ignore: avoid_print
      print('Error disconnecting: $e');
    }
  }
}

// ─── CALL STATE — simple enum for UI to react to ──────────────────────────────
enum MeetCallState { idle, connecting, connected, disconnected, error }

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
