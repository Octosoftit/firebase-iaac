variable "project_id" {
  type        = string
  description = "The id of the created project."
  nullable    = false
}

variable "project_name" {
  type        = string
  description = "The name of the created project"
  nullable    = false
}

variable "location" {
  type        = string
  description = "The location to create the project in"
  default     = "europe-west"
  nullable    = false
}

variable "backup_bucket_location" {
  type        = string
  description = "The location to create the bucket for backups in"
  default     = "europe-west1"
  nullable    = false
}

variable "resource_suffix" {
  type        = string
  description = "The suffix to attach to SA in order to allow quick testing. Empty on production"
  default     = ""
  nullable    = false
}

variable "gcp_sa_access_token" {
  type        = string
  description = "Access token to be used to attach the Firebase strage bucket to firestore"
  default     = ""
  nullable    = false
}
