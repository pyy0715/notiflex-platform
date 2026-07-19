terraform {
  required_version = ">= 1.5"

  required_providers {
    google = {
      source  = "hashicorp/google"
      version = "~> 6.0"
    }
  }
}

provider "google" {
  project = var.project_id
}

# Proxy-only subnet required by the regional external Application Load Balancer
# (gke-l7-regional-external-managed GatewayClass). GKE does NOT create this for
# you — it's a VPC prerequisite. Without it, the Gateway stays Programmed: False.
# default network is auto-mode, which reserves the ENTIRE 10.128.0.0/9 range
# (10.128.0.0 - 10.255.255.255) for its own per-region subnets. Any CIDR inside
# 10.128.0.0/9 is rejected with "cannot overlap with 10.128.0.0/9". So we pick a
# /23 in 10.0.0.0/8 but well outside that reserved block: 10.0.0.0/23.
resource "google_compute_subnetwork" "proxy_only" {
  name          = "notiflex-proxy-only"
  project       = var.project_id
  region        = "us-central1"
  network       = "https://www.googleapis.com/compute/v1/projects/${var.project_id}/global/networks/default"
  ip_cidr_range = "10.0.0.0/23"
  purpose       = "REGIONAL_MANAGED_PROXY"
  role          = "ACTIVE"
}

# Spot, e2-medium, autoscaling 1->3, Gateway API (standard channel), zonal.
resource "google_container_cluster" "notiflex" {
  name     = var.cluster_name
  project  = var.project_id
  location = var.zone

  # This cluster is ephemeral by design (see CLAUDE.md) — torn down and
  # rebuilt often. The provider's deletion_protection defaults to true,
  # which blocks terraform destroy; disable it explicitly.
  deletion_protection = false

  # Node pool is managed separately below so it can be resized/upgraded
  # independently of the cluster control plane.
  remove_default_node_pool = true
  initial_node_count       = 1

  gateway_api_config {
    channel = "CHANNEL_STANDARD"
  }
}

resource "google_container_node_pool" "primary" {
  name     = "default-pool"
  project  = var.project_id
  location = var.zone
  cluster  = google_container_cluster.notiflex.name

  initial_node_count = var.num_nodes

  autoscaling {
    min_node_count = var.min_nodes
    max_node_count = var.max_nodes
  }

  node_config {
    machine_type = var.machine_type
    disk_size_gb = var.disk_size_gb
    disk_type    = "pd-standard"
    spot         = true

    oauth_scopes = [
      "https://www.googleapis.com/auth/cloud-platform",
    ]
  }
}
