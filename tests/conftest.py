"""Shared pytest fixtures and module-level mocks for the backend test suite.

Firebase Admin and GCS are mocked here — before any test module imports api —
so api.py's module-level initialisation runs against fakes instead of real
cloud services. pipeline is NOT mocked so test_pipeline.py gets the real module.
"""

import sys
from unittest.mock import MagicMock

_firebase_mock = MagicMock()
_firebase_mock.get_app.return_value = MagicMock()  # prevent ValueError branch

_firestore_mock = MagicMock()
_firestore_mock.SERVER_TIMESTAMP = "SERVER_TIMESTAMP"

_gcp_firestore_mock = MagicMock()

_gcs_mock = MagicMock()
_gcs_mock.Client.return_value = MagicMock()

sys.modules.setdefault("firebase_admin", _firebase_mock)
sys.modules.setdefault("firebase_admin.auth", MagicMock())
sys.modules.setdefault("firebase_admin.firestore", _firestore_mock)
sys.modules.setdefault("google.cloud.storage", _gcs_mock)
sys.modules.setdefault("google.cloud.firestore", _gcp_firestore_mock)
# pipeline is NOT mocked here so test_pipeline.py imports the real module.
# test_api.py patches api.run_pipeline locally per test.
