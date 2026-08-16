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

class ParticipantRecord {
  final String identity;
  final String name;
  final DateTime firstJoinedAt;
  DateTime? lastLeftAt;
  Duration totalTimeInMeeting;

  ParticipantRecord({
    required this.identity,
    required this.name,
    required this.firstJoinedAt,
    this.lastLeftAt,
    this.totalTimeInMeeting = Duration.zero,
  });

  void markLeft(DateTime leftAt) {
    lastLeftAt = leftAt;
    totalTimeInMeeting += leftAt.difference(firstJoinedAt);
  }

  @override
  String toString() {
    return 'ParticipantRecord($identity, name: $name, totalTime: $totalTimeInMeeting)';
  }
}
