terraform {
  required_providers {
    google = {
      source = "hashicorp/google"
    }
    kubernetes = {
      source = "hashicorp/kubernetes"
    }
    helm = {
      source = "hashicorp/helm"
    }
  }
}

variable "project" {
  description = "GCP project ID"
  type = string
}

variable "region" {
  description = "GCP region"
  type = string
  default = "us-central1"
}

variable "source_endpoint" {
  description = "Source ES/OS endpoint"
  type = string
}

variable "target_endpoint" {
  description = "Target OS endpoint"
  type = string
}

provider "google" {
  project = var.project
  region  = var.region
}

resource "google_container_cluster" "migration" {
  name     = "migration-cluster-${var.project}"
  location = var.region

  initial_node_count = 3
  node_config {
    machine_type = "e2-standard-4"
    oauth_scopes = [
      "https://www.googleapis.com/auth/cloud-platform",
    ]
    service_account = google_service_account.migration_node.email
  }

  workload_identity_config {
    workload_pool = "${var.project}.svc.id.goog"
  }

  deletion_protection = false
}

resource "google_container_node_pool" "migration_workloads" {
  name       = "migration-workload-pool"
  cluster    = google_container_cluster.migration.name
  location   = var.region
  node_count = 2

  node_config {
    machine_type = "e2-standard-8"
    oauth_scopes = ["https://www.googleapis.com/auth/cloud-platform"]
    service_account = google_service_account.migration_node.email
  }
}

resource "google_compute_network" "migration_vpc" {
  name                    = "migration-vpc-${var.project}"
  auto_create_subnetworks = true
}

resource "google_compute_firewall" "migration_ingress" {
  name    = "migration-ingress"
  network = google_compute_network.migration_vpc.name

  allow {
    protocol = "tcp"
    ports    = ["443", "9200", "9300"]
  }

  source_ranges = ["0.0.0.0/0"]
  target_tags   = ["migration"]
}

resource "google_service_account" "migration_node" {
  account_id   = "migration-node-sa"
  display_name = "Migration Node Service Account"
}

resource "google_storage_bucket" "migration_snapshots" {
  name     = "migration-snapshots-${var.project}"
  location = var.region
  force_destroy = true
}

resource "google_service_account_iam_member" "migration_k8s_wi" {
  service_account_id = google_service_account.migration_node.name
  role               = "roles/iam.serviceAccountUser"
  member             = "serviceAccount:${var.project}.svc.id.goog[migration/migrations-service-account]"
}

resource "google_project_iam_member" "migration_storage_access" {
  project = var.project
  role    = "roles/storage.objectAdmin"
  member  = "serviceAccount:${google_service_account.migration_node.email}"
}

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
  value = "gcloud container clusters get-credentials ${google_container_cluster.migration.name} --region ${var.region} --project ${var.project}"
}
