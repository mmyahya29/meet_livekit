import 'dart:async';
import 'dart:ui';
import 'package:flutter/material.dart' hide ConnectionState;
import 'package:flutter_webrtc/flutter_webrtc.dart' show Helper;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:livekit_client/livekit_client.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:flutter_animate/flutter_animate.dart';

import '../providers/meet_providers.dart';
import '../design/meet_design_system.dart';
import '../models/meeting_summary.dart';
import 'meet_ephemeral_chat_widget.dart';

class MeetRoomScreen extends ConsumerStatefulWidget {
  final String serverUrl;
  final String token;
  final int? durationMinutes;
  final void Function(MeetingSummary summary) onLeaveCall;
  final void Function(Object error)? onError;

  const MeetRoomScreen({
    required this.serverUrl,
    required this.token,
    required this.onLeaveCall,
    this.durationMinutes,
    this.onError,
    super.key,
  });

  @override
  ConsumerState<MeetRoomScreen> createState() => _MeetRoomScreenState();
}

class _MeetRoomScreenState extends ConsumerState<MeetRoomScreen> with WidgetsBindingObserver {
  bool _isManuallyEnding = false;
  late final _roomNotifier = ref.read(meetLiveKitRoomProvider.notifier);
  
  // Analytics Tracking
  late final DateTime _meetingStartTime;
  final Map<String, ParticipantRecord> _participantsTracker = {};
  EventsListener<RoomEvent>? _roomListener;

  // Timeout logic
  final ValueNotifier<int> _secondsRemainingNotifier = ValueNotifier<int>(0);
  final ValueNotifier<bool> _gracePeriodNotifier = ValueNotifier<bool>(false);
  Timer? _callTimer;

  @override
  void initState() {
    super.initState();
    _meetingStartTime = DateTime.now();
    if (widget.durationMinutes != null) {
      _secondsRemainingNotifier.value = widget.durationMinutes! * 60;
    }
    
    WidgetsBinding.instance.addObserver(this);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _initCall();
    });
  }

  Future<void> _initCall() async {
    ref.read(meetCallStateProvider.notifier).state = MeetCallState.connecting;
    try {
      await _roomNotifier.connect(
        serverUrl: widget.serverUrl,
        token: widget.token,
      );

      if (mounted) {
        ref.read(meetCallStateProvider.notifier).state = MeetCallState.connected;
        final room = ref.read(meetLiveKitRoomProvider);
        
        // Track Local Participant
        if (room.localParticipant != null) {
          _trackParticipantJoin(room.localParticipant!);
        }
        
        // Track already existing Remote Participants
        for (final p in room.remoteParticipants.values) {
          _trackParticipantJoin(p);
        }

        room.addListener(_onRoomEvent);
        _setupRoomListener(room);
        
        if (widget.durationMinutes != null) {
          _startTimer();
        }
      }
    } catch (e) {
      if (mounted) {
        ref.read(meetCallStateProvider.notifier).state = MeetCallState.error;
        widget.onError?.call(e);
      }
    }
  }

  void _setupRoomListener(Room room) {
    _roomListener = room.createListener();
    _roomListener?.on<ParticipantConnectedEvent>((event) {
      _trackParticipantJoin(event.participant);
    });
    _roomListener?.on<ParticipantDisconnectedEvent>((event) {
      _trackParticipantLeave(event.participant.identity);
    });
  }

  void _trackParticipantJoin(Participant p) {
    if (_participantsTracker.containsKey(p.identity)) {
      _participantsTracker[p.identity]!.markRejoined(DateTime.now()); // Rejoined
    } else {
      _participantsTracker[p.identity] = ParticipantRecord(
        identity: p.identity,
        name: p.name.isNotEmpty == true ? p.name : 'Unknown',
        firstJoinedAt: DateTime.now(),
      );
    }
  }

  void _trackParticipantLeave(String identity) {
    if (_participantsTracker.containsKey(identity)) {
      _participantsTracker[identity]!.markLeft(DateTime.now());
    }
  }

  void _startTimer() {
    _callTimer?.cancel();
    _callTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (!mounted) {
        timer.cancel();
        return;
      }
      
      if (_secondsRemainingNotifier.value > 0) {
        _secondsRemainingNotifier.value--;
      } else {
        if (!_gracePeriodNotifier.value) {
          _gracePeriodNotifier.value = true;
          _secondsRemainingNotifier.value = 60; // 60 seconds grace period
        } else {
          _secondsRemainingNotifier.value--;
          if (_secondsRemainingNotifier.value <= 0) {
            timer.cancel();
            _forceEndCall();
          }
        }
      }
    });
  }

  Future<void> _endCall() async {
    final bool? confirm = await showDialog<bool>(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          title: const Text('End Call?'),
          content: const Text('Are you sure you want to leave the room?'),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () => Navigator.of(context).pop(true),
              style: FilledButton.styleFrom(backgroundColor: Colors.red),
              child: const Text('Leave'),
            ),
          ],
        );
      },
    );

    if (confirm != true) return;
    _forceEndCall();
  }

  Future<void> _forceEndCall() async {
    if (_isManuallyEnding) return;
    if (mounted) {
      setState(() {
        _isManuallyEnding = true;
      });
    }
    
    await Future.delayed(const Duration(milliseconds: 50));
    await _roomNotifier.disconnect();
    
    // Finalize tracking
    final now = DateTime.now();
    for (final record in _participantsTracker.values) {
      if (record.lastLeftAt == null) {
        record.markLeft(now);
      }
    }
    
    final summary = MeetingSummary(
      startTime: _meetingStartTime,
      endTime: now,
      participants: _participantsTracker,
    );
    
    if (!mounted) {
      widget.onLeaveCall(summary);
      return;
    }
    
    ref.read(meetCallStateProvider.notifier).state = MeetCallState.disconnected;

    widget.onLeaveCall(summary);
  }

  Future<void> _toggleCamera() async {
    final room = ref.read(meetLiveKitRoomProvider);
    final current = ref.read(meetIsCameraEnabledProvider);
    await room.localParticipant?.setCameraEnabled(!current);
    ref.read(meetIsCameraEnabledProvider.notifier).state = !current;
  }

  Future<void> _switchCamera() async {
    final room = ref.read(meetLiveKitRoomProvider);
    final track = room.localParticipant?.videoTrackPublications.firstOrNull?.track;
    if (track is LocalVideoTrack) {
      await Helper.switchCamera(track.mediaStreamTrack);
    }
  }

  Future<void> _toggleMic() async {
    final room = ref.read(meetLiveKitRoomProvider);
    final current = ref.read(meetIsMicEnabledProvider);
    await room.localParticipant?.setMicrophoneEnabled(!current);
    ref.read(meetIsMicEnabledProvider.notifier).state = !current;
  }

  Future<void> _toggleScreenShare() async {
    final room = ref.read(meetLiveKitRoomProvider);
    final current = ref.read(meetIsScreenShareEnabledProvider);
    if (!current) {
      try {
        if (Theme.of(context).platform == TargetPlatform.android) {
          await Helper.requestCapturePermission();
        }
      } catch (e) {
        debugPrint('Screen capture permission denied: $e');
        return;
      }
    }
    await room.localParticipant?.setScreenShareEnabled(!current);
    ref.read(meetIsScreenShareEnabledProvider.notifier).state = !current;
  }

  void _toggleTileView() {
    final current = ref.read(meetIsTileViewEnabledProvider);
    ref.read(meetIsTileViewEnabledProvider.notifier).state = !current;
  }

  void _toggleChat() {
    final current = ref.read(meetIsChatOpenProvider);
    ref.read(meetIsChatOpenProvider.notifier).state = !current;
  }

  void _onRoomEvent() {
    if (mounted) {
      setState(() {});
      
      final room = ref.read(meetLiveKitRoomProvider);
      if (room.connectionState == ConnectionState.disconnected && !_isManuallyEnding) {
        ref.read(meetCallStateProvider.notifier).state = MeetCallState.disconnected;
        _forceEndCall();
      }
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _callTimer?.cancel();
    _secondsRemainingNotifier.dispose();
    _gracePeriodNotifier.dispose();
    _roomListener?.dispose();
    final room = ref.read(meetLiveKitRoomProvider);
    room.removeListener(_onRoomEvent);
    _roomNotifier.disconnect();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.detached) {
      _roomNotifier.disconnect();
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_isManuallyEnding) {
      return const Scaffold(backgroundColor: Colors.black);
    }

    final screenWidth = MediaQuery.sizeOf(context).width;
    final isMobile    = screenWidth < 600;
    final callState   = ref.watch(meetCallStateProvider);
    final isCameraOn  = ref.watch(meetIsCameraEnabledProvider);
    final isMicOn     = ref.watch(meetIsMicEnabledProvider);
    final isScreenOn  = ref.watch(meetIsScreenShareEnabledProvider);
    final isTileView  = ref.watch(meetIsTileViewEnabledProvider);
    final isChatOpen  = ref.watch(meetIsChatOpenProvider);
    final room        = ref.watch(meetLiveKitRoomProvider);

    Widget body = switch (callState) {
      MeetCallState.connecting => const _ConnectingView(),
      MeetCallState.error => _ErrorView(onRetry: _initCall, onBack: () => widget.onLeaveCall(
        MeetingSummary(startTime: _meetingStartTime, endTime: DateTime.now(), participants: {})
      )),
      MeetCallState.connected || _ => _CallView(
        room:        room,
        isCameraOn:  isCameraOn,
        isMicOn:     isMicOn,
        isScreenOn:  isScreenOn,
        isTileView:  isTileView,
        onEndCall:   _endCall,
        onToggleCam: _toggleCamera,
        onToggleMic: _toggleMic,
        onSwitchCamera: _switchCamera,
        onToggleScreen: _toggleScreenShare,
        onToggleTileView: _toggleTileView,
        onToggleChat: _toggleChat,
        isChatOpen: isChatOpen,
        isMobile: isMobile,
      ),
    };

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, result) async {
        if (didPop) return;
        await _endCall();
      },
      child: Scaffold(
        backgroundColor: Colors.black,
        body: Stack(
          children: [
            Positioned.fill(
              child: body,
            ),
            AnimatedPositioned(
              duration: const Duration(milliseconds: 300),
              curve: Curves.easeOutCubic,
              top: isMobile ? (isChatOpen ? MediaQuery.sizeOf(context).height / 2 : MediaQuery.sizeOf(context).height) : 0,
              bottom: isMobile ? 0 : 0,
              right: isMobile ? 0 : (isChatOpen ? 0 : -350),
              left: isMobile ? 0 : null,
              width: isMobile ? null : 350,
              child: ClipRRect(
                borderRadius: isMobile ? const BorderRadius.vertical(top: Radius.circular(24)) : BorderRadius.zero,
                child: BackdropFilter(
                  filter: ImageFilter.blur(sigmaX: 20, sigmaY: 20),
                  child: Container(
                    decoration: BoxDecoration(
                      color: Colors.black.withValues(alpha: 0.5),
                      border: Border(
                        left: isMobile ? BorderSide.none : const BorderSide(color: Colors.white12),
                        top: isMobile ? const BorderSide(color: Colors.white12) : BorderSide.none,
                      ),
                    ),
                    child: MeetEphemeralChatWidget(
                      room: room,
                      onClose: _toggleChat,
                    ),
                  ),
                ),
              ),
            ),
            if (callState == MeetCallState.connected && widget.durationMinutes != null)
              Positioned(
                top: 16,
                left: 0,
                right: 0,
                child: SafeArea(
                  child: Center(
                    child: _CallTimerBanner(
                      secondsRemainingNotifier: _secondsRemainingNotifier,
                      gracePeriodNotifier: _gracePeriodNotifier,
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _CallTimerBanner extends StatelessWidget {
  final ValueNotifier<int> secondsRemainingNotifier;
  final ValueNotifier<bool> gracePeriodNotifier;

  const _CallTimerBanner({
    required this.secondsRemainingNotifier,
    required this.gracePeriodNotifier,
  });

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<int>(
      valueListenable: secondsRemainingNotifier,
      builder: (context, secondsRemaining, _) {
        return ValueListenableBuilder<bool>(
          valueListenable: gracePeriodNotifier,
          builder: (context, gracePeriodActive, _) {
            final String timeStr = '${(secondsRemaining ~/ 60).toString().padLeft(2, '0')}:${(secondsRemaining % 60).toString().padLeft(2, '0')}';
            final bool isLowTime = secondsRemaining < 60 && secondsRemaining > 0;

            if (!gracePeriodActive && !isLowTime && secondsRemaining > 300) {
              return const SizedBox.shrink(); // Only show when under 5 minutes or grace period
            }

            return MeetGlassContainer(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              borderRadius: BorderRadius.circular(MeetRadius.full),
              tintColor: Colors.white.withValues(alpha: 0.1),
              border: Border.all(color: Colors.white.withValues(alpha: 0.25), width: 1.5),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                decoration: BoxDecoration(
                  color: gracePeriodActive 
                    ? Colors.red.withValues(alpha: 0.2)
                    : isLowTime ? Colors.orange.withValues(alpha: 0.2) : Colors.transparent,
                  borderRadius: BorderRadius.circular(MeetRadius.full),
                  border: Border.all(
                    color: gracePeriodActive 
                      ? Colors.red.withValues(alpha: 0.5)
                      : Colors.transparent,
                  ),
                ),
                child: Text(
                  gracePeriodActive ? 'Ending in $secondsRemaining s...' : 'Time remaining: $timeStr',
                  style: TextStyle(
                    color: gracePeriodActive ? Colors.red : Colors.white, 
                    fontWeight: FontWeight.bold, 
                    fontSize: 14, 
                    decoration: TextDecoration.none
                  ),
                ),
              ).animate(target: gracePeriodActive ? 1 : 0)
               .tint(color: Colors.red, end: 0.5)
               .shimmer(duration: 1.seconds),
            ).animate().fadeIn(duration: 400.ms).slideY(begin: -0.5, end: 0, curve: Curves.easeOutQuad);
          },
        );
      },
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// CONNECTING VIEW
// ─────────────────────────────────────────────────────────────────────────────
class _ConnectingView extends StatelessWidget {
  const _ConnectingView();

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            MeetColors.surfaceElevated.withValues(alpha: 0.9), 
            Colors.black,
          ],
        ),
      ),
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              padding: const EdgeInsets.all(24),
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: MeetColors.primary.withValues(alpha: 0.1),
                boxShadow: MeetShadows.glow(MeetColors.primary),
              ),
              child: const Icon(LucideIcons.video, color: MeetColors.primary, size: 48)
                  .animate(onPlay: (controller) => controller.repeat(reverse: true))
                  .scale(begin: const Offset(1, 1), end: const Offset(1.1, 1.1), duration: 1.seconds)
                  .shimmer(duration: 2.seconds),
            ).animate().fadeIn(duration: 500.ms).slideY(begin: 0.2, end: 0, curve: Curves.easeOutCubic),
            const SizedBox(height: 32),
            const Text(
              'Connecting securely...',
              style: TextStyle(
                color: Colors.white, 
                fontSize: 18, 
                fontWeight: FontWeight.w600,
                letterSpacing: 0.5,
              ),
            ).animate().fadeIn(delay: 200.ms, duration: 500.ms),
          ],
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// ERROR VIEW
// ─────────────────────────────────────────────────────────────────────────────
class _ErrorView extends StatelessWidget {
  final VoidCallback onRetry;
  final VoidCallback onBack;
  const _ErrorView({required this.onRetry, required this.onBack});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.video_call_outlined, color: Colors.red, size: 64),
          const SizedBox(height: 16),
          const Text('Could not connect', style: TextStyle(color: Colors.white, fontSize: 18)),
          const SizedBox(height: 24),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              TextButton(onPressed: onBack,  child: const Text('Go Back')),
              const SizedBox(width: 16),
              ElevatedButton(onPressed: onRetry, child: const Text('Retry')),
            ],
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// MAIN CALL VIEW
// ─────────────────────────────────────────────────────────────────────────────
class _CallView extends StatelessWidget {
  final Room room;
  final bool isCameraOn;
  final bool isMicOn;
  final bool isScreenOn;
  final bool isTileView;
  final VoidCallback onEndCall;
  final VoidCallback onToggleCam;
  final VoidCallback onToggleMic;
  final VoidCallback onToggleScreen;
  final VoidCallback onToggleTileView;
  final VoidCallback onToggleChat;
  final VoidCallback onSwitchCamera;
  final bool isChatOpen;
  final bool isMobile;

  const _CallView({
    required this.room,
    required this.isCameraOn,
    required this.isMicOn,
    required this.isScreenOn,
    required this.isTileView,
    required this.onEndCall,
    required this.onToggleCam,
    required this.onToggleMic,
    required this.onSwitchCamera,
    required this.onToggleScreen,
    required this.onToggleTileView,
    required this.onToggleChat,
    required this.isChatOpen,
    required this.isMobile,
  });

  @override
  Widget build(BuildContext context) {
    final localParticipant = room.localParticipant;
    final remoteParticipants = room.remoteParticipants.values.toList();
    final List<Participant> allParticipants = [
      ?localParticipant,
      ...remoteParticipants
    ];

    final activeScreenShareRemote = remoteParticipants.where(
      (p) => p.videoTrackPublications.any((t) => t.source == TrackSource.screenShareVideo && t.subscribed)
    ).firstOrNull;

    final activeScreenShareLocal = (localParticipant != null && isScreenOn) ? localParticipant : null;
    final bool isScreenShareActive = activeScreenShareRemote != null || activeScreenShareLocal != null;

    Widget mainBackground;
    bool showPips = true;

    if (activeScreenShareRemote != null) {
      mainBackground = _RemoteParticipantView(
          participant: activeScreenShareRemote, source: TrackSource.screenShareVideo);
    } else if (activeScreenShareLocal != null) {
      mainBackground = _LocalParticipantView(
          participant: localParticipant,
          isCameraOn: true,
          source: TrackSource.screenShareVideo);
    } else if (isTileView) {
      showPips = false;
      if (allParticipants.isEmpty) {
        mainBackground = const Center(
            child: Text('Waiting for participants...',
                style: TextStyle(color: Colors.white54, fontSize: 16)));
      } else {
        mainBackground = LayoutBuilder(
          builder: (context, constraints) {
            final int count = allParticipants.length;
            final double margin = 8.0;
            double width, height;

            if (count == 1) {
              width = constraints.maxWidth - (margin * 2);
              height = constraints.maxHeight - (margin * 2);
            } else if (count == 2) {
              if (constraints.maxHeight > constraints.maxWidth) {
                width = constraints.maxWidth - (margin * 2);
                height = (constraints.maxHeight / 2) - (margin * 2);
              } else {
                width = (constraints.maxWidth / 2) - (margin * 2);
                height = constraints.maxHeight - (margin * 2);
              }
            } else if (count <= 4) {
              width = (constraints.maxWidth / 2) - (margin * 2);
              height = (constraints.maxHeight / 2) - (margin * 2);
            } else if (count <= 9) {
              width = (constraints.maxWidth / 3) - (margin * 2);
              height = (constraints.maxHeight / 3) - (margin * 2);
            } else {
              width = (constraints.maxWidth / 4) - (margin * 2);
              height = (constraints.maxHeight / 4) - (margin * 2);
            }

            return Center(
              child: Wrap(
                alignment: WrapAlignment.center,
                runAlignment: WrapAlignment.center,
                children: allParticipants.map((p) {
                  return Container(
                    width: width,
                    height: height,
                    margin: EdgeInsets.all(margin),
                    clipBehavior: Clip.antiAlias,
                    decoration: BoxDecoration(
                      color: const Color(0xFF1A1A2E),
                      borderRadius: BorderRadius.circular(16),
                    ),
                    child: p is LocalParticipant
                        ? _LocalParticipantView(
                            participant: p, isCameraOn: isCameraOn)
                        : _RemoteParticipantView(
                            participant: p as RemoteParticipant),
                  );
                }).toList(),
              ),
            );
          },
        );
      }
    } else if (remoteParticipants.isNotEmpty) {
      mainBackground = _RemoteParticipantView(participant: remoteParticipants.first);
    } else {
      mainBackground = Container(
        color: const Color(0xFF0A0A1A),
        child: const Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.person_outline, color: Colors.white38, size: 80),
              SizedBox(height: 16),
              Text(
                'Waiting for others to join...',
                style: TextStyle(color: Colors.white54, fontSize: 16),
              ),
            ],
          ),
        ),
      );
    }

    List<Participant> pipParticipants = [];
    if (showPips) {
      if (isScreenShareActive) {
        pipParticipants = allParticipants;
      } else if (!isTileView && remoteParticipants.isNotEmpty) {
        pipParticipants = allParticipants.where((p) => p != remoteParticipants.first).toList();
      } else {
        pipParticipants = allParticipants;
      }
    }

    return Stack(
      children: [
        Positioned.fill(
          child: Stack(
            fit: StackFit.expand,
            children: [
              mainBackground,
              Container(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [
                      Colors.black.withValues(alpha: 0.6),
                      Colors.transparent,
                      Colors.transparent,
                      Colors.black.withValues(alpha: 0.8),
                    ],
                    stops: const [0.0, 0.15, 0.7, 1.0],
                  ),
                ),
              ),
            ],
          ),
        ),
        if (showPips && pipParticipants.isNotEmpty)
          Positioned(
            top: 48,
            right: 16,
            bottom: 120, 
            child: SizedBox(
              width: 120,
              child: SingleChildScrollView(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: pipParticipants.map((p) {
                    return Padding(
                      padding: const EdgeInsets.only(bottom: 8),
                      child: Container(
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: Colors.white.withValues(alpha: 0.2), width: 1.5),
                          boxShadow: const [
                            BoxShadow(color: Colors.black26, blurRadius: 8, offset: Offset(0, 4)),
                          ],
                        ),
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(10.5),
                          child: SizedBox(
                            width: 120,
                            height: 160,
                            child: p is LocalParticipant
                                ? _LocalParticipantView(
                                    participant: p, isCameraOn: isCameraOn)
                                : _RemoteParticipantView(
                                    participant: p as RemoteParticipant),
                          ),
                        ),
                      ).animate().fadeIn(duration: 400.ms).slideX(begin: 0.2, end: 0, curve: Curves.easeOutQuad),
                    );
                  }).toList(),
                ),
              ),
            ),
          ),
        Positioned(
          bottom: isMobile ? MediaQuery.of(context).padding.bottom + 8 : 24,
          left: 0,
          right: (isChatOpen && !isMobile) ? 350 : 0, 
          child: Center(
            child: MeetGlassContainer(
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
              borderRadius: BorderRadius.circular(MeetRadius.full),
              tintColor: Colors.black.withValues(alpha: 0.5),
              border: Border.all(color: Colors.white.withValues(alpha: 0.1)),
              child: _ControlBar(
                isCameraOn: isCameraOn,
                isMicOn: isMicOn,
                isScreenOn: isScreenOn,
                isTileView: isTileView,
                onEndCall: onEndCall,
                onToggleCam: onToggleCam,
                onToggleMic: onToggleMic,
                onSwitchCamera: onSwitchCamera,
                onToggleScreen: onToggleScreen,
                onToggleTileView: onToggleTileView,
                onToggleChat: onToggleChat,
                isChatOpen: isChatOpen,
                isMobile: isMobile,
              ),
            ),
          ),
        ),
      ],
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// REMOTE PARTICIPANT VIDEO
// ─────────────────────────────────────────────────────────────────────────────
class _RemoteParticipantView extends StatefulWidget {
  final RemoteParticipant participant;
  final TrackSource source;
  const _RemoteParticipantView({required this.participant, this.source = TrackSource.camera});

  @override
  State<_RemoteParticipantView> createState() => _RemoteParticipantViewState();
}

class _RemoteParticipantViewState extends State<_RemoteParticipantView> {
  VideoTrack? _videoTrack;

  @override
  void initState() {
    super.initState();
    widget.participant.addListener(_onParticipantChanged);
    _updateVideoTrack();
  }

  void _onParticipantChanged() {
    if (mounted) setState(_updateVideoTrack);
  }

  void _updateVideoTrack() {
    _videoTrack = widget.participant.videoTrackPublications
      .where((pub) {
        if (!pub.subscribed || pub.track == null || pub.source != widget.source) return false;
        if (pub.muted || (pub.track?.muted ?? false)) return false;
        return true;
      })
      .map((pub) => pub.track as VideoTrack)
      .firstOrNull;
      
    if (widget.source == TrackSource.camera && !widget.participant.isCameraEnabled()) {
      _videoTrack = null;
    }
  }

  @override
  void dispose() {
    widget.participant.removeListener(_onParticipantChanged);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    Widget content;
    if (_videoTrack != null) {
      content = VideoTrackRenderer(_videoTrack!);
    } else {
      content = Container(
        color: const Color(0xFF1A1A2E),
        child: const Center(
          child: CircleAvatar(
            radius: 40,
            backgroundColor: Colors.white12,
            child: Icon(Icons.person, color: Colors.white38, size: 48),
          ),
        ),
      );
    }
    
    return Stack(
      fit: StackFit.expand,
      children: [
        content,
        _buildConnectionOverlay(widget.participant.connectionQuality),
      ],
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// LOCAL PARTICIPANT VIDEO 
// ─────────────────────────────────────────────────────────────────────────────
class _LocalParticipantView extends StatefulWidget {
  final LocalParticipant? participant;
  final bool isCameraOn;
  final TrackSource source;
  const _LocalParticipantView({required this.participant, required this.isCameraOn, this.source = TrackSource.camera});

  @override
  State<_LocalParticipantView> createState() => _LocalParticipantViewState();
}

class _LocalParticipantViewState extends State<_LocalParticipantView> {
  VideoTrack? _videoTrack;

  @override
  void initState() {
    super.initState();
    widget.participant?.addListener(_onParticipantChanged);
    _updateVideoTrack();
  }

  void _onParticipantChanged() {
    if (mounted) setState(_updateVideoTrack);
  }

  void _updateVideoTrack() {
    _videoTrack = widget.participant?.videoTrackPublications
      .where((pub) => pub.track != null && pub.source == widget.source)
      .map((pub) => pub.track as VideoTrack)
      .firstOrNull;
  }

  @override
  void dispose() {
    widget.participant?.removeListener(_onParticipantChanged);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    Widget content;
    if (widget.isCameraOn && _videoTrack != null) {
      content = VideoTrackRenderer(_videoTrack!);
    } else {
      content = Container(
        color: const Color(0xFF0D0D2B),
        child: const Center(
          child: CircleAvatar(
            radius: 30,
            backgroundColor: Colors.white12,
            child: Icon(Icons.person, color: Colors.white38, size: 36),
          ),
        ),
      );
    }
    
    return Stack(
      fit: StackFit.expand,
      children: [
        content,
        if (widget.participant != null)
           _buildConnectionOverlay(widget.participant!.connectionQuality),
      ],
    );
  }
}

Widget _buildConnectionOverlay(ConnectionQuality quality) {
  if (quality == ConnectionQuality.excellent || quality == ConnectionQuality.good || quality == ConnectionQuality.unknown) {
    return const SizedBox.shrink();
  }
  
  final isLost = quality == ConnectionQuality.lost;
  return Positioned(
    top: 8,
    right: 8,
    child: Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.7),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: isLost ? Colors.red : Colors.orange),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            isLost ? LucideIcons.wifiOff : LucideIcons.wifi, 
            color: isLost ? Colors.red : Colors.orange, 
            size: 14
          ),
          const SizedBox(width: 4),
          Text(
            isLost ? 'Lost' : 'Poor Connection',
            style: TextStyle(color: isLost ? Colors.red : Colors.orange, fontSize: 10, fontWeight: FontWeight.bold, decoration: TextDecoration.none),
          ),
        ],
      ),
    ),
  );
}

// ─────────────────────────────────────────────────────────────────────────────
// CONTROL BAR
// ─────────────────────────────────────────────────────────────────────────────
class _ControlBar extends StatelessWidget {
  final bool isCameraOn;
  final bool isMicOn;
  final bool isScreenOn;
  final bool isTileView;
  final VoidCallback onEndCall;
  final VoidCallback onToggleCam;
  final VoidCallback onToggleMic;
  final VoidCallback onToggleScreen;
  final VoidCallback onToggleTileView;
  final VoidCallback onToggleChat;
  final VoidCallback onSwitchCamera;
  final bool isChatOpen;
  final bool isMobile;

  const _ControlBar({
    required this.isCameraOn,
    required this.isMicOn,
    required this.isScreenOn,
    required this.isTileView,
    required this.onEndCall,
    required this.onToggleCam,
    required this.onToggleMic,
    required this.onSwitchCamera,
    required this.onToggleScreen,
    required this.onToggleTileView,
    required this.onToggleChat,
    required this.isChatOpen,
    required this.isMobile,
  });

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 16,
      runSpacing: 16,
      alignment: WrapAlignment.center,
      crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          _ControlButton(
            icon: isMicOn ? Icons.mic : Icons.mic_off,
            label: isMicOn ? 'Mute' : 'Unmute',
            onTap: onToggleMic,
            isActive: isMicOn,
            isMobile: isMobile,
          ),
          MeetBouncyTap(
            onTap: onEndCall,
            child: Container(
              width: isMobile ? 48 : 56,
              height: isMobile ? 48 : 56,
              decoration: BoxDecoration(
                gradient: const LinearGradient(
                  colors: [Color(0xFFE53935), Color(0xFFC62828)],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
                shape: BoxShape.circle,
                boxShadow: MeetShadows.glow(const Color(0xFFE53935)),
              ),
              child: Icon(Icons.call_end, color: Colors.white, size: isMobile ? 22 : 26),
            ),
          ),
          _ControlButton(
            icon: isCameraOn ? Icons.videocam : Icons.videocam_off,
            label: isCameraOn ? 'Hide Cam' : 'Show Cam',
            onTap: onToggleCam,
            isActive: isCameraOn,
            isMobile: isMobile,
          ),
          _ControlButton(
            icon: isScreenOn ? Icons.stop_screen_share : Icons.screen_share,
            label: isScreenOn ? 'Stop Share' : 'Share',
            onTap: onToggleScreen,
            isActive: isScreenOn,
            isMobile: isMobile,
          ),
          _ControlButton(
            icon: isTileView ? Icons.grid_view : Icons.picture_in_picture,
            label: isTileView ? 'Speaker' : 'Grid',
            onTap: onToggleTileView,
            isActive: isTileView,
            isMobile: isMobile,
          ),
          _ControlButton(
            icon: isChatOpen ? Icons.chat_bubble : Icons.chat_bubble_outline,
            label: 'Chat',
            onTap: onToggleChat,
            isActive: isChatOpen,
            isMobile: isMobile,
          ),
        ].animate(interval: 50.ms).fadeIn(duration: 300.ms).slideY(begin: 0.2, end: 0, curve: Curves.easeOutQuad),
      );
  }
}

class _ControlButton extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final bool isActive;
  final bool isMobile;

  const _ControlButton({
    required this.icon,
    required this.label,
    required this.onTap,
    required this.isActive,
    required this.isMobile,
  });

  @override
  Widget build(BuildContext context) {
    return MeetBouncyTap(
      onTap: onTap,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: isMobile ? 44 : 52,
            height: isMobile ? 44 : 52,
            decoration: BoxDecoration(
              color: isActive
                ? Colors.white.withValues(alpha: 0.15)
                : Colors.white.withValues(alpha: 0.05),
              shape: BoxShape.circle,
              border: Border.all(
                color: Colors.white.withValues(alpha: isActive ? 0.3 : 0.1),
              ),
            ),
            child: Icon(icon, color: Colors.white, size: isMobile ? 18 : 22),
          ),
          const SizedBox(height: 6),
          Text(label, style: const TextStyle(color: Colors.white54, fontSize: 11)),
        ],
      ),
    );
  }
}
