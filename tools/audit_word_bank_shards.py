#!/usr/bin/env python3
import argparse
import json
import os
import subprocess
import sys
from collections import Counter
from datetime import datetime, timezone
from pathlib import Path
from typing import Any, Dict, Iterable, List, Optional


ROOT = Path(__file__).resolve().parents[1]
DEFAULT_PATTERN = "assets/word_bank/word_bank_main-[a-z].json"
DEFAULT_OUTPUT_DIR = ROOT / "logs" / "word_bank_audit" / "latest"
VALIDATOR = ROOT / "tools" / "validate_word_bank_main.py"
REVIEWER = ROOT / "tools" / "review_word_bank_content.py"


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(
        description="Audit all word_bank_main-[a-z].json shards and write summary reports."
    )
    parser.add_argument(
        "--pattern",
        default=DEFAULT_PATTERN,
        help="Glob pattern for shard files, relative to repository root.",
    )
    parser.add_argument(
        "--letters",
        help="Comma-separated or compact list of letters to audit, for example 'p' or 'p,q,r'.",
    )
    parser.add_argument(
        "--output-dir",
        default=str(DEFAULT_OUTPUT_DIR),
        help="Directory for aggregated reports.",
    )
    parser.add_argument(
        "--format",
        choices=("text", "json", "md"),
        default="text",
        help="Stdout output format.",
    )
    parser.add_argument(
        "--fail-on-errors",
        action="store_true",
        help="Return non-zero when any validation failure, missing shard, or tool failure is present.",
    )
    parser.add_argument(
        "--fail-on-threshold",
        action="append",
        default=[],
        metavar="KEY=VALUE",
        help="Fail if a summary metric is greater than VALUE. Supported keys: validation_failed_files, validation_errors, validation_warnings, content_candidates, missing_shards.",
    )
    parser.add_argument(
        "--min-score",
        type=int,
        default=2,
        help="Minimum review score passed to review_word_bank_content.py.",
    )
    return parser.parse_args()


def current_timestamp() -> str:
    return datetime.now(timezone.utc).isoformat(timespec="seconds").replace("+00:00", "Z")


def parse_letters(raw: Optional[str]) -> List[str]:
    if not raw:
        return [chr(code) for code in range(ord("a"), ord("z") + 1)]
    letters: List[str] = []
    for chunk in raw.split(","):
        piece = chunk.strip().lower()
        if not piece:
            continue
        if len(piece) == 1 and piece.isalpha():
            letters.append(piece)
            continue
        if piece.isalpha():
            letters.extend(char for char in piece if char.isalpha())
            continue
        raise ValueError(f"Unsupported letters value: {raw!r}")
    unique = sorted(set(letters))
    if not unique:
        raise ValueError("At least one valid letter is required")
    return unique


def repo_path(path: str) -> Path:
    candidate = Path(path)
    return candidate if candidate.is_absolute() else ROOT / candidate


def write_json(path: Path, payload: Any) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    temp_path = path.with_name(f".{path.name}.tmp")
    with temp_path.open("w", encoding="utf-8") as file:
        json.dump(payload, file, ensure_ascii=False, indent=2)
        file.write("\n")
    os.replace(temp_path, path)


def write_text(path: Path, text: str) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    temp_path = path.with_name(f".{path.name}.tmp")
    temp_path.write_text(text, encoding="utf-8")
    os.replace(temp_path, path)


def run_json_command(command: List[str]) -> tuple[int, Dict[str, Any]]:
    result = subprocess.run(command, cwd=ROOT, capture_output=True, text=True)
    payload = {}
    if result.stdout.strip():
        payload = json.loads(result.stdout)
    return result.returncode, payload


def render_markdown(summary: Dict[str, Any]) -> str:
    lines = [
        "# Word Bank Shard Audit Summary",
        "",
        f"- GeneratedAt: {summary['generatedAt']}",
        f"- Pattern: `{summary['pattern']}`",
        f"- Requested letters: `{','.join(summary['requestedLetters'])}`",
        f"- Scanned files: {summary['scannedFileCount']}",
        f"- Missing shards: {summary['missingShardCount']}",
        f"- Validation failed files: {summary['validation']['failedFiles']}",
        f"- Validation errors: {summary['validation']['errorCount']}",
        f"- Validation warnings: {summary['validation']['warningCount']}",
        f"- Content candidates: {summary['review']['candidateCount']}",
        "",
        "## Top Review Reasons",
        "",
    ]
    for reason, count in summary["review"]["topReasons"]:
        lines.append(f"- `{reason}`: {count}")
    lines.extend(["", "## Priority Files", ""])
    for item in summary["priorityFiles"]:
        lines.append(
            f"- `{item['file']}`: validationStatus={item['validationStatus']}, "
            f"errors={item['errorCount']}, warnings={item['warningCount']}, "
            f"candidates={item['candidateCount']}"
        )
    if summary["missingShards"]:
        lines.extend(["", "## Missing Shards", ""])
        for shard in summary["missingShards"]:
            lines.append(f"- `{shard}`")
    return "\n".join(lines) + "\n"


def render_text(summary: Dict[str, Any]) -> str:
    lines = [
        f"Scanned files: {summary['scannedFileCount']}",
        f"Missing shards: {summary['missingShardCount']}",
        f"Validation failed files: {summary['validation']['failedFiles']}",
        f"Validation errors: {summary['validation']['errorCount']}",
        f"Validation warnings: {summary['validation']['warningCount']}",
        f"Content candidates: {summary['review']['candidateCount']}",
        "Top reasons:",
    ]
    for reason, count in summary["review"]["topReasons"]:
        lines.append(f"- {reason}: {count}")
    return "\n".join(lines) + "\n"


def parse_thresholds(items: Iterable[str]) -> Dict[str, int]:
    thresholds: Dict[str, int] = {}
    for item in items:
        if "=" not in item:
            raise ValueError(f"Threshold must use KEY=VALUE format: {item!r}")
        key, raw_value = item.split("=", 1)
        key = key.strip()
        raw_value = raw_value.strip()
        if not raw_value.isdigit():
            raise ValueError(f"Threshold value must be a non-negative integer: {item!r}")
        thresholds[key] = int(raw_value)
    return thresholds


def main() -> int:
    args = parse_args()
    requested_letters = parse_letters(args.letters)
    expected_files = {f"word_bank_main-{letter}.json" for letter in requested_letters}
    glob_root = repo_path(".")
    all_matches = sorted(glob_root.glob(args.pattern))
    shard_paths = [path for path in all_matches if path.name in expected_files]
    found_files = {path.name for path in shard_paths}
    missing_shards = sorted(expected_files - found_files)

    output_dir = repo_path(args.output_dir)
    by_file_dir = output_dir / "by-file"

    validation_category_counts: Counter[str] = Counter()
    warning_category_counts: Counter[str] = Counter()
    review_reason_counts: Counter[str] = Counter()
    combined_results = []
    tool_failures = []

    for path in shard_paths:
        validation_code, validation_payload = run_json_command(
            [
                sys.executable,
                str(VALIDATOR),
                "--path",
                str(path),
                "--format",
                "json",
            ]
        )
        review_code, review_payload = run_json_command(
            [
                sys.executable,
                str(REVIEWER),
                "--path",
                str(path),
                "--format",
                "json",
                "--min-score",
                str(args.min_score),
            ]
        )

        if not validation_payload:
            tool_failures.append(
                {
                    "file": path.name,
                    "tool": "validate_word_bank_main.py",
                    "exitCode": validation_code,
                }
            )
            validation_payload = {
                "path": str(path),
                "file": path.name,
                "status": "TOOL FAILURE",
                "entryCount": None,
                "errorCount": 0,
                "warningCount": 0,
                "errorCategoryCounts": {},
                "warningCategoryCounts": {},
                "errors": [],
                "warnings": [],
                "exitCode": validation_code,
            }
        if not review_payload:
            tool_failures.append(
                {
                    "file": path.name,
                    "tool": "review_word_bank_content.py",
                    "exitCode": review_code,
                }
            )
            review_payload = {
                "path": str(path),
                "file": path.name,
                "candidateCount": 0,
                "reasonCounts": {},
                "candidates": [],
            }

        validation_category_counts.update(validation_payload.get("errorCategoryCounts", {}))
        warning_category_counts.update(validation_payload.get("warningCategoryCounts", {}))
        review_reason_counts.update(review_payload.get("reasonCounts", {}))

        combined = {
            "path": str(path),
            "file": path.name,
            "validationStatus": validation_payload.get("status"),
            "entryCount": validation_payload.get("entryCount"),
            "errorCount": validation_payload.get("errorCount", 0),
            "warningCount": validation_payload.get("warningCount", 0),
            "candidateCount": review_payload.get("candidateCount", 0),
            "topReasons": dict(
                list((review_payload.get("reasonCounts") or {}).items())[:5]
            ),
        }
        combined_results.append(combined)

        base_name = path.name.replace(".json", "")
        write_json(by_file_dir / f"{base_name}.validation.json", validation_payload)
        write_json(by_file_dir / f"{base_name}.review.json", review_payload)

    combined_results.sort(
        key=lambda item: (
            0 if item["validationStatus"] == "VALIDATION FAILED" else 1,
            -int(item["candidateCount"]),
            -int(item["errorCount"]),
            item["file"],
        )
    )

    summary = {
        "generatedAt": current_timestamp(),
        "pattern": args.pattern,
        "requestedLetters": requested_letters,
        "scannedFileCount": len(shard_paths),
        "missingShardCount": len(missing_shards),
        "missingShards": missing_shards,
        "validation": {
            "failedFiles": sum(
                1 for item in combined_results if item["validationStatus"] == "VALIDATION FAILED"
            ),
            "errorCount": sum(item["errorCount"] for item in combined_results),
            "warningCount": sum(item["warningCount"] for item in combined_results),
            "errorCategoryCounts": dict(validation_category_counts.most_common()),
            "warningCategoryCounts": dict(warning_category_counts.most_common()),
        },
        "review": {
            "candidateCount": sum(item["candidateCount"] for item in combined_results),
            "topReasons": review_reason_counts.most_common(10),
        },
        "priorityFiles": combined_results[:10],
        "files": combined_results,
        "toolFailures": tool_failures,
    }

    write_json(output_dir / "summary.json", summary)
    write_text(output_dir / "summary.md", render_markdown(summary))

    if args.format == "json":
        json.dump(summary, sys.stdout, ensure_ascii=False, indent=2)
        sys.stdout.write("\n")
    elif args.format == "md":
        sys.stdout.write(render_markdown(summary))
    else:
        sys.stdout.write(render_text(summary))

    exit_code = 0
    if args.fail_on_errors and (
        summary["missingShardCount"] > 0
        or summary["validation"]["failedFiles"] > 0
        or tool_failures
    ):
        exit_code = 1

    thresholds = parse_thresholds(args.fail_on_threshold)
    metric_map = {
        "validation_failed_files": summary["validation"]["failedFiles"],
        "validation_errors": summary["validation"]["errorCount"],
        "validation_warnings": summary["validation"]["warningCount"],
        "content_candidates": summary["review"]["candidateCount"],
        "missing_shards": summary["missingShardCount"],
    }
    for key, limit in thresholds.items():
        if key not in metric_map:
            raise ValueError(f"Unsupported threshold key: {key}")
        if metric_map[key] > limit:
            exit_code = 1

    return exit_code


if __name__ == "__main__":
    sys.exit(main())
