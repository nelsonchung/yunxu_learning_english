#!/usr/bin/env python3
import argparse
import json
import re
import sys
from collections import Counter
from pathlib import Path
from typing import Dict, Optional


ROOT = Path(__file__).resolve().parents[1]
DEFAULT_PATH = ROOT / "assets" / "word_bank" / "word_bank_main.json"

TEMPLATE_SENTENCE_PATTERNS = [
    (re.compile(r"^The term .+ refers to ", re.IGNORECASE), "template_definition_sentence", 2),
    (re.compile(r"^The lesson introduced ", re.IGNORECASE), "template_lesson_sentence", 2),
    (re.compile(r"^We learned the meaning of ", re.IGNORECASE), "template_lesson_sentence", 2),
    (re.compile(r"^We discussed the term ", re.IGNORECASE), "template_lesson_sentence", 2),
    (re.compile(r"^We practiced using ", re.IGNORECASE), "template_practice_sentence", 2),
    (re.compile(r"^Students practiced using ", re.IGNORECASE), "template_practice_sentence", 2),
    (re.compile(r"^The guide wrote down ", re.IGNORECASE), "template_generated_sentence", 2),
    (re.compile(r"^The teacher wrote down ", re.IGNORECASE), "template_generated_sentence", 2),
    (re.compile(r"^Mia wrote down ", re.IGNORECASE), "template_generated_sentence", 2),
    (re.compile(r"^The coach wrote down ", re.IGNORECASE), "template_generated_sentence", 2),
    (re.compile(r"^The note explained ", re.IGNORECASE), "template_generated_sentence", 2),
    (re.compile(r"^The article explained ", re.IGNORECASE), "template_generated_sentence", 2),
    (re.compile(r"^The textbook defined ", re.IGNORECASE), "template_generated_sentence", 2),
    (re.compile(r"^Writers use .+ for ", re.IGNORECASE), "template_writers_use_sentence", 3),
    (
        re.compile(r"^Writers use .+ to describe something that is ", re.IGNORECASE),
        "template_writers_use_sentence",
        3,
    ),
    (re.compile(r"^Writers use .+ to mean ", re.IGNORECASE), "template_writers_use_sentence", 3),
    (
        re.compile(r"^The word .+ still appears in older books and notes\.", re.IGNORECASE),
        "template_older_books_sentence",
        3,
    ),
    (
        re.compile(r"^In the report, the sample looked .+ to the researchers\.", re.IGNORECASE),
        "template_report_sample_sentence",
        3,
    ),
    (
        re.compile(r"^How to use .+ in a sentence\.", re.IGNORECASE),
        "sentence_prompt_pollution",
        4,
    ),
    (
        re.compile(r"^She adjusted the sample .+ to match the description in the manual\.", re.IGNORECASE),
        "template_adverb_sentence",
        3,
    ),
    (
        re.compile(r"^The report says the movement happened .+ during the test\.", re.IGNORECASE),
        "generic_adverb_sentence",
        3,
    ),
    (
        re.compile(r"^She responded .+ after reading the short message\.", re.IGNORECASE),
        "generic_adverb_sentence",
        3,
    ),
]

MEANING_PATTERNS = [
    (re.compile(r"\balternative (form|spelling|letter-case form)\b", re.IGNORECASE), "lexicography_alternative_form", 4),
    (re.compile(r"\b(obsolete|dated spelling|nonstandard spelling|eye dialect)\b", re.IGNORECASE), "lexicography_nonstandard_form", 4),
    (re.compile(r"\b(plural of|past tense of|past participle of|present participle of|third-person singular|comparative of|superlative of|inflection of)\b", re.IGNORECASE), "lexicography_inflection_gloss", 4),
    (re.compile(r"\b(surname|given name|proper noun)\b", re.IGNORECASE), "lexicography_name_gloss", 3),
    (re.compile(r"^罕見或專門用語。?$"), "placeholder_meaning", 4),
    (re.compile(r"^罕見或專門的英語術語", re.IGNORECASE), "placeholder_meaning", 4),
    (re.compile(r"如何(?:用|使用).{0,30}造句"), "meaning_prompt_pollution", 5),
    (re.compile(r"How to use .+ in a sentence", re.IGNORECASE), "meaning_prompt_pollution", 5),
]

BAD_TRANSLATION_MARKERS = [
    ("用上了這個副詞", "meta_adverb_translation", 3),
]


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(
        description="Review word bank entries for suspicious content quality issues."
    )
    parser.add_argument(
        "--path",
        default=str(DEFAULT_PATH),
        help="Path to the word bank JSON file.",
    )
    parser.add_argument(
        "--min-score",
        type=int,
        default=2,
        help="Minimum score required for an entry to be reported.",
    )
    parser.add_argument(
        "--limit",
        type=int,
        default=50,
        help="Maximum number of entries to print in text mode.",
    )
    parser.add_argument(
        "--prefix",
        help="Only review words whose lowercase form starts with this prefix.",
    )
    parser.add_argument(
        "--format",
        choices=("text", "json"),
        default="text",
        help="Output format.",
    )
    return parser.parse_args()


def has_cjk(text: str) -> bool:
    return any("\u4e00" <= char <= "\u9fff" for char in text)


def has_ascii_letter(text: str) -> bool:
    return any(char.isascii() and char.isalpha() for char in text)


def split_bilingual_sentence(sentence: str) -> tuple[str, str]:
    for index, char in enumerate(sentence):
        if "\u4e00" <= char <= "\u9fff":
            start = index
            while start > 0 and sentence[start - 1].isspace():
                start -= 1
            return sentence[:start].strip(), sentence[start:].strip()
    return sentence.strip(), ""


def translation_contains_word(sentence: str, word: str) -> bool:
    _, translation = split_bilingual_sentence(sentence)
    if not translation:
        return False
    lower_word = word.casefold()
    return lower_word in translation.casefold()


def english_half_repeats_meaning_prompt(text: str) -> bool:
    return bool(re.search(r"How to use .+ in a sentence", text, re.IGNORECASE))


def review_entry(index: int, entry: dict) -> Optional[dict]:
    word = entry.get("word", "")
    meaning = entry.get("meaning", "")
    sentences = entry.get("sentences") or []
    score = 0
    reasons: list[str] = []

    for pattern, reason, weight in MEANING_PATTERNS:
        if pattern.search(meaning):
            reasons.append(reason)
            score += weight

    for sentence_index, sentence in enumerate(sentences, start=1):
        english_half, translation_half = split_bilingual_sentence(sentence)

        for pattern, reason, weight in TEMPLATE_SENTENCE_PATTERNS:
            if pattern.search(english_half):
                reasons.append(f"{reason}:s{sentence_index}")
                score += weight

        for marker, reason, weight in BAD_TRANSLATION_MARKERS:
            if marker in sentence:
                reasons.append(f"{reason}:s{sentence_index}")
                score += weight

        if english_half_repeats_meaning_prompt(english_half):
            reasons.append(f"sentence_prompt_pollution:s{sentence_index}")
            score += 4

        if english_half and english_half[0].isascii() and english_half[0].islower():
            reasons.append(f"sentence_fragment_style:s{sentence_index}")
            score += 1

        if not has_cjk(sentence) or not has_ascii_letter(sentence):
            reasons.append(f"missing_bilingual_content:s{sentence_index}")
            score += 1

        if translation_contains_word(sentence, word):
            reasons.append(f"untranslated_word_in_translation:s{sentence_index}")
            score += 2

        if translation_half and english_half and translation_half == english_half:
            reasons.append(f"copied_translation_half:s{sentence_index}")
            score += 3

    if score == 0:
        return None

    return {
        "index": index,
        "word": word,
        "score": score,
        "reasons": reasons,
        "reasonCounts": dict(Counter(reason.split(":")[0] for reason in reasons).most_common()),
        "meaning": meaning,
        "partOfSpeech": entry.get("partOfSpeech", ""),
        "sentences": sentences,
    }


def build_payload(path: Path, results: list[dict], reason_counts: Counter[str]) -> Dict[str, object]:
    return {
        "path": str(path),
        "file": path.name,
        "candidateCount": len(results),
        "reasonCounts": dict(reason_counts.most_common()),
        "candidates": results,
    }


def main() -> int:
    args = parse_args()
    path = Path(args.path)
    with path.open(encoding="utf-8") as file:
        data = json.load(file)

    prefix = args.prefix.casefold() if args.prefix else None
    results = []
    reason_counts: Counter[str] = Counter()

    for index, entry in enumerate(data):
        word = str(entry.get("word", ""))
        if prefix and not word.casefold().startswith(prefix):
            continue
        reviewed = review_entry(index, entry)
        if reviewed is None or reviewed["score"] < args.min_score:
            continue
        results.append(reviewed)
        for reason in reviewed["reasons"]:
            reason_counts[reason.split(":")[0]] += 1

    results.sort(key=lambda item: (-item["score"], item["word"]))

    if args.format == "json":
        payload = build_payload(path, results, reason_counts)
        json.dump(payload, sys.stdout, ensure_ascii=False, indent=2)
        sys.stdout.write("\n")
        return 0

    print(f"REVIEW CANDIDATES: {len(results)}")
    print(f"Path: {path}")
    print("Reason counts:")
    for reason, count in reason_counts.most_common():
        print(f"{count}\t{reason}")
    print("")

    for item in results[: args.limit]:
        print(f"score={item['score']} word={item['word']} index={item['index']}")
        print("  reasons: " + ", ".join(item["reasons"]))
        print("  meaning: " + item["meaning"])
        for sentence_index, sentence in enumerate(item["sentences"], start=1):
            print(f"  s{sentence_index}: {sentence}")
        print("")

    remaining = len(results) - min(len(results), args.limit)
    if remaining > 0:
        print(f"... {remaining} more candidates not shown")
    return 0


if __name__ == "__main__":
    sys.exit(main())
