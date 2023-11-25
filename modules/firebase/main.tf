
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
  provider = google-beta.service-account
  #   provider      = google-beta.gcloud-user
  project       = var.project_id
  location_id   = var.location
  database_type = "CLOUD_FIRESTORE"
}

