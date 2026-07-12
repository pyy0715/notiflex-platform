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

# Spot, e2-medium, autoscaling 1->3, Gateway API (standard channel), zonal.
resource "google_container_cluster" "notiflex" {
  name     = var.cluster_name
  project  = var.project_id
  location = var.zone

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
