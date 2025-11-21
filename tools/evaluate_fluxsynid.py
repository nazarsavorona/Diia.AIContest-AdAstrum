"""
Quick evaluation helper for the FLUXSynID dataset.

It walks a subset of folders, treats *_doc images as valid and all other
JPG/PNG images in the same folder as invalid, then runs the validation
pipeline to get a rough precision/recall readout.
"""

from __future__ import annotations

import argparse
import json
import sys
from collections import Counter, defaultdict
from pathlib import Path
from typing import List, Tuple

PROJECT_ROOT = Path(__file__).resolve().parents[1]
if str(PROJECT_ROOT) not in sys.path:
    sys.path.insert(0, str(PROJECT_ROOT))

from app.core.pipeline import ValidationPipeline


def collect_samples(
    dataset_root: Path, max_folders: int, limit_negatives: int
) -> List[Tuple[Path, bool]]:
    """Collect (path, is_valid) pairs from the dataset."""
    samples: List[Tuple[Path, bool]] = []
    folders_seen = 0

    for folder in sorted(dataset_root.iterdir()):
        if not folder.is_dir():
            continue

        doc_candidates = sorted(
            list(folder.glob("*_doc*.jpg")) + list(folder.glob("*_doc*.png"))
        )
        if not doc_candidates:
            continue

        doc_path = doc_candidates[0]
        samples.append((doc_path, True))
        folders_seen += 1

        negatives = [
            p
            for p in sorted(folder.glob("*.jpg")) + sorted(folder.glob("*.png"))
            if "_doc" not in p.stem
        ]

        if limit_negatives:
            negatives = negatives[:limit_negatives]

        samples.extend((p, False) for p in negatives)

        if folders_seen >= max_folders:
            break

    return samples


def run_evaluation(samples: List[Tuple[Path, bool]], mode: str) -> None:
    pipeline = ValidationPipeline(mode=mode)

    counters = Counter()
    valid_error_codes = Counter()
    invalid_error_codes = Counter()
    false_negatives = []
    false_positives = []

    for path, is_valid in samples:
        with open(path, "rb") as f:
            image_bytes = f.read()

        result = pipeline.validate(image_bytes, is_base64=False)
        passed = result.get("status") == "success"
        errors = result.get("errors") or []
        codes = [e.get("code") for e in errors if e.get("code")]

        if is_valid:
            counters["valid_total"] += 1
            if passed:
                counters["valid_pass"] += 1
            else:
                counters["valid_fail"] += 1
                valid_error_codes.update(codes)
                if len(false_negatives) < 5:
                    false_negatives.append((path, codes, result.get("metadata")))
        else:
            counters["invalid_total"] += 1
            if passed:
                counters["invalid_pass"] += 1
                if len(false_positives) < 5:
                    false_positives.append((path, codes, result.get("metadata")))
            else:
                counters["invalid_reject"] += 1
                invalid_error_codes.update(codes)

    total = counters["valid_total"] + counters["invalid_total"]
    true_positive = counters["valid_pass"]
    false_positive = counters["invalid_pass"]
    true_negative = counters["invalid_reject"]
    false_negative = counters["valid_fail"]

    precision = (
        true_positive / (true_positive + false_positive)
        if (true_positive + false_positive)
        else 0.0
    )
    recall = true_positive / counters["valid_total"] if counters["valid_total"] else 0.0
    specificity = (
        true_negative / counters["invalid_total"] if counters["invalid_total"] else 0.0
    )
    accuracy = (true_positive + true_negative) / total if total else 0.0

    print(json.dumps(
        {
            "counts": counters,
            "metrics": {
                "accuracy": round(accuracy, 3),
                "precision": round(precision, 3),
                "recall": round(recall, 3),
                "specificity": round(specificity, 3),
            },
            "top_valid_error_codes": valid_error_codes.most_common(10),
            "top_invalid_error_codes": invalid_error_codes.most_common(10),
            "sample_false_negatives": [
                {
                    "path": str(p),
                    "errors": c,
                }
                for p, c, _ in false_negatives
            ],
            "sample_false_positives": [
                {
                    "path": str(p),
                    "errors": c,
                }
                for p, c, _ in false_positives
            ],
        },
        indent=2,
        default=str,
    ))


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument(
        "--dataset",
        default="/Users/ihor.olkhovatyi/Downloads/FLUXSynID/FLUXSynID",
        type=Path,
        help="Root folder containing FLUXSynID subfolders",
    )
    parser.add_argument("--mode", default="full", choices=["full", "stream"])
    parser.add_argument(
        "--max-folders",
        type=int,
        default=25,
        help="How many subject folders to sample",
    )
    parser.add_argument(
        "--limit-negatives",
        type=int,
        default=3,
        help="Limit how many non-doc images to pull from each folder (0 = all)",
    )
    args = parser.parse_args()

    samples = collect_samples(args.dataset, args.max_folders, args.limit_negatives)
    if not samples:
        raise SystemExit("No samples found. Check --dataset path.")

    run_evaluation(samples, args.mode)


if __name__ == "__main__":
    main()
