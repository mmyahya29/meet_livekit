# Meet LiveKit

A robust, drop-in Flutter package for adding LiveKit-powered group video calls to your app. Extracted and decoupled from the Foster marketplace architecture, this package offers a fully functional, self-contained video conferencing UI with local data-channel chat, advanced participant tracking, and custom meeting timeouts.

## Features

- 🎥 **Video & Audio**: Seamless integration with `livekit_client` for robust WebRTC video calls.
- 💬 **Ephemeral Chat**: Built-in chat overlay powered by LiveKit data channels. Messages disappear when the call ends, ensuring privacy.
- ⏱️ **Custom Timeouts**: Enforce meeting durations with visual countdown warnings and a configurable grace period before automatic disconnection.
- 📊 **Meeting Analytics**: Retrieve a detailed `MeetingSummary` object when a call finishes, including the exact join, leave, and total time duration for every individual participant.
- 📱 **Responsive UI**: Gracefully handles screen sharing, speaker view, grid view (tile mode), and picture-in-picture (PIP) for mobile and desktop platforms.
- 🎨 **Standalone Design System**: Comes with its own independent styling tokens (`MeetColors`, `MeetRadius`, `MeetShadows`), so you don't need to depend on external UI libraries.

## Installation

Add `meet_livekit` to your `pubspec.yaml` dependencies (or point it to your local path):

```yaml
dependencies:
  flutter:
    sdk: flutter
  meet_livekit:
    path: ../meet_livekit # Replace with actual path or git url
  flutter_riverpod: ^2.6.1
  livekit_client: ^2.11.0
```

## Quick Start

`MeetRoomScreen` handles all UI states (connecting, error, connected call). Just wrap your app with a `ProviderScope` (from `flutter_riverpod`) and push the `MeetRoomScreen` when you want to start a call.

### 1. Initialize ProviderScope

Ensure your root widget is wrapped in `ProviderScope`:

```dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

void main() {
  runApp(const ProviderScope(child: MyApp()));
}
```

### 2. Join a Room

To launch the video call screen, push it into your navigation stack:

```dart
import 'package:flutter/material.dart';
import 'package:meet_livekit/meet_livekit.dart';

void joinMeeting(BuildContext context) {
  Navigator.push(
    context,
    MaterialPageRoute(
      builder: (context) => MeetRoomScreen(
        serverUrl: 'wss://your-project.livekit.cloud',
        token: 'YOUR_LIVEKIT_ACCESS_TOKEN',
        
        // Optional: Force the meeting to end after 30 minutes
        durationMinutes: 30, 
        
        onLeaveCall: (MeetingSummary summary) {
          Navigator.pop(context); // Close the screen
          
          // Access meeting analytics
          print('Meeting lasted: ${summary.totalDuration.inMinutes} minutes');
          for (var p in summary.participants.values) {
            print('${p.name} was present for ${p.totalTimeInMeeting.inMinutes} mins');
          }
        },
        onError: (error) {
          print('Failed to connect: $error');
        },
      ),
    ),
  );
}
```

## Analytics Tracking (`MeetingSummary`)

When the call terminates (either by the user pressing the End Call button or the timeout expiring), the `onLeaveCall` callback is fired with a `MeetingSummary` object.

```dart
class MeetingSummary {
  final DateTime startTime;
  final DateTime endTime;
  final Map<String, ParticipantRecord> participants;
  
  Duration get totalDuration;
}

class ParticipantRecord {
  final String identity;
  final String name;
  final DateTime firstJoinedAt;
  final DateTime? lastLeftAt;
  final Duration totalTimeInMeeting;
}
```
*Note: If a user disconnects and reconnects due to network issues, their `totalTimeInMeeting` correctly pauses and resumes accumulation.*

## Use Cases

1. **Mentorship & Tutoring Platforms**: Use `durationMinutes` to rigidly enforce 30-minute paid sessions. 
2. **Telehealth / Consultations**: Use the `MeetingSummary` analytics to bill clients exactly for the amount of time the professional spent in the active call.
3. **Internal Team Tools**: A quick, robust drop-in component for internal dashboards to allow instant face-to-face team collaboration.

## Platform Setup Requirements

Because this package relies on `flutter_webrtc` under the hood, ensure you have the appropriate OS-level permissions configured in your host app:

**iOS (`Info.plist`)**
```xml
<key>NSCameraUsageDescription</key>
<string>We require camera access to connect to the video call.</string>
<key>NSMicrophoneUsageDescription</key>
<string>We require microphone access to connect to the audio call.</string>
```

**Android (`AndroidManifest.xml`)**
```xml
<uses-permission android:name="android.permission.CAMERA" />
<uses-permission android:name="android.permission.RECORD_AUDIO" />
<uses-permission android:name="android.permission.INTERNET" />
```
