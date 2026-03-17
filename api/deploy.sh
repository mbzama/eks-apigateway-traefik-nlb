#!/usr/bin/env bash
set -euo pipefail

# ── Configuration ─────────────────────────────────────────────────────────────
DOCKERHUB_USERNAME="${DOCKERHUB_USERNAME:-}"
IMAGE_NAME="${IMAGE_NAME:-mock-api}"
IMAGE_TAG="${IMAGE_TAG:-latest}"

# ── Validation ────────────────────────────────────────────────────────────────
if [[ -z "$DOCKERHUB_USERNAME" ]]; then
  echo "ERROR: DOCKERHUB_USERNAME is not set." >&2
  exit 1
fi

FULL_IMAGE="$DOCKERHUB_USERNAME/$IMAGE_NAME"

# ── Build ─────────────────────────────────────────────────────────────────────
echo "Building image: $FULL_IMAGE:$IMAGE_TAG ..."
docker build --target production \
  -t "$FULL_IMAGE:$IMAGE_TAG" \
  -t "$FULL_IMAGE:latest" \
  .

# ── Push ──────────────────────────────────────────────────────────────────────
echo "Pushing $FULL_IMAGE:$IMAGE_TAG ..."
docker push "$FULL_IMAGE:$IMAGE_TAG"

echo "Pushing $FULL_IMAGE:latest ..."
docker push "$FULL_IMAGE:latest"

echo "Done. Image pushed to Docker Hub: $FULL_IMAGE:$IMAGE_TAG"
