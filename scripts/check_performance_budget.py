#!/usr/bin/env python3
"""Attach reproducibility metadata and enforce matching UI performance budgets."""

from __future__ import annotations

import argparse
import hashlib
import json
import platform
import shutil
import subprocess
import sys
from pathlib import Path
from typing import Any, Optional


PHASES = ("first_frame", "layout", "paint", "text", "text_input")
DEFAULT_ELISA_FLAGS = "-O2"
DEFAULT_C_FLAGS = "-O0 -std=c11 -Wall -Wextra -Werror"
DEFAULT_LINK_FLAGS = "-Wl,-dead_strip"


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


def file_hashes(root: Path) -> dict[str, str]:
    paths = {
        "benchmark_c": "test/performance_benchmark.c",
        "benchmark_elisa": "test/performance_benchmark.elisa",
    }
    return {name: sha256(root / path) for name, path in paths.items()}


def host_metadata() -> dict[str, str]:
    system = platform.system()
    os_version = output(["sw_vers", "-productVersion"]) if system == "Darwin" else platform.release()
    os_build = output(["sw_vers", "-buildVersion"]) if system == "Darwin" else ""
    return {
        "os_family": "macOS" if system == "Darwin" else system,
        "os_version": os_version,
        "os_major": os_version.split(".", 1)[0] if os_version else "",
        "os_build": os_build,
        "kernel_release": platform.release(),
        "architecture": platform.machine(),
        "model": output(["sysctl", "-n", "hw.model"]),
        "cpu": output(["sysctl", "-n", "machdep.cpu.brand_string"]),
    }


def compiler_metadata(stage1: Path) -> dict[str, str]:
    product = stage1 / "bin" / "elisac-stage1"
    runtime = stage1 / "build" / "runtime" / "elisacore_runtime.o"
    return {
        "revision": output(["git", "-C", str(stage1), "rev-parse", "HEAD"]),
        "product_sha256": sha256(product),
        "runtime_sha256": sha256(runtime),
    }


def clang_metadata() -> dict[str, str]:
    clang_path = shutil.which("clang")
    clang_version = output(["clang", "--version"]).splitlines()
    if not clang_path:
        return {"version": "unavailable", "binary_sha256": ""}
    try:
        clang_hash = sha256(Path(clang_path).resolve())
    except OSError:
        clang_hash = ""
    return {
        "version": clang_version[0] if clang_version else "unavailable",
        "binary_sha256": clang_hash,
    }


def flattened(value: dict[str, Any], prefix: str = "") -> dict[str, Any]:
    result: dict[str, Any] = {}
    for key, item in value.items():
        name = f"{prefix}.{key}" if prefix else key
        if isinstance(item, dict):
            result.update(flattened(item, name))
        else:
            result[name] = item
    return result


def budget_matches(metadata: dict[str, Any], entry: dict[str, Any]) -> bool:
    match = entry.get("match", {})
    comparable = {key: value for key, value in metadata.items() if key != "schema_version"}
    return isinstance(match, dict) and bool(match) and match == flattened(comparable)


def select_budget(metadata: dict[str, Any], entries: list[dict[str, Any]]) -> Optional[dict[str, Any]]:
    matches = [entry for entry in entries if budget_matches(metadata, entry)]
    return matches[0] if len(matches) == 1 else None


def missing_budget_exit_code(required: bool) -> int:
    return 5 if required else 0


def evaluate_limits(metrics: dict[str, Any], entry: dict[str, Any]) -> list[str]:
    limits = entry.get("limits", {})
    failures: list[str] = []
    for phase in PHASES:
        phase_limits = limits.get(phase, {})
        observed = metrics["phases"][phase]
        for name in ("median_batch_ns", "max_sample_ns"):
            limit = phase_limits.get(name)
            if limit is not None and observed[name] > limit:
                failures.append(f"{phase}.{name}={observed[name]} exceeds {limit}")
    rss_limit = limits.get("peak_rss_bytes")
    if rss_limit is not None and metrics["peak_rss_bytes"] > rss_limit:
        failures.append(f"peak_rss_bytes={metrics['peak_rss_bytes']} exceeds {rss_limit}")
    return failures


def validate_budget_entry(entry: dict[str, Any]) -> list[str]:
    errors: list[str] = []
    if not isinstance(entry.get("id"), str) or not entry["id"]:
        errors.append("missing non-empty budget id")
    if not isinstance(entry.get("match"), dict) or not entry["match"]:
        errors.append("missing exact-match metadata")

    limits = entry.get("limits")
    observed = entry.get("observed")
    if not isinstance(limits, dict):
        errors.append("missing limits object")
        limits = {}
    if not isinstance(observed, dict):
        errors.append("missing observed baseline object")
        observed = {}

    observed_phases = observed.get("phases")
    limit_rss = limits.get("peak_rss_bytes")
    observed_rss = observed.get("peak_rss_bytes")
    if not isinstance(observed_phases, dict):
        errors.append("missing observed phase baselines")
        observed_phases = {}
    match = entry.get("match", {})
    expected_processes = match.get("workload.process_repetitions") if isinstance(match, dict) else None
    expected_repetitions = match.get("workload.repetitions") if isinstance(match, dict) else None
    if type(expected_processes) is not int or expected_processes <= 0:
        errors.append("match must include a positive workload.process_repetitions")
    if type(expected_repetitions) is not int or expected_repetitions <= 0:
        errors.append("match must include a positive workload.repetitions")
    for name, value in (("limits.peak_rss_bytes", limit_rss), ("observed.peak_rss_bytes", observed_rss)):
        if type(value) is not int or value <= 0:
            errors.append(f"{name} must be a positive integer")
    if type(limit_rss) is int and type(observed_rss) is int and observed_rss > limit_rss:
        errors.append("observed.peak_rss_bytes exceeds its limit")

    limit_phases = limits.get("phases", {})
    if limit_phases:
        errors.append("phase limits must be declared directly under limits")
    for phase in PHASES:
        phase_limits = limits.get(phase)
        phase_observed = observed_phases.get(phase)
        if not isinstance(phase_limits, dict):
            errors.append(f"missing limits.{phase}")
            phase_limits = {}
        if not isinstance(phase_observed, dict):
            errors.append(f"missing observed.phases.{phase}")
            phase_observed = {}
        for field in ("median_batch_ns", "max_sample_ns"):
            limit = phase_limits.get(field)
            baseline = phase_observed.get(field)
            if type(limit) is not int or limit <= 0:
                errors.append(f"limits.{phase}.{field} must be a positive integer")
            if type(baseline) is not int or baseline <= 0:
                errors.append(f"observed.phases.{phase}.{field} must be a positive integer")
            elif type(limit) is int and baseline > limit:
                errors.append(f"observed.phases.{phase}.{field} exceeds its limit")
        median = phase_observed.get("median_batch_ns")
        maximum = phase_observed.get("max_sample_ns")
        if type(median) is int and type(maximum) is int and median > maximum:
            errors.append(f"observed.phases.{phase} median exceeds maximum")
        samples_by_process = phase_observed.get("samples_ns_by_process")
        if not isinstance(samples_by_process, list):
            errors.append(f"observed.phases.{phase} is missing raw samples")
            continue
        if type(expected_processes) is int and len(samples_by_process) != expected_processes:
            errors.append(f"observed.phases.{phase} has the wrong process sample count")
        flattened_samples: list[int] = []
        for process_samples in samples_by_process:
            if not isinstance(process_samples, list):
                errors.append(f"observed.phases.{phase} contains an invalid process sample set")
                continue
            if type(expected_repetitions) is int and len(process_samples) != expected_repetitions:
                errors.append(f"observed.phases.{phase} contains an incomplete raw sample set")
            if any(type(value) is not int or value <= 0 for value in process_samples):
                errors.append(f"observed.phases.{phase} contains an invalid raw duration")
                continue
            flattened_samples.extend(process_samples)
        if flattened_samples:
            ordered_samples = sorted(flattened_samples)
            raw_median = ordered_samples[len(ordered_samples) // 2]
            raw_maximum = ordered_samples[-1]
            if raw_median != median or raw_maximum != maximum:
                errors.append(f"observed.phases.{phase} summary does not match raw samples")
    return errors


def records_from_log(path: Path) -> tuple[list[dict[str, Any]], int]:
    records: list[dict[str, Any]] = []
    passed = 0
    for line in path.read_text(errors="replace").splitlines():
        line = line.strip()
        if line == "performance: benchmark passed":
            passed += 1
        if not line.startswith("{"):
            continue
        try:
            record = json.loads(line)
        except json.JSONDecodeError:
            continue
        if isinstance(record, dict) and record.get("workload_id"):
            records.append(record)
    return records, passed


def aggregate(records: list[dict[str, Any]]) -> dict[str, Any]:
    first = records[0]
    phases: dict[str, dict[str, int]] = {}
    for phase in PHASES:
        samples: list[int] = []
        for record in records:
            samples.extend(int(value) for value in record["phases"][phase]["samples_ns"])
        samples.sort()
        operations = int(records[0]["phases"][phase]["operations_per_batch"])
        phases[phase] = {
            "samples": len(samples),
            "median_batch_ns": samples[len(samples) // 2],
            "max_sample_ns": samples[-1],
            "median_operation_ns": samples[len(samples) // 2] // operations,
        }
    return {
        "processes": len(records),
        "iterations": first["iterations"],
        "warmups": first["warmups"],
        "repetitions_per_process": first["repetitions"],
        "large_tree_widgets": min(int(record["large_tree_widgets"]) for record in records),
        "large_tree_commands": min(int(record["large_tree_commands"]) for record in records),
        "peak_rss_bytes": max(int(record["peak_rss_bytes"]) for record in records),
        "phases": phases,
    }


def validate_records(records: list[dict[str, Any]], process_repetitions: int) -> Optional[str]:
    if len(records) != process_repetitions:
        return f"expected {process_repetitions} records; found {len(records)}"
    stable_fields = ("workload_id", "iterations", "warmups", "repetitions")
    first = records[0]
    for index, record in enumerate(records):
        if any(record.get(field) != first.get(field) for field in stable_fields):
            return "inconsistent benchmark workload records"
        repetitions = record.get("repetitions")
        if type(repetitions) is not int or repetitions <= 0:
            return f"record {index + 1} has invalid repetition count"
        if type(record.get("iterations")) is not int or record["iterations"] <= 0:
            return f"record {index + 1} has invalid iteration count"
        if type(record.get("warmups")) is not int or record["warmups"] < 0:
            return f"record {index + 1} has invalid warmup count"
        if type(record.get("peak_rss_bytes")) is not int or record["peak_rss_bytes"] <= 0:
            return f"record {index + 1} has invalid peak RSS"
        phases = record.get("phases")
        if not isinstance(phases, dict):
            return f"record {index + 1} is missing phase samples"
        for phase in PHASES:
            result = phases.get(phase)
            if not isinstance(result, dict):
                return f"record {index + 1} is missing phase {phase}"
            samples = result.get("samples_ns")
            operations = result.get("operations_per_batch")
            if not isinstance(samples, list) or len(samples) != repetitions:
                return f"record {index + 1} phase {phase} has an incomplete sample set"
            if any(type(value) is not int or value <= 0 for value in samples):
                return f"record {index + 1} phase {phase} has an invalid duration sample"
            if type(operations) is not int or operations <= 0:
                return f"record {index + 1} phase {phase} has an invalid operation count"
            ordered = sorted(samples)
            if result.get("median_batch_ns") != ordered[len(ordered) // 2]:
                return f"record {index + 1} phase {phase} median does not match samples"
            if result.get("max_sample_ns") != ordered[-1]:
                return f"record {index + 1} phase {phase} maximum does not match samples"
            if result.get("median_operation_ns") != ordered[len(ordered) // 2] // operations:
                return f"record {index + 1} phase {phase} operation time does not match samples"
            if index > 0:
                first_operations = records[0]["phases"][phase]["operations_per_batch"]
                if operations != first_operations:
                    return f"inconsistent {phase} operation counts across processes"
    return None


def make_metadata(
    root: Path,
    stage1: Path,
    records: list[dict[str, Any]],
    process_repetitions: int,
    elisa_flags: str = DEFAULT_ELISA_FLAGS,
    c_flags: str = DEFAULT_C_FLAGS,
    link_flags: str = DEFAULT_LINK_FLAGS,
) -> dict[str, Any]:
    first = records[0]
    clang = clang_metadata()
    operations = {
        name: int(first["phases"][name]["operations_per_batch"])
        for name in PHASES
    }
    return {
        "schema_version": 1,
        "workload": {
            "id": first["workload_id"],
            "iterations": first["iterations"],
            "warmups": first["warmups"],
            "repetitions": first["repetitions"],
            "process_repetitions": process_repetitions,
            "compile_flags": {
                "elisa": elisa_flags,
                "c": c_flags,
                "linker": link_flags,
            },
            "source_sha256": file_hashes(root),
            "operations_per_batch": operations,
        },
        "host": host_metadata(),
        "compiler": compiler_metadata(stage1),
        "clang": clang,
    }


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--root", type=Path, required=True)
    parser.add_argument("--stage1", type=Path, required=True)
    parser.add_argument("--log", type=Path, required=True)
    parser.add_argument("--manifest", type=Path, required=True)
    parser.add_argument("--process-repetitions", type=int, required=True)
    parser.add_argument("--elisa-flags", required=True)
    parser.add_argument("--c-flags", required=True)
    parser.add_argument("--link-flags", required=True)
    parser.add_argument("--require-budget", action="store_true")
    args = parser.parse_args()

    records, passed = records_from_log(args.log)
    record_error = validate_records(records, args.process_repetitions)
    if record_error or passed != args.process_repetitions:
        print(
            "performance: invalid benchmark run: "
            f"{record_error or 'wrong number of successful pass markers'}; "
            f"found {len(records)} records and {passed} pass markers",
            file=sys.stderr,
        )
        return 2
    if any(record.get("schema_version") != 1 for record in records):
        print("performance: unsupported benchmark result schema", file=sys.stderr)
        return 2
    metadata = make_metadata(
        args.root,
        args.stage1.resolve(),
        records,
        args.process_repetitions,
        args.elisa_flags,
        args.c_flags,
        args.link_flags,
    )
    metrics = aggregate(records)
    print("performance: metadata=" + json.dumps(metadata, sort_keys=True, separators=(",", ":")))
    print("performance: summary=" + json.dumps(metrics, sort_keys=True, separators=(",", ":")))

    try:
        manifest = json.loads(args.manifest.read_text())
    except (OSError, json.JSONDecodeError) as error:
        print(f"performance: cannot read budget manifest: {error}", file=sys.stderr)
        return 2
    if manifest.get("schema_version") != 1:
        print("performance: unsupported budget manifest schema", file=sys.stderr)
        return 2
    entries = manifest.get("reference_budgets")
    if not isinstance(entries, list):
        print("performance: reference_budgets must be a list", file=sys.stderr)
        return 2

    matches = [entry for entry in entries if isinstance(entry, dict) and budget_matches(metadata, entry)]
    if len(matches) > 1:
        print("performance: ambiguous exact reference-device/toolchain/workload match", file=sys.stderr)
        return 2
    if not matches:
        print("performance: UNBUDGETED; no exact reference-device/toolchain/workload match")
        return missing_budget_exit_code(args.require_budget)
    entry = matches[0]
    invalid_entry = validate_budget_entry(entry)
    if invalid_entry:
        print(f"performance: invalid reference budget {entry.get('id', 'unnamed')}: ", file=sys.stderr)
        for error in invalid_entry:
            print(f"performance: {error}", file=sys.stderr)
        return 2

    failures = evaluate_limits(metrics, entry)
    print(f"performance: reference_budget={entry.get('id', 'unnamed')} status={'FAIL' if failures else 'PASS'}")
    if failures:
        for failure in failures:
            print(f"performance: regression: {failure}", file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
