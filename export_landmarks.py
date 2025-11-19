#!/usr/bin/env python3
"""
Utility script for exporting face landmarks from local images.

This allows running the validation pipeline without the HTTP API and
writing the detected landmarks into plain-text files for further analysis.
"""

from __future__ import annotations

import argparse
import sys
from pathlib import Path
from typing import List, Optional, Sequence, Tuple

import cv2
import numpy as np

from app.core.pipeline import ValidationPipeline
import config

MP_FACE_MESH_IMPORT_ERROR = ""
try:
    from mediapipe.solutions import face_mesh as mp_face_mesh
except Exception as exc:  # pragma: no cover - optional dependency already required by pipeline
    mp_face_mesh = None
    MP_FACE_MESH_IMPORT_ERROR = str(exc)

# Supported image extensions (lowercase)
IMAGE_EXTENSIONS = {".jpg", ".jpeg", ".png"}


def parse_arguments() -> argparse.Namespace:
    """Parse CLI arguments."""
    parser = argparse.ArgumentParser(
        description="Export face landmarks detected by the validation pipeline."
    )

    input_group = parser.add_mutually_exclusive_group(required=True)
    input_group.add_argument(
        "-i",
        "--image",
        dest="images",
        action="append",
        help="Path to an image file. Can be provided multiple times.",
    )
    input_group.add_argument(
        "-f",
        "--fixtures",
        dest="fixture_dirs",
        action="append",
        help="Directory containing fixtures/images. Recursively scanned.",
    )

    parser.add_argument(
        "-m",
        "--mode",
        choices=[config.MODE_FULL, config.MODE_STREAM],
        default=config.MODE_STREAM,
        help="Pipeline mode to use. Stream mode skips heavy background models.",
    )
    parser.add_argument(
        "-o",
        "--output-dir",
        default="landmark_exports",
        help="Directory where landmark .txt files will be written.",
    )
    parser.add_argument(
        "--include-3d",
        action="store_true",
        help="Also export 3D landmarks when available.",
    )
    parser.add_argument(
        "--overwrite",
        action="store_true",
        help="Overwrite existing export files. By default files are skipped.",
    )
    parser.add_argument(
        "--skip-overlay",
        action="store_true",
        help="Do not generate annotated image overlays with landmarks.",
    )
    parser.add_argument(
        "--connections",
        choices=["contours", "mesh", "none"],
        default="contours",
        help=(
            "Choose how to connect landmarks in annotated images: "
            "'contours' (default) draws MediaPipe contour lines, 'mesh' draws "
            "the full tessellation, and 'none' draws only points."
        ),
    )

    return parser.parse_args()


def is_image_file(path: Path) -> bool:
    """Check whether a path points to a supported image file."""
    return path.is_file() and path.suffix.lower() in IMAGE_EXTENSIONS


def collect_targets(args: argparse.Namespace) -> List[Tuple[Path, Path]]:
    """
    Collect image paths that should be processed.

    Returns:
        List of tuples (image_path, base_dir_for_relative_output)
    """
    targets: List[Tuple[Path, Path]] = []

    def add_file(file_path: Path, base_dir: Path):
        if is_image_file(file_path):
            targets.append((file_path, base_dir))
        else:
            print(f"[skip] {file_path} is not a supported image", file=sys.stderr)

    if args.images:
        for raw_path in args.images:
            path = Path(raw_path).expanduser().resolve()
            if path.is_file():
                add_file(path, path.parent)
            elif path.is_dir():
                for img in path.rglob("*"):
                    add_file(img, path)
            else:
                print(f"[warn] Path does not exist: {path}", file=sys.stderr)

    if args.fixture_dirs:
        for raw_dir in args.fixture_dirs:
            dir_path = Path(raw_dir).expanduser().resolve()
            if dir_path.is_dir():
                for img in dir_path.rglob("*"):
                    add_file(img, dir_path)
            elif dir_path.is_file():
                add_file(dir_path, dir_path.parent)
            else:
                print(f"[warn] Fixture path not found: {dir_path}", file=sys.stderr)

    # Deduplicate while keeping order
    seen = set()
    deduped_targets: List[Tuple[Path, Path]] = []
    for image_path, base_dir in targets:
        key = str(image_path)
        if key not in seen:
            seen.add(key)
            deduped_targets.append((image_path, base_dir))

    return deduped_targets


def format_errors(errors: Sequence[dict]) -> str:
    """Human readable summary of validation errors."""
    if not errors:
        return "none"
    return "; ".join(f"{e.get('code')}: {e.get('message')}" for e in errors)


def get_connection_pairs(mode: str) -> Tuple[Tuple[int, int], ...]:
    """
    Return landmark connection pairs based on requested overlay style.
    """
    if mode == "none" or mp_face_mesh is None:
        if mode != "none" and mp_face_mesh is None:
            print(
                "[warn] MediaPipe face mesh module unavailable. "
                "Install mediapipe (pip install mediapipe==0.10.8) or run the "
                "exporter inside the project's virtual environment to enable "
                f"'{mode}' connections.",
                file=sys.stderr,
            )
            if MP_FACE_MESH_IMPORT_ERROR:
                print(
                    f"        Import error: {MP_FACE_MESH_IMPORT_ERROR}",
                    file=sys.stderr,
                )
        return ()

    if mode == "mesh":
        connection_source = mp_face_mesh.FACEMESH_TESSELATION
    else:
        connection_source = mp_face_mesh.FACEMESH_CONTOURS

    pairs = []
    for connection in connection_source:
        if isinstance(connection, (tuple, list)):
            if len(connection) == 2:
                start, end = connection
            else:
                start, end = connection[:2]
        else:
            start = getattr(connection, "start", None)
            end = getattr(connection, "end", None)

        if start is None or end is None:
            continue

        try:
            start_idx = int(getattr(start, "value", start))
            end_idx = int(getattr(end, "value", end))
        except (TypeError, ValueError):
            continue

        pairs.append((start_idx, end_idx))

    if not pairs and mode != "none":
        print(
            f"[warn] Unable to load '{mode}' landmark connections; "
            "falling back to points only.",
            file=sys.stderr,
        )
    return tuple(pairs)


def save_annotated_image(
    image_bytes: bytes,
    landmarks: Sequence[dict],
    output_path: Path,
    connections: Sequence[Tuple[int, int]],
) -> bool:
    """
    Render landmarks onto the original image and save the annotated copy.
    """
    if not landmarks:
        return False

    try:
        array = np.frombuffer(image_bytes, dtype=np.uint8)
        image = cv2.imdecode(array, cv2.IMREAD_COLOR)
    except Exception as exc:  # pragma: no cover - defensive guard
        print(f"[warn] Failed to decode image for overlay: {exc}", file=sys.stderr)
        return False

    if image is None or image.size == 0:
        print("[warn] Could not decode image for overlay rendering.", file=sys.stderr)
        return False

    height, width = image.shape[:2]
    if width == 0 or height == 0:
        return False

    for idx, lnd in enumerate(landmarks):
        x = int(round(lnd.get("x", 0.0)))
        y = int(round(lnd.get("y", 0.0)))
        x = max(0, min(width - 1, x))
        y = max(0, min(height - 1, y))
        cv2.circle(image, (x, y), 1, (0, 255, 0), -1)
        if idx % 50 == 0:
            cv2.putText(
                image,
                str(idx),
                (x + 2, y - 2),
                cv2.FONT_HERSHEY_SIMPLEX,
                0.3,
                (0, 255, 255),
                1,
                lineType=cv2.LINE_AA,
            )

    if connections:
        for start, end in connections:
            if start >= len(landmarks) or end >= len(landmarks):
                continue
            p1 = landmarks[start]
            p2 = landmarks[end]
            x1 = int(round(p1.get("x", 0.0)))
            y1 = int(round(p1.get("y", 0.0)))
            x2 = int(round(p2.get("x", 0.0)))
            y2 = int(round(p2.get("y", 0.0)))
            x1 = max(0, min(width - 1, x1))
            y1 = max(0, min(height - 1, y1))
            x2 = max(0, min(width - 1, x2))
            y2 = max(0, min(height - 1, y2))
            cv2.line(image, (x1, y1), (x2, y2), (0, 0, 255), 1, lineType=cv2.LINE_AA)

    output_path.parent.mkdir(parents=True, exist_ok=True)
    if not cv2.imwrite(str(output_path), image):
        print(f"[warn] Failed to write overlay image: {output_path}", file=sys.stderr)
        return False
    return True


def export_landmarks_for_image(
    image_path: Path,
    base_dir: Path,
    pipeline: ValidationPipeline,
    output_root: Path,
    include_3d: bool,
    overwrite: bool,
    write_overlay: bool,
    connections: Sequence[Tuple[int, int]],
) -> Tuple[bool, Path, Optional[Path]]:
    """
    Run validation on a single image and export the landmarks.

    Returns:
        Tuple (success, txt_path, overlay_path_or_none)
    """
    relative = image_path.relative_to(base_dir)
    export_path = (output_root / relative).with_suffix(".txt")

    try:
        data = image_path.read_bytes()
    except OSError as exc:
        print(f"[fail] Unable to read {image_path}: {exc}", file=sys.stderr)
        return False, export_path, None

    result = pipeline.validate(data, is_base64=False)
    metadata = result.get("metadata", {})
    face_meta = metadata.get("face") or {}
    landmarks = face_meta.get("landmarks")
    landmarks_3d = face_meta.get("landmarks_3d")

    export_path.parent.mkdir(parents=True, exist_ok=True)

    lines: List[str] = []
    lines.append(f"# Image: {image_path}")
    lines.append(f"# Mode: {pipeline.mode}")
    lines.append(f"# Status: {result.get('status')}")
    errors = result.get("errors", [])
    if errors:
        lines.append(f"# Errors: {format_errors(errors)}")
    lines.append("")

    if landmarks:
        lines.append("# 2D Landmarks (index x y)")
        for idx, lnd in enumerate(landmarks):
            lines.append(f"{idx} {lnd.get('x', 0.0):.4f} {lnd.get('y', 0.0):.4f}")
    else:
        lines.append("# No 2D landmarks detected.")

    if include_3d and landmarks_3d:
        lines.append("")
        lines.append("# 3D Landmarks (index x y z)")
        for idx, lnd in enumerate(landmarks_3d):
            lines.append(
                f"{idx} {lnd.get('x', 0.0):.4f} {lnd.get('y', 0.0):.4f} {lnd.get('z', 0.0):.4f}"
            )

    if export_path.exists() and not overwrite:
        print(
            f"[skip] {export_path} already exists (use --overwrite to refresh)",
            file=sys.stderr,
        )
    else:
        export_path.write_text("\n".join(lines) + "\n", encoding="utf-8")

    overlay_path: Optional[Path] = None
    if write_overlay and landmarks:
        overlay_relative = relative.with_name(f"{relative.stem}_landmarks{relative.suffix}")
        candidate_path = output_root / overlay_relative
        if candidate_path.exists() and not overwrite:
            print(
                f"[skip] {candidate_path} already exists (use --overwrite to refresh)",
                file=sys.stderr,
            )
        else:
            saved = save_annotated_image(
                image_bytes=data,
                landmarks=landmarks,
                output_path=candidate_path,
                connections=connections,
            )
            if saved:
                overlay_path = candidate_path
            else:
                print(
                    f"[warn] Failed to create annotated image for {image_path}",
                    file=sys.stderr,
                )

    return landmarks is not None, export_path, overlay_path


def main() -> int:
    args = parse_arguments()
    targets = collect_targets(args)

    if not targets:
        print("No images found to process.", file=sys.stderr)
        return 1

    pipeline = ValidationPipeline(mode=args.mode)
    output_root = Path(args.output_dir).expanduser().resolve()
    connections = get_connection_pairs(args.connections)

    print(
        f"Exporting landmarks for {len(targets)} image(s) "
        f"using '{args.mode}' pipeline. Output -> {output_root}"
    )

    success_count = 0
    annotate_images = not args.skip_overlay
    for image_path, base_dir in targets:
        ok, export_path, overlay_path = export_landmarks_for_image(
            image_path=image_path,
            base_dir=base_dir,
            pipeline=pipeline,
            output_root=output_root,
            include_3d=args.include_3d,
            overwrite=args.overwrite,
            write_overlay=annotate_images,
            connections=connections,
        )
        status = "✓" if ok else "!"
        overlay_note = ""
        if overlay_path:
            overlay_note = f" (annotated: {overlay_path})"
        print(f"[{status}] {image_path} -> {export_path}{overlay_note}")
        if ok:
            success_count += 1

    print(
        f"\nFinished exporting {success_count}/{len(targets)} "
        f"images. Landmarks saved under {output_root}"
    )
    return 0 if success_count else 2


if __name__ == "__main__":
    raise SystemExit(main())
