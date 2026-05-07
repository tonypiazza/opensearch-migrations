{{- define "migration.gcsFunctions" -}}
  get_gcs_endpoint_flag() {
    if [ -n "${GCS_ENDPOINT_URL}" ]; then
      echo "--endpoint-url=$GCS_ENDPOINT_URL"
    else
      echo ""
    fi
  }

  check_gcs_available() {
    gcloud storage buckets list --limit=1 > /dev/null 2>&1
  }

  bucket_exists() {
    local bucket="$1"
    gcloud storage buckets describe "gs://$bucket" > /dev/null 2>&1
  }
{{- end }}
