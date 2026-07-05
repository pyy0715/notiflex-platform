#!/usr/bin/env bash
# Build + push the notiflex-api image to Artifact Registry.
# Pushes both the immutable <sha> tag and the dev :latest tag.
#
# Usage:
#   ./scripts/image-push.sh
#   IMAGE_NAME=notiflex-api ./scripts/image-push.sh
#
# Prereq: `gcloud auth configure-docker us-central1-docker.pkg.dev` (already done once).
set -euo pipefail

REGISTRY="${REGISTRY:-us-central1-docker.pkg.dev/bubbly-subject-501015-t9/containers}"
IMAGE_NAME="${IMAGE_NAME:-notiflex-api}"
FULL_IMAGE="${REGISTRY}/${IMAGE_NAME}"

# Step 1: build first (delegates to image-build.sh).
"$(dirname "$0")"/image-build.sh

echo
echo "==> Authenticating docker to ${REGISTRY}..."
gcloud auth configure-docker "${REGISTRY%%/*}" --quiet >/dev/null

echo "==> Pushing immutable + latest tags..."
docker push --all-tags "${FULL_IMAGE}"

echo
echo "==> Images now in AR:"
gcloud artifacts docker images list "${FULL_IMAGE}" \
  --format="table(package:label=IMAGE, tags:label=TAG, version:label=DIGEST, create_time:label=CREATED)" \
  --include-tags

echo
echo "Done. Use this reference in manifests:"
SHA="$(git -C "$(dirname "$0")/.." rev-parse --short=7 HEAD 2>/dev/null || echo dev)"
echo "  ${FULL_IMAGE}:${SHA}"
