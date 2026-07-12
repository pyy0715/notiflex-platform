output "cluster_name" {
  value = google_container_cluster.notiflex.name
}

output "cluster_endpoint" {
  value     = google_container_cluster.notiflex.endpoint
  sensitive = true
}

output "get_credentials_command" {
  description = "Run this after apply to point kubectl at the new cluster"
  value       = "gcloud container clusters get-credentials ${google_container_cluster.notiflex.name} --zone ${var.zone}"
}
