#!/usr/bin/env python3
"""Fast unit tests for exact-match and fail-on-regression budget behavior."""

import contextlib
import io
import json
import os
import sys
import tempfile
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / "scripts"))
import check_performance_budget as budget  # noqa: E402


class PerformanceBudgetTest(unittest.TestCase):
    def setUp(self):
        self.metadata = {
            "host": {
                "os_family": "macOS", "os_version": "26.6.2", "os_major": "26",
                "os_build": "25G83", "kernel_release": "25.6.0",
                "architecture": "arm64", "model": "Mac17,4", "cpu": "Apple M5",
            },
            "compiler": {
                "revision": "stage1-revision", "product_sha256": "product-hash",
                "runtime_sha256": "runtime-hash",
            },
            "clang": {"version": "clang 1.0", "binary_sha256": "clang-hash"},
            "workload": {
                "id": "retained-tree-v3-large-list", "iterations": 32, "warmups": 2,
                "repetitions": 7, "process_repetitions": 3,
                "compile_flags": {
                    "elisa": budget.DEFAULT_ELISA_FLAGS,
                    "c": budget.DEFAULT_C_FLAGS,
                    "linker": budget.DEFAULT_LINK_FLAGS,
                },
                "source_sha256": {
                    "benchmark_c": "c-hash", "benchmark_elisa": "elisa-hash",
                    "virtual_list_elisa": "virtual-list-hash",
                    "virtual_list_anchored_elisa": "virtual-list-window-hash",
                },
                "operations_per_batch": {
                    "first_frame": 32, "layout": 32, "paint": 32,
                    "text": 2048, "text_input": 512, "virtual_list_window": 128,
                },
            },
        }
        self.metrics = {
            "peak_rss_bytes": 100,
            "phases": {
                name: {"median_batch_ns": 10, "max_sample_ns": 12}
                for name in budget.PHASES
            },
        }
        limits = {
            name: {"median_batch_ns": 11, "max_sample_ns": 13}
            for name in budget.PHASES
        }
        limits["peak_rss_bytes"] = 110
        self.entry = {
            "id": "test-reference",
            "match": budget.flattened(self.metadata),
            "limits": limits,
            "observed": {
                "peak_rss_bytes": 100,
                "phases": {
                    name: {
                        "median_batch_ns": 10,
                        "max_sample_ns": 12,
                        "samples_ns_by_process": [[10, 10, 10, 10, 10, 10, 12]] * 3,
                    }
                    for name in budget.PHASES
                },
            },
        }

    def test_exact_device_workload_and_compiler_match(self):
        self.assertTrue(budget.budget_matches(self.metadata, self.entry))

    def test_changed_compiler_product_does_not_inherit_budget(self):
        self.metadata["compiler"]["product_sha256"] = "different-product-hash"
        self.assertFalse(budget.budget_matches(self.metadata, self.entry))

    def test_partial_exact_tuple_does_not_inherit_budget(self):
        del self.entry["match"]["compiler.product_sha256"]
        self.assertFalse(budget.budget_matches(self.metadata, self.entry))

    def test_different_device_does_not_inherit_budget(self):
        self.metadata["host"]["model"] = "DifferentDevice"
        self.assertFalse(budget.budget_matches(self.metadata, self.entry))
        self.assertIsNone(budget.select_budget(self.metadata, [self.entry]))
        self.assertEqual(budget.missing_budget_exit_code(required=True), 5)
        self.assertEqual(budget.missing_budget_exit_code(required=False), 0)

    def test_ambiguous_budget_does_not_pick_arbitrarily(self):
        self.assertIsNone(budget.select_budget(self.metadata, [self.entry, self.entry]))

    def test_recorded_reference_tuple_matches_when_present(self):
        stage1 = Path(os.environ.get("ELISA_UI_STAGE1", ROOT.parent / "Elisa-compiler"))
        if not (stage1 / "bin/elisac-stage1").is_file():
            self.skipTest("latest compiler checkout is unavailable")
        record = {
            "workload_id": "retained-tree-v3-large-list",
            "iterations": 32,
            "warmups": 2,
            "repetitions": 7,
            "phases": {
                name: {"operations_per_batch": count}
                for name, count in {
                    "first_frame": 32, "layout": 32, "paint": 32,
                    "text": 2048, "text_input": 512, "virtual_list_window": 128,
                }.items()
            },
        }
        metadata = budget.make_metadata(ROOT, stage1.resolve(), [record], process_repetitions=3)
        manifest = json.loads((ROOT / "test/performance_budgets.json").read_text())
        entry = budget.select_budget(metadata, manifest["reference_budgets"])
        if entry is None:
            self.skipTest("this host/compiler tuple has no reference budget")
        self.assertEqual(entry["id"], "macos26-mac17-4-apple-m5-fd2cb3c-retained-tree-v3-large-list")
        self.assertEqual(budget.evaluate_limits(entry["observed"], entry), [])

    def test_required_mode_accepts_exact_budget_and_rejects_missing_budget(self):
        stage1 = Path(os.environ.get("ELISA_UI_STAGE1", ROOT.parent / "Elisa-compiler"))
        if not (stage1 / "bin/elisac-stage1").is_file():
            self.skipTest("latest compiler checkout is unavailable")
        manifest_path = ROOT / "test/performance_budgets.json"
        manifest = json.loads(manifest_path.read_text())
        operation_counts = {
            "first_frame": 32, "layout": 32, "paint": 32,
            "text": 2048, "text_input": 512, "virtual_list_window": 128,
        }
        record = {
            "schema_version": 1,
            "workload_id": "retained-tree-v3-large-list",
            "iterations": 32,
            "warmups": 2,
            "repetitions": 7,
            "phases": {
                name: {"operations_per_batch": operations}
                for name, operations in operation_counts.items()
            },
        }
        metadata = budget.make_metadata(ROOT, stage1.resolve(), [record], 3)
        entry = budget.select_budget(metadata, manifest["reference_budgets"])
        if entry is None:
            self.skipTest("this host/compiler/workload tuple has no reference budget")
        observed = entry["observed"]
        record["large_tree_widgets"] = 221
        record["large_tree_commands"] = 221
        record["peak_rss_bytes"] = observed["peak_rss_bytes"]
        for name, phase in observed["phases"].items():
            record["phases"][name] = {
                "samples_ns": [phase["median_batch_ns"]] * 6 + [phase["max_sample_ns"]],
                "operations_per_batch": operation_counts[name],
                "median_batch_ns": phase["median_batch_ns"],
                "max_sample_ns": phase["max_sample_ns"],
                "median_operation_ns": phase["median_batch_ns"] // operation_counts[name],
            }

        with tempfile.TemporaryDirectory(prefix="elisa-perf-budget-test-") as temp:
            temp_path = Path(temp)
            log_path = temp_path / "run.log"
            log_path.write_text((json.dumps(record) + "\nperformance: benchmark passed\n") * 3)
            previous_argv = sys.argv
            try:
                sys.argv = [
                    "check_performance_budget.py", "--root", str(ROOT),
                    "--stage1", str(stage1), "--log", str(log_path),
                    "--manifest", str(manifest_path), "--process-repetitions", "3",
                    f"--elisa-flags={budget.DEFAULT_ELISA_FLAGS}",
                    f"--c-flags={budget.DEFAULT_C_FLAGS}",
                    f"--link-flags={budget.DEFAULT_LINK_FLAGS}",
                    "--require-budget",
                ]
                capture = io.StringIO()
                with contextlib.redirect_stdout(capture):
                    result = budget.main()
                self.assertEqual(result, 0)
                self.assertIn(
                    "reference_budget=macos26-mac17-4-apple-m5-fd2cb3c-retained-tree-v3-large-list status=PASS",
                    capture.getvalue(),
                )

                empty_manifest = temp_path / "empty.json"
                empty_manifest.write_text('{"schema_version":1,"reference_budgets":[]}')
                sys.argv[sys.argv.index(str(manifest_path))] = str(empty_manifest)
                with contextlib.redirect_stdout(io.StringIO()):
                    self.assertEqual(budget.main(), 5)

                partial_manifest = temp_path / "partial.json"
                partial_entry = dict(manifest["reference_budgets"][0])
                partial_entry["limits"] = dict(partial_entry["limits"])
                del partial_entry["limits"]["text_input"]
                partial_manifest.write_text(json.dumps({
                    "schema_version": 1,
                    "reference_budgets": [partial_entry],
                }))
                sys.argv[sys.argv.index(str(empty_manifest))] = str(partial_manifest)
                with contextlib.redirect_stdout(io.StringIO()), contextlib.redirect_stderr(io.StringIO()):
                    self.assertEqual(budget.main(), 2)
            finally:
                sys.argv = previous_argv

    def test_aggregation_preserves_worst_sample_and_operation_count(self):
        phases = {
            name: {
                "samples_ns": [10, 14],
                "operations_per_batch": 2,
                "median_batch_ns": 14,
                "max_sample_ns": 14,
                "median_operation_ns": 7,
            }
            for name in budget.PHASES
        }
        record = {
            "iterations": 32,
            "warmups": 2,
            "repetitions": 2,
            "large_tree_widgets": 221,
            "large_tree_commands": 221,
            "peak_rss_bytes": 100,
            "phases": phases,
        }
        later = {**record, "phases": {
            name: {**phase, "samples_ns": [11, 15]}
            for name, phase in phases.items()
        }, "peak_rss_bytes": 120}
        result = budget.aggregate([record, later])
        self.assertEqual(result["phases"]["paint"]["samples"], 4)
        self.assertEqual(result["phases"]["paint"]["median_batch_ns"], 14)
        self.assertEqual(result["phases"]["paint"]["max_sample_ns"], 15)
        self.assertEqual(result["phases"]["paint"]["median_operation_ns"], 7)
        self.assertEqual(result["peak_rss_bytes"], 120)

    def test_incomplete_measurement_record_is_rejected(self):
        record = {
            "schema_version": 1,
            "workload_id": "retained-tree-v3-large-list",
            "iterations": 32,
            "warmups": 2,
            "repetitions": 7,
            "peak_rss_bytes": 100,
            "phases": {
                name: {
                    "samples_ns": [10] * 6,
                    "operations_per_batch": 1,
                    "median_batch_ns": 10,
                    "max_sample_ns": 10,
                    "median_operation_ns": 10,
                }
                for name in budget.PHASES
            },
        }
        self.assertIn("incomplete sample set", budget.validate_records([record], 1))

    def test_phase_and_memory_overages_are_reported(self):
        self.metrics["phases"]["paint"]["max_sample_ns"] = 14
        self.metrics["peak_rss_bytes"] = 111
        failures = budget.evaluate_limits(self.metrics, self.entry)
        self.assertEqual(len(failures), 2)
        self.assertTrue(any("paint.max_sample_ns" in failure for failure in failures))
        self.assertTrue(any("peak_rss_bytes" in failure for failure in failures))

    def test_incomplete_reference_budget_is_rejected(self):
        del self.entry["limits"]["paint"]
        errors = budget.validate_budget_entry(self.entry)
        self.assertIn("missing limits.paint", errors)


if __name__ == "__main__":
    unittest.main()
