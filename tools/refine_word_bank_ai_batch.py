#!/usr/bin/env python3
"""AI-assisted batch refiner for polluted word-bank example sentences.

The deterministic refiner is intentionally conservative. This helper asks a
local model for varied candidate sentences, then applies only candidates that
pass strict local validation.
"""

from __future__ import annotations

import argparse
import importlib.util
import json
import re
import subprocess
import sys
from datetime import datetime
from pathlib import Path
from typing import Any


ROOT = Path(__file__).resolve().parents[1]
DEFAULT_PATH = ROOT / "assets" / "word_bank" / "word_bank_main-f.json"
BASE_REFINER = ROOT / "tools" / "refine_word_bank_sentences.py"


BAD_TEXT_RE = re.compile(
    r"這個詞|這個副詞|這個形容詞|這個動詞|詞彙表|例句|博物館標籤|舊展品|"
    r"褪色地圖|natural sentence|clear example|technical passage|glossary|meaning of|"
    r"如何用|作者|作家|可以可|Writers use|The word .+ still appears in older books and notes|"
    r"Something described as|The term .+ refers to|learned the meaning of",
    re.IGNORECASE,
)

AI_FORBIDDEN_RE = re.compile(
    r"作者|作家|這個詞|這個字|這個副詞|這個形容詞|這個動詞|詞彙表|例句|造句|"
    r"字典|辭典|舊書|較舊的書|舊筆記|博物館標籤|舊展品|褪色地圖|"
    r"Writers use|writer|author|word list|glossary|dictionary|old books|old notes|"
    r"meaning of|How to use|in a sentence|clear example|natural sentence|technical passage",
    re.IGNORECASE,
)

WEAK_MEANING_TEXT_RE = re.compile(
    r"罕見.*術語|罕见.*术语|記錄為|记录为|如何使用|如何用|造句|How to use|"
    r"同義詞|同義字|同义词|同义字|dated form|過時形式|过时形式",
    re.IGNORECASE,
)


def load_base_refiner() -> Any:
    spec = importlib.util.spec_from_file_location("base_refiner", BASE_REFINER)
    if spec is None or spec.loader is None:
        raise RuntimeError(f"Unable to load {BASE_REFINER}")
    module = importlib.util.module_from_spec(spec)
    sys.modules["base_refiner"] = module
    spec.loader.exec_module(module)
    return module


BASE = load_base_refiner()


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(
        description="Use Gemini to rewrite polluted word-bank sentences in guarded batches."
    )
    parser.add_argument("--path", default=str(DEFAULT_PATH), help="Shard path to refine.")
    parser.add_argument("--apply", action="store_true", help="Write validated changes.")
    parser.add_argument("--batch-size", type=int, default=24, help="Entries per model call.")
    parser.add_argument("--iterations", type=int, default=1, help="Model calls to run.")
    parser.add_argument("--model", help="Optional Gemini model name.")
    parser.add_argument("--report", help="Optional JSON report path.")
    parser.add_argument(
        "--include-weak-meaning",
        action="store_true",
        help="Also send entries whose meaning is flagged as noisy or placeholder-like.",
    )
    parser.add_argument(
        "--only-bad-text",
        action="store_true",
        help="Only select entries whose existing sentences contain explicit template/pollution text.",
    )
    parser.add_argument(
        "--artifact-dir",
        default=str(ROOT / ".omx" / "artifacts"),
        help="Directory for a markdown artifact with prompts and raw model output.",
    )
    parser.add_argument(
        "--artifact-slug",
        default="word-bank-f-ai-refine",
        help="Artifact filename slug.",
    )
    parser.add_argument(
        "--timeout",
        type=int,
        default=240,
        help="Timeout in seconds for each Gemini call.",
    )
    return parser.parse_args()


def repo_path(raw_path: str) -> Path:
    path = Path(raw_path)
    return path if path.is_absolute() else ROOT / path


def read_json(path: Path) -> Any:
    with path.open(encoding="utf-8") as file:
        return json.load(file)


def write_json(path: Path, payload: Any) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    temp_path = path.with_name(f".{path.name}.tmp")
    with temp_path.open("w", encoding="utf-8") as file:
        json.dump(payload, file, ensure_ascii=False, indent=2)
        file.write("\n")
    temp_path.replace(path)


def has_bad_sentence(entry: dict[str, Any]) -> bool:
    sentences = [str(sentence) for sentence in entry.get("sentences") or []]
    reasons = BASE.entry_reasons(entry)
    return bool(BAD_TEXT_RE.search("\n".join(sentences))) or (
        reasons and BASE.needs_sentence_refine(reasons)
    )


def candidate_entries(
    data: list[dict[str, Any]],
    skipped: set[str],
    include_weak_meaning: bool,
    only_bad_text: bool,
) -> list[tuple[int, dict[str, Any]]]:
    rows: list[tuple[int, dict[str, Any]]] = []
    for index, entry in enumerate(data):
        word = str(entry.get("word", "")).strip()
        if not word or word.lower() in skipped:
            continue
        sentences_text = "\n".join(str(sentence) for sentence in entry.get("sentences") or [])
        if only_bad_text and not BAD_TEXT_RE.search(sentences_text):
            continue
        reasons = BASE.entry_reasons(entry)
        if "weak_or_noisy_meaning" in reasons and not include_weak_meaning:
            continue
        if WEAK_MEANING_TEXT_RE.search(str(entry.get("meaning", ""))) and not include_weak_meaning:
            continue
        if has_bad_sentence(entry):
            rows.append((index, entry))
    return rows


def make_prompt(entries: list[dict[str, Any]]) -> str:
    compact_entries = [
        {
            "word": str(entry.get("word", "")),
            "partOfSpeech": str(entry.get("partOfSpeech", "")),
            "meaning": str(entry.get("meaning", "")),
            "currentSentences": entry.get("sentences") or [],
        }
        for entry in entries
    ]
    return (
        "You are rewriting an English-learning word bank for Traditional Chinese learners.\n"
        "Return STRICT JSON only: an array of objects in the same order. Each object must be:\n"
        '{"word":"...","sentences":["English sentence. 繁體中文翻譯。","English sentence. 繁體中文翻譯。"]}\n'
        "The sentences array must contain exactly two combined bilingual strings. Do not split English and Chinese into separate array items.\n"
        'If the meaning is too vague, contradictory, or unsafe to infer, return {"word":"...","sentences":null,"reason":"..."}.\n\n'
        "Rules:\n"
        "- Write real example sentences, not definitions. The English sentence must naturally use the target word.\n"
        "- Keep the English simple and concrete. Prefer daily life, school, clinic, lab, office, repair, travel, or family contexts.\n"
        "- The Chinese translation must be natural Traditional Chinese and must NOT copy the English target word.\n"
        "- Avoid the words 作者, 作家, 這個詞, 這個字, 詞彙表, 例句, 字典, 舊書, old books, writer, author, glossary, dictionary.\n"
        "- Do not use filler such as museum labels, faded maps, old displays, old notes, or 'the word still appears'.\n"
        "- Use varied sentence structures across the two examples.\n"
        "- For rare technical words, make a realistic but plain sentence in the correct domain.\n"
        "- Do not invent a different meaning from the provided meaning. Skip if unsure.\n\n"
        "Entries:\n"
        f"{json.dumps(compact_entries, ensure_ascii=False, indent=2)}\n"
    )


def run_gemini(prompt: str, args: argparse.Namespace) -> str:
    command = ["gemini"]
    if args.model:
        command.extend(["--model", args.model])
    command.extend(["--prompt", prompt, "--output-format", "text"])
    result = subprocess.run(
        command,
        cwd=ROOT,
        text=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.STDOUT,
        timeout=args.timeout,
        check=False,
    )
    if result.returncode != 0:
        raise RuntimeError(result.stdout.strip() or f"gemini exited with {result.returncode}")
    return result.stdout


def extract_json_array(raw_output: str) -> Any:
    decoder = json.JSONDecoder()
    candidates: list[Any] = []
    for match in re.finditer(r"\[", raw_output):
        try:
            payload, _ = decoder.raw_decode(raw_output[match.start() :])
        except json.JSONDecodeError:
            continue
        if (
            isinstance(payload, list)
            and payload
            and all(isinstance(item, dict) and "word" in item for item in payload)
        ):
            candidates.append(payload)
    if not candidates:
        raise ValueError("No word-bank JSON array found in model output")
    return candidates[-1]


def english_contains_word(word: str, english: str) -> bool:
    normalized_word = word.lower().strip()
    normalized_english = english.lower()
    if " " in normalized_word:
        return normalized_word in normalized_english
    return bool(re.search(rf"(?<![a-z]){re.escape(normalized_word)}(?:s|es|ed|ing|ly)?(?![a-z])", normalized_english))


def validate_sentence(word: str, sentence: str, index: int) -> list[str]:
    errors: list[str] = []
    english, zh = BASE.split_bilingual_sentence(sentence)
    if not english or not zh:
        errors.append(f"missing_bilingual_half:s{index}")
        return errors
    if not english_contains_word(word, english):
        errors.append(f"english_missing_word:s{index}")
    if BASE.raw_word_in_zh(word, sentence):
        errors.append(f"raw_word_in_zh:s{index}")
    if AI_FORBIDDEN_RE.search(sentence) or BASE.QUALITY_RE.search(sentence) or BASE.META_OUTPUT_RE.search(sentence):
        errors.append(f"forbidden_or_meta_text:s{index}")
    if len(english.split()) < 4:
        errors.append(f"english_too_short:s{index}")
    if len(zh) < 4:
        errors.append(f"zh_too_short:s{index}")
    return errors


def validate_result(entry: dict[str, Any], result: dict[str, Any]) -> tuple[list[str], list[str]]:
    word = str(entry.get("word", "")).strip()
    if str(result.get("word", "")).strip().lower() != word.lower():
        return [], ["word_mismatch"]
    sentences = result.get("sentences")
    if sentences is None:
        reason = str(result.get("reason", "model_skipped"))[:80]
        return [], [f"model_skipped:{reason}"]
    if isinstance(sentences, list) and len(sentences) == 4 and all(isinstance(item, str) for item in sentences):
        sentences = [f"{sentences[0].strip()} {sentences[1].strip()}", f"{sentences[2].strip()} {sentences[3].strip()}"]
    if not isinstance(sentences, list) or len(sentences) != 2 or not all(isinstance(item, str) for item in sentences):
        return [], ["invalid_sentence_shape"]
    errors: list[str] = []
    for index, sentence in enumerate(sentences, start=1):
        errors.extend(validate_sentence(word, sentence, index))
    if sentences[0] == sentences[1]:
        errors.append("duplicate_sentences")
    return sentences, errors


def main() -> int:
    args = parse_args()
    path = repo_path(args.path)
    data = read_json(path)
    if not isinstance(data, list):
        raise SystemExit(f"Expected a JSON list: {path}")

    skipped: set[str] = set()
    changes: list[dict[str, Any]] = []
    rejected: list[dict[str, Any]] = []
    artifacts: list[dict[str, str]] = []

    for iteration in range(1, args.iterations + 1):
        candidates = candidate_entries(
            data, skipped, args.include_weak_meaning, args.only_bad_text
        )[: args.batch_size]
        if not candidates:
            break
        indexes = [index for index, _ in candidates]
        entries = [entry for _, entry in candidates]
        prompt = make_prompt(entries)
        try:
            raw_output = run_gemini(prompt, args)
        except Exception as exc:
            for index, entry in candidates:
                word = str(entry.get("word", ""))
                skipped.add(word.lower())
                rejected.append(
                    {
                        "iteration": iteration,
                        "index": index,
                        "word": word,
                        "errors": [f"model_error:{exc}"],
                    }
                )
            print(
                json.dumps(
                    {
                        "iteration": iteration,
                        "changeCount": 0,
                        "rejectedCount": len(candidates),
                        "applied": bool(args.apply),
                        "error": "model_error",
                    },
                    ensure_ascii=False,
                ),
                flush=True,
            )
            continue
        artifacts.append({"prompt": prompt, "rawOutput": raw_output})
        try:
            results = extract_json_array(raw_output)
        except Exception as exc:
            for index, entry in candidates:
                word = str(entry.get("word", ""))
                skipped.add(word.lower())
                rejected.append(
                    {
                        "iteration": iteration,
                        "index": index,
                        "word": word,
                        "errors": [f"json_parse_error:{exc}"],
                        "rawOutput": raw_output[:2000],
                    }
                )
            continue
        if not isinstance(results, list) or len(results) != len(entries):
            for index, entry in candidates:
                word = str(entry.get("word", ""))
                skipped.add(word.lower())
                rejected.append(
                    {
                        "iteration": iteration,
                        "index": index,
                        "word": word,
                        "errors": ["result_count_mismatch"],
                    }
                )
            continue
        iteration_changes = 0
        iteration_rejected = 0
        for index, entry, result in zip(indexes, entries, results, strict=True):
            word = str(entry.get("word", ""))
            if not isinstance(result, dict):
                skipped.add(word.lower())
                iteration_rejected += 1
                rejected.append(
                    {
                        "iteration": iteration,
                        "index": index,
                        "word": word,
                        "errors": ["result_not_object"],
                    }
                )
                continue
            new_sentences, errors = validate_result(entry, result)
            if errors:
                skipped.add(word.lower())
                iteration_rejected += 1
                rejected.append(
                    {
                        "iteration": iteration,
                        "index": index,
                        "word": word,
                        "errors": errors,
                        "proposedSentences": result.get("sentences"),
                    }
                )
                continue
            old_sentences = entry.get("sentences") or []
            if old_sentences != new_sentences:
                change = {
                    "iteration": iteration,
                    "index": index,
                    "word": word,
                    "oldSentences": old_sentences,
                    "newSentences": new_sentences,
                }
                changes.append(change)
                iteration_changes += 1
                if args.apply:
                    entry["sentences"] = new_sentences
            skipped.add(word.lower())
        if args.apply and iteration_changes:
            write_json(path, data)
        print(
            json.dumps(
                {
                    "iteration": iteration,
                    "changeCount": iteration_changes,
                    "rejectedCount": iteration_rejected,
                    "applied": bool(args.apply),
                },
                ensure_ascii=False,
            ),
            flush=True,
        )

    timestamp = datetime.now().strftime("%Y%m%d-%H%M%S")
    artifact_dir = repo_path(args.artifact_dir)
    artifact_dir.mkdir(parents=True, exist_ok=True)
    artifact_path = artifact_dir / f"gemini-{args.artifact_slug}-{timestamp}.md"
    artifact_body = [
        "# Gemini Word-Bank Refinement",
        "",
        "## Original User Task",
        "",
        "Refine polluted bilingual example sentences in `word_bank_main-f.json`.",
        "",
        "## Final Prompt Sent To Gemini CLI",
        "",
        "Prompts are listed per batch below.",
        "",
        "## Gemini Output (Raw)",
        "",
        "Raw outputs are listed per batch below.",
        "",
    ]
    for number, item in enumerate(artifacts, start=1):
        artifact_body.extend(
            [
                f"### Batch {number} Prompt",
                "",
                "```text",
                item["prompt"],
                "```",
                "",
                f"### Batch {number} Raw Output",
                "",
                "```text",
                item["rawOutput"],
                "```",
                "",
            ]
        )
    artifact_body.extend(
        [
            "## Concise Summary",
            "",
            f"Validated changes: {len(changes)}. Rejected or skipped: {len(rejected)}.",
            "",
            "## Action Items / Next Steps",
            "",
            "Continue batch refinement and inspect rejected entries that lack reliable meanings.",
            "",
        ]
    )
    artifact_path.write_text("\n".join(artifact_body), encoding="utf-8")

    report = {
        "path": str(path),
        "applied": bool(args.apply),
        "changeCount": len(changes),
        "rejectedCount": len(rejected),
        "artifact": str(artifact_path),
        "changes": changes,
        "rejected": rejected,
    }
    if args.report:
        write_json(repo_path(args.report), report)
    print(
        json.dumps(
            {
                "changeCount": len(changes),
                "rejectedCount": len(rejected),
                "applied": bool(args.apply),
                "artifact": str(artifact_path),
            },
            ensure_ascii=False,
            indent=2,
        )
    )
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
