output "app" {
  value = google_firebase_web_app.app
}

output "app_config" {
  value = data.google_firebase_web_app_config.app
}

output "app_backup_bucket" {
  value = google_storage_bucket.backup
}

output "admin_sdk_account_key" {
  value = google_service_account_key.admin_sdk
}
