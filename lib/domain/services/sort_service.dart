import '../models/word_card.dart';

enum SortMode {
  alphabetAsc,
  alphabetDesc,
  createdAtDesc,
  createdAtAsc,
}

class SortService {
  List<WordCard> sort(List<WordCard> cards, SortMode mode) {
    final sorted = List<WordCard>.from(cards);
    switch (mode) {
      case SortMode.alphabetAsc:
        sorted.sort((a, b) =>
            a.word.toLowerCase().compareTo(b.word.toLowerCase()));
        break;
      case SortMode.alphabetDesc:
        sorted.sort((a, b) =>
            b.word.toLowerCase().compareTo(a.word.toLowerCase()));
        break;
      case SortMode.createdAtDesc:
        sorted.sort((a, b) => b.createdAt.compareTo(a.createdAt));
        break;
      case SortMode.createdAtAsc:
        sorted.sort((a, b) => a.createdAt.compareTo(b.createdAt));
        break;
    }
    return sorted;
  }
}
