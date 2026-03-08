#!/usr/bin/env python3
import argparse
import json
import re
import sys
import urllib.parse
from concurrent.futures import ThreadPoolExecutor
from pathlib import Path
from typing import Optional

from wordfreq import zipf_frequency

CURRENT_DIR = Path(__file__).resolve().parent
if str(CURRENT_DIR) not in sys.path:
    sys.path.insert(0, str(CURRENT_DIR))

from repair_html_polluted_word_bank_entries import clean_markup, fetch_json


ROOT = Path(__file__).resolve().parents[1]
WORD_BANK_PATH = ROOT / "assets" / "word_bank" / "word_bank_main.json"
SOURCE_PATH = ROOT / "assets" / "word_bank" / "en"
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
POS_MAP = {
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
BAD_DEF_PATTERNS = [
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
    "superseded spelling",
]
BAD_TEXT = [
    "offensive",
    "vulgar",
    "slur",
    "ethnic slur",
    "racial slur",
    "city in",
    "town in",
    "village in",
    "country in",
    "county in",
    "province of",
]
BANNED_WORDS = {
    "dumbledore",
    "trump",
    "twitter",
    "york",
    "russia",
    "japan",
    "boston",
    "barcelona",
    "arsenal",
    "finland",
    "panama",
    "geneva",
    "montana",
    "berlin",
    "harry",
    "henry",
    "mary",
    "peter",
    "jane",
    "morgan",
    "buddy",
    "bitch",
    "damn",
    "crap",
    "dont",
    "didnt",
    "doesnt",
    "cannot",
}


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser()
    parser.add_argument("--target", type=int, default=1000)
    parser.add_argument("--batch-size", type=int, default=40)
    parser.add_argument("--window-size", type=int, default=300)
    parser.add_argument("--workers", type=int, default=20)
    parser.add_argument("--min-zipf", type=float, default=2.8)
    parser.add_argument("--write-every-batch", action="store_true")
    return parser.parse_args()


def load_word_bank() -> list[dict]:
    with WORD_BANK_PATH.open(encoding="utf-8") as file:
        return json.load(file)


def write_word_bank(data: list[dict]) -> None:
    data.sort(key=lambda item: item["word"].casefold())
    with WORD_BANK_PATH.open("w", encoding="utf-8") as file:
        json.dump(data, file, ensure_ascii=False, indent=2)
        file.write("\n")


def build_covered_tokens(existing_words: set[str]) -> set[str]:
    covered = set()
    for word in existing_words:
        for token in re.split(r"[^a-z]+", word):
            if token:
                covered.add(token)
    return covered


def load_candidates(existing_words: set[str], covered_tokens: set[str], min_zipf: float) -> list[str]:
    candidates = []
    with SOURCE_PATH.open(encoding="utf-8") as file:
        for raw in file:
            word = raw.strip()
            if not word or not re.fullmatch(r"[a-z]+", word):
                continue
            if not 4 <= len(word) <= 15:
                continue
            if word in existing_words or word in covered_tokens or word in BANNED_WORDS:
                continue
            if zipf_frequency(word, "en") < min_zipf:
                continue
            candidates.append(word)
    return sorted(set(candidates), key=lambda word: (-zipf_frequency(word, "en"), word))


def choose_definition(word: str) -> Optional[dict]:
    try:
        data = fetch_json(
            "https://en.wiktionary.org/api/rest_v1/page/definition/" + urllib.parse.quote(word)
        )
    except Exception:
        return None

    candidates = []
    for entry in data.get("en", []):
        bank_pos = POS_MAP.get(entry.get("partOfSpeech"))
        if bank_pos not in ALLOWED_POS:
            continue
        for order, definition_obj in enumerate(entry.get("definitions", [])):
            raw_definition = (definition_obj.get("definition") or "").strip()
            definition = clean_markup(raw_definition)
            if not definition:
                continue
            lower_definition = definition.lower()
            if any(pattern in lower_definition for pattern in BAD_DEF_PATTERNS):
                continue
            if any(pattern in lower_definition for pattern in BAD_TEXT):
                continue
            if len(definition.split()) < 3 or len(definition.split()) > 22:
                continue
            examples = []
            for example in definition_obj.get("examples") or []:
                cleaned_example = clean_markup(example)
                if not cleaned_example or len(cleaned_example.split()) < 4:
                    continue
                if any(pattern in cleaned_example.lower() for pattern in BAD_TEXT):
                    continue
                examples.append(cleaned_example)
            score = 0
            if 4 <= len(definition.split()) <= 18:
                score += 3
            if examples:
                score += 4
            if word in lower_definition:
                score -= 2
            score -= order / 10
            candidates.append(
                {
                    "score": score,
                    "word": word,
                    "partOfSpeech": bank_pos,
                    "definition": definition,
                    "examples": examples[:2],
                }
            )

    if not candidates:
        return None
    candidates.sort(key=lambda item: item["score"], reverse=True)
    best = candidates[0]
    if best["score"] < 6:
        return None
    return best


def translate_text(text: str) -> str:
    try:
        obj = fetch_json(
            "https://translate.googleapis.com/translate_a/single"
            "?client=gtx&sl=en&tl=zh-TW&dt=t&q=" + urllib.parse.quote(text)
        )
        return clean_markup("".join(segment[0] for segment in obj[0] if segment and segment[0]))
    except Exception:
        return clean_markup(text)


def fallback_examples(word: str, part_of_speech: str, definition: str) -> list[str]:
    if part_of_speech == "noun":
        return [
            f"The term {word} refers to {definition.rstrip('.')}.",
            f"We learned the meaning of {word} during today's lesson.",
        ]
    if part_of_speech == "verb":
        return [
            f"People often {word} when the situation calls for it.",
            f"Learning when to {word} can improve communication.",
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


def build_entry(meta: dict) -> dict:
    meaning = translate_text(meta["definition"])
    examples = list(meta["examples"])
    if len(examples) < 2:
        examples.extend(fallback_examples(meta["word"], meta["partOfSpeech"], meta["definition"]))
    sentences = []
    for english in examples[:2]:
        english = clean_markup(english).replace("\\n", " ")
        chinese = translate_text(english)
        sentences.append(f"{english} {chinese}")
    return {
        "word": meta["word"],
        "meaning": meaning,
        "partOfSpeech": meta["partOfSpeech"],
        "sentences": sentences,
    }


def main() -> None:
    args = parse_args()
    data = load_word_bank()
    existing_words = {item["word"] for item in data}
    covered_tokens = build_covered_tokens(existing_words)
    candidates = load_candidates(existing_words, covered_tokens, args.min_zipf)

    print(f"base_count={len(data)} candidate_pool={len(candidates)}", flush=True)

    added = 0
    cursor = 0
    pending = []
    batches = 0

    while added < args.target and cursor < len(candidates):
        window = candidates[cursor : cursor + args.window_size]
        cursor += len(window)
        with ThreadPoolExecutor(max_workers=args.workers) as executor:
            results = list(executor.map(choose_definition, window))
        accepted_now = 0
        for meta in results:
            if not meta:
                continue
            if meta["word"] in existing_words:
                continue
            entry = build_entry(meta)
            pending.append(entry)
            existing_words.add(entry["word"])
            accepted_now += 1
            while len(pending) >= args.batch_size and added < args.target:
                take = pending[: args.batch_size]
                pending = pending[args.batch_size :]
                data.extend(take)
                batches += 1
                added += len(take)
                if args.write_every_batch:
                    write_word_bank(data)
                print(
                    f"BATCH {batches}: added={len(take)} total_added={added} cursor={cursor} main_count={len(data)} last_word={take[-1]['word']}",
                    flush=True,
                )
                if added >= args.target:
                    break
        print(
            f"WINDOW done: cursor={cursor} accepted_now={accepted_now} pending={len(pending)} total_added={added}",
            flush=True,
        )

    if pending and added < args.target:
        need = min(args.target - added, len(pending))
        take = pending[:need]
        data.extend(take)
        batches += 1
        added += len(take)
        print(
            f"FINAL BATCH {batches}: added={len(take)} total_added={added} cursor={cursor} main_count={len(data)}",
            flush=True,
        )

    write_word_bank(data)
    print(f"DONE added_total={added} final_count={len(data)} batches={batches}", flush=True)


if __name__ == "__main__":
    main()
