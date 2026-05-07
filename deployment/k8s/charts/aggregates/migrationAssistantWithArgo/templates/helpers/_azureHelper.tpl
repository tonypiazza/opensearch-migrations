{{- define "migration.azureFunctions" -}}
  check_azure_available() {
    az storage blob service-properties show --account-name "$AZURE_STORAGE_ACCOUNT" > /dev/null 2>&1
  }

  container_exists() {
    local container="$1"
    az storage container exists --name "$container" --account-name "$AZURE_STORAGE_ACCOUNT" --auth-mode login > /dev/null 2>&1
  }
{{- end }}
