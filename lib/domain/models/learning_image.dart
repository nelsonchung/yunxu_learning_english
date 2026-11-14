import 'dart:convert';

enum LearningImageMode { precise, fast }

extension LearningImageModeLabel on LearningImageMode {
  String get label => this == LearningImageMode.precise ? '精緻模式' : '快速模式';
  String get model => this == LearningImageMode.precise
      ? 'gpt-image-2.5-sunburst'
      : 'gpt-image-2.5-flare';
}

enum LearningImageStage {
  idle,
  researching,
  conflict,
  generating,
  ready,
  failed,
  cancelled,
}

class LearningImageSource {
  const LearningImageSource({required this.title, required this.url});
  final String title;
  final String url;
  Map<String, Object?> toMap() => {'title': title, 'url': url};
  factory LearningImageSource.fromMap(Map data) => LearningImageSource(
    title: data['title'] as String,
    url: data['url'] as String,
  );
}

class LearningImageContent {
  const LearningImageContent({
    required this.word,
    required this.meaning,
    required this.partsOfSpeech,
    required this.sentences,
    required this.memoryHint,
    required this.diagram,
    this.conflict = '',
    this.sources = const [],
  });
  final String word, meaning, partsOfSpeech, memoryHint, diagram, conflict;
  final List<String> sentences;
  final List<LearningImageSource> sources;
  Map<String, Object?> toMap() => {
    'word': word,
    'meaning': meaning,
    'partsOfSpeech': partsOfSpeech,
    'sentences': sentences,
    'memoryHint': memoryHint,
    'diagram': diagram,
    'conflict': conflict,
    'sources': sources.map((s) => s.toMap()).toList(),
  };
  String get promptData => jsonEncode(toMap());
  factory LearningImageContent.fromMap(
    Map data, {
    List<LearningImageSource>? sources,
  }) => LearningImageContent(
    word: data['word'] as String,
    meaning: data['meaning'] as String,
    partsOfSpeech: data['partsOfSpeech'] as String,
    sentences: (data['sentences'] as List).cast<String>().take(3).toList(),
    memoryHint: data['memoryHint'] as String,
    diagram: data['diagram'] as String,
    conflict: data['conflict'] as String? ?? '',
    sources:
        sources ??
        (data['sources'] as List? ?? [])
            .map((s) => LearningImageSource.fromMap(s as Map))
            .toList(),
  );
}

class LearningImageCost {
  const LearningImageCost({required this.usd, required this.unknown});
  final double usd;
  final bool unknown;
  static const rateDate = '2026-10-04';
  static const exchangeRate = 32.0;
  static LearningImageCost calculate(
    String model,
    Map? usage, {
    int? searches,
  }) {
    final searchCost =
        model == 'gpt-5.4-mini' && searches != null && searches >= 0
        ? searches * .01
        : 0.0;
    if (usage == null) return LearningImageCost(usd: searchCost, unknown: true);
    if (model == 'gpt-live-1') {
      final seconds = usage['seconds'];
      if (seconds is! num || !seconds.isFinite || seconds < 0) {
        return const LearningImageCost(usd: 0, unknown: true);
      }
      return LearningImageCost(
        usd: seconds / 60 * .05,
        unknown: usage['final'] != true,
      );
    }
    int? count(dynamic v) => v is int && v >= 0 ? v : null;
    final input = count(usage['input_tokens']);
    final output = count(usage['output_tokens']);
    final details = usage['input_tokens_details'] is Map
        ? usage['input_tokens_details'] as Map
        : null;
    if (model == 'gpt-6-luna') {
      final cached = count(details?['cached_tokens']);
      final validInput = input != null && cached != null && cached <= input;
      return LearningImageCost(
        usd:
            ((validInput ? (input - cached) * .10 + cached * .01 : 0) +
                (output ?? 0) * .50) /
            1000000,
        unknown: !validInput || output == null,
      );
    }
    if (model == 'gpt-5.4-mini') {
      final cached = count(details?['cached_tokens']);
      final validInput = input != null && cached != null && cached <= input;
      return LearningImageCost(
        usd:
            searchCost +
            ((validInput ? (input - cached) * .75 + cached * .075 : 0) +
                    (output == null ? 0 : output * 4.5)) /
                1000000,
        unknown: !validInput || output == null || searches == null,
      );
    }
    if (model == 'gpt-image-2.5-sunburst' || model == 'gpt-image-2.5-flare') {
      final text = count(details?['text_tokens']);
      final image = count(details?['image_tokens']);
      // Cache modality pricing cannot safely be inferred from a total cache count.
      final cached = count(details?['cached_tokens']);
      if (text == null ||
          image == null ||
          output == null ||
          (cached != null && cached != 0) ||
          input == null ||
          text + image != input) {
        return LearningImageCost(
          usd: output == null ? 0 : output * 30 / 1000000,
          unknown: true,
        );
      }
      return LearningImageCost(
        usd: (text * 5 + image * 8 + output * 30) / 1000000,
        unknown: false,
      );
    }
    return const LearningImageCost(usd: 0, unknown: true);
  }
}

class LearningImageAttempt {
  LearningImageAttempt({
    required this.id,
    required this.model,
    required this.createdAt,
    this.requestId,
    this.wordId,
    this.word,
    this.generationId,
    this.outcome,
    this.usage,
    this.searches,
    this.status = 'pending',
    this.rateDate = LearningImageCost.rateDate,
    LearningImageCost? savedCost,
  }) : _savedCost = savedCost;
  final String id, model;
  final DateTime createdAt;
  final String? requestId;
  final String? wordId, word, generationId, outcome;
  final Map? usage;
  final int? searches;
  final String status;
  final String rateDate;
  final LearningImageCost? _savedCost;
  LearningImageCost get cost =>
      _savedCost ??
      LearningImageCost.calculate(model, usage, searches: searches);

  /// Updating lifecycle state must retain the original fee snapshot.
  LearningImageAttempt withOutcome(String value) => LearningImageAttempt(
    id: id,
    model: model,
    createdAt: createdAt,
    requestId: requestId,
    wordId: wordId,
    word: word,
    generationId: generationId,
    outcome: value,
    usage: usage,
    searches: searches,
    status: status,
    rateDate: rateDate,
    savedCost: cost,
  );
  Map<String, Object?> toMap() => {
    'id': id,
    'model': model,
    'createdAt': createdAt.millisecondsSinceEpoch,
    'requestId': requestId,
    'wordId': wordId,
    'word': word,
    'generationId': generationId,
    'outcome': outcome,
    'usage': usage,
    'searches': searches,
    'status': status,
    'rateDate': rateDate,
    'usd': cost.usd,
    'unknown': cost.unknown,
  };
  factory LearningImageAttempt.fromMap(Map data) => LearningImageAttempt(
    id: data['id'] as String,
    model: data['model'] as String,
    createdAt: DateTime.fromMillisecondsSinceEpoch(data['createdAt'] as int),
    requestId: data['requestId'] as String?,
    wordId: data['wordId'] as String?,
    word: data['word'] as String?,
    generationId: data['generationId'] as String?,
    outcome: data['outcome'] as String?,
    usage: data['usage'] as Map?,
    searches: data['searches'] as int?,
    status: data['status'] as String,
    rateDate: data['rateDate'] as String? ?? 'unknown',
    savedCost: LearningImageCost(
      usd: (data['usd'] as num?)?.toDouble() ?? 0,
      unknown: data['unknown'] as bool? ?? true,
    ),
  );
}

class LearningImageMetadata {
  const LearningImageMetadata({
    required this.wordId,
    required this.imageIdentity,
    required this.content,
    required this.model,
    required this.createdAt,
  });
  final String wordId, imageIdentity, model;
  final LearningImageContent content;
  List<LearningImageSource> get sources => content.sources;
  final DateTime createdAt;
  Map<String, Object?> toMap() => {
    'wordId': wordId,
    'imageIdentity': imageIdentity,
    'content': content.toMap(),
    'model': model,
    'createdAt': createdAt.millisecondsSinceEpoch,
  };
  factory LearningImageMetadata.fromMap(Map data) => LearningImageMetadata(
    wordId: data['wordId'] as String,
    imageIdentity: data['imageIdentity'] as String,
    content: LearningImageContent.fromMap(data['content'] as Map),
    model: data['model'] as String,
    createdAt: DateTime.fromMillisecondsSinceEpoch(data['createdAt'] as int),
  );
}
