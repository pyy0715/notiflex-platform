output "workload_identity_provider" {
  description = "Value for the GCP_WORKLOAD_IDENTITY_PROVIDER GitHub repo variable"
  value       = google_iam_workload_identity_pool_provider.github_provider.name
}

output "service_account_email" {
  description = "Value for the GCP_SERVICE_ACCOUNT GitHub repo variable"
  value       = google_service_account.github_actions_ci.email
}
