#!/usr/bin/env python3
import argparse
import concurrent.futures
import html
import json
import re
import sys
import time
import urllib.error
import urllib.parse
import urllib.request
from collections import Counter
from functools import lru_cache
from pathlib import Path
from typing import Optional

from bs4 import BeautifulSoup
from wordfreq import zipf_frequency


CURRENT_DIR = Path(__file__).resolve().parent
if str(CURRENT_DIR) not in sys.path:
    sys.path.insert(0, str(CURRENT_DIR))

from repair_html_polluted_word_bank_entries import clean_markup, fetch_json
from sync_letter_word_bank_progress import (
    build_coverage,
    load_source_words,
    load_target_words,
    write_json,
    write_lines,
)
from tag_word_bank_audiences import (
    ACADEMIC_SIGNALS,
    ACADEMIC_WORDS,
    DEFAULT_EXAM_BOOK_WORDS,
    DEFAULT_HS_PDF,
    EXAM_TAGS,
    SCHOOL_LEVELS,
    SOURCE_TAGS,
    WORKPLACE_SIGNALS,
    WORKPLACE_WORDS,
    contains_any,
    load_exam_book_words,
    normalize_key,
    parse_hs_levels,
)
from validate_word_bank_main import ALLOWED_POS


ROOT = Path(__file__).resolve().parents[1]
SOURCE_PATH = ROOT / "assets" / "word_bank" / "en"
TARGET_PATH = ROOT / "assets" / "word_bank" / "word_bank_main-l.json"
LOG_DIR = ROOT / "logs" / "word_bank_l"
BATCH_DIR = LOG_DIR / "batches"
MANIFEST_PATH = LOG_DIR / "manifest.json"
RUN_PROGRESS_PATH = LOG_DIR / "run_progress.json"
COMPLETION_SUMMARY_PATH = LOG_DIR / "completion_summary.json"
SEP_TOKEN = "|||SEP|||"
SEP_RE = re.compile(r"\|\|\|.*?\|\|\|")
HTML_PARENS_RE = re.compile(r"^\([^)]{1,40}\)\s*")
PLACEHOLDER_MEANING = "罕見或專門用語。"

KAIKKI_POS_MAP = {
    "noun": "noun",
    "name": "noun",
    "letter": "noun",
    "symbol": "noun",
    "numeral": "noun",
    "suffix": "noun",
    "prefix": "noun",
    "verb": "verb",
    "adj": "adjective",
    "adjective": "adjective",
    "participle": "adjective",
    "adv": "adverb",
    "adverb": "adverb",
    "pron": "pronoun",
    "pronoun": "pronoun",
    "prep": "preposition",
    "preposition": "preposition",
    "conj": "conjunction",
    "conjunction": "conjunction",
    "intj": "exclamation",
    "interj": "exclamation",
    "exclamation": "exclamation",
    "det": "determiner",
    "determiner": "determiner",
    "article": "determiner",
}

FORM_PATTERNS = [
    (re.compile(r"^plural of ([^.;]+)", re.I), "plural"),
    (re.compile(r"^singular of ([^.;]+)", re.I), "singular"),
    (re.compile(r"^alternative (?:form|spelling|letter-case form) of ([^.;]+)", re.I), "alternative"),
    (re.compile(r"^alternative capitalization of ([^.;]+)", re.I), "alternative"),
    (re.compile(r"^past tense of ([^.;]+)", re.I), "past"),
    (re.compile(r"^past participle of ([^.;]+)", re.I), "past_participle"),
    (re.compile(r"^present participle of ([^.;]+)", re.I), "present_participle"),
    (re.compile(r"^third-person singular simple present indicative form of ([^.;]+)", re.I), "third_person"),
    (re.compile(r"^third-person singular simple present of ([^.;]+)", re.I), "third_person"),
    (re.compile(r"^comparative of ([^.;]+)", re.I), "comparative"),
    (re.compile(r"^superlative of ([^.;]+)", re.I), "superlative"),
]

SPECIAL_CANDIDATES = {
    "quaggle": {
        "partOfSpeech": "verb",
        "definition": "To shake.",
        "relationType": None,
        "relationTarget": None,
        "source": "manual-special",
        "confidence": "high",
        "score": 60,
    },
    "qualmyish": {
        "partOfSpeech": "adjective",
        "definition": "Somewhat qualmy or uneasy.",
        "relationType": None,
        "relationTarget": None,
        "source": "manual-special",
        "confidence": "high",
        "score": 60,
    },
    "quintupliribbed": {
        "partOfSpeech": "adjective",
        "definition": "Having five ribs.",
        "relationType": None,
        "relationTarget": None,
        "source": "manual-special",
        "confidence": "high",
        "score": 60,
    },
    "quondamly": {
        "partOfSpeech": "adverb",
        "definition": "Formerly; in the past.",
        "relationType": None,
        "relationTarget": None,
        "source": "manual-special",
        "confidence": "high",
        "score": 60,
    },
}


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(
        description="Complete a letter word bank using Kaikki/Merriam and deterministic sentence generation."
    )
    parser.add_argument("--start-batch", type=int, default=0)
    parser.add_argument("--end-batch", type=int, default=None)
    parser.add_argument("--workers", type=int, default=8)
    parser.add_argument("--prefix", default="l")
    parser.add_argument("--source", type=Path, default=SOURCE_PATH)
    parser.add_argument("--target", type=Path, default=TARGET_PATH)
    parser.add_argument("--log-dir", type=Path, default=LOG_DIR)
    parser.add_argument("--manifest", type=Path, default=MANIFEST_PATH)
    parser.add_argument("--hs-pdf", type=Path, default=DEFAULT_HS_PDF)
    parser.add_argument("--exam-book-words", type=Path, default=DEFAULT_EXAM_BOOK_WORDS)
    parser.add_argument("--force", action="store_true")
    return parser.parse_args()


def load_json(path: Path):
    with path.open(encoding="utf-8") as file:
        return json.load(file)


def sort_entries(entries: list[dict]) -> list[dict]:
    return sorted(entries, key=lambda item: item["word"].casefold())


@lru_cache(maxsize=100000)
def fetch_html(url: str) -> str:
    last_error = None
    for attempt in range(3):
        try:
            request = urllib.request.Request(url.replace(" ", "%20"), headers={"User-Agent": "Mozilla/5.0"})
            with urllib.request.urlopen(request, timeout=12) as response:
                return response.read().decode("utf-8", "ignore")
        except urllib.error.HTTPError as exc:
            last_error = exc
            if exc.code in {404, 410}:
                break
            time.sleep(0.3 * (attempt + 1))
        except Exception as exc:
            last_error = exc
            time.sleep(0.3 * (attempt + 1))
    raise last_error


@lru_cache(maxsize=100000)
def translate_text(text: str) -> str:
    url = (
        "https://translate.googleapis.com/translate_a/single"
        "?client=gtx&sl=en&tl=zh-TW&dt=t&q=" + urllib.parse.quote(text)
    )
    try:
        obj = fetch_json(url)
        return clean_markup("".join(segment[0] for segment in obj[0] if segment and segment[0]))
    except Exception:
        return text


def strip_leading_domain(gloss: str) -> str:
    cleaned = clean_markup(gloss)
    while True:
        updated = HTML_PARENS_RE.sub("", cleaned).strip()
        if updated == cleaned:
            return cleaned
        cleaned = updated


def parse_sense_relation(definition: str) -> tuple[Optional[str], Optional[str]]:
    plain = strip_leading_domain(definition)
    for pattern, relation_type in FORM_PATTERNS:
        match = pattern.match(plain)
        if match:
            return relation_type, clean_markup(match.group(1))
    return None, None


def normalize_pos_token(token: str) -> Optional[str]:
    return KAIKKI_POS_MAP.get(token.casefold())


def extract_kaikki_pos(item_id: str) -> Optional[str]:
    parts = [part for part in item_id.split("-") if part]
    if not parts or parts[0] != "en":
        return None
    for token in reversed(parts[1:]):
        pos = normalize_pos_token(token)
        if pos is not None:
            return pos
    return None


def build_kaikki_url(word: str) -> str:
    key = word.casefold()
    return (
        "https://kaikki.org/dictionary/English/meaning/"
        + urllib.parse.quote(key[0])
        + "/"
        + urllib.parse.quote(key[:2])
        + "/"
        + urllib.parse.quote(key)
        + ".html"
    )


@lru_cache(maxsize=2048)
def search_kaikki_prefix(prefix: str) -> list[list[str]]:
    normalized = prefix.casefold()
    if len(normalized) not in {2, 3}:
        raise ValueError(f"unsupported Kaikki prefix length: {prefix!r}")
    escaped = (
        normalized.replace("/", "_slash_")
        .replace("\\", "_backslash_")
        .replace("*", "_star_")
        .replace("?", "_ques_")
        .replace("#", "_hash_")
        .replace(".", "_dot_")
    )
    url = "https://kaikki.org/dictionary/search/start/" + urllib.parse.quote(escaped) + ".json"
    return fetch_json(url)[1]


def find_kaikki_search_url(word: str) -> Optional[str]:
    normalized = word.casefold()
    prefixes = []
    if len(normalized) >= 3:
        prefixes.append(normalized[:3])
    if len(normalized) >= 2:
        prefixes.append(normalized[:2])
    for prefix in prefixes:
        try:
            rows = search_kaikki_prefix(prefix)
        except Exception:
            continue
        exact = [url for label, url in rows if label == word]
        if exact:
            return exact[0]
        folded = [url for label, url in rows if label.casefold() == normalized]
        if folded:
            return folded[0]
    return None


def parse_kaikki_candidates(word: str, html_text: str) -> list[dict]:
    soup = BeautifulSoup(html_text, "lxml")
    candidates: list[dict] = []
    for item in soup.select("ol > li[id]"):
        item_id = item.get("id", "")
        pos = extract_kaikki_pos(item_id)
        if pos is None:
            continue
        if pos not in ALLOWED_POS:
            continue
        gloss_node = item.select_one(".gloss")
        if gloss_node is None:
            continue
        definition = clean_markup(gloss_node.get_text(" ", strip=True))
        if not definition:
            continue
        relation_type, relation_target = parse_sense_relation(definition)
        score = 50
        plain = strip_leading_domain(definition)
        if 2 <= len(plain.split()) <= 18:
            score += 6
        if relation_type is None:
            score += 12
        else:
            score -= 10
        if word[:1].isupper() and word in plain:
            score += 6
        if any(tag in plain.casefold() for tag in ("phonetics", "medicine", "biology", "botany")):
            score += 2
        candidates.append(
            {
                "partOfSpeech": pos,
                "definition": plain,
                "relationType": relation_type,
                "relationTarget": relation_target,
                "source": "kaikki-html",
                "confidence": "high" if relation_type is None else "medium",
                "score": score,
            }
        )
    candidates.sort(key=lambda item: item["score"], reverse=True)
    return candidates


def choose_kaikki_candidate(word: str) -> Optional[dict]:
    url = build_kaikki_url(word)
    try:
        html_text = fetch_html(url)
    except Exception:
        return None
    candidates = parse_kaikki_candidates(word, html_text)
    if not candidates:
        return None
    return candidates[0]


def choose_kaikki_search_candidate(word: str) -> Optional[dict]:
    url = find_kaikki_search_url(word)
    if not url:
        return None
    try:
        html_text = fetch_html(url)
    except Exception:
        return None
    candidates = parse_kaikki_candidates(word, html_text)
    if not candidates:
        return None
    best = dict(candidates[0])
    best["source"] = "kaikki-search"
    return best


def choose_merriam_candidate(word: str) -> Optional[dict]:
    url = "https://www.merriam-webster.com/dictionary/" + urllib.parse.quote(word)
    try:
        page = fetch_html(url)
    except Exception:
        return None
    match = re.search(r'<meta name="description" content="([^"]+)"', page)
    if not match:
        return None
    description = html.unescape(match.group(1))
    pattern = re.compile(rf"The meaning of {re.escape(word.upper())} is (.+?)(?:\\. How to use|\\.$)")
    matched = pattern.search(description)
    if not matched:
        matched = re.search(r" is (.+?)(?:\\. How to use|\\.$)", description)
    if not matched:
        return None
    definition = clean_markup(matched.group(1))
    if not definition:
        return None
    relation_type, relation_target = parse_sense_relation(definition)
    pos = infer_pos(word, definition)
    return {
        "partOfSpeech": pos,
        "definition": strip_leading_domain(definition),
        "relationType": relation_type,
        "relationTarget": relation_target,
        "source": "merriam-meta",
        "confidence": "medium",
        "score": 30,
    }


def choose_morphology_candidate(word: str) -> Optional[dict]:
    lower = word.casefold()
    if lower.endswith("idae"):
        return {
            "partOfSpeech": "noun",
            "definition": "A taxonomic family.",
            "relationType": None,
            "relationTarget": None,
            "source": "morphology",
            "confidence": "low",
            "score": 15,
        }
    if lower.endswith("aceae"):
        return {
            "partOfSpeech": "noun",
            "definition": "A botanical family.",
            "relationType": None,
            "relationTarget": None,
            "source": "morphology",
            "confidence": "low",
            "score": 15,
        }
    if lower.endswith("ales"):
        return {
            "partOfSpeech": "noun",
            "definition": "A taxonomic order.",
            "relationType": None,
            "relationTarget": None,
            "source": "morphology",
            "confidence": "low",
            "score": 14,
        }
    if lower.endswith("oidea"):
        return {
            "partOfSpeech": "noun",
            "definition": "A taxonomic superfamily or related group.",
            "relationType": None,
            "relationTarget": None,
            "source": "morphology",
            "confidence": "low",
            "score": 14,
        }
    if lower.startswith("labio") and lower.endswith("ize"):
        return {
            "partOfSpeech": "verb",
            "definition": "To make or pronounce with involvement of the lips and another articulated area.",
            "relationType": None,
            "relationTarget": None,
            "source": "morphology",
            "confidence": "low",
            "score": 13,
        }
    if lower.startswith("labio") and lower.endswith("al"):
        return {
            "partOfSpeech": "adjective",
            "definition": "Relating to the lips and another articulatory or anatomical structure.",
            "relationType": None,
            "relationTarget": None,
            "source": "morphology",
            "confidence": "low",
            "score": 12,
        }
    return None


def choose_placeholder_candidate(word: str) -> dict:
    return {
        "partOfSpeech": infer_pos(word),
        "definition": "A rare or specialized English term.",
        "relationType": None,
        "relationTarget": None,
        "source": "placeholder",
        "confidence": "low",
        "score": 0,
    }


def choose_candidate(word: str) -> dict:
    if word in SPECIAL_CANDIDATES:
        return dict(SPECIAL_CANDIDATES[word])

    candidates: list[dict] = []
    kaikkei = choose_kaikki_candidate(word)
    if kaikkei is not None:
        candidates.append(kaikkei)

    kaikkei_search = choose_kaikki_search_candidate(word)
    if kaikkei_search is not None:
        candidates.append(kaikkei_search)

    merriam = choose_merriam_candidate(word)
    if merriam is not None:
        candidates.append(merriam)

    if not candidates and not word.islower():
        lower_kaikki = choose_kaikki_candidate(word.casefold())
        if lower_kaikki is not None:
            lowered_definition = lower_kaikki["definition"]
            if word in lowered_definition or any(
                marker in lowered_definition.casefold()
                for marker in ("genus", "family", "order", "taxonomic", "species")
            ):
                candidates.append(lower_kaikki)

    morphology = choose_morphology_candidate(word)
    if morphology is not None:
        candidates.append(morphology)

    if not candidates:
        return choose_placeholder_candidate(word)
    candidates.sort(key=lambda item: item["score"], reverse=True)
    return candidates[0]


def infer_pos(word: str, definition: str = "") -> str:
    lower_word = word.casefold()
    lower_definition = definition.casefold()
    if lower_definition.startswith("to "):
        return "verb"
    if lower_word.endswith("ly"):
        return "adverb"
    if lower_word.endswith(("ness", "ment", "ship", "dom", "hood", "ity", "ism", "tion", "sion", "ance", "ence", "acy")):
        return "noun"
    if lower_word.endswith(("less", "ous", "ful", "ish", "ical", "able", "ible", "al", "ate", "ed", "like")):
        return "adjective"
    return "noun"


def normalize_phrase(definition: str) -> str:
    phrase = strip_leading_domain(definition).rstrip(".")
    for prefix in (
        "relating to ",
        "pertaining to ",
        "involving ",
        "characterized by ",
        "consisting of ",
        "capable of ",
        "having ",
    ):
        if phrase.casefold().startswith(prefix):
            phrase = phrase[len(prefix):]
            break
    for prefix in ("a ", "an ", "the "):
        if phrase.casefold().startswith(prefix):
            phrase = phrase[len(prefix):]
            break
    return phrase


def domain_from_definition(definition: str) -> str:
    lower = definition.casefold()
    if any(token in lower for token in ("phonetics", "articulated", "uttered", "consonant", "vowel", "lip and tongue", "lip and upper teeth", "alveolar ridge")):
        return "phonetics"
    if any(token in lower for token in ("cervix", "pharynx", "larynx", "maxilla", "chin", "teeth", "tooth", "surgery", "medical", "clinical")):
        return "medical"
    if any(
        token in lower
        for token in (
            "mathematical",
            "mathematics",
            "geometry",
            "algebra",
            "equation",
            "quadratic",
            "quantitative",
            "quantity",
            "ratio",
            "proportion",
            "measurement",
            "measure",
            "number",
            "numeric",
            "fourfold",
            "fivefold",
        )
    ):
        return "math"
    if any(token in lower for token in ("genus", "family", "order", "species", "botanical", "tree", "plant", "orchid", "flower", "herb", "moss", "lichen", "fungus", "alga")):
        return "taxonomy"
    if any(token in lower for token in ("instrument", "device", "tool")):
        return "instrument"
    return "general"


def clean_chinese_text(text: str) -> str:
    cleaned = clean_markup(text).strip()
    cleaned = re.sub(r"\s+", "", cleaned)
    cleaned = re.sub(r"[。．]{2,}", "。", cleaned)
    cleaned = re.sub(r"[，,]{2,}", "，", cleaned)
    cleaned = re.sub(r"。([，,])", "。", cleaned)
    return cleaned.strip(" 　")


def primary_meaning_text(meaning: str) -> str:
    primary = re.split(r"[；;（(]", clean_chinese_text(meaning), maxsplit=1)[0].strip()
    return primary.rstrip("。")


def primary_definition_gloss(definition: str) -> str:
    for part in re.split(r"[；;]", strip_leading_domain(definition)):
        gloss = clean_markup(part).strip().strip(".")
        if gloss:
            return gloss
    return strip_leading_domain(definition)


def translate_sentence_text(english: str, fallback: str) -> str:
    translated = clean_chinese_text(translate_text(english))
    if not translated or translated.casefold() == english.casefold():
        return fallback
    return translated


def extract_base_word(word: str, suffix: str) -> str:
    base = word[: -len(suffix)]
    if suffix in {"ness", "less", "ful", "ly", "proof", "ship", "hood"} and base.endswith("i"):
        return base[:-1] + "y"
    if suffix == "ability" and base.endswith("i"):
        return base[:-1] + "y"
    if suffix in {"ation", "ation", "ative", "able"} and base.endswith("ic"):
        return base
    return base


def guess_placeholder_gloss(word: str, part_of_speech: str) -> Optional[str]:
    clean_word = clean_markup(word).strip()
    if not clean_word:
        return None
    if " " in clean_word:
        return clean_word

    lower = clean_word.casefold()
    suffix_rules = [
        ("ability", "the ability or quality of being {base}"),
        ("ness", "the state or quality of being {base}"),
        ("ship", "the role, state, or quality of {base}"),
        ("proof", "resistant to {base}"),
        ("less", "without {base}"),
        ("ful", "full of {base}"),
        ("like", "like {base}"),
        ("hearted", "having a {base} heart or temperament"),
        ("able", "able to be {base}"),
        ("ation", "the act or process related to {base}"),
        ("ition", "the act or process related to {base}"),
        ("ment", "the act, process, or result related to {base}"),
        ("ism", "a doctrine, condition, or practice related to {base}"),
        ("ist", "a person connected with {base}"),
        ("ize", "to make something {base}"),
        ("ise", "to make something {base}"),
        ("ation", "the act or process of making something {base}"),
        ("ic", "related to {base}"),
        ("ical", "related to {base}"),
        ("ous", "full of or related to {base}"),
        ("al", "related to {base}"),
        ("ary", "related to {base}"),
        ("ian", "related to {base}"),
        ("oid", "resembling {base}"),
        ("ly", "in a {base} way"),
    ]
    for suffix, template in suffix_rules:
        if lower.endswith(suffix) and len(clean_word) > len(suffix) + 2:
            base = extract_base_word(clean_word, suffix).replace("-", " ")
            if base:
                return template.format(base=base)

    if part_of_speech == "adverb" and lower.endswith("ly") and len(clean_word) > 4:
        return f"in a {clean_word[:-2]} way"
    if part_of_speech == "adjective":
        return f"related to {clean_word}"
    if part_of_speech == "verb":
        return f"to use or make something {clean_word}"
    if part_of_speech == "noun":
        return clean_word
    return None


def guess_placeholder_meaning(word: str, part_of_speech: str) -> str:
    translated_word = clean_chinese_text(translate_text(word))
    if translated_word and translated_word.casefold() != word.casefold():
        if part_of_speech == "adverb" and translated_word.endswith("地"):
            return translated_word
        if part_of_speech == "adjective" and (translated_word.endswith("的") or translated_word.endswith("狀") or translated_word.endswith("化")):
            return translated_word
        if part_of_speech == "noun" and translated_word not in {"四鳥"}:
            return translated_word

    gloss = guess_placeholder_gloss(word, part_of_speech)
    if gloss:
        translated = clean_chinese_text(translate_text(gloss))
        if translated and translated.casefold() not in {gloss.casefold(), word.casefold()}:
            return translated

    return PLACEHOLDER_MEANING


def meaning_from_candidate(word: str, candidate: dict) -> str:
    source = candidate.get("source")
    definition = candidate["definition"]
    lower = definition.casefold()
    part_of_speech = candidate.get("partOfSpeech")
    if source == "placeholder":
        return guess_placeholder_meaning(word, part_of_speech or infer_pos(word, definition))
    translated = clean_chinese_text(translate_text(definition))
    if part_of_speech == "adverb":
        translated = clean_chinese_text(translate_text(primary_definition_gloss(definition)))
    if not translated or translated.casefold() == definition.casefold():
        translated = PLACEHOLDER_MEANING
    if source == "morphology":
        if part_of_speech == "verb":
            return "使其發音同時涉及嘴唇與另一個發音部位。"
        if "family" in lower:
            return "分類學上的一個科。"
        if "order" in lower:
            return "分類學上的一個目。"
        if "superfamily" in lower:
            return "分類學上的一個總科或相關類群。"
    return translated


def generate_placeholder_sentence_pairs(word: str, part_of_speech: str, meaning_zh: str) -> tuple[str, str, str, str]:
    meaning_core = primary_meaning_text(meaning_zh) or "相關概念"
    if part_of_speech == "adverb":
        return (
            f"Writers sometimes use {word} to describe how an action happens.",
            f"寫作者有時會用這個副詞來描述動作發生的方式。",
            f"Readers may still see {word} in older or specialist writing.",
            "讀者仍可能在較早或較專門的文本中看到這個副詞。",
        )
    if part_of_speech == "adjective":
        return (
            f"Specialist notes describe one feature as {word}.",
            f"專業說明有時會用這個詞描述「{meaning_core}」這類特徵。",
            f"The term {word} appears in technical descriptions and older dictionaries.",
            "這個詞也可能出現在技術性描述或較早的字典中。",
        )
    if part_of_speech == "verb":
        return (
            f"Older sources sometimes use {word} as a verb in a specialized context.",
            "較早的資料有時會把這個字當成動詞使用。",
            f"Readers may encounter {word} when a text needs that exact specialized meaning.",
            f"當文本需要表達「{meaning_core}」這類意思時，讀者可能會看到這個動詞。",
        )
    return (
        f"The glossary lists {word} as a specialized term.",
        f"詞彙表會把這個詞列為一個較專門的名稱。",
        f"Readers may encounter {word} in older or technical writing.",
        "讀者可能會在較早或技術性的文章中看到這個詞。",
    )


def classify_adverb_usage(word: str, definition: str, meaning_zh: str) -> str:
    lower = definition.casefold()
    lower_word = word.casefold()
    lower_meaning = meaning_zh.casefold()
    if any(
        token in lower
        for token in ("qualitative", "quantitative", "quote", "quotation", "cited", "described", "measured", "valued", "valent")
    ) or any(token in lower_word for token in ("qualit", "quantit", "quot", "value", "valent")) or any(
        token in lower_meaning for token in ("定性", "定量", "量化", "引用", "可引用", "四價")
    ):
        return "analysis"
    if any(
        token in lower
        for token in (
            "every ",
            "daily",
            "weekly",
            "monthly",
            "yearly",
            "annually",
            "once",
            "twice",
            "per ",
            "periodic",
            "habitual",
            "usual",
        )
    ) or any(token in lower_meaning for token in ("每", "日常", "經常", "一次")):
        return "frequency"
    if any(
        token in lower
        for token in (
            "square",
            "angular",
            "corner",
            "sided",
            "in four parts",
            "in five parts",
            "crosswise",
            "arranged",
            "positioned",
        )
    ) or any(token in meaning_zh for token in ("四邊形", "四方", "角", "交錯", "排列", "象限", "部分")):
        return "arrangement"
    if any(
        token in lower
        for token in (
            "question",
            "curious",
            "quizzical",
            "complain",
            "quarrel",
            "fear",
            "trembl",
            "quiet",
            "quick",
            "eager",
        )
    ) or any(
        token in lower_word
        for token in ("question", "quiz", "quer", "quarrel", "quiver", "quake", "quick", "quiet", "quixot", "queasy")
    ):
        return "reaction"
    return "fallback"


def generate_relation_sentence_pairs(word: str, relation_type: str, target: str) -> tuple[str, str, str, str]:
    target_clean = clean_markup(target).strip()
    if relation_type == "plural":
        return (
            f"The article used {word} when referring to more than one {target_clean}.",
            "文章在表達複數概念時會用到這個詞形。",
            f"Students learned that {word} is the plural form of {target_clean}.",
            "學生學到這個字是相應的複數形式。",
        )
    if relation_type == "singular":
        return (
            f"The glossary gives {word} as the singular form connected with {target_clean}.",
            "詞彙表把這個字列為相應的單數形式。",
            f"Readers can meet {word} when a text shifts from plural to singular reference.",
            "當文字從複數轉成單數表達時，讀者可能會看到這個字。",
        )
    if relation_type == "alternative":
        return (
            f"Older sources sometimes write {word} as an alternative form of {target_clean}.",
            "較早的資料有時會使用這個變體拼法。",
            f"Editors kept {word} in the word bank so readers can recognize that variant spelling.",
            "這筆資料保留下來，是為了讓讀者辨認這種變體拼法。",
        )
    if relation_type in {"past", "past_participle", "present_participle", "third_person"}:
        return (
            f"The grammar note lists {word} as a verb form connected with {target_clean}.",
            "文法說明把這個字列為相關動詞的詞形變化。",
            f"Learners may see {word} in older or more formal examples built from {target_clean}.",
            "學習者可能會在較早或較正式的例句中看到這個字。",
        )
    if relation_type in {"comparative", "superlative"}:
        return (
            f"The handbook records {word} as a comparison form related to {target_clean}.",
            "手冊把這個字列為相關的比較形式。",
            f"Students compared {word} with the base adjective {target_clean} during review.",
            "複習時，學生會把這個字和原來的形容詞一起比較。",
        )
    return (
        f"The dictionary note connects {word} with {target_clean}.",
        "字典說明把這個字和另一個相關形式連在一起。",
        f"Readers may notice {word} when comparing related English forms.",
        "讀者在比對相關英文詞形時，可能會注意到這個字。",
    )


def generate_sentence_pairs(word: str, part_of_speech: str, definition: str, meaning_zh: str, relation_type: Optional[str], relation_target: Optional[str], source: Optional[str]) -> tuple[str, str, str, str]:
    if relation_type and relation_target:
        return generate_relation_sentence_pairs(word, relation_type, relation_target)
    if source == "placeholder":
        return generate_placeholder_sentence_pairs(word, part_of_speech, meaning_zh)

    phrase = normalize_phrase(definition)
    domain = domain_from_definition(definition)
    lower = definition.casefold()
    meaning_core = primary_meaning_text(meaning_zh) or "相關概念"

    if part_of_speech == "verb":
        return (
            f"The older text uses {word} to mean {phrase}.",
            "較早或較專門的文本會用到這個動詞。",
            f"Careful readers can still spot {word} in historical or specialist writing.",
            "讀者仍可能在歷史或專業寫作中看到這個動詞。",
        )

    if part_of_speech == "adverb":
        if domain == "math":
            sentence_one = f"The report models the change {word} over time."
            sentence_two = f"Researchers described the pattern {word} in the final section."
            return (
                sentence_one,
                translate_sentence_text(sentence_one, "報告用這個副詞描述變化的方式。"),
                sentence_two,
                translate_sentence_text(sentence_two, "研究者在最後一節用這個副詞描述相關模式。"),
            )
        usage = classify_adverb_usage(word, definition, meaning_zh)
        if usage == "frequency":
            sentence_one = f"The festival is held {word} in the old town square."
            sentence_two = f"The committee reviews the rules {word}."
            return (
                sentence_one,
                translate_sentence_text(sentence_one, "這個副詞可用來表達某件事發生的頻率。"),
                sentence_two,
                translate_sentence_text(sentence_two, "這個副詞也可以用來描述定期進行的安排。"),
            )
        elif usage == "arrangement":
            sentence_one = f"The lamps were arranged {word} around the hall."
            sentence_two = f"The paths were laid out {word} near the garden."
            return (
                sentence_one,
                translate_sentence_text(sentence_one, "這個副詞可用來描述物件的排列方式。"),
                sentence_two,
                translate_sentence_text(sentence_two, "這個副詞也可以表示空間上的配置方式。"),
            )
        elif usage == "reaction":
            sentence_one = f"She looked {word} at the note on the door."
            sentence_two = f"He answered {word} when the question was repeated."
            return (
                sentence_one,
                translate_sentence_text(sentence_one, "這個副詞可用來描述人物的反應方式。"),
                sentence_two,
                translate_sentence_text(sentence_two, "這個副詞也能表達回應時的語氣或態度。"),
            )
        elif usage == "analysis":
            sentence_one = f"The study discusses the change {word} in its main section."
            sentence_two = f"The writer described the contrast {word} in the final paragraph."
            return (
                sentence_one,
                translate_sentence_text(sentence_one, "這個副詞可用來描述分析或討論的方式。"),
                sentence_two,
                translate_sentence_text(sentence_two, "這個副詞也能用來表達說明或比較的角度。"),
            )
        else:
            sentence_one = f"Writers sometimes use {word} to describe how something happened."
            sentence_two = f"Readers may still see {word} in older or specialist writing."
            return (
                sentence_one,
                "這個副詞可用來描述事情發生的方式。",
                sentence_two,
                "讀者仍可能在較早或較專門的文本中看到這個副詞。",
            )

    if part_of_speech == "adjective":
        if domain == "phonetics":
            return (
                f"In phonetics, {word} describes something involving {phrase}.",
                "在語音學裡，這個詞用來描述這種發音特徵。",
                f"Students used {word} while describing the sound pattern.",
                "學生在描述這種發音模式時會用到這個詞。",
            )
        if domain == "medical":
            return (
                f"The clinician used {word} to describe the feature in the exam notes.",
                "臨床說明會用這個詞來描述相關的身體結構或狀態。",
                f"The diagram highlights a {word} structure near the front of the mouth.",
                "圖解也可能用這個詞標示相應的部位。",
            )
        if domain == "taxonomy":
            return (
                f"Researchers used {word} when noting the specimen's traits.",
                "研究紀錄會用這個詞描述樣本的特徵。",
                f"The guide points out a {word} feature that helps identify the specimen.",
                "圖鑑會指出這種特徵，幫助辨認標本。",
            )
        return (
            f"The report uses {word} to describe a related feature.",
            "報告用這個詞來描述某種相關特徵。",
            f"Readers may encounter {word} in descriptive or specialist writing.",
            "讀者可能會在描述性或專業文本中看到這個詞。",
        )

    if part_of_speech == "noun":
        if domain == "instrument":
            return (
                f"The lab used a {word} while measuring subtle speech movements.",
                "實驗室在測量細微動作時會使用這種儀器。",
                f"The technician checked the {word} before the recording session began.",
                "技術員會在開始記錄前先檢查這個裝置。",
            )
        if domain == "phonetics":
            return (
                f"The textbook mentions {word} when introducing less common speech terms.",
                "語音學教材在介紹較少見術語時會提到這個詞。",
                f"Students wrote down the meaning of {word} during the phonetics lesson.",
                f"學生在語音學課上會記下「{meaning_core}」這個意思。",
            )
        if domain == "medical":
            return (
                f"The doctor explained the role of {word} during the consultation.",
                "醫師說明時會提到這個部位或概念的作用。",
                f"The training diagram labels {word} beside the related anatomy.",
                "教學圖示也可能把這個名稱標在相關解剖部位旁邊。",
            )
        if domain == "taxonomy":
            if "family" in lower or "order" in lower or "genus" in lower or word[:1].isupper():
                return (
                    f"Biologists list {word} in reference works on classification.",
                    "分類參考資料會列出這個名稱。",
                    f"The museum label mentions {word} when explaining the specimen's group.",
                    "標本標籤在說明所屬類群時也可能提到這個名稱。",
                )
            return (
                f"The field guide identifies {word} among similar living things.",
                "野外圖鑑會用這個名稱區分相近的生物。",
                f"Researchers recorded {word} during their survey of the area.",
                "研究人員在調查時也可能記錄到這個名稱。",
            )
        if (
            any(token in lower for token in ("biblical", "father of", "mother of", "brother of", "uncle of", "surname", "given name"))
            or re.search(r"\b(city|province|king)\b", lower)
        ):
            return (
                f"The reference note explains who {word} is in its historical setting.",
                "參考資料會交代這個名字在歷史或文本中的身分。",
                f"Students came across {word} while reading an older text.",
                "學生閱讀較早的文本時，可能會遇到這個名字。",
            )
        return (
            f"The glossary explains that {word} means {phrase}.",
            "詞彙表會說明這個詞的意思。",
            f"Readers may encounter {word} in specialist books or historical writing.",
            "讀者可能會在專業書籍或較早的文獻中看到這個詞。",
        )

    return (
        f"The entry for {word} explains that it means {phrase}.",
        f"條目說明這個字表示「{meaning_core}」。",
        f"Readers can still meet {word} in dictionaries and specialized texts.",
        "讀者仍可能在字典或專業文本中看到這個字。",
    )


def estimate_difficulty(word: str, relation_target: Optional[str], hs_levels: dict[str, int]) -> int:
    key = normalize_key(relation_target or word)
    if key in hs_levels:
        return hs_levels[key]
    freq = zipf_frequency(key, "en")
    if freq >= 6.0:
        return 1
    if freq >= 5.0:
        return 2
    if freq >= 4.5:
        return 3
    if freq >= 4.0:
        return 4
    if freq >= 3.0:
        return 5
    return 6


def school_levels_for_difficulty(level: int) -> list[str]:
    if level <= 1:
        return ["elementary", "juniorHigh", "seniorHigh"]
    if level == 2:
        return ["juniorHigh", "seniorHigh"]
    if level in {3, 4}:
        return ["seniorHigh"]
    return ["seniorHigh", "college"]


def metadata_for_entry(word: str, meaning: str, sentences: list[str], definition: str, difficulty: int, hs_levels: dict[str, int], exam_book_words: set[str]) -> tuple[list[str], list[str], list[str], list[str]]:
    key = normalize_key(word)
    combined_text = f"{word} {meaning} {' '.join(sentences)} {definition}"
    definition_domain = domain_from_definition(definition)
    school_levels = school_levels_for_difficulty(difficulty)
    exam_tags: list[str] = []
    audience_tags: list[str] = []
    source_tags: list[str] = []

    if key in hs_levels:
        source_tags.append("twCeec")
        if difficulty >= 5:
            source_tags.append("collegeSignals")
    elif key in exam_book_words:
        source_tags.append("pdfExamBook")

    workplace_match = definition_domain != "taxonomy" and (
        key in WORKPLACE_WORDS or contains_any(combined_text, WORKPLACE_SIGNALS)
    )
    academic_match = key in ACADEMIC_WORDS or contains_any(combined_text, ACADEMIC_SIGNALS)

    if workplace_match:
        exam_tags.append("toeic")
        source_tags.append("toeicSignals")
    if academic_match or difficulty >= 5:
        if "college" not in school_levels:
            school_levels.append("college")
        source_tags.append("collegeSignals")

    if not school_levels and not exam_tags:
        audience_tags.append("general")

    school_levels = [item for item in SCHOOL_LEVELS if item in set(school_levels)]
    exam_tags = [item for item in EXAM_TAGS if item in set(exam_tags)]
    audience_tags = ["general"] if audience_tags else []
    deduped_source: list[str] = []
    seen_source = set()
    for tag in source_tags:
        if tag in SOURCE_TAGS and tag not in seen_source:
            deduped_source.append(tag)
            seen_source.add(tag)
    if not deduped_source:
        deduped_source = ["collegeSignals"] if difficulty >= 4 else ["pdfExamBook"]
    return school_levels, exam_tags, audience_tags, deduped_source


def build_entry(word: str, hs_levels: dict[str, int], exam_book_words: set[str]) -> tuple[dict, str, str]:
    candidate = choose_candidate(word)
    definition = candidate["definition"]
    relation_type = candidate.get("relationType")
    relation_target = candidate.get("relationTarget")
    part_of_speech = candidate["partOfSpeech"]
    if part_of_speech not in ALLOWED_POS:
        part_of_speech = infer_pos(word, definition)

    translated_definition = meaning_from_candidate(word, candidate)
    sentence_one, translated_one, sentence_two, translated_two = generate_sentence_pairs(
        word,
        part_of_speech,
        definition,
        translated_definition,
        relation_type,
        relation_target,
        candidate.get("source"),
    )
    translated_definition = clean_chinese_text(translated_definition) or PLACEHOLDER_MEANING
    translated_one = clean_chinese_text(translated_one) or "這個詞會出現在相關語境中。"
    translated_two = clean_chinese_text(translated_two) or "讀者可能會在字典或專業文本中看到這個詞。"

    difficulty = estimate_difficulty(word, relation_target, hs_levels)
    sentences = [
        f"{clean_markup(sentence_one)} {translated_one}",
        f"{clean_markup(sentence_two)} {translated_two}",
    ]
    school_levels, exam_tags, audience_tags, source_tags = metadata_for_entry(
        word,
        translated_definition,
        sentences,
        definition,
        difficulty,
        hs_levels,
        exam_book_words,
    )

    entry = {
        "word": word,
        "meaning": translated_definition,
        "partOfSpeech": part_of_speech,
        "sentences": sentences,
        "difficultyLevel": difficulty,
        "schoolLevels": school_levels,
        "sourceTags": source_tags,
    }
    if exam_tags:
        entry["examTags"] = exam_tags
    if audience_tags:
        entry["audienceTags"] = audience_tags
    return entry, candidate["source"], candidate["confidence"]


def load_completed_batches(path: Path) -> set[int]:
    if not path.exists():
        return set()
    data = load_json(path)
    return {
        int(index)
        for index in data.get("completedBatches", [])
        if isinstance(index, int) or (isinstance(index, str) and str(index).isdigit())
    }


def sync_progress(prefix: str, source_path: Path, target_path: Path, log_dir: Path, manifest: dict, completed_batches: set[int]) -> dict:
    source_words = load_source_words(source_path, prefix)
    target_words = load_target_words(target_path, prefix)
    coverage = build_coverage(source_words, target_words, prefix)
    write_json(log_dir / "coverage.json", coverage)
    write_lines(log_dir / "missing_words.txt", coverage["missingWords"])
    write_lines(log_dir / "extra_words.txt", coverage["extraWords"])
    run_progress = {
        "completedBatches": sorted(completed_batches),
        "completedBatchCount": len(completed_batches),
        "batchCount": int(manifest.get("batchCount", 0)),
        "remainingBatches": max(int(manifest.get("batchCount", 0)) - len(completed_batches), 0),
        "targetCount": len(target_words),
        "coveredCount": coverage["coveredCount"],
        "missingCount": coverage["missingCount"],
        "exactCoverage": True,
    }
    write_json(log_dir / "run_progress.json", run_progress)
    return coverage


def main() -> int:
    args = parse_args()
    manifest = load_json(args.manifest)
    batch_dir = args.log_dir / "batches"
    run_progress_path = args.log_dir / "run_progress.json"
    completion_summary_path = args.log_dir / "completion_summary.json"
    end_batch = args.end_batch if args.end_batch is not None else int(manifest["batchCount"]) - 1

    hs_levels = parse_hs_levels(args.hs_pdf)
    exam_book_words = load_exam_book_words(args.exam_book_words)
    target_entries = sort_entries(load_json(args.target))
    existing_words = {entry["word"] for entry in target_entries}
    completed_batches = load_completed_batches(run_progress_path)
    source_counter: Counter[str] = Counter()
    confidence_counter: Counter[str] = Counter()

    for batch_index in range(args.start_batch, end_batch + 1):
        if batch_index in completed_batches and not args.force:
            print(f"BATCH {batch_index:03d}: already completed, skipping", flush=True)
            continue

        batch_txt = batch_dir / f"batch_{batch_index:03d}.txt"
        batch_json = batch_dir / f"batch_{batch_index:03d}.json"
        words = [line.strip() for line in batch_txt.read_text(encoding="utf-8").splitlines() if line.strip()]
        if not args.force:
            words = [word for word in words if word not in existing_words]
        if not words:
            completed_batches.add(batch_index)
            sync_progress(args.prefix, args.source, args.target, args.log_dir, manifest, completed_batches)
            print(f"BATCH {batch_index:03d}: nothing to add", flush=True)
            continue

        print(f"BATCH {batch_index:03d}: generating {len(words)} words", flush=True)
        with concurrent.futures.ThreadPoolExecutor(max_workers=args.workers) as executor:
            built = list(executor.map(lambda word: build_entry(word, hs_levels, exam_book_words), words))

        batch_entries = [entry for entry, _source, _confidence in built]
        for _entry, source, confidence in built:
            source_counter[source] += 1
            confidence_counter[confidence] += 1

        write_json(batch_json, batch_entries)

        by_word = {entry["word"]: entry for entry in target_entries}
        for entry in batch_entries:
            by_word[entry["word"]] = entry
            existing_words.add(entry["word"])
        target_entries = sort_entries(list(by_word.values()))
        write_json(args.target, target_entries)

        completed_batches.add(batch_index)
        coverage = sync_progress(args.prefix, args.source, args.target, args.log_dir, manifest, completed_batches)
        print(
            f"BATCH {batch_index:03d}: added={len(batch_entries)} total={len(target_entries)} remaining_missing={coverage['missingCount']}",
            flush=True,
        )

    final_coverage = sync_progress(args.prefix, args.source, args.target, args.log_dir, manifest, completed_batches)
    write_json(
        completion_summary_path,
        {
            "startBatch": args.start_batch,
            "endBatch": end_batch,
            "targetCount": final_coverage["targetPrefixCount"],
            "coveredCount": final_coverage["coveredCount"],
            "missingCount": final_coverage["missingCount"],
            "sourceCounts": dict(source_counter),
            "confidenceCounts": dict(confidence_counter),
        },
    )
    print(
        f"DONE start_batch={args.start_batch} end_batch={end_batch} "
        f"covered={final_coverage['coveredCount']} missing={final_coverage['missingCount']}",
        flush=True,
    )
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
