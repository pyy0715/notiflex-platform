.PHONY: help cluster-status cluster-creds image-list

# Defaults — override on the CLI, e.g. `make cluster-status ZONE=us-central1-b`
CLUSTER_NAME ?= notiflex
ZONE ?= us-central1-a
IMAGE_NAME ?= notiflex-api
REGISTRY ?= us-central1-docker.pkg.dev/bubbly-subject-501015-t9/containers

help: ## Show available targets
	@grep -E '^[a-zA-Z_-]+:.*?## ' $(MAKEFILE_LIST) | awk 'BEGIN{FS=":.*?## "}{printf "  \033[36m%-18s\033[0m %s\n", $$1, $$2}'

cluster-status: ## Show cluster status, node count, and gateway API channel
	@gcloud container clusters describe $(CLUSTER_NAME) --zone $(ZONE) \
	  --format="table(name, status, machineType:label=MACHINE, current_node_count:label=NODES, networkConfig.gatewayApiConfig.channel:label=GATEWAY_API)" || \
	  echo "Cluster '$(CLUSTER_NAME)' not found in $(ZONE)."

cluster-creds: ## Fetch kubectl credentials for the cluster
	gcloud container clusters get-credentials $(CLUSTER_NAME) --zone $(ZONE)

image-list: ## List images in Artifact Registry
	gcloud artifacts docker images list $(REGISTRY)/$(IMAGE_NAME) --include-tags \
	  --format="table(package:label=IMAGE, tags:label=TAG, version:label=DIGEST, create_time:label=CREATED)"
