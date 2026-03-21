#!/usr/bin/env python3
import argparse
import json
import re
import sys
from collections import Counter
from pathlib import Path
from typing import List


ROOT = Path(__file__).resolve().parents[1]
DEFAULT_PATH = ROOT / "assets" / "word_bank" / "word_bank_main.json"
ALLOWED_POS = {
    "noun",
    "verb",
    "adjective",
    "adverb",
    "pronoun",
    "preposition",
    "conjunction",
    "exclamation",
    "determiner",
}
ALLOWED_SCHOOL_LEVELS = {"elementary", "juniorHigh", "seniorHigh", "college"}
ALLOWED_EXAM_TAGS = {"toeic"}
ALLOWED_AUDIENCE_TAGS = {"general"}
ALLOWED_SOURCE_TAGS = {"twCeec", "toeicSignals", "collegeSignals", "pdfExamBook"}
HTML_TAG_RE = re.compile(r"<[^>]+>")


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(
        description="Validate assets/word_bank/word_bank_main.json"
    )
    parser.add_argument(
        "--path",
        default=str(DEFAULT_PATH),
        help="Path to the word bank JSON file.",
    )
    parser.add_argument(
        "--fail-on-warnings",
        action="store_true",
        help="Return a non-zero exit code when warnings are present.",
    )
    parser.add_argument(
        "--max-issues",
        type=int,
        default=50,
        help="Maximum number of errors or warnings to print.",
    )
    return parser.parse_args()


def add_issue(issues: List[str], word: str, message: str) -> None:
    issues.append(f"{word}: {message}")


def validate_string_list(
    issues: List[str],
    word: str,
    field_name: str,
    raw_value: object,
    allowed_values: set[str],
) -> None:
    if raw_value is None:
        return
    if not isinstance(raw_value, list):
        add_issue(issues, word, f"{field_name} must be a list when present")
        return

    seen: set[str] = set()
    for item in raw_value:
        if not isinstance(item, str) or not item.strip():
            add_issue(issues, word, f"{field_name} contains an invalid value")
            continue
        if item not in allowed_values:
            add_issue(issues, word, f"{field_name} contains unsupported value: {item!r}")
        if item in seen:
            add_issue(issues, word, f"{field_name} contains duplicate value: {item!r}")
        seen.add(item)


def main() -> int:
    args = parse_args()
    path = Path(args.path)
    with path.open(encoding="utf-8") as file:
        data = json.load(file)

    errors: List[str] = []
    warnings: List[str] = []

    if not isinstance(data, list):
        print("ERROR: top-level JSON value must be a list")
        return 1

    words = []
    for index, item in enumerate(data):
        word = f"index:{index}"
        if not isinstance(item, dict):
            errors.append(f"{word}: item must be an object")
            continue

        actual_word = item.get("word")
        if not isinstance(actual_word, str) or not actual_word.strip():
            errors.append(f"{word}: missing or invalid word")
            continue
        word = actual_word
        words.append(word)

        meaning = item.get("meaning")
        part_of_speech = item.get("partOfSpeech")
        sentences = item.get("sentences")
        school_levels = item.get("schoolLevels")
        exam_tags = item.get("examTags")
        audience_tags = item.get("audienceTags")
        source_tags = item.get("sourceTags")
        difficulty_level = item.get("difficultyLevel")

        if meaning is None:
            add_issue(errors, word, "missing meaning")
        elif not isinstance(meaning, str):
            add_issue(errors, word, f"meaning must be a string, got {type(meaning).__name__}")
        elif not meaning.strip():
            add_issue(errors, word, "meaning is empty")
        elif HTML_TAG_RE.search(meaning):
            add_issue(errors, word, "meaning contains HTML or wiki markup")
        elif "\n" in meaning:
            add_issue(warnings, word, "meaning contains newline")
        elif "\\n" in meaning:
            add_issue(warnings, word, "meaning contains escaped newline")

        if not isinstance(part_of_speech, str) or not part_of_speech.strip():
            add_issue(errors, word, "missing or empty partOfSpeech")
        elif part_of_speech not in ALLOWED_POS:
            add_issue(warnings, word, f"legacy or non-standard partOfSpeech: {part_of_speech!r}")

        if not isinstance(sentences, list):
            add_issue(errors, word, "sentences must be a list")
            continue
        if len(sentences) != 2:
            add_issue(errors, word, f"sentences must contain exactly 2 items, got {len(sentences)}")
        for sentence_index, sentence in enumerate(sentences):
            if not isinstance(sentence, str) or not sentence.strip():
                add_issue(errors, word, f"sentence {sentence_index + 1} is missing or empty")
                continue
            if "\n" in sentence:
                add_issue(warnings, word, f"sentence {sentence_index + 1} contains newline")
            elif "\\n" in sentence:
                add_issue(warnings, word, f"sentence {sentence_index + 1} contains escaped newline")
            if HTML_TAG_RE.search(sentence):
                add_issue(errors, word, f"sentence {sentence_index + 1} contains HTML or wiki markup")

        validate_string_list(
            errors,
            word,
            "schoolLevels",
            school_levels,
            ALLOWED_SCHOOL_LEVELS,
        )
        validate_string_list(
            errors,
            word,
            "examTags",
            exam_tags,
            ALLOWED_EXAM_TAGS,
        )
        validate_string_list(
            errors,
            word,
            "audienceTags",
            audience_tags,
            ALLOWED_AUDIENCE_TAGS,
        )
        validate_string_list(
            errors,
            word,
            "sourceTags",
            source_tags,
            ALLOWED_SOURCE_TAGS,
        )
        if difficulty_level is not None:
            if not isinstance(difficulty_level, int):
                add_issue(errors, word, "difficultyLevel must be an integer when present")
            elif difficulty_level < 1 or difficulty_level > 6:
                add_issue(errors, word, f"difficultyLevel out of range: {difficulty_level}")

    duplicates = sorted(word for word, count in Counter(words).items() if count > 1)
    for word in duplicates:
        add_issue(errors, word, "duplicate word entry")

    if words != sorted(words, key=str.casefold):
        errors.append("GLOBAL: word list is not sorted by casefold()")

    if errors:
        print(f"VALIDATION FAILED: {len(errors)} error(s), {len(warnings)} warning(s)")
        for issue in errors[: args.max_issues]:
            print(f"ERROR {issue}")
        if len(errors) > args.max_issues:
            print(f"... {len(errors) - args.max_issues} more errors")
        if warnings:
            print(f"WARNINGS NOT SHOWN: {len(warnings)}")
        return 1

    status = "VALIDATION OK"
    if warnings:
        status = "VALIDATION OK WITH WARNINGS"
    print(f"{status}: {len(data)} entries")
    print(
        "Checks: structure, duplicates, sorting, HTML markup, newline, partOfSpeech, sentence count"
    )
    if warnings:
        for issue in warnings[: args.max_issues]:
            print(f"WARN {issue}")
        if len(warnings) > args.max_issues:
            print(f"... {len(warnings) - args.max_issues} more warnings")
        return 1 if args.fail_on_warnings else 0
    return 0


if __name__ == "__main__":
    sys.exit(main())
