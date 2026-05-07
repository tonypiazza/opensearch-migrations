output "cluster_name" {
  value = google_container_cluster.migration.name
}

output "cluster_endpoint" {
  value = google_container_cluster.migration.endpoint
}

output "bucket_name" {
  value = google_storage_bucket.migration_snapshots.name
}

output "kubeconfig_command" {
  description = "Run this to get kubectl access"
  value = "gcloud container clusters get-credentials ${google_container_cluster.migration.name} --region ${var.region} --project ${var.project}"
}
