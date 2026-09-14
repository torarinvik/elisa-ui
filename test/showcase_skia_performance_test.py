#!/usr/bin/env python3
"""Regression checks for real-renderer latency record validation."""

from __future__ import annotations

import sys
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / "scripts"))
import check_showcase_skia_performance as budget  # noqa: E402


def record(samples: list[int], digests: list[str] | None = None) -> dict[str, object]:
    return {
        "workload_id": budget.WORKLOAD_ID,
        "warmups": budget.WARMUPS,
        "repetitions": budget.REPETITIONS,
        "operations_per_batch": 1,
        "samples_ns": samples,
        "tail_pixel_digests": digests or ["0123456789abcdef"] * budget.REPETITIONS,
    }


class ShowcaseSkiaPerformanceTest(unittest.TestCase):
    def test_accepts_complete_process_samples_with_stable_pixels(self) -> None:
        samples = list(range(1, budget.REPETITIONS + 1))
        valid = record(samples)
        self.assertIsNone(budget.validate_records([valid] * 3, 3))
        summary = budget.aggregate([valid] * 3)
        self.assertEqual(summary["median_ns"], 4)
        self.assertEqual(summary["max_sample_ns"], 7)

    def test_rejects_missing_process_or_incomplete_samples(self) -> None:
        samples = list(range(1, budget.REPETITIONS + 1))
        self.assertIn("expected 3", budget.validate_records([record(samples)], 3) or "")
        self.assertIn("incomplete latency", budget.validate_records([record(samples[:-1])], 1) or "")

    def test_rejects_nonpositive_duration_and_bad_operation_count(self) -> None:
        samples = list(range(1, budget.REPETITIONS + 1))
        invalid_time = record([0, *samples[1:]])
        self.assertIn("invalid latency", budget.validate_records([invalid_time], 1) or "")
        invalid_work = record(samples)
        invalid_work["operations_per_batch"] = 0
        self.assertIn("one complete workflow", budget.validate_records([invalid_work], 1) or "")

    def test_rejects_unstable_rendered_pixels(self) -> None:
        samples = list(range(1, budget.REPETITIONS + 1))
        digests = ["0123456789abcdef"] * (budget.REPETITIONS - 1) + ["fedcba9876543210"]
        self.assertIn("different tail pixels", budget.validate_records([record(samples, digests)], 1) or "")
        one = record(samples)
        two = record(samples, ["fedcba9876543210"] * budget.REPETITIONS)
        self.assertIn("different tail pixels", budget.validate_records([one, two], 2) or "")
        malformed = record(samples, ["0123456789abcdeg"] * budget.REPETITIONS)
        self.assertIn("invalid pixel digest", budget.validate_records([malformed], 1) or "")

    def test_reference_requires_raw_samples_and_consistent_summaries(self) -> None:
        samples = list(range(1, budget.REPETITIONS + 1))
        entry = {
            "id": "unit-test-reference",
            "match": {"workload.process_repetitions": 1},
            "limits": {"median_ns": 4, "max_sample_ns": 7},
            "observed": {
                "samples_ns_by_process": [samples],
                "median_ns": 4,
                "max_sample_ns": 7,
                "tail_pixel_digest": "0123456789abcdef",
            },
        }
        self.assertIsNone(budget.validate_entry(entry))
        entry["observed"]["median_ns"] = 3
        self.assertIn("does not match", budget.validate_entry(entry) or "")

    def test_gate_requires_one_exact_tuple(self) -> None:
        exact = {"host.model": "Mac17,4", "compiler.product_sha256": "product"}
        entry = {"id": "exact", "match": exact}
        self.assertIs(budget.select_exact_budget([entry], exact), entry)
        self.assertIsNone(budget.select_exact_budget([entry], {"host.model": "other"}))
        self.assertIsNone(budget.select_exact_budget([entry, entry], exact))

    def test_gate_rejects_latency_regressions_and_changed_render(self) -> None:
        entry = {
            "observed": {"tail_pixel_digest": "0123456789abcdef"},
            "limits": {"median_ns": 100, "max_sample_ns": 120},
        }
        within = {
            "median_ns": 100,
            "max_sample_ns": 120,
            "tail_pixel_digest": "0123456789abcdef",
        }
        self.assertEqual(budget.evaluate_budget(entry, within), [])
        regressed = {
            "median_ns": 101,
            "max_sample_ns": 121,
            "tail_pixel_digest": "fedcba9876543210",
        }
        failures = budget.evaluate_budget(entry, regressed)
        self.assertEqual(len(failures), 3)
        self.assertTrue(any("median_ns" in failure for failure in failures))
        self.assertTrue(any("max_sample_ns" in failure for failure in failures))
        self.assertTrue(any("tail_pixel_digest" in failure for failure in failures))

    def test_limits_are_positive_and_must_cover_the_baseline(self) -> None:
        entry = {
            "id": "unit-test-reference",
            "match": {"workload.process_repetitions": 1},
            "limits": {"median_ns": 3, "max_sample_ns": 7},
            "observed": {
                "samples_ns_by_process": [list(range(1, budget.REPETITIONS + 1))],
                "median_ns": 4,
                "max_sample_ns": 7,
                "tail_pixel_digest": "0123456789abcdef",
            },
        }
        self.assertIn("exceeds or lacks", budget.validate_entry(entry) or "")


if __name__ == "__main__":
    unittest.main()
