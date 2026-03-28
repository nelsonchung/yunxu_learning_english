#!/usr/bin/env python3
import argparse
import json
from collections import Counter, defaultdict
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
DEFAULT_SOURCE = ROOT / "assets" / "word_bank" / "en"


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(
        description="Sync coverage and run_progress for a fixed letter word-bank manifest."
    )
    parser.add_argument("--prefix", required=True)
    parser.add_argument("--target", required=True)
    parser.add_argument("--log-dir", required=True)
    parser.add_argument("--source", default=str(DEFAULT_SOURCE))
    parser.add_argument(
        "--completed-batch",
        dest="completed_batches",
        action="append",
        type=int,
        default=[],
        help="Batch index to mark as completed. Repeat for multiple batches.",
    )
    return parser.parse_args()


def load_json(path: Path):
    with path.open(encoding="utf-8") as file:
        return json.load(file)


def write_json(path: Path, payload) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    with path.open("w", encoding="utf-8") as file:
        json.dump(payload, file, ensure_ascii=False, indent=2)
        file.write("\n")


def write_lines(path: Path, lines: list[str]) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    with path.open("w", encoding="utf-8") as file:
        if lines:
            file.write("\n".join(lines))
            file.write("\n")


def load_source_words(path: Path, prefix: str) -> list[str]:
    normalized_prefix = prefix.casefold()
    words: list[str] = []
    with path.open(encoding="utf-8") as file:
        for raw in file:
            word = raw.strip()
            if not word:
                continue
            if word.casefold().startswith(normalized_prefix):
                words.append(word)
    return words


def load_target_words(path: Path, prefix: str) -> list[str]:
    entries = load_json(path)
    return [
        str(entry.get("word", "")).strip()
        for entry in entries
        if isinstance(entry, dict)
        and str(entry.get("word", "")).strip()
        and str(entry.get("word", "")).strip().casefold().startswith(prefix.casefold())
    ]


def build_coverage(source_words: list[str], target_words: list[str], prefix: str) -> dict:
    source_counter = Counter(source_words)
    target_counter = Counter(target_words)
    source_exact = set(source_words)
    target_exact = set(target_words)
    missing_words = [word for word in source_words if word not in target_exact]
    extra_words = sorted(target_exact - source_exact, key=str.casefold)

    source_casefold_groups: dict[str, list[str]] = defaultdict(list)
    for word in source_words:
        source_casefold_groups[word.casefold()].append(word)
    casefold_collisions = [
        sorted(group, key=str.casefold)
        for group in source_casefold_groups.values()
        if len(set(group)) > 1
    ]
    casefold_collisions.sort(key=lambda group: group[0].casefold())

    return {
        "prefix": prefix,
        "sourceCount": len(source_words),
        "targetPrefixCount": len(target_words),
        "coveredCount": len(source_exact & target_exact),
        "missingCount": len(missing_words),
        "extraCount": len(extra_words),
        "coverageRatio": round((len(source_exact & target_exact) / len(source_exact)) if source_exact else 1.0, 6),
        "missingWords": missing_words,
        "extraWords": extra_words,
        "casefoldCollisionCount": len(casefold_collisions),
        "casefoldCollisions": casefold_collisions,
        "duplicateSourceWords": sorted([word for word, count in source_counter.items() if count > 1], key=str.casefold),
        "duplicateTargetWords": sorted([word for word, count in target_counter.items() if count > 1], key=str.casefold),
    }


def main() -> int:
    args = parse_args()
    prefix = args.prefix
    source_path = Path(args.source).resolve()
    target_path = Path(args.target).resolve()
    log_dir = Path(args.log_dir).resolve()

    manifest_path = log_dir / "manifest.json"
    if not manifest_path.exists():
        raise FileNotFoundError(f"Missing manifest: {manifest_path}")
    manifest = load_json(manifest_path)
    batch_count = int(manifest.get("batchCount", 0))

    source_words = load_source_words(source_path, prefix)
    target_words = load_target_words(target_path, prefix)
    coverage = build_coverage(source_words, target_words, prefix)
    write_json(log_dir / "coverage.json", coverage)
    write_lines(log_dir / "missing_words.txt", coverage["missingWords"])
    write_lines(log_dir / "extra_words.txt", coverage["extraWords"])

    existing_progress_path = log_dir / "run_progress.json"
    completed: set[int] = set()
    if existing_progress_path.exists():
        existing_progress = load_json(existing_progress_path)
        completed.update(
            int(index)
            for index in existing_progress.get("completedBatches", [])
            if isinstance(index, int) or (isinstance(index, str) and str(index).isdigit())
        )
    completed.update(args.completed_batches)
    completed = {index for index in completed if 0 <= index < batch_count}

    run_progress = {
        "completedBatches": sorted(completed),
        "completedBatchCount": len(completed),
        "batchCount": batch_count,
        "remainingBatches": max(batch_count - len(completed), 0),
        "targetCount": len(target_words),
        "coveredCount": coverage["coveredCount"],
        "missingCount": coverage["missingCount"],
        "exactCoverage": True,
    }
    write_json(log_dir / "run_progress.json", run_progress)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
