"""
Simple API latency/accuracy smoke test against a running validator API.

It picks a few doc images (expected valid) and non-doc live images
(expected invalid) from the FLUX dataset, sends them to both validate/photo
and validate/stream, and reports timing and pass/fail counts.
"""

from __future__ import annotations

import argparse
import base64
import json
import time
from pathlib import Path
from typing import List, Tuple, Dict

import requests


def load_samples(dataset_root: Path, doc_limit: int, neg_limit: int) -> Tuple[List[bytes], List[bytes]]:
    """Load doc and non-doc samples as raw bytes."""
    docs: List[bytes] = []
    negatives: List[bytes] = []

    for folder in sorted(dataset_root.iterdir()):
        if not folder.is_dir():
            continue

        doc_paths = sorted(folder.glob("*_doc*.jpg")) + sorted(folder.glob("*_doc*.png"))
        for p in doc_paths:
            if len(docs) >= doc_limit:
                break
            docs.append(p.read_bytes())
        if len(docs) >= doc_limit:
            break

    for folder in sorted(dataset_root.iterdir()):
        if not folder.is_dir():
            continue

        live_paths = [
            p
            for p in sorted(folder.glob("*.jpg")) + sorted(folder.glob("*.png"))
            if "_doc" not in p.name
        ]
        for p in live_paths:
            if len(negatives) >= neg_limit:
                break
            negatives.append(p.read_bytes())
        if len(negatives) >= neg_limit:
            break

    if not docs:
        raise SystemExit("No doc images found in dataset.")
    if not negatives:
        raise SystemExit("No non-doc images found in dataset.")

    return docs, negatives


def to_base64(img_bytes: bytes) -> str:
    return base64.b64encode(img_bytes).decode("utf-8")


def post_json(session: requests.Session, url: str, payload: dict) -> Tuple[dict, float, int]:
    start = time.perf_counter()
    resp = session.post(url, json=payload, timeout=30)
    elapsed = time.perf_counter() - start
    try:
        data = resp.json()
    except Exception:
        data = {"status": "error", "raw": resp.text}
    return data, elapsed, resp.status_code


def run_tests(api_base: str, docs: List[bytes], negatives: List[bytes]) -> Dict:
    stats = {
        "validate_photo": {"valid_total": 0, "valid_pass": 0, "invalid_total": 0, "invalid_reject": 0, "latencies": []},
        "validate_stream": {"valid_total": 0, "valid_pass": 0, "invalid_total": 0, "invalid_reject": 0, "latencies": []},
    }

    photo_url = f"{api_base}/validate/photo"
    stream_url = f"{api_base}/validate/stream"

    def record(endpoint: str, is_valid: bool, result: dict, elapsed: float):
        key = "validate_photo" if endpoint == photo_url else "validate_stream"
        stats[key]["latencies"].append(elapsed)
        if is_valid:
            stats[key]["valid_total"] += 1
            if result.get("status") == "success":
                stats[key]["valid_pass"] += 1
        else:
            stats[key]["invalid_total"] += 1
            if result.get("status") != "success":
                stats[key]["invalid_reject"] += 1

    session = requests.Session()

    # Docs (expected valid)
    for img in docs:
        b64 = to_base64(img)
        payload = {"image": b64, "mode": "full"}
        res, t, code = post_json(session, photo_url, payload)
        record(photo_url, True, res, t)

        payload_stream = {"image": b64, "mode": "stream"}
        res, t, code = post_json(session, stream_url, payload_stream)
        record(stream_url, True, res, t)

    # Negatives (expected invalid)
    for img in negatives:
        b64 = to_base64(img)
        payload = {"image": b64, "mode": "full"}
        res, t, code = post_json(session, photo_url, payload)
        record(photo_url, False, res, t)

        payload_stream = {"image": b64, "mode": "stream"}
        res, t, code = post_json(session, stream_url, payload_stream)
        record(stream_url, False, res, t)

    return stats


def summarize(stats: Dict) -> dict:
    def agg(key: str):
        lat = stats[key]["latencies"]
        lat_sorted = sorted(lat)
        def pct(p):
            idx = int(len(lat_sorted) * p / 100)
            idx = min(idx, len(lat_sorted) - 1)
            return lat_sorted[idx]
        return {
            "valid_pass": f"{stats[key]['valid_pass']}/{stats[key]['valid_total']}",
            "invalid_reject": f"{stats[key]['invalid_reject']}/{stats[key]['invalid_total']}",
            "latency_avg_s": round(sum(lat) / len(lat), 3) if lat else None,
            "latency_p95_s": round(pct(95), 3) if lat else None,
        }
    return {"validate_photo": agg("validate_photo"), "validate_stream": agg("validate_stream")}


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--api", default="https://d28w3hxcjjqa9z.cloudfront.net/api/v1", help="Base API URL")
    parser.add_argument("--dataset", default="/Users/ihor.olkhovatyi/Downloads/FLUXSynID/FLUXSynID", type=Path)
    parser.add_argument("--docs", type=int, default=50, help="Number of doc images to test")
    parser.add_argument("--negatives", type=int, default=3, help="Number of live/non-doc images to test")
    args = parser.parse_args()

    docs, negatives = load_samples(args.dataset, args.docs, args.negatives)
    stats = run_tests(args.api, docs, negatives)
    summary = summarize(stats)
    print(json.dumps(summary, indent=2))


if __name__ == "__main__":
    main()
