#!/usr/bin/env python3
"""Build per-shard sentence refine queues from review_word_bank_content output."""

from __future__ import annotations

import argparse
import importlib.util
import json
import sys
from collections import Counter
from pathlib import Path
from typing import Any


ROOT = Path(__file__).resolve().parents[1]
REVIEW_TOOL = ROOT / "tools" / "review_word_bank_content.py"


def load_review_module() -> Any:
    spec = importlib.util.spec_from_file_location("review_tool", REVIEW_TOOL)
    if spec is None or spec.loader is None:
        raise RuntimeError(f"Unable to load {REVIEW_TOOL}")
    module = importlib.util.module_from_spec(spec)
    sys.modules["review_tool"] = module
    spec.loader.exec_module(module)
    return module


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(
        description="Queue sentence-refine candidates for a word-bank shard."
    )
    parser.add_argument("--path", required=True, help="Shard JSON path.")
    parser.add_argument(
        "--min-score",
        type=int,
        default=2,
        help="Minimum review score to include in the queue.",
    )
    parser.add_argument(
        "--report",
        help="Optional output JSON path. Defaults to logs/refine/<shard>.queue.json",
    )
    return parser.parse_args()


def repo_path(raw_path: str) -> Path:
    path = Path(raw_path)
    return path if path.is_absolute() else ROOT / path


def default_report_path(shard_path: Path) -> Path:
    return ROOT / "logs" / "refine" / f"{shard_path.stem}.queue.json"


def main() -> int:
    args = parse_args()
    review = load_review_module()
    shard_path = repo_path(args.path)
    with shard_path.open(encoding="utf-8") as file:
        data = json.load(file)

    if not isinstance(data, list):
        raise SystemExit(f"Expected a JSON list: {shard_path}")

    candidates: list[dict[str, Any]] = []
    reason_counts: Counter[str] = Counter()

    for index, entry in enumerate(data):
        result = review.review_entry(index, entry)
        if result is None or result["score"] < args.min_score:
            continue
        for reason, count in result["reasonCounts"].items():
            reason_counts[reason] += count
        candidates.append(
            {
                "index": index,
                "word": result["word"],
                "score": result["score"],
                "reasons": result["reasons"],
                "reasonCounts": result["reasonCounts"],
                "partOfSpeech": result.get("partOfSpeech", ""),
                "meaning": result.get("meaning", ""),
                "sentences": result.get("sentences", []),
            }
        )

    report_path = repo_path(args.report) if args.report else default_report_path(shard_path)
    report_path.parent.mkdir(parents=True, exist_ok=True)
    payload = {
        "path": str(shard_path),
        "entryCount": len(data),
        "candidateCount": len(candidates),
        "minScore": args.min_score,
        "reasonCounts": dict(reason_counts.most_common()),
        "candidates": candidates,
    }
    with report_path.open("w", encoding="utf-8") as file:
        json.dump(payload, file, ensure_ascii=False, indent=2)

    print(
        json.dumps(
            {
                "path": str(shard_path),
                "entryCount": len(data),
                "candidateCount": len(candidates),
                "report": str(report_path),
                "topReasons": reason_counts.most_common(8),
            },
            ensure_ascii=False,
            indent=2,
        )
    )
    return 0


if __name__ == "__main__":
    raise SystemExit(main())