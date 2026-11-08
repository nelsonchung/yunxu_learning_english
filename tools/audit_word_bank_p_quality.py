#!/usr/bin/env python3
"""Audit word_bank_main-p.json for prompt-polluted meanings and weak examples."""

from __future__ import annotations

import argparse
import csv
import json
import os
import re
import sys
from collections import Counter
from datetime import datetime, timezone
from pathlib import Path
from typing import Any


ROOT = Path(__file__).resolve().parents[1]
DEFAULT_PATH = ROOT / "assets" / "word_bank" / "word_bank_main-p.json"
DEFAULT_OUTPUT_DIR = ROOT / "logs" / "word_bank_p_quality_audit" / "latest"


MEANING_RULES: list[tuple[str, re.Pattern[str], int]] = [
    (
        "placeholder_meaning",
        re.compile(
            r"rare or specialized English term recorded as|"
            r"(?:罕見|罕见).{0,12}(?:專門|专门|專業|专业).{0,8}(?:英語|英语|英文)(?:術語|术语)|"
            r"(?:記錄為|记录为).{0,24}(?:罕見|罕见|專門|专门|專業|专业).{0,8}(?:英語|英语|英文)(?:術語|术语)|"
            r"(?:記錄為|记录为)\s*[A-Za-z]",
            re.IGNORECASE,
        ),
        5,
    ),
    (
        "meaning_prompt_pollution",
        re.compile(r"How to use .+ in a sentence|如何在句子中使用.{0,80}|如何(?:使用|用).{0,40}造句|關於.{0,40}常見問題", re.IGNORECASE),
        5,
    ),
    (
        "meaning_web_noise",
        re.compile(r"Learn definitions, uses, and phrases|Synonym Discussion|Merriam-Webster Dictionary|韋氏字典|學習定義|学习定义|同義詞討論|同義字討論", re.IGNORECASE),
        4,
    ),
    (
        "meaning_template_phrase",
        re.compile(r"作者(?:使用|將)|作家(?:使用|用|們用)|\bWriters use\b|這句話與", re.IGNORECASE),
        4,
    ),
]


SENTENCE_RULES: list[tuple[str, re.Pattern[str], int]] = [
    ("template_writers_use", re.compile(r"^Writers use .+ (?:for|to mean|to describe)", re.IGNORECASE), 5),
    ("template_older_books", re.compile(r"^The word .+ still appears in older books and notes\.", re.IGNORECASE), 5),
    ("template_report_sample", re.compile(r"^In the report, the sample looked .+ to the researchers\.", re.IGNORECASE), 4),
    ("template_lesson", re.compile(r"^(?:We learned the meaning of|The lesson introduced|We discussed the term) ", re.IGNORECASE), 4),
    ("template_explainer", re.compile(r"^(?:The note explained|The article explained|The textbook defined) ", re.IGNORECASE), 3),
    ("sentence_prompt_pollution", re.compile(r"How to use .+ in a sentence|如何在句子中使用.{0,80}|如何(?:使用|用).{0,40}造句|關於.{0,40}常見問題", re.IGNORECASE), 5),
    (
        "sentence_placeholder_text",
        re.compile(
            r"rare or specialized English term recorded as|"
            r"(?:罕見|罕见).{0,12}(?:專門|专门|專業|专业).{0,8}(?:英語|英语|英文)(?:術語|术语)|"
            r"(?:記錄為|记录为).{0,24}(?:罕見|罕见|專門|专门|專業|专业).{0,8}(?:英語|英语|英文)(?:術語|术语)",
            re.IGNORECASE,
        ),
        5,
    ),
    ("sentence_author_template_zh", re.compile(r"作者(?:使用|將)|作家(?:使用|用|們用).{0,80}(?:表示|描述|形容|記錄為)"), 4),
    ("generic_adverb_template", re.compile(r"^(?:She responded|The report says the movement happened|She adjusted the sample) ", re.IGNORECASE), 3),
]


BAD_TRANSLATION_MARKERS: list[tuple[str, str, int]] = [
    ("。。", "double_chinese_period", 3),
    ("這個字仍然出現在較舊", "older_books_translation", 4),
    ("這個詞仍然出現在較舊", "older_books_translation", 4),
    ("用上了這個副詞", "meta_adverb_translation", 3),
    ("如何在句子中使用", "translation_prompt_pollution", 5),
    ("如何使用", "translation_prompt_pollution", 4),
]


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(
        description="Audit p-letter word bank entries for content quality issues."
    )
    parser.add_argument("--path", default=str(DEFAULT_PATH), help="Path to word_bank_main-p.json.")
    parser.add_argument(
        "--output-dir",
        default=str(DEFAULT_OUTPUT_DIR),
        help="Directory where JSON/CSV/Markdown audit reports are written.",
    )
    parser.add_argument("--min-score", type=int, default=3, help="Minimum score to include.")
    parser.add_argument("--limit", type=int, default=50, help="Rows to show in text output.")
    parser.add_argument(
        "--format",
        choices=("text", "json", "md"),
        default="text",
        help="Stdout format.",
    )
    return parser.parse_args()


def repo_path(raw_path: str) -> Path:
    path = Path(raw_path)
    return path if path.is_absolute() else ROOT / path


def current_timestamp() -> str:
    return datetime.now(timezone.utc).isoformat(timespec="seconds").replace("+00:00", "Z")


def write_json(path: Path, payload: Any) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    temp_path = path.with_name(f".{path.name}.tmp")
    with temp_path.open("w", encoding="utf-8") as file:
        json.dump(payload, file, ensure_ascii=False, indent=2)
        file.write("\n")
    os.replace(temp_path, path)


def write_text(path: Path, text: str) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    temp_path = path.with_name(f".{path.name}.tmp")
    temp_path.write_text(text, encoding="utf-8")
    os.replace(temp_path, path)


def split_bilingual_sentence(sentence: str) -> tuple[str, str]:
    for index, char in enumerate(sentence):
        if "\u4e00" <= char <= "\u9fff":
            start = index
            while start > 0 and sentence[start - 1].isspace():
                start -= 1
            return sentence[:start].strip(), sentence[start:].strip()
    return sentence.strip(), ""


def has_cjk(text: str) -> bool:
    return any("\u4e00" <= char <= "\u9fff" for char in text)


def has_ascii_letter(text: str) -> bool:
    return any(char.isascii() and char.isalpha() for char in text)


def line_numbers_for_entries(path: Path) -> list[int | None]:
    numbers: list[int] = []
    word_line_re = re.compile(r'^\s*"word"\s*:')
    with path.open(encoding="utf-8") as file:
        for line_number, line in enumerate(file, start=1):
            if word_line_re.search(line):
                numbers.append(line_number)
    return numbers


def sentence_quality_reasons(word: str, sentence: str, sentence_index: int) -> list[tuple[str, int]]:
    reasons: list[tuple[str, int]] = []
    english_half, translation_half = split_bilingual_sentence(sentence)

    for reason, pattern, weight in SENTENCE_RULES:
        if pattern.search(sentence) or pattern.search(english_half):
            reasons.append((f"{reason}:s{sentence_index}", weight))

    for marker, reason, weight in BAD_TRANSLATION_MARKERS:
        if marker in sentence:
            reasons.append((f"{reason}:s{sentence_index}", weight))

    if not english_half or not translation_half:
        reasons.append((f"missing_bilingual_half:s{sentence_index}", 3))
    elif not has_ascii_letter(english_half) or not has_cjk(translation_half):
        reasons.append((f"weak_bilingual_shape:s{sentence_index}", 2))

    if len(word) > 1 and translation_half and re.search(
        rf"(?<![A-Za-z]){re.escape(word)}(?![A-Za-z])",
        translation_half,
        re.IGNORECASE,
    ):
        reasons.append((f"untranslated_word_in_translation:s{sentence_index}", 2))

    if english_half and english_half[0].isascii() and english_half[0].islower():
        reasons.append((f"sentence_fragment_style:s{sentence_index}", 1))

    if len(sentence) > 280:
        reasons.append((f"sentence_too_long:s{sentence_index}", 2))

    return reasons


def review_entry(index: int, line_number: int | None, entry: dict[str, Any]) -> dict[str, Any] | None:
    word = str(entry.get("word", ""))
    meaning = str(entry.get("meaning", ""))
    sentences = entry.get("sentences") or []
    reasons: list[str] = []
    score = 0

    for reason, pattern, weight in MEANING_RULES:
        if pattern.search(meaning):
            reasons.append(reason)
            score += weight

    if "。" in meaning and "。" in meaning.rstrip("。"):
        reasons.append("meaning_multi_sentence_or_noise")
        score += 1

    if "。。" in meaning:
        reasons.append("meaning_double_chinese_period")
        score += 3

    if len(meaning) > 80:
        reasons.append("meaning_too_long")
        score += 1

    if len(word) > 1 and has_cjk(meaning) and re.search(
        rf"(?<![A-Za-z]){re.escape(word)}(?![A-Za-z])",
        meaning,
        re.IGNORECASE,
    ):
        reasons.append("meaning_untranslated_word")
        score += 4

    if not isinstance(sentences, list) or len(sentences) != 2:
        reasons.append("invalid_sentence_count")
        score += 5
    else:
        for sentence_index, sentence in enumerate(sentences, start=1):
            for reason, weight in sentence_quality_reasons(word, str(sentence), sentence_index):
                reasons.append(reason)
                score += weight

    if not reasons:
        return None

    return {
        "index": index,
        "line": line_number,
        "word": word,
        "score": score,
        "reasons": reasons,
        "reasonCounts": dict(Counter(reason.split(":")[0] for reason in reasons).most_common()),
        "meaning": meaning,
        "partOfSpeech": entry.get("partOfSpeech", ""),
        "sentences": sentences,
    }


def build_markdown(payload: dict[str, Any]) -> str:
    lines = [
        "# word_bank_main-p.json Quality Audit",
        "",
        f"- GeneratedAt: {payload['generatedAt']}",
        f"- Path: `{payload['path']}`",
        f"- Entries: {payload['entryCount']}",
        f"- Candidates: {payload['candidateCount']}",
        f"- MinScore: {payload['minScore']}",
        "",
        "## Reason Counts",
        "",
    ]
    for reason, count in payload["reasonCounts"].items():
        lines.append(f"- `{reason}`: {count}")
    lines.extend(["", "## Top Candidates", ""])
    for item in payload["candidates"][:50]:
        line = item["line"] if item["line"] is not None else "?"
        lines.append(
            f"- score={item['score']} line={line} word=`{item['word']}` "
            f"reasons={', '.join(item['reasons'][:6])}"
        )
    return "\n".join(lines) + "\n"


def write_csv(path: Path, candidates: list[dict[str, Any]]) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    temp_path = path.with_name(f".{path.name}.tmp")
    with temp_path.open("w", encoding="utf-8", newline="") as file:
        writer = csv.DictWriter(
            file,
            fieldnames=[
                "index",
                "line",
                "word",
                "score",
                "reasons",
                "partOfSpeech",
                "meaning",
                "sentence1",
                "sentence2",
            ],
        )
        writer.writeheader()
        for item in candidates:
            sentences = item.get("sentences") or []
            writer.writerow(
                {
                    "index": item["index"],
                    "line": item["line"],
                    "word": item["word"],
                    "score": item["score"],
                    "reasons": ";".join(item["reasons"]),
                    "partOfSpeech": item.get("partOfSpeech", ""),
                    "meaning": item.get("meaning", ""),
                    "sentence1": sentences[0] if len(sentences) > 0 else "",
                    "sentence2": sentences[1] if len(sentences) > 1 else "",
                }
            )
    os.replace(temp_path, path)


def main() -> int:
    args = parse_args()
    path = repo_path(args.path)
    output_dir = repo_path(args.output_dir)

    with path.open(encoding="utf-8") as file:
        data = json.load(file)
    if not isinstance(data, list):
        raise ValueError(f"{path} must contain a JSON array")

    line_numbers = line_numbers_for_entries(path)
    candidates = []
    reason_counts: Counter[str] = Counter()
    for index, entry in enumerate(data):
        line_number = line_numbers[index] if index < len(line_numbers) else None
        reviewed = review_entry(index, line_number, entry)
        if reviewed is None or reviewed["score"] < args.min_score:
            continue
        candidates.append(reviewed)
        for reason in reviewed["reasons"]:
            reason_counts[reason.split(":")[0]] += 1

    candidates.sort(key=lambda item: (-item["score"], item["index"]))
    payload = {
        "generatedAt": current_timestamp(),
        "path": str(path),
        "file": path.name,
        "entryCount": len(data),
        "candidateCount": len(candidates),
        "minScore": args.min_score,
        "reasonCounts": dict(reason_counts.most_common()),
        "candidates": candidates,
    }

    write_json(output_dir / "audit.json", payload)
    write_text(output_dir / "audit.md", build_markdown(payload))
    write_csv(output_dir / "candidates.csv", candidates)

    if args.format == "json":
        json.dump(payload, sys.stdout, ensure_ascii=False, indent=2)
        sys.stdout.write("\n")
    elif args.format == "md":
        sys.stdout.write(build_markdown(payload))
    else:
        print(f"Entries: {len(data)}")
        print(f"Candidates: {len(candidates)}")
        print("Reason counts:")
        for reason, count in reason_counts.most_common():
            print(f"- {reason}: {count}")
        print("")
        for item in candidates[: args.limit]:
            print(
                f"score={item['score']} line={item['line']} "
                f"word={item['word']} reasons={', '.join(item['reasons'])}"
            )
    return 0


if __name__ == "__main__":
    sys.exit(main())
