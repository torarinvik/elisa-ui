#!/usr/bin/env python3
"""Require an exact-tuple budget for the real million-item Showcase path."""

from __future__ import annotations

import argparse
import hashlib
import json
import platform
import re
import shutil
import subprocess
import sys
from pathlib import Path
from typing import Any


WORKLOAD_ID = "showcase-million-list-skia-v1"
WARMUPS = 2
REPETITIONS = 7
ELISA_FLAGS = "-O2"
HOST_FLAGS = "-std=c++20 -DSK_BUILD_FOR_MAC -fPIC"
SHIM_FLAGS = "-std=c++17 -fPIC"
LINK_FLAGS = "-Wl,-dead_strip -framework CoreFoundation -framework CoreGraphics -framework CoreText -framework Foundation -lz"
SOURCE_EXTENSIONS = {".elisa", ".elisai", ".c", ".cpp", ".h", ".hpp", ".m", ".mm"}


def output(command: list[str]) -> str:
    try:
        return subprocess.check_output(command, text=True, stderr=subprocess.DEVNULL).strip()
    except (OSError, subprocess.CalledProcessError):
        return ""


def sha256(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as source:
        for chunk in iter(lambda: source.read(1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest()


def source_bundle_sha256(root: Path) -> str:
    roots = [root / "src", root / "examples/showcase"]
    files = [
        root / "test/showcase_app_skia_host.cpp",
        root / "test/showcase_app_skia_test.elisa",
        root / "scripts/check_skia.sh",
        root / "scripts/render_showcase_skia.sh",
        root / "scripts/check_showcase_skia_performance.py",
        root / "third_party/skia.lock",
    ]
    test_dir = root / "test"
    files.extend(
        path for path in test_dir.iterdir()
        if path.is_file() and path.suffix in SOURCE_EXTENSIONS
        and path.name.startswith(("showcase_app_skia_", "showcase_skia_"))
    )
    for directory in roots:
        files.extend(
            path for path in directory.rglob("*")
            if path.is_file() and path.suffix in SOURCE_EXTENSIONS
        )
    digest = hashlib.sha256()
    for path in sorted(set(files), key=lambda item: item.relative_to(root).as_posix()):
        digest.update(path.relative_to(root).as_posix().encode("utf-8"))
        digest.update(b"\0")
        digest.update(path.read_bytes())
        digest.update(b"\0")
    return digest.hexdigest()


def host_metadata() -> dict[str, str]:
    system = platform.system()
    os_version = output(["sw_vers", "-productVersion"]) if system == "Darwin" else platform.release()
    return {
        "os_family": "macOS" if system == "Darwin" else system,
        "os_version": os_version,
        "os_major": os_version.split(".", 1)[0] if os_version else "",
        "os_build": output(["sw_vers", "-buildVersion"]) if system == "Darwin" else "",
        "kernel_release": platform.release(),
        "architecture": platform.machine(),
        "model": output(["sysctl", "-n", "hw.model"]),
        "cpu": output(["sysctl", "-n", "machdep.cpu.brand_string"]),
    }


def binary_metadata(name: str) -> dict[str, str]:
    executable = shutil.which(name)
    version = output([name, "--version"]).splitlines()
    return {
        "version": version[0] if version else "unavailable",
        "binary_sha256": sha256(Path(executable).resolve()) if executable else "",
    }


def flatten(value: dict[str, Any], prefix: str = "") -> dict[str, Any]:
    flattened: dict[str, Any] = {}
    for key, item in value.items():
        name = f"{prefix}.{key}" if prefix else key
        if isinstance(item, dict):
            flattened.update(flatten(item, name))
        else:
            flattened[name] = item
    return flattened


def metadata(root: Path, stage1: Path, skia_root: Path, skia_out: Path, skia_lib: Path,
             width: int, height: int, process_repetitions: int) -> dict[str, Any]:
    lock = root / "third_party/skia.lock"
    build_manifest = skia_out / "elisa-ui-skia-build.lock"
    args = skia_out / "args.gn"
    optional_archives = {}
    for name in ("libpng.a", "libzlib.a"):
        archive = skia_out / name
        optional_archives[name] = sha256(archive) if archive.is_file() else None
    return {
        "host": host_metadata(),
        "compiler": {
            "revision": output(["git", "-C", str(stage1), "rev-parse", "HEAD"]),
            "product_sha256": sha256(stage1 / "bin/elisac-stage1"),
            "runtime_sha256": sha256(stage1 / "build/runtime/elisacore_runtime.o"),
            "driver_script_sha256": sha256(stage1 / "scripts/elisac_stage1.sh"),
        },
        "clang": binary_metadata("clang++"),
        "skia": {
            "revision": output(["git", "-C", str(skia_root), "rev-parse", "HEAD"]),
            "lock_sha256": sha256(lock),
            "build_manifest_sha256": sha256(build_manifest),
            "args_sha256": sha256(args),
            "archive_sha256": sha256(skia_lib),
            "optional_archives": optional_archives,
        },
        "workload": {
            "id": WORKLOAD_ID,
            "warmups": WARMUPS,
            "repetitions": REPETITIONS,
            "process_repetitions": process_repetitions,
            "dimensions": {"width": width, "height": height, "scale": 1.0},
            "operations_per_batch": 1,
            "compile_flags": {
                "elisa": ELISA_FLAGS,
                "host": HOST_FLAGS,
                "shim": SHIM_FLAGS,
                "linker": LINK_FLAGS,
            },
            "source_bundle_sha256": source_bundle_sha256(root),
        },
    }


def records_from_log(path: Path) -> list[dict[str, Any]]:
    records: list[dict[str, Any]] = []
    for line in path.read_text(errors="replace").splitlines():
        try:
            record = json.loads(line)
        except json.JSONDecodeError:
            continue
        if isinstance(record, dict) and record.get("workload_id") == WORKLOAD_ID:
            records.append(record)
    return records


def validate_records(records: list[dict[str, Any]], process_repetitions: int) -> str | None:
    if len(records) != process_repetitions:
        return f"expected {process_repetitions} fresh-process records, found {len(records)}"
    reference_digest: str | None = None
    for process, record in enumerate(records, start=1):
        if record.get("warmups") != WARMUPS or record.get("repetitions") != REPETITIONS:
            return f"process {process} reported an unexpected workload shape"
        if record.get("operations_per_batch") != 1:
            return f"process {process} did not measure one complete workflow per sample"
        samples = record.get("samples_ns")
        digests = record.get("tail_pixel_digests")
        if not isinstance(samples, list) or len(samples) != REPETITIONS:
            return f"process {process} has an incomplete latency sample set"
        if any(type(sample) is not int or sample <= 0 for sample in samples):
            return f"process {process} has an invalid latency sample"
        if not isinstance(digests, list) or len(digests) != REPETITIONS:
            return f"process {process} has an incomplete pixel digest set"
        if any(not isinstance(digest, str) or re.fullmatch(r"[0-9a-f]{16}", digest) is None for digest in digests):
            return f"process {process} has an invalid pixel digest"
        if len(set(digests)) != 1:
            return f"process {process} produced different tail pixels across repeats"
        if reference_digest is None:
            reference_digest = digests[0]
        elif digests[0] != reference_digest:
            return "fresh processes produced different tail pixels"
    return None


def aggregate(records: list[dict[str, Any]]) -> dict[str, Any]:
    samples_by_process = [record["samples_ns"] for record in records]
    samples = sorted(sample for process in samples_by_process for sample in process)
    return {
        "samples_ns_by_process": samples_by_process,
        "median_ns": samples[len(samples) // 2],
        "max_sample_ns": samples[-1],
        "tail_pixel_digest": records[0]["tail_pixel_digests"][0],
    }


def validate_entry(entry: dict[str, Any]) -> str | None:
    if not isinstance(entry.get("id"), str) or not entry["id"]:
        return "reference entry is missing a non-empty id"
    observed = entry.get("observed")
    limits = entry.get("limits")
    if not isinstance(observed, dict) or not isinstance(limits, dict):
        return "reference entry is missing observed values or limits"
    samples_by_process = observed.get("samples_ns_by_process")
    if not isinstance(samples_by_process, list):
        return "reference entry is missing raw per-process samples"
    match = entry.get("match")
    process_count = match.get("workload.process_repetitions") if isinstance(match, dict) else None
    if type(process_count) is not int or len(samples_by_process) != process_count:
        return "reference entry has the wrong process sample count"
    flattened: list[int] = []
    for process_samples in samples_by_process:
        if not isinstance(process_samples, list) or len(process_samples) != REPETITIONS:
            return "reference entry has an incomplete process sample set"
        if any(type(sample) is not int or sample <= 0 for sample in process_samples):
            return "reference entry contains invalid raw samples"
        flattened.extend(process_samples)
    flattened.sort()
    if observed.get("median_ns") != flattened[len(flattened) // 2] or observed.get("max_sample_ns") != flattened[-1]:
        return "reference summary does not match its raw samples"
    for key in ("median_ns", "max_sample_ns"):
        if type(limits.get(key)) is not int or limits[key] <= 0:
            return f"reference entry is missing a positive {key} limit"
        if type(observed.get(key)) is not int or observed[key] > limits[key]:
            return f"reference observed {key} exceeds or lacks its limit"
    digest = observed.get("tail_pixel_digest")
    if not isinstance(digest, str) or re.fullmatch(r"[0-9a-f]{16}", digest) is None:
        return "reference entry is missing its tail pixel digest"
    return None


def select_exact_budget(entries: list[dict[str, Any]], current_match: dict[str, Any]) -> dict[str, Any] | None:
    matches = [entry for entry in entries if isinstance(entry, dict) and entry.get("match") == current_match]
    return matches[0] if len(matches) == 1 else None


def evaluate_budget(entry: dict[str, Any], observed: dict[str, Any]) -> list[str]:
    failures: list[str] = []
    if observed["tail_pixel_digest"] != entry["observed"]["tail_pixel_digest"]:
        failures.append(
            f"tail_pixel_digest={observed['tail_pixel_digest']} differs from "
            f"recorded {entry['observed']['tail_pixel_digest']}"
        )
    for key in ("median_ns", "max_sample_ns"):
        if observed[key] > entry["limits"][key]:
            failures.append(f"{key}={observed[key]} exceeds {entry['limits'][key]}")
    return failures


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--root", type=Path, required=True)
    parser.add_argument("--stage1", type=Path, required=True)
    parser.add_argument("--skia-root", type=Path, required=True)
    parser.add_argument("--skia-out", type=Path, required=True)
    parser.add_argument("--skia-lib", type=Path, required=True)
    parser.add_argument("--log", type=Path, required=True)
    parser.add_argument("--manifest", type=Path, required=True)
    parser.add_argument("--process-repetitions", type=int, required=True)
    parser.add_argument("--width", type=int, required=True)
    parser.add_argument("--height", type=int, required=True)
    args = parser.parse_args()

    if args.process_repetitions <= 0 or args.width <= 0 or args.height <= 0:
        print("showcase skia performance: process count and dimensions must be positive", file=sys.stderr)
        return 2

    records = records_from_log(args.log)
    error = validate_records(records, args.process_repetitions)
    if error:
        print(f"showcase skia performance: invalid run: {error}", file=sys.stderr)
        return 2
    current = metadata(args.root, args.stage1.resolve(), args.skia_root.resolve(),
                       args.skia_out.resolve(), args.skia_lib.resolve(),
                       args.width, args.height, args.process_repetitions)
    current_match = flatten(current)
    try:
        manifest = json.loads(args.manifest.read_text())
    except (OSError, json.JSONDecodeError) as exc:
        print(f"showcase skia performance: cannot read budget manifest: {exc}", file=sys.stderr)
        return 2
    if not isinstance(manifest, dict) or manifest.get("schema_version") != 1:
        print("showcase skia performance: unsupported budget manifest", file=sys.stderr)
        return 2
    entries = manifest.get("reference_budgets", [])
    if not isinstance(entries, list):
        print("showcase skia performance: unsupported budget manifest", file=sys.stderr)
        return 2
    entry = select_exact_budget(entries, current_match)
    if entry is None:
        print("showcase skia performance: no unique exact host/compiler/Skia/workload budget; current tuple:")
        print(json.dumps(current_match, sort_keys=True, indent=2))
        return 5

    entry_error = validate_entry(entry)
    if entry_error:
        print(f"showcase skia performance: invalid reference entry: {entry_error}", file=sys.stderr)
        return 2
    observed = aggregate(records)
    failures = evaluate_budget(entry, observed)
    if failures:
        print("showcase skia performance: FAIL " + "; ".join(failures), file=sys.stderr)
        return 4
    print(
        "showcase skia performance: PASS "
        f"budget={entry['id']} processes={args.process_repetitions} "
        f"samples={args.process_repetitions * REPETITIONS} median_ns={observed['median_ns']} "
        f"max_sample_ns={observed['max_sample_ns']} tail_pixel_digest={observed['tail_pixel_digest']}"
    )
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
