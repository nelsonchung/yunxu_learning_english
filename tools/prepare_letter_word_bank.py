#!/usr/bin/env python3
import argparse
import json
from collections import Counter, defaultdict
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
DEFAULT_SOURCE = ROOT / "assets" / "word_bank" / "en"


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(
        description="Prepare exact-coverage batch files for a letter-specific word bank."
    )
    parser.add_argument("--prefix", required=True, help="Letter prefix to process, such as l.")
    parser.add_argument("--target", required=True, help="Target word bank JSON path.")
    parser.add_argument("--log-dir", required=True, help="Directory to store manifest and batches.")
    parser.add_argument("--source", default=str(DEFAULT_SOURCE), help="Source word list path.")
    parser.add_argument("--batch-size", type=int, default=50, help="Words per batch.")
    return parser.parse_args()


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


def load_target_entries(path: Path) -> list[dict]:
    with path.open(encoding="utf-8") as file:
        data = json.load(file)
    if not isinstance(data, list):
        raise ValueError(f"{path} must contain a JSON array")
    return data


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


def chunked(words: list[str], size: int) -> list[list[str]]:
    return [words[index : index + size] for index in range(0, len(words), size)]


def main() -> int:
    args = parse_args()
    prefix = args.prefix
    source_path = Path(args.source).resolve()
    target_path = Path(args.target).resolve()
    log_dir = Path(args.log_dir).resolve()
    batch_dir = log_dir / "batches"
    batch_dir.mkdir(parents=True, exist_ok=True)

    source_words = load_source_words(source_path, prefix)
    target_entries = load_target_entries(target_path)
    target_words = [
        str(entry.get("word", "")).strip()
        for entry in target_entries
        if isinstance(entry, dict) and str(entry.get("word", "")).strip()
    ]
    target_prefix_words = [word for word in target_words if word.casefold().startswith(prefix.casefold())]

    source_counter = Counter(source_words)
    target_counter = Counter(target_prefix_words)
    source_exact = set(source_words)
    target_exact = set(target_prefix_words)

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

    duplicate_source_words = sorted(
        [word for word, count in source_counter.items() if count > 1],
        key=str.casefold,
    )
    duplicate_target_words = sorted(
        [word for word, count in target_counter.items() if count > 1],
        key=str.casefold,
    )

    batches = chunked(missing_words, args.batch_size)
    manifest_batches = []
    for index, words in enumerate(batches):
        batch_path = batch_dir / f"batch_{index:03d}.txt"
        write_lines(batch_path, words)
        manifest_batches.append(
            {
                "index": index,
                "path": str(batch_path.relative_to(ROOT)),
                "wordCount": len(words),
                "firstWord": words[0],
                "lastWord": words[-1],
            }
        )

    manifest = {
        "prefix": prefix,
        "sourcePath": str(source_path.relative_to(ROOT)),
        "targetPath": str(target_path.relative_to(ROOT)),
        "batchSize": args.batch_size,
        "sourceCount": len(source_words),
        "targetPrefixCount": len(target_prefix_words),
        "missingCount": len(missing_words),
        "batchCount": len(batches),
        "batches": manifest_batches,
    }
    write_json(log_dir / "manifest.json", manifest)

    coverage = {
        "prefix": prefix,
        "sourceCount": len(source_words),
        "targetPrefixCount": len(target_prefix_words),
        "coveredCount": len(source_exact & target_exact),
        "missingCount": len(missing_words),
        "extraCount": len(extra_words),
        "coverageRatio": round((len(source_exact & target_exact) / len(source_exact)) if source_exact else 1.0, 6),
        "missingWords": missing_words,
        "extraWords": extra_words,
        "casefoldCollisionCount": len(casefold_collisions),
        "casefoldCollisions": casefold_collisions,
        "duplicateSourceWords": duplicate_source_words,
        "duplicateTargetWords": duplicate_target_words,
    }
    write_json(log_dir / "coverage.json", coverage)
    write_lines(log_dir / "missing_words.txt", missing_words)
    write_lines(log_dir / "extra_words.txt", extra_words)

    progress = {
        "completedBatches": [],
        "completedBatchCount": 0,
        "targetCount": len(target_prefix_words),
        "coveredCount": len(source_exact & target_exact),
        "missingCount": len(missing_words),
        "exactCoverage": True,
    }
    write_json(log_dir / "run_progress.json", progress)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
