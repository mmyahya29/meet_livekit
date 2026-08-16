import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:livekit_client/livekit_client.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import '../design/meet_design_system.dart';

class MeetEphemeralChatWidget extends StatefulWidget {
  final Room room;
  final VoidCallback onClose;

  const MeetEphemeralChatWidget({super.key, required this.room, required this.onClose});

  @override
  State<MeetEphemeralChatWidget> createState() => _MeetEphemeralChatWidgetState();
}

class _MeetEphemeralChatWidgetState extends State<MeetEphemeralChatWidget> {
  final List<Map<String, dynamic>> _messages = [];
  final TextEditingController _controller = TextEditingController();
  final ScrollController _scrollController = ScrollController();
  EventsListener<RoomEvent>? _listener;
  String? _myIdentity;

  @override
  void initState() {
    super.initState();
    _myIdentity = widget.room.localParticipant?.identity;
    _setupListener();
  }

  void _setupListener() {
    _listener = widget.room.createListener();
    _listener?.on<DataReceivedEvent>((event) {
      final text = utf8.decode(event.data);
      if (mounted) {
        setState(() {
          _messages.add({
            'senderId': event.participant?.identity ?? 'Unknown',
            'senderName': event.participant?.name.isNotEmpty == true ? event.participant!.name : 'Anonymous',
            'text': text,
            'timestamp': DateTime.now(),
          });
        });
        _scrollToBottom();
      }
    });
  }

  @override
  void dispose() {
    _listener?.dispose();
    _controller.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  Future<void> _sendMessage() async {
    final text = _controller.text.trim();
    if (text.isEmpty) return;
    _controller.clear();

    setState(() {
      _messages.add({
        'senderId': _myIdentity,
        'senderName': 'You',
        'text': text,
        'timestamp': DateTime.now(),
      });
    });
    _scrollToBottom();

    final data = utf8.encode(text);
    try {
      await widget.room.localParticipant?.publishData(data, reliable: true);
    } catch (e) {
      debugPrint('Failed to send data: $e');
    }
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollController.hasClients) {
        _scrollController.animateTo(
          _scrollController.position.maxScrollExtent,
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeOut,
        );
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    return Column(
      children: [
        // Header
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            border: Border(bottom: BorderSide(color: isDark ? Colors.white12 : Colors.black12)),
          ),
          child: Row(
            children: [
              const Icon(LucideIcons.messageCircle, size: 20),
              const SizedBox(width: 12),
              const Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Group Chat', style: TextStyle(fontWeight: FontWeight.w600, fontSize: 16)),
                    Text('Messages disappear when call ends', style: TextStyle(fontSize: 12, color: MeetColors.onSurfaceVariant)),
                  ],
                ),
              ),
              IconButton(
                icon: const Icon(LucideIcons.x, size: 20),
                onPressed: widget.onClose,
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(),
              ),
            ],
          ),
        ),

        // Messages List
        Expanded(
          child: _messages.isEmpty
              ? Center(
                  child: Text(
                    'No messages yet.\nSay hello!',
                    textAlign: TextAlign.center,
                    style: TextStyle(color: theme.colorScheme.onSurfaceVariant),
                  ),
                )
              : ListView.builder(
                  controller: _scrollController,
                  padding: const EdgeInsets.all(16),
                  itemCount: _messages.length,
                  itemBuilder: (context, index) {
                    final msg = _messages[index];
                    final isMe = msg['senderId'] == _myIdentity;
                    
                    return Padding(
                      padding: const EdgeInsets.only(bottom: 16),
                      child: Row(
                        mainAxisAlignment: isMe ? MainAxisAlignment.end : MainAxisAlignment.start,
                        crossAxisAlignment: CrossAxisAlignment.end,
                        children: [
                          if (!isMe) ...[
                            CircleAvatar(
                              radius: 14,
                              backgroundColor: MeetColors.primary.withValues(alpha: 0.2),
                              child: Text(
                                (msg['senderName'] as String)[0].toUpperCase(),
                                style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: MeetColors.primary),
                              ),
                            ),
                            const SizedBox(width: 8),
                          ],
                          Flexible(
                            child: Column(
                              crossAxisAlignment: isMe ? CrossAxisAlignment.end : CrossAxisAlignment.start,
                              children: [
                                if (!isMe)
                                  Padding(
                                    padding: const EdgeInsets.only(bottom: 4, left: 4),
                                    child: Text(
                                      msg['senderName'],
                                      style: TextStyle(fontSize: 12, color: theme.colorScheme.onSurfaceVariant, fontWeight: FontWeight.w500),
                                    ),
                                  ),
                                Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                                  decoration: BoxDecoration(
                                    color: isMe ? MeetColors.primary : (isDark ? theme.colorScheme.surfaceContainerHighest : Colors.grey.shade200),
                                    borderRadius: BorderRadius.only(
                                      topLeft: const Radius.circular(16),
                                      topRight: const Radius.circular(16),
                                      bottomLeft: Radius.circular(isMe ? 16 : 4),
                                      bottomRight: Radius.circular(isMe ? 4 : 16),
                                    ),
                                  ),
                                  child: Text(
                                    msg['text'],
                                    style: TextStyle(
                                      color: isMe ? Colors.white : Colors.black87,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    );
                  },
                ),
        ),

        // Input Area
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            border: Border(top: BorderSide(color: isDark ? Colors.white12 : Colors.black12)),
          ),
          child: Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _controller,
                  decoration: InputDecoration(
                    hintText: 'Type a message...',
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(MeetRadius.full),
                      borderSide: BorderSide.none,
                    ),
                    filled: true,
                    fillColor: isDark ? theme.colorScheme.surfaceContainerHighest : Colors.grey.shade200,
                    contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                  ),
                  onSubmitted: (_) => _sendMessage(),
                ),
              ),
              const SizedBox(width: 8),
              MeetBouncyTap(
                onTap: _sendMessage,
                child: Container(
                  padding: const EdgeInsets.all(12),
                  decoration: const BoxDecoration(
                    color: MeetColors.primary,
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(LucideIcons.send, color: Colors.white, size: 20),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}
