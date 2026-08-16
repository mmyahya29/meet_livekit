import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:meet_livekit/meet_livekit.dart';

void main() {
  runApp(
    const ProviderScope(
      child: MyApp(),
    ),
  );
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Meet LiveKit Example',
      theme: ThemeData.dark(useMaterial3: true).copyWith(
        scaffoldBackgroundColor: MeetColors.background,
        colorScheme: const ColorScheme.dark(
          primary: MeetColors.primary,
          surface: MeetColors.surface,
        ),
      ),
      home: const EntryScreen(),
    );
  }
}

class EntryScreen extends StatefulWidget {
  const EntryScreen({super.key});

  @override
  State<EntryScreen> createState() => _EntryScreenState();
}

class _EntryScreenState extends State<EntryScreen> {
  final _urlController = TextEditingController(text: 'wss://your-project.livekit.cloud');
  final _tokenController = TextEditingController(text: 'eyJhbGciOi...');
  final _durationController = TextEditingController();

  void _joinRoom() {
    if (_urlController.text.isEmpty || _tokenController.text.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please enter a URL and Token')),
      );
      return;
    }

    final duration = int.tryParse(_durationController.text);

    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => MeetRoomScreen(
          serverUrl: _urlController.text,
          token: _tokenController.text,
          durationMinutes: duration,
          onLeaveCall: (summary) {
            Navigator.pop(context);
            _showSummaryDialog(summary);
          },
          onError: (e) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(content: Text('Error joining room: $e')),
            );
          },
        ),
      ),
    );
  }

  void _showSummaryDialog(MeetingSummary summary) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Meeting Ended'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Total Duration: ${summary.totalDuration.inMinutes}m ${summary.totalDuration.inSeconds % 60}s'),
            const SizedBox(height: 16),
            const Text('Participants:', style: TextStyle(fontWeight: FontWeight.bold)),
            ...summary.participants.values.map((p) => Text('- ${p.name} (${p.totalTimeInMeeting.inMinutes}m ${p.totalTimeInMeeting.inSeconds % 60}s)')),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('OK'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 400),
          child: MeetGlassContainer(
            padding: const EdgeInsets.all(32),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const Icon(Icons.videocam, size: 48, color: MeetColors.primary),
                const SizedBox(height: 16),
                const Text(
                  'Join LiveKit Room',
                  style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold, color: Colors.white),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 32),
                TextField(
                  controller: _urlController,
                  decoration: const InputDecoration(
                    labelText: 'Server URL',
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 16),
                TextField(
                  controller: _tokenController,
                  maxLines: 3,
                  decoration: const InputDecoration(
                    labelText: 'LiveKit Token',
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 16),
                TextField(
                  controller: _durationController,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(
                    labelText: 'Duration (Minutes, Optional)',
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 32),
                ElevatedButton(
                  onPressed: _joinRoom,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: MeetColors.primary,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 16),
                  ),
                  child: const Text('Join Room'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
