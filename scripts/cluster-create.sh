#!/usr/bin/env bash
# Create the notiflex GKE cluster (Standard, Spot, zonal).
# Idempotent-ish: if the cluster already exists, exits early.
#
# Usage:
#   ./scripts/cluster-create.sh                 # defaults
#   CLUSTER_NAME=notiflex ZONE=us-central1-a ./scripts/cluster-create.sh
#
# Env overrides:
#   CLUSTER_NAME, ZONE, MACHINE_TYPE, NUM_NODES, MIN_NODES, MAX_NODES, DISK_SIZE
set -euo pipefail

CLUSTER_NAME="${CLUSTER_NAME:-notiflex}"
ZONE="${ZONE:-us-central1-a}"
MACHINE_TYPE="${MACHINE_TYPE:-e2-medium}"
NUM_NODES="${NUM_NODES:-1}"
MIN_NODES="${MIN_NODES:-1}"
MAX_NODES="${MAX_NODES:-3}"
DISK_SIZE="${DISK_SIZE:-30}"

echo "==> Checking for existing cluster '${CLUSTER_NAME}' in ${ZONE}..."
if gcloud container clusters describe "${CLUSTER_NAME}" --zone "${ZONE}" >/dev/null 2>&1; then
  echo "    Cluster '${CLUSTER_NAME}' already exists. Nothing to do."
  echo "    Recreate: run scripts/cluster-delete.sh first."
  exit 0
fi

echo "==> Creating cluster '${CLUSTER_NAME}' (Spot, ${MACHINE_TYPE}, ${NUM_NODES} node, autoscale ${MIN_NODES}->${MAX_NODES})..."
# NOTE: --gateway-api=standard enables the GKE Gateway controller
# (networkConfig.gatewayApiConfig.channel = CHANNEL_STANDARD).
gcloud container clusters create "${CLUSTER_NAME}" \
  --zone "${ZONE}" \
  --num-nodes "${NUM_NODES}" \
  --machine-type "${MACHINE_TYPE}" \
  --spot \
  --enable-autoscaling --min-nodes "${MIN_NODES}" --max-nodes "${MAX_NODES}" \
  --disk-size "${DISK_SIZE}" \
  --disk-type pd-standard \
  --gateway-api=standard \

echo "==> Fetching kubectl credentials..."
gcloud container clusters get-credentials "${CLUSTER_NAME}" --zone "${ZONE}"

echo "==> Verifying..."
gcloud container clusters describe "${CLUSTER_NAME}" --zone "${ZONE}" \
  --format="table(name, status, machineType:label=MACHINE, current_node_count:label=NODES, networkConfig.gatewayApiConfig.channel:label=GATEWAY_API)"

echo
echo "==> Nodes (spot label check):"
kubectl get nodes -o wide
echo
echo "==> Spot/preemption labels per node:"
kubectl get nodes -o jsonpath='{range .items[*]}{.metadata.name}{"\t"}{.metadata.labels.cloud\.google\.com/gke-spot}{"\t"}{.metadata.labels.cloud\.google\.com/gke-provisioning}{"\n"}{end}'

echo
echo "Done. Cluster '${CLUSTER_NAME}' is ready."
