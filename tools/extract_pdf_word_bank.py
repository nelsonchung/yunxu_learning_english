#!/usr/bin/env python3
"""Extract a structured word bank from the scanned PDF dictionary.

Output schema:
[
  {
    "word": "coat",
    "meaning": "外套",
    "partOfSpeech": "noun",
    "sentences": ["...", "..."],
    "sourcePage": 120
  }
]
"""

from __future__ import annotations

import argparse
import json
import re
import subprocess
import sys
import tempfile
from concurrent.futures import ThreadPoolExecutor, as_completed
from dataclasses import dataclass
from pathlib import Path
from typing import Iterable


ENTRY_WORD_RE = re.compile(
    r"([A-Za-z][A-Za-z'\-]*(?:\s+[A-Za-z][A-Za-z'\-]*){0,4})\s*$"
)
BRACKET_RE = re.compile(r"\[[^\]]{2,28}\]")
CJK_RE = re.compile(r"[\u3400-\u4DBF\u4E00-\u9FFF]")
VALID_WORD_RE = re.compile(r"^[A-Za-z][A-Za-z'\- ]*[A-Za-z]$")
NOISE_TOKEN_RE = re.compile(r"^[A-Z]{2,5}$")
COMMON_LEADING_WORDS = {"a", "an", "the", "as", "to"}
COMMON_SHORT_WORDS = {"i", "in", "on", "at", "by", "up", "of", "or"}


@dataclass
class Entry:
    word: str
    meaning: str
    part_of_speech: str
    sentences: list[str]
    source_page: int

    def to_json(self) -> dict[str, object]:
        return {
            "word": self.word,
            "meaning": self.meaning,
            "partOfSpeech": self.part_of_speech,
            "sentences": self.sentences,
            "sourcePage": self.source_page,
        }


def ensure_binary(name: str) -> None:
    if not shutil_which(name):
        raise RuntimeError(f"Required binary not found in PATH: {name}")


def shutil_which(name: str) -> str | None:
    return subprocess.run(
        ["/usr/bin/env", "bash", "-lc", f"command -v {name}"],
        capture_output=True,
        text=True,
        check=False,
    ).stdout.strip() or None


def normalize_spaces(text: str) -> str:
    return re.sub(r"\s+", " ", text).strip()


def normalize_word(raw: str) -> str:
    text = raw.strip(" \t\n\r\f\v|_.,;:!?*()[]{}<>+=~`\"“”‘’")
    text = normalize_spaces(text)
    tokens = text.split(" ")
    while len(tokens) > 1:
        first = tokens[0]
        first_lower = first.lower()
        if first_lower in COMMON_LEADING_WORDS:
            tokens = tokens[1:]
            continue
        if len(first_lower) <= 2 and first_lower not in COMMON_SHORT_WORDS:
            tokens = tokens[1:]
            continue
        if NOISE_TOKEN_RE.match(first):
            tokens = tokens[1:]
            continue
        if len(first) <= 3 and any(ch.isupper() for ch in first):
            tokens = tokens[1:]
            continue
        break
    return " ".join(tokens).strip()


def clean_meaning(raw: str) -> str:
    text = normalize_spaces(raw)
    text = re.sub(r"\s+[|]?\d{1,3}\s*$", "", text)
    text = text.split(";", 1)[0]
    text = re.sub(r"[A-Za-z\[\]`'\"].*$", "", text)
    text = text.strip(" \t\n\r\f\v|_.,;:!?*()[]{}<>+=~`\"")
    return normalize_spaces(text)


def is_valid_word(word: str) -> bool:
    if len(word) < 2 or len(word) > 48:
        return False
    if not VALID_WORD_RE.match(word):
        return False
    if word.lower().startswith(("e.g", "ps", "www")):
        return False
    return True


def infer_part_of_speech(word: str, pos_hint_raw: str) -> str:
    hint = re.sub(r"[^a-z]", "", pos_hint_raw.lower())
    lowered = word.lower()

    if " " in lowered:
        return "phrase"
    if "pron" in hint:
        return "pronoun"
    if "conj" in hint:
        return "conjunction"
    if "interj" in hint:
        return "interjection"
    if "prep" in hint:
        return "preposition"
    if "adv" in hint:
        return "adverb"
    if hint in {"v", "vt", "vi", "verb"} or "verb" in hint:
        return "verb"
    if hint in {"adj", "a", "s"} or "adjective" in hint:
        return "adjective"
    if hint in {"n", "noun", "c", "u", "cn", "un"} or "noun" in hint:
        return "noun"

    if lowered.endswith("ly"):
        return "adverb"
    if lowered.endswith(("ing", "ed", "en", "ize", "ise", "fy")):
        return "verb"
    if lowered.endswith(
        ("ous", "ful", "able", "ible", "al", "ive", "ic", "less", "ish", "ary")
    ):
        return "adjective"
    return "noun"


def generate_sentences(word: str, part_of_speech: str) -> list[str]:
    if part_of_speech == "verb":
        return [
            f"I practiced the verb \"{word}\" in a short sentence today.",
            f"Our teacher asked us to review \"{word}\" before tomorrow's quiz.",
        ]
    if part_of_speech == "adjective":
        return [
            f"I used the adjective \"{word}\" to describe a class activity.",
            f"We reviewed \"{word}\" with two example phrases in class.",
        ]
    if part_of_speech == "adverb":
        return [
            f"I added the adverb \"{word}\" to my notes this morning.",
            f"Our group practiced \"{word}\" in a speaking drill today.",
        ]
    if part_of_speech == "phrase":
        return [
            f"I practiced the phrase \"{word}\" in today's speaking exercise.",
            f"Our group used \"{word}\" in a short dialogue.",
        ]
    return [
        f"I added \"{word}\" to my vocabulary notebook today.",
        f"She reviewed \"{word}\" twice before going to bed.",
    ]


def parse_line(line: str, page_number: int) -> Entry | None:
    bracket = BRACKET_RE.search(line)
    if not bracket:
        return None

    before = line[: bracket.start()]
    after = line[bracket.end() :]

    word_match = ENTRY_WORD_RE.search(before)
    if not word_match:
        return None

    word = normalize_word(word_match.group(1))
    if not is_valid_word(word):
        return None

    meaning_match = CJK_RE.search(after)
    if not meaning_match:
        return None

    pos_hint = after[: meaning_match.start()]
    meaning_raw = after[meaning_match.start() :]

    meaning = clean_meaning(meaning_raw)
    if not meaning or not CJK_RE.search(meaning):
        return None

    part_of_speech = infer_part_of_speech(word, pos_hint)
    sentences = generate_sentences(word, part_of_speech)

    return Entry(
        word=word,
        meaning=meaning,
        part_of_speech=part_of_speech,
        sentences=sentences,
        source_page=page_number,
    )


def parse_text(text: str, page_number: int) -> list[Entry]:
    entries: list[Entry] = []
    for raw_line in text.splitlines():
        line = normalize_spaces(raw_line)
        if not line:
            continue
        entry = parse_line(line, page_number)
        if entry is not None:
            entries.append(entry)
    return entries


def extract_page_number_from_name(path: Path) -> int:
    match = re.search(r"-(\d+)\.png$", path.name)
    if not match:
        raise ValueError(f"Cannot parse page number from file name: {path}")
    return int(match.group(1))


def ocr_image(image_path: Path, language: str, psm: int) -> tuple[int, str]:
    page_number = extract_page_number_from_name(image_path)
    result = subprocess.run(
        [
            "tesseract",
            str(image_path.resolve()),
            "stdout",
            "-l",
            language,
            "--psm",
            str(psm),
        ],
        capture_output=True,
        text=True,
        check=False,
    )
    if result.returncode != 0:
        stderr = result.stderr.strip().splitlines()[-1] if result.stderr else ""
        raise RuntimeError(
            f"OCR failed for page {page_number} ({image_path.name}): {stderr}"
        )
    return page_number, result.stdout


def render_pdf_pages(pdf_path: Path, output_prefix: Path, start_page: int, end_page: int, dpi: int) -> None:
    cmd = [
        "pdftoppm",
        "-f",
        str(start_page),
        "-l",
        str(end_page),
        "-r",
        str(dpi),
        "-png",
        str(pdf_path),
        str(output_prefix),
    ]
    subprocess.run(cmd, check=True)


def deduplicate(entries: Iterable[Entry]) -> list[Entry]:
    by_word: dict[str, Entry] = {}
    for entry in entries:
        key = entry.word.lower()
        existing = by_word.get(key)
        if existing is None:
            by_word[key] = entry
            continue
        if len(entry.meaning) > len(existing.meaning):
            by_word[key] = entry
    return sorted(by_word.values(), key=lambda item: item.word.lower())


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--pdf", required=True, help="Path to the source PDF file")
    parser.add_argument("--output", required=True, help="Output JSON path")
    parser.add_argument("--start-page", type=int, default=100)
    parser.add_argument("--end-page", type=int, default=300)
    parser.add_argument("--dpi", type=int, default=260)
    parser.add_argument("--workers", type=int, default=4)
    parser.add_argument("--language", default="chi_tra+eng")
    parser.add_argument("--psm", type=int, default=6)
    return parser.parse_args()


def main() -> int:
    args = parse_args()
    pdf_path = Path(args.pdf)
    output_path = Path(args.output)

    if not pdf_path.exists():
        raise FileNotFoundError(f"PDF not found: {pdf_path}")
    if args.start_page <= 0 or args.end_page < args.start_page:
        raise ValueError("Invalid page range")
    if args.workers <= 0:
        raise ValueError("workers must be positive")

    ensure_binary("pdftoppm")
    ensure_binary("tesseract")

    output_path.parent.mkdir(parents=True, exist_ok=True)

    print(
        f"[1/3] Rendering PDF pages {args.start_page}-{args.end_page} at {args.dpi} DPI...",
        file=sys.stderr,
    )

    with tempfile.TemporaryDirectory(prefix="yunxu_word_bank_") as tmp_dir:
        tmp_path = Path(tmp_dir)
        render_pdf_pages(
            pdf_path=pdf_path,
            output_prefix=tmp_path / "page",
            start_page=args.start_page,
            end_page=args.end_page,
            dpi=args.dpi,
        )

        images = sorted(tmp_path.glob("page-*.png"), key=extract_page_number_from_name)
        if not images:
            raise RuntimeError("No rendered PNG pages were produced")

        print(f"[2/3] OCR on {len(images)} pages with {args.workers} workers...", file=sys.stderr)

        parsed_entries: list[Entry] = []
        ocr_results: dict[int, str] = {}

        with ThreadPoolExecutor(max_workers=args.workers) as executor:
            futures = {
                executor.submit(ocr_image, image, args.language, args.psm): image
                for image in images
            }
            completed = 0
            for future in as_completed(futures):
                page_number, text = future.result()
                ocr_results[page_number] = text
                completed += 1
                if completed % 10 == 0 or completed == len(images):
                    print(
                        f"  OCR progress: {completed}/{len(images)} pages",
                        file=sys.stderr,
                    )

        for page_number in sorted(ocr_results):
            parsed_entries.extend(parse_text(ocr_results[page_number], page_number))

        deduped = deduplicate(parsed_entries)

    print(
        f"[3/3] Writing {len(deduped)} unique words to {output_path}...",
        file=sys.stderr,
    )
    output_payload = [entry.to_json() for entry in deduped]
    output_path.write_text(
        json.dumps(output_payload, ensure_ascii=False, indent=2),
        encoding="utf-8",
    )

    print(
        f"Done. Parsed {len(parsed_entries)} raw entries, kept {len(deduped)} unique words.",
        file=sys.stderr,
    )
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
