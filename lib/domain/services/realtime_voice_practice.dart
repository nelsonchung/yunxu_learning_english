import 'voice_practice_service.dart';

class RealtimeVoicePractice {
  RealtimeVoicePractice(this.answerGoal);

  final int? answerGoal;
  final _items = <String, ({bool learner, String text})>{};
  final _committed = <String>{};
  final _additionalCommits = <String>{};
  final _transcribed = <String>{};
  final pendingResponses = <String>{};
  final interruptedResponses = <String>{};
  final completedResponses = <String>{};
  final transcriptEvents = <String>{};
  String? activeResponse;
  String? audioItem;
  int audioIndex = 0;
  int audioBytes = 0;
  bool responseRequested = false;
  bool replyPending = false;
  bool finalReplyRequested = false;
  bool finalReplyCompleted = false;
  bool interrupting = false;
  bool speaking = false;
  bool playing = false;

  bool get blocksMicrophone =>
      responseRequested ||
      pendingResponses.isNotEmpty ||
      playing ||
      interrupting;

  int get answerCount => _committed.length;
  bool get goalReached {
    final goal = answerGoal;
    return goal != null && answerCount >= goal;
  }

  bool get transcriptionComplete => pendingTranscriptions.isEmpty;
  Iterable<String> get pendingTranscriptions => [
    ..._committed,
    ..._additionalCommits,
  ].where((id) => !_transcribed.contains(id));

  Iterable<({bool learner, String text})> get captions =>
      _items.values.where((item) => item.text.trim().isNotEmpty);

  bool commit(String id) {
    if (_committed.contains(id) || _additionalCommits.contains(id)) {
      return false;
    }
    if (goalReached || blocksMicrophone) {
      _additionalCommits.add(id);
      return false;
    }
    _committed.add(id);
    _items[id] = (learner: true, text: '');
    return true;
  }

  bool completeTranscription(String id) =>
      (_committed.contains(id) || _additionalCommits.contains(id)) &&
      _transcribed.add(id);

  void transcript(
    String id,
    String text, {
    required bool learner,
    bool finalText = false,
  }) {
    if (learner && !_committed.contains(id)) return;
    if (learner && _transcribed.contains(id)) return;
    _items[id] = (
      learner: learner,
      text: finalText ? text : '${_items[id]?.text ?? ''}$text',
    );
  }

  List<VoicePracticeTurn> get turns {
    final turns = <VoicePracticeTurn>[];
    var assistant = StringBuffer();
    for (final item in _items.values) {
      if (item.learner) {
        final user = item.text.trim();
        if (user.isNotEmpty) {
          turns.add((assistant: assistant.toString().trim(), user: user));
        }
        assistant = StringBuffer();
      } else if (item.text.isNotEmpty) {
        if (assistant.isNotEmpty) assistant.write(' ');
        assistant.write(item.text);
      }
    }
    return turns;
  }
}
