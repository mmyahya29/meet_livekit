class MeetingSummary {
  final DateTime startTime;
  final DateTime endTime;
  final Map<String, ParticipantRecord> participants;

  MeetingSummary({
    required this.startTime,
    required this.endTime,
    required this.participants,
  });

  Duration get totalDuration => endTime.difference(startTime);

  @override
  String toString() {
    return 'MeetingSummary(duration: $totalDuration, participants: ${participants.length})';
  }
}

class ParticipantSession {
  final DateTime joinedAt;
  DateTime? leftAt;

  ParticipantSession({required this.joinedAt, this.leftAt});

  Duration get duration => (leftAt ?? DateTime.now()).difference(joinedAt);
}

class ParticipantRecord {
  final String identity;
  final String name;
  final List<ParticipantSession> sessions = [];

  ParticipantRecord({
    required this.identity,
    required this.name,
    required DateTime firstJoinedAt,
  }) {
    sessions.add(ParticipantSession(joinedAt: firstJoinedAt));
  }

  DateTime get firstJoinedAt => sessions.first.joinedAt;
  DateTime? get lastLeftAt => sessions.last.leftAt;

  Duration get totalTimeInMeeting {
    return sessions.fold(Duration.zero, (total, session) => total + session.duration);
  }

  void markRejoined(DateTime joinedAt) {
    if (sessions.isNotEmpty && sessions.last.leftAt == null) return; // Already active
    sessions.add(ParticipantSession(joinedAt: joinedAt));
  }

  void markLeft(DateTime leftAt) {
    if (sessions.isNotEmpty && sessions.last.leftAt == null) {
      sessions.last.leftAt = leftAt;
    }
  }

  @override
  String toString() {
    return 'ParticipantRecord($identity, name: $name, totalTime: $totalTimeInMeeting, sessions: ${sessions.length})';
  }
}
