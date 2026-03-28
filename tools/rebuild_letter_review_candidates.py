#!/usr/bin/env python3
import argparse
import json
from collections import Counter
from pathlib import Path
from concurrent.futures import ThreadPoolExecutor

from run_l_kaikki_completion import build_entry, sort_entries
from sync_letter_word_bank_progress import write_json
from tag_word_bank_audiences import (
    DEFAULT_EXAM_BOOK_WORDS,
    DEFAULT_HS_PDF,
    load_exam_book_words,
    parse_hs_levels,
)


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(
        description="Rebuild reviewed word-bank entries using the Kaikki completion generator."
    )
    parser.add_argument("--review-json", type=Path, required=True)
    parser.add_argument("--target", type=Path, required=True)
    parser.add_argument("--summary-json", type=Path, required=True)
    parser.add_argument("--prefix")
    parser.add_argument("--workers", type=int, default=8)
    parser.add_argument("--hs-pdf", type=Path, default=DEFAULT_HS_PDF)
    parser.add_argument("--exam-book-words", type=Path, default=DEFAULT_EXAM_BOOK_WORDS)
    return parser.parse_args()


def load_json(path: Path):
    with path.open(encoding="utf-8") as file:
        return json.load(file)


def main() -> int:
    args = parse_args()
    review_payload = load_json(args.review_json)
    prefix = args.prefix.casefold() if args.prefix else None
    candidate_words = []
    for candidate in review_payload.get("candidates", []):
        word = candidate.get("word")
        if not isinstance(word, str) or not word:
            continue
        if prefix and not word.casefold().startswith(prefix):
            continue
        if word not in candidate_words:
            candidate_words.append(word)

    hs_levels = parse_hs_levels(args.hs_pdf)
    exam_book_words = load_exam_book_words(args.exam_book_words)

    with ThreadPoolExecutor(max_workers=args.workers) as executor:
        built = list(executor.map(lambda word: build_entry(word, hs_levels, exam_book_words), candidate_words))

    replacement_map = {entry["word"]: entry for entry, _source, _confidence in built}
    existing_entries = sort_entries(load_json(args.target))
    merged_entries = []
    replaced_words = set()
    for entry in existing_entries:
        word = entry.get("word")
        if word in replacement_map:
            merged_entries.append(replacement_map[word])
            replaced_words.add(word)
        else:
            merged_entries.append(entry)

    for word in candidate_words:
        if word not in replaced_words and word in replacement_map:
            merged_entries.append(replacement_map[word])

    merged_entries = sort_entries(merged_entries)
    write_json(args.target, merged_entries)

    source_counts = Counter(source for _entry, source, _confidence in built)
    confidence_counts = Counter(confidence for _entry, _source, confidence in built)
    summary = {
        "wordCount": len(candidate_words),
        "sourceCounts": dict(source_counts),
        "confidenceCounts": dict(confidence_counts),
    }
    write_json(args.summary_json, summary)
    print(json.dumps(summary, ensure_ascii=False, indent=2))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
