"""Tests for api.py FastAPI endpoints.

No cloud dependencies — api.py is fully local. Tests patch disk I/O where
needed so no real files are written during the test run.
"""

import io
import os
import shutil
import tempfile
import time
from unittest.mock import MagicMock, patch

import joblib
import pandas as pd
import pytest
from fastapi.testclient import TestClient

import api
from api import _model_cache, _training_in_progress, app, get_uid

# Override auth so every request provides UID without a real header.
app.dependency_overrides[get_uid] = lambda: "uid_test"

client = TestClient(app)

UID = "uid_test"


# ── Helpers ───────────────────────────────────────────────────────────────────


def _make_model_assets():
    """Return a minimal (model, feature_cols, summary) tuple."""
    model = MagicMock()
    model.predict.return_value = [150.0]
    feature_cols = [
        "Days_Since_Last",
        "Previous_1RM",
        "Last_Avg_Reps",
        "Prev_Volume_Load",
        "Prev_Rep_Consistency",
        "Prev_Form_Issue",
        "Prev_Fatigue",
        "RM_Momentum",
        "Exercise_Bench Press",
        "Category_Chest",
    ]
    summary = pd.DataFrame(
        {
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
        }
    )
    return model, feature_cols, summary


def _inject_model(uid, assets):
    """Inject model assets directly into the in-process cache."""
    _model_cache[uid] = assets


@pytest.fixture(autouse=True)
def clear_state():
    """Reset in-process cache and training set between tests."""
    _model_cache.clear()
    _training_in_progress.clear()
    yield
    _model_cache.clear()
    _training_in_progress.clear()


# ── Auth ──────────────────────────────────────────────────────────────────────


class TestAuthDependency:
    def test_missing_header_raises_401(self):
        with pytest.raises(Exception) as exc_info:
            get_uid(None)
        assert exc_info.value.status_code == 401
        assert "Missing" in exc_info.value.detail

    def test_header_present_returns_uid(self):
        assert get_uid("alice") == "alice"


# ── /train ────────────────────────────────────────────────────────────────────


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
                files={"file": ("data.csv", b"Date,Exercise\n2026-01-01,Squat", "text/csv")},
            )
        assert response.status_code == 200
        assert "Training started" in response.json()["message"]

    def test_rejects_oversized_csv(self):
        oversized = b"x" * (api._MAX_CSV_BYTES + 1)
        with patch.object(api, "_run_train"):
            response = client.post(
                "/train",
                files={"file": ("big.csv", oversized, "text/csv")},
            )
        assert response.status_code == 413
        assert "too large" in response.json()["detail"].lower()

    def test_returns_409_when_training_in_progress(self):
        _training_in_progress.add(UID)
        response = client.post(
            "/train",
            files={"file": ("data.csv", b"a,b\n1,2", "text/csv")},
        )
        assert response.status_code == 409

    def test_oversized_releases_slot(self):
        """Slot must be released even when the size check fails."""
        oversized = b"x" * (api._MAX_CSV_BYTES + 1)
        with patch.object(api, "_run_train"):
            client.post("/train", files={"file": ("big.csv", oversized, "text/csv")})
        assert UID not in _training_in_progress

    def test_file_read_error_releases_slot_and_returns_400(self):
        import starlette.datastructures

        original = starlette.datastructures.UploadFile.read

        async def _fail(self, size=-1):
            raise IOError("disk error")

        starlette.datastructures.UploadFile.read = _fail
        try:
            response = client.post(
                "/train",
                files={"file": ("d.csv", b"a,b\n1,2", "text/csv")},
            )
            assert response.status_code == 400
            assert UID not in _training_in_progress
        finally:
            starlette.datastructures.UploadFile.read = original


# ── /exercises ────────────────────────────────────────────────────────────────


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

    def test_returns_500_when_summary_missing_columns(self):
        model, feature_cols, _ = _make_model_assets()
        _inject_model(UID, (model, feature_cols, pd.DataFrame({"WrongCol": [1]})))
        assert client.get("/exercises").status_code == 500


# ── /recommend ────────────────────────────────────────────────────────────────


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
        body = client.post(
            "/recommend",
            json={"exercise": "Bench Press", "category": "Chest"},
        ).json()
        assert isinstance(body["target_reps"], int)
        assert isinstance(body["target_weight"], float)
        assert isinstance(body["predicted_1rm"], float)
        assert isinstance(body["status"], str)
        assert isinstance(body["notes_insight"], str)

    def test_strength_mode_accepted(self):
        _inject_model(UID, _make_model_assets())
        body = client.post(
            "/recommend",
            json={"exercise": "Bench Press", "category": "Chest", "mode": "strength"},
        ).json()
        valid = {"STRENGTH", "FORM", "DELOAD", "AI OVERRIDE"}
        assert any(v in body["status"] for v in valid)

    def test_unknown_mode_falls_back_to_hypertrophy(self):
        _inject_model(UID, _make_model_assets())
        body = client.post(
            "/recommend",
            json={"exercise": "Bench Press", "category": "Chest", "mode": "invalid"},
        ).json()
        valid = {"HYPERTROPHY", "FORM", "DELOAD", "AI OVERRIDE"}
        assert any(v in body["status"] for v in valid)


# ── Model cache ───────────────────────────────────────────────────────────────


class TestModelCache:
    def test_evict_removes_oldest_entry(self):
        from api import _CACHE_MAX, _evict_model_cache

        for i in range(_CACHE_MAX):
            _model_cache[f"uid_{i}"] = (MagicMock(), [], MagicMock())

        assert len(_model_cache) == _CACHE_MAX
        _evict_model_cache()
        assert len(_model_cache) == _CACHE_MAX - 1
        assert "uid_0" not in _model_cache

    def test_evict_no_op_when_under_limit(self):
        from api import _evict_model_cache

        _model_cache["only_one"] = (MagicMock(), [], MagicMock())
        _evict_model_cache()
        assert "only_one" in _model_cache


# ── Training slot ─────────────────────────────────────────────────────────────


class TestTrainingSlot:
    def test_claim_returns_true_when_free(self):
        from api import _claim_training_slot

        assert _claim_training_slot("u1") is True
        assert "u1" in _training_in_progress

    def test_claim_returns_false_when_taken(self):
        from api import _claim_training_slot

        _training_in_progress.add("u2")
        assert _claim_training_slot("u2") is False

    def test_release_removes_uid(self):
        from api import _release_training_slot

        _training_in_progress.add("u3")
        _release_training_slot("u3")
        assert "u3" not in _training_in_progress

    def test_release_no_op_when_not_present(self):
        from api import _release_training_slot

        _release_training_slot("ghost")  # must not raise


# ── Disk save / load ──────────────────────────────────────────────────────────


class TestSaveUserModel:
    def test_saves_to_disk_and_warms_cache(self):
        from api import _save_user_model

        tmp = tempfile.mkdtemp()
        try:
            with patch.object(api, "_MODEL_DIR", tmp):
                model = {"w": 1.0}
                fc = ["Days_Since_Last"]
                summary = pd.DataFrame({"Exercise": ["X"], "Category": ["Y"]})
                _save_user_model("uid_s", model, fc, summary)

            assert "uid_s" in _model_cache
            assert os.path.exists(os.path.join(tmp, "uid_s", "xgb_model.joblib"))
            assert os.path.exists(os.path.join(tmp, "uid_s", "feature_cols.joblib"))
            assert os.path.exists(os.path.join(tmp, "uid_s", "workout_summary.csv"))
        finally:
            shutil.rmtree(tmp, ignore_errors=True)


class TestLoadUserModel:
    def test_returns_cached_value_on_hit(self):
        assets = _make_model_assets()
        _inject_model("uid_c", assets)
        from api import _load_user_model

        assert _load_user_model("uid_c") is assets

    def test_loads_from_disk_on_cache_miss(self):
        from api import _load_user_model

        tmp = tempfile.mkdtemp()
        try:
            uid = "uid_disk"
            path = os.path.join(tmp, uid)
            os.makedirs(path)

            model = {"w": 2.0}
            fc = ["Days_Since_Last"]
            summary = pd.DataFrame({"Date": ["2026-01-01"], "Exercise": ["X"]})
            joblib.dump(model, os.path.join(path, "xgb_model.joblib"))
            joblib.dump(fc, os.path.join(path, "feature_cols.joblib"))
            summary.to_csv(os.path.join(path, "workout_summary.csv"), index=False)

            with patch.object(api, "_MODEL_DIR", tmp):
                result = _load_user_model(uid)

            assert result is not None
            loaded_model, loaded_fc, _ = result
            assert loaded_model == model
            assert loaded_fc == fc
            assert uid in _model_cache
        finally:
            shutil.rmtree(tmp, ignore_errors=True)

    def test_returns_none_when_no_model_on_disk(self):
        from api import _load_user_model

        with patch.object(api, "_MODEL_DIR", "/nonexistent/path"):
            assert _load_user_model("uid_missing") is None


# ── _run_train ────────────────────────────────────────────────────────────────


class TestRunTrainDirect:
    def _summary(self):
        return pd.DataFrame({"Exercise": ["X"], "Category": ["Y"]})

    def test_success_saves_model_and_releases_slot(self):
        from api import _run_train

        _training_in_progress.add("uid_t")
        with patch("api.run_pipeline", return_value=({"m": 1}, ["col"], self._summary())), \
             patch("api._save_user_model"):
            _run_train("uid_t", b"a,b\n1,2")

        assert "uid_t" not in _training_in_progress

    def test_failure_releases_slot(self):
        from api import _run_train

        _training_in_progress.add("uid_tf")
        with patch("api.run_pipeline", side_effect=ValueError("bad csv")):
            _run_train("uid_tf", b"garbage")

        assert "uid_tf" not in _training_in_progress


# ── /delete-user-data ────────────────────────────────────────────────────────


class TestDeleteUserDataEndpoint:
    def test_returns_200(self):
        response = client.delete("/delete-user-data")
        assert response.status_code == 200
        assert "deleted" in response.json()["message"].lower()

    def test_evicts_model_cache(self):
        _inject_model(UID, _make_model_assets())
        client.delete("/delete-user-data")
        assert UID not in _model_cache

    def test_deletes_model_directory(self):
        tmp = tempfile.mkdtemp()
        uid_dir = os.path.join(tmp, UID)
        os.makedirs(uid_dir)
        try:
            with patch.object(api, "_MODEL_DIR", tmp):
                client.delete("/delete-user-data")
            assert not os.path.exists(uid_dir)
        finally:
            shutil.rmtree(tmp, ignore_errors=True)

    def test_no_error_when_directory_missing(self):
        with patch.object(api, "_MODEL_DIR", "/nonexistent/path"):
            assert client.delete("/delete-user-data").status_code == 200


# ── /recommend decision-tree tests ───────────────────────────────────────────

_DEFAULT_FEATURE_COLS = [
    "Days_Since_Last",
    "Previous_1RM",
    "Last_Avg_Reps",
    "Prev_Volume_Load",
    "Prev_Rep_Consistency",
    "Prev_Form_Issue",
    "Prev_Fatigue",
    "RM_Momentum",
    "Exercise_Bench Press",
    "Category_Chest",
]


def _make_custom_assets(
    avg_reps=8.0,
    max_weight=135.0,
    had_form=0,
    had_fatigue=0,
    pred_1rm=300.0,
    summary_rows=None,
):
    model = MagicMock()
    model.predict.return_value = [pred_1rm]
    if summary_rows is None:
        summary_rows = pd.DataFrame(
            {
                "Exercise": ["Bench Press"],
                "Category": ["Chest"],
                "Session_Max_1RM": [145.0],
                "Days_Since_Last": [7.0],
                "Max_Weight": [max_weight],
                "Avg_Reps": [avg_reps],
                "Volume_Load": [3240.0],
                "Rep_Consistency": [0.9],
                "Had_Form_Issue": [had_form],
                "Had_Fatigue": [had_fatigue],
            }
        )
    return model, _DEFAULT_FEATURE_COLS, summary_rows


def _plateau_rows():
    return pd.DataFrame(
        {
            "Exercise": ["Bench Press"] * 4,
            "Category": ["Chest"] * 4,
            "Session_Max_1RM": [145.0, 145.0, 145.5, 145.0],
            "Days_Since_Last": [7.0] * 4,
            "Max_Weight": [135.0] * 4,
            "Avg_Reps": [8.0] * 4,
            "Volume_Load": [3240.0] * 4,
            "Rep_Consistency": [0.9] * 4,
            "Had_Form_Issue": [0] * 4,
            "Had_Fatigue": [0] * 4,
        }
    )


class TestRecommendLogic:
    def _post(self, mode="hypertrophy"):
        return client.post(
            "/recommend",
            json={"exercise": "Bench Press", "category": "Chest", "mode": mode},
        )

    # FORM FOCUS

    def test_form_focus_status(self):
        _inject_model(UID, _make_custom_assets(had_form=1))
        assert "FORM FOCUS" in self._post().json()["status"]

    def test_form_focus_holds_weight(self):
        _inject_model(UID, _make_custom_assets(had_form=1, max_weight=135.0))
        assert self._post().json()["target_weight"] == 135.0

    def test_form_focus_sets_hypertrophy_default_reps(self):
        _inject_model(UID, _make_custom_assets(had_form=1))
        assert self._post().json()["target_reps"] == 10

    def test_form_focus_insight_mentions_technique(self):
        _inject_model(UID, _make_custom_assets(had_form=1))
        assert "technique" in self._post().json()["notes_insight"].lower()

    # DELOAD

    def test_deload_status_when_plateau(self):
        _inject_model(UID, _make_custom_assets(summary_rows=_plateau_rows()))
        assert "DELOAD" in self._post().json()["status"]

    def test_deload_sets_reps_to_15(self):
        _inject_model(UID, _make_custom_assets(summary_rows=_plateau_rows()))
        assert self._post().json()["target_reps"] == 15

    def test_deload_reduces_weight_to_60_percent(self):
        _inject_model(UID, _make_custom_assets(summary_rows=_plateau_rows()))
        body = self._post().json()
        assert body["target_weight"] == pytest.approx(round(135.0 * 0.6 / 2.5) * 2.5)

    # PROGRESSION

    def test_hypertrophy_progression_status(self):
        _inject_model(UID, _make_custom_assets(avg_reps=12.0))
        assert "HYPERTROPHY PROGRESSION" in self._post().json()["status"]

    def test_hypertrophy_progression_increases_weight_by_2_5(self):
        _inject_model(UID, _make_custom_assets(avg_reps=12.0, max_weight=135.0))
        assert self._post().json()["target_weight"] == pytest.approx(137.5)

    def test_strength_progression_status(self):
        _inject_model(UID, _make_custom_assets(avg_reps=6.0, max_weight=135.0))
        assert "STRENGTH PROGRESSION" in self._post("strength").json()["status"]

    def test_strength_progression_increases_weight_by_5(self):
        _inject_model(UID, _make_custom_assets(avg_reps=6.0, max_weight=135.0))
        assert self._post("strength").json()["target_weight"] == pytest.approx(140.0)

    # STABILIZATION

    def test_hypertrophy_stabilization_status(self):
        _inject_model(UID, _make_custom_assets(avg_reps=5.0))
        assert "HYPERTROPHY STABILIZATION" in self._post().json()["status"]

    def test_hypertrophy_stabilization_holds_weight(self):
        _inject_model(UID, _make_custom_assets(avg_reps=5.0, max_weight=135.0))
        assert self._post().json()["target_weight"] == pytest.approx(135.0)

    def test_hypertrophy_stabilization_sets_reps_to_10(self):
        _inject_model(UID, _make_custom_assets(avg_reps=5.0))
        assert self._post().json()["target_reps"] == 10

    def test_strength_stabilization_status(self):
        _inject_model(UID, _make_custom_assets(avg_reps=2.0, max_weight=135.0))
        assert "STRENGTH STABILIZATION" in self._post("strength").json()["status"]

    # VOLUME

    def test_hypertrophy_volume_status(self):
        _inject_model(UID, _make_custom_assets(avg_reps=8.0))
        assert "HYPERTROPHY VOLUME" in self._post().json()["status"]

    def test_hypertrophy_volume_sets_target_reps_to_12(self):
        _inject_model(UID, _make_custom_assets(avg_reps=8.0))
        assert self._post().json()["target_reps"] == 12

    # AI OVERRIDE

    def test_ai_override_status_when_pred_1rm_too_low(self):
        _inject_model(UID, _make_custom_assets(avg_reps=8.0, max_weight=135.0, pred_1rm=50.0))
        assert "AI OVERRIDE" in self._post().json()["status"]

    def test_ai_override_reduces_target_weight_below_last_weight(self):
        _inject_model(UID, _make_custom_assets(avg_reps=8.0, max_weight=135.0, pred_1rm=50.0))
        assert self._post().json()["target_weight"] < 135.0

    # NEW EXERCISE

    def test_new_exercise_status_when_max_weight_is_zero(self):
        _inject_model(UID, _make_custom_assets(max_weight=0.0, pred_1rm=200.0))
        assert "NEW EXERCISE" in self._post().json()["status"]

    def test_new_exercise_target_weight_derived_from_pred_1rm(self):
        _inject_model(UID, _make_custom_assets(max_weight=0.0, pred_1rm=200.0))
        body = self._post().json()
        assert body["target_weight"] > 0
        assert body["target_reps"] == 8

    # Insights

    def test_fatigue_insight_when_had_fatigue(self):
        _inject_model(UID, _make_custom_assets(had_fatigue=1))
        assert "fatigue" in self._post().json()["notes_insight"].lower()

    def test_plateau_insight_when_plateau_detected(self):
        _inject_model(UID, _make_custom_assets(summary_rows=_plateau_rows()))
        assert "4 sessions" in self._post().json()["notes_insight"]

    def test_declining_momentum_insight(self):
        rows = pd.DataFrame(
            {
                "Exercise": ["Bench Press"] * 3,
                "Category": ["Chest"] * 3,
                "Session_Max_1RM": [150.0, 145.0, 140.0],
                "Days_Since_Last": [7.0] * 3,
                "Max_Weight": [135.0] * 3,
                "Avg_Reps": [8.0] * 3,
                "Volume_Load": [3240.0] * 3,
                "Rep_Consistency": [0.9] * 3,
                "Had_Form_Issue": [0] * 3,
                "Had_Fatigue": [0] * 3,
            }
        )
        _inject_model(UID, _make_custom_assets(summary_rows=rows))
        assert "declining" in self._post().json()["notes_insight"].lower()

    def test_rising_momentum_insight(self):
        rows = pd.DataFrame(
            {
                "Exercise": ["Bench Press"] * 3,
                "Category": ["Chest"] * 3,
                "Session_Max_1RM": [140.0, 148.0, 156.0],
                "Days_Since_Last": [7.0] * 3,
                "Max_Weight": [135.0] * 3,
                "Avg_Reps": [8.0] * 3,
                "Volume_Load": [3240.0] * 3,
                "Rep_Consistency": [0.9] * 3,
                "Had_Form_Issue": [0] * 3,
                "Had_Fatigue": [0] * 3,
            }
        )
        _inject_model(UID, _make_custom_assets(summary_rows=rows))
        assert "momentum" in self._post().json()["notes_insight"].lower()

    def test_two_session_momentum_does_not_crash(self):
        rows = pd.DataFrame(
            {
                "Exercise": ["Bench Press"] * 2,
                "Category": ["Chest"] * 2,
                "Session_Max_1RM": [140.0, 145.0],
                "Days_Since_Last": [7.0] * 2,
                "Max_Weight": [135.0] * 2,
                "Avg_Reps": [8.0] * 2,
                "Volume_Load": [3240.0] * 2,
                "Rep_Consistency": [0.9] * 2,
                "Had_Form_Issue": [0] * 2,
                "Had_Fatigue": [0] * 2,
            }
        )
        _inject_model(UID, _make_custom_assets(summary_rows=rows))
        assert self._post().status_code == 200

    def test_required_1rm_always_present_and_is_float(self):
        _inject_model(UID, _make_model_assets())
        body = self._post().json()
        assert "required_1rm" in body
        assert isinstance(body["required_1rm"], float)
