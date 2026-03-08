#!/usr/bin/env python3
"""Add first-pass audience metadata to assets/word_bank/word_bank_main.json.

Metadata rules:
1. Use the official Taiwan senior-high reference vocabulary PDF to assign
   CEEC difficulty levels 1-6.
2. Map CEEC levels to school audiences:
   - level 1 => elementary
   - levels 1-2 => juniorHigh
   - levels 1-6 => seniorHigh
   - levels 5-6 => college (first-pass advanced bucket)
3. Add TOEIC when the entry looks workplace-oriented based on curated signals.
4. Add source tags so the UI can explain why the label exists.
"""

from __future__ import annotations

import argparse
import json
import re
from collections import Counter
from pathlib import Path
from typing import Iterable

from pypdf import PdfReader


ROOT = Path(__file__).resolve().parents[1]
DEFAULT_WORD_BANK = ROOT / "assets" / "word_bank" / "word_bank_main.json"
DEFAULT_HS_PDF = ROOT / "docs" / "materials" / "高中英文參考詞彙表(111學年度起適用).pdf"
DEFAULT_EXAM_BOOK_WORDS = (
    ROOT / "assets" / "word_bank" / "pdf_word_bank.words.single.txt"
)

SCHOOL_LEVELS = ("elementary", "juniorHigh", "seniorHigh", "college")
EXAM_TAGS = ("toeic",)
AUDIENCE_TAGS = ("general",)
SOURCE_TAGS = ("twCeec", "toeicSignals", "collegeSignals", "pdfExamBook")

POS_TOKEN_RE = re.compile(r"^(?P<word>.+?)\s+(?P<pos>[A-Za-z./()]+)$")
HS_LEVEL_HEADER_RE = re.compile(r"(?:依級別排序\s+)?第([一二三四五六])級")

VALID_POS_TOKENS = {
    "n",
    "v",
    "adj",
    "adv",
    "prep",
    "pron",
    "conj",
    "interj",
    "aux",
    "art",
    "det",
    "num",
    "modal",
}

WORKPLACE_WORDS = {
    "account",
    "agenda",
    "airport",
    "application",
    "appointment",
    "budget",
    "business",
    "career",
    "client",
    "company",
    "conference",
    "contract",
    "customer",
    "deadline",
    "delivery",
    "department",
    "discount",
    "document",
    "employee",
    "equipment",
    "expense",
    "factory",
    "finance",
    "flight",
    "hotel",
    "interview",
    "invoice",
    "manager",
    "market",
    "marketing",
    "meeting",
    "office",
    "order",
    "payment",
    "product",
    "profit",
    "project",
    "proposal",
    "purchase",
    "receipt",
    "refund",
    "report",
    "reservation",
    "salary",
    "schedule",
    "service",
    "shipment",
    "staff",
    "tour",
    "travel",
    "warehouse",
}

WORKPLACE_SIGNALS = (
    "office",
    "company",
    "business",
    "meeting",
    "manager",
    "customer",
    "client",
    "budget",
    "contract",
    "invoice",
    "order",
    "project",
    "department",
    "employee",
    "shipment",
    "delivery",
    "hotel",
    "flight",
    "reservation",
    "travel",
    "公司",
    "會議",
    "客戶",
    "預算",
    "合約",
    "發票",
    "訂單",
    "專案",
    "部門",
    "員工",
    "出貨",
    "配送",
    "飯店",
    "航班",
    "預約",
    "商務",
)

ACADEMIC_WORDS = {
    "academic",
    "analysis",
    "biology",
    "campus",
    "chemistry",
    "college",
    "curriculum",
    "economics",
    "engineering",
    "essay",
    "experiment",
    "graduate",
    "lecture",
    "mathematics",
    "medicine",
    "physics",
    "professor",
    "research",
    "scholar",
    "scholarship",
    "scientific",
    "seminar",
    "student",
    "study",
    "thesis",
    "tuition",
    "undergraduate",
    "university",
}

ACADEMIC_SIGNALS = (
    "university",
    "college",
    "campus",
    "professor",
    "research",
    "academic",
    "scientific",
    "scholarship",
    "lecture",
    "seminar",
    "experiment",
    "thesis",
    "essay",
    "study",
    "student",
    "大學",
    "校園",
    "教授",
    "研究",
    "學術",
    "獎學金",
    "講座",
    "實驗",
    "論文",
)


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--input", default=str(DEFAULT_WORD_BANK))
    parser.add_argument("--output", default=str(DEFAULT_WORD_BANK))
    parser.add_argument("--hs-pdf", default=str(DEFAULT_HS_PDF))
    parser.add_argument("--exam-book-words", default=str(DEFAULT_EXAM_BOOK_WORDS))
    parser.add_argument(
        "--stdout-only",
        action="store_true",
        help="Print summary only without writing changes.",
    )
    return parser.parse_args()


def normalize_key(value: str) -> str:
    return re.sub(r"\s+", " ", value.strip().lower())


def parse_hs_levels(pdf_path: Path) -> dict[str, int]:
    pages = [(page.extract_text() or "") for page in PdfReader(str(pdf_path)).pages]

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
        raise ValueError("Cannot locate the by-level section in the HS reference PDF")

    levels: dict[str, int] = {}
    current_level: int | None = None
    for page_no in range(start_page, alpha_page):
        for raw_line in pages[page_no - 1].splitlines():
            text = " ".join(raw_line.strip().split())
            if not text:
                continue
            if text in {"依級別排序", "高中英文參考詞彙表"}:
                continue
            if text.isdigit() or re.fullmatch(r"[A-Z]", text):
                continue

            header_match = HS_LEVEL_HEADER_RE.fullmatch(text)
            if header_match:
                current_level = "一二三四五六".index(header_match.group(1)) + 1
                continue

            if current_level is None:
                continue

            match = POS_TOKEN_RE.match(text)
            if not match:
                continue

            pos_tokens = [token for token in match.group("pos").lower().split("/") if token]
            if not any(token.strip("().") in VALID_POS_TOKENS for token in pos_tokens):
                continue

            word = match.group("word").strip(" .")
            levels[normalize_key(word)] = current_level

    if len(levels) < 5000:
        raise ValueError(f"Unexpectedly low HS entry count: {len(levels)}")

    return levels


def load_exam_book_words(path: Path) -> set[str]:
    if not path.exists():
        return set()
    return {
        normalize_key(line)
        for line in path.read_text(encoding="utf-8").splitlines()
        if line.strip()
    }


def contains_any(text: str, signals: Iterable[str]) -> bool:
    normalized = text.casefold()
    return any(signal.casefold() in normalized for signal in signals)


def unique_in_order(items: Iterable[str]) -> list[str]:
    seen: set[str] = set()
    unique: list[str] = []
    for item in items:
        if item in seen:
            continue
        seen.add(item)
        unique.append(item)
    return unique


def main() -> int:
    args = parse_args()
    input_path = Path(args.input)
    output_path = Path(args.output)
    hs_levels = parse_hs_levels(Path(args.hs_pdf))
    exam_book_words = load_exam_book_words(Path(args.exam_book_words))

    word_bank = json.loads(input_path.read_text(encoding="utf-8"))
    if not isinstance(word_bank, list):
        raise ValueError("word bank JSON must be a list")

    school_counter: Counter[str] = Counter()
    exam_counter: Counter[str] = Counter()
    audience_counter: Counter[str] = Counter()
    source_counter: Counter[str] = Counter()
    difficulty_counter: Counter[int] = Counter()

    for entry in word_bank:
        if not isinstance(entry, dict):
            continue

        word = str(entry.get("word", "")).strip()
        if not word:
            continue

        key = normalize_key(word)
        meaning = str(entry.get("meaning", "")).strip()
        sentences = entry.get("sentences")
        sentence_text = ""
        if isinstance(sentences, list):
            sentence_text = " ".join(item for item in sentences if isinstance(item, str))
        combined_text = f"{word} {meaning} {sentence_text}"

        ceec_level = hs_levels.get(key)
        in_exam_book = key in exam_book_words
        workplace_match = key in WORKPLACE_WORDS or contains_any(
            combined_text,
            WORKPLACE_SIGNALS,
        )
        academic_match = key in ACADEMIC_WORDS or contains_any(
            combined_text,
            ACADEMIC_SIGNALS,
        )

        school_levels: list[str] = []
        exam_tags: list[str] = []
        audience_tags: list[str] = []
        source_tags: list[str] = []

        if ceec_level is not None:
            school_levels.append("seniorHigh")
            source_tags.append("twCeec")
            entry["difficultyLevel"] = ceec_level
            difficulty_counter[ceec_level] += 1
            if ceec_level <= 2:
                school_levels.append("juniorHigh")
            if ceec_level == 1:
                school_levels.append("elementary")
            if ceec_level >= 5:
                school_levels.append("college")
                source_tags.append("collegeSignals")
        else:
            entry.pop("difficultyLevel", None)

        if academic_match and "college" not in school_levels:
            school_levels.append("college")
            source_tags.append("collegeSignals")

        if workplace_match:
            exam_tags.append("toeic")
            source_tags.append("toeicSignals")

        if in_exam_book:
            source_tags.append("pdfExamBook")

        school_levels = unique_in_order(
            item for item in school_levels if item in SCHOOL_LEVELS
        )
        exam_tags = unique_in_order(item for item in exam_tags if item in EXAM_TAGS)
        if not school_levels and not exam_tags:
            audience_tags.append("general")
        audience_tags = unique_in_order(
            item for item in audience_tags if item in AUDIENCE_TAGS
        )
        source_tags = unique_in_order(
            item for item in source_tags if item in SOURCE_TAGS
        )

        if school_levels:
            entry["schoolLevels"] = school_levels
            school_counter.update(school_levels)
        else:
            entry.pop("schoolLevels", None)

        if exam_tags:
            entry["examTags"] = exam_tags
            exam_counter.update(exam_tags)
        else:
            entry.pop("examTags", None)

        if audience_tags:
            entry["audienceTags"] = audience_tags
            audience_counter.update(audience_tags)
        else:
            entry.pop("audienceTags", None)

        if source_tags:
            entry["sourceTags"] = source_tags
            source_counter.update(source_tags)
        else:
            entry.pop("sourceTags", None)

    print(f"Processed {len(word_bank)} entries")
    print(f"HS overlap: {sum(difficulty_counter.values())}")
    print(f"School levels: {dict(sorted(school_counter.items()))}")
    print(f"Exam tags: {dict(sorted(exam_counter.items()))}")
    print(f"Audience tags: {dict(sorted(audience_counter.items()))}")
    print(f"Source tags: {dict(sorted(source_counter.items()))}")
    print(f"Difficulty levels: {dict(sorted(difficulty_counter.items()))}")

    if not args.stdout_only:
        output_path.write_text(
            json.dumps(word_bank, ensure_ascii=False, indent=2) + "\n",
            encoding="utf-8",
        )
        print(f"Wrote {output_path}")

    return 0


if __name__ == "__main__":
    raise SystemExit(main())
