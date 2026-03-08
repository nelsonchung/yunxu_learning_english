#!/usr/bin/env python3
"""Extract the Taiwan HS reference word list and build pdf_word_bank.json.

This script:
1. Parses the "依字母排序" section from the official PDF (6000 entries).
2. Maps POS tags to app enum values.
3. Fills Chinese meanings via machine translation (en -> zh-TW).
4. Generates two bilingual example sentences per word.
5. Preserves existing entries from input JSON, then appends missing words.
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

from pypdf import PdfReader


POS_MAP = {
    "n": "noun",
    "v": "verb",
    "adj": "adjective",
    "adv": "adverb",
    "prep": "preposition",
    "pron": "pronoun",
    "conj": "conjunction",
    "interj": "interjection",
    "aux": "verb",
    "art": "other",
    "det": "other",
    "num": "other",
    "modal": "other",
}

CJK_RE = re.compile(r"[\u4E00-\u9FFF]")
LATIN_RE = re.compile(r"^[A-Za-z][A-Za-z0-9 './()\-]*$")


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--pdf", required=True, help="Path to source PDF")
    parser.add_argument("--input", required=True, help="Input JSON path")
    parser.add_argument("--output", required=True, help="Output JSON path")
    parser.add_argument("--workers", type=int, default=8, help="Translation workers")
    parser.add_argument(
        "--sleep-ms",
        type=int,
        default=25,
        help="Delay per translation call to reduce throttling",
    )
    return parser.parse_args()


def normalize_key(word: str) -> str:
    return re.sub(r"\s+", " ", word.strip().lower())


def normalize_word_display(word: str) -> str:
    text = re.sub(r"^依級別排序\s*第[一二三四五六]級\s+", "", word)
    text = re.sub(r"^依級別排序\s+", "", text)
    text = re.sub(r"^第[一二三四五六]級\s+", "", text)
    text = re.sub(
        r"^(?:n|v|adj|adv|prep|pron|conj|art|aux|interj)\.\s+",
        "",
        text,
        flags=re.IGNORECASE,
    )
    text = re.sub(
        r"\s+(?:n|v|adj|adv|prep|pron|conj|art|aux|interj)\.?$",
        "",
        text,
        flags=re.IGNORECASE,
    )
    text = re.sub(r"\s*/\s*", "/", text)
    text = re.sub(r"\(\s+", "(", text)
    text = re.sub(r"\s+\)", ")", text)
    text = re.sub(r"\s+,", ",", text)
    text = re.sub(r"\s+", " ", text).strip(" .")
    if text == "sportsman/sportswoma":
        text = "sportsman/sportswoman"
    return text


def load_json_loose(path: Path) -> list[dict[str, object]]:
    if not path.exists():
        return []
    raw = path.read_text(encoding="utf-8").strip()
    if not raw:
        return []
    fixed = re.sub(r",\s*]", "\n]", raw)
    data = json.loads(fixed)
    if not isinstance(data, list):
        raise ValueError(f"Input JSON must be a list: {path}")
    out: list[dict[str, object]] = []
    for item in data:
        if isinstance(item, dict):
            out.append(item)
    return out


def read_pdf_pages(pdf_path: Path) -> list[str]:
    if not pdf_path.exists():
        raise FileNotFoundError(f"PDF not found: {pdf_path}")
    reader = PdfReader(str(pdf_path))
    return [(page.extract_text() or "") for page in reader.pages]


def find_level_section_pages(pages: list[str]) -> tuple[int, int]:
    start_page = -1
    alpha_page = -1
    for idx, text in enumerate(pages):
        if start_page < 0 and "第一級" in text and "a/an art." in text and "a/an art. 1" not in text:
            start_page = idx + 1
        if alpha_page < 0 and "a/an art. 1" in text:
            alpha_page = idx + 1
        if start_page > 0 and alpha_page > 0:
            break
    if start_page < 0 or alpha_page < 0 or alpha_page <= start_page:
        raise ValueError(
            "Cannot locate by-level and alphabetical boundaries in PDF pages"
        )
    return start_page, alpha_page - 1


def extract_by_level_entries(pages: list[str]) -> list[tuple[str, str]]:
    start_page, end_page = find_level_section_pages(pages)
    raw_lines: list[str] = []
    for page_no in range(start_page, end_page + 1):
        raw_lines.extend(pages[page_no - 1].splitlines())

    entry_re = re.compile(r"^(?P<word>.+?)\s+(?P<pos>[A-Za-z./()]+)$")
    valid_pos = set(POS_MAP.keys())

    def skip_line(line: str) -> bool:
        text = line.strip()
        if not text:
            return True
        if text.isdigit():
            return True
        if text in {"依級別排序", "高中英文參考詞彙表"}:
            return True
        if re.fullmatch(r"第[一二三四五六]級", text):
            return True
        if re.fullmatch(r"[A-Z]", text):
            return True
        return False

    lines: list[str] = []
    for line in raw_lines:
        text = " ".join(line.strip().split())
        if skip_line(text):
            continue
        lines.append(text)

    parsed: list[tuple[str, str]] = []
    fragment = ""
    for line in lines:
        fragment = (fragment + " " + line).strip() if fragment else line
        match = entry_re.match(fragment)
        if not match:
            continue
        word = normalize_word_display(match.group("word"))
        pos = match.group("pos").strip()
        tokens = [token for token in pos.lower().split("/") if token]
        if not any(token.strip("().") in valid_pos for token in tokens):
            continue
        parsed.append((word, pos))
        fragment = ""

    if len(parsed) < 5000:
        raise ValueError(f"Unexpectedly low parsed entry count: {len(parsed)}")

    seen: set[str] = set()
    unique: list[tuple[str, str]] = []
    for word, pos in parsed:
        key = normalize_key(word)
        if key in seen:
            continue
        seen.add(key)
        unique.append((word, pos))
    return unique


def map_part_of_speech(word: str, raw_pos: str) -> str:
    first = raw_pos.strip().lower()
    first = first.split("/")[0]
    first = first.strip(".")
    first = first.strip("()")
    mapped = POS_MAP.get(first)
    if mapped:
        return mapped
    if " " in word:
        return "phrase"
    return "other"


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
            translated = "".join(part[0] for part in data[0] if part and part[0]).strip()
            if translated:
                if sleep_ms > 0:
                    time.sleep(sleep_ms / 1000.0)
                return translated
        except Exception:
            if attempt < 3:
                time.sleep(0.5 * (attempt + 1))
    return None


def choose_meaning(word: str, translated: str | None) -> str:
    if translated and CJK_RE.search(translated):
        return translated
    if translated and not LATIN_RE.match(translated):
        return translated
    return "（待人工確認）"


def generate_sentences(word: str, meaning: str, part_of_speech: str) -> list[str]:
    if part_of_speech == "verb":
        return [
            f'We practiced how to "{word}" in class today.\n我們今天在課堂上練習了如何「{word}」。',
            f'The teacher asked us to "{word}" in a short dialogue.\n老師要我們在短對話中使用「{word}」。',
        ]
    if part_of_speech == "adjective":
        return [
            f'This is a "{word}" idea for our project.\n這對我們的專案來說是個「{word}」的想法。',
            f'The plan sounds "{word}" and practical.\n這個計畫聽起來「{word}」又實際。',
        ]
    if part_of_speech == "adverb":
        return [
            f'She spoke "{word}" during the presentation.\n她在簡報時說話很「{word}」。',
            f'Please read the instructions "{word}".\n請「{word}」地閱讀說明。',
        ]
    if part_of_speech == "preposition":
        return [
            f'We talked "{word}" the final plan after class.\n下課後我們用「{word}」來討論最終計畫。',
            f'I wrote one sentence with "{word}" in my notebook.\n我在筆記本裡寫了一句包含「{word}」的句子。',
        ]
    if part_of_speech == "pronoun":
        return [
            f'I used "{word}" correctly in the exercise.\n我在練習裡正確使用了「{word}」。',
            f'The dialogue includes "{word}" in the second line.\n那段對話的第二句有用到「{word}」。',
        ]
    if part_of_speech == "conjunction":
        return [
            f'I used "{word}" to connect two clauses.\n我用「{word}」來連接兩個子句。',
            f'Our teacher gave an example sentence with "{word}".\n老師給了一句包含「{word}」的例句。',
        ]
    if part_of_speech == "interjection":
        return [
            f'In spoken English, people may say "{word}" naturally.\n在口說英文中，人們可能會自然說出「{word}」。',
            f'I heard "{word}" in a short conversation.\n我在一段短對話裡聽到「{word}」。',
        ]
    if part_of_speech == "phrase":
        return [
            f'We practiced the phrase "{word}" today.\n我們今天練習了片語「{word}」。',
            f'I can use "{word}" in everyday conversation.\n我可以在日常對話中使用「{word}」。',
        ]
    return [
        f'I learned the word "{word}" today.\n我今天學了「{word}」這個單字。',
        f'The meaning of "{word}" is "{meaning}".\n「{word}」的意思是「{meaning}」。',
    ]


def main() -> int:
    args = parse_args()
    pdf_path = Path(args.pdf)
    input_path = Path(args.input)
    output_path = Path(args.output)

    existing = load_json_loose(input_path)
    existing_by_key = {
        normalize_key(str(item.get("word", ""))): item
        for item in existing
        if str(item.get("word", "")).strip()
    }

    pages = read_pdf_pages(pdf_path)
    extracted = extract_by_level_entries(pages)
    print(f"parsed entries from PDF: {len(extracted)}")

    extracted_keys = {normalize_key(word) for word, _ in extracted}
    custom_entries: list[dict[str, object]] = []
    for item in existing:
        key = normalize_key(str(item.get("word", "")))
        if key and key not in extracted_keys:
            custom_entries.append(item)

    new_words: list[str] = []
    for word, _ in extracted:
        key = normalize_key(word)
        current = existing_by_key.get(key)
        meaning = str((current or {}).get("meaning", "")).strip()
        if not meaning:
            new_words.append(word)

    print(f"new words to append: {len(new_words)}")

    translated_map: dict[str, str] = {}
    if new_words:
        with ThreadPoolExecutor(max_workers=max(1, args.workers)) as executor:
            future_to_word = {
                executor.submit(translate_to_zh_tw, word, args.sleep_ms): word
                for word in new_words
            }
            done = 0
            total = len(future_to_word)
            for future in as_completed(future_to_word):
                word = future_to_word[future]
                translated_map[word] = choose_meaning(word, future.result())
                done += 1
                if done % 200 == 0 or done == total:
                    print(f"translation progress: {done}/{total}")

    output_entries: list[dict[str, object]] = []
    output_entries.extend(custom_entries)

    for word, raw_pos in extracted:
        key = normalize_key(word)
        part = map_part_of_speech(word, raw_pos)
        current = existing_by_key.get(key)
        meaning = str((current or {}).get("meaning", "")).strip()
        if not meaning:
            meaning = translated_map.get(word, "（待人工確認）")
        sentences_raw = (current or {}).get("sentences")
        parsed_sentences: list[str] = []
        if isinstance(sentences_raw, list):
            parsed_sentences = [
                str(item).strip()
                for item in sentences_raw
                if str(item).strip()
            ][:2]
        if len(parsed_sentences) < 2:
            parsed_sentences = generate_sentences(word, meaning, part)

        output_entries.append(
            {
                "word": word,
                "meaning": meaning,
                "partOfSpeech": part,
                "sentences": parsed_sentences,
            }
        )

    output_path.parent.mkdir(parents=True, exist_ok=True)
    output_path.write_text(
        json.dumps(output_entries, ensure_ascii=False, indent=2),
        encoding="utf-8",
    )

    print(f"total output entries: {len(output_entries)}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
