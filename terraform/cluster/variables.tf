variable "project_id" {
  description = "GCP project ID"
  type        = string
  default     = "bubbly-subject-501015-t9"
}

variable "zone" {
  description = "GKE cluster zone"
  type        = string
  default     = "us-central1-a"
}

variable "cluster_name" {
  description = "GKE cluster name"
  type        = string
  default     = "notiflex"
}

variable "machine_type" {
  description = "Node machine type"
  type        = string
  default     = "e2-medium"
}

variable "num_nodes" {
  description = "Initial node count"
  type        = number
  default     = 1
}

variable "min_nodes" {
  description = "Autoscaler minimum node count"
  type        = number
  default     = 1
}

variable "max_nodes" {
  description = "Autoscaler maximum node count"
  type        = number
  default     = 3
}

variable "disk_size_gb" {
  description = "Node boot disk size in GB"
  type        = number
  default     = 30
}

variable "argocd_chart_version" {
  description = "argo/argo-cd Helm chart version"
  type        = string
  default     = "10.1.3"
}

variable "argocd_namespace" {
  description = "Namespace to install ArgoCD into"
  type        = string
  default     = "argocd"
}
