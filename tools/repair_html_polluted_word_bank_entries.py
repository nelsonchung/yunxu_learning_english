#!/usr/bin/env python3
import argparse
import concurrent.futures
import html
import json
import re
import time
import urllib.parse
import urllib.request
from pathlib import Path
from typing import Optional, Tuple

from bs4 import BeautifulSoup


ROOT = Path(__file__).resolve().parents[1]
WORD_BANK_PATH = ROOT / "assets" / "word_bank" / "word_bank_main.json"
HTML_TAG_RE = re.compile(r"<[^>]+>")
WHITESPACE_RE = re.compile(r"\s+")

WIKTIONARY_POS_TO_BANK = {
    "Noun": "noun",
    "Verb": "verb",
    "Adjective": "adjective",
    "Adverb": "adverb",
    "Pronoun": "pronoun",
    "Preposition": "preposition",
    "Conjunction": "conjunction",
    "Interjection": "exclamation",
    "Determiner": "determiner",
}

BANK_POS_PRIORITY = {
    "noun": 0,
    "verb": 1,
    "adjective": 2,
    "adverb": 3,
    "pronoun": 4,
    "determiner": 5,
    "preposition": 6,
    "conjunction": 7,
    "exclamation": 8,
}

BAD_DEFINITION_PATTERNS = [
    "alternative form",
    "alternative spelling",
    "obsolete",
    "misspelling",
    "plural of",
    "past tense of",
    "past participle of",
    "present participle of",
    "third-person singular",
    "comparative of",
    "superlative of",
    "initialism",
    "abbreviation",
    "clipping",
    "acronym",
    "surname",
    "given name",
    "proper noun",
    "inflection of",
    "eye dialect",
    "nonstandard spelling",
    "dated spelling",
]


def fetch_json(url: str, retries: int = 3) -> dict:
    last_error = None
    for attempt in range(retries):
        req = urllib.request.Request(url, headers={"User-Agent": "Mozilla/5.0"})
        try:
            with urllib.request.urlopen(req, timeout=20) as response:
                return json.loads(response.read().decode("utf-8"))
        except Exception as exc:  # pragma: no cover - network retries
            last_error = exc
            time.sleep(0.5 * (attempt + 1))
    raise last_error


def clean_markup(text: str) -> str:
    if not text:
        return ""
    text = html.unescape(text)
    text = text.replace("\n", " ")
    soup = BeautifulSoup(text, "html.parser")
    cleaned = soup.get_text(" ", strip=True)
    cleaned = html.unescape(cleaned)
    cleaned = cleaned.replace("\xa0", " ")
    cleaned = WHITESPACE_RE.sub(" ", cleaned).strip()
    cleaned = re.sub(r"\s+([,.;:?!])", r"\1", cleaned)
    cleaned = re.sub(r"([(\[])\s+", r"\1", cleaned)
    cleaned = re.sub(r"\s+([)\]])", r"\1", cleaned)
    return cleaned.strip()


def translate_text(text: str) -> str:
    if not text:
        return ""
    url = (
        "https://translate.googleapis.com/translate_a/single"
        "?client=gtx&sl=en&tl=zh-TW&dt=t&q=" + urllib.parse.quote(text)
    )
    try:
        obj = fetch_json(url)
        return clean_markup("".join(segment[0] for segment in obj[0] if segment and segment[0]))
    except Exception:
        return clean_markup(text)


def contains_markup(item: dict) -> bool:
    if HTML_TAG_RE.search(item.get("meaning", "")):
        return True
    return any(HTML_TAG_RE.search(sentence) for sentence in item.get("sentences", []))


def choose_candidate(word: str, current_pos: str, wiktionary_data: dict) -> Optional[dict]:
    candidates = []
    for entry in wiktionary_data.get("en", []):
        bank_pos = WIKTIONARY_POS_TO_BANK.get(entry.get("partOfSpeech"))
        if not bank_pos:
            continue
        pos_matches = bank_pos == current_pos
        for order, definition_obj in enumerate(entry.get("definitions", [])):
            raw_definition = (definition_obj.get("definition") or "").strip()
            definition = clean_markup(raw_definition)
            if not definition:
                continue
            lower_definition = definition.lower()
            if any(pattern in lower_definition for pattern in BAD_DEFINITION_PATTERNS):
                continue
            examples = []
            for example in definition_obj.get("examples") or []:
                cleaned_example = clean_markup(example)
                if cleaned_example and len(cleaned_example.split()) >= 4:
                    examples.append(cleaned_example)
            score = 0
            if pos_matches:
                score += 10
            score -= BANK_POS_PRIORITY.get(bank_pos, 99)
            if 3 <= len(definition.split()) <= 18:
                score += 3
            if examples:
                score += 3
            if definition.lower().startswith(("a ", "an ", "the ")) and bank_pos == "noun":
                score += 1
            if word.lower() in lower_definition:
                score -= 2
            score -= order / 10
            candidates.append(
                {
                    "score": score,
                    "partOfSpeech": bank_pos,
                    "definition": definition,
                    "examples": examples[:2],
                }
            )
    if not candidates:
        return None
    candidates.sort(key=lambda item: item["score"], reverse=True)
    return candidates[0]


def make_fallback_examples(word: str, part_of_speech: str, definition: str) -> list[str]:
    if part_of_speech == "noun":
        return [
            f"The term {word} refers to {definition.rstrip('.')}.",
            f"We learned the meaning of {word} during today's lesson.",
        ]
    if part_of_speech == "verb":
        return [
            f"People often {word} when the situation calls for it.",
            f"Learning when to {word} helps you communicate more clearly.",
        ]
    if part_of_speech == "adjective":
        return [
            f"The report describes the result as {word}.",
            f"Everyone noticed the {word} tone of the message.",
        ]
    if part_of_speech == "adverb":
        return [
            f"The team responded {word} to the change.",
            f"She handled the problem {word} during the meeting.",
        ]
    return [
        f"The lesson introduced {word} as a useful term to understand.",
        f"Students practiced using {word} in class.",
    ]


def rebuild_entry(item: dict) -> Tuple[dict, str]:
    word = item["word"]
    current_pos = item["partOfSpeech"]
    try:
        wiktionary_data = fetch_json(
            "https://en.wiktionary.org/api/rest_v1/page/definition/" + urllib.parse.quote(word)
        )
        candidate = choose_candidate(word, current_pos, wiktionary_data)
    except Exception:
        candidate = None

    if candidate is None:
        meaning = clean_markup(item.get("meaning", ""))
        if not meaning:
            meaning = word
        examples = [clean_markup(sentence) for sentence in item.get("sentences", []) if clean_markup(sentence)]
        fallback_source = "fallback-clean"
        if len(examples) < 2:
            examples.extend(make_fallback_examples(word, current_pos, meaning))
        built_sentences = []
        for english in examples[:2]:
            english = clean_markup(english)
            if word.lower() not in english.lower():
                english = english.rstrip(".") + f". The word {word} is central here."
            chinese = translate_text(english)
            built_sentences.append(f"{english} {chinese}")
        return {
            "word": word,
            "meaning": meaning,
            "partOfSpeech": current_pos,
            "sentences": built_sentences,
        }, fallback_source

    examples = candidate["examples"]
    if len(examples) < 2:
        examples.extend(make_fallback_examples(word, candidate["partOfSpeech"], candidate["definition"]))
    meaning = translate_text(candidate["definition"])
    built_sentences = []
    for english in examples[:2]:
        english = clean_markup(english)
        if word.lower() not in english.lower():
            english = english.rstrip(".") + f". The word {word} is central here."
        chinese = translate_text(english)
        built_sentences.append(f"{english} {chinese}")
    rebuilt = {
        "word": word,
        "meaning": meaning,
        "partOfSpeech": candidate["partOfSpeech"],
        "sentences": built_sentences,
    }
    return rebuilt, "wiktionary-rebuild"


def clean_existing_entry(item: dict) -> dict:
    word = item["word"]
    meaning = clean_markup(item.get("meaning", "")) or word
    english_lines = []
    for sentence in item.get("sentences", []):
        cleaned_sentence = clean_markup(sentence)
        if cleaned_sentence:
            english_lines.append(cleaned_sentence)
    if len(english_lines) < 2:
        english_lines.extend(make_fallback_examples(word, item["partOfSpeech"], meaning))
    sentences = []
    for english in english_lines[:2]:
        if word.lower() not in english.lower():
            english = english.rstrip(".") + f". The word {word} is central here."
        chinese = translate_text(english)
        sentences.append(f"{english} {chinese}")
    return {
        "word": word,
        "meaning": meaning,
        "partOfSpeech": item["partOfSpeech"],
        "sentences": sentences,
    }


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser()
    parser.add_argument("--words", nargs="*", help="Only repair these words.")
    parser.add_argument("--limit", type=int, help="Only repair the first N polluted entries.")
    parser.add_argument("--workers", type=int, default=8)
    parser.add_argument("--write", action="store_true")
    return parser.parse_args()


def main() -> None:
    args = parse_args()
    with WORD_BANK_PATH.open(encoding="utf-8") as file:
        data = json.load(file)

    targets = [item for item in data if contains_markup(item)]
    if args.words:
        wanted = set(args.words)
        targets = [item for item in data if item["word"] in wanted]
    if args.limit is not None:
        targets = targets[: args.limit]

    print(f"target_count={len(targets)}", flush=True)
    if not targets:
        return

    by_word = {item["word"]: item for item in data}
    stats = {}

    with concurrent.futures.ThreadPoolExecutor(max_workers=args.workers) as executor:
        future_map = {executor.submit(rebuild_entry, item): item["word"] for item in targets}
        for index, future in enumerate(concurrent.futures.as_completed(future_map), start=1):
            word = future_map[future]
            try:
                rebuilt, source = future.result()
            except Exception:
                rebuilt = clean_existing_entry(by_word[word])
                source = "exception-clean"
            by_word[word] = rebuilt
            stats[source] = stats.get(source, 0) + 1
            if index % 25 == 0 or index == len(targets):
                print(f"processed={index}/{len(targets)}", flush=True)

    output = sorted(by_word.values(), key=lambda item: item["word"].casefold())
    if args.write:
        with WORD_BANK_PATH.open("w", encoding="utf-8") as file:
            json.dump(output, file, ensure_ascii=False, indent=2)
            file.write("\n")

    print("stats", json.dumps(stats, ensure_ascii=False, sort_keys=True), flush=True)


if __name__ == "__main__":
    main()
