import '../../domain/models/word_card.dart';
import '../../domain/services/review_schedule_service.dart';
import '../sources/word_local_db.dart';
import 'word_repository.dart';

class LocalWordRepository implements WordRepository {
  LocalWordRepository({
    required WordLocalDb localDb,
    required ReviewScheduleService scheduleService,
  })  : _localDb = localDb,
        _scheduleService = scheduleService;

  final WordLocalDb _localDb;
  final ReviewScheduleService _scheduleService;

  @override
  Future<List<WordCard>> fetchAll({bool includeDeleted = false}) async {
    final raw = await _localDb.getAll();
    final cards = raw.map(WordCard.fromMap).toList();
    if (includeDeleted) {
      return cards;
    }
    return cards.where((card) => !card.isDeleted).toList();
  }

  @override
  Future<List<WordCard>> fetchDue(DateTime day) async {
    final all = await fetchAll();
    return all
        .where((card) => _scheduleService.isDueOnOrBefore(card, day))
        .toList();
  }

  @override
  Future<void> add(WordCard card) async {
    await _localDb.put(card.id, card.toMap());
  }

  @override
  Future<void> update(WordCard card) async {
    await _localDb.put(card.id, card.toMap());
  }

  @override
  Future<void> delete(String id) async {
    await _localDb.delete(id);
  }
}
