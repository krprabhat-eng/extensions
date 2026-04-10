locals {
  # Parse source_url to get bucket and archive name
  # Assumes format gs://bucket-name/path/to/archive.zip
  source_parts = split("/", replace(var.source_url, "gs://", ""))
  source_bucket = local.source_parts[0]
  source_archive = join("/", slice(local.source_parts, 1, length(local.source_parts)))

  instance_id = var.extension_id != null ? var.extension_id : "firestore-bigquery-export"

  function_name_fsexportbigquery = var.extension_id != null ? "ext-${var.extension_id}-fsexportbigquery" : "fsexportbigquery"
  function_name_syncBigQuery     = var.extension_id != null ? "ext-${var.extension_id}-syncBigQuery" : "syncBigQuery"
  function_name_initBigQuerySync = var.extension_id != null ? "ext-${var.extension_id}-initBigQuerySync" : "initBigQuerySync"
  function_name_setupBigQuerySync = var.extension_id != null ? "ext-${var.extension_id}-setupBigQuerySync" : "setupBigQuerySync"

  env_vars = {
    DATASET_LOCATION                  = var.dataset_location
    BIGQUERY_PROJECT_ID               = var.bigquery_project_id != null ? var.bigquery_project_id : var.project_id
    DATABASE                         = var.database
    DATABASE_REGION                   = var.database_region
    COLLECTION_PATH                   = var.collection_path
    WILDCARD_IDS                      = tostring(var.wildcard_ids)
    DATASET_ID                        = var.dataset_id
    TABLE_ID                          = var.table_id
    TABLE_PARTITIONING                = var.table_partitioning
    TIME_PARTITIONING_FIELD           = var.time_partitioning_field
    TIME_PARTITIONING_FIRESTORE_FIELD = var.time_partitioning_firestore_field
    TIME_PARTITIONING_FIELD_TYPE      = var.time_partitioning_field_type
    CLUSTERING                        = var.clustering
    MAX_DISPATCHES_PER_SECOND         = tostring(var.max_dispatches_per_second)
    VIEW_TYPE                         = var.view_type
    MAX_STALENESS                     = var.max_staleness
    REFRESH_INTERVAL_MINUTES          = var.refresh_interval_minutes != null ? tostring(var.refresh_interval_minutes) : null
    BACKUP_COLLECTION                 = var.backup_collection
    TRANSFORM_FUNCTION                = var.transform_function
    USE_NEW_SNAPSHOT_QUERY_SYNTAX     = var.use_new_snapshot_query_syntax
    EXCLUDE_OLD_DATA                  = var.exclude_old_data
    KMS_KEY_NAME                      = var.kms_key_name
    MAX_ENQUEUE_ATTEMPTS              = tostring(var.max_enqueue_attempts)
    LOG_LEVEL                         = var.log_level
  }
}

# Cloud Function v2 for fsexportbigquery
resource "google_cloudfunctions2_function" "fsexportbigquery" {
  name        = local.function_name_fsexportbigquery
  location    = var.database_region
  project     = var.project_id

  build_config {
    runtime     = "nodejs22"
    entry_point = "fsexportbigquery"
    source {
      storage_source {
        bucket = local.source_bucket
        object = local.source_archive
      }
    }
  }

  service_config {
    max_instance_count = 100
    available_memory   = "256M"
    environment_variables = local.env_vars
  }

  event_trigger {
    trigger_region        = var.database_region
    event_type            = "google.cloud.firestore.document.v1.written"
    retry_policy          = "RETRY_POLICY_RETRY"
    
    event_filters {
      attribute = "database"
      value     = var.database
    }
    event_filters {
      attribute = "document"
      value     = "${var.collection_path}/{documentId}"
      operator  = "match-path-pattern"
    }
  }
}

# Cloud Tasks Queues for task-triggered functions
resource "google_cloud_tasks_queue" "syncBigQuery" {
  name     = "${local.instance_id}-syncBigQuery"
  project  = var.project_id
  location = var.database_region

  rate_limits {
    max_concurrent_dispatches = 500
    max_dispatches_per_second = var.max_dispatches_per_second
  }

  retry_config {
    max_attempts = 5
    min_backoff  = "60s"
  }
}

resource "google_cloud_tasks_queue" "initBigQuerySync" {
  name     = "${local.instance_id}-initBigQuerySync"
  project  = var.project_id
  location = var.database_region

  retry_config {
    max_attempts = 15
    min_backoff  = "60s"
  }
}

resource "google_cloud_tasks_queue" "setupBigQuerySync" {
  name     = "${local.instance_id}-setupBigQuerySync"
  project  = var.project_id
  location = var.database_region

  retry_config {
    max_attempts = 15
    min_backoff  = "60s"
  }
}

# Cloud Functions v1 for task-triggered functions
resource "google_cloudfunctions_function" "syncBigQuery" {
  name        = local.function_name_syncBigQuery
  runtime     = "nodejs22"
  project     = var.project_id
  region      = var.database_region
  ingress_settings = "ALLOW_INTERNAL_AND_GCLB"

  source_archive_bucket = local.source_bucket
  source_archive_object = local.source_archive

  entry_point = "syncBigQuery"
  trigger_http = true

  environment_variables = local.env_vars
}

resource "google_cloudfunctions_function" "initBigQuerySync" {
  name        = local.function_name_initBigQuerySync
  runtime     = "nodejs22"
  project     = var.project_id
  region      = var.database_region
  ingress_settings = "ALLOW_INTERNAL_AND_GCLB"

  source_archive_bucket = local.source_bucket
  source_archive_object = local.source_archive

  entry_point = "initBigQuerySync"
  trigger_http = true

  environment_variables = local.env_vars
}

resource "google_cloudfunctions_function" "setupBigQuerySync" {
  name        = local.function_name_setupBigQuerySync
  runtime     = "nodejs22"
  project     = var.project_id
  region      = var.database_region
  ingress_settings = "ALLOW_INTERNAL_AND_GCLB"

  source_archive_bucket = local.source_bucket
  source_archive_object = local.source_archive

  entry_point = "setupBigQuerySync"
  trigger_http = true

  environment_variables = local.env_vars
}
