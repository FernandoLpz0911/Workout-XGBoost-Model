"""Tests for api.py FastAPI endpoints.

External dependencies (Firebase Admin, GCS, pipeline) are mocked in
conftest.py so no cloud credentials are needed.
"""

import time
from datetime import datetime, timedelta, timezone
from unittest.mock import MagicMock, patch

import pytest
from fastapi.testclient import TestClient

import api
from api import (
    _model_cache,
    _model_loaded_at,
    _premium_cache,
    app,
    get_uid,
    require_premium,
)

# Override auth dependencies so every request authenticates as "uid_test"
# without hitting Firebase.
app.dependency_overrides[get_uid] = lambda: "uid_test"
app.dependency_overrides[require_premium] = lambda: "uid_test"

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
    _premium_cache.clear()
    yield
    _model_cache.clear()
    _model_loaded_at.clear()
    _premium_cache.clear()


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


class TestRequirePremium:
    def _make_doc(self, status="active", expiry_offset_days=None):
        doc = MagicMock()
        doc.exists = True
        data = {"subscriptionStatus": status}
        if expiry_offset_days is not None:
            expiry_dt = datetime.now(timezone.utc) + timedelta(days=expiry_offset_days)
            ts = MagicMock()
            ts.astimezone.return_value = expiry_dt
            data["subscriptionExpiry"] = ts
        doc.to_dict.return_value = data
        return doc

    def _call(self, doc):
        db = MagicMock()
        db.collection.return_value.document.return_value.get.return_value = doc
        from fastapi import HTTPException
        from api import require_premium
        with patch.object(api, "admin_firestore") as mock_fs:
            mock_fs.client.return_value = db
            try:
                return require_premium(uid="uid_exp_test")
            except HTTPException as exc:
                return exc

    def test_active_with_future_expiry_returns_uid(self):
        doc = self._make_doc(status="active", expiry_offset_days=10)
        result = self._call(doc)
        assert result == "uid_exp_test"

    def test_active_with_past_expiry_raises_403(self):
        from fastapi import HTTPException
        doc = self._make_doc(status="active", expiry_offset_days=-1)
        result = self._call(doc)
        assert isinstance(result, HTTPException)
        assert result.status_code == 403

    def test_active_with_no_expiry_field_returns_uid(self):
        doc = self._make_doc(status="active", expiry_offset_days=None)
        result = self._call(doc)
        assert result == "uid_exp_test"

    def test_not_active_raises_403(self):
        from fastapi import HTTPException
        doc = self._make_doc(status="none")
        result = self._call(doc)
        assert isinstance(result, HTTPException)
        assert result.status_code == 403


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

    def test_evicts_premium_cache(self):
        _premium_cache[UID] = (True, time.monotonic() + 60)
        client.delete("/delete-user-data")
        assert UID not in _premium_cache
