#!/usr/bin/env bash
# Build the notiflex-api container image for Artifact Registry.
# Tags: <registry>/<image>:<git-sha> (immutable) and :latest (dev convenience).
#
# Usage:
#   ./scripts/image-build.sh
#   IMAGE_NAME=notiflex-api ./scripts/image-build.sh
#
# Env overrides:
#   REGISTRY     — full AR host/path (default: us-central1-docker.pkg.dev/bubbly-subject-501015-t9/containers)
#   IMAGE_NAME   — image name (default: notiflex-api)
#   SOURCE_DIR   — build context dir (default: ./app)
set -euo pipefail

REGISTRY="${REGISTRY:-us-central1-docker.pkg.dev/bubbly-subject-501015-t9/containers}"
IMAGE_NAME="${IMAGE_NAME:-notiflex-api}"
SOURCE_DIR="${SOURCE_DIR:-./app}"
FULL_IMAGE="${REGISTRY}/${IMAGE_NAME}"

# Determine immutable tag from git short SHA. Require a clean-ish commit:
# fall back to 'dev' if not in a git repo.
SHA="$(git -C "$(dirname "$0")/.." rev-parse --short=7 HEAD 2>/dev/null || echo dev)"
VERSION="$(cat "$(dirname "$0")/../VERSION" 2>/dev/null || echo dev)"
TAG_IMMUTABLE="${FULL_IMAGE}:${SHA}"
TAG_LATEST="${FULL_IMAGE}:latest"

echo "==> Building ${IMAGE_NAME}"
echo "    context: ${SOURCE_DIR}"
echo "    version: ${VERSION}  (from VERSION file)"
echo "    tags:    :${SHA}  (immutable)"
echo "             :latest  (dev pointer)"

docker build \
  --platform linux/amd64 \
  --build-arg VERSION="${VERSION}" \
  --build-arg COMMIT="${SHA}" \
  --tag "${TAG_IMMUTABLE}" \
  --tag "${TAG_LATEST}" \
  "${SOURCE_DIR}"

echo
echo "==> Built images:"
docker images "${FULL_IMAGE}" --format "table {{.Repository}}:{{.Tag}}\t{{.ID}}\t{{.Size}}"

echo
echo "Immutable tag: ${TAG_IMMUTABLE}"
