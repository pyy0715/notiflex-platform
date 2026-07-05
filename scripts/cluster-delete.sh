#!/usr/bin/env bash
# Delete the notiflex GKE cluster and its node VMs / disks.
# BLAST RADIUS: removes the cluster and all workloads running on it. ArgoCD,
# PVCs, and any in-cluster state are destroyed. No data is recoverable.
#
# Usage:
#   ./scripts/cluster-delete.sh                  # interactive prompt (default)
#   ./scripts/cluster-delete.sh --yes            # skip confirmation
#   CLUSTER_NAME=notiflex ZONE=us-central1-a ./scripts/cluster-delete.sh
set -euo pipefail

CLUSTER_NAME="${CLUSTER_NAME:-notiflex}"
ZONE="${ZONE:-us-central1-a}"
FORCE=0

for arg in "$@"; do
  case "$arg" in
    --yes|-y) FORCE=1 ;;
    *) echo "Unknown arg: $arg" >&2; exit 2 ;;
  esac
done

echo "==> Checking cluster '${CLUSTER_NAME}' in ${ZONE}..."
if ! gcloud container clusters describe "${CLUSTER_NAME}" --zone "${ZONE}" >/dev/null 2>&1; then
  echo "    Cluster '${CLUSTER_NAME}' not found. Nothing to delete."
  exit 0
fi

echo "    Cluster found. This will delete the cluster, its node VMs, and disks."
echo "    All in-cluster workloads and PVC data will be lost."
if [ "$FORCE" -ne 1 ]; then
  read -r -p "    Type the cluster name to confirm deletion: " CONFIRM
  if [ "$CONFIRM" != "${CLUSTER_NAME}" ]; then
    echo "    Aborted: name did not match." >&2
    exit 1
  fi
fi

echo "==> Deleting cluster '${CLUSTER_NAME}'..."
gcloud container clusters delete "${CLUSTER_NAME}" --zone "${ZONE}" --quiet --async

echo
echo "==> Deletion triggered (running asynchronously)."
echo "    Monitor: gcloud container operations list --zone ${ZONE} --filter='status=RUNNING'"
echo "    Verify:  gcloud container clusters describe ${CLUSTER_NAME} --zone ${ZONE}  (should error once gone)"
