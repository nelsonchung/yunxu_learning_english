import '../../domain/models/word_card.dart';

abstract class WordRepository {
  Future<List<WordCard>> fetchAll();
  Future<List<WordCard>> fetchDue(DateTime day);
  Future<void> add(WordCard card);
  Future<void> update(WordCard card);
  Future<void> delete(String id);
}
