# ====================================================== #
#   Section: Creating the Firebase project & WebApp
# ====================================================== #
resource "google_firebase_project" "default" {
  provider = google-beta.service-account
  project  = var.project_id

}

resource "google_firebase_web_app" "app" {
  provider     = google-beta.service-account
  project      = var.project_id
  display_name = var.project_name
  depends_on = [
    google_firebase_project.default
  ]
}

data "google_firebase_web_app_config" "app" {
  provider   = google-beta.service-account
  web_app_id = google_firebase_web_app.app.app_id
}

resource "google_app_engine_application" "app" {
  provider      = google-beta.service-account
  project       = var.project_id
  location_id   = var.location
  database_type = "CLOUD_FIRESTORE"
}

# ====================================================== #
#   Section: Creating the Firebase SA and relative roles
# ====================================================== #
resource "google_service_account" "admin_sdk" {
  provider     = google-beta.gcloud-user
  project      = var.project_id
  account_id   = length(var.resource_suffix) > 0 ? "firebase-adminsdk-${var.resource_suffix}" : "firebase-adminsdk"
  display_name = "firebase-adminsdk"
}

resource "google_project_iam_member" "admin-sdk-token-creator" {
  provider = google-beta.gcloud-user
  project  = var.project_id
  role     = "roles/iam.serviceAccountTokenCreator"
  member   = "serviceAccount:${google_service_account.admin_sdk.email}"
}

resource "google_project_iam_member" "admin-sdk-agent" {
  provider = google-beta.gcloud-user
  project  = var.project_id
  role     = "roles/firebase.sdkAdminServiceAgent"
  member   = "serviceAccount:${google_service_account.admin_sdk.email}"
}

resource "google_service_account_key" "admin_sdk" {
  provider           = google-beta.gcloud-user
  service_account_id = google_service_account.admin_sdk.id
  # Wait for the account being added to roles
  depends_on = [
    google_project_iam_member.admin-sdk-token-creator,
    google_project_iam_member.admin-sdk-agent,
  ]
}

# ====================================================== #
#   Section: Creating the Firebase Storage Backup and 
#            activate the storage bucket to Firestore
# ====================================================== #
resource "google_storage_bucket" "backup" {
  provider = google-beta.service-account
  project  = var.project_id
  name     = "${var.project_id}-backup"
  location = var.backup_bucket_location
}

locals {
  #   firestore_access_token = data.google_service_account_access_token.default.access_token
  firestore_access_token = var.gcp_sa_access_token
  firestore_bucket_name  = data.google_firebase_web_app_config.app.storage_bucket
  activation_url         = "https://firebasestorage.googleapis.com/v1beta/projects/${var.project_id}/buckets/${local.firestore_bucket_name}:addFirebase"
}
resource "null_resource" "activate_storage" {
  triggers = {
    bucket = local.firestore_bucket_name
  }
  provisioner "local-exec" {
    command     = "curl -X POST -H 'Authorization: Bearer ${nonsensitive(local.firestore_access_token)}' -H 'Content-Type: application/json' '${local.activation_url}'"
    interpreter = ["sh", "-c"]
  }
  depends_on = [
    google_firebase_web_app.app
  ]
}
