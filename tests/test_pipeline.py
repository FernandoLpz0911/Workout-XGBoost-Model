"""Tests for pipeline.py — pure computation, no external dependencies."""

import io

import numpy as np
import pytest

from pipeline import STRENGTH_CATEGORIES, _tag_comment, calculate_hybrid_1rm, run_pipeline


# ── Helpers ───────────────────────────────────────────────────────────────────

def _csv(*rows: str) -> io.BytesIO:
    """Build an in-memory CSV file with a FitNotes-compatible header."""
    header = "Date,Exercise,Category,Weight,Reps,Comment"
    return io.BytesIO(("\n".join([header, *rows]) + "\n").encode())


BENCH_ROWS = [
    "2026-01-01,Bench Press,Chest,100,8,",
    "2026-01-08,Bench Press,Chest,105,8,felt good",
    "2026-01-15,Bench Press,Chest,110,8,",
]
SQUAT_ROWS = [
    "2026-01-01,Squat,Legs,150,5,",
    "2026-01-08,Squat,Legs,155,5,",
]


# ── calculate_hybrid_1rm ─────────────────────────────────────────────────────

class TestCalculateHybrid1RM:
    def test_zero_reps_returns_zero(self):
        assert calculate_hybrid_1rm(100, 0) == 0

    def test_one_rep_equals_weight(self):
        assert calculate_hybrid_1rm(100, 1) == pytest.approx(100.0, abs=0.1)

    def test_brzycki_for_six_reps(self):
        expected = 100 / (1.0278 - 0.0278 * 6)
        assert calculate_hybrid_1rm(100, 6) == pytest.approx(expected, abs=0.1)

    def test_epley_for_seven_reps(self):
        expected = 100 * (1 + 0.0333 * 7)
        assert calculate_hybrid_1rm(100, 7) == pytest.approx(expected, abs=0.1)

    def test_mayhew_for_twelve_reps(self):
        expected = (100 * 100) / (52.2 + 41.9 * np.exp(-0.055 * 12))
        assert calculate_hybrid_1rm(100, 12) == pytest.approx(expected, abs=0.1)

    def test_scales_linearly_with_weight(self):
        assert calculate_hybrid_1rm(200, 5) == pytest.approx(
            calculate_hybrid_1rm(100, 5) * 2, abs=0.01
        )

    def test_boundary_6_uses_brzycki_not_epley(self):
        brzycki = 100 / (1.0278 - 0.0278 * 6)
        assert calculate_hybrid_1rm(100, 6) == pytest.approx(brzycki, abs=0.01)

    def test_boundary_7_uses_epley_not_brzycki(self):
        epley = 100 * (1 + 0.0333 * 7)
        assert calculate_hybrid_1rm(100, 7) == pytest.approx(epley, abs=0.01)


# ── _tag_comment ─────────────────────────────────────────────────────────────

class TestTagComment:
    def test_empty_string_returns_zeros(self):
        assert _tag_comment("") == (0, 0, False, False)

    def test_nan_returns_zeros(self):
        assert _tag_comment(float("nan")) == (0, 0, False, False)

    def test_form_issue_detected(self):
        form, fatigue, drop, warmup = _tag_comment("did it wrong")
        assert form == 1
        assert fatigue == 0

    def test_fatigue_detected(self):
        _, fatigue, _, _ = _tag_comment("forearm fatigued")
        assert fatigue == 1

    def test_drop_set_detected(self):
        _, _, drop, _ = _tag_comment("drop set")
        assert drop is True

    def test_warmup_detected(self):
        _, _, _, warmup = _tag_comment("warm up set")
        assert warmup is True

    def test_case_insensitive_form(self):
        form, _, _, _ = _tag_comment("DID IT WRONG")
        assert form == 1

    def test_clean_comment_returns_all_zeros(self):
        assert _tag_comment("felt great today") == (0, 0, False, False)


# ── run_pipeline ──────────────────────────────────────────────────────────────

class TestRunPipeline:
    def test_returns_three_values(self):
        model, feature_cols, summary = run_pipeline(_csv(*BENCH_ROWS, *SQUAT_ROWS))
        assert model is not None
        assert isinstance(feature_cols, list)
        assert not summary.empty

    def test_feature_cols_are_strings(self):
        _, feature_cols, _ = run_pipeline(_csv(*BENCH_ROWS))
        assert all(isinstance(c, str) for c in feature_cols)

    def test_summary_contains_expected_columns(self):
        _, _, summary = run_pipeline(_csv(*BENCH_ROWS))
        for col in ["Exercise", "Category", "Session_Max_1RM", "Max_Weight"]:
            assert col in summary.columns

    def test_cardio_excluded_from_model(self):
        f = _csv(
            "2026-01-01,General Running,Cardio,0,0,",
            "2026-01-01,Bench Press,Chest,100,8,",
        )
        _, _, summary = run_pipeline(f)
        assert "General Running" not in summary["Exercise"].values
        assert "Bench Press" in summary["Exercise"].values

    def test_drop_sets_excluded(self):
        f = _csv(
            "2026-01-01,Bench Press,Chest,100,8,",
            "2026-01-01,Bench Press,Chest,80,12,drop set",
            "2026-01-08,Bench Press,Chest,105,8,",
        )
        _, _, summary = run_pipeline(f)
        first = summary[summary["Exercise"] == "Bench Press"].iloc[0]
        assert first["Max_Weight"] == pytest.approx(100.0, abs=0.01)

    def test_warmup_sets_excluded(self):
        f = _csv(
            "2026-01-01,Bench Press,Chest,45,15,warm up",
            "2026-01-01,Bench Press,Chest,100,8,",
            "2026-01-08,Bench Press,Chest,105,8,",
        )
        _, _, summary = run_pipeline(f)
        first = summary[summary["Exercise"] == "Bench Press"].iloc[0]
        assert first["Max_Weight"] == pytest.approx(100.0, abs=0.01)

    def test_weight_based_warmups_excluded(self):
        # 45 lbs < 60 % of 135 lbs — should be filtered out
        f = _csv(
            "2026-01-01,Bench Press,Chest,45,15,",
            "2026-01-01,Bench Press,Chest,135,8,",
        )
        _, _, summary = run_pipeline(f)
        assert summary.iloc[0]["Max_Weight"] == pytest.approx(135.0, abs=0.01)

    def test_non_numeric_weight_rows_skipped(self):
        f = _csv(
            "2026-01-01,Bench Press,Chest,hundred,8,",
            "2026-01-08,Bench Press,Chest,105,8,",
        )
        model, _, summary = run_pipeline(f)
        assert model is not None
        assert len(summary) == 1

    def test_non_numeric_reps_rows_skipped(self):
        f = _csv(
            "2026-01-01,Bench Press,Chest,100,many,",
            "2026-01-08,Bench Press,Chest,105,8,",
        )
        _, _, summary = run_pipeline(f)
        assert len(summary) == 1

    def test_predict_returns_float(self):
        import pandas as pd

        model, feature_cols, _ = run_pipeline(_csv(*BENCH_ROWS))
        sim = pd.DataFrame({col: [0.0] for col in feature_cols})
        pred = model.predict(sim)
        assert len(pred) == 1
        assert isinstance(float(pred[0]), float)

    def test_single_session_completes_without_error(self):
        f = _csv("2026-01-01,Bench Press,Chest,100,8,")
        model, feature_cols, summary = run_pipeline(f)
        assert not summary.empty

    def test_multiple_exercises_produce_separate_summary_rows(self):
        f = _csv(*BENCH_ROWS, *SQUAT_ROWS)
        _, _, summary = run_pipeline(f)
        exercises = set(summary["Exercise"].unique())
        assert "Bench Press" in exercises
        assert "Squat" in exercises

    def test_days_since_last_is_14_for_first_session(self):
        f = _csv(*BENCH_ROWS)
        _, _, summary = run_pipeline(f)
        first = summary[summary["Exercise"] == "Bench Press"].iloc[0]
        assert first["Days_Since_Last"] == pytest.approx(14.0, abs=0.01)

    def test_days_since_last_correct_for_second_session(self):
        # Sessions 7 days apart
        f = _csv(
            "2026-01-01,Bench Press,Chest,100,8,",
            "2026-01-08,Bench Press,Chest,105,8,",
        )
        _, _, summary = run_pipeline(f)
        second = summary[summary["Exercise"] == "Bench Press"].iloc[1]
        assert second["Days_Since_Last"] == pytest.approx(7.0, abs=0.01)

    def test_strength_categories_constant_is_a_set(self):
        assert isinstance(STRENGTH_CATEGORIES, set)
        assert "Chest" in STRENGTH_CATEGORIES
        assert "Cardio" not in STRENGTH_CATEGORIES
