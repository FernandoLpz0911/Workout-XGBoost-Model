"""Firebase Cloud Functions for the Workout ML project.

Deploy with:
    firebase deploy --only functions

Requires the Cloud Function's service account to have the
``roles/storage.objectAdmin`` IAM role on the GCS bucket.
"""

import os

import firebase_admin
from firebase_admin import storage
from firebase_functions import auth_fn

firebase_admin.initialize_app()

_GCS_BUCKET = os.getenv("GCS_BUCKET", "workout-ml-user-models")


@auth_fn.on_user_deleted()
def on_user_deleted(event: auth_fn.AuthEvent) -> None:
    """Delete all GCS model artifacts when a Firebase user account is removed.

    Prevents orphaned ``user_models/{uid}/`` objects from accumulating in GCS
    after account deletion.
    """
    uid = event.data.uid
    bucket = storage.bucket(_GCS_BUCKET)
    blobs = list(bucket.list_blobs(prefix=f"user_models/{uid}/"))
    for blob in blobs:
        blob.delete()
    if blobs:
        print(f"Deleted {len(blobs)} GCS objects for uid={uid}")
