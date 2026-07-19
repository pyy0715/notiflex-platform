variable "project_id" {
  description = "GCP project ID"
  type        = string
  default     = "bubbly-subject-501015-t9"
}

variable "github_repo" {
  description = "GitHub repo allowed to assume the CI service account, as owner/name"
  type        = string
  default     = "pyy0715/notiflex-platform"
}

variable "artifact_registry_location" {
  description = "Location of the Artifact Registry repository"
  type        = string
  default     = "us-central1"
}

variable "artifact_registry_repository" {
  description = "Artifact Registry repository name"
  type        = string
  default     = "containers"
}
