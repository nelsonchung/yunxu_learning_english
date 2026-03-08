#!/usr/bin/env python3
"""Review and enrich pdf_word_bank.json with missing meanings and bilingual sentences.

What this script does:
1. Fill missing `meaning` values.
   - First try to reuse meanings from existing entries by normalized/derived forms.
   - Then fallback to machine translation (English -> Traditional Chinese).
2. Replace `sentences` with two bilingual examples (English + Chinese).

Usage:
  python3 tools/enrich_pdf_word_bank.py \
    --input assets/word_bank/pdf_word_bank.json \
    --output assets/word_bank/pdf_word_bank.json
"""

from __future__ import annotations

import argparse
import json
import re
import time
import urllib.parse
import urllib.request
from concurrent.futures import ThreadPoolExecutor, as_completed
from pathlib import Path


PLACEHOLDER_MEANINGS = {
    "（PDF提及，待補中文）",
    "(PDF提及，待補中文)",
    "PDF提及，待補中文",
    "",
}

CJK_RE = re.compile(r"[\u4E00-\u9FFF]")
LATIN_RE = re.compile(r"^[A-Za-z][A-Za-z0-9 './-]*$")


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--input", required=True, help="Input JSON path")
    parser.add_argument("--output", required=True, help="Output JSON path")
    parser.add_argument(
        "--workers",
        type=int,
        default=6,
        help="Number of translation workers (default: 6)",
    )
    parser.add_argument(
        "--sleep-ms",
        type=int,
        default=30,
        help="Small delay between requests per worker to reduce rate limiting",
    )
    return parser.parse_args()


def normalize_word(word: str) -> str:
    return re.sub(r"\s+", " ", word.strip().lower())


def strip_word_key(word: str) -> str:
    return re.sub(r"[^a-z]", "", word.lower())


def derive_variants(word: str) -> list[str]:
    lowered = normalize_word(word)
    stripped = strip_word_key(lowered)
    variants = {lowered, stripped}

    def add_form(form: str) -> None:
        if form:
            variants.add(form)
            variants.add(strip_word_key(form))

    if stripped.endswith("ies") and len(stripped) > 4:
        add_form(stripped[:-3] + "y")
    if stripped.endswith("es") and len(stripped) > 3:
        add_form(stripped[:-2])
    if stripped.endswith("s") and len(stripped) > 3:
        add_form(stripped[:-1])
    if stripped.endswith("ing") and len(stripped) > 5:
        add_form(stripped[:-3])
        add_form(stripped[:-3] + "e")
    if stripped.endswith("ed") and len(stripped) > 4:
        add_form(stripped[:-2])
        add_form(stripped[:-1])
    if stripped.endswith("er") and len(stripped) > 4:
        add_form(stripped[:-2])
    if stripped.endswith("est") and len(stripped) > 5:
        add_form(stripped[:-3])

    return [item for item in variants if item]


def is_missing_meaning(value: object) -> bool:
    text = str(value or "").strip()
    return text in PLACEHOLDER_MEANINGS


def translate_to_zh_tw(word: str, sleep_ms: int) -> str | None:
    url = (
        "https://translate.googleapis.com/translate_a/single"
        f"?client=gtx&sl=en&tl=zh-TW&dt=t&q={urllib.parse.quote(word)}"
    )
    for attempt in range(4):
        try:
            with urllib.request.urlopen(url, timeout=15) as response:
                payload = response.read().decode("utf-8")
            data = json.loads(payload)
            translated = "".join(part[0] for part in data[0] if part and part[0])
            translated = translated.strip()
            if translated:
                if sleep_ms > 0:
                    time.sleep(sleep_ms / 1000.0)
                return translated
        except Exception:
            if attempt < 3:
                time.sleep(0.5 * (attempt + 1))
            continue
    return None


def choose_meaning(word: str, translated: str | None) -> str:
    if translated and CJK_RE.search(translated):
        return translated
    if translated and not LATIN_RE.match(translated):
        return translated
    return "（疑似OCR詞，待人工確認）"


def build_bilingual_sentences(word: str, meaning: str) -> list[str]:
    safe_word = word.replace('"', "'").strip()
    safe_meaning = meaning.replace('"', "'").strip()
    sentence_1 = (
        f'I reviewed the word "{safe_word}" today.\n'
        f'我今天複習了「{safe_word}」這個單字。'
    )
    sentence_2 = (
        f'The meaning of "{safe_word}" is "{safe_meaning}".\n'
        f'「{safe_word}」的意思是「{safe_meaning}」。'
    )
    return [sentence_1, sentence_2]


def main() -> int:
    args = parse_args()
    input_path = Path(args.input)
    output_path = Path(args.output)
    if not input_path.exists():
        raise FileNotFoundError(f"Input file not found: {input_path}")
    if args.workers <= 0:
        raise ValueError("--workers must be positive")

    data = json.loads(input_path.read_text(encoding="utf-8"))
    if not isinstance(data, list):
        raise ValueError("Input JSON must be a list")

    known_map: dict[str, str] = {}
    for item in data:
        if not isinstance(item, dict):
            continue
        word = normalize_word(str(item.get("word", "")))
        meaning = str(item.get("meaning", "")).strip()
        if not word or is_missing_meaning(meaning):
            continue
        for key in derive_variants(word):
            known_map.setdefault(key, meaning)

    translate_targets: dict[str, str] = {}
    reused_count = 0
    for item in data:
        if not isinstance(item, dict):
            continue
        word = str(item.get("word", "")).strip()
        if not word or not is_missing_meaning(item.get("meaning")):
            continue

        found = None
        for key in derive_variants(word):
            if key in known_map:
                found = known_map[key]
                break
        if found:
            item["meaning"] = found
            reused_count += 1
        else:
            translate_targets[word] = word

    translated_map: dict[str, str] = {}
    if translate_targets:
        with ThreadPoolExecutor(max_workers=args.workers) as executor:
            future_to_word = {
                executor.submit(translate_to_zh_tw, word, args.sleep_ms): word
                for word in translate_targets
            }
            completed = 0
            total = len(future_to_word)
            for future in as_completed(future_to_word):
                word = future_to_word[future]
                result = future.result()
                translated_map[word] = choose_meaning(word, result)
                completed += 1
                if completed % 200 == 0 or completed == total:
                    print(f"translation progress: {completed}/{total}")

    translated_count = 0
    unresolved_count = 0
    for item in data:
        if not isinstance(item, dict):
            continue
        word = str(item.get("word", "")).strip()
        if not word:
            continue

        if is_missing_meaning(item.get("meaning")):
            meaning = translated_map.get(word, "（疑似OCR詞，待人工確認）")
            item["meaning"] = meaning
            if meaning == "（疑似OCR詞，待人工確認）":
                unresolved_count += 1
            else:
                translated_count += 1

        item["sentences"] = build_bilingual_sentences(
            word=word,
            meaning=str(item.get("meaning", "")).strip() or "（待確認）",
        )

    output_path.parent.mkdir(parents=True, exist_ok=True)
    output_path.write_text(
        json.dumps(data, ensure_ascii=False, indent=2),
        encoding="utf-8",
    )

    total = len(data)
    print(f"total entries: {total}")
    print(f"reused meanings from known map: {reused_count}")
    print(f"translated meanings: {translated_count}")
    print(f"unresolved meanings: {unresolved_count}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
