#!/usr/bin/env python3
import argparse
import json
import re
import sys
from collections import Counter
from pathlib import Path
from typing import Any, Dict, List


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
    parser.add_argument(
        "--format",
        choices=("text", "json"),
        default="text",
        help="Output format.",
    )
    return parser.parse_args()


def add_issue(
    issues: List[Dict[str, str]],
    *,
    severity: str,
    category: str,
    word: str,
    message: str,
) -> None:
    issues.append(
        {
            "severity": severity,
            "category": category,
            "word": word,
            "message": message,
        }
    )


def format_issue(issue: Dict[str, str]) -> str:
    return f"{issue['word']}: {issue['message']}"


def validate_string_list(
    issues: List[Dict[str, str]],
    *,
    word: str,
    field_name: str,
    raw_value: object,
    allowed_values: set[str],
) -> None:
    if raw_value is None:
        return
    if not isinstance(raw_value, list):
        add_issue(
            issues,
            severity="error",
            category="schema",
            word=word,
            message=f"{field_name} must be a list when present",
        )
        return

    seen: set[str] = set()
    for item in raw_value:
        if not isinstance(item, str) or not item.strip():
            add_issue(
                issues,
                severity="error",
                category="field-value",
                word=word,
                message=f"{field_name} contains an invalid value",
            )
            continue
        if item not in allowed_values:
            add_issue(
                issues,
                severity="error",
                category="field-value",
                word=word,
                message=f"{field_name} contains unsupported value: {item!r}",
            )
        if item in seen:
            add_issue(
                issues,
                severity="error",
                category="duplicates",
                word=word,
                message=f"{field_name} contains duplicate value: {item!r}",
            )
        seen.add(item)


def group_issue_counts(issues: List[Dict[str, str]]) -> Dict[str, int]:
    counter: Counter[str] = Counter()
    for issue in issues:
        counter[issue["category"]] += 1
    return dict(counter.most_common())


def build_payload(
    *,
    path: Path,
    data: object,
    errors: List[Dict[str, str]],
    warnings: List[Dict[str, str]],
    exit_code: int,
) -> Dict[str, Any]:
    entry_count = len(data) if isinstance(data, list) else None
    status = "VALIDATION OK"
    if errors:
        status = "VALIDATION FAILED"
    elif warnings:
        status = "VALIDATION OK WITH WARNINGS"

    return {
        "path": str(path),
        "file": path.name,
        "status": status,
        "entryCount": entry_count,
        "errorCount": len(errors),
        "warningCount": len(warnings),
        "errorCategoryCounts": group_issue_counts(errors),
        "warningCategoryCounts": group_issue_counts(warnings),
        "errors": errors,
        "warnings": warnings,
        "exitCode": exit_code,
    }


def print_text_output(
    *,
    path: Path,
    data: object,
    errors: List[Dict[str, str]],
    warnings: List[Dict[str, str]],
    max_issues: int,
) -> None:
    if errors:
        print(f"VALIDATION FAILED: {len(errors)} error(s), {len(warnings)} warning(s)")
        for issue in errors[:max_issues]:
            print(f"ERROR {format_issue(issue)}")
        if len(errors) > max_issues:
            print(f"... {len(errors) - max_issues} more errors")
        if warnings:
            print(f"WARNINGS NOT SHOWN: {len(warnings)}")
        return

    print(f"{'VALIDATION OK WITH WARNINGS' if warnings else 'VALIDATION OK'}: {len(data)} entries")
    print(
        "Checks: structure, duplicates, sorting, HTML markup, newline, partOfSpeech, sentence count"
    )
    if warnings:
        for issue in warnings[:max_issues]:
            print(f"WARN {format_issue(issue)}")
        if len(warnings) > max_issues:
            print(f"... {len(warnings) - max_issues} more warnings")


def main() -> int:
    args = parse_args()
    path = Path(args.path)
    with path.open(encoding="utf-8") as file:
        data = json.load(file)

    errors: List[Dict[str, str]] = []
    warnings: List[Dict[str, str]] = []

    if not isinstance(data, list):
        add_issue(
            errors,
            severity="error",
            category="schema",
            word="GLOBAL",
            message="top-level JSON value must be a list",
        )
        payload = build_payload(
            path=path,
            data=data,
            errors=errors,
            warnings=warnings,
            exit_code=1,
        )
        if args.format == "json":
            json.dump(payload, sys.stdout, ensure_ascii=False, indent=2)
            sys.stdout.write("\n")
        else:
            print("ERROR: top-level JSON value must be a list")
        return 1

    words = []
    for index, item in enumerate(data):
        word = f"index:{index}"
        if not isinstance(item, dict):
            add_issue(
                errors,
                severity="error",
                category="schema",
                word=word,
                message="item must be an object",
            )
            continue

        actual_word = item.get("word")
        if not isinstance(actual_word, str) or not actual_word.strip():
            add_issue(
                errors,
                severity="error",
                category="schema",
                word=word,
                message="missing or invalid word",
            )
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
            add_issue(
                errors,
                severity="error",
                category="schema",
                word=word,
                message="missing meaning",
            )
        elif not isinstance(meaning, str):
            add_issue(
                errors,
                severity="error",
                category="schema",
                word=word,
                message=f"meaning must be a string, got {type(meaning).__name__}",
            )
        elif not meaning.strip():
            add_issue(
                errors,
                severity="error",
                category="schema",
                word=word,
                message="meaning is empty",
            )
        elif HTML_TAG_RE.search(meaning):
            add_issue(
                errors,
                severity="error",
                category="markup",
                word=word,
                message="meaning contains HTML or wiki markup",
            )
        elif "\n" in meaning:
            add_issue(
                warnings,
                severity="warning",
                category="newline",
                word=word,
                message="meaning contains newline",
            )
        elif "\\n" in meaning:
            add_issue(
                warnings,
                severity="warning",
                category="newline",
                word=word,
                message="meaning contains escaped newline",
            )

        if not isinstance(part_of_speech, str) or not part_of_speech.strip():
            add_issue(
                errors,
                severity="error",
                category="schema",
                word=word,
                message="missing or empty partOfSpeech",
            )
        elif part_of_speech not in ALLOWED_POS:
            add_issue(
                warnings,
                severity="warning",
                category="field-value",
                word=word,
                message=f"legacy or non-standard partOfSpeech: {part_of_speech!r}",
            )

        if not isinstance(sentences, list):
            add_issue(
                errors,
                severity="error",
                category="schema",
                word=word,
                message="sentences must be a list",
            )
            continue
        if len(sentences) != 2:
            add_issue(
                errors,
                severity="error",
                category="schema",
                word=word,
                message=f"sentences must contain exactly 2 items, got {len(sentences)}",
            )
        for sentence_index, sentence in enumerate(sentences):
            if not isinstance(sentence, str) or not sentence.strip():
                add_issue(
                    errors,
                    severity="error",
                    category="schema",
                    word=word,
                    message=f"sentence {sentence_index + 1} is missing or empty",
                )
                continue
            if "\n" in sentence:
                add_issue(
                    warnings,
                    severity="warning",
                    category="newline",
                    word=word,
                    message=f"sentence {sentence_index + 1} contains newline",
                )
            elif "\\n" in sentence:
                add_issue(
                    warnings,
                    severity="warning",
                    category="newline",
                    word=word,
                    message=f"sentence {sentence_index + 1} contains escaped newline",
                )
            if HTML_TAG_RE.search(sentence):
                add_issue(
                    errors,
                    severity="error",
                    category="markup",
                    word=word,
                    message=f"sentence {sentence_index + 1} contains HTML or wiki markup",
                )

        validate_string_list(
            errors,
            word=word,
            field_name="schoolLevels",
            raw_value=school_levels,
            allowed_values=ALLOWED_SCHOOL_LEVELS,
        )
        validate_string_list(
            errors,
            word=word,
            field_name="examTags",
            raw_value=exam_tags,
            allowed_values=ALLOWED_EXAM_TAGS,
        )
        validate_string_list(
            errors,
            word=word,
            field_name="audienceTags",
            raw_value=audience_tags,
            allowed_values=ALLOWED_AUDIENCE_TAGS,
        )
        validate_string_list(
            errors,
            word=word,
            field_name="sourceTags",
            raw_value=source_tags,
            allowed_values=ALLOWED_SOURCE_TAGS,
        )
        if difficulty_level is not None:
            if not isinstance(difficulty_level, int):
                add_issue(
                    errors,
                    severity="error",
                    category="field-value",
                    word=word,
                    message="difficultyLevel must be an integer when present",
                )
            elif difficulty_level < 1 or difficulty_level > 6:
                add_issue(
                    errors,
                    severity="error",
                    category="field-value",
                    word=word,
                    message=f"difficultyLevel out of range: {difficulty_level}",
                )

    duplicates = sorted(word for word, count in Counter(words).items() if count > 1)
    for word in duplicates:
        add_issue(
            errors,
            severity="error",
            category="duplicates",
            word=word,
            message="duplicate word entry",
        )

    if words != sorted(words, key=str.casefold):
        add_issue(
            errors,
            severity="error",
            category="sorting",
            word="GLOBAL",
            message="word list is not sorted by casefold()",
        )

    exit_code = 1 if errors else 1 if warnings and args.fail_on_warnings else 0
    payload = build_payload(
        path=path,
        data=data,
        errors=errors,
        warnings=warnings,
        exit_code=exit_code,
    )

    if args.format == "json":
        json.dump(payload, sys.stdout, ensure_ascii=False, indent=2)
        sys.stdout.write("\n")
    else:
        print_text_output(
            path=path,
            data=data,
            errors=errors,
            warnings=warnings,
            max_issues=args.max_issues,
        )
    return exit_code


if __name__ == "__main__":
    sys.exit(main())
