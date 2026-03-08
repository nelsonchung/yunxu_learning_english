#!/usr/bin/env python3
import argparse
import json
import re
import sys
import urllib.parse
from collections import Counter
from pathlib import Path
from concurrent.futures import ThreadPoolExecutor, as_completed

CURRENT_DIR = Path(__file__).resolve().parent
if str(CURRENT_DIR) not in sys.path:
    sys.path.insert(0, str(CURRENT_DIR))

from repair_html_polluted_word_bank_entries import (
    WIKTIONARY_POS_TO_BANK,
    clean_markup,
    fetch_json,
)


ROOT = Path(__file__).resolve().parents[1]
WORD_BANK_PATH = ROOT / "assets" / "word_bank" / "word_bank_main.json"
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
POS_TOKEN_MAP = {
    "interjection": "exclamation",
    "auxiliary verb": "verb",
    "number": "determiner",
    "other": "determiner",
}


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser()
    parser.add_argument("--write", action="store_true")
    parser.add_argument("--limit", type=int)
    parser.add_argument("--workers", type=int, default=12)
    parser.add_argument("--skip-dictionary", action="store_true")
    return parser.parse_args()


def normalize_sentence(sentence: str) -> str:
    sentence = sentence.replace("\\n", "\n")
    parts = [clean_markup(part) for part in sentence.split("\n")]
    parts = [part for part in parts if part]
    return " ".join(parts).strip()


def normalize_text(text: str) -> str:
    return clean_markup(text.replace("\\n", " ").replace("\n", " "))


def map_pos_tokens(raw_pos: str) -> list[str]:
    if raw_pos == "phrase":
        return ["noun"]
    tokens = []
    for token in raw_pos.split("/"):
        token = token.strip().lower()
        if not token:
            continue
        token = POS_TOKEN_MAP.get(token, token)
        tokens.append(token)
    unique = []
    for token in tokens:
        if token not in unique:
            unique.append(token)
    return unique


def get_wiktionary_pos(word: str) -> list[str]:
    try:
        data = fetch_json(
            "https://en.wiktionary.org/api/rest_v1/page/definition/" + urllib.parse.quote(word)
        )
    except Exception:
        return []
    result = []
    for entry in data.get("en", []):
        bank_pos = WIKTIONARY_POS_TO_BANK.get(entry.get("partOfSpeech"))
        if bank_pos and bank_pos not in result:
            result.append(bank_pos)
    return result


def canonicalize_pos(word: str, raw_pos: str, skip_dictionary: bool = False) -> tuple[str, str]:
    if raw_pos in ALLOWED_POS:
        return raw_pos, "already-allowed"

    mapped = map_pos_tokens(raw_pos)
    allowed_mapped = [token for token in mapped if token in ALLOWED_POS]
    if len(allowed_mapped) == 1:
        return allowed_mapped[0], f"direct-map:{raw_pos}"

    if raw_pos == "phrase":
        return "noun", "phrase->noun"

    if skip_dictionary:
        if allowed_mapped:
            return allowed_mapped[0], f"fallback-first:{raw_pos}"
        return raw_pos, f"unchanged:{raw_pos}"

    wiktionary_pos = get_wiktionary_pos(word)
    for token in allowed_mapped:
        if token in wiktionary_pos:
            return token, f"wiktionary-match:{raw_pos}"

    if allowed_mapped:
        return allowed_mapped[0], f"fallback-first:{raw_pos}"

    if wiktionary_pos:
        return wiktionary_pos[0], f"wiktionary-first:{raw_pos}"

    return raw_pos, f"unchanged:{raw_pos}"


def main() -> None:
    args = parse_args()
    with WORD_BANK_PATH.open(encoding="utf-8") as file:
        data = json.load(file)

    items = data if args.limit is None else data[: args.limit]
    newline_fixed = 0
    meaning_newline_fixed = 0
    pos_stats = Counter()
    legacy_indexes = []

    for item in items:
        original_meaning = item.get("meaning", "")
        normalized_meaning = normalize_text(original_meaning)
        if normalized_meaning != original_meaning:
            item["meaning"] = normalized_meaning
            meaning_newline_fixed += 1

        new_sentences = []
        for sentence in item.get("sentences", []):
            normalized_sentence = normalize_sentence(sentence)
            if normalized_sentence != sentence:
                newline_fixed += 1
            new_sentences.append(normalized_sentence)
        item["sentences"] = new_sentences

        original_pos = item.get("partOfSpeech")
        if original_pos not in ALLOWED_POS:
            legacy_indexes.append((item["word"], original_pos, item))

    direct_only = []
    need_lookup = []
    for word, original_pos, item in legacy_indexes:
        raw_mapped = map_pos_tokens(original_pos)
        if original_pos == "phrase" or len([token for token in raw_mapped if token in ALLOWED_POS]) <= 1:
            direct_only.append((word, original_pos, item))
        else:
            need_lookup.append((word, original_pos, item))

    for word, original_pos, item in direct_only:
        new_pos, reason = canonicalize_pos(word, original_pos, skip_dictionary=True)
        if new_pos != original_pos:
            item["partOfSpeech"] = new_pos
            pos_stats[reason] += 1

    if args.skip_dictionary:
        lookup_results = []
    else:
        lookup_results = []
        with ThreadPoolExecutor(max_workers=args.workers) as executor:
            future_map = {
                executor.submit(canonicalize_pos, word, original_pos, False): (word, original_pos, item)
                for word, original_pos, item in need_lookup
            }
            for future in as_completed(future_map):
                word, original_pos, item = future_map[future]
                new_pos, reason = future.result()
                lookup_results.append((item, original_pos, new_pos, reason))

    for item, original_pos, new_pos, reason in lookup_results:
        if new_pos != original_pos:
            item["partOfSpeech"] = new_pos
            pos_stats[reason] += 1

    if args.write:
        with WORD_BANK_PATH.open("w", encoding="utf-8") as file:
            json.dump(data, file, ensure_ascii=False, indent=2)
            file.write("\n")

    print(f"sentence_newlines_fixed={newline_fixed}")
    print(f"meaning_newlines_fixed={meaning_newline_fixed}")
    print(f"pos_fixed_total={sum(pos_stats.values())}")
    print("pos_fix_breakdown")
    for reason, count in pos_stats.most_common():
        print(f"{count}\t{reason}")


if __name__ == "__main__":
    main()
