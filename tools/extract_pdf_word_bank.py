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
from collections import Counter, defaultdict
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
ALL_CANDIDATE_RE = re.compile(
    r"[A-Za-z][A-Za-z'\-]*(?:\s+[A-Za-z][A-Za-z'\-]*){0,3}"
)
BAD_WORD_RE = re.compile(r"^(?:cre|gre|ghe|eee|eed|emd|aay|sis)$", re.IGNORECASE)
MENTION_TOKEN_RE = re.compile(r"[A-Za-z][A-Za-z'\-]{1,31}")
VOWELS = set("aeiouy")
WORD_DICT_PATH = Path("/usr/share/dict/words")
PHRASE_LINK_TOKENS = {"of", "in", "on", "to", "by", "or", "as", "an", "a", "the", "and", "for", "at"}
DERIVATIONAL_SUFFIX_RE = re.compile(
    r"(?:tion|sion|ment|ness|able|ible|ally|ingly|ing|ed|ship|hood|ward|ance|ence|ism|ist|ize|ise|ous|ive|ary|ory|less|ful)$"
)
MENTION_NOISE_WORDS = {
    "aaa",
    "eeee",
    "eeg",
    "gees",
    "gexd",
    "hl",
    "iii",
    "lll",
    "nnn",
    "ooo",
    "qqq",
    "rrr",
    "sss",
    "ttt",
    "www",
    "xxx",
    "yyy",
    "zzz",
}
_WORD_DICTIONARY: set[str] | None = None
ALLOW_UNKNOWN_WORDS = False
INCLUDE_ALL_MENTIONS = False
RELAXED_MENTION_FILTER = False


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


def is_likely_unknown_token(cleaned: str) -> bool:
    if not cleaned:
        return True
    if cleaned in PHRASE_LINK_TOKENS:
        return False
    if is_known_english_word(cleaned):
        return False
    if DERIVATIONAL_SUFFIX_RE.search(cleaned) and len(cleaned) >= 6:
        return False
    return len(cleaned) >= 5


def is_meaningful_token(token: str) -> bool:
    cleaned = re.sub(r"[^a-z]", "", token.lower())
    if not cleaned:
        return False
    if cleaned in PHRASE_LINK_TOKENS:
        return True
    if is_known_english_word(cleaned):
        return True
    if DERIVATIONAL_SUFFIX_RE.search(cleaned) and len(cleaned) >= 6:
        return True
    if "-" in token:
        parts = [part for part in re.split(r"-+", cleaned) if part]
        if parts and all(
            part in PHRASE_LINK_TOKENS or is_known_english_word(part)
            for part in parts
        ):
            return True
    return False


def is_reasonable_candidate_phrase(word: str) -> bool:
    if RELAXED_MENTION_FILTER:
        tokens = [item for item in word.split() if item]
        if not tokens:
            return False
        if len(tokens) > 4:
            return False
        return any(
            len(re.sub(r"[^a-z]", "", token.lower())) >= 3 for token in tokens
        )

    tokens = [item for item in word.split() if item]
    if not tokens:
        return False
    content_tokens: list[str] = []
    unknown_count = 0
    for token in tokens:
        cleaned = re.sub(r"[^a-z]", "", token.lower())
        if not cleaned:
            return False
        if cleaned in PHRASE_LINK_TOKENS:
            continue
        content_tokens.append(token)
        if len(cleaned) < 3:
            return False
        if not is_meaningful_token(token):
            unknown_count += 1

    if not content_tokens:
        return False
    if len(content_tokens) == 1:
        return unknown_count == 0
    return unknown_count == 0


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
        if "--" in lowered:
            continue
        if not ALLOW_UNKNOWN_WORDS:
            if (
                len(tokens) > 1
                and "-" not in lowered
                and "'" not in lowered
                and is_likely_unknown_token(alpha)
            ):
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

    if not ALLOW_UNKNOWN_WORDS:
        while len(filtered) > 1:
            last = filtered[-1]
            alpha_last = re.sub(r"[^a-z]", "", last)
            if not is_likely_unknown_token(alpha_last):
                break
            filtered.pop()

    return " ".join(filtered).strip()


def clean_meaning(raw: str) -> str:
    text = normalize_spaces(raw)
    text = re.sub(r"\s+[|]?\d{1,3}\s*$", "", text)
    text = text.split(";", 1)[0]
    text = re.sub(r"[A-Za-z\[\]`'\"].*$", "", text)
    text = text.strip(" \t\n\r\f\v|_.,;:!?*()[]{}<>+=~`\"")
    return normalize_spaces(text)


def is_valid_word(word: str) -> bool:
    if len(word) < 2 or len(word) > 64:
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
        if not ALLOW_UNKNOWN_WORDS:
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
        if not ALLOW_UNKNOWN_WORDS:
            if (
                len(tokens) > 1
                and len(cleaned) <= 3
                and cleaned not in PHRASE_LINK_TOKENS
                and not is_known_english_word(cleaned)
            ):
                return False
    return True


def normalize_mention_token(raw: str) -> str:
    token = raw.strip(" \t\n\r\f\v|_.,;:!?*()[]{}<>+=~`\"“”‘’")
    token = token.replace("’", "'").replace("`", "'").lower()
    token = token.strip("-'")
    token = re.sub(r"-{2,}", "-", token)
    token = re.sub(r"'{2,}", "'", token)
    return token


def is_valid_mention_token(token: str) -> bool:
    if not token:
        return False
    if len(token) < 3 or len(token) > 32:
        return False
    if token in MENTION_NOISE_WORDS:
        return False
    if not re.fullmatch(r"[a-z][a-z'\-]*[a-z]", token):
        return False

    alpha = re.sub(r"[^a-z]", "", token)
    if len(alpha) < 2:
        return False
    if len(alpha) >= 4 and not any(char in VOWELS for char in alpha):
        return False
    if len(alpha) >= 8:
        vowel_ratio = sum(char in VOWELS for char in alpha) / len(alpha)
        if vowel_ratio < 0.2:
            return False
    if BAD_WORD_RE.match(alpha):
        return False
    if alpha.startswith(("www", "http")):
        return False
    return True


def should_include_unknown_mention_token(
    alpha: str, token_occurrences: int, page_occurrences: int, min_unknown_count: int
) -> bool:
    if not alpha:
        return False
    if len(alpha) <= 3:
        return False
    if token_occurrences >= min_unknown_count and page_occurrences >= 3:
        return True
    if DERIVATIONAL_SUFFIX_RE.search(alpha) and token_occurrences >= max(
        2, min_unknown_count - 1
    ):
        return True
    return False


def extract_mention_tokens(text: str) -> list[str]:
    words: list[str] = []
    for match in MENTION_TOKEN_RE.finditer(text):
        token = normalize_mention_token(match.group(0))
        if is_valid_mention_token(token):
            words.append(token)
    return words


def build_token_mention_entries(
    ocr_results: dict[int, dict[int, str]],
    existing_words: set[str],
    min_count: int,
    min_unknown_count: int,
    placeholder_meaning: str,
) -> list[Entry]:
    token_counter: Counter[str] = Counter()
    token_pages: dict[str, set[int]] = defaultdict(set)

    for page_number in sorted(ocr_results):
        texts_by_psm = ocr_results[page_number]
        for text in texts_by_psm.values():
            for token in extract_mention_tokens(text):
                if token in existing_words:
                    continue
                token_counter[token] += 1
                token_pages[token].add(page_number)

    entries: list[Entry] = []
    for token, count in token_counter.items():
        pages = token_pages[token]
        page_occurrences = len(pages)
        alpha = re.sub(r"[^a-z]", "", token)
        known = is_known_english_word(alpha)
        keep = False
        if known:
            required = min_count
            if len(alpha) <= 3:
                required = max(required, 3)
            keep = count >= required or page_occurrences >= required
        else:
            keep = should_include_unknown_mention_token(
                alpha=alpha,
                token_occurrences=count,
                page_occurrences=page_occurrences,
                min_unknown_count=min_unknown_count,
            )
        if not keep:
            continue

        part_of_speech = infer_part_of_speech(token, "")
        entries.append(
            Entry(
                word=token,
                meaning=placeholder_meaning,
                part_of_speech=part_of_speech,
                sentences=generate_sentences(token, part_of_speech),
                source_page=min(pages),
            )
        )

    return entries


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


def parse_all_candidates_from_segment(segment: str, page_number: int) -> list[Entry]:
    if EXAMPLE_PREFIX_RE.search(segment):
        return []
    if not CJK_RE.search(segment):
        return []

    simplified = BRACKET_RE.sub(" ", segment)
    simplified = normalize_spaces(
        simplified.replace("|", " ").replace("_", " ").replace("`", " ")
    )
    if not simplified:
        return []
    if "。" in simplified:
        return []

    meaning_match = CJK_RE.search(simplified)
    if not meaning_match:
        return []

    before = simplified[: meaning_match.start()]
    after = simplified[meaning_match.start() :]
    if "." in before and "[" not in before:
        return []

    meaning = clean_meaning(after)
    if not meaning or not CJK_RE.search(meaning):
        return []

    candidates = ALL_CANDIDATE_RE.findall(before)
    if not candidates or len(candidates) > 10:
        return []

    entries: list[Entry] = []
    seen_words: set[str] = set()
    for candidate in candidates:
        word = normalize_word(candidate)
        if not word:
            continue
        if word in seen_words:
            continue
        if RELAXED_MENTION_FILTER:
            if len(word) < 3 or len(word) > 64:
                continue
            if not VALID_WORD_RE.match(word):
                continue
        else:
            if not is_valid_word(word):
                continue
        if not is_reasonable_candidate_phrase(word):
            continue
        part_of_speech = infer_part_of_speech(word, "")
        entries.append(
            Entry(
                word=word,
                meaning=meaning,
                part_of_speech=part_of_speech,
                sentences=generate_sentences(word, part_of_speech),
                source_page=page_number,
            )
        )
        seen_words.add(word)
    return entries


def parse_text(text: str, page_number: int) -> list[Entry]:
    entries: list[Entry] = []
    for raw_line in text.splitlines():
        line = normalize_spaces(raw_line)
        if not line:
            continue

        entry = parse_line(line, page_number)
        if entry is not None:
            entries.append(entry)
            if not INCLUDE_ALL_MENTIONS:
                continue

        for segment in PHRASE_SPLIT_RE.split(line):
            segment = normalize_spaces(segment)
            if not segment:
                continue
            fallback = parse_fallback_segment(segment, page_number)
            if fallback is not None:
                entries.append(fallback)
            if INCLUDE_ALL_MENTIONS:
                entries.extend(parse_all_candidates_from_segment(segment, page_number))
    return entries


def extract_page_number_from_name(path: Path) -> int:
    match = re.search(r"-(\d+)\.png$", path.name)
    if not match:
        raise ValueError(f"Cannot parse page number from file name: {path}")
    return int(match.group(1))


def ocr_image(image_path: Path, language: str, psm: int) -> str:
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
            f"OCR failed for page image {image_path.name} with psm={psm}: {stderr}"
        )
    return result.stdout


def ocr_image_with_multiple_psm(
    image_path: Path, language: str, psm_values: list[int]
) -> tuple[int, dict[int, str]]:
    page_number = extract_page_number_from_name(image_path)
    texts: dict[int, str] = {}
    for psm in psm_values:
        texts[psm] = ocr_image(image_path=image_path, language=language, psm=psm)
    return page_number, texts


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
    parser.add_argument("--start-page", type=int, default=20)
    parser.add_argument("--end-page", type=int, default=300)
    parser.add_argument("--dpi", type=int, default=260)
    parser.add_argument("--workers", type=int, default=4)
    parser.add_argument("--language", default="chi_tra+eng")
    parser.add_argument(
        "--allow-unknown-words",
        action="store_true",
        help="Relax dictionary-based filters to maximize recall.",
    )
    parser.add_argument(
        "--psm-list",
        default="6,4",
        help="Comma-separated tesseract PSM values. Example: 6,4 or 6,4,11",
    )
    parser.add_argument(
        "--include-all-mentions",
        action="store_true",
        help="Extract all candidate English terms in dictionary-like segments.",
    )
    parser.add_argument(
        "--mentions-relaxed",
        action="store_true",
        help="Relax phrase quality checks for all-candidate extraction.",
    )
    parser.add_argument(
        "--include-token-mentions",
        action="store_true",
        help="Extract single-word English tokens from OCR text for higher recall.",
    )
    parser.add_argument(
        "--token-min-count",
        type=int,
        default=2,
        help="Minimum OCR occurrences/pages for dictionary-known token mentions.",
    )
    parser.add_argument(
        "--token-unknown-min-count",
        type=int,
        default=3,
        help="Minimum OCR occurrences for unknown token mentions.",
    )
    parser.add_argument(
        "--token-placeholder-meaning",
        default="（PDF提及，待補中文）",
        help="Meaning text for token mentions extracted from OCR context.",
    )
    return parser.parse_args()


def main() -> int:
    global ALLOW_UNKNOWN_WORDS
    global INCLUDE_ALL_MENTIONS
    global RELAXED_MENTION_FILTER
    args = parse_args()
    ALLOW_UNKNOWN_WORDS = bool(args.allow_unknown_words)
    INCLUDE_ALL_MENTIONS = bool(args.include_all_mentions)
    RELAXED_MENTION_FILTER = bool(args.mentions_relaxed)
    pdf_path = Path(args.pdf)
    output_path = Path(args.output)

    if not pdf_path.exists():
        raise FileNotFoundError(f"PDF not found: {pdf_path}")
    if args.start_page <= 0 or args.end_page < args.start_page:
        raise ValueError("Invalid page range")
    if args.workers <= 0:
        raise ValueError("workers must be positive")
    if args.token_min_count <= 0:
        raise ValueError("token-min-count must be positive")
    if args.token_unknown_min_count <= 0:
        raise ValueError("token-unknown-min-count must be positive")
    psm_values = []
    for raw in args.psm_list.split(","):
        raw = raw.strip()
        if not raw:
            continue
        try:
            psm_values.append(int(raw))
        except ValueError as error:
            raise ValueError(f"Invalid psm value: {raw}") from error
    if not psm_values:
        raise ValueError("psm-list must contain at least one integer value")

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

        print(
            f"[2/3] OCR on {len(images)} pages with {args.workers} workers "
            f"(psm={psm_values})...",
            file=sys.stderr,
        )

        parsed_entries: list[Entry] = []
        ocr_results: dict[int, dict[int, str]] = {}

        with ThreadPoolExecutor(max_workers=args.workers) as executor:
            futures = {
                executor.submit(
                    ocr_image_with_multiple_psm, image, args.language, psm_values
                ): image
                for image in images
            }
            completed = 0
            for future in as_completed(futures):
                page_number, text_by_psm = future.result()
                ocr_results[page_number] = text_by_psm
                completed += 1
                if completed % 10 == 0 or completed == len(images):
                    print(
                        f"  OCR progress: {completed}/{len(images)} pages",
                        file=sys.stderr,
                    )

        for page_number in sorted(ocr_results):
            text_by_psm = ocr_results[page_number]
            for psm in psm_values:
                parsed_entries.extend(parse_text(text_by_psm.get(psm, ""), page_number))

        deduped = deduplicate(parsed_entries)

        token_entries: list[Entry] = []
        if args.include_token_mentions:
            existing_words = {entry.word.lower() for entry in deduped}
            token_entries = build_token_mention_entries(
                ocr_results=ocr_results,
                existing_words=existing_words,
                min_count=args.token_min_count,
                min_unknown_count=args.token_unknown_min_count,
                placeholder_meaning=args.token_placeholder_meaning.strip()
                or "（PDF提及，待補中文）",
            )
            deduped = deduplicate([*deduped, *token_entries])

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
        "Done. Parsed "
        f"{len(parsed_entries)} raw entries, "
        f"added {len(token_entries) if args.include_token_mentions else 0} token mentions, "
        f"kept {len(deduped)} unique words.",
        file=sys.stderr,
    )
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
