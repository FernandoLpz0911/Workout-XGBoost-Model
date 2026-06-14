"""Tests for api.py FastAPI endpoints.

External dependencies (Firebase Admin, GCS, pipeline) are mocked in
conftest.py so no cloud credentials are needed.
"""

import time
from unittest.mock import MagicMock, patch

import pandas as pd
import pytest
from fastapi.testclient import TestClient

import api
from api import (
    _model_cache,
    _model_loaded_at,
    app,
    get_uid,
)

# Override auth so every request authenticates as "uid_test" without Firebase.
app.dependency_overrides[get_uid] = lambda: "uid_test"

client = TestClient(app)

UID = "uid_test"


def _make_model_assets():
    """Return a minimal (model, feature_cols, summary) tuple."""
    import pandas as pd

    model = MagicMock()
    model.predict.return_value = [150.0]
    feature_cols = [
        "Days_Since_Last", "Previous_1RM", "Last_Avg_Reps",
        "Prev_Volume_Load", "Prev_Rep_Consistency", "Prev_Form_Issue",
        "Prev_Fatigue", "RM_Momentum",
        "Exercise_Bench Press", "Category_Chest",
    ]
    summary = pd.DataFrame({
        "Exercise": ["Bench Press"],
        "Category": ["Chest"],
        "Session_Max_1RM": [145.0],
        "Days_Since_Last": [7.0],
        "Max_Weight": [135.0],
        "Avg_Reps": [8.0],
        "Volume_Load": [3240.0],
        "Rep_Consistency": [0.9],
        "Had_Form_Issue": [0],
        "Had_Fatigue": [0],
    })
    return model, feature_cols, summary


def _inject_model(uid, assets):
    """Inject model assets into the cache with a fresh timestamp."""
    _model_cache[uid] = assets
    _model_loaded_at[uid] = time.monotonic()


@pytest.fixture(autouse=True)
def clear_caches():
    """Reset in-process caches between tests so state doesn't leak."""
    _model_cache.clear()
    _model_loaded_at.clear()
    yield
    _model_cache.clear()
    _model_loaded_at.clear()


class TestTrainEndpoint:
    def test_rejects_non_csv_file(self):
        response = client.post(
            "/train",
            files={"file": ("data.json", b"{}", "application/json")},
        )
        assert response.status_code == 400
        assert "CSV" in response.json()["detail"]

    def test_accepts_csv_and_returns_200(self):
        with patch.object(api, "_run_train"):
            response = client.post(
                "/train",
                files={
                    "file": (
                        "data.csv",
                        b"Date,Exercise\n2026-01-01,Squat",
                        "text/csv",
                    )
                },
            )
        assert response.status_code == 200
        assert "Training started" in response.json()["message"]

    def test_rejects_oversized_csv(self):
        from api import _MAX_CSV_BYTES

        oversized = b"x" * (_MAX_CSV_BYTES + 1)
        with patch.object(api, "_run_train"):
            response = client.post(
                "/train",
                files={"file": ("big.csv", oversized, "text/csv")},
            )
        assert response.status_code == 413
        assert "too large" in response.json()["detail"].lower()

    def test_returns_409_when_training_in_progress(self):
        with patch.object(api, "_training_status_ref") as mock_ref_fn:
            mock_ref = MagicMock()
            mock_ref_fn.return_value = mock_ref

            import sys
            gcp_firestore_mock = sys.modules["google.cloud.firestore"]
            original = gcp_firestore_mock.transactional

            def fake_transactional(fn):
                def wrapper(txn):
                    return False  # always report slot taken
                return wrapper

            gcp_firestore_mock.transactional = fake_transactional
            try:
                response = client.post(
                    "/train",
                    files={"file": ("data.csv", b"a,b\n1,2", "text/csv")},
                )
                assert response.status_code == 409
            finally:
                gcp_firestore_mock.transactional = original


class TestExercisesEndpoint:
    def test_returns_404_when_no_model(self):
        response = client.get("/exercises")
        assert response.status_code == 404

    def test_returns_grouped_exercises_when_model_exists(self):
        _inject_model(UID, _make_model_assets())
        response = client.get("/exercises")
        assert response.status_code == 200
        data = response.json()
        assert "Chest" in data
        assert "Bench Press" in data["Chest"]


class TestRecommendEndpoint:
    def test_returns_404_when_no_model(self):
        response = client.post(
            "/recommend",
            json={"exercise": "Bench Press", "category": "Chest"},
        )
        assert response.status_code == 404

    def test_returns_404_for_unknown_exercise(self):
        _inject_model(UID, _make_model_assets())
        response = client.post(
            "/recommend",
            json={"exercise": "Leg Press", "category": "Legs"},
        )
        assert response.status_code == 404

    def test_returns_recommendation_for_known_exercise(self):
        _inject_model(UID, _make_model_assets())
        response = client.post(
            "/recommend",
            json={"exercise": "Bench Press", "category": "Chest"},
        )
        assert response.status_code == 200
        body = response.json()
        assert "target_reps" in body
        assert "target_weight" in body
        assert "status" in body
        assert "predicted_1rm" in body

    def test_recommendation_fields_are_correct_types(self):
        _inject_model(UID, _make_model_assets())
        response = client.post(
            "/recommend",
            json={"exercise": "Bench Press", "category": "Chest"},
        )
        body = response.json()
        assert isinstance(body["target_reps"], int)
        assert isinstance(body["target_weight"], float)
        assert isinstance(body["predicted_1rm"], float)
        assert isinstance(body["status"], str)
        assert isinstance(body["notes_insight"], str)

    def test_strength_mode_accepted(self):
        _inject_model(UID, _make_model_assets())
        response = client.post(
            "/recommend",
            json={
                "exercise": "Bench Press",
                "category": "Chest",
                "mode": "strength",
            },
        )
        assert response.status_code == 200
        body = response.json()
        valid = {"STRENGTH", "FORM", "DELOAD", "AI OVERRIDE"}
        assert any(v in body["status"] for v in valid)

    def test_unknown_mode_falls_back_to_hypertrophy(self):
        _inject_model(UID, _make_model_assets())
        response = client.post(
            "/recommend",
            json={
                "exercise": "Bench Press",
                "category": "Chest",
                "mode": "invalid",
            },
        )
        assert response.status_code == 200
        body = response.json()
        valid = {"HYPERTROPHY", "FORM", "DELOAD", "AI OVERRIDE"}
        assert any(v in body["status"] for v in valid)


class TestModelCache:
    def test_evict_model_cache_removes_oldest_entry(self):
        from api import _CACHE_MAX, _evict_model_cache

        for i in range(_CACHE_MAX):
            _inject_model(f"uid_{i}", (MagicMock(), [], MagicMock()))

        assert len(_model_cache) == _CACHE_MAX
        assert len(_model_loaded_at) == _CACHE_MAX
        _evict_model_cache()
        assert len(_model_cache) == _CACHE_MAX - 1
        assert "uid_0" not in _model_cache
        assert "uid_0" not in _model_loaded_at

    def test_evict_model_cache_no_op_when_under_limit(self):
        from api import _evict_model_cache

        _model_cache["only_one"] = (MagicMock(), [], MagicMock())
        _evict_model_cache()
        assert "only_one" in _model_cache


class TestDeleteUserDataEndpoint:
    def test_returns_200(self):
        response = client.delete("/delete-user-data")
        assert response.status_code == 200
        assert "deleted" in response.json()["message"].lower()

    def test_evicts_model_cache(self):
        _inject_model(UID, _make_model_assets())
        assert UID in _model_cache
        client.delete("/delete-user-data")
        assert UID not in _model_cache


# ── /recommend decision-tree tests ───────────────────────────────────────────

_DEFAULT_FEATURE_COLS = [
    "Days_Since_Last", "Previous_1RM", "Last_Avg_Reps",
    "Prev_Volume_Load", "Prev_Rep_Consistency", "Prev_Form_Issue",
    "Prev_Fatigue", "RM_Momentum",
    "Exercise_Bench Press", "Category_Chest",
]


def _make_custom_assets(
    avg_reps=8.0,
    max_weight=135.0,
    had_form=0,
    had_fatigue=0,
    pred_1rm=300.0,
    summary_rows=None,
):
    """Return (model, feature_cols, summary) with configurable last-session data."""
    model = MagicMock()
    model.predict.return_value = [pred_1rm]
    if summary_rows is not None:
        summary = pd.DataFrame(summary_rows)
    else:
        summary = pd.DataFrame({
            "Exercise": ["Bench Press"],
            "Category": ["Chest"],
            "Session_Max_1RM": [145.0],
            "Days_Since_Last": [7.0],
            "Max_Weight": [max_weight],
            "Avg_Reps": [avg_reps],
            "Volume_Load": [max_weight * avg_reps * 3],
            "Rep_Consistency": [0.9],
            "Had_Form_Issue": [had_form],
            "Had_Fatigue": [had_fatigue],
        })
    return model, _DEFAULT_FEATURE_COLS, summary


def _plateau_rows(max_weight=135.0, avg_reps=8.0):
    """Four sessions with a flat 1RM — triggers the plateau detection."""
    return {
        "Exercise": ["Bench Press"] * 4,
        "Category": ["Chest"] * 4,
        "Session_Max_1RM": [150.0, 150.5, 151.0, 150.2],
        "Days_Since_Last": [7.0] * 4,
        "Max_Weight": [max_weight] * 4,
        "Avg_Reps": [avg_reps] * 4,
        "Volume_Load": [max_weight * avg_reps * 3] * 4,
        "Rep_Consistency": [0.9] * 4,
        "Had_Form_Issue": [0] * 4,
        "Had_Fatigue": [0] * 4,
    }


class TestRecommendLogic:
    """Tests for the /recommend decision tree branches and insight generation."""

    def _post(self, exercise="Bench Press", category="Chest", mode="hypertrophy"):
        return client.post(
            "/recommend",
            json={"exercise": exercise, "category": category, "mode": mode},
        )

    # FORM FOCUS ──────────────────────────────────────────────────────────────

    def test_form_focus_status(self):
        _inject_model(UID, _make_custom_assets(had_form=1, pred_1rm=300.0))
        assert "FORM FOCUS" in self._post().json()["status"]

    def test_form_focus_holds_weight(self):
        _inject_model(UID, _make_custom_assets(had_form=1, max_weight=135.0, pred_1rm=300.0))
        assert self._post().json()["target_weight"] == pytest.approx(135.0)

    def test_form_focus_sets_hypertrophy_default_reps(self):
        _inject_model(UID, _make_custom_assets(had_form=1, pred_1rm=300.0))
        assert self._post().json()["target_reps"] == 10

    def test_form_focus_insight_mentions_technique(self):
        _inject_model(UID, _make_custom_assets(had_form=1, pred_1rm=300.0))
        insight = self._post().json()["notes_insight"].lower()
        assert "technique" in insight or "form" in insight

    # DELOAD ──────────────────────────────────────────────────────────────────

    def test_deload_status_when_plateau(self):
        _inject_model(UID, _make_custom_assets(pred_1rm=300.0, summary_rows=_plateau_rows()))
        assert "DELOAD" in self._post().json()["status"]

    def test_deload_sets_reps_to_15(self):
        _inject_model(UID, _make_custom_assets(pred_1rm=300.0, summary_rows=_plateau_rows()))
        assert self._post().json()["target_reps"] == 15

    def test_deload_reduces_weight_to_60_percent(self):
        _inject_model(UID, _make_custom_assets(pred_1rm=300.0, summary_rows=_plateau_rows(max_weight=100.0)))
        assert self._post().json()["target_weight"] < 100.0

    # HYPERTROPHY PROGRESSION ─────────────────────────────────────────────────

    def test_hypertrophy_progression_status(self):
        _inject_model(UID, _make_custom_assets(avg_reps=12.0, max_weight=135.0, pred_1rm=500.0))
        assert "PROGRESSION" in self._post().json()["status"]

    def test_hypertrophy_progression_increases_weight_by_2_5(self):
        _inject_model(UID, _make_custom_assets(avg_reps=12.0, max_weight=135.0, pred_1rm=500.0))
        assert self._post().json()["target_weight"] == pytest.approx(137.5)

    # STRENGTH PROGRESSION ────────────────────────────────────────────────────

    def test_strength_progression_status(self):
        _inject_model(UID, _make_custom_assets(avg_reps=6.0, max_weight=135.0, pred_1rm=500.0))
        assert "PROGRESSION" in self._post(mode="strength").json()["status"]

    def test_strength_progression_increases_weight_by_5(self):
        _inject_model(UID, _make_custom_assets(avg_reps=6.0, max_weight=135.0, pred_1rm=500.0))
        assert self._post(mode="strength").json()["target_weight"] == pytest.approx(140.0)

    # HYPERTROPHY STABILIZATION ───────────────────────────────────────────────

    def test_hypertrophy_stabilization_status(self):
        _inject_model(UID, _make_custom_assets(avg_reps=5.0, max_weight=135.0, pred_1rm=500.0))
        assert "STABILIZATION" in self._post().json()["status"]

    def test_hypertrophy_stabilization_holds_weight(self):
        _inject_model(UID, _make_custom_assets(avg_reps=5.0, max_weight=135.0, pred_1rm=500.0))
        assert self._post().json()["target_weight"] == pytest.approx(135.0)

    def test_hypertrophy_stabilization_sets_reps_to_10(self):
        _inject_model(UID, _make_custom_assets(avg_reps=5.0, max_weight=135.0, pred_1rm=500.0))
        assert self._post().json()["target_reps"] == 10

    # STRENGTH STABILIZATION ──────────────────────────────────────────────────

    def test_strength_stabilization_status(self):
        _inject_model(UID, _make_custom_assets(avg_reps=2.0, max_weight=135.0, pred_1rm=500.0))
        assert "STABILIZATION" in self._post(mode="strength").json()["status"]

    # VOLUME ──────────────────────────────────────────────────────────────────

    def test_hypertrophy_volume_status(self):
        _inject_model(UID, _make_custom_assets(avg_reps=9.0, max_weight=135.0, pred_1rm=500.0))
        assert "VOLUME" in self._post().json()["status"]

    def test_hypertrophy_volume_sets_target_reps_to_12(self):
        _inject_model(UID, _make_custom_assets(avg_reps=9.0, max_weight=135.0, pred_1rm=500.0))
        assert self._post().json()["target_reps"] == 12

    # AI OVERRIDE ─────────────────────────────────────────────────────────────

    def test_ai_override_status_when_pred_1rm_too_low(self):
        _inject_model(UID, _make_custom_assets(avg_reps=8.0, max_weight=135.0, pred_1rm=100.0))
        assert "AI OVERRIDE" in self._post().json()["status"]

    def test_ai_override_reduces_target_weight_below_last_weight(self):
        _inject_model(UID, _make_custom_assets(avg_reps=8.0, max_weight=200.0, pred_1rm=100.0))
        assert self._post().json()["target_weight"] < 200.0

    # NEW EXERCISE ────────────────────────────────────────────────────────────

    def test_new_exercise_status_when_max_weight_is_zero(self):
        _inject_model(UID, _make_custom_assets(avg_reps=0.0, max_weight=0.0, pred_1rm=150.0))
        assert self._post().json()["status"] == "NEW EXERCISE: Baseline"

    def test_new_exercise_target_weight_derived_from_pred_1rm(self):
        _inject_model(UID, _make_custom_assets(avg_reps=0.0, max_weight=0.0, pred_1rm=150.0))
        assert self._post().json()["target_weight"] > 0.0

    # Insight strings ─────────────────────────────────────────────────────────

    def test_fatigue_insight_when_had_fatigue(self):
        _inject_model(UID, _make_custom_assets(had_fatigue=1, pred_1rm=300.0))
        insight = self._post().json()["notes_insight"].lower()
        assert "fatigue" in insight or "grip" in insight

    def test_plateau_insight_when_plateau_detected(self):
        _inject_model(UID, _make_custom_assets(pred_1rm=300.0, summary_rows=_plateau_rows()))
        insight = self._post().json()["notes_insight"]
        assert "1RM gain" in insight or "4 sessions" in insight

    def test_declining_momentum_insight(self):
        rows = {
            "Exercise": ["Bench Press"] * 3,
            "Category": ["Chest"] * 3,
            "Session_Max_1RM": [150.0, 145.0, 140.0],
            "Days_Since_Last": [7.0] * 3,
            "Max_Weight": [135.0] * 3,
            "Avg_Reps": [9.0] * 3,
            "Volume_Load": [3645.0] * 3,
            "Rep_Consistency": [0.9] * 3,
            "Had_Form_Issue": [0] * 3,
            "Had_Fatigue": [0] * 3,
        }
        _inject_model(UID, _make_custom_assets(pred_1rm=500.0, summary_rows=rows))
        assert "declin" in self._post().json()["notes_insight"].lower()

    def test_rising_momentum_insight(self):
        rows = {
            "Exercise": ["Bench Press"] * 3,
            "Category": ["Chest"] * 3,
            "Session_Max_1RM": [100.0, 110.0, 120.0],
            "Days_Since_Last": [7.0] * 3,
            "Max_Weight": [100.0] * 3,
            "Avg_Reps": [9.0] * 3,
            "Volume_Load": [2700.0] * 3,
            "Rep_Consistency": [0.9] * 3,
            "Had_Form_Issue": [0] * 3,
            "Had_Fatigue": [0] * 3,
        }
        _inject_model(UID, _make_custom_assets(pred_1rm=500.0, summary_rows=rows))
        insight = self._post().json()["notes_insight"].lower()
        assert "momentum" in insight or "climbing" in insight

    def test_two_session_momentum_does_not_crash(self):
        rows = {
            "Exercise": ["Bench Press"] * 2,
            "Category": ["Chest"] * 2,
            "Session_Max_1RM": [140.0, 145.0],
            "Days_Since_Last": [7.0] * 2,
            "Max_Weight": [135.0] * 2,
            "Avg_Reps": [9.0] * 2,
            "Volume_Load": [3645.0] * 2,
            "Rep_Consistency": [0.9] * 2,
            "Had_Form_Issue": [0] * 2,
            "Had_Fatigue": [0] * 2,
        }
        _inject_model(UID, _make_custom_assets(pred_1rm=500.0, summary_rows=rows))
        assert self._post().status_code == 200

    def test_required_1rm_always_present_and_is_float(self):
        _inject_model(UID, _make_model_assets())
        body = self._post().json()
        assert "required_1rm" in body
        assert isinstance(body["required_1rm"], float)
