"""
Quick latency benchmark for ValidationPipeline.

It reports initialization time, first-call latency, and warm-call stats
for both validate (full) and validate_stream (lightweight) modes.
"""

from __future__ import annotations

import argparse
import statistics
import sys
from pathlib import Path
from time import perf_counter
from typing import List

PROJECT_ROOT = Path(__file__).resolve().parents[1]
if str(PROJECT_ROOT) not in sys.path:
    sys.path.insert(0, str(PROJECT_ROOT))

from app.core.pipeline import ValidationPipeline  # noqa: E402


def load_samples(dataset_root: Path, max_folders: int, per_folder: int) -> List[bytes]:
    """Load bytes for a small set of *_doc images."""
    images: List[bytes] = []
    for folder in sorted(dataset_root.iterdir()):
        if not folder.is_dir():
            continue
        docs = sorted(folder.glob("*_doc*.jpg")) + sorted(folder.glob("*_doc*.png"))
        if not docs:
            continue
        for doc_path in docs[:per_folder]:
            images.append(doc_path.read_bytes())
        if len(images) >= max_folders * per_folder:
            break
    if not images:
        raise SystemExit("No doc images found; check dataset path.")
    return images


def benchmark_mode(mode: str, samples: List[bytes], warm_iters: int = 5) -> dict:
    """Benchmark one mode of the pipeline."""
    t0 = perf_counter()
    pipeline = ValidationPipeline(mode=mode)
    init_time = perf_counter() - t0

    def run_once(img: bytes):
        start = perf_counter()
        if mode == "stream":
            pipeline.validate_stream(img, is_base64=False)
        else:
            pipeline.validate(img, is_base64=False)
        return perf_counter() - start

    # First call (cold)
    first_latency = run_once(samples[0])

    # Warm calls
    warm_latencies = [run_once(img) for img in samples[:warm_iters]]

    return {
        "init_time_s": round(init_time, 3),
        "first_call_s": round(first_latency, 3),
        "warm_avg_s": round(statistics.mean(warm_latencies), 3),
        "warm_p95_s": round(statistics.quantiles(warm_latencies, n=20)[-1], 3)
        if len(warm_latencies) > 1
        else round(warm_latencies[0], 3),
        "runs": len(warm_latencies) + 1,
    }


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument(
        "--dataset",
        default="/Users/ihor.olkhovatyi/Downloads/FLUXSynID/FLUXSynID",
        type=Path,
        help="Root folder containing FLUXSynID subfolders",
    )
    parser.add_argument("--folders", type=int, default=5, help="Folders to sample")
    parser.add_argument(
        "--per-folder", type=int, default=1, help="Doc images per folder to load"
    )
    parser.add_argument(
        "--warm-iters", type=int, default=5, help="Warm calls per mode"
    )
    args = parser.parse_args()

    samples = load_samples(args.dataset, args.folders, args.per_folder)

    results = {
        "full_validate": benchmark_mode("full", samples, args.warm_iters),
        "stream_validate": benchmark_mode("stream", samples, args.warm_iters),
    }

    import json

    print(json.dumps(results, indent=2))


if __name__ == "__main__":
    main()
