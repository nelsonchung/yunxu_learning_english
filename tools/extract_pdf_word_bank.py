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
NOISE_PREFIX_TOKENS = {
    "ee",
    "eee",
    "eed",
    "emd",
    "gee",
    "gees",
    "geieed",
    "feized",
    "cre",
    "ces",
    "moa",
    "wee",
    "siz",
    "sir",
    "od",
    "oe",
    "eh",
    "za",
    "sit",
    "ae",
    "aay",
    "app",
    "ely",
    "ss",
    "ig",
    "wise",
    "wisi",
    "wis",
    "wea",
    "ged",
    "sis",
    "wie",
    "wots",
    "yea",
    "feised",
    "het",
    "feed",
}
EXAMPLE_PREFIX_RE = re.compile(r"^\s*(?:e\.?g\.?|ps\.?)", re.IGNORECASE)
PHRASE_SPLIT_RE = re.compile(r"[;；]+")
BAD_WORD_RE = re.compile(r"^(?:cre|gre|ghe|eee|eed|emd|aay|sis)$", re.IGNORECASE)
VOWELS = set("aeiouy")
WORD_DICT_PATH = Path("/usr/share/dict/words")
PHRASE_LINK_TOKENS = {"of", "in", "on", "to", "by", "or", "as", "an", "a", "the", "and", "for", "at"}
DERIVATIONAL_SUFFIX_RE = re.compile(
    r"(?:tion|sion|ment|ness|able|ible|ally|ingly|ing|ed|ship|hood|ward|ance|ence|ism|ist|ize|ise|ous|ive|ary|ory|less|ful)$"
)
_WORD_DICTIONARY: set[str] | None = None


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


def get_word_dictionary() -> set[str]:
    global _WORD_DICTIONARY
    if _WORD_DICTIONARY is not None:
        return _WORD_DICTIONARY
    if not WORD_DICT_PATH.exists():
        _WORD_DICTIONARY = set()
        return _WORD_DICTIONARY
    with WORD_DICT_PATH.open("r", encoding="utf-8", errors="ignore") as handle:
        _WORD_DICTIONARY = {
            line.strip().lower()
            for line in handle
            if line.strip() and line.strip().isalpha()
        }
    return _WORD_DICTIONARY


def is_known_english_word(token: str) -> bool:
    dictionary = get_word_dictionary()
    if not dictionary:
        return True
    return token in dictionary


def normalize_word(raw: str) -> str:
    text = raw.strip(" \t\n\r\f\v|_.,;:!?*()[]{}<>+=~`\"“”‘’")
    text = normalize_spaces(text)
    tokens = text.split(" ")
    while len(tokens) > 1:
        first = tokens[0]
        first_lower = first.lower()
        if first_lower in NOISE_PREFIX_TOKENS:
            tokens = tokens[1:]
            continue
        if NOISE_TOKEN_RE.match(first):
            tokens = tokens[1:]
            continue
        if len(first) <= 3 and any(ch.isupper() for ch in first):
            tokens = tokens[1:]
            continue
        if first_lower in {"a", "an", "the", "i"} and len(tokens) <= 2:
            tokens = tokens[1:]
            continue
        break
    filtered: list[str] = []
    for token in tokens:
        lowered = token.lower()
        alpha = re.sub(r"[^a-z]", "", lowered)
        if not alpha:
            continue
        if lowered in NOISE_PREFIX_TOKENS and len(tokens) > 1:
            continue
        if len(alpha) <= 2 and len(tokens) > 1 and lowered not in {"of", "in", "on"}:
            continue
        if len(alpha) >= 6 and not any(char in VOWELS for char in alpha):
            continue
        if len(alpha) >= 8:
            vowel_ratio = sum(char in VOWELS for char in alpha) / len(alpha)
            if vowel_ratio < 0.2:
                continue
        filtered.append(lowered)

    if len(filtered) == 2 and filtered[0] in {"a", "an", "the", "i", "as"}:
        filtered = filtered[1:]
    if len(filtered) >= 3 and filtered[0] == "and":
        filtered = filtered[1:]
    if (
        len(filtered) == 2
        and filtered[0] in {"in", "on", "at", "by", "for"}
        and len(filtered[1]) >= 10
    ):
        filtered = filtered[1:]

    return " ".join(filtered).strip()


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
    if BAD_WORD_RE.match(word):
        return False
    tokens = word.split()
    if not tokens:
        return False
    if len(tokens) == 1:
        cleaned = re.sub(r"[^a-z]", "", tokens[0].lower())
        if len(cleaned) < 3:
            return False
        if len(cleaned) <= 4 and not is_known_english_word(cleaned):
            return False
        if (
            len(cleaned) >= 8
            and not is_known_english_word(cleaned)
            and not DERIVATIONAL_SUFFIX_RE.search(cleaned)
            and "-" not in tokens[0]
        ):
            return False
    for token in tokens:
        if len(token) <= 1:
            return False
        if any(ch.isupper() for ch in token):
            return False
        cleaned = re.sub(r"[^a-z]", "", token.lower())
        if not cleaned:
            return False
        if len(cleaned) >= 4 and not any(char in VOWELS for char in cleaned):
            return False
        if (
            len(tokens) > 1
            and len(cleaned) <= 3
            and cleaned not in PHRASE_LINK_TOKENS
            and not is_known_english_word(cleaned)
        ):
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
    before = normalize_spaces(before.replace("|", " ").replace("_", " "))
    before = re.sub(r"[^A-Za-z'\-\s]+$", "", before)

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


def parse_fallback_segment(segment: str, page_number: int) -> Entry | None:
    if EXAMPLE_PREFIX_RE.search(segment):
        return None
    if not CJK_RE.search(segment):
        return None

    simplified = BRACKET_RE.sub(" ", segment)
    simplified = normalize_spaces(
        simplified.replace("|", " ").replace("_", " ").replace("`", " ")
    )
    if not simplified:
        return None
    if "。" in simplified:
        return None

    meaning_match = CJK_RE.search(simplified)
    if not meaning_match:
        return None

    before = simplified[: meaning_match.start()]
    after = simplified[meaning_match.start() :]
    if "." in before or "," in before:
        return None
    english_tokens = re.findall(r"[A-Za-z][A-Za-z'\-]*", before)
    if len(english_tokens) > 6:
        return None

    word_match = ENTRY_WORD_RE.search(before)
    if not word_match:
        return None

    word = normalize_word(word_match.group(1))
    if not is_valid_word(word):
        return None

    meaning = clean_meaning(after)
    if not meaning or not CJK_RE.search(meaning):
        return None

    part_of_speech = infer_part_of_speech(word, "")
    return Entry(
        word=word,
        meaning=meaning,
        part_of_speech=part_of_speech,
        sentences=generate_sentences(word, part_of_speech),
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
            continue

        for segment in PHRASE_SPLIT_RE.split(line):
            segment = normalize_spaces(segment)
            if not segment:
                continue
            fallback = parse_fallback_segment(segment, page_number)
            if fallback is not None:
                entries.append(fallback)
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
    def score(item: Entry) -> int:
        base = 0
        if " " in item.word:
            base += 1
        else:
            base += 2
        if 2 <= len(item.meaning) <= 24:
            base += 2
        if BAD_WORD_RE.match(item.word):
            base -= 4
        if item.part_of_speech in {"verb", "adjective", "adverb", "phrase"}:
            base += 1
        return base

    by_word: dict[str, Entry] = {}
    for entry in entries:
        key = entry.word.lower()
        existing = by_word.get(key)
        if existing is None:
            by_word[key] = entry
            continue
        if score(entry) > score(existing):
            by_word[key] = entry
            continue
        if score(entry) == score(existing) and len(entry.meaning) > len(
            existing.meaning
        ):
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
